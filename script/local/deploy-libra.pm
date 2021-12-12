package deploy_poa;

use strict;
use warnings;

use File::Temp qw(tempfile tempdir);
use List::Util qw(sum);
use YAML;

use Minion::System::Pgroup;
use Minion::StaticFleet;


# Program environment ---------------------------------------------------------

my $FLEET = $_;                                # Fleet running this program
my %PARAMS = @_;                               # Script parameters
my $RUNNER = $PARAMS{RUNNER};                  # Runner used to run this script

my $SHARED = $ENV{MINION_SHARED};       # Directory shared by all local scripts
my $PUBLIC = $SHARED . '/libra';        # Directory for specific but public
my $PRIVATE = $ENV{MINION_PRIVATE};     # Directory specific to this script

# A list of nodes behaving as an Ethereum POA node.
# This list is created by one or many invocations of 'behave-poa.pm'.
#
my $ROLES_PATH = $PUBLIC . '/behaviors.txt';

# Where the deployment happens on the workers.
# Scripts should create and edit files only in this directory to avoid name
# conflicts.
#
my $DEPLOY_PATH = 'deploy/libra';

# A Blockchain description in a format that Diablo understands.
# This file is created by this script during deployment.
#
my $CHAIN_PATH = $PUBLIC . '/chain.yaml';

my $VALIDATOR_PORT_START     = 7000;
my $VALIDATOR_PORT_INCREMENT = 1;

my $CLIENT_PORT_START     = 9000;
my $CLIENT_PORT_INCREMENT = 1;



# Interaction functions -------------------------------------------------------

