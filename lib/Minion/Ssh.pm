package Minion::Ssh;

use parent qw(Minion::Worker);
use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);

use Minion::Io::Util qw(output_function);
use Minion::System::Process;
use Minion::Worker;


sub _init
{
    my ($self, $addr, %opts) = @_;
    my (@sshcmd, @scpcmd, $value, $port, $logcode, %aliases, $ctrlpath);

    confess() if (!defined($addr));
    confess() if (ref($addr) ne '');

    $self->{__PACKAGE__()}->{_host} = $addr;

    if (defined($value = $opts{ALIASES})) {
	confess() if (ref($value) ne 'HASH');
	%aliases = %$value;
	delete($opts{ALIASES});
    }

    if (defined($value = $opts{ERR})) {
	if ((ref($value) ne 'GLOB') &&
	    !(blessed($value) && $value->can('printf'))) {
	    $value = output_function($value);
	    confess() if (!defined($value));
	}
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    } else {
	$self->{__PACKAGE__()}->{_err} = \*STDERR;
    }

    if (defined($value = $opts{LOG})) {
	$value = output_function($value);
	confess() if (!defined($value));
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    } else {
	$self->{__PACKAGE__()}->{_log} = sub {};
    }

    if (defined($port = $opts{PORT})) {
	confess() if (!($port =~ /^\d+$/));
	confess() if ($port > 65535);
	delete($opts{PORT});
    } else {
	$port = 22;
    }

    $self->{__PACKAGE__()}->{_port} = $port;

    if (defined($value = $opts{USER})) {
	$addr = $value . '@' . $addr;
	$self->{__PACKAGE__()}->{_user} = $value;
	delete($opts{USER});
    }

    @sshcmd = ( 'ssh' , '-T' , '-o' , 'StrictHostKeyChecking=no' , '-o'
	      , 'UserKnownHostsFile=/dev/null' , '-o' , 'LogLevel=ERROR'
	      , '-o', 'ControlMaster=auto', '-o', 'ControlPersist=60',
	      , '-o', 'ControlPath=/tmp/minion-ssh.' . $addr . ':' . $port .
		'.sock'
	      , '-p' , $port , $addr );
    @scpcmd = ( 'scp' , '-q' , '-o' , 'StrictHostKeyChecking=no' , '-o'
	      , 'UserKnownHostsFile=/dev/null' , '-o' , 'LogLevel=ERROR'
	      , '-o', 'ControlMaster=auto', '-o', 'ControlPersist=60',
	      , '-o', 'ControlPath=/tmp/minion-ssh.' . $addr . ':' . $port .
		'.sock'
	      , '-r', '-C', '-P', $port, $addr );

    $self->{__PACKAGE__()}->{_scpcmd} = \@scpcmd;
    $self->{__PACKAGE__()}->{_sshcmd} = \@sshcmd;

    return $self->SUPER::_init(ALIASES => {
	'ssh:host' => sub { return $self->host(); },
	'ssh:port' => sub { return $self->port(); },
	'ssh:user' => sub { return $self->user(); },
	%aliases
	});
}


sub _log
{
    my ($self, $msg) = @_;

    $self->{__PACKAGE__()}->{_log}->(sprintf("%s\n", $msg));

    return 1;
}


sub host
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_host};
}

sub port
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_port};
}

sub user
{
    my ($self, @err) = @_;
    my ($ret);

    confess() if (@err);

    $ret = $self->{__PACKAGE__()}->{_user};

    if (!defined($ret)) {
	$ret = $ENV{USER};
    }

    return $ret;
}


sub __protect
{
    my (@words) = @_;
    my (@ret, $word);

    foreach $word (@words) {
	$word =~ s/'/\\'/g;
	$word = "'$word'";

	push(@ret, $word);
    }

    return @ret;
}

sub execute
{
    my ($self, $cmd, %opts) = @_;
    my (%popts, $opt, $value, $sshcmd, $ecmd);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$cmd);

    foreach $opt (qw(STDIN STDOUT STDERR)) {
	if (defined($value = $opts{$opt})) {
	    $popts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    if (!defined($popts{STDIN})) {
	$popts{STDIN} = '/dev/null';
    }

    $sshcmd = $self->{__PACKAGE__()}->{_sshcmd};
    $ecmd = [ @$sshcmd, __protect(@$cmd) ];

    $self->_log(join(' ', @$ecmd));

    return Minion::System::Process->new($ecmd, %popts);
}

sub send
{
    my ($self, $sources, %opts) = @_;
    my (%popts, @scpcmd, $addr, $value, $proc);

    confess() if (!defined($sources));
    confess() if (ref($sources) ne 'ARRAY');
    confess() if (!grep { ref($_) eq '' } @$sources);

    @scpcmd = @{$self->{__PACKAGE__()}->{_scpcmd}};
    $addr = pop(@scpcmd);
    push(@scpcmd, @$sources);

    if (defined($value = $opts{TARGET})) {
	confess() if (ref($value) ne '');
	push(@scpcmd, $addr . ':' . $value);
	delete($opts{TARGET});
    } else {
	push(@scpcmd, $addr . ':');
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $self->_log(join(' ', @scpcmd));

    return Minion::System::Process->new(
	\@scpcmd,
	STDERR => $self->{__PACKAGE__()}->{_err}
	);
}

sub recv
{
    my ($self, $sources, %opts) = @_;
    my (%popts, @scpcmd, $addr, $value, $proc);

    confess() if (!defined($sources));
    confess() if (ref($sources) ne 'ARRAY');
    confess() if (!grep { ref($_) eq '' } @$sources);

    @scpcmd = @{$self->{__PACKAGE__()}->{_scpcmd}};
    $addr = pop(@scpcmd);
    push(@scpcmd, map { $addr . ':' . $_ } @$sources);

    if (defined($value = $opts{TARGET})) {
	confess() if (ref($value) ne '');
	push(@scpcmd, $value);
	delete($opts{TARGET});
    } else {
	push(@scpcmd, '.');
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $self->_log(join(' ', @scpcmd));

    return Minion::System::Process->new(
	\@scpcmd,
	STDERR => $self->{__PACKAGE__()}->{_err}
	);
}


1;
__END__
