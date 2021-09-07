use lib qw(t/);
use strict;
use warnings;

use File::Temp qw(tempfile);
use Test::More tests => 39;

use Minion::TestConfig;
use Minion::System::Pgroup;

BEGIN
{
    use_ok('Minion::Aws::Cli');
    use_ok('Minion::System::Future');
};


# Test configuration ==========================================================

# Where to find the configuration for the tests of this file.
#
my $CONFIG_PATH = '.config/test-aws.conf';

# The configuration once loaded.
#
my $config;

# Load the configuration from a file if it exists.
#
if (-f $CONFIG_PATH) {
    $config = Minion::TestConfig->load($CONFIG_PATH);

    if (!defined($config)) {
	exit(1);
    }
}

# Load the parameters with the specified names from the given configuration.
# If the configuration is not initialized or if one of the parameters cannot be
# found, then skip exactly one test.
# Otherwise, return a hash with the keys being the given names and the values
# being the associated parameters.
#
sub from_config
{
    my ($config, @names) = @_;
    my ($name, %params);

    if (!defined($config)) {
	skip('no aws config', 1);
    }

    foreach $name (@names) {
	if (!$config->has($name)) {
	    skip("no '$name' in aws config", 1);
	}

	$params{$name} = $config->get($name);
    }

    return %params;
}


# Test utilities ==============================================================

# A summary of the aws commands to test.
# Should always be at 1, except when working on this specific test file.
#
my %test_summary = (
    'request_spot_fleet'                  => 1,
    'cancel_spot_fleet_requests'          => 1,
    'describe_spot_fleet_requests'        => 1,
    'describe_spot_fleet_instances'       => 1,
    'describe_instances'                  => 1,
    'describe_spot_fleet_request_history' => 1,
    );

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

# Test if two lists contain the same elements, not necessary in the same order.
# If not, fail a test.
# Otherwise, pass a test.
#
sub contain_same
{
    my ($l0, $l1) = @_;
    my ($e);

    foreach $e (@$l0) {
	if (!grep { $e eq $_ } @$l1) {
	    fail();
	}
    }

    foreach $e (@$l1) {
	if (!grep { $e eq $_ } @$l0) {
	    fail();
	}
    }

    pass();
}

# Test if the given aws command correctly supports a logger.
# Given an aws command creation routine which takes one argument (the logger),
# test if the created aws command supports a logger.
# This routine is intended to be a subtest.
#
sub has_logger
{
    my ($routine) = @_;

    plan tests => 9;

    my ($cli, $logger);
    my ($fh, $path);

    $logger = '';
    $cli = $routine->(sub { if (defined($_[0])) { $logger .= shift(); } });

    ok($cli);
    $cli->wait();
    isnt($logger, '');


    $logger = '';
    $cli = $routine->(\$logger);

    ok($cli);
    $cli->wait();
    isnt($logger, '');


    ($fh, $path) = tempfile('minion-test.XXXXXX', SUFFIX => '.log');
    $cli = $routine->($fh);

    ok($cli);
    $cli->wait();
    close($fh); open($fh, '<', $path);
    ok(defined(<$fh>));
    close($fh); unlink($path);


    ($fh, $path) = tempfile('minion-test.XXXXXX', SUFFIX => '.log');
    printf($fh "First line\n");
    close($fh);
    $cli = $routine->($path);

    ok($cli);
    $cli->wait();
    open($fh, '<', $path);
    is(<$fh>, "First line\n");
    ok(defined(<$fh>));
    close($fh); unlink($path);
}


# Test cases ==================================================================

# request_spot_fleet ----------------------------------------------------------

