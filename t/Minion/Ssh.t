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


my $CONFIG_PATH = '.config/test-ssh.conf';
my ($ntest, %tests, $config, $name, $routine, $worker0, $worker1);

$ntest = 1;
%tests = Minion::TestWorker::tests();
$config = Minion::TestConfig->load($CONFIG_PATH);



# Ssh from config host --------------------------------------------------------

SKIP: {
    skip("no config file at '$CONFIG_PATH'", scalar(%tests))
	if (!defined($config));
    skip("no 'host' parameter in '$CONFIG_PATH'", scalar(%tests))
	if (!$config->has('host'));

    $worker0 = Minion::Ssh->new($config->get('host'));
    $worker1 = Minion::Ssh->new($config->get('host'));
    $ntest += scalar(%tests);

    while (($name, $routine) = each(%tests)) {
	subtest "ssh " . $name => sub { $routine->($worker0, $worker1) };
    }
}

# Ssh from config host + user + port ------------------------------------------

SKIP: {
    skip("no config file at '$CONFIG_PATH'", scalar(%tests))
	if (!defined($config));
    skip("no 'host' parameter in '$CONFIG_PATH'", scalar(%tests))
	if (!$config->has('host'));
    skip("no 'user' parameter in '$CONFIG_PATH'", scalar(%tests))
	if (!$config->has('user'));
    skip("no 'port' parameter in '$CONFIG_PATH'", scalar(%tests))
	if (!$config->has('port'));

    $worker0 = Minion::Ssh->new(
	$config->get('host'),
	USER => $config->get('user'),
	PORT => $config->get('port')
	);
    $worker1 = Minion::Ssh->new(
	$config->get('host'),
	USER => $config->get('user'),
	PORT => $config->get('port')
	);
    $ntest += scalar(%tests);

    while (($name, $routine) = each(%tests)) {
	subtest "ssh user+port " . $name => sub {
	    $routine->($worker0, $worker1) };
    }
}


done_testing($ntest);


__END__
