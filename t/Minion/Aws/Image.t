use lib qw(t/);
use strict;
use warnings;

use Test::More tests => 20;

use Minion::TestConfig;

BEGIN
{
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


# Test utilities ==============================================================

# Try to execute the given routine.
# If it makes the program die then pass the test.
# Otherwise, fail the test.
#
sub dies_ok
{
    my ($routine, @args) = @_;

    eval {
	$routine->();
    };

    if (@args) {
	ok($@, @args);
    } else {
	ok($@);
    }
}


# Test cases ==================================================================

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_region
    ));

    subtest 'new image' => sub {
	plan tests => 3;

	my ($image);

	$image = Minion::Aws::Image->new($params{'default_image'});

	ok($image);
	is($image->id(), $params{'default_image'});
	is($image->region(), $params{'default_region'});
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    subtest 'new image with invalid id' => sub {
	plan tests => 1;

	my ($image);

	dies_ok(sub { $image = Minion::Aws::Image->new('invalid-id'); });
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image with name and description' => sub {
	plan tests => 5;

	my ($image, $err, $log);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    DESCRIPTION => 'my-description',
	    ERR         => \$err,
	    LOG         => \$log,
	    NAME        => 'my-name'
	    );

	ok($image);
	is($image->name(), 'my-name');
	is($image->description(), 'my-description');
	is($err, '');
	is($log, '');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image get name and description' => sub {
	plan tests => 5;

	my ($image, $err, $log);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log
	    );

	ok($image);
	ok($image->name());
	ok($image->description());
	is($err, '');
	isnt($log, '');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image update name and description' => sub {
	plan tests => 8;

	my ($image, $err, $log, $ret);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    DESCRIPTION => 'my-description',
	    ERR         => \$err,
	    LOG         => \$log,
	    NAME        => 'my-name'
	    );

	ok($image);

	$ret = $image->update();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();

	ok($ret);
	is($err, '');
	isnt($log, '');

	isnt($image->name(), 'my-name');
	isnt($image->description(), 'my-description');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image status' => sub {
	plan tests => 6;

	my ($image, $err, $log, $ret, $status);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log
	    );

	ok($image);

	$ret = $image->status();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$status = $ret->get();

	is($status, 'available');
	is($err, '');
	isnt($log, '');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image copy same region' => sub {
	plan tests => 11;

	my ($image, $err, $log, $ret, $copy);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    );

	ok($image);

	$ret = $image->copy('minion-test-newname');

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	is($err, '');
	isnt($log, '');

	is($copy->name(), 'minion-test-newname');
	is($copy->region(), $image->region());
	is($copy->status()->get(), 'available');

	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image copy same region with description' => sub {
	plan tests => 13;

	my ($image, $err, $log, $ret, $copy);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    );

	ok($image);

	$ret = $image->copy(
	    'minion-test-newname',
	    DESCRIPTION => 'minion-test-description'
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	is($err, '');
	isnt($log, '');

	$log = '';

	is($copy->name(), 'minion-test-newname');
	is($copy->description(), 'minion-test-description');
	is($copy->region(), $image->region());
	is($log, '');

	is($copy->status()->get(), 'available');

	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image copy no wait same region' => sub {
	plan tests => 12;

	my ($image, $err, $log, $ret, $copy, $status);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    );

	ok($image);

	$ret = $image->copy(
	    'minion-test-newname',
	    WAIT => 0
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	is($err, '');
	isnt($log, '');

	ok($copy->id());
	is($copy->region(), $image->region());

	while (1) {
	    $status = $copy->status()->get();

	    if (defined($status) && ($status ne 'pending')) {
		last;
	    }

	    sleep(1);
	}

	is($copy->status()->get(), 'available');
	is($copy->name(), 'minion-test-newname');

	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_image));

    subtest 'new image copy same region err/log' => sub {
	plan tests => 17;

	my ($image, $err, $log, $ret, $copy, $cerr, $clog);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    );

	ok($image);

	$cerr = '';
	$clog = '';
	$ret = $image->copy(
	    'minion-test-newname',
	    ERR         => \$cerr,
	    LOG         => \$clog,
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	ok($copy->id());
	is($copy->region(), $image->region());

	is($err, '');
	isnt($log, '');
	is($cerr, '');
	is($clog, '');

	is($copy->status()->get(), 'available');

	is($cerr, '');
	isnt($clog, '');

	$cerr = '';
	$clog = '';
	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();

	is($cerr, '');
	isnt($clog, '');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        alt_image alt_region
    ));

    subtest 'new image remote region' => sub {
	plan tests => 3;

	my ($image);

	$image = Minion::Aws::Image->new(
	    $params{'alt_image'},
	    REGION => $params{'alt_region'}
	    );

	ok($image);
	is($image->id(), $params{'alt_image'});
	is($image->region(), $params{'alt_region'});
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        alt_image alt_region
    ));

    subtest 'new remote image get name and description' => sub {
	plan tests => 5;

	my ($image, $err, $log);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'alt_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    REGION      => $params{'alt_region'}
	    );

	ok($image);
	ok($image->name());
	ok($image->description());
	is($err, '');
	isnt($log, '');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        alt_image alt_region
    ));

    subtest 'new remote image update name and description' => sub {
	plan tests => 8;

	my ($image, $err, $log, $ret);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'alt_image'},
	    DESCRIPTION => 'my-description',
	    ERR         => \$err,
	    LOG         => \$log,
	    NAME        => 'my-name',
	    REGION      => $params{'alt_region'}
	    );

	ok($image);

	$ret = $image->update();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();

	ok($ret);
	is($err, '');
	isnt($log, '');

	isnt($image->name(), 'my-name');
	isnt($image->description(), 'my-description');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        alt_image alt_region
    ));

    subtest 'new remote image status' => sub {
	plan tests => 6;

	my ($image, $err, $log, $ret, $status);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'alt_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    REGION      => $params{'alt_region'}
	    );

	ok($image);

	$ret = $image->status();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$status = $ret->get();

	is($status, 'available');
	is($err, '');
	isnt($log, '');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image alt_region
    ));

    subtest 'new image copy remote region' => sub {
	plan tests => 11;

	my ($image, $err, $log, $ret, $copy);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log
	    );

	ok($image);

	$ret = $image->copy(
	    'minion-test-newname',
	    REGION      => $params{'alt_region'}
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	is($err, '');
	isnt($log, '');

	is($copy->name(), 'minion-test-newname');
	is($copy->region(), $params{'alt_region'});
	is($copy->status()->get(), 'available');

	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image alt_region
    ));

    subtest 'new image copy no wait remote region' => sub {
	plan tests => 12;

	my ($image, $err, $log, $ret, $copy, $status);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    );

	ok($image);

	$ret = $image->copy(
	    'minion-test-newname',
	    REGION => $params{'alt_region'},
	    WAIT   => 0
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	is($err, '');
	isnt($log, '');

	ok($copy->id());
	is($copy->region(), $params{'alt_region'});

	while (1) {
	    $status = $copy->status()->get();

	    if (defined($status) && ($status ne 'pending')) {
		last;
	    }

	    sleep(1);
	}

	is($copy->status()->get(), 'available');
	is($copy->name(), 'minion-test-newname');

	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image alt_region
    ));

    subtest 'new image copy remote region err/log' => sub {
	plan tests => 17;

	my ($image, $err, $log, $ret, $copy, $cerr, $clog);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'default_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    );

	ok($image);

	$cerr = '';
	$clog = '';
	$ret = $image->copy(
	    'minion-test-newname',
	    ERR         => \$cerr,
	    LOG         => \$clog,
	    REGION      => $params{'alt_region'}
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	ok($copy->id());
	is($copy->region(), $params{'alt_region'});

	is($err, '');
	isnt($log, '');
	is($cerr, '');
	is($clog, '');

	is($copy->status()->get(), 'available');

	is($cerr, '');
	isnt($clog, '');

	$cerr = '';
	$clog = '';
	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();

	is($cerr, '');
	isnt($clog, '');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        alt_image alt_region default_region
    ));

    subtest 'new remote image copy default region' => sub {
	plan tests => 11;

	my ($image, $err, $log, $ret, $copy);

	$err = '';
	$log = '';
	$image = Minion::Aws::Image->new(
	    $params{'alt_image'},
	    ERR         => \$err,
	    LOG         => \$log,
	    REGION      => $params{'alt_region'}
	    );

	ok($image);

	$ret = $image->copy('minion-test-newname');

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$copy = $ret->get();

	ok($copy);
	is($err, '');
	isnt($log, '');

	is($copy->name(), 'minion-test-newname');
	is($copy->region(), $params{'default_region'});
	is($copy->status()->get(), 'available');

	$ret = $copy->delete();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret = $ret->get();
     };
}


__END__
