package deploy_solana;

use strict;
use warnings;

use File::Copy;

use Minion::System::Pgroup;


my $RPC_TCP_PORT = 8899;
my $GOSSIP_TCP_PORT = 8001;
my $DYNAMIC_TCP_PORT = 9000;


my $FLEET = $_;                        # Global parameter (setup by the Runner)
my %PARAMS = @_;                      # Script parameters (setup by the Runner)
my $RUNNER = $PARAMS{RUNNER};             # Runner itself (setup by the Runner)


my $MINION_SHARED = $ENV{MINION_SHARED};        # Environment (setup by Runner)
my $MINION_PRIVATE = $ENV{MINION_PRIVATE};  # Where to store local private data

my $DATA_DIR = $MINION_SHARED . '/solana';  # Where to store things across
                                                 # Runner invocations

my $ROLES_PATH = $DATA_DIR . '/behaviors.txt';           # Behaviors of workers
my $CHAIN_PATH = $DATA_DIR . '/chain.yaml';   # Diablo description of the chain


my $DEPLOY_ROOT = 'deploy/solana';       # Where the files are deployed on
                                              # the workers

# List of ip/port of the Quorum nodes
#
my $NODEFILE_NAME = 'nodes.conf';
my $NODEFILE_PATH = $MINION_PRIVATE . '/' . $NODEFILE_NAME;
my $NODEFILE_LOC = $DEPLOY_ROOT . '/' . $NODEFILE_NAME;

# Directory containing nodes data directories
#
my $NETWORK_NAME = 'network';
my $NETWORK_PATH = $MINION_PRIVATE . '/' . $NETWORK_NAME;
my $NETWORK_LOC = $DEPLOY_ROOT . '/' . $NETWORK_NAME;
my $ACCOUNTS_LOC = $DEPLOY_ROOT . '/accounts.yaml.gz';


# Extract from the given $path the Quorum nodes.
#
# Return: { $ip => { 'worker' => $worker
#                  , 'number' => $number
#                  }
#         }
#
#   where $ip is an IPv4 address, $worker is a Minion::Worker object and
#   $number indicates the number of instances to deploy on $worker.
#
sub get_nodes
{
    my ($path) = @_;
    my (%nodes, $node, $fh, $line, $ip, $number, $worker, $assigned);

    if (!open($fh, '<', $path)) {
	die ("cannot open '$path' : $!");
    }

    while (defined($line = <$fh>)) {
	chomp($line);
	($ip, $number) = split(':', $line);

	$node = $nodes{$ip};

	if (defined($node)) {
	    $node->{'number'} += $number;
	    next;
	}

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

	$nodes{$ip} = {
	    'worker' => $assigned,
	    'number' => $number
	};
    }

    close($fh);

    return \%nodes;
}

# Generate the file of Solana nodes.
# It has the following format:
#
#   IP0:portA0:portB0:portC0
#   IP1:portA1:portB1:portC1
#   ...
#
# Where portA is the port used for rpc (--rpc-port paraneter in solana-validator), port B
# is the port used for gossip (--gossip-port in solana-validator) and port C is the port used for dynamic (--dynamic-port-range in solana-validator).
#
sub build_nodefile
{
    my ($path, $nodes) = @_;
    my ($fh, $ip, $number, $i);

    if (!open($fh, '>', $path)) {
	return undef;
    }

    foreach $ip (sort { $a cmp $b } keys(%$nodes)) {
	$number = $nodes->{$ip}->{'number'};

	for ($i = 0; $i < $number; $i++) {
	    printf($fh "%s:%d:%d:%d\n", $ip, $RPC_TCP_PORT + 2 * $i,
		   $GOSSIP_TCP_PORT + $i, $DYNAMIC_TCP_PORT + 10 * $i);
	}
    }

    close($fh);

    return 1;
}

sub build_chainfile
{
    my ($path, $nodes) = @_;
    my ($fh, $ip, $i);

    if (!open($fh, '>', $path)) {
	die ("cannot write chain file '$path' : $!");
    }

    printf($fh "name: solana\n");
    printf($fh "nodes:\n");

    foreach $ip (keys(%$nodes)) {
	for ($i = 0; $i < $nodes->{$ip}->{'number'}; $i++) {
	    printf($fh "  - %s:%d\n", $ip, $RPC_TCP_PORT + 2 * $i);
	}
    }

    printf($fh "extra:\n  - %d\n  - \"deploy/diablo/accounts.yaml.gz\"\n", 150000); # extra

    close($fh);
}

# Dispatch the content of the given network to the workers.
#
sub dispatch
{
    my ($nodes, $network) = @_;
    my ($index, $ip, $worker, $number, @paths, $i, $proc, @procs, @stats);

    $index = 0;
    foreach $ip (sort { $a cmp $b } keys(%$nodes)) {
	$worker = $nodes->{$ip}->{'worker'};
	$number = $nodes->{$ip}->{'number'};
	@paths = ();

	for ($i = 0; $i < $number; $i++) {
	    push(@paths, $network . '/n' . $index);
	    $index += 1;
	}

	$proc = $worker->send([ @paths ], TARGET => $DEPLOY_ROOT);
	push(@procs, $proc);
    }

    @stats = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @stats) {
	die ("cannot dispatch solana network to workers");
    }
}

# Deploy a Solana blockchain over the workers listed in $ROLES_PATH which
# are in the given $FLEET.
#
sub deploy_solana
{
    my ($nodes, @workers, $genworker, $proc);

    # No node with Solana behavior.
    # We exit with success.
    #
    if (!(-f $ROLES_PATH)) {
	return 1;
    }

    # Get workers and number of nodes on each worker from role file.
    #
    $nodes = get_nodes($ROLES_PATH);
    @workers = map { $_->{'worker'} } values(%$nodes);

    # Generate a file containing the ip/ports of each Solana node.
    #
    if (!build_nodefile($NODEFILE_PATH, $nodes)) {
	die ("cannot generate node file '$NODEFILE_PATH' : $!");
    }

    # Prepare Solana deployment for all nodes.
    #
    $proc = $RUNNER->run(\@workers, [ 'deploy-solana-worker','prepare' ]);
    if ($proc->wait() != 0) {
	die ("failed to prepare solana workers");
    }

    # Generate network for Solana

    $genworker = $workers[0];

    $proc = $genworker->send([ $NODEFILE_PATH ], TARGET => $DEPLOY_ROOT);
    if ($proc->wait() != 0) {
	die ("cannot send solana node file to worker");
    }

    $proc = $RUNNER->run(
	$genworker,
	[ 'deploy-solana-worker', 'generate', $NODEFILE_LOC ,
	  150000 ]
	);
    if ($proc->wait() != 0) {
	die ("failed to generate solana testnet");
    }

    # Fetch and dispatch generated testnet

    $proc = $genworker->recv([ $NETWORK_LOC ], TARGET => $MINION_PRIVATE);
    if ($proc->wait() != 0) {
	die ("cannot receive solana testnet from worker");
    }

    $proc = $genworker->recv([ $ACCOUNTS_LOC ], TARGET => $DATA_DIR);
    if ($proc->wait() != 0) {
	die ("cannot receive solana accounts from worker");
    }

    build_chainfile($CHAIN_PATH, $nodes);

    dispatch($nodes, $NETWORK_PATH);

    $genworker->execute(
	[ 'rm', '-rf', $NODEFILE_LOC, $NETWORK_LOC, $ACCOUNTS_LOC ]
	)->wait();


    return 1;
}


deploy_solana();
__END__
