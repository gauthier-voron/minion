package Minion::Run::Runner;

use strict;
use warnings;

use Carp qw(confess);
use File::Temp;

use Minion::Fleet;
use Minion::Io::Util qw(output_function);
use Minion::StaticFleet;
use Minion::System::Pgroup;
use Minion::System::Process;
use Minion::Worker;


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, %opts) = @_;
    my ($value);

    if (defined($value = $opts{ERR})) {
	$value = output_function($value);
	confess() if (!defined($value));
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOCAL})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ref($_) ne '' } @$value);
	$self->{__PACKAGE__()}->{_locals} = [ @$value ];
	delete($opts{LOCAL});
    }

    if (defined($value = $opts{LOG})) {
	$value = output_function($value);
	confess() if (!defined($value));
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    }

    if (defined($value = $opts{REMOTE})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ref($_) ne '' } @$value);
	$self->{__PACKAGE__()}->{_remotes} = [ @$value ];
	delete($opts{REMOTE});
    }

    if (defined($value = $opts{SHARED})) {
	confess() if (ref($value) ne '');
	$self->{__PACKAGE__()}->{_shared} = $value;
	delete($opts{SHARED});
    } else {
	$self->{__PACKAGE__()}->{_shared} = File::Temp->newdir
	    ('minion.XXXXXX', SUFFIX => '.d');
    }

    confess(join(' ', keys(%opts))) if (%opts);

    return $self;
}


sub _err
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_err};
}

sub _log
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_log};
}


sub _print_err
{
    my ($self, $msg) = @_;
    my ($err);

    $err = $self->_err();

    if (defined($err)) {
	$err->($msg);
    } else {
	printf(STDERR "%s\n", $msg);
    }
}

sub _print_log
{
    my ($self, $msg) = @_;
    my ($log);

    $log = $self->_log();

    if (defined($log)) {
	$log->($msg);
    }
}


sub resolve_local
{
    my ($self, $name, @err) = @_;
    my ($root, $path, $epath);

    confess() if (@err);
    confess() if (!defined($name));
    confess() if (ref($name) ne '');

    foreach $root (@{$self->{__PACKAGE__()}->{_locals}}) {
	$path = $root . '/' . $name;

	# TODO
	# if ((-f $path) && (-r $path) && (-x $path)) {
	#     return $path;
	# }

	$epath = $path . '.pm';
	if ((-f $epath) && (-r $epath)) {
	    return $epath;
	}
    }

    return undef;
}

sub _run_local
{
    my ($self, $fleet, $path, $args, %opts) = @_;
    my ($proc, $dir);

    $proc = Minion::System::Process->new(sub {
	$dir = File::Temp->newdir
	    ('minion.XXXXXX', SUFFIX => '.d');

	$_ = $fleet;
	@_ = (
	    FLEET  => $fleet,
	    RUNNER => $self
	    );
	@ARGV = @$args;
	$ENV{MINION_SHARED} = $self->{__PACKAGE__()}->{_shared};
	$ENV{MINION_PRIVATE} = $dir;

	require $path;
    }, %opts);

    return $proc;
}

sub resolve_remote
{
    my ($self, $name, $system, @err) = @_;
    my ($path, $root);

    confess() if (@err);
    confess() if (!defined($name));
    confess() if (ref($name) ne '');
    confess() if (!defined($system));
    confess() if (ref($system) ne '');

    while (1) {
	foreach $root (@{$self->{__PACKAGE__()}->{_remotes}}) {
	    if ($system ne '') {
		$path = $root . '/' . $system . '/' . $name;
	    } else {
		$path = $root . '/' . $name;
	    }

	    if ((-f $path) && (-r $path) && (-x $path)) {
		return $path;
	    }
	}

	if ($system eq '') {
	    last;
	} elsif ($system =~ m|^(.*)/[^/]*$|) {
	    $system = $1;
	} else {
	    $system = '';
	}
    }

    return undef;
}

sub _run_remote
{
    my ($self, $fleet, $paths, $args, %opts) = @_;
    my ($worker, $system, $path, @procs, $proc, @ws, @ews, %popts, $opt, $val);

    foreach $opt (qw(STDIN STDOUT STDERR)) {
	if (defined($val = $opts{$opt . 'S'})) {
	    if (ref($val) eq 'ARRAY') {
		confess('not yet implemented');
	    } else {
		$popts{$opt} = $val;
		delete($opts{$opt . 'S'});
	    }
	}
    }

    return Minion::System::Process->new(sub {
	foreach $worker ($fleet->members()) {
	    $system = $worker->get('run:system');
	    $path = $paths->{$system};
	    $proc = $worker->send([$path], TARGET => '.minion-task');
	    push(@procs, $proc);
	}

	@ws = Minion::System::Pgroup->new(\@procs)->waitall();
	if (grep { $_->exitstatus() != 0 } @ws) {
	    exit (1);
	}

	@ews = $fleet->execute(['./.minion-task', @$args])->waitall();

	@ws = $fleet->execute(['rm', '.minion-task'])->waitall();
	if (grep { $_->exitstatus() != 0 } @ws) {
	    exit (1);
	}

	if (grep { $_->exitstatus() != 0 } @ews) {
	    exit (1);
	}
    }, %opts);
}

