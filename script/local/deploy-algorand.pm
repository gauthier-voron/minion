package deploy_algorand;

use strict;
use warnings;

use List::Util qw(sum);

use Minion::StaticFleet;
use Minion::System::Pgroup;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};

my $NODE_LIST_PATH = $ENV{MINION_SHARED} . '/algorand-nodes';

my $NETWORK_TEMPLATE_NAME = 'network.json';
my $NETWORK_TEMPLATE_PATH = $ENV{MINION_PRIVATE} . '/' .$NETWORK_TEMPLATE_NAME;

my $NODEFILE_NAME = 'nodes';
my $NODEFILE_PATH = $ENV{MINION_PRIVATE} . '/' . $NODEFILE_NAME;

my $PEER_TCP_PORT   = 7000;
my $CLIENT_TCP_PORT = 9000;

my $NETWORK_NAME = 'network';
my $NETWORK_PATH = $ENV{MINION_PRIVATE} . '/' . $NETWORK_NAME;

my $CHAINEXTRA_NAME = 'chain.yml';
my $CHAINEXTRA_PATH = $ENV{MINION_PRIVATE} . '/' . $CHAINEXTRA_NAME;

my $CHAINCONFIG_NAME = 'algorand-chain.yml';
my $CHAINCONFIG_PATH = $ENV{MINION_SHARED} . '/' . $CHAINCONFIG_NAME;
my $CHAINCONFIG_TCP_PORT = 3000;


# Extract from the given $path the Algorand nodes.
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

# Return the sorted IPs of Algorand full or client nodes from the actors as
# returned by `get_actors()` and a role.
# If an actor has an instance number greater than 1 then its IP is repeated as
# many times.
#
# Return: [ $ip , ... ]
#
sub get_actors_ip_instances
{
    my ($actors, $role) = @_;
    my (@ips, $ip, $actor, $number, $i);

    while (($ip, $actor) = each(%{$actors->{$role}})) {
	$number = $actor->[1];
	for ($i = 0; $i < $number; $i++) {
	    push(@ips, $ip);
	}
    }

    return [ sort { $a cmp $b } @ips ];
}

# Return the workers of Algorand full or client nodes from the actors as
# returned by `get_actors()` and a role.
# If an actor has an instance number greater than 1 then the corresponding
# worker is repeated as many times.
# The workers appear sorted by their IP.
#
# Return: [ $worker , ... ]
#
sub get_actors_worker_instances
{
    my ($actors, $role) = @_;
    my (@workers, $ip, $actor, $worker, $number, $i);

    foreach $ip (sort { $a cmp $b } keys(%{$actors->{$role}})) {
	$actor = $actors->{$role}->{$ip};
	$worker = $actor->[0];
	$number = $actor->[1];

	for ($i = 0; $i < $number; $i++) {
	    push(@workers, $worker);
	}
    }

    return \@workers;
}

sub build_network_template
{
    my ($path, $nodes) = @_;
    my ($nodenum, $walletnum);
    my ($fh, $share, $rem, $stake, $name, $sep, $i);

    $nodenum = sum(map { $_->{'number'} } values(%$nodes));
    $walletnum = $nodenum;

    $share = sprintf("%.2f", 100.0 / $walletnum);
    $rem = 100.0 - ($share * $walletnum);

    if (!open($fh, '>', $path)) {
	die ("cannot create algorand network template '$path' : $!");
    }

    printf($fh "%s", <<"EOF");
{
    "Genesis": {
	"NetworkName": "PrivateNet",
	"Wallets": [
EOF

    $sep = '';

    for ($i = 0; $i < $walletnum; $i++) {
	if ($i == 0) {
	    $stake = $share + $rem;
	} else {
	    $stake = $share;
	}

	printf($fh "%s%s", $sep, <<"EOF");
	    {
		"Name": "wallet_$i",
		"Stake": $stake,
		"Online": true
	    }
EOF
	$sep = "\t    ,\n";
    }

    printf($fh "%s", <<"EOF");
	]
    }
    ,
    "Nodes": [
EOF

    $sep = '';

    for ($i = 0; $i < $walletnum; $i++) {
	$name = "n" . $i;

	printf($fh "%s%s", $sep, <<"EOF");
	{
	    "Name": "$name",
	    "IsRelay": true,
	    "Wallets": [
		{
		    "Name": "wallet_$i",
		    "ParticipationOnly": false
		}
            ]
	}
EOF

	$sep = "\t,\n";
    }

    printf($fh "%s", <<"EOF");
    ]
}
EOF

    close($fh);
}

