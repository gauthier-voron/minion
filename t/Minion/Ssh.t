use lib qw(. t/);
use strict;
use warnings;

use Test::More;

use Minion::TestConfig;
use Minion::TestWorker;

BEGIN
{
    use_ok('Minion::Ssh');
};


# Test configuration ==========================================================

my ($ntest, %tests, $config, $name, $routine, $worker0, $worker1);

# Where to find the configuration for the tests of this file.
#
my $CONFIG_PATH = '.config/test-ssh.conf';

# The intended number of test.
#
$ntest = 1;

# The generic worker test set.
#
%tests = Minion::TestWorker::tests();

# The configuration once loaded.
#
$config = Minion::TestConfig->load($CONFIG_PATH);


# Test cases ==================================================================

# Ssh from config host --------------------------------------------------------

SKIP: {
    my %params = $config->params(sub {skip(shift(), scalar(%tests))}, 'host');

    $worker0 = Minion::Ssh->new($params{'host'});
    $worker1 = Minion::Ssh->new($params{'host'});
    $ntest += scalar(%tests);

    while (($name, $routine) = each(%tests)) {
	subtest "ssh " . $name => sub { $routine->($worker0, $worker1) };
    }
}

# Ssh from config host + user + port ------------------------------------------

SKIP: {
    my %params = $config->params(sub { skip(shift(), scalar(%tests)) },
				 qw(host user port));

    $worker0 = Minion::Ssh->new(
	$params{'host'},
	USER => $params{'user'},
	PORT => $params{'port'}
	);
    $worker1 = Minion::Ssh->new(
	$params{'host'},
	USER => $params{'user'},
	PORT => $params{'port'}
	);
    $ntest += scalar(%tests);

    while (($name, $routine) = each(%tests)) {
	subtest "ssh user+port " . $name => sub {
	    $routine->($worker0, $worker1) };
    }
}


done_testing($ntest);


__END__
