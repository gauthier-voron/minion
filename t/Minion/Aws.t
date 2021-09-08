use lib qw(t/);
use strict;
use warnings;

use Test::More tests => 10;

use Minion::TestConfig;

BEGIN
{
    use_ok('Minion::Aws');
    use_ok('Minion::Aws::Cli');
    use_ok('Minion::Aws::Image');
    use_ok('Minion::System::Future');
};


# Test configuration ==========================================================

# Where to find the configuration for the tests of this file.
#
my $CONFIG_PATH = '.config/test-aws.conf';

# The configuration once loaded.
#
my $config = Minion::TestConfig->load($CONFIG_PATH);


# Test cases ==================================================================

# find_images -----------------------------------------------------------------

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1); }, qw(
        default_image default_region
    ));

    subtest 'find images from exact name' => sub {
	plan tests => 6;

	my ($image, $name, $ret, $images);

	$image = Minion::Aws::Image->new($params{'default_image'});
	$name = $image->name();

	$ret = Minion::Aws::find_images(
	    $name,
	    REGIONS => [ $params{'default_region' } ]
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$images = $ret->get();

	ok($images);
	is(ref($images), 'HASH');
	ok($images->{$params{'default_region'}});
	is($images->{$params{'default_region'}}->name(), $name);
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1); }, qw(
        default_image default_region
    ));

    subtest 'find images from exact description' => sub {
	plan tests => 6;

	my ($image, $description, $ret, $images);

	$image = Minion::Aws::Image->new($params{'default_image'});
	$description = $image->description();

	$ret = Minion::Aws::find_images(
	    $description,
	    REGIONS => [ $params{'default_region' } ]
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$images = $ret->get();

	ok($images);
	is(ref($images), 'HASH');
	ok($images->{$params{'default_region'}});
	is($images->{$params{'default_region'}}->description(), $description);
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1); }, qw(
        default_region
    ));

    subtest 'find images from pattern' => sub {
	plan tests => 6;

	my ($ret, $images, $image);

	$ret = Minion::Aws::find_images(
	    '*ubuntu*20.04*amd64*server*',
	    REGIONS => [ $params{'default_region' } ]
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$images = $ret->get();

	ok($images);
	is(ref($images), 'HASH');

	$image = $images->{$params{'default_region'}};

	ok($image);
	like($image->name(), qr/^.*ubuntu.*20\.04.*amd64.*server.*$/);
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1); }, qw(
        default_region alt_region
    ));

    subtest 'find images from pattern in all regions' => sub {
	plan tests => 7;

	my ($ret, $images);

	$ret = Minion::Aws::find_images('*ubuntu*20.04*amd64*server*');

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$images = $ret->get();

	ok($images);
	is(ref($images), 'HASH');
	ok($images->{$params{'default_region'}});
	ok($images->{$params{'alt_region'}});

	ok(!grep { $_->name() !~ /^.*ubuntu.*20\.04.*amd64.*server.*$/ }
	    values(%$images));
     };
}


# find_secgroups --------------------------------------------------------------

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1); }, qw(
        default_secgroup default_region
    ));

    subtest 'find secgroup by name' => sub {
	plan tests => 5;

	my ($name, $ret, $secgroups);

	$name = Minion::Aws::Cli->describe_security_groups(
	    IDS   => [ $params{'default_secgroup'} ],
	    QUERY => 'SecurityGroups[0].GroupName'
	    )->get();

	$ret = Minion::Aws::find_secgroups(
	    $name,
	    REGIONS => [ $params{'default_region'} ]
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$secgroups = $ret->get();

	ok($secgroups);
	is(ref($secgroups), 'HASH');
	is_deeply($secgroups, {
	    $params{'default_region'} => $params{'default_secgroup'}
	});
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1); }, qw(
        default_secgroup default_region alt_region
    ));

    subtest 'find secgroups by name' => sub {
	plan tests => 8;

	my ($name, $ret, $secgroups);

	$name = Minion::Aws::Cli->describe_security_groups(
	    IDS   => [ $params{'default_secgroup'} ],
	    QUERY => 'SecurityGroups[0].GroupName'
	    )->get();

	$ret = Minion::Aws::find_secgroups($name);

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$secgroups = $ret->get();

	ok($secgroups);
	is(ref($secgroups), 'HASH');
	ok(scalar(%$secgroups) >= 2);
	ok(grep { $_ eq $params{'default_region'} } keys(%$secgroups));
	ok(grep { $_ eq $params{'alt_region'} } keys(%$secgroups));
	is($secgroups->{$params{'default_region'}},
	   $params{'default_secgroup'});
     };
}


__END__
