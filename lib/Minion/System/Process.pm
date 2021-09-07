package Minion::System::Process;

use strict;
use warnings;

use Carp qw(confess);
use IO::Handle;
use IO::Select;
use POSIX ":sys_wait_h";
use Scalar::Util qw(blessed);
use Time::HiRes;

use Minion::Io::Handle;
use Minion::System::ReactItem;


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $routine, %opts) = @_;
    my ($ref);

    confess() if (!defined($routine));

    if (ref($routine) eq 'CODE') {
	return $self->_forkto($routine, %opts);
    }

    if (ref($routine) eq 'ARRAY') {
	return $self->_forkexec($routine, %opts);
    }

    confess();
}


sub _add_react
{
    my ($self, $fh, $code, $selset) = @_;
    my ($handle, $ritem, $fileno);

    $handle = Minion::Io::Handle->new($fh);
    $handle->autoflush(1);
    $handle->blocking(0);

    $ritem = Minion::System::ReactItem->new($handle, $code);
    $fileno = $handle->fileno();

    $selset->add([ $fileno, $ritem ]);
}

sub _add_react_input
{
    my ($self, $fh, $code) = @_;

    return $self->_add_react($fh, $code, $self->{__PACKAGE__()}->{_selin});
}

sub _add_react_output
{
    my ($self, $fh, $code) = @_;

    return $self->_add_react($fh, $code, $self->{__PACKAGE__()}->{_selout});
}

sub _register_assigned
{
    my ($self, $fh) = @_;
    my ($assigned, $fileno);

    $assigned = $self->{__PACKAGE__()}->{_assigned};
    $fileno = fileno($fh);

    confess() if (exists($assigned->{$fileno}));

    $assigned->{$fileno} = 1;
}

sub _create_child_input
{
    my ($self, $parentend) = @_;
    my ($ref, $fh, $tmp, $ph);

    confess() if (!defined($parentend));

    $ref = ref($parentend);

    if ($ref eq '') {
	if (!open($fh, '<', $parentend)) {
	    return undef;
	}

	return [ $fh, sub { } ];
    }

    if (($ref eq 'GLOB') ||
	(blessed($parentend) && $parentend->isa('IO::Handle'))) {

	if (!open($fh, '<&', $parentend)) {
	    return undef;
	}

	return [ $fh, sub { } ];
    }

    if (($ref eq 'SCALAR') && defined($$parentend)) {
	$tmp = $$parentend;
	$parentend = sub { my $ret = $tmp; $tmp = undef; return $ret; };
	$ref = ref($parentend);
    }

    if ($ref eq 'CODE') {
	if (!pipe($fh, $ph)) {
	    return undef;
	}

	$self->_add_react_output($ph, $parentend);

	return [ $fh, sub { close($ph); } ];
    }

    if (($ref eq 'SCALAR') && !defined($$parentend)) {
	if (!pipe($fh, $ph)) {
	    return undef;
	}

	$$parentend = $ph;

	return [ $fh, sub { close($ph); } ];
    }

    confess();
}

sub _create_child_output
{
    my ($self, $parentend) = @_;
    my ($ref, $fh, $tmp, $ph);

    confess() if (!defined($parentend));

    $ref = ref($parentend);

    if ($ref eq '') {
	if (!open($fh, '>>', $parentend)) {
	    return undef;
	}

	return [ $fh, sub { } ];
    }
    
    if (($ref eq 'GLOB') ||
	(blessed($parentend) && $parentend->isa('IO::Handle'))) {

	if (!open($fh, '>&', $parentend)) {
	    return undef;
	}

	return [ $fh, sub { } ];
    }

    if (($ref eq 'SCALAR') && defined($$parentend)) {
	$tmp = $parentend;
	$parentend = sub { $$tmp .= shift() if (@_); };
	$ref = ref($parentend);
    }

    if ($ref eq 'CODE') {
	if (!pipe($ph, $fh)) {
	    return undef;
	}

	$self->_add_react_input($ph, $parentend);

	return [ $fh, sub { close($ph); } ];
    }

    if (($ref eq 'SCALAR') && !defined($$parentend)) {
	if (!pipe($ph, $fh)) {
	    return undef;
	}

	$$parentend = $ph;

	return [ $fh, sub { close($ph); } ];
    }

    confess();
}

