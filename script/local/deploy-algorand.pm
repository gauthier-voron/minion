package deploy_algorand;

use strict;
use warnings;

use Minion::StaticFleet;
use Minion::System::Pgroup;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};

my $ACTORS_LIST_PATH = $ENV{MINION_SHARED} . '/algorand-actors';

my $NETWORK_TEMPLATE_NAME = 'network.json';
my $NETWORK_TEMPLATE_PATH = $ENV{MINION_PRIVATE} . '/' .$NETWORK_TEMPLATE_NAME;

my $NODEFILE_NAME = 'nodes';
my $NODEFILE_PATH = $ENV{MINION_PRIVATE} . '/' . $NODEFILE_NAME;
my $NODEFILE_TCP_PORT = 7000;

my $CLIENTFILE_NAME = 'clients';
my $CLIENTFILE_PATH = $ENV{MINION_PRIVATE} . '/' . $CLIENTFILE_NAME;
my $CLIENTFILE_TCP_PORT = 9000;

my $NETWORK_NAME = 'network';
my $NETWORK_PATH = $ENV{MINION_PRIVATE} . '/' . $NETWORK_NAME;

my $CHAINCONFIG_NAME = 'algorand-chain.yml';
my $CHAINCONFIG_PATH = $ENV{MINION_SHARED} . '/' . $CHAINCONFIG_NAME;
my $CHAINCONFIG_TCP_PORT = 3000;


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

sub build_network_template
{
    my ($path, $nodenum, $walletnum) = @_;
    my ($fh, $share, $rem, $stake, $online, $name, $sep, $i);

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

	if ($i < $nodenum) {
	    $online = 'true';
	} else {
	    $online = 'false';
	}

	printf($fh "%s%s", $sep, <<"EOF");
	    {
		"Name": "wallet_$i",
		"Stake": $stake,
		"Online": $online
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
	if ($i < $nodenum) {
	    $name = "n" . $i;
	    $online = 'true';
	} else {
	    $name = "c" . ($i - $nodenum);
	    $online = 'false';
	}

	printf($fh "%s%s", $sep, <<"EOF");
	{
	    "Name": "$name",
	    "IsRelay": $online,
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
    my ($fh, $node);

    if (!open($fh, '>', $path)) {
	die ("cannot create algorand nodefile '$path' : $!");
    }

    foreach $node (@$nodes) {
	printf($fh "%s:%d\n", $node, $NODEFILE_TCP_PORT);
    }

    close($fh);
}

sub build_clientfile
{
    my ($path, $clients) = @_;
    my ($fh, $client);

    if (!open($fh, '>', $path)) {
	die ("cannot create algorand clientfile '$path' : $!");
    }

    foreach $client (@$clients) {
	printf($fh "%s:%d\n", $client, $CLIENTFILE_TCP_PORT);
    }

    close($fh);
}

sub build_chainconfig
{
    my ($path, $clients, $extra) = @_;
    my ($fh, $client, $eh, $line);

    if (!open($fh, '>', $path)) {
	die ("cannot create algorand chain config '$path' : $!");
    }

    printf($fh "name: algorand\n");
    printf($fh "nodes:\n");

    foreach $client (@$clients) {
	printf($fh "  - localhost:%d\n", $CLIENTFILE_TCP_PORT);
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
    my ($actors, @nodes, @clients, $genworker, $ret);
    my ($i, $proc, @procs, @statuses);

    if (!(-e $ACTORS_LIST_PATH)) {
	return 1;
    }

    $actors = get_actors($ACTORS_LIST_PATH);

    if (defined($actors->{'node'})) {
	@nodes = keys(%{$actors->{'node'}});
    } else {
	die ("no algorand 'node' defined");
    }

    if (defined($actors->{'client'})) {
	@clients = keys(%{$actors->{'client'}});
    } else {
	die ("no algorand 'client' defined");
    }

    # Build the global information files necessary to generate the Algorand
    # testnet.
    #

    build_network_template(
	$NETWORK_TEMPLATE_PATH,
	scalar(@nodes),
	scalar(@nodes) + scalar(@clients)
	);

    build_nodefile($NODEFILE_PATH, \@nodes);

    build_clientfile($CLIENTFILE_PATH, \@clients);

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
	[ $NETWORK_TEMPLATE_PATH, $NODEFILE_PATH, $CLIENTFILE_PATH ],
	TARGET => 'deploy/algorand/'
	);
    if ($proc->wait() != 0) {
	die ("cannot send algorand network template to worker");
    }

    $proc = $RUNNER->run(
	$genworker,
	[ 'deploy-algorand-worker', 'generate', $NETWORK_TEMPLATE_NAME,
	  $NODEFILE_NAME, $CLIENTFILE_NAME ]
	);
    if ($proc->wait() != 0) {
	die ("failed to generate algorand testnet");
    }

    $proc = $genworker->recv(
	[ 'deploy/algorand/network', 'deploy/algorand/chain.yml' ],
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
	  'deploy/algorand/' . $NODEFILE_NAME,
	  'deploy/algorand/' . $CLIENTFILE_NAME ]
	)->wait();


    # Now this control node can dispatch the necessary information to every
    # nodes.
    #

    build_chainconfig($CHAINCONFIG_PATH, \@clients,
		      $ENV{MINION_PRIVATE} . '/chain.yml');

    for ($i = 0; $i < scalar(@nodes); $i++) {
	$proc = $actors->{'node'}->{$nodes[$i]}->send(
	    [ $NETWORK_PATH . '/n' . $i ],
	    TARGET => 'deploy/algorand/node'
	    );
	push(@procs, $proc);
    }

    for ($i = 0; $i < scalar(@clients); $i++) {
	$proc = $actors->{'client'}->{$clients[$i]}->send(
	    [ $NETWORK_PATH . '/c' . $i ],
	    TARGET => 'deploy/algorand/client'
	    );
	push(@procs, $proc);
    }

    @statuses = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @statuses) {
	die ("cannot dispatch algorand network to workers");
    }


    # Cleanup before to finish.
    #

    unlink($ACTORS_LIST_PATH);

    return 1;
}


deploy_algorand();
__END__
