package behave_solana;


use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray);


my $FLEET = $_;                        # Global parameter (setup by the Runner)
my $MINION_SHARED = $ENV{MINION_SHARED};        # Environment (setup by Runner)

my $DATA_DIR = $MINION_SHARED . '/solana';  # Where to store things across
                                                 # Runner invocations

my $ROLES_PATH = $DATA_DIR . '/behaviors.txt';           # Behaviors of workers

my ($number, @err);                                     # Arguments and options

my ($worker, $ip, $text, $fh);


# Parse options and check for sanity ------------------------------------------

GetOptionsFromArray(
    \@ARGV,
    'n|number=i' => \$number
    );

@err = @ARGV;

if (@err) {
    die ("unexpected argument '" . shift(@err) . "'");
}

if (!defined($number)) {
    $number = 1;
}


# Create behavior data directory if needed ------------------------------------

if (!(-d $DATA_DIR) && !mkdir($DATA_DIR)) {
    die ("cannot create data directory: $!");
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

    $text .= sprintf("%s:%d\n", $ip, $number);
}


if (!open($fh, '>>', $ROLES_PATH)) {
    die ("cannot open roles file '$ROLES_PATH'");
}

printf($fh "%s", $text);

close($fh);


1;
__END__
