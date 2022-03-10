package deploy_poa;

use strict;
use warnings;

use File::Temp qw(tempfile tempdir);

use Minion::System::Pgroup;
use Minion::StaticFleet;


# Program environment ---------------------------------------------------------

my $FLEET = $_;                                # Fleet running this program
my %PARAMS = @_;                               # Script parameters
my $RUNNER = $PARAMS{RUNNER};                  # Runner used to run this script

my $SHARED = $ENV{MINION_SHARED};       # Directory shared by all local scripts
my $PUBLIC = $SHARED . '/poa';          # Directory for specific but public
my $PRIVATE = $ENV{MINION_PRIVATE};     # Directory specific to this script

# A list of nodes behaving as an Ethereum POA node.
# This list is created by one or many invocations of 'behave-poa.pm'.
#
my $ROLES_PATH = $PUBLIC . '/behaviors.txt';

my $NETWORK_NAME = 'network';

# Geth accounts (address and private key) generated at install time.
# These files are on the remote nodes.
#
my $KEYS_JSON_PATH = 'install/geth-accounts/accounts.json';

# Where the deployment happens on the workers.
# Scripts should create and edit files only in this directory to avoid name
# conflicts.
#
my $DEPLOY_PATH = 'deploy/poa';

# A Blockchain description in a format that Diablo understands.
# This file is created by this script during deployment.
#
my $CHAIN_PATH = $PUBLIC . '/chain.yaml';



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

sub generate_chainfile
{
    my ($dest, $nodes, $accounts) = @_;
    my ($wfh, $ip, $index, $path, $rfh, $port);

    if (!open($wfh, '>', $dest)) {
	die ("cannot write '$dest' : $!");
    }

    printf($wfh "name: ethereum\n");
    printf($wfh "nodes:\n");

    foreach $ip (keys(%$nodes)) {
	foreach $index (@{$nodes->{$ip}->{'indices'}}) {
	    $path = $accounts . '/n' . $index . '/wsport';
	    if (!open($rfh, '<', $path)) {
		die ("cannot read '$path' : $!");
	    }

	    chomp($port = <$rfh>);
	    close($rfh);

	    if ($port !~ /^\d+$/) {
		die ("corrupted file '$path' : '$port'");
	    }

	    printf($wfh "  - %s:%d\n", $ip, $port);
	}
    }

    printf($wfh "key_file: \"%s\"\n", $KEYS_JSON_PATH);
    close($wfh);
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
	    [ 'deploy-poa-worker' , 'prepare' , map { 'n' . $_ }
	      @{$nodes->{$ip}->{'indices'}} ]
	    );
	$pgroup->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgroup->waitall()) {
	die ('cannot prepare deployment on workers');
    }
}

sub gather_accounts
{
    my ($nodes) = @_;
    my ($dest, $pgroup, $ip, $proc);

    $dest = tempdir(DIR => $PRIVATE);
    $pgroup = Minion::System::Pgroup->new([]);

    foreach $ip (keys(%$nodes)) {
	$proc = $nodes->{$ip}->{'worker'}->recv(
	    [ map { $DEPLOY_PATH . '/n' . $_ } @{$nodes->{$ip}->{'indices'}} ],
	    TARGET => $dest
	    );
	$pgroup->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgroup->waitall()) {
	die ('cannot prepare deployment on workers');
    }

    system('tar', '--directory=' . $dest , '-czf', $ENV{MINION_PRIVATE} . '/' . $NETWORK_NAME . '.tar.gz', '.');

    return $dest;
}

sub generate_genesis
{
    my ($worker, $accounts) = @_;
    my ($dest, $cmd, $input, $output);

    ($_, $dest) = tempfile(DIR => $PRIVATE);
    $input = $DEPLOY_PATH . '/network';
    $output = $DEPLOY_PATH . '/genesis.json';

    if ($worker->send([ $ENV{MINION_PRIVATE} . '/' . $NETWORK_NAME . '.tar.gz' ], TARGET => $DEPLOY_PATH . '/' )->wait() != 0) {
	die ('cannot send accounts to worker');
    }

    $cmd = [ 'deploy-poa-worker', 'generate', $input, $output ];
    if ($RUNNER->run($worker, $cmd)->wait() != 0) {
	die ('cannot generate testnet');
    }

    if ($worker->recv([ $output ], TARGET => $dest)->wait() != 0) {
	die ('cannot receive genesis file from worker');
    }

    if ($worker->execute(['rm', '-rf', $input,$output])->wait() != 0) {
	die ('cannot clean files on worker');
    }

    return $dest;
}

