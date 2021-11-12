package deploy;

use strict;
use warnings;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};


# Remove the previous deployment directory to start from a clean one.
#

$FLEET->execute(['rm', '-rf', 'deploy'], STDERRS => '/dev/null')->waitall();

# Deploy the blockchains that have been enabled by 'behave-*' scripts.
# Do nothing if not enabled.
#

if ($RUNNER->run($FLEET, [ 'deploy-algorand' ])->wait() != 0) {
    die ("failed to deploy algorand");
}

if ($RUNNER->run($FLEET, [ 'deploy-quorum-ibft' ])->wait() != 0) {
    die ("failed to deploy quorum-ibft");
}

if ($RUNNER->run($FLEET, [ 'deploy-quorum-raft' ])->wait() != 0) {
    die ("failed to deploy quorum-raft");
}

# Deploy diablo at the very end as it might need some configuration generated
# by the deployment of other blockchains.
#

if ($RUNNER->run($FLEET, [ 'deploy-diablo' ])->wait() != 0) {
    die ("failed to deploy diablo");
}


1;
__END__
