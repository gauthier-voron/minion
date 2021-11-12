package diablo;

use strict;
use warnings;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};

my ($action, @err) = @ARGV;


if (!defined($action)) {
    die ("missing action operand");
} elsif (@err) {
    die ("unexpected operand '" . shift(@err) . "'");
}


# Start the Diablo primary node first and when confirmation that it is running,
# then start the diablo secondaries.
#
sub start_nodes
{
    my ($proc);

    $proc = $RUNNER->run($FLEET, [ 'diablo-worker', 'primary', 'start' ]);
    if ($proc->wait() != 0) {
	die ("cannot start diablo primary node");
    }

    $proc = $RUNNER->run($FLEET, [ 'diablo-worker', 'secondary', 'start' ]);
    if ($proc->wait() != 0) {
	$RUNNER->run($FLEET, [ 'diablo-worker', 'primary', 'stop' ])->wait();
	die ("cannot start diablo primary node");
    }

    return 1;
}

# Stop the Diablo primary and secondary nodes.
#
sub stop_nodes
{
    my ($proc);

    $proc = $RUNNER->run($FLEET, [ 'diablo-worker', 'any', 'stop' ]);
    if ($proc->wait() != 0) {
	die ("cannot stop diablo nodes");
    }

    return 1;
}

# Wait for the Diablo primary and secondary nodes.
#
sub wait_nodes
{
    my ($proc);

    $proc = $RUNNER->run($FLEET, [ 'diablo-worker', 'any', 'wait' ]);
    if ($proc->wait() != 0) {
	die ("cannot wait diablo nodes");
    }

    return 1;
}


if ($action eq 'start') {
    start_nodes();
} elsif ($action eq 'stop') {
    stop_nodes();
} elsif ($action eq 'wait') {
    wait_nodes();
} else {
    die ("unknown action '$action'");
}
__END__