sub build_nodefile
{
    my ($path, $nodes) = @_;
    my ($fh, $ip, $i);

    if (!open($fh, '>', $path)) {
	die ("cannot create algorand nodefile '$path' : $!");
    }

    foreach $ip (keys(%$nodes)) {
	for ($i = 0; $i < $nodes->{$ip}->{'number'}; $i++) {
	    printf($fh "%s:%d:%d\n", $ip, $PEER_TCP_PORT + $i,
		   $CLIENT_TCP_PORT + $i);
	}
    }

    close($fh);
}

sub dispatch
{
    my ($nodes, $network) = @_;
    my ($ip, $i, $done, @paths, @procs, $proc, @statuses);

    $done = 0;

    foreach $ip (keys(%$nodes)) {
	@paths = ();

	for ($i = 0; $i < $nodes->{$ip}->{'number'}; $i++) {
	    push(@paths, $NETWORK_PATH . '/n' . ($done + scalar(@paths)));
	}

	$proc = $nodes->{$ip}->{'worker'}->send(
	    [ @paths ],
	    TARGET => 'deploy/algorand/'
	    );
	push(@procs, $proc);

	$done += scalar(@paths);
    }

    @statuses = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @statuses) {
	die ("cannot dispatch algorand network to workers");
    }
}

sub build_chainconfig
{
    my ($path, $nodes, $extra) = @_;
    my ($fh, $ip, $i, $eh, $line);

    if (!open($fh, '>', $path)) {
	die ("cannot create algorand chain config '$path' : $!");
    }

    printf($fh "name: algorand\n");
    printf($fh "nodes:\n");

    foreach $ip (keys(%$nodes)) {
	for ($i = 0; $i < $nodes->{$ip}->{'number'}; $i++) {
	    printf($fh "  - %s:%d\n", $ip, $CLIENT_TCP_PORT + $i);
	}
    }

    if (open($eh, '<', $extra)) {
	while (defined($line = <$eh>)) {
	    printf($fh "%s", $line);
	}
	close($eh);
    }

    close($fh);
}

sub deploy_algorand
{
    my ($nodes, $genworker, $ret);
    my ($i, $proc, @procs, @statuses);

    if (!(-e $NODE_LIST_PATH)) {
	return 1;
    }

    $nodes = get_nodes($NODE_LIST_PATH);

    # Build the global information files necessary to generate the Algorand
    # testnet.
    #

    build_network_template($NETWORK_TEMPLATE_PATH, $nodes);

    build_nodefile($NODEFILE_PATH, $nodes);

    # The testnet generation involves Algorand binaries. It is thus necessary
    # to send the information files to a worker with the installed binaries for
    # it to generate the testnet and fetch back the generated network.
    #

    $genworker = ($FLEET->members())[0];

    $proc = $RUNNER->run(
	$FLEET,
	[ 'deploy-algorand-worker', 'prepare' ]
	);
    if ($proc->wait() != 0) {
	die ("failed to prepare algorand workers");
    }

    $proc = $genworker->send(
	[ $NETWORK_TEMPLATE_PATH, $NODEFILE_PATH ],
	TARGET => 'deploy/algorand/'
	);
    if ($proc->wait() != 0) {
	die ("cannot send algorand network template to worker");
    }

    $proc = $RUNNER->run(
	$genworker,
	[ 'deploy-algorand-worker', 'generate', $NETWORK_TEMPLATE_NAME,
	  $NODEFILE_NAME ]
	);
    if ($proc->wait() != 0) {
	die ("failed to generate algorand testnet");
    }

    $proc = $genworker->recv(
	[ 'deploy/algorand/' . $NETWORK_NAME,
	  'deploy/algorand/' . $CHAINEXTRA_NAME
	],
	TARGET => $ENV{MINION_PRIVATE}
	);
    if ($proc->wait() != 0) {
	die ("cannot receive algorand testnet from worker");
    }

    $genworker->execute(
	[ 'rm', '-rf',
	  'deploy/algorand/network',
	  'deploy/algorand/chain.yml',
	  'deploy/algorand/' . $NETWORK_TEMPLATE_NAME,
	  'deploy/algorand/' . $NODEFILE_NAME ]
	)->wait();


    # Now this control node can dispatch the necessary information to every
    # nodes.
    #

    build_chainconfig($CHAINCONFIG_PATH, $nodes, $CHAINEXTRA_PATH);

    dispatch($nodes, $NETWORK_PATH);


    # Cleanup before to finish.
    #

    unlink($NODE_LIST_PATH);

    return 1;
}


deploy_algorand();
__END__
