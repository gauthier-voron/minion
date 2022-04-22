package behave_algorand;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray);

# Implicitely defined variables:
#
#   - $_    : a Minion::Fleet containing all the workers running this code.
#
#   - @_    : (
#
#              FLEET  => same as $_
#
#              RUNNER => the runner of this script
#
#             )
#
#   - @ARGV : a list of command line arguments given to the script.
#
#   - $ENV{MINION_FLEET}   : the name of the fleet to run this code on.
#
#   - $ENV{MINION_SHARED}  : the path to a directory to store shared data.
#
#   - $ENV{MINION_PRIVATE} : the path to a directory to store private data.
#

my $MINION_SHARED = $ENV{MINION_SHARED};        # Environment (setup by Runner)

my $DATA_DIR = $MINION_SHARED . '/algorand';     # Where to store things across
                                                 # Runner invocations

my $fleet = $_;
my ($number, @err);
my (@ips, $worker, $ip, $fh, $nodes);

GetOptionsFromArray(
    \@ARGV,
    'n|number=i' => \$number
    );

@err = @ARGV;

if (@err) {
    die ("unexpected argument '" . shift(@err) . "'");
}

$nodes = $ENV{MINION_SHARED} . '/algorand-nodes';

if (!defined($number)) {
    $number = 1;
}

if (!(-d $DATA_DIR) && !mkdir($DATA_DIR)) {
    die ("cannot create data directory: $!");
}

foreach $worker ($fleet->members()) {
    if ($worker->can('public_ip')) {
	push(@ips, $worker->public_ip());
    } elsif ($worker->can('host')) {
	push(@ips, $worker->host());
    } else {
	die ("cannot get ip of worker '$worker'");
    }
}

if (!open($fh, '>>', $nodes)) {
    die ("cannot open actors file '$nodes'");
}

foreach $ip (@ips) {
    printf($fh "%s:%d\n", $ip, $number);
}

close($fh);


1;
__END__
