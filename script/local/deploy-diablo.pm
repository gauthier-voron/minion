package deploy_algorand;

use strict;
use warnings;

use File::Temp qw(tempfile);

use Minion::System::Pgroup;


my $PRIMARY_TCP_PORT = 5000;


my $FLEET = $_;                        # Global parameter (setup by the Runner)
my %PARAMS = @_;                      # Script parameters (setup by the Runner)
my $RUNNER = $PARAMS{RUNNER};             # Runner itself (setup by the Runner)


my $SHARED = $ENV{MINION_SHARED};

my $DATA_DIR = $SHARED . '/diablo';
my $ROLES_PATH = $DATA_DIR . '/behaviors.txt';
my $WORKLOAD_PATH = $DATA_DIR . '/workload.yaml';


my $PRIVATE = $ENV{MINION_PRIVATE};

my $SPEC_WORKLOAD_PATH = $PRIVATE . '/workload.yaml';


my $DEPLOY = 'deploy/diablo';
my $CHAIN_PRIMARY_LOC = $DEPLOY . '/primary/chain.yaml';
my $CHAIN_LOC = $DEPLOY . '/chain.yaml';
my $WORKLOAD_LOC = $DEPLOY . '/workload.yaml';
my $KEYS_LOC = $DEPLOY . '/keys.json';


my $ALGORAND_CHAINCONFIG_PATH = $SHARED . '/algorand-chain.yml';
my $LIBRA_CHAIN_PATH = $SHARED . '/libra/chain.yaml';
my $POA_CHAIN_PATH = $SHARED . '/poa/chain.yaml';
my $QUORUMIBFT_CHAIN_PATH = $SHARED . '/quorum-ibft/chain.yaml';
my $QUORUMRAFT_CHAIN_PATH = $SHARED . '/quorum-raft/chain.yaml';


# Extract from the given $path the Quorum nodes.
#
# Return: { $ip => { 'worker'      => $worker
#                  , 'primary'     => $primary
#                  , 'secondaries' => $secondaries
#                  }
#         }
#
#   where $ip is an IPv4 address, $worker is a Minion::Worker object, $primary
#   is '1' if the worker is primary and '0' if not, and $secondaries
#   indicates the number of secondary instances to deploy on $worker.
#
sub get_nodes
{
    my ($path) = @_;
    my (%nodes, $node, $fh, $line, $ip, $role, $number, $worker, $assigned);

    if (!open($fh, '<', $path)) {
	die ("cannot open '$path' : $!");
    }

    while (defined($line = <$fh>)) {
	chomp($line);
	($ip, $role, $number) = split(':', $line);

	$node = $nodes{$ip};

	if (!defined($node)) {
	    $assigned = undef;

	    foreach $worker ($FLEET->members()) {
		if ($worker->can('public_ip')) {
		    $assigned = $worker->public_ip();
		} elsif ($worker->can('host')) {
		    $assigned = $worker->host_ip();
		}

		if ($assigned eq $ip) {
		    $assigned = $worker;
		    last;
		} else {
		    $assigned = undef;
		}
	    }

	    if (!defined($assigned)) {
		die ("cannot find worker with ip '$ip' in deployment fleet");
	    }

	    $node = {
		'worker' => $assigned,
		'primary' => 0,
		'secondary' => 0
	    };

	    $nodes{$ip} = $node;
	}

	if ($role eq 'primary') {
	    if ($number ne '1') {
		die ("malformed roles file '$path': $line");
	    }
	    $node->{'primary'} += 1;
	} elsif ($role eq 'secondary') {
	    $node->{'secondaries'} += $number;
	} else {
	    die ("malformed roles file '$path': $line");
	}
    }

    close($fh);

    $number = 0;
    foreach $ip (keys(%nodes)) {
	$number += $nodes{$ip}->{'primary'};
    }

    if ($number < 1) {
	die ("no primary node defined in '$path'");
    } elsif ($number > 1) {
	die ("multiple primary nodes defined in '$path'");
    }

    return \%nodes;
}


sub grep_region_chain
{
    my ($chain, $worker) = @_;
    my ($wregion, $member, @allowed, $rfh, $line, $ip, $wfh, $path);

    $wregion = $worker->region();

    foreach $member ($FLEET->members()) {
	if ($member->region() ne $wregion) {
	    next;
	}
	push(@allowed, $member->public_ip());
    }

    ($wfh, $path) = tempfile(DIR => $PRIVATE);

    if (!open($rfh, '<', $chain)) {
	die ("cannot grep '$chain'");
    }

    while (defined($line = <$rfh>)) {
	chomp($line);

	if ($line =~ /^  - (\d+\.\d+\.\d+\.\d+):\d+$/) {
	    $ip = $1;

	    if (!grep { $ip eq $_ } @allowed) {
		next;
	    }
	}

	printf($wfh "%s\n", $line);
    }

    close($rfh);
    close($wfh);

    return $path;
}

