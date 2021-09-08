use lib qw(t/);
use strict;
use warnings;

use Test::More tests => 20;

use Minion::TestConfig;

BEGIN
{
    use_ok('Minion::Fleet');
    use_ok('Minion::Worker');
    use_ok('Minion::Aws::Fleet');
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
    my %params = $config->params(sub { skip(shift(), 1) }, qw(default_region));

    subtest 'new fleet' => sub {
	plan tests => 5;

	my ($fleet);

	$fleet = Minion::Aws::Fleet->new('sfr-0000000000');

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));
	is($fleet->id(), 'sfr-0000000000');
	is($fleet->region(), $params{'default_region'});
	is($fleet->user(), undef);
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'new fleet with invalid id' => sub {
    plan tests => 1;

    dies_ok(sub { Minion::Aws::Fleet->new('invalid-id'); });
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_region
    ));

    subtest 'new fleet with attributes' => sub {
	plan tests => 11;

	my ($image, $fleet);

	$image = Minion::Aws::Image->new('ami-000000000');

	ok($image);

	$fleet = Minion::Aws::Fleet->new(
	    'sfr-0000000000',
	    IMAGE    => $image,
	    KEY      => 'my-key',
	    PRICE    => 0.0,
	    REGION   => 'no-where-0',
	    SECGROUP => 'sg-000000000',
	    SIZE     => 10,
	    TYPE     => 'x0.none'
	    );

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));
	is($fleet->id(), 'sfr-0000000000');
	is($fleet->image(), $image);
	is($fleet->key(), 'my-key');
	is($fleet->price(), 0.0);
	is($fleet->region(), 'no-where-0');
	is($fleet->secgroup(), 'sg-000000000');
	is($fleet->size(), 10);
	is($fleet->type(), 'x0.none');
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_region default_type
    ));

    subtest 'launch fleet' => sub {
	plan tests => 11;

	my ($ret, $fleet);

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'}
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));
	ok($fleet->id());
	ok($fleet->image());
	is($fleet->image()->id(), $params{'default_image'});
	is($fleet->region(), $params{'default_region'});
	is($fleet->type(), $params{'default_type'});

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_region default_type default_secgroup
    ));

    subtest 'launch fleet with parameters' => sub {
	plan tests => 15;

	my ($ret, $fleet);

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    KEY      => 'my-key',
	    PRICE    => 0.042,
	    REGION   => $params{'default_region'},
	    SECGROUP => $params{'default_secgroup'},
	    SIZE     => 2
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));
	ok($fleet->id());
	ok($fleet->image());
	is($fleet->image()->id(), $params{'default_image'});
	is($fleet->type(), $params{'default_type'});
	is($fleet->key(), 'my-key');
	is($fleet->price(), 0.042);
	is($fleet->region(), $params{'default_region'});
	is($fleet->secgroup(), $params{'default_secgroup'});
	is($fleet->size(), 2);

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_region default_type default_secgroup
    ));

    subtest 'launch fleet with parameters no update' => sub {
	plan tests => 19;

	my ($ret, $fleet, $err, $log);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    ERR      => \$err,
	    KEY      => 'my-key',
	    LOG      => \$log,
	    PRICE    => 0.042,
	    REGION   => $params{'default_region'},
	    SECGROUP => $params{'default_secgroup'},
	    SIZE     => 2
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	is($err, '');
	isnt($log, '');

	$err = '';
	$log = '';

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));
	ok($fleet->id());
	ok($fleet->image());
	is($fleet->image()->id(), $params{'default_image'});
	is($fleet->type(), $params{'default_type'});
	is($fleet->key(), 'my-key');
	is($fleet->price(), 0.042);
	is($fleet->region(), $params{'default_region'});
	is($fleet->secgroup(), $params{'default_secgroup'});
	is($fleet->size(), 2);

	is($err, '');
	is($log, '');

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_region default_type default_secgroup
    ));

    subtest 'launch fleet get causes update' => sub {
	plan tests => 21;

	my ($ret, $fleet, $id, $err, $log);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    KEY      => 'my-key',
	    PRICE    => 0.042,
	    REGION   => $params{'default_region'},
	    SECGROUP => $params{'default_secgroup'},
	    SIZE     => 2
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	$id = $fleet->id();

	$fleet = Minion::Aws::Fleet->new(
	    $id,
	    ERR => \$err,
	    LOG => \$log
	    );

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));
	is($fleet->id(), $id);
	is($fleet->region(), $params{'default_region'});

	is($err, '');
	is($log, '');

	$err = '';
	$log = '';

	ok($fleet->image());
	is($fleet->image()->id(), $params{'default_image'});
	is($fleet->type(), $params{'default_type'});
	is($fleet->key(), 'my-key');
	is($fleet->price(), 0.042);
	is($fleet->secgroup(), $params{'default_secgroup'});
	is($fleet->size(), 2);

	is($err, '');
	isnt($log, '');

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_type
    ));

    subtest 'launch fleet with forced update' => sub {
	plan tests => 17;

	my ($ret, $fleet, $id, $err, $log);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    KEY      => 'my-key',
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	$id = $fleet->id();

	$fleet = Minion::Aws::Fleet->new(
	    $id,
	    ERR => \$err,
	    KEY => 'wrong-key',
	    LOG => \$log
	    );

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));
	is($fleet->key(), 'wrong-key');

	is($err, '');
	is($log, '');

	$err = '';
	$log = '';

	$ret = $fleet->update();

	ok($ret);
	ok(Minion::System::Future->comply($ret));
	ok($ret->get());

	is($err, '');
	isnt($log, '');

	is($fleet->key(), 'my-key');

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_type
    ));

    subtest 'fleet status' => sub {
	plan tests => 18;

	my ($ret, $fleet, $status, $err, $log, $i);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    ERR => \$err,
	    LOG => \$log
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	for ($i = 0; $i < 2; $i++) {
	    $err = '';
	    $log = '';

	    $ret = $fleet->status();

	    ok($ret);
	    ok(Minion::System::Future->comply($ret));

	    $status = $ret->get();

	    ok($status);
	    is(ref($status), '');
	    is($err, '');
	    isnt($log, '');
	}

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_type
    ));

    subtest 'fleet history' => sub {
	plan tests => 17;

	my ($ret, $fleet, $err, $log, $hist);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    ERR => \$err,
	    LOG => \$log
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	$err = '';
	$log = '';

	$ret = $fleet->history();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$hist = $ret->get();

	ok($hist);
	is(ref($hist), 'ARRAY');
	is($err, '');
	isnt($log, '');

	while (scalar(@$hist) == 0) {
	    $hist = $fleet->history()->get();
	}

	ok($hist->[0]);
	like($hist->[0]->time(), qr/^\d+$/);
	is($hist->[0]->type(), 'submitted');
	is($hist->[0]->message(), undef);

	while (!grep { defined($_->message()) } @$hist) {
	    $hist = $fleet->history()->get();
	}

	ok(grep {defined($_->message()) && (ref($_->message()) eq '')} @$hist);

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_type
    ));

    subtest 'fleet instances' => sub {
	plan tests => 14;

	my ($ret, $fleet, $err, $log, $insts);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    ERR  => \$err,
	    LOG  => \$log,
	    SIZE => 3
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	$err = '';
	$log = '';

	$ret = $fleet->instances();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$insts = $ret->get();

	ok($insts);
	is(ref($insts), 'ARRAY');
	is($err, '');
	isnt($log, '');

	while (scalar(@$insts) == 0) {
	    $insts = $fleet->instances()->get();
	}

	ok($insts->[0]);
	ok(!grep { !Minion::Worker->comply($_) } @$insts);

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_type
    ));

    subtest 'fleet members' => sub {
	plan tests => 10;

	my ($ret, $fleet, $err, $log, @members);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    ERR  => \$err,
	    LOG  => \$log,
	    SIZE => 3
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	$err = '';
	$log = '';

	@members = $fleet->members();

	is(scalar(@members), 3);
	ok(!grep { !Minion::Worker->comply($_) } @members);
	is($err, '');
	isnt($log, '');

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

TODO: {
    local $TODO = "Need a global AWS object deduplicator";

    my %params = $config->params(sub { todo_skip(shift(), 1) }, qw(
        default_image default_type
    ));

    subtest 'fleet members are cached instances' => sub {
	plan tests => 10;

	my ($ret, $fleet, $err, $log, $insts, @members);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    ERR  => \$err,
	    LOG  => \$log,
	    SIZE => 3
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	$insts = $fleet->instances()->get();

	while (scalar(@$insts) != 3) {
	    $insts = $fleet->instances()->get();
	}

	$err = '';
	$log = '';

	@members = $fleet->members();

	is(scalar(@members), 3);
	is($err, '');
	is($log, '');
	is_deeply(\@members, $insts);

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        default_image default_type
    ));

    subtest 'fleet user/region transmits to members' => sub {
	plan tests => 9;

	my ($ret, $fleet, $err, $log, @members);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'default_image'},
	    $params{'default_type'},
	    SIZE => 3,
	    USER => 'my-test-user'
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	@members = $fleet->members();

	is(scalar(@members), 3);
	ok(!grep { $_->user() ne $fleet->user() } @members);
	ok(!grep { $_->region() ne $fleet->region() } @members);

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = $config->params(sub { skip(shift(), 1) }, qw(
        alt_image alt_type alt_region
    ));

    subtest 'remote fleet user/region transmits to members' => sub {
	plan tests => 9;

	my ($ret, $fleet, $err, $log, @members);

	$err = '';
	$log = '';

	$ret = Minion::Aws::Fleet->launch(
	    $params{'alt_image'},
	    $params{'alt_type'},
	    REGION => $params{'alt_region'},
	    SIZE   => 3,
	    USER   => 'my-test-user'
	    );

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$fleet = $ret->get();

	ok($fleet);
	ok(Minion::Fleet->comply($fleet));

	@members = $fleet->members();

	is(scalar(@members), 3);
	ok(!grep { $_->user() ne $fleet->user() } @members);
	ok(!grep { $_->region() ne $fleet->region() } @members);

	$ret = $fleet->cancel();

	ok($ret);
	ok(Minion::System::Future->comply($ret));

	$ret->get();
     };
}



__END__