SKIP: {
    my %params = from_config($config, qw(default_image default_type));

    subtest 'request_spot_fleet (simple)' => sub {
	if ($test_summary{'request_spot_fleet'}) {
	    plan tests => 7;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($request, $result);
	my ($id, $cancel);

	$request = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'}
	    );

	ok($request) or return;
	ok(Minion::System::Future->comply($request));
	is($request->out(), undef);

	$result = $request->get();

	ok(defined($result)) or return;
	is(ref($result), 'HASH') or return;

	$id = $result->{'SpotFleetRequestId'};

	ok(defined($id)) or return;
	like($id, qr/^sfr(-[0-9a-f]+)+$/) or return;

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
     };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(
        alt_image alt_type alt_price alt_ssh alt_region alt_secgroup alt_user
    ));

    subtest 'request_spot_fleet (options)' => sub {
	if ($test_summary{'request_spot_fleet'}) {
	    plan tests => 7;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($request, $result);
	my ($id, $cancel);

	$request = Minion::Aws::Cli->request_spot_fleet(
	    $params{'alt_image'},
	    $params{'alt_type'},
	    ERR      => sub {},
	    KEY      => $params{'alt_ssh'},
	    LOG      => sub {},
	    PRICE    => $params{'alt_price'},
	    REGION   => $params{'alt_region'},
	    SECGROUP => $params{'alt_secgroup'},
	    SIZE     => 5,
	    TIME     => 600,
	    );

	ok($request) or return;
	ok(Minion::System::Future->comply($request));
	is($request->out(), undef);

	$result = $request->get();

	ok(defined($result)) or return;
	is(ref($result), 'HASH') or return;

	$id = $result->{'SpotFleetRequestId'};

	ok(defined($id)) or return;
	like($id, qr/^sfr(-[0-9a-f]+)+$/) or return;

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests(
		 [ $id ],
		 REGION => $params{'alt_region'}
	    )->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(default_image default_type));

    subtest 'request_spot_fleet (invalid)' => sub {
	if ($test_summary{'request_spot_fleet'}) {
	    plan tests => 18;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($request);

	$request = Minion::Aws::Cli->request_spot_fleet(
	    'ami-000000000',
	    $params{'default_type'},
	    ERR => sub {}
	    );

	ok($request);
	ok(!defined($request->get()));

	dies_ok(sub { Minion::Aws::Cli->request_spot_fleet(
			  'Bad Format',
			  $params{'default_type'}
			  )});

	$request = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    'x0.unknown',
	    ERR => sub {}
	    );

	ok($request);
    	ok(!defined($request->get()));

	dies_ok(sub { Minion::Aws::Cli->request_spot_fleet(
			  $params{'default_image'},
			  'Bad Format'
			  )});

	ok(!defined(Minion::Aws::Cli->request_spot_fleet(
			$params{'default_image'},
			$params{'default_type'},
			PRICE => 0.000
		    )));

	ok(!defined(Minion::Aws::Cli->request_spot_fleet(
			$params{'default_image'},
			$params{'default_type'},
			PRICE => -10
		    )));

	dies_ok(sub { Minion::Aws::Cli->request_spot_fleet(
			  $params{'default_image'},
			  $params{'default_type'},
			  PRICE => 'Not A Number'
			  )});

	$request = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    ERR    => sub {},
	    REGION => 'no-where-1'
	    );

	ok($request);
    	ok(!defined($request->get()));

	dies_ok(sub { Minion::Aws::Cli->request_spot_fleet(
			  $params{'default_image'},
			  $params{'default_type'},
			  REGION => 'Bad Format'
			  )});

	ok(!defined(Minion::Aws::Cli->request_spot_fleet(
			$params{'default_image'},
			$params{'default_type'},
			SIZE => 0
		    )));
	
	ok(!defined(Minion::Aws::Cli->request_spot_fleet(
			$params{'default_image'},
			$params{'default_type'},
			SIZE => -10
		    )));

	dies_ok(sub { Minion::Aws::Cli->request_spot_fleet(
			  $params{'default_image'},
			  $params{'default_type'},
			  SIZE => 'Not A Number'
			  )});

	ok(!defined(Minion::Aws::Cli->request_spot_fleet(
			$params{'default_image'},
			$params{'default_type'},
			TIME => 0
		    )));

	ok(!defined(Minion::Aws::Cli->request_spot_fleet(
			$params{'default_image'},
			$params{'default_type'},
			TIME => -10
		    )));

	dies_ok(sub { Minion::Aws::Cli->request_spot_fleet(
			  $params{'default_image'},
			  $params{'default_type'},
			  TIME => 'Not A Number'
			  )});
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(default_type));

    subtest 'request_spot_fleet (err)' => sub {
	if ($test_summary{'request_spot_fleet'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->request_spot_fleet(
		    'ami-000000000',
		    $params{'default_type'},
		    ERR => $logger
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(default_type));

    subtest 'request_spot_fleet (log)' => sub {
	if ($test_summary{'request_spot_fleet'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->request_spot_fleet(
		    'ami-000000000',
		    $params{'default_type'},
		    ERR => sub {},
		    LOG => $logger
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}


# cancel_spot_fleet_requests --------------------------------------------------

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'cancel_spot_fleet_requests (simple)' => sub {
	if ($test_summary{'cancel_spot_fleet_requests'}) {
	    plan tests => 4;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $cancel);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$cancel = Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ]);

	ok($cancel) or diag("cannot cancel request '$id'"), return;
	ok(Minion::System::Future->comply($cancel));
	is($cancel->out(), undef);
	ok($cancel->get()) or diag("cannot cancel request '$id'"), return;
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(default_image default_type));

    subtest 'cancel_spot_fleet_requests (invalid)' => sub {
	if ($test_summary{'cancel_spot_fleet_requests'}) {
	    plan tests => 6;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($cancel, $result);

	$cancel = Minion::Aws::Cli->cancel_spot_fleet_requests(
	    [ 'sfr-00000000-0000-0000-0000-000000000000' ]
	    );

	ok($cancel);
	ok($result = $cancel->get());
	is($result->{'UnsuccessfulFleetRequests'}->[0]->{'SpotFleetRequestId'},
	   'sfr-00000000-0000-0000-0000-000000000000');

	dies_ok(sub { Minion::Aws::Cli->cancel_spot_fleet_requests(
			  'Bad Type'
			  )});

	dies_ok(sub { Minion::Aws::Cli->cancel_spot_fleet_requests(
			  [ 'Bad Format' ]
			  )});

	dies_ok(sub { Minion::Aws::Cli->cancel_spot_fleet_requests(
			  [ 'sfr-00000000-0000-0000-0000-000000000000' ],
			  REGION => 'Bad Format'
			  )});
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(
        timeout alt_image alt_type alt_region
    ));

    subtest 'cancel_spot_fleet_requests (region)' => sub {
	if ($test_summary{'cancel_spot_fleet_requests'}) {
	    plan tests => 10;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($request, $result, $id, $cancel, $ud);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'alt_image'},
	    $params{'alt_type'},
	    REGION => $params{'alt_region'},
	    TIME   => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$cancel = Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ]);

	ok($cancel);
	ok($result = $cancel->get());
	is(ref($result), 'HASH');
	ok($ud = $result->{'UnsuccessfulFleetRequests'}->[0]
	   ->{'SpotFleetRequestId'});
	is($ud, $id);

	$cancel = Minion::Aws::Cli->cancel_spot_fleet_requests(
	    [ $id ],
	    REGION => $params{'alt_region'});

	ok($cancel) or diag("cannot cancel request '$id'"), return;
	ok($result = $cancel->get())
	    or diag("cannot cancel request '$id'"), return;
	is(ref($result), 'HASH')
	    or diag("cannot cancel request '$id'"), return;
	ok($ud = $result->{'SuccessfulFleetRequests'}->[0]
	   ->{'SpotFleetRequestId'})
	    or diag("cannot cancel request '$id'"), return;
	is($ud, $id)
	    or diag("cannot cancel request '$id'"), return;
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'cancel_spot_fleet_requests (many)' => sub {
	if ($test_summary{'cancel_spot_fleet_requests'}) {
	    plan tests => 2;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($i, @requests, $request, $result, $id, @ids, $cancel);

	for ($i = 0; $i < 3; $i++) {
	    $request = Minion::Aws::Cli->request_spot_fleet(
		$params{'default_image'},
		$params{'default_type'},
		TIME => $params{'timeout'}
		);
	    push(@requests, $request);
	}

	Minion::System::Pgroup->new(\@requests)->waitall();

	foreach $request (@requests) {
	    $id = $request->get()->{'SpotFleetRequestId'};
	    push(@ids, $id);
	}

	$cancel = Minion::Aws::Cli->cancel_spot_fleet_requests(\@ids);

	ok($cancel) or diag('cannot cancel request ' .
			    join(', ', map { "'$_'" } @ids)), return;
	ok($cancel->get()) or diag('cannot cancel request ' .
			    join(', ', map { "'$_'" } @ids)), return;
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    subtest 'cancel_spot_fleet_requests (err)' => sub {
	if ($test_summary{'cancel_spot_fleet_requests'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->cancel_spot_fleet_requests(
		    [ 'sfr-00000000-0000-0000-0000-000000000000' ],
		    ERR    => $logger,
		    REGION => 'no-where-0'
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    subtest 'cancel_spot_fleet_requests (log)' => sub {
	if ($test_summary{'cancel_spot_fleet_requests'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->cancel_spot_fleet_requests(
		    [ 'sfr-00000000-0000-0000-0000-000000000000' ],
		    LOG => $logger
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}


# describe_spot_fleet_requests ------------------------------------------------

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_requests (simple)' => sub {
	if ($test_summary{'describe_spot_fleet_requests'}) {
	    plan tests => 9;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe, $result);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_requests(
	    IDS => [ $id ]
	    );

	ok($describe);
	ok(Minion::System::Future->comply($describe));
	is($describe->out(), undef);
	ok($result = $describe->get());
	is(ref($result), 'HASH');
	is(ref($result->{'SpotFleetRequestConfigs'}), 'ARRAY');
	is(ref($result->{'SpotFleetRequestConfigs'}->[0]), 'HASH');
	is($result->{'SpotFleetRequestConfigs'}->[0]->{'SpotFleetRequestId'},
	    $id);
	is(ref($result->{'SpotFleetRequestConfigs'}->[0]
	       ->{'SpotFleetRequestState'}), '');

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(default_image default_type));

    subtest 'describe_spot_fleet_requests (invalid)' => sub {
	if ($test_summary{'describe_spot_fleet_requests'}) {
	    plan tests => 7;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($describe, $id);

	$describe = Minion::Aws::Cli->describe_spot_fleet_requests(
	    ERR => sub {},
	    IDS => [ 'sfr-00000000-0000-0000-0000-000000000000' ]
	    );

	ok($describe);
	ok(!defined($describe->get()));

	dies_ok(sub {Minion::Aws::Cli->describe_spot_fleet_requests(
			 IDS => [
			     'sfr-00000000-0000-0000-0000-000000000000',
			     'sfr-00000000-0000-0000-0000-000000000001',
			     'Bad Format'
			 ]
			 )});

	dies_ok(sub {Minion::Aws::Cli->describe_spot_fleet_requests(
			 IDS => 'Bad Type',
			 )});

	dies_ok(sub {Minion::Aws::Cli->describe_spot_fleet_requests(
			 IDS => [ 'sfr-00000000-0000-0000-0000-000000000000' ],
			 REGION => 'Bad Format'
			 )});

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'}
	    )->get()->{'SpotFleetRequestId'};

    	$describe = Minion::Aws::Cli->describe_spot_fleet_requests(
	    ERR   => sub {},
	    IDS   => [ $id ],
	    QUERY => 'Bad Format'
	    );

	ok($describe);
	ok(!defined($describe->get()));

	if(!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(
        timeout alt_image alt_type alt_region
    ));

    subtest 'describe_spot_fleet_requests (region)' => sub {
	if ($test_summary{'describe_spot_fleet_requests'}) {
	    plan tests => 5;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe, $result);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'alt_image'},
	    $params{'alt_type'},
	    REGION => $params{'alt_region'},
	    TIME   => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_requests(
	    ERR => sub {},
	    IDS => [ $id ]
	    );

	ok($describe);
	ok(!defined($describe->get()));

	$describe = Minion::Aws::Cli->describe_spot_fleet_requests(
	    IDS    => [ $id ],
	    REGION => $params{'alt_region'}
	    );

	ok($describe);
	ok($result = $describe->get());
	is($result->{'SpotFleetRequestConfigs'}->[0]->{'SpotFleetRequestId'},
	    $id);

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests(
		 [ $id ],
		 REGION => $params{'alt_region'}
	    )->get()) {
	    diag("cannot cancel requests '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_requests (query)' => sub {
	if ($test_summary{'describe_spot_fleet_requests'}) {
	    plan tests => 4;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe, $result);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_requests(
	    IDS   => [ $id ],
	    QUERY => 'SpotFleetRequestConfigs[0].SpotFleetRequestId'
	    );

	ok($describe);
	ok($result = $describe->get());
	is(ref($result), '');
	is($result, $id);

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_requests (many)' => sub {
	if ($test_summary{'describe_spot_fleet_requests'}) {
	    plan tests => 3;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($i, @requests, $request, @ids, $id, $describe, $result);

	for ($i = 0; $i < 3; $i++) {
	    $request = Minion::Aws::Cli->request_spot_fleet(
		$params{'default_image'},
		$params{'default_type'},
		TIME => $params{'timeout'}
		);
	    push(@requests, $request);
	}

	Minion::System::Pgroup->new(\@requests)->waitall();

	foreach $request (@requests) {
	    $id = $request->get()->{'SpotFleetRequestId'};
	    push(@ids, $id);
	}

	$describe = Minion::Aws::Cli->describe_spot_fleet_requests(
	    IDS => \@ids
	    );

	ok($describe);
	ok($result = $describe->get());
	contain_same([ map { $_->{'SpotFleetRequestId'} }
		       @{$result->{'SpotFleetRequestConfigs'}} ],
		     \@ids);

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests(\@ids)->get()) {
	    diag("cannot cancel requests " . join(', ', map { "'$_'" } @ids));
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    subtest 'describe_spot_fleet_requests (err)' => sub {
	if ($test_summary{'describe_spot_fleet_requests'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_spot_fleet_requests(
		    IDS    => [ 'sfr-00000000-0000-0000-0000-000000000000' ],
		    ERR    => $logger,
		    REGION => 'no-where-0'
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_requests (log)' => sub {
	if ($test_summary{'describe_spot_fleet_requests'}) {
	    my $id = Minion::Aws::Cli->request_spot_fleet(
		$params{'default_image'},
		$params{'default_type'},
		TIME => $params{'timeout'}
		)->get()->{'SpotFleetRequestId'};

	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_spot_fleet_requests(
		    IDS => [ $id ],
		    LOG => $logger
		    );
	    });

	    if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()){
		diag("cannot cancel request '$id'");
		return;
	    }
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}


# describe_spot_fleet_instances -----------------------------------------------

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_instances (simple)' => sub {
	if ($test_summary{'describe_spot_fleet_instances'}) {
	    plan tests => 8;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe, $result, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_instances($id);

	ok($describe);
	ok(Minion::System::Future->comply($describe));
	is($describe->out(), undef);
	ok($result = $describe->get());
	is(ref($result), 'HASH');
	is(ref($result->{'ActiveInstances'}), 'ARRAY');

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $describe = Minion::Aws::Cli->describe_spot_fleet_instances($id);
	    $result = $describe->get();

	    last if (scalar(@{$result->{'ActiveInstances'}}) > 0);
	}

	is(ref($result->{'ActiveInstances'}->[0]), 'HASH');
	is(ref($result->{'ActiveInstances'}->[0]->{'InstanceId'}), '');

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_instances (invalid)' => sub {
	if ($test_summary{'describe_spot_fleet_instances'}) {
	    plan tests => 7;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_instances(
	    'sfr-00000000-0000-0000-0000-000000000000',
	    ERR => sub {}
	    );

	ok($describe);
	ok(!defined($describe->get()));

    	dies_ok(sub {Minion::Aws::Cli->describe_spot_fleet_instances(
			 'Bad Format',
			 )});

    	dies_ok(sub {Minion::Aws::Cli->describe_spot_fleet_instances(
			 [ 'Bad Type' ],
			 )});

    	dies_ok(sub {Minion::Aws::Cli->describe_spot_fleet_instances(
			 $id,
			 REGION => 'Bad Format'
			 )});

	$describe = Minion::Aws::Cli->describe_spot_fleet_instances(
	    $id,
	    ERR   => sub {},
	    QUERY => 'Bad Format'
	    );

	ok($describe);
	ok(!defined($describe->get()));

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(
        timeout alt_image alt_type alt_region
    ));

    subtest 'describe_spot_fleet_instances (region)' => sub {
	if ($test_summary{'describe_spot_fleet_instances'}) {
	    plan tests => 5;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe, $result, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'alt_image'},
	    $params{'alt_type'},
	    REGION => $params{'alt_region'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_instances(
	    $id,
	    ERR => sub {}
	    );

	ok($describe);
	ok(!defined($describe->get()));

	$describe = Minion::Aws::Cli->describe_spot_fleet_instances(
	    $id,
	    REGION => $params{'alt_region'}
	    );

	ok($describe);
	ok($result = $describe->get());

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $describe = Minion::Aws::Cli->describe_spot_fleet_instances(
		$id,
		REGION => $params{'alt_region'}
		);
	    $result = $describe->get();

	    last if (scalar(@{$result->{'ActiveInstances'}}) > 0);
	}

	ok(scalar(@{$result->{'ActiveInstances'}}) > 0);

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests(
		 [ $id ],
		 REGION => $params{'alt_region'}
	    )->get()) {
	    diag("cannot cancel requests '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_instances (query)' => sub {
	if ($test_summary{'describe_spot_fleet_instances'}) {
	    plan tests => 4;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe, $result, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_instances(
	    $id,
	    QUERY => 'ActiveInstances[*].InstanceId'
	    );

	ok($describe);
	ok($result = $describe->get());
	is(ref($result), 'ARRAY');

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $describe = Minion::Aws::Cli->describe_spot_fleet_instances(
		$id,
		QUERY => 'ActiveInstances[*].InstanceId'
		);
	    $result = $describe->get();

	    last if (scalar(@$result) > 0);
	}

	is(ref($result->[0]), '');

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    subtest 'describe_spot_fleet_instances (err)' => sub {
	if ($test_summary{'describe_spot_fleet_instances'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_spot_fleet_instances(
		    'sfr-00000000-0000-0000-0000-000000000000',
		    ERR    => $logger,
		    REGION => 'no-where-0'
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_instances (log)' => sub {
	if ($test_summary{'describe_spot_fleet_instances'}) {
	    my $id = Minion::Aws::Cli->request_spot_fleet(
		$params{'default_image'},
		$params{'default_type'},
		TIME => $params{'timeout'}
		)->get()->{'SpotFleetRequestId'};

	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_spot_fleet_instances(
		    $id,
		    LOG => $logger
		    );
	    });

	    if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()){
		diag("cannot cancel request '$id'");
		return;
	    }
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}


# describe_instances ==========================================================

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_instances (simple)' => sub {
	if ($test_summary{'describe_instances'}) {
	    plan tests => 10;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $iid, $describe, $result, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $iid = Minion::Aws::Cli->describe_spot_fleet_instances(
		$id,
		QUERY => 'ActiveInstances[0].InstanceId'
		)->get();

	    last if (defined($iid));
	}

	$describe = Minion::Aws::Cli->describe_instances(
	    IDS => [ $iid ]
	    );

	ok($describe);
	ok(Minion::System::Future->comply($describe));
	is($describe->out(), undef);
	ok($result = $describe->get());
	is(ref($result), 'HASH');
	is(ref($result->{'Reservations'}), 'ARRAY');
	is(ref($result->{'Reservations'}->[0]), 'HASH');
	is(ref($result->{'Reservations'}->[0]->{'Instances'}), 'ARRAY');
	is(ref($result->{'Reservations'}->[0]->{'Instances'}->[0]), 'HASH');
	is($result->{'Reservations'}->[0]->{'Instances'}->[0]->{'InstanceId'},
	   $iid);

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_instances (invalid)' => sub {
	if ($test_summary{'describe_instances'}) {
	    plan tests => 10;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $iid, $describe, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $iid = Minion::Aws::Cli->describe_spot_fleet_instances(
		$id,
		QUERY => 'ActiveInstances[0].InstanceId'
		)->get();

	    last if (defined($iid));
	}

	$describe = Minion::Aws::Cli->describe_instances(
	    ERR => sub {},
	    IDS => [ 'i-00000000000000000' ]
	    );

	ok($describe);
	ok(!defined($describe->get()));


	dies_ok(sub { Minion::Aws::Cli->describe_instances(
			  IDS => [ 'Bad Format' ]
			  )});

	dies_ok(sub { Minion::Aws::Cli->describe_instances(
			  IDS => 'Bad Type'
			  )});
	

	$describe = Minion::Aws::Cli->describe_instances(
	    ERR     => sub {},
	    FILTERS => { 'Bad Key' => 'Bad Value' },
	    IDS     => [ $iid ]
	    );

	ok($describe);
	ok(!defined($describe->get()));


	dies_ok(sub { Minion::Aws::Cli->describe_instances(
			  FILTERS => 'Bad Type',
			  IDS     => [ $iid ]
			  )});


	$describe = Minion::Aws::Cli->describe_instances(
	    ERR   => sub {},
	    IDS   => [ $iid ],
	    QUERY => 'Bad Value'
	    );

	ok($describe);
	ok(!defined($describe->get()));


	dies_ok(sub { Minion::Aws::Cli->describe_instances(
			  IDS    => [ $iid ],
			  REGION => 'Bad Format'
			  )});


	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_instances (filter)' => sub {
	if ($test_summary{'describe_instances'}) {
	    plan tests => 3;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $iid, $describe, $result, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $iid = Minion::Aws::Cli->describe_spot_fleet_instances(
		$id,
		QUERY => 'ActiveInstances[0].InstanceId'
		)->get();

	    last if (defined($iid));
	}

	$describe = Minion::Aws::Cli->describe_instances(
	    FILTERS => { 'instance-id' => $iid }
	    );

	ok($describe);
	ok($result = $describe->get());
	is($result->{'Reservations'}->[0]->{'Instances'}->[0]->{'InstanceId'},
	   $iid);

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

 SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_instances (query)' => sub {
	if ($test_summary{'describe_instances'}) {
	    plan tests => 5;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $iid, $describe, $result, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $iid = Minion::Aws::Cli->describe_spot_fleet_instances(
		$id,
		QUERY => 'ActiveInstances[0].InstanceId'
		)->get();

	    last if (defined($iid));
	}

	$describe = Minion::Aws::Cli->describe_instances(
	    IDS   => [ $iid ],
	    QUERY => 'Reservations[0].Instances[0].' .
                     '{Id:InstanceId,Ip:PublicIpAddress}'
	    );

	ok($describe);
	ok($result = $describe->get());
	is(ref($result), 'HASH');
	is($result->{'Id'}, $iid);
	like($result->{'Ip'}, qr/^\d+\.\d+\.\d+\.\d+$/);

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

 SKIP: {
    my %params = from_config($config, qw(
        timeout alt_image alt_type alt_region
    ));

    subtest 'describe_instances (region)' => sub {
	if ($test_summary{'describe_instances'}) {
	    plan tests => 5;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $iid, $describe, $result, $start);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'alt_image'},
	    $params{'alt_type'},
	    REGION => $params{'alt_region'},
	    TIME   => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $iid = Minion::Aws::Cli->describe_spot_fleet_instances(
		$id,
		QUERY  => 'ActiveInstances[0].InstanceId',
		REGION => $params{'alt_region'}
		)->get();

	    last if (defined($iid));
	}


	$describe = Minion::Aws::Cli->describe_instances(
	    ERR => sub {},
	    IDS => [ $iid ],
	    );

	ok($describe);
	ok(!defined($describe->get()));


	$describe = Minion::Aws::Cli->describe_instances(
	    IDS    => [ $iid ],
	    REGION => $params{'alt_region'}
	    );

	ok($describe);
	ok($result = $describe->get());
	is($result->{'Reservations'}->[0]->{'Instances'}->[0]->{'InstanceId'},
	   $iid);


	if (!Minion::Aws::Cli->cancel_spot_fleet_requests(
		 [ $id ],
		 REGION => $params{'alt_region'}
	    )->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    subtest 'describe_instances (err)' => sub {
	if ($test_summary{'describe_instances'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_instances(
		    ERR    => $logger,
		    IDS    => [ 'i-00000000000000000' ]
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_instances (log)' => sub {
	if ($test_summary{'describe_instances'}) {
	    my ($id, $start, $iid);

	    $id = Minion::Aws::Cli->request_spot_fleet(
		$params{'default_image'},
		$params{'default_type'},
		TIME => $params{'timeout'}
		)->get()->{'SpotFleetRequestId'};

	    $start = time();

	    while ((time() - $start) < $params{'timeout'}) {
		$iid = Minion::Aws::Cli->describe_spot_fleet_instances(
		    $id,
		    QUERY  => 'ActiveInstances[0].InstanceId'
		    )->get();

		last if (defined($iid));
	    }

	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_instances(
		    IDS => [ $iid ],
		    LOG => $logger
		    );
	    });

	    if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()){
		diag("cannot cancel request '$id'");
		return;
	    }
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}


# describe_spot_fleet_request_history -----------------------------------------

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_request_history (simple)' => sub {
	if ($test_summary{'describe_spot_fleet_request_history'}) {
	    plan tests => 7;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe, $result);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    $id, $params{'timeout'}
	    );

	ok($describe);
	ok(Minion::System::Future->comply($describe));
	is($describe->out(), undef);
	ok($result = $describe->get());
	is(ref($result), 'HASH');
	is($result->{'SpotFleetRequestId'}, $id);
	is(ref($result->{'HistoryRecords'}), 'ARRAY');


	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_request_history (invalid)' => sub {
	if ($test_summary{'describe_spot_fleet_request_history'}) {
	    plan tests => 10;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $describe);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};


	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    'sfr-00000000-0000-0000-0000-000000000000', $params{'timeout'},
	    ERR => sub {}
	    );

	ok($describe);
	ok(!defined($describe->get()));


	dies_ok(sub { Minion::Aws::Cli->describe_spot_fleet_request_history(
			  $id, 'Bad Format'
			  )});


	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    $id, 0
	    );

	ok(!defined($describe));

	
	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    $id, -10
	    );

	ok(!defined($describe));


	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    $id, $params{'timeout'},
	    ERR   => sub {},
	    QUERY => 'Bad Value'
	    );

	ok($describe);
	ok(!defined($describe->get()));


	dies_ok(sub { Minion::Aws::Cli->describe_spot_fleet_request_history(
			  $id, $params{'timeout'},
			  REGION => 'Bad Format'
			  )});


	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    $id, $params{'timeout'},
	    ERR   => sub {},
	    REGION => 'no-where-0'
	    );

	ok($describe);
	ok(!defined($describe->get()));


	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout default_image default_type));

    subtest 'describe_spot_fleet_request_history (query)' => sub {
	if ($test_summary{'describe_spot_fleet_request_history'}) {
	    plan tests => 5;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $start, $result);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'default_image'},
	    $params{'default_type'},
	    TIME => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};

	$start = time();

	while ((time() - $start) < $params{'timeout'}) {
	    $result = Minion::Aws::Cli->describe_spot_fleet_request_history(
		$id, $params{'timeout'},
		QUERY => 'HistoryRecords[*]'
		)->get();

	    last if (scalar(@$result) > 0);
	}

	ok(scalar(@$result) > 0);
	is(ref($result->[0]), 'HASH');
	is(ref($result->[0]->{'EventType'}), '');
	is(ref($result->[0]->{'Timestamp'}), '');
	is(ref($result->[0]->{'EventInformation'}), 'HASH');

	if (!Minion::Aws::Cli->cancel_spot_fleet_requests([ $id ])->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(
        timeout alt_image alt_type alt_region
    ));

    subtest 'describe_spot_fleet_request_history (region)' => sub {
	if ($test_summary{'describe_spot_fleet_request_history'}) {
	    plan tests => 4;
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}

	my ($id, $start, $describe, $result);

	$id = Minion::Aws::Cli->request_spot_fleet(
	    $params{'alt_image'},
	    $params{'alt_type'},
	    REGION => $params{'alt_region'},
	    TIME   => $params{'timeout'}
	    )->get()->{'SpotFleetRequestId'};


	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    $id, $params{'timeout'},
	    ERR => sub {}
	    );

	ok($describe);
	ok(!defined($describe->get()));


	$describe = Minion::Aws::Cli->describe_spot_fleet_request_history(
	    $id, $params{'timeout'},
	    REGION => $params{'alt_region'}
	    );

	ok($describe);
	ok($describe->get());


	if (!Minion::Aws::Cli->cancel_spot_fleet_requests(
		 [ $id ],
		 REGION => $params{'alt_region'}
	    )->get()) {
	    diag("cannot cancel request '$id'");
	    return;
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout));

    subtest 'describe_spot_fleet_request_history (err)' => sub {
	if ($test_summary{'describe_spot_fleet_request_history'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_spot_fleet_request_history(
		    'sfr-00000000-0000-0000-0000-000000000000',
		    $params{'timeout'},
		    ERR => $logger
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SKIP: {
    my %params = from_config($config, qw(timeout));

    subtest 'describe_spot_fleet_request_history (log)' => sub {
	if ($test_summary{'describe_spot_fleet_request_history'}) {
	    has_logger(sub {
		my ($logger) = @_;

		return Minion::Aws::Cli->describe_spot_fleet_request_history(
		    'sfr-00000000-0000-0000-0000-000000000000',
		    $params{'timeout'},
		    ERR => sub {},
		    LOG => $logger
		    );
	    });
	} else {
	    plan skip_all => 'test disabled (dev only)';
	}
    };
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -



__END__
