package deploy_avalanche;

use strict;
use warnings;

use File::Copy;

use Minion::System::Pgroup;


my $API_TCP_PORT = 9650;                       # HTTP port
my $P2P_TCP_PORT = 9651;                         # Staking port


my $FLEET = $_;                        # Global parameter (setup by the Runner)
my %PARAMS = @_;                      # Script parameters (setup by the Runner)
my $RUNNER = $PARAMS{RUNNER};             # Runner itself (setup by the Runner)


my $MINION_SHARED = $ENV{MINION_SHARED};        # Environment (setup by Runner)
my $MINION_PRIVATE = $ENV{MINION_PRIVATE};  # Where to store local private data

my $DATA_DIR = $MINION_SHARED . '/avalanche';  # Where to store things across
                                                 # Runner invocations

my $ROLES_PATH = $DATA_DIR . '/behaviors.txt';           # Behaviors of workers
my $CHAIN_PATH = $DATA_DIR . '/chain.yaml';   # Diablo description of the chain


my $DEPLOY_ROOT = 'deploy/avalanche';       # Where the files are deployed on
                                              # the workers

# List of ip/port of the Avalanche nodes
#
my $NODEFILE_NAME = 'nodes.conf';
my $NODEFILE_PATH = $MINION_PRIVATE . '/' . $NODEFILE_NAME;
my $NODEFILE_LOC = $DEPLOY_ROOT . '/' . $NODEFILE_NAME;

# Directory containing nodes data directories
#
my $NETWORK_NAME = 'network';
my $NETWORK_PATH = $MINION_PRIVATE . '/' . $NETWORK_NAME;
my $NETWORK_LOC = $DEPLOY_ROOT . '/' . $NETWORK_NAME;

my $KEYS_ROOT = 'install/geth-accounts';
my $KEYS_TXT_LOC = $KEYS_ROOT . '/accounts.txt';
my $KEYS_YAML_LOC = $KEYS_ROOT . '/accounts.yaml';


# Extract from the given $path the Avalanche nodes.
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

# Generate the file of Avalanche nodes.
# It has the following format:
#
#   IP0:portA0:portB0
#   IP1:portA1:portB1
#   ...
#
# Where portA is the port used for client API (--http-port paraneter), port B
# is the port used for P2P (--staking-port).
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
	    printf($fh "%s:%d:%d\n", $ip, $API_TCP_PORT + 2*$i,
		   $P2P_TCP_PORT + 2*$i);
	}
    }

    close($fh);

    return 1;
}

sub generate_setup
{
    my ($nodes, $target) = @_;
    my ($ifh, $ofh, $line, $ip, $i, $port, $worker, %groups, $tags);

    foreach $ip (keys(%$nodes)) {
        for ($i = 0; $i < $nodes->{$ip}->{'number'}; $i++) {
            $line = sprintf("%s:%d/ext/bc/C/ws", $ip, $API_TCP_PORT + 2 * $i);
            $tags = $nodes->{$ip}->{'worker'}->region();
            push(@{$groups{$tags}}, $line);
        }
    }

    if (!open($ofh, '>', $target)) {
        return 0;
    }

    printf($ofh "interface: \"ethereum\"\n");
    printf($ofh "\n");
    printf($ofh "endpoints:\n");

    foreach $tags (keys(%groups)) {
        printf($ofh "\n");
        printf($ofh "  - addresses:\n");
        foreach $line (@{$groups{$tags}}) {
            printf($ofh "    - %s\n", $line);
        }
        printf($ofh "    tags:\n");
        foreach $line (split("\n", $tags)) {
            printf($ofh "    - %s\n", $line);
        }
    }

    close($ofh);

    return 1;
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
	die ("cannot dispatch avalanche network to workers");
    }
}

# Deploy an Avalanche blockchain over the workers listed in $ROLES_PATH which
# are in the given $FLEET.
#
sub deploy_avalanche
{
    my ($nodes, @workers, $genworker, $proc);

    # No node with Avalanche behavior.
    # We exit with success.
    #
    if (!(-f $ROLES_PATH)) {
	return 1;
    }

    # Get workers and number of nodes on each worker from role file.
    #
    $nodes = get_nodes($ROLES_PATH);
    @workers = map { $_->{'worker'} } values(%$nodes);

    # Generate a file containing the ip/ports of each Avalanche node.
    #
    if (!build_nodefile($NODEFILE_PATH, $nodes)) {
	die ("cannot generate node file '$NODEFILE_PATH' : $!");
    }

    # Prepare Avalanche deployment for all nodes.
    #
    $proc = $RUNNER->run(\@workers, [ 'deploy-avalanche-worker','prepare' ]);
    if ($proc->wait() != 0) {
	die ("failed to prepare avalanche workers");
    }

    # Generate network for Avalanche

    $genworker = $workers[0];

    $proc = $genworker->send([ $NODEFILE_PATH ], TARGET => $DEPLOY_ROOT);
    if ($proc->wait() != 0) {
	die ("cannot send avalanche node file to worker");
    }

    $proc = $RUNNER->run(
	$genworker,
	[ 'deploy-avalanche-worker', 'generate', $NODEFILE_LOC ,
	  $KEYS_TXT_LOC ]
	);
    if ($proc->wait() != 0) {
	die ("failed to generate avalanche testnet");
    }

    # Fetch and dispatch generated testnet

    $proc = $genworker->recv([ $NETWORK_LOC . '.tar.gz' ], TARGET => $MINION_PRIVATE);
    if ($proc->wait() != 0) {
	die ("cannot receive avalanche testnet from worker");
    }
    $proc = $genworker->recv(
    [ $KEYS_YAML_LOC ],
    TARGET => $DATA_DIR . '/accounts.yaml'
    );
    if ($proc->wait() != 0) {
        die ("cannot receive poa accounts from worker");
    }

    system('tar', '--directory=' . $ENV{MINION_PRIVATE}, '-xzf',
	   $ENV{MINION_PRIVATE} . '/' . $NETWORK_NAME . '.tar.gz');

    generate_setup($nodes, $DATA_DIR . '/setup.yaml');

    dispatch($nodes, $NETWORK_PATH);

    $genworker->execute(
	[ 'rm', '-rf', $NODEFILE_LOC, $NETWORK_LOC . '.tar.gz' ]
	)->wait();


    return 1;
}


deploy_avalanche();
__END__