sub _add_io
{
    my ($self, $rspec) = @_;
    my ($childend, $op, $parentend);
    my ($childpair, $childfh, $childcs, $childsub);
    my ($parentsub);

    confess() if (!defined($rspec));
    confess() if (ref($rspec) ne 'ARRAY');
    confess() if (scalar(@$rspec) != 3);

    ($childend, $op, $parentend) = @$rspec;

    confess() if (!defined($childend));

    if ($op eq '<') {
	$childpair = $self->_create_child_input($parentend);
    } elsif ($op eq '>') {
	$childpair = $self->_create_child_output($parentend);
    } else {
	confess();
    }

    if (!defined($childpair)) {
	return;
    }

    ($childfh, $childcs) = @$childpair;

    if ((ref($childend) eq 'SCALAR') && !defined($$childend)) {
	$childsub = sub {
	    $childcs->();
	    $$childend = $childfh;
	};
    } elsif ((ref($childend) eq 'GLOB') ||
	     (blessed($childend) && $childend->isa('IO::Handle'))) {
	$self->_register_assigned($childend);
	$childsub = sub {
	    $childcs->();
	    exit(1) if (!open($childend, $op . '&', $childfh));
	    close($childfh);
	};
    } else {
	confess();
    }

    $parentsub = sub { close($childfh); };

    return [ $parentsub, $childsub ];
}


sub _forkto
{
    my ($self, $code, %opts) = @_;
    my ($value, $io, $iosubs, @psubs, @csubs, $iosub, $pid, %aliases, $name);

    $self->{__PACKAGE__()}->{_selin} = IO::Select->new();
    $self->{__PACKAGE__()}->{_selout} = IO::Select->new();
    $self->{__PACKAGE__()}->{_assigned} = {};
    $self->{__PACKAGE__()}->{_io} = [];

    %aliases = (
	STDIN  => [ \*STDIN,  '<' ],
	STDOUT => [ \*STDOUT, '>' ],
	STDERR => [ \*STDERR, '>' ]
	);

    foreach $name (keys(%aliases)) {
	if (defined($value = $opts{$name})) {
	    $iosubs = $self->_add_io([ @{$aliases{$name}}, $value ]);

	    if (!defined($iosubs)) {
		return undef;
	    }

	    push(@psubs, $iosubs->[0]);
	    push(@csubs, $iosubs->[1]);

	    delete($opts{$name});
	}
    }

    if (defined($value = $opts{IO})) {
	confess() if (ref($value) ne 'ARRAY');

	foreach $io (@$value) {
	    $iosubs = $self->_add_io($io);

	    if (!defined($iosubs)) {
		return undef;
	    }

	    push(@psubs, $iosubs->[0]);
	    push(@csubs, $iosubs->[1]);
	}

	delete($opts{IO});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    if (($pid = fork()) == 0) {
	foreach $iosub (@csubs) {
	    $iosub->();
	}

	$code->();
	exit (0);
    }

    foreach $iosub (@psubs) {
	$iosub->();
    }

    $self->{__PACKAGE__()}->{_pid} = $pid;
    $self->{__PACKAGE__()}->{_iosize} = 4096;

    return $self;
}

sub _forkexec
{
    my ($self, $command, %opts) = @_;

    return $self->_forkto(sub {
	exec (@$command);
	exit (1);
    }, %opts);
}


sub pid
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_pid};
}

sub exitstatus
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_exitstatus};
}


sub kill
{
    my ($self, $sig, @err) = @_;

    confess() if (@err);

    if (!defined($sig)) {
	$sig = 'TERM';
    }

    return kill($sig, $self->pid());
}

sub wait
{
    my ($self, @err) = @_;
    my ($ret);

    confess() if (@err);

    $self->_purge_oe();

    waitpid($self->pid(), 0);
    $ret = $?;

    $self->{__PACKAGE__()}->{_exitstatus} = $ret;

    return $ret;
}

