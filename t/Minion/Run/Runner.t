use lib qw(t/);
use strict;
use warnings;

use Test::More tests => 19;

use File::Temp qw(tempdir);

use Minion::MockFleet;
use Minion::MockWorker;

BEGIN
{
    use_ok('Minion::Run::Runner');
    use_ok('Minion::Shell');
    use_ok('Minion::StaticFleet');
    use_ok('Minion::System::Waitable');
};


# Test cases ==================================================================

# Resolve local ---------------------------------------------------------------

subtest 'resolve single local perl module' => sub {
    plan tests => 4;

    my ($path, $fh, $runner, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/a.pm'); close($fh);
    open($fh, '>', $path . '/a'); close($fh);
    open($fh, '>', $path . '/b.pm'); close($fh);
    open($fh, '>', $path . '/.pm'); close($fh);

    $runner = Minion::Run::Runner->new(LOCAL => [ $path ]);

    ok($runner);

    $ret = $runner->resolve_local('a');

    ok($ret);
    is(ref($ret), '');
    is($ret, $path . '/a.pm');
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve many local perl module' => sub {
    plan tests => 4;

    my ($path0, $path1, $path2, $fh, $runner, $ret);

    $path0 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path0 . '/a'); close($fh);

    $path1 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path1 . '/a.pm'); close($fh);
    open($fh, '>', $path1 . '/a'); close($fh);

    $path2 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path2 . '/a.pm'); close($fh);

    $runner = Minion::Run::Runner->new(LOCAL => [ $path0, $path1, $path2 ]);

    ok($runner);

    $ret = $runner->resolve_local('a');

    ok($ret);
    is(ref($ret), '');
    is($ret, $path1 . '/a.pm');
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve one local not found' => sub {
    plan tests => 2;

    my ($path, $fh, $runner, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/b.pm'); close($fh);
    open($fh, '>', $path . '/.pm'); close($fh);
    open($fh, '>', $path . '/c'); close($fh);

    $runner = Minion::Run::Runner->new(LOCAL => [ $path ]);

    ok($runner);

    $ret = $runner->resolve_local('a');

    is($ret, undef);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve no local not found' => sub {
    plan tests => 2;

    my ($runner, $ret);

    $runner = Minion::Run::Runner->new();

    ok($runner);

    $ret = $runner->resolve_local('a');

    is($ret, undef);
};

# Resolve remote --------------------------------------------------------------