sub aggregate_nodes
{
    my ($statics) = @_;
    my ($dest, $wfh, $ip, $path, $rfh, $line, $sep);

    ($wfh, $dest) = tempfile(DIR => $PRIVATE);

    printf($wfh "[");
    $sep = "\n";

    while (($ip, $path) = each(%$statics)) {
	if (!open($rfh, '<', $path)) {
	    die ("cannot read '$path' : $!");
	}

	while (defined($line = <$rfh>)) {
	    chomp($line);

	    $line =~ s/0\.0\.0\.0/$ip/;

	    printf($wfh "%s    %s", $sep, $line);

	    $sep = ",\n";
	}

	close($rfh);
    }

    printf($wfh "\n]\n");

    close($wfh);

    return $dest;
}

sub setup_nodes
{
    my ($nodes, $genesis) = @_;
    my ($dest, $input, $output, @ips, $fleet, $cmd, $statics);

    $dest = tempdir(DIR => $PRIVATE);
    $input = $DEPLOY_PATH . '/genesis.json';
    $output = $DEPLOY_PATH . '/static-nodes.txt';

    @ips = keys(%$nodes);
    $fleet = Minion::StaticFleet->new([ map {$nodes->{$_}->{'worker'}} @ips ]);

    if (grep { $_->exitstatus() != 0 }
	$fleet->send([ $genesis ], TARGETS => $input)->waitall()) {
	die ('cannot send genesis to workers');
    }

    $cmd = [ 'deploy-poa-worker' , 'setup' , $input, $output ];
    if ($RUNNER->run($fleet, $cmd)->wait() != 0) {
	die ('cannot generate testnet');
    }

    $statics = { map { $_ => $dest . '/' . $_ . '.txt' } @ips };
    if (grep { $_->exitstatus() != 0 }
	$fleet->recv(
	    [ $output ],
	    TARGETS => [ map { $statics->{$_} } @ips ]
	)->waitall()) {
	die ('cannot receive static nodes from workers');
    }

    if (grep { $_->exitstatus() != 0 }
	$fleet->execute([ 'rm', $input, $output ])->waitall()) {
	die ('cannot cleanup workers');
    }

    return aggregate_nodes($statics);
}

sub setup_network
{
    my ($nodes, $statics) = @_;
    my ($fleet, $input, $cmd);

    $fleet = Minion::StaticFleet->new([ map {$_->{'worker'}} values(%$nodes)]);

    $input = $DEPLOY_PATH . '/static-nodes.json';

    if (grep { $_->exitstatus() != 0 }
	$fleet->send([ $statics ], TARGETS => $input)->waitall()) {
	die ('cannot send statics to workers');
    }

    $cmd = [ 'deploy-poa-worker' , 'finalize' , $input ];
    if ($RUNNER->run($fleet, $cmd)->wait() != 0) {
	die ('cannot finalize testnet configuration');
    }

    if (grep { $_->exitstatus() != 0 }
	$fleet->execute([ 'rm', $input ])->waitall()) {
	die ('cannot cleanup workers');
    }
}


# Main function ---------------------------------------------------------------

sub deploy_poa
{
    my ($nodes, $accounts, $genworker, $genesis, $statics);

    if (!(-f $ROLES_PATH)) {
	return 1;
    }

    $nodes = get_nodes($ROLES_PATH);
    $genworker = (values(%$nodes))[0]->{'worker'};

    prepare_accounts($nodes);

    $accounts = gather_accounts($nodes);

    $genesis = generate_genesis($genworker, $accounts);

    $statics = setup_nodes($nodes, $genesis);

    setup_network($nodes, $statics);

    generate_chainfile($CHAIN_PATH, $nodes, $accounts);

    return 1;
}


deploy_poa();
__END__