sub trywait
{
    my ($self, %opts) = @_;
    my ($ret, $timeout, $now, $end);

    if (defined($timeout = $opts{TIMEOUT})) {
	confess() if (ref($timeout) ne '');
	confess() if ($timeout !~ /^\d+(?:\.\d+)?$/);
	delete($opts{TIMEOUT});
    } else {
	$timeout = 0;
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $now = Time::HiRes::time();
    $end = $now + $timeout;

    while ($now <= $end) {
	$self->tryreact(TIMEOUT => sprintf("%.3f", $end - $now));

	$ret = waitpid($self->pid(), WNOHANG);

	if ($ret == $self->pid()) {
	    last;
	}

	$now = Time::HiRes::time();
    }

    if ($ret != $self->pid()) {
	return undef;
    }

    $ret = $?;

    $self->_purge_oe();

    $self->{__PACKAGE__()}->{_exitstatus} = $ret;

    return $ret;
}


sub __write_buffer_nb
{
    my ($handle, $buffer, $length, $offset) = @_;
    my ($done, $ret);

    $done = 0;

    while ($done < $length) {
	$ret = $handle->syswrite($buffer, $length - $done, $offset + $done);

	if (!defined($ret)) {
	    last;
	}

	if ($ret == 0) {
	    last;
	}

	$done += $ret;
    }

    return $done;
}

sub _do_react_write
{
    my ($self, $ritem) = @_;
    my ($buf, $len, $elen, $off, $cap);

    $cap = $self->{__PACKAGE__()}->{_iosize};
    $buf = $ritem->buffer();
    $off = $ritem->offset();

    if (defined($buf)) {
	$len = length($buf);
	$elen = $len - $off;

	if ($cap < $elen) {
	    $elen = $cap;
	}

	$off += __write_buffer_nb($ritem->handle(), $buf, $elen, $off);

	if ($off < $len) {
	    $ritem->update($buf, $off);
	    return 1;
	}
    }

    while (defined($buf = $ritem->code()->($cap))) {
	$elen = $len = length($buf);

	if ($cap < $elen) {
	    $elen = $cap;
	}

	$off = __write_buffer_nb($ritem->handle(), $buf, $elen, 0);

	if ($off < $len) {
	    $ritem->update($buf, $off);
	    return 1;
	}
    }

    $ritem->update(undef, 0);
    return 0;
}

sub _react_write
{
    my ($self, $ritem) = @_;
    my ($oldsig, $raised, $alive);

    $oldsig = $SIG{PIPE};
    $raised = 0;

    $SIG{PIPE} = sub {
	$raised = 1;
    };

    $alive = $self->_do_react_write($ritem);

    $SIG{PIPE} = $oldsig;

    if ($raised && $ritem->handle()->opened()) {
	$ritem->handle()->close();
	$ritem->update(undef, 0);
    }

    return $alive;
}

sub _react_read
{
    my ($self, $ritem) = @_;
    my ($cap, $buf, $done);

    $cap = $self->{__PACKAGE__()}->{_iosize};

    while (defined($done = $ritem->handle()->sysread($buf, $cap))) {
	if ($done == 0) {
	    $ritem->code()->();
	    return 0;
	}

	$ritem->code()->($buf);
	$buf = undef;
    }

    return 1;
}

sub _react_selected
{
    my ($self, $selected, $selset, $handler) = @_;
    my ($pair, $fileno, $ritem, $alive);

    foreach $pair (@$selected) {
	($fileno, $ritem) = @$pair;
	$alive = $handler->($self, $ritem);

	if (!$alive) {
	    $selset->remove($fileno);
	    $ritem->handle()->close();
	}
    }

    return scalar(@$selected);
}

sub _react
{
    my ($self, $timeout) = @_;
    my ($selin, $selout, @selret, $read, $write, $count);

    $selin = $self->{__PACKAGE__()}->{_selin};
    $selout = $self->{__PACKAGE__()}->{_selout};

    if (($selin->count() + $selout->count()) == 0) {
	return 0;
    }

    @selret = IO::Select->select($selin, $selout, undef, $timeout);

    if (scalar(@selret) == 0) {
	return 0;
    }

    ($read, $write) = @selret;

    $count = 0;
    $count += $self->_react_selected($read, $selin, \&_react_read);
    $count += $self->_react_selected($write, $selout, \&_react_write);

    return $count;
}

sub react
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->_react();
}

sub tryreact
{
    my ($self, %opts) = @_;
    my ($value, $timeout);

    if (defined($value = $opts{TIMEOUT})) {
	confess() if (ref($value) ne '');
	confess() if ($value !~ /^\d+(?:\.\d+)?$/);
	$timeout = $value;
	delete($opts{TIMEOUT});
    } else {
	$timeout = 0;
    }

    confess(join(' ', key(%opts))) if (%opts);

    return $self->_react($timeout);
}

sub _purge_oe
{
    my ($self) = @_;

    while ($self->react() > 0) {
    }
}


1;
__END__