sub _run_detect_systems
{
    my ($self, $fleet) = @_;
    my ($name, $path, $size, $worker, @status);
    my (%eopts, $err, $out, @outs);

    $name = 'detect-system';

    $path = $self->resolve_remote($name, '');

    if (!defined($path)) {
	$self->_print_err("cannot resolve remote script '$name'");
	return 0;
    }

    $size = scalar($fleet->members());

    $self->_print_log("detect system for $size workers with '$path'");


    @status = $fleet->send([$path], TARGETS => '.minion-task')->waitall();
    if (grep { $_->exitstatus() != 0 } @status) {
	$self->_print_err("cannot send '$path' to workers");
	return 0;
    }


    @outs = ('') x $size;

    if (defined($err = $self->_err())) {
	$eopts{STDERRS} = $err;
    }

    @status = $fleet->execute(
	['./.minion-task'],
	STDOUTS => [ map { \$_ } @outs ],
	%eopts
	)->waitall();

    if (grep { $_->exitstatus() != 0 } @status) {
	$self->_print_err("cannot execute '$path' on workers");
	return 0;
    }


    $fleet->execute(['rm', '.minion-task'], %eopts)->waitall();


    foreach $worker ($fleet->members()) {
	$out = shift(@outs);
	chomp($out);
	$worker->set('run:system', $out);
    }


    return 1;
}

sub _detect_systems
{
    my ($self, $fleet) = @_;
    my ($worker, $system, @detects, %systems);

    foreach $worker ($fleet->members()) {
	$system = $worker->get('run:system');

	if (!defined($system)) {
	    push(@detects, $worker);
	    next;
	}

	push(@{$systems{$system}}, $worker);
    }

    if (scalar(@detects) > 0) {
	if (!$self->_run_detect_systems(Minion::StaticFleet->new(\@detects))) {
	    return undef;
	}

        foreach $worker (@detects) {
	    $system = $worker->get('run:system');

	    if (!defined($system)) {
		confess();
	    }

	    push(@{$systems{$system}}, $worker);
	}
    }

    return \%systems;
}

sub resolve
{
    my ($self, $workers, $cmd) = @_;
    my ($fleet, $systems, $name, $worker, $system, $path, @paths);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (scalar(@$cmd) < 1);
    confess() if (grep { ref($_) ne '' } @$cmd);
    confess() if (ref($workers) ne 'ARRAY');
    confess() if (grep { !Minion::Worker->comply($_) } @$workers);

    $fleet = Minion::StaticFleet->new($workers);

    $systems = $self->_detect_systems($fleet);

    if (!defined($systems)) {
	return undef;
    }

    $name = $cmd->[0];

    foreach $worker (@$workers) {
	$system = $worker->get('run:system');
	$path = $self->resolve_remote($name, $system);

	if (!defined($path)) {
	    return undef;
	}

	push(@paths, $path);
    }

    return \@paths;
}

sub run
{
    my ($self, $fleet, $cmd, %opts) = @_;
    my ($name, @args, $path, $system, $systems, %paths);
    my (%lopts, %ropts, $opt, $value);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (scalar(@$cmd) < 1);
    confess() if (grep { ref($_) ne '' } @$cmd);
    confess() if (!defined($fleet));

    if (!Minion::Fleet->comply($fleet)) {
	if (Minion::Worker->comply($fleet)) {
	    $fleet = Minion::StaticFleet->new([ $fleet ]);
	} elsif ((ref($fleet) eq 'ARRAY') &&
		 !grep { !Minion::Worker->comply($_) } @$fleet) {
	    $fleet = Minion::StaticFleet->new($fleet);
	}
    }

    confess() if (!Minion::Fleet->comply($fleet));

    foreach $opt (qw(STDIN STDOUT STDERR)) {
	if (defined($value = $opts{$opt})) {
	    $lopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    foreach $opt (qw(STDINS STDOUTS STDERRS)) {
	if (defined($value = $opts{$opt})) {
	    $ropts{substr($opt, 0, -1)} = $value;
	    delete($opts{$opt});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    ($name, @args) = @$cmd;
    $path = $self->resolve_local($name);

    $systems = $self->_detect_systems($fleet);

    if (defined($path)) {
	$self->_print_log("resolve '$name' as local '$path'");
	return $self->_run_local($fleet, $path, \@args, %lopts);
    }

    if (!defined($systems)) {
	return 0;
    }

    foreach $system (keys(%$systems)) {
	$path = $self->resolve_remote($name, $system);

	if (!defined($path)) {
	    $self->_print_err("cannot resolve '$name' for system '$system'");
	    return 0;
	}

	$self->_print_log("resolve '$name' as remote '$path' for system ".
			  "'$system'");
	$paths{$system} = $path;
    }

    return $self->_run_remote($fleet, \%paths, \@args, %ropts);
}


1;
__END__