subtest 'resolve single remote executable no system' => sub {
    plan tests => 4;

    my ($path, $fh, $runner, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/a.sh'); close($fh); chmod(0755, $path . '/a.sh');
    open($fh, '>', $path . '/a'); close($fh); chmod(0755, $path . '/a');
    open($fh, '>', $path . '/b.pm'); close($fh); chmod(0755, $path . '/b.pm');

    $runner = Minion::Run::Runner->new(REMOTE => [ $path ]);

    ok($runner);

    $ret = $runner->resolve_remote('a', '');

    ok($ret);
    is(ref($ret), '');
    is($ret, $path . '/a');
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve single remote not executable no system' => sub {
    plan tests => 2;

    my ($path, $fh, $runner, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/a.sh'); close($fh);
    open($fh, '>', $path . '/a'); close($fh);
    open($fh, '>', $path . '/b.pm'); close($fh);

    $runner = Minion::Run::Runner->new(REMOTE => [ $path ]);

    ok($runner);

    $ret = $runner->resolve_remote('a', '');

    is($ret, undef);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve many remotes executable no system' => sub {
    plan tests => 4;

    my ($path0, $path1, $path2, $path3, $fh, $runner, $ret);

    # No file named a
    $path0 = tempdir('minion-test.XXXXXX', CLEANUP => 1);

    # File with correct name but not executable
    $path1 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path1 . '/a'); close($fh);

    # File with correct name and executable
    $path2 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path2 . '/a'); close($fh); chmod(0755, $path2 . '/a');

    # File with correct name and executable but tool late
    $path3 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path3 . '/a'); close($fh); chmod(0755, $path3 . '/a');

    $runner = Minion::Run::Runner->new(
	REMOTE => [ $path0, $path1, $path2, $path3 ]
	);

    ok($runner);

    $ret = $runner->resolve_remote('a', '');

    ok($ret);
    is(ref($ret), '');
    is($ret, $path2 . '/a');
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve no remote no system' => sub {
    plan tests => 2;

    my ($runner, $ret);

    $runner = Minion::Run::Runner->new();

    ok($runner);

    $ret = $runner->resolve_remote('a', '');

    is($ret, undef);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve single remote executable with exact system' => sub {
    plan tests => 4;

    my ($path, $fh, $runner, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    mkdir($path . '/a');
    mkdir($path . '/a/a');
    mkdir($path . '/b');
    open($fh, '>', $path . '/exe'); close($fh); chmod(0755, $path . '/exe');
    open($fh, '>', $path . '/a/exe'); close($fh); chmod(0755, $path .'/a/exe');
    open($fh, '>', $path . '/a/a/exe');close($fh);chmod(0755,$path.'/a/a/exe');
    open($fh, '>', $path . '/b/exe'); close($fh); chmod(0755, $path .'/b/exe');

    $runner = Minion::Run::Runner->new(REMOTE => [ $path ]);

    ok($runner);

    $ret = $runner->resolve_remote('exe', 'a');

    ok($ret);
    is(ref($ret), '');
    is($ret, $path . '/a/exe');
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve single remote executable with best fit system' => sub {
    plan tests => 4;

    my ($path, $fh, $runner, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    mkdir($path . '/a');
    mkdir($path . '/a/a');
    mkdir($path . '/b');
    open($fh, '>', $path . '/exe'); close($fh); chmod(0755, $path . '/exe');
    open($fh, '>', $path . '/a/exe'); close($fh); chmod(0755, $path .'/a/exe');
    open($fh, '>', $path . '/a/a/exe');close($fh);chmod(0755,$path.'/a/a/exe');
    open($fh, '>', $path . '/b/exe'); close($fh); chmod(0755, $path .'/b/exe');

    $runner = Minion::Run::Runner->new(REMOTE => [ $path ]);

    ok($runner);

    $ret = $runner->resolve_remote('exe', 'a/b/c/d');

    ok($ret);
    is(ref($ret), '');
    is($ret, $path . '/a/exe');
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'resolve many remotes executable with best fit system' => sub {
    plan tests => 4;

    my ($path0, $path1, $path2, $fh, $runner, $ret);

    $path0 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    mkdir($path0 . '/b');
    open($fh, '>', $path0 . '/b/exe'); close($fh); chmod(0755,$path0.'/b/exe');

    $path1 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    mkdir($path1 . '/a');
    open($fh, '>', $path1 . '/exe'); close($fh); chmod(0755, $path1 .'/exe');
    open($fh, '>', $path1 . '/a/exe'); close($fh); chmod(0755,$path1.'/a/exe');

    $path2 = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    mkdir($path2 . '/a');
    mkdir($path2 . '/a/a');
    open($fh, '>', $path2.'/a/a/exe');close($fh);chmod(0755,$path2.'/a/a/exe');

    $runner = Minion::Run::Runner->new(REMOTE => [ $path0, $path1, $path2 ]);

    ok($runner);

    $ret = $runner->resolve_remote('exe', 'a/a/a');

    ok($ret);
    is(ref($ret), '');
    is($ret, $path2 . '/a/a/exe');
};

# Run local -------------------------------------------------------------------

my $LOCAL_TEST_SCRIPT = <<'EOF';
#!/usr/bin/perl -l

use strict;
use warnings;

use Minion::Fleet;

my $FLEET = $_;

if ((scalar(@_) % 2) != 0) {
    exit (1);
}

my %PARAMS = @_;

if (!defined($FLEET) || !Minion::Fleet->comply($FLEET)) {
    exit (2);
}

if (!defined($PARAMS{FLEET}) || ($PARAMS{FLEET} != $FLEET)) {
    exit (3);
}

if (!defined($PARAMS{RUNNER}) || !($PARAMS{RUNNER}->can('run'))) {
    exit (4);
}

if (($ARGV[0] ne 'arg0') || ($ARGV[1] ne 'arg1')) {
    exit (5);
}

if (!defined($ENV{MINION_SHARED}) || !(-d $ENV{MINION_SHARED})) {
    exit (6);
}

if (!defined($ENV{MINION_PRIVATE}) || !(-d $ENV{MINION_PRIVATE})) {
    exit (7);
}

1;
EOF

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'run empty fleet single local perl module' => sub {
    plan tests => 5;

    my ($path, $fh, $runner, $fleet, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/a.pm');
    printf($fh "%s", $LOCAL_TEST_SCRIPT);
    close($fh);

    $runner = Minion::Run::Runner->new(LOCAL => [ $path ]);
    $fleet = Minion::MockFleet->new();

    ok($runner);
    ok($fleet);

    $ret = $runner->run($fleet, [ 'a', 'arg0', 'arg1' ]);

    ok($ret);
    ok(Minion::System::Waitable->comply($ret));
    is($ret->wait() >> 8, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'run worker single local perl module' => sub {
    plan tests => 5;

    my ($path, $fh, $runner, $worker, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/a.pm');
    printf($fh "%s", $LOCAL_TEST_SCRIPT);
    close($fh);

    $runner = Minion::Run::Runner->new(LOCAL => [ $path ]);
    $worker = Minion::MockWorker->new();
    $worker->set('run:system', '');

    ok($runner);
    ok($worker);

    $ret = $runner->run([ $worker ], [ 'a', 'arg0', 'arg1' ]);

    ok($ret);
    ok(Minion::System::Waitable->comply($ret));
    is($ret->wait() >> 8, 0);
};

# Run remote ------------------------------------------------------------------

my $REMOTE_TEST_SCRIPT = <<'EOF';
#!/bin/bash

if [ "x$1" != 'xarg0' -o "x$2" != 'xarg1' ] ; then
    exit 1
fi

exit 0
EOF

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'run fleet single remote' => sub {
    plan tests => 5;

    my ($path, $fh, $runner, $worker, $fleet, $sandbox, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/a');
    printf($fh "%s", $REMOTE_TEST_SCRIPT);
    close($fh);
    chmod(0755, $path . '/a');

    $runner = Minion::Run::Runner->new(REMOTE => [ $path ]);

    $sandbox = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    $worker = Minion::Shell->new(HOME => $sandbox);
    $worker->set('run:system', '');
    $fleet = Minion::StaticFleet->new([$worker]);

    ok($runner);
    ok($fleet);

    $ret = $runner->run($fleet, [ 'a', 'arg0', 'arg1' ]);

    ok($ret);
    ok(Minion::System::Waitable->comply($ret));
    is($ret->wait() >> 8, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'run worker single remote' => sub {
    plan tests => 5;

    my ($path, $fh, $runner, $worker, $sandbox, $ret);

    $path = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    open($fh, '>', $path . '/a');
    printf($fh "%s", $REMOTE_TEST_SCRIPT);
    close($fh);
    chmod(0755, $path . '/a');

    $runner = Minion::Run::Runner->new(REMOTE => [ $path ]);

    $sandbox = tempdir('minion-test.XXXXXX', CLEANUP => 1);
    $worker = Minion::Shell->new(HOME => $sandbox);
    $worker->set('run:system', '');

    ok($runner);
    ok($worker);

    $ret = $runner->run([ $worker ], [ 'a', 'arg0', 'arg1' ]);

    ok($ret);
    ok(Minion::System::Waitable->comply($ret));
    is($ret->wait() >> 8, 0);
};


__END__
