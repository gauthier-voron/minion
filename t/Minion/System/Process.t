use strict;
use warnings;

use File::Temp qw(tempfile);
use POSIX;
use Test::More tests => 50;
use Time::HiRes qw(time usleep);

BEGIN
{
    use_ok('Minion::System::Process');
    use_ok('Minion::System::Waitable');
};


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


# process execution -----------------------------------------------------------

subtest 'forked execution' => sub {
    plan tests => 6;

    my ($process, $status);

    $process = Minion::System::Process->new(sub {
	exit (42);
    });

    ok($process);
    ok(Minion::System::Waitable->comply($process));
    isnt($process->pid(), 0);
    is($process->exitstatus(), undef);

    $status = $process->wait();

    is($status >> 8, 42);
    is($process->exitstatus() >> 8, 42);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'fork-exec execution' => sub {
    plan tests => 6;

    my ($process, $status);

    $process = Minion::System::Process->new(['false']);

    ok($process);
    ok(Minion::System::Waitable->comply($process));
    isnt($process->pid(), 0);
    is($process->exitstatus(), undef);

    $status = $process->wait();

    isnt($status, 0);
    is($process->exitstatus(), $status);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'wait' => sub {
    plan tests => 2;

    my ($process, $start, $t0, $t1);

    $process = Minion::System::Process->new(sub {
    });

    $start = time();
    $process->wait();
    $t0 = time() - $start;

    $process = Minion::System::Process->new(sub {
	usleep(100_000);
    });

    $start = time();
    $process->wait();
    $t1 = time() - $start;

    ok($t0 < 0.050);
    ok($t1 > 0.050);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'trywait' => sub {
    plan tests => 5;

    my ($process, $status, $start, $duration);

    $process = Minion::System::Process->new(sub {
	usleep(100_000);
    });

    is($process->exitstatus(), undef);

    $start = time();
    $status = $process->trywait();
    $duration = time() - $start;

    ok($duration < 0.010);
    is($status, undef);

    usleep(150_000);

    $start = time();
    $status = $process->trywait();
    $duration = time() - $start;

    ok($duration < 0.010);
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'trywait timeout' => sub {
    plan tests => 7;

    my ($process, $status, $start, $duration);

    $process = Minion::System::Process->new(sub {
	usleep(100_000);
    });

    is($process->exitstatus(), undef);

    $start = time();
    $status = $process->trywait(TIMEOUT => 0.050);
    $duration = time() - $start;

    ok($duration >= 0.050);
    ok($duration <= 0.100);
    is($status, undef);

    usleep(30_000);

    $start = time();
    $status = $process->trywait(TIMEOUT => 0.050);
    $duration = time() - $start;

    ok($duration >= 0.020);
    ok($duration <= 0.050);
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'forked kill' => sub {
    plan tests => 7;

    my ($process, $status, $before, $after);

    $process = Minion::System::Process->new(sub {
	sleep(100);
    });

    ok($process);
    ok(Minion::System::Waitable->comply($process));
    isnt($process->pid(), 0);
    is($process->exitstatus(), undef);

    $process->kill();

    $before = time();
    $status = $process->wait();
    $after = time();

    ok(($after - $before) < 90);
    is($status & 0xff, SIGTERM);
    is($status, $process->exitstatus());
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'fork-exec kill' => sub {
    plan tests => 7;

    my ($process, $status, $before, $after);

    $process = Minion::System::Process->new(['sleep', '100']);

    ok($process);
    ok(Minion::System::Waitable->comply($process));
    isnt($process->pid(), 0);
    is($process->exitstatus(), undef);

    $process->kill();

    $before = time();
    $status = $process->wait();
    $after = time();

    ok(($after - $before) < 90);
    is($status & 0xff, SIGTERM);
    is($status, $process->exitstatus());
};


# io new input ----------------------------------------------------------------

subtest 'io new input scalar' => sub {
    plan tests => 4;

    my ($process, $fh, $scalar, $status);

    $scalar = "10\n7";
    $process = Minion::System::Process->new(sub {
	my $v0 = <$fh>;
	my $v1 = <$fh>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \$fh, '<', \$scalar ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    $status = $process->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new input subroutine' => sub {
    plan tests => 5;

    my ($process, $fh, @values, $status);

    @values = ("10\n", '7');
    $process = Minion::System::Process->new(sub {
	my $v0 = <$fh>;
	my $v1 = <$fh>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \$fh, '<', sub { return shift(@values); } ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    $status = $process->wait();

    is($status, 0);
    is(scalar(@values), 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new input glob' => sub {
    plan tests => 4;

    my ($process, $fh, $piper, $pipew, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);
	close($pipew);

	my $v0 = <$fh>;
	my $v1 = <$fh>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \$fh, '<', $piper ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    printf($pipew "10\n");
    printf($pipew "7");

    close($piper);
    close($pipew);

    $status = $process->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new input filename' => sub {
    plan tests => 4;

    my ($process, $fh, $path, $status);

    ($fh, $path) = tempfile('perl-test-more.XXXXXX', TMPDIR => 1);
    printf($fh "10\n7");
    close($fh); $fh = undef;

    $process = Minion::System::Process->new(sub {
	my $v0 = <$fh>;
	my $v1 = <$fh>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \$fh, '<', $path ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    $status = $process->wait();

    is($status, 0);

    unlink($path);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new input new pipe' => sub {
    plan tests => 4;

    my ($process, $fh, $pipew, $status);

    $process = Minion::System::Process->new(sub {
	my $v0 = <$fh>;
	my $v1 = <$fh>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \$fh, '<', \$pipew ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    printf($pipew "10\n");
    printf($pipew "7");
    close($pipew);

    $status = $process->wait();

    is($status, 0);
};

# io new output ---------------------------------------------------------------

subtest 'io new output scalar' => sub {
    plan tests => 5;

    my ($process, $fh, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf($fh "10\n");
	printf($fh "7");
    }, IO => [ [ \$fh, '>', \$scalar ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new output subroutine' => sub {
    plan tests => 5;

    my ($process, $fh, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf($fh "10\n");
	printf($fh "7");
    }, IO => [ [ \$fh, '>', sub { $scalar .= shift() if (@_); } ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new output glob' => sub {
    plan tests => 5;

    my ($process, $fh, $piper, $pipew, $scalar, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);
	close($pipew);

	printf($fh "10\n");
	printf($fh "7");
    }, IO => [ [ \$fh, '>', $pipew ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    close($pipew);

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new output filename' => sub {
    plan tests => 5;

    my ($process, $fh, $path, $scalar, $status);

    ($fh, $path) = tempfile('perl-test-more.XXXXXX', TMPDIR => 1);
    printf($fh "previous content\n");
    close($fh); $fh = undef;

    $process = Minion::System::Process->new(sub {
	printf($fh "10\n");
	printf($fh "7");
    }, IO => [ [ \$fh, '>', $path ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    usleep(100_000);

    fail() if (!open($fh, '<', $path));

    {
	local $/ = undef;
	$scalar = <$fh>;
    }

    close($fh);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "previous content\n10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io new output new pipe' => sub {
    plan tests => 5;

    my ($process, $fh, $piper, $scalar, $status);

    $process = Minion::System::Process->new(sub {
	printf($fh "10\n");
	printf($fh "7");
    }, IO => [ [ \$fh, '>', \$piper ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));
    ok(!defined($fh));

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# io dup2 input ---------------------------------------------------------------

subtest 'io dup2 input scalar' => sub {
    plan tests => 3;

    my ($process, $scalar, $status);

    $scalar = "10\n7";
    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \*STDIN, '<', \$scalar ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 input subroutine' => sub {
    plan tests => 4;

    my ($process, @values, $status);

    @values = ("10\n", '7');
    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \*STDIN, '<', sub { return shift(@values); } ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is(scalar(@values), 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 input glob' => sub {
    plan tests => 3;

    my ($process, $piper, $pipew, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);
	close($pipew);

	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \*STDIN, '<', $piper ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    printf($pipew "10\n");
    printf($pipew "7");

    close($piper);
    close($pipew);

    $status = $process->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 input filename' => sub {
    plan tests => 3;

    my ($process, $fh, $path, $status);

    ($fh, $path) = tempfile('perl-test-more.XXXXXX', TMPDIR => 1);
    printf($fh "10\n7");
    close($fh); $fh = undef;

    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \*STDIN, '<', $path ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);

    unlink($path);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 input new pipe' => sub {
    plan tests => 3;

    my ($process, $pipew, $status);

    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ \*STDIN, '<', \$pipew ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    printf($pipew "10\n");
    printf($pipew "7");
    close($pipew);

    $status = $process->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 input same glob' => sub {
    plan tests => 3;

    my ($process, $piper, $pipew, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($pipew);

	my $v0 = <$piper>;
	my $v1 = <$piper>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, IO => [ [ $piper, '<', $piper ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    printf($pipew "10\n");
    printf($pipew "7");

    close($piper);
    close($pipew);

    $status = $process->wait();

    is($status, 0);
};

# io dup2 output --------------------------------------------------------------

subtest 'io dup2 output scalar' => sub {
    plan tests => 4;

    my ($process, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, IO => [ [ \*STDOUT, '>', \$scalar ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 output subroutine' => sub {
    plan tests => 4;

    my ($process, $fh, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, IO => [ [ \*STDOUT, '>', sub { $scalar .= shift() if (@_); } ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 output glob' => sub {
    plan tests => 4;

    my ($process, $fh, $piper, $pipew, $scalar, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);
	close($pipew);

	printf("10\n");
	printf("7");
    }, IO => [ [ \*STDOUT, '>', $pipew ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    close($pipew);

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 output filename' => sub {
    plan tests => 4;

    my ($process, $fh, $path, $scalar, $status);

    ($fh, $path) = tempfile('perl-test-more.XXXXXX', TMPDIR => 1);
    printf($fh "previous content\n");
    close($fh); $fh = undef;

    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, IO => [ [ \*STDOUT, '>', $path ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    usleep(100_000);

    fail() if (!open($fh, '<', $path));

    {
	local $/ = undef;
	$scalar = <$fh>;
    }

    close($fh);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "previous content\n10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 output new pipe' => sub {
    plan tests => 4;

    my ($process, $piper, $scalar, $status);

    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, IO => [ [ \*STDOUT, '>', \$piper ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io dup2 output same glob' => sub {
    plan tests => 4;

    my ($process, $fh, $piper, $pipew, $scalar, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);

	printf($pipew "10\n");
	printf($pipew "7");
    }, IO => [ [ $pipew, '>', $pipew ] ]);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    close($pipew);

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# stdin option ----------------------------------------------------------------

subtest 'stdin from scalar' => sub {
    plan tests => 3;

    my ($process, $scalar, $status);

    $scalar = "10\n7";
    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, STDIN => \$scalar);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdin from subroutine' => sub {
    plan tests => 4;

    my ($process, @values, $status);

    @values = ("10\n", '7');
    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, STDIN => sub { return shift(@values); });

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is(scalar(@values), 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdin from glob' => sub {
    plan tests => 3;

    my ($process, $piper, $pipew, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);
	close($pipew);

	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, STDIN => $piper);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    printf($pipew "10\n");
    printf($pipew "7");

    close($piper);
    close($pipew);

    $status = $process->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdin from filename' => sub {
    plan tests => 3;

    my ($process, $fh, $path, $status);

    ($fh, $path) = tempfile('perl-test-more.XXXXXX', TMPDIR => 1);
    printf($fh "10\n7");
    close($fh); $fh = undef;

    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, STDIN => $path);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);

    unlink($path);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdin from new pipe' => sub {
    plan tests => 3;

    my ($process, $pipew, $status);

    $process = Minion::System::Process->new(sub {
	my $v0 = <STDIN>;
	my $v1 = <STDIN>;

	if ($v0 ne "10\n") { exit (1); }
	if ($v1 ne "7")    { exit (1); }

	exit (0);
    }, STDIN => \$pipew);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    printf($pipew "10\n");
    printf($pipew "7");
    close($pipew);

    $status = $process->wait();

    is($status, 0);
};

# stdout option ---------------------------------------------------------------

subtest 'stdout to scalar' => sub {
    plan tests => 4;

    my ($process, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, STDOUT => \$scalar);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdout to subroutine' => sub {
    plan tests => 4;

    my ($process, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, STDOUT => sub { $scalar .= shift() if (@_); });

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdout to glob' => sub {
    plan tests => 4;

    my ($process, $piper, $pipew, $scalar, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);
	close($pipew);

	printf("10\n");
	printf("7");
    }, STDOUT => $pipew);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    close($pipew);

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdout to filename' => sub {
    plan tests => 4;

    my ($process, $fh, $path, $scalar, $status);

    ($fh, $path) = tempfile('perl-test-more.XXXXXX', TMPDIR => 1);
    printf($fh "previous content\n");
    close($fh); $fh = undef;

    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, STDOUT => $path);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    usleep(100_000);

    fail() if (!open($fh, '<', $path));

    {
	local $/ = undef;
	$scalar = <$fh>;
    }

    close($fh);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "previous content\n10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdout to new pipe' => sub {
    plan tests => 4;

    my ($process, $piper, $scalar, $status);

    $process = Minion::System::Process->new(sub {
	printf("10\n");
	printf("7");
    }, STDOUT => \$piper);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# stderr option ---------------------------------------------------------------

subtest 'stderr to scalar' => sub {
    plan tests => 4;

    my ($process, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf(STDERR "10\n");
	printf(STDERR "7");
    }, STDERR => \$scalar);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stderr to subroutine' => sub {
    plan tests => 4;

    my ($process, $scalar, $status);

    $scalar = '';
    $process = Minion::System::Process->new(sub {
	printf(STDERR "10\n");
	printf(STDERR "7");
    }, STDERR => sub { $scalar .= shift() if (@_); });

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stderr to glob' => sub {
    plan tests => 4;

    my ($process, $piper, $pipew, $scalar, $status);

    pipe($piper, $pipew);
    $process = Minion::System::Process->new(sub {
	close($piper);
	close($pipew);

	printf(STDERR "10\n");
	printf(STDERR "7");
    }, STDERR => $pipew);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    close($pipew);

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stderr to filename' => sub {
    plan tests => 4;

    my ($process, $fh, $path, $scalar, $status);

    ($fh, $path) = tempfile('perl-test-more.XXXXXX', TMPDIR => 1);
    printf($fh "previous content\n");
    close($fh); $fh = undef;

    $process = Minion::System::Process->new(sub {
	printf(STDERR "10\n");
	printf(STDERR "7");
    }, STDERR => $path);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    usleep(100_000);

    fail() if (!open($fh, '<', $path));

    {
	local $/ = undef;
	$scalar = <$fh>;
    }

    close($fh);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "previous content\n10\n7");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stderr to new pipe' => sub {
    plan tests => 4;

    my ($process, $piper, $scalar, $status);

    $process = Minion::System::Process->new(sub {
	printf(STDERR "10\n");
	printf(STDERR "7");
    }, STDERR => \$piper);

    ok($process) or return;
    ok(Minion::System::Waitable->comply($process));

    {
	local $/ = undef;
	$scalar = <$piper>;
    }

    close($piper);

    $status = $process->wait();

    is($status, 0);
    is($scalar, "10\n7");
};

# conflicting options ---------------------------------------------------------

subtest 'stdin conflicts with io' => sub {
    plan tests => 1;

    dies_ok(sub {
	Minion::System::Process->new(
	    sub {},
	    STDIN => '/dev/null',
	    IO => [ [ \*STDIN, '<', '/dev/zero' ] ]
	    )});
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stdout conflicts with io' => sub {
    plan tests => 1;

    dies_ok(sub {
	Minion::System::Process->new(
	    sub {},
	    STDOUT => '/dev/null',
	    IO => [ [ \*STDOUT, '>', '/dev/zero' ] ]
	    )});
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'stderr conflicts with io' => sub {
    plan tests => 1;

    dies_ok(sub {
	Minion::System::Process->new(
	    sub {},
	    STDERR => '/dev/null',
	    IO => [ [ \*STDERR, '>', '/dev/zero' ] ]
	    )});
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

subtest 'io conflicts with io' => sub {
    plan tests => 1;

    dies_ok(sub {
	Minion::System::Process->new(
	    sub {},
	    IO => [
		[ \*STDIN, '<', '/dev/zero' ],
		[ \*STDIN, '<', '/dev/null' ]
	    ]
	    )});
};



__END__
