package behave_diablo;

use strict;
use warnings;

my $FLEET = $_;
my ($role) = @ARGV;
my (@ips, $worker, $ip, $fh, $actors);

$actors = $ENV{MINION_SHARED} . '/diablo-actors';

if (!grep { $role eq $_ } qw(primary secondary)) {
    die ("unknown role '$role'");
}

foreach $worker ($FLEET->members()) {
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
