use lib qw(. t/);
use strict;
use warnings;

use Test::More;

use Minion::TestConfig;
use Minion::TestWorker;

BEGIN
{
    use_ok('Minion::Aws::Fleet');
    use_ok('Minion::Aws::Instance');
};


# Test configuration ==========================================================

my ($ntest, %tests);

# Where to find the configuration for the tests of this file.
#
my $CONFIG_PATH = '.config/test-aws.conf';

# The configuration once loaded.
#
my $config = Minion::TestConfig->load($CONFIG_PATH);

# The intended number of test.
#
$ntest = 2;

# The generic worker test set.
#
%tests = Minion::TestWorker::tests();


# Test cases ==================================================================

# Instances of same fleet -----------------------------------------------------

SKIP: {
    my %params = $config->params(sub {skip(shift(), scalar(%tests))}, qw(
        default_image default_type default_user default_price default_secgroup
        default_ssh
    ));

    my ($name, $routine, $fleet, $worker0, $worker1);

    $fleet = Minion::Aws::Fleet->launch(
	$params{'default_image'},
	$params{'default_type'},
	KEY      => $params{'default_ssh'},
	PRICE    => $params{'default_price'},
	SECGROUP => $params{'default_secgroup'},
	SIZE     => 2,
	TIME     => 600,
	USER     => $params{'default_user'}
	)->get();

    while (grep { $_->execute(['true'], STDERR => '/dev/null')->wait() != 0 }
	   $fleet->members()) {
	sleep(1);
    }

    ($worker0, $worker1) = $fleet->members();

    $ntest += scalar(%tests);

    while (($name, $routine) = each(%tests)) {
	subtest "aws same fleet " . $name => sub {
	    $routine->($worker0, $worker1) };
    }

    $fleet->cancel()->get();
}

# Instances of distant fleets -------------------------------------------------

SKIP: {
    my %params = $config->params(sub {skip(shift(), scalar(%tests))}, qw(
        default_image default_type default_user default_price default_secgroup
        default_ssh alt_image alt_type alt_user alt_price alt_secgroup
        alt_ssh alt_region
    ));

    my ($name, $routine, $fleet0, $fleet1, $worker0, $worker1);

    $fleet0 = Minion::Aws::Fleet->launch(
	$params{'default_image'},
	$params{'default_type'},
	KEY      => $params{'default_ssh'},
	PRICE    => $params{'default_price'},
	SECGROUP => $params{'default_secgroup'},
	SIZE     => 1,
	TIME     => 600,
	USER     => $params{'default_user'}
	)->get();

    $fleet1 = Minion::Aws::Fleet->launch(
	$params{'alt_image'},
	$params{'alt_type'},
	KEY      => $params{'alt_ssh'},
	PRICE    => $params{'alt_price'},
	REGION   => $params{'alt_region'},
	SECGROUP => $params{'alt_secgroup'},
	SIZE     => 1,
	TIME     => 600,
	USER     => $params{'alt_user'}
	)->get();

    while (grep { $_->execute(['true'], STDERR => '/dev/null')->wait() != 0 }
	   ($fleet0->members(), $fleet1->members())) {
	sleep(1);
    }

    ($worker0) = $fleet0->members();
    ($worker1) = $fleet1->members();

    $ntest += scalar(%tests);

    while (($name, $routine) = each(%tests)) {
	subtest "aws distant fleets " . $name => sub {
	    $routine->($worker0, $worker1) };
    }

    $fleet0->cancel()->get();
    $fleet1->cancel()->get();
}

# Instances properties --------------------------------------------------------

SKIP: {
    my %params = $config->params(sub {skip(shift(), scalar(%tests))}, qw(
        default_image default_type default_user default_price default_secgroup
        default_ssh default_region
    ));

    my ($name, $routine, $fleet, $instance);

    $fleet = Minion::Aws::Fleet->launch(
	$params{'default_image'},
	$params{'default_type'},
	KEY      => $params{'default_ssh'},
	PRICE    => $params{'default_price'},
	SECGROUP => $params{'default_secgroup'},
	SIZE     => 1,
	TIME     => 600,
	USER     => $params{'default_user'}
	)->get();

    ($instance) = $fleet->members();

    $ntest += 1;
    
    subtest 'aws instance builtin properties' => sub {
	plan tests => 7;

	is($instance->get('aws:id'),         $instance->id());
	is($instance->get('aws:public-ip'),  $instance->public_ip());
	is($instance->get('aws:private-ip'), $instance->private_ip());
	is($instance->get('aws:region'),     $params{'default_region'});
	is($instance->get('ssh:host'),       $instance->public_ip());
	is($instance->get('ssh:user'),       $params{'default_user'});
	is($instance->get('ssh:port'),       22);
    };

    $fleet->cancel()->get();
}


done_testing($ntest);


__END__