# Extract from the given $path the Quorum nodes.
#
# Return: { $ip => { 'worker'  => $worker
#                  , 'indices' => [ $indices ]
#                  }
#         }
#
#   where $ip is an IPv4 address, $worker is a Minion::Worker object and
#   $indices is an array of integers, each being the index of an ethereum node
#   to deploy on $worker.
#
# Example: { '1.1.1.1' => { 'worker'  => Minion::Worker('A')
#                         , 'indices' => [ 0, 3, 4 ]
#                         },
#          , '4.4.4.4' => { 'worker'  => Minion::Worker('B')
#                         , 'indices' => [ 1 ]
#                         },
#          , '2.2.2.2' => { 'worker'  => Minion::Worker('C')
#                         , 'indices' => [ 2 ]
#                         }
#          }
#
sub get_nodes
{
    my ($path) = @_;
    my (%nodes, $node, $fh, $line, $ip, $num, $worker, $assigned, $index, $i);

    if (!open($fh, '<', $path)) {
	die ("cannot open '$path' : $!");
    }

    $index = 0;

    while (defined($line = <$fh>)) {
	chomp($line);
	($ip, $num) = split(':', $line);

	$node = $nodes{$ip};

	if (!defined($node)) {
	    $assigned = undef;

	    foreach $worker ($FLEET->members()) {
		if ($worker->can('public_ip')&&($worker->public_ip() eq $ip)) {
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

	    $node = {
		'worker' => $assigned,
		'indices' => []
	    };

	    $nodes{$ip} = $node;
	}

	for ($i = 0; $i < $num; $i++) {
	    push(@{$node->{'indices'}}, $index);
	    $index += 1;
	}
    }

    close($fh);

    return \%nodes;
}

sub generate_chainfile_extra
{
    my ($stream, $network) = @_;
    my ($path, $fh, $line, $addr, $key, $seq);

    printf($stream "extra:\n");

    $path = $network . '/logs/init.log';

    if (!open($fh, '<', $path)) {
	die ("cannot read init logfile '$path'");
    }

    while (defined($line = <$fh>)) {
	chomp($line);

	if ($line =~ m|^User account index: \d+, address: ([0-9a-f]+), private_key: "([0-9a-f]+)", sequence number: (\d+), status: Persisted$|) {
	    ($addr, $key, $seq) = ($1, $2, $3);

	    printf($stream "  - address: %s\n", $addr);
	    printf($stream "    key: %s\n", $key);
	    printf($stream "    sequence: %d\n", $seq);
	}
    }

    close($fh);
}

sub generate_chainfile
{
    my ($dest, $network, $nodes, $ports) = @_;
    my ($fh, $ip, $index);

    if (!open($fh, '>', $dest)) {
	die ("cannot write '$dest' : $!");
    }

    printf($fh "name: diem\n");
    printf($fh "nodes:\n");

    foreach $ip (keys(%$nodes)) {
	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    printf($fh "  - %s:%d\n", $ip, $ports->{$index}->{'client'});
	}
    }

    generate_chainfile_extra($fh, $network);

    close($fh);

    system('cat', $dest);
}


# Transfer/remote functions ---------------------------------------------------

sub prepare_accounts
{
    my ($nodes) = @_;
    my ($pgroup, $ip, $proc);

    $pgroup = Minion::System::Pgroup->new([]);

    foreach $ip (keys(%$nodes)) {
	$proc = $RUNNER->run(
	    $nodes->{$ip}->{'worker'},
	    [ 'deploy-libra-worker' , 'prepare' ]
	    );
	$pgroup->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgroup->waitall()) {
	die ('cannot prepare deployment on workers');
    }
}

sub generate_local_testnet
{
    my ($worker, $nodes, $path) = @_;
    my ($dest, $cmd, $num, $output);

    $num = sum(map { scalar(@{$_->{'indices'}}) } values(%$nodes));
    $output = $path;
    $dest = tempdir(DIR => $PRIVATE);

    $cmd = [ 'deploy-libra-worker', 'generate', $num, $output ];
    if ($RUNNER->run($worker, $cmd)->wait() != 0) {
	die ('cannot generate local testnet');
    }

    rmdir($dest);
    if ($worker->recv([ $output ], TARGET => $dest)->wait() != 0) {
	die ('cannot receive local testnet from worker');
    }

    if ($worker->execute(['rm', '-rf', $output])->wait() != 0) {
	die ('cannot clean files on worker');
    }

    return $dest;
}

sub dispatch_network
{
    my ($network, $nodes) = @_;
    my ($ip, $worker, $index, $proc, $pgroup);

    system('ls', $network);

    $pgroup = Minion::System::Pgroup->new([]);

    foreach $ip (keys(%$nodes)) {
	$worker = $nodes->{$ip}->{'worker'};

	$proc = $worker->send(
	    [
	     ( map { $network . '/n' . $_ } @{$nodes->{$ip}->{'indices'}} ),
	     $network . '/mint.key',
	     $network . '/wallet',
	     $network . '/waypoint'
	    ],
	    TARGET => $DEPLOY_PATH
	    );

	$pgroup->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgroup->waitall()) {
	die ('cannot send network config to workers');
    }
}


# Local function --------------------------------------------------------------

#
# Return: { $index => { 'validator' => $port
#                     , 'client'    => $port
#                     }
#         }
#
sub assign_ports
{
    my ($nodes) = @_;
    my (%ports, $ip, $index, $vport, $cport);

    foreach $ip (keys(%$nodes)) {
	$vport = $VALIDATOR_PORT_START;
	$cport = $CLIENT_PORT_START;

	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    $ports{$index} = {
		'validator' => $vport,
		'client'    => $cport
	    };

	    $vport += $VALIDATOR_PORT_INCREMENT;
	    $cport += $CLIENT_PORT_INCREMENT;
	}
    }

    return \%ports;
}

sub setup_paths
{
    my ($network, $nodes, $from) = @_;
    my ($ip, $index, $path, $fh, $line, $to, $text);

    $to = $DEPLOY_PATH;

    foreach $ip (keys(%$nodes)) {
	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    $path = $network . '/n' . $index . '/node.yaml';
	    $text = '';

	    if (!open($fh, '<', $path)) {
		die ("cannot open config file '$path'");
	    }

	    while (defined($line = <$fh>)) {
		$line =~ s|$from|$to|g;
		$line =~ s|$to/(\d+)/|$to/n$1/|g;
		$line =~ s|$to/(\d+)$|$to/n$1|g;
		$text .= $line;
	    }

	    close($fh);

	    if (!open($fh, '>', $path)) {
		die ("cannot modify config file '$path'");
	    }

	    printf($fh "%s", $text);
	    close($fh);
	}
    }
}

