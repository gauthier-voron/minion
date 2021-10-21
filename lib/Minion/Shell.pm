package Minion::Shell;

use parent qw(Minion::Worker);
use strict;
use warnings;

use Carp qw(confess);
use Cwd;
use Scalar::Util qw(blessed);

use Minion::Io::Util qw(output_function);
use Minion::System::Process;
use Minion::Worker;


sub _init
{
    my ($self, %opts) = @_;
    my ($value);

    if (defined($value = $opts{HOME})) {
	confess() if (ref($value) ne '');
	$self->{__PACKAGE__()}->{_home} = $value;
	delete($opts{HOME});
    }

    if (defined($value = $opts{ERR})) {
	if ((ref($value) ne 'GLOB') &&
	    !(blessed($value) && $value->can('printf'))) {
	    $value = output_function($value);
	    confess() if (!defined($value));
	}
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$value = output_function($value);
	confess() if (!defined($value));
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    return $self->SUPER::_init(ALIASES => {
	'shell:home' => sub { return $self->home(); }
    });
}


sub home
{
    my ($self, @err) = @_;
    my ($ret);

    confess() if (@err);

    $ret = $self->{__PACKAGE__()}->{_home};

    if (defined($ret)) {
	return $ret;
    }

    return getcwd();
}

sub _log
{
    my ($self, $msg) = @_;
    my ($log);

    $log = $self->{__PACKAGE__()}->{_log};

    if (!defined($log)) {
	return 0;
    }

    $log->($msg . "\n");

    return 1;
}


sub execute
{
    my ($self, $cmd, %opts) = @_;
    my (%popts, $opt, $value, $sshcmd, $home);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$cmd);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$popts{STDERR} = $value;
    }

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

    $home = $self->{__PACKAGE__()}->{_home};

    $self->_log(join(' ', @$cmd));

    if (defined($home)) {
	return Minion::System::Process->new(sub {
	    if (!chdir($home)) {
		printf(STDERR "cannot change directory to '%s' : %s\n",
		       $home, $!);
		exit (1);
	    }
	    exec (@$cmd);
	}, %popts);
    } else {
	return Minion::System::Process->new($cmd, %popts);
    }
}

sub send
{
    my ($self, $sources, %opts) = @_;
    my ($value, $target, $cmd, %popts);

    confess() if (!defined($sources));
    confess() if (ref($sources) ne 'ARRAY');
    confess() if (scalar(@$sources) < 1);
    confess() if (grep { ref($_) ne '' } @$sources);

    $target = $self->{__PACKAGE__()}->{_home};

    if (!defined($target)) {
	$target = '.';
    }

    if (defined($value = $opts{TARGET})) {
	$target .= '/' . $value;
	delete($opts{TARGET});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$popts{STDERR} = $value;
    }

    $cmd = [ 'cp', '-R', @$sources, $target ];

    $self->_log(join(' ', @$cmd));

    return Minion::System::Process->new($cmd, %popts);
}

sub recv
{
    my ($self, $sources, %opts) = @_;
    my ($value, @srcs, $target, $cmd, %popts);

    confess() if (!defined($sources));
    confess() if (ref($sources) ne 'ARRAY');
    confess() if (scalar(@$sources) < 1);
    confess() if (grep { ref($_) ne '' } @$sources);

    @srcs = @$sources;

    if (defined($value = $self->{__PACKAGE__()}->{_home})) {
	@srcs = map { $value . '/' . $_ } @srcs;
    }

    if (defined($target = $opts{TARGET})) {
	delete($opts{TARGET});
    } else {
	$target = '.';
    }

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$popts{STDERR} = $value;
    }

    $cmd = [ 'cp', '-R', @srcs, $target ];

    $self->_log(join(' ', @$cmd));

    return Minion::System::Process->new($cmd, %popts);
}


sub serialize
{
    my ($self, $fh, @err) = @_;
    my ($home);

    confess() if (@err);
    confess() if (!defined($fh));

    $home = $self->{__PACKAGE__()}->{_home};

    Minion::Serializable->serialize($fh, $home);

    return 1;
}

sub deserialize
{
    my ($class, $fh, @err) = @_;
    my ($home, %opts);

    confess() if (@err);
    confess() if (!defined($fh));

    if (!Minion::Serializable->deserialize($fh, \$home)) {
	return undef;
    }

    if (defined($home)) {
	$opts{HOME} = $home;
    }

    return __PACKAGE__()->new(%opts);
}


1;
__END__
