package behave_diablo;


use strict;
use warnings;

use File::Copy;
use Getopt::Long qw(GetOptionsFromArray);


my $FLEET = $_;                        # Global parameter (setup by the Runner)
my $MINION_SHARED = $ENV{MINION_SHARED};        # Environment (setup by Runner)

my $DATA_DIR = $MINION_SHARED . '/diablo';       # Where to store things across
                                                 # Runner invocations

my $ROLES_PATH = $DATA_DIR . '/behaviors.txt';           # Behaviors of workers
my $WORKLOAD_PATH = $DATA_DIR . '/workload.yaml';          # Benchmark workload

my ($role, $workload, $number, @err);                   # Arguments and options

my ($worker, $ip, $text, $fh);


# Parse options and check for sanity ------------------------------------------

GetOptionsFromArray(
    \@ARGV,
    'n|number=i' => \$number
    );

($role, $workload, @err) = @ARGV;

if (@err) {
    die ("unexpected argument '" . shift(@err) . "'");
} elsif (!grep { $role eq $_ } qw(primary secondary)) {
    die ("unknown role '$role'");
}

if ($role eq 'primary') {
    if (!defined($workload)) {
	die ('missing workload operand');
    }
} elsif (defined($workload)) {
    die ("unexpected operand '$workload'");
}

if (!defined($number)) {
    $number = 1;
} elsif ($role eq 'primary') {
    die ("invalid option '--number' used with 'primary' role");
}


# Create behavior data directory if needed ------------------------------------

if (!(-d $DATA_DIR) && !mkdir($DATA_DIR)) {
    die ("cannot create data directory: $!");
}


# Copy workload file if supplied ----------------------------------------------

if (defined($workload) && !copy($workload, $WORKLOAD_PATH)) {
    die ("cannot copy workload file '$workload'");
}


# Fetch nodes IP and put them in the data directory ---------------------------

$text = '';

foreach $worker ($FLEET->members()) {
    if ($worker->can('public_ip')) {
	$ip = $worker->public_ip();
    } elsif ($worker->can('host')) {
	$ip = $worker->host();
    } else {
	die ("cannot get ip of worker '$worker'");
    }

    $text .= sprintf("%s:%s:%d\n", $ip, $role, $number);
}


if (!open($fh, '>>', $ROLES_PATH)) {
    die ("cannot open roles file '$ROLES_PATH'");
}

printf($fh "%s", $text);

close($fh);


1;
__END__