sub deploy_diablo_chain
{
    my ($nodes, $primary, $secondaries, $chain) = @_;
    my ($node, @procs, $proc, @stats, $tchain);

    foreach $node (values(%$nodes)) {
	if ($node->{'primary'} > 0) {
	    $proc = $node->{'worker'}->send(
		[ $chain ],
		TARGET => $CHAIN_PRIMARY_LOC);
	    push(@procs, $proc);
	}

	if ($node->{'secondaries'} > 0) {
	    $tchain = grep_region_chain($chain, $node->{'worker'});
	    $proc = $node->{'worker'}->send(
		[ $tchain ],
		TARGET => $CHAIN_LOC);
	    push(@procs, $proc);
	}
    }

    @stats = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @stats) {
	die ("cannot send algorand chain configuration on workers");
    }

    return 1;
}

sub deploy_diablo_algorand
{
    return deploy_diablo_chain(@_, $ALGORAND_CHAINCONFIG_PATH);
}

sub deploy_diablo_libra
{
    return deploy_diablo_chain(@_, $LIBRA_CHAIN_PATH);
}

sub deploy_diablo_poa
{
    return deploy_diablo_chain(@_, $POA_CHAIN_PATH);
}

sub deploy_diablo_quorum_ibft
{
    return deploy_diablo_chain(@_, $QUORUMIBFT_CHAIN_PATH);
}

sub deploy_diablo_quorum_raft
{
    return deploy_diablo_chain(@_, $QUORUMRAFT_CHAIN_PATH);
}


sub specialize_workload
{
    my ($path, $template, $secondaries, $threads) = @_;
    my ($rfh, $wfh, $line);

    if (!open($rfh, '<', $template)) {
	die ("cannot read workload file '$template' : $!");
    }

    if (!open($wfh, '>', $path)) {
	die ("cannot write workload file '$path' : $!");
    }

    while (defined($line = <$rfh>)) {
	chomp($line);

	if ($line =~ /^secondaries: \d+\s*$/) {
	    $line = 'secondaries: ' . $secondaries;
	} elsif ($line =~ /^threads: \d+\s*$/) {
	    $line = 'threads: ' . $threads;
	}

	printf($wfh "%s\n", $line);
    }

    close($rfh);
    close($wfh);
}

sub deploy_diablo
{
    my ($nodes, $ip, $primary, @secondaries, $proc, @procs, @stats);

    if (!(-e $ROLES_PATH)) {
	return 1;
    }

    $nodes = get_nodes($ROLES_PATH);


    foreach $ip (keys(%$nodes)) {
	if ($nodes->{$ip}->{'primary'} > 0) {
	    $proc = $RUNNER->run(
		$nodes->{$ip}->{'worker'},
		[ 'deploy-diablo-worker', 'primary', $PRIMARY_TCP_PORT ]
		);
	    if ($proc->wait() != 0) {
		die ("cannot to deploy diablo primary on worker");
	    }
	    $primary = $ip;
	    last;
	}
    }

    foreach $ip (keys(%$nodes)) {
	if ($nodes->{$ip}->{'secondaries'} > 0) {
	    $proc = $RUNNER->run(
		$nodes->{$ip}->{'worker'},
		[ 'deploy-diablo-worker', 'secondary',
		  $primary . ':' . $PRIMARY_TCP_PORT,
		  $nodes->{$ip}->{'secondaries'} ]
		);
	    push(@procs, $proc);
	    push(@secondaries, $ip);
	}
    }

    @stats = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @stats) {
	die ("cannot deploy diablo secondaries on workers");
    }


    specialize_workload
	($SPEC_WORKLOAD_PATH, $WORKLOAD_PATH, scalar(@secondaries), 1);

    @procs = ();

    foreach $ip (keys(%$nodes)) {
	$proc = $nodes->{$ip}->{'worker'}->send(
	    [ $SPEC_WORKLOAD_PATH ],
	    TARGET => $WORKLOAD_LOC
	    );
	push(@procs, $proc);
    }

    @stats = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @stats) {
	die ("cannot send workload on workers");
    }


    if (-f $ALGORAND_CHAINCONFIG_PATH) {
	return deploy_diablo_algorand($nodes, $primary, \@secondaries);
    }

    if (-f $LIBRA_CHAIN_PATH) {
	return deploy_diablo_libra($nodes, $primary, \@secondaries);
    }

    if (-f $POA_CHAIN_PATH) {
	return deploy_diablo_poa($nodes, $primary, \@secondaries);
    }

    if (-f $QUORUMIBFT_CHAIN_PATH) {
	return deploy_diablo_quorum_ibft($nodes, $primary, \@secondaries);
    }

    if (-f $QUORUMRAFT_CHAIN_PATH) {
	return deploy_diablo_quorum_raft($nodes, $primary, \@secondaries);
    }


    return 1;
}


deploy_diablo();
__END__
