package behave_algorand;

use strict;
use warnings;

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

my $fleet = $_;
my ($role) = @ARGV;
my (@ips, $worker, $ip, $fh, $actors);

$actors = $ENV{MINION_SHARED} . '/algorand-actors';

if (!grep { $role eq $_ } qw(node client)) {
    die ("unknown role '$role'");
}

foreach $worker ($fleet->members()) {
    if ($worker->can('public_ip')) {
	push(@ips, $worker->public_ip());
    } elsif ($worker->can('host')) {
	push(@ips, $worker->host());
    } else {
	die ("cannot get ip of worker '$worker' for role '$role'");
    }
}

if (!open($fh, '>>', $actors)) {
    die ("cannot open actors file '$actors'");
}

foreach $ip (@ips) {
    printf($fh "%s:%s\n", $ip, $role);
}

close($fh);


1;
__END__