sub setup_waypoint
{
    my ($network) = @_;
    my ($path, $fh, $line, $waypoint);

    $path = $network . '/logs/0.log';

    if (!open($fh, '<', $path)) {
	die ("cannot open log file '$path'");
    }

    while (defined($line = <$fh>)) {
	chomp($line);

	if ($line =~ m|"waypoint"\s*:\s*"(0:[^"]+)"|) {
	    $waypoint = $1;
	} else {
	    next;
	}

	last;
    }

    close($fh);

    if (!defined($line)) {
	die ("cannot find waypoint in '$path'");
    }


    $path = $network . '/waypoint';

    if (!open($fh, '>', $path)) {
	die ("cannot create waypoint '$path'");
    }

    printf($fh "%s\n", $waypoint);

    close($fh);
}

sub setup_addresses
{
    my ($network, $nodes, $ports) = @_;
    my ($ip, $index, $path, $port, $fh, $line);
    my (%confs, %enodes, %peers);

    # Load

    foreach $ip (keys(%$nodes)) {
	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    $path = $network . '/n' . $index . '/node.yaml';
	    $confs{$index} = YAML::LoadFile($path);

	    $port = $confs{$index}->{'validator_network'}->{'listen_address'};
	    $port =~ s|^.*/||;

	    $path = $network . '/logs/' . $index . '.log';

	    if (!open($fh, '<', $path)) {
		die ("cannot open log file '$path'");
	    }

	    while (defined($line = <$fh>)) {
		chomp($line);

		if ($line =~ m|Start listening for incoming connections on (\S+/$port/\S+)|) {
		    $enodes{$index} = $1;
		} else {
		    next;
		}

		if ($line =~ m|"peer_id"\s*:\s*"([^"]+)"|) {
		    $peers{$index} = $1;
		} else {
		    next;
		}

		last;
	    }

	    close($fh);

	    if (!defined($line)) {
		die ("cannot find id of peer $index in '$path'");
	    }
	}
    }

    # Modify

    foreach $ip (keys(%$nodes)) {
	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    $port = $ports->{$index}->{'validator'};

	    $enodes{$index} =~ s|/ip4/0.0.0.0/|/ip4/$ip/|;
	    $enodes{$index} =~ s|/tcp/\d+/|/tcp/$port/|;
	}
    }

    foreach $ip (keys(%$nodes)) {
	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    $confs{$index}->{'json_rpc'}->{'address'} =
		'0.0.0.0:' . $ports->{$index}->{'client'};

	    $confs{$index}->{'validator_network'}->{'discovery_method'}='none';

	    $confs{$index}->{'validator_network'}->{'listen_address'} =
		'/ip4/0.0.0.0/tcp/' . $ports->{$index}->{'validator'};

	    $confs{$index}->{'validator_network'}->{'seeds'} = {
		map { $peers{$_} => {
		    'addresses' => [ $enodes{$_} ],
		    'keys'      => [ (split('/', $enodes{$_}))[6] ],
		    'role'      => 'Validator'
		} }
		sort { $a <=> $b }
		grep { $_ != $index }
		keys(%peers)
	    };
	}
    }

    # Dump

    foreach $ip (keys(%$nodes)) {
	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    $path = $network . '/n' . $index . '/node.yaml';
	    YAML::DumpFile($path, $confs{$index});
	}
    }
}


# Main function ---------------------------------------------------------------

sub deploy_libra
{
    my ($nodes, $ports, $genworker, $network, $path);

    if (!(-f $ROLES_PATH)) {
	return 1;
    }

    $nodes = get_nodes($ROLES_PATH);
    $ports = assign_ports($nodes);
    $genworker = (values(%$nodes))[0]->{'worker'};

    prepare_accounts($nodes);

    $path = $DEPLOY_PATH . '/network';
    $network = generate_local_testnet($genworker, $nodes, $path);

    setup_paths($network, $nodes, $path);

    setup_waypoint($network);

    setup_addresses($network, $nodes, $ports);

    dispatch_network($network, $nodes);

    generate_chainfile($CHAIN_PATH, $network, $nodes, $ports);

    return 1;
}


deploy_libra();
__END__
