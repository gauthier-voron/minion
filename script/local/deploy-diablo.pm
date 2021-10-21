package deploy_algorand;

use strict;
use warnings;

use File::Copy;

use Minion::System::Pgroup;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};

my $ACTORS_LIST_PATH = $ENV{MINION_SHARED} . '/diablo-actors';

my $ALGORAND_CHAINCONFIG_PATH = $ENV{MINION_SHARED} . '/algorand-chain.yml';

my $PRIMARYFILE_NAME = 'primary';
my $PRIMARYFILE_PATH = $ENV{MINION_PRIVATE} . '/' . $PRIMARYFILE_NAME;
my $PRIMARYFILE_TCP_PORT = 5000;


sub get_actors
{
    my ($path) = @_;;
    my ($fh, $line, $ip, $role, %actors, $worker, $assigned);

    if (!open($fh, '<', $path)) {
	die ("cannot open '$path' : $!");
    }

    while (defined($line = <$fh>)) {
	chomp($line);
	($ip, $role) = split(':', $line);

	$assigned = undef;

	foreach $worker ($FLEET->members()) {
	    if ($worker->can('public_ip') && ($worker->public_ip() eq $ip)) {
		$assigned = $worker;
		last;
	    } elsif ($worker->can('host') && ($worker->host() eq $ip)) {
		$assigned = $worker;
		last;
	    }
	}

	if (!defined($assigned)) {
	    die ("cannot find worker with ip '$ip' in deployment fleet");
	}

	if (defined($actors{$role}) && defined($actors{$role}->{$ip})) {
	    if ($assigned ne $actors{$role}->{$ip}) {
		die ("two workers have the same ip '$ip' on deployment fleet");
	    }
	}

	$actors{$role}->{$ip} = $assigned;
    }

    close($fh);

    return \%actors;
}

sub build_primaryfile
{
    my ($path, $primary) = @_;
    my ($fh);

    if (!open($fh, '>', $path)) {
	die ("cannot create diablo primaryfile '$path' : $!");
    }

    printf($fh "%s:%d\n", $primary, $PRIMARYFILE_TCP_PORT);

    close($fh);
}


sub deploy_diablo_algorand
{
    my ($primary, $secondaries) = @_;
    my ($chain, $pproc, $sproc, $worker, @procs, $pgrp, $proc);

    $pproc = $RUNNER->run($primary, [ 'deploy-diablo-worker', 'primary' ]);
    $sproc = $RUNNER->run($secondaries, ['deploy-diablo-worker', 'secondary']);

    if ($pproc->wait() != 0) {
	die ("cannot deploy diablo primary node");
    }

    if ($sproc->wait() != 0) {
	die ("cannot deploy diablo secondary nodes");
    }

    $chain = $ENV{MINION_PRIVATE} . '/chain.yml';

    if (!copy($ALGORAND_CHAINCONFIG_PATH, $chain)) {
	die ("cannot send '$ALGORAND_CHAINCONFIG_PATH' to workers");
    }

    foreach $worker ($primary, @$secondaries) {
	$proc = $worker->send(
	    [ $chain, $PRIMARYFILE_PATH ],
	    TARGET => 'deploy/diablo/'
	    );
	push(@procs, $proc);
    }

    $pgrp = Minion::System::Pgroup->new(\@procs);

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	die ("cannot send config files to workers");
    }

    unlink($chain);

    return 1;
}

sub deploy_diablo
{
    my ($actors, $primary, @secondaries);

    if (!(-e $ACTORS_LIST_PATH)) {
	return 1;
    }

    $actors = get_actors($ACTORS_LIST_PATH);

    if (defined($actors->{'primary'})) {
	if (scalar(%{$actors->{'primary'}}) > 1) {
	    die ("more than one diablo 'primary' defined");
	}
	$primary = (keys(%{$actors->{'primary'}}))[0];
    } else {
	die ("no diablo 'primary' defined");
    }

    if (defined($actors->{'secondary'})) {
	@secondaries = keys(%{$actors->{'secondary'}});
    } else {
	die ("no diablo 'secondary' defined");
    }

    build_primaryfile($PRIMARYFILE_PATH, $primary);

    if (-e $ALGORAND_CHAINCONFIG_PATH) {
	return deploy_diablo_algorand(
	    $actors->{'primary'}->{$primary},
	    [ map { $actors->{'secondary'}->{$_} } @secondaries ]);
    }

    return 1;
}


deploy_diablo();
__END__
