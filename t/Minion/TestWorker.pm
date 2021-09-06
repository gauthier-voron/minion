package Minion::TestWorker;

use strict;
use warnings;

use File::Temp qw(tempdir);
use Test::More;
use Time::HiRes qw(time usleep);

use Minion::System::Process;
use Minion::System::Waitable;


my %TESTS;


sub tests
{
    return %TESTS;
}


sub __make_tree
{
    my ($tmp, $fh);

    $tmp = tempdir('perl-test-worker.XXXXXX', CLEANUP => 1);

    open($fh, '>', $tmp . '/file');
    close($fh);

    mkdir($tmp . '/dir');

    open($fh, '>', $tmp . '/dir/other-file');
    printf($fh "Hello World!\n");
    close($fh);

    return $tmp;
}

sub __make_remote_tree
{
    my ($worker) = @_;
    my ($status, $tmp, $in);

    $tmp = '';

    $status = $worker->execute(
	['mktemp', '-d', 'perl-test-worker.XXXXXX'],
	STDOUT => \$tmp
	)->wait();

    if (($status != 0) || ($tmp eq '')) {
	return;
    }

    chomp($tmp);

    $status = $worker->execute(['touch', $tmp . '/file'])->wait();
    if ($status != 0) {
	return;
    }

    $status = $worker->execute(['mkdir', $tmp . '/dir'])->wait();
    if ($status != 0) {
	return;
    }

    $in = "Hello World!\n";
    $status = $worker->execute(
	['dd', 'of=' . $tmp . '/dir/other-file'],
	STDIN  => \$in,
	STDOUT => '/dev/null',
	STDERR => '/dev/null'
	)->wait();
    if ($status != 0) {
	return;
    }

    return $tmp;
}


# Execution tests =============================================================

$TESTS{'execute returns waitable'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($ret, $status);

    $ret = $worker->execute(['true']);

    ok(defined($ret));
    ok(Minion::System::Waitable->comply($ret));

    $status = $ret->wait();

    ok(defined($status));
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'execute returns status waitable'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($ret, $status);

    $ret = $worker->execute(['false']);

    ok(defined($ret));
    ok(Minion::System::Waitable->comply($ret));

    $status = $ret->wait();

    ok(defined($status));
    isnt($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'execute shell commands'} = sub
{
    plan tests => 2;

    my ($worker) = @_;
    my ($ret, $status, $out);

    $out = '';

    $ret = Minion::System::Process->new(sub {
	$status = $worker->execute(['printf', 'Hello %s\n', 'Bob'])->wait();
	exit ($status);
    }, STDOUT => \$out)->wait();

    is($ret, 0);
    is($out, "Hello Bob\n");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'execute and capture shell commands'} = sub
{
    plan tests => 2;

    my ($worker) = @_;
    my ($status, $out);

    $out = '';

    $status = $worker->execute(
	['printf', 'Hello %s\n', 'Bob'],
	STDOUT => \$out
	)->wait();

    is($status, 0);
    is($out, "Hello Bob\n");
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'execute and redirect shell commands'} = sub
{
    plan tests => 2;

    my ($worker) = @_;
    my ($status, $in, $out);

    $in = "Hello Alice\n";
    $out = '';

    $status = $worker->execute(
	['cat'],
	STDIN  => \$in,
	STDOUT => \$out
	)->wait();

    is($status, 0);
    is($out, $in);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'execute commands in parallel workers'} = sub
{
    plan tests => 4;

    my ($worker0, $worker1) = @_;
    my ($p0, $p1, $s0, $s1);
    my ($pin, $pout);

    pipe($pin, $pout);

    $p0 = $worker0->execute(['cat'], STDIN => $pin);
    $p1 = $worker1->execute(['sleep', '0.2']);

    ok(defined($p0));
    ok(defined($p1));

    close($pin);

    $s1 = $p1->wait();

    close($pout);

    $s0 = $p0->wait();

    is($s0, 0);
    is($s1, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'execute stdin default is empty'} = sub
{
    plan tests => 2;

    my ($worker) = @_;
    my ($status);

    $status = $worker->execute(['cat'])->wait();

    ok(defined($status));
    is($status, 0);
};


# Sending tests ===============================================================

$TESTS{'send returns waitable'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $ret, $status);

    $tree = __make_tree();

    $ret = $worker->send([$tree . '/file']);

    ok(defined($ret));
    ok(Minion::System::Waitable->comply($ret));

    $status = $ret->wait();

    ok(defined($status));
    is($status, 0);

    $status = $worker->execute(['rm', 'file'])->wait();

    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send single file gets same name'} = sub
{
    plan tests => 3;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_tree();

    $status = $worker->send([$tree . '/file'])->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-f', 'file'])->wait();
    is($status, 0);

    $status = $worker->execute(['rm', 'file'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send many files get same names'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_tree();

    $status = $worker->send(
	[$tree . '/file', $tree . '/dir/other-file']
	)->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-f', 'file'])->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-f', 'other-file'])->wait();
    is($status, 0);

    $status = $worker->execute(['rm', 'file', 'other-file'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send single file with target name'} = sub
{
    plan tests => 3;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_tree();

    $status = $worker->send(
	[$tree . '/file'],
	TARGET => 'my-sent-file'
	)->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-f', 'my-sent-file'])->wait();
    is($status, 0);

    $status = $worker->execute(['rm', 'my-sent-file'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send many files with target dir'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_tree();

    $status = $worker->execute(['mkdir', 'my-send-dest'])->wait();
    is($status, 0);

    $status = $worker->send(
	[$tree . '/file', $tree . '/dir/other-file'],
	TARGET => 'my-send-dest'
	)->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-f', 'my-send-dest/file'])->wait();
    is($status, 0);

    $status =$worker->execute(['test','-f','my-send-dest/other-file'])->wait();
    is($status, 0);

    $status = $worker->execute(['rm', '-rf', 'my-send-dest'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send single file replace existing file'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $in, $status);

    $tree = __make_tree();
    $in = 'some text';

    $status = $worker->execute(
	['dd' , 'of=my-replaced-file'],
	STDIN => \$in,
	STDOUT => '/dev/null',
	STDERR => '/dev/null'
	)->wait();
    is($status, 0);

    $status = $worker->send(
	[$tree . '/file'],
	TARGET => 'my-replaced-file'
	)->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-f', 'my-replaced-file'])->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-s', 'my-replaced-file'])->wait();
    isnt($status, 0);

    $status = $worker->execute(['rm', 'my-replaced-file'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send single directory'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_tree();

    $status = $worker->send([$tree . '/dir'])->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-d', 'dir'])->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-f', 'dir/other-file'])->wait();
    is($status, 0);

    $status = $worker->execute(['rm', '-rf', 'dir'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send single directory with target name'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_tree();

    $status = $worker->send(
	[$tree . '/dir'],
	TARGET => 'my-sent-dir'
	)->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-d', 'my-sent-dir'])->wait();
    is($status, 0);

    $status = $worker->execute(
	['test', '-f', 'my-sent-dir/other-file']
	)->wait();
    is($status, 0);

    $status = $worker->execute(['rm', '-rf', 'my-sent-dir'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send single directory with target dir'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_tree();

    $status = $worker->execute(['mkdir', 'my-dest-dir'])->wait();
    is($status, 0);

    $status = $worker->send(
	[$tree . '/dir'],
	TARGET => 'my-dest-dir'
	)->wait();
    is($status, 0);

    $status = $worker->execute(['test', '-d', 'my-dest-dir/dir'])->wait();
    is($status, 0);

    $status = $worker->execute(
	['test', '-f', 'my-dest-dir/dir/other-file']
	)->wait();
    is($status, 0);

    $status = $worker->execute(['rm', '-rf', 'my-dest-dir'])->wait();
    is($status, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'send single directory with conflicting target'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($tree, $in, $status, $outter);

    $tree = __make_tree();
    $in = 'some text';

    $status = $worker->execute(
	['dd' , 'of=my-file'],
	STDIN => \$in,
	STDOUT => '/dev/null',
	STDERR => '/dev/null'
	)->wait();
    is($status, 0);

    $outter = Minion::System::Process->new(sub {
	$status = $worker->send(
	    [$tree . '/dir'],
	    TARGET => 'my-file'
	    )->wait();
	exit (0) if ($status == 0);
	exit (1);
    }, STDERR => '/dev/null')->wait();
    isnt($outter, 0);

    $status = $worker->execute(['test', '-f', 'my-file'])->wait();
    is($status, 0);

    $status = $worker->execute(['rm', 'my-file'])->wait();
    is($status, 0);
};


# Receiving tests =============================================================

$TESTS{'receive returns waitable'} = sub
{
    plan tests => 6;

    my ($worker) = @_;
    my ($tree, $ret, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $ret = $worker->recv([$tree . '/file']);

    ok(defined($ret));
    ok(Minion::System::Waitable->comply($ret));

    $status = $ret->wait();

    ok(defined($status));
    is($status, 0);

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    $status = unlink('file');
    ok($status);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive single file gets same name'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $status = $worker->recv([$tree . '/file'])->wait();
    is($status, 0);

    ok(-f 'file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    $status = unlink('file');
    ok($status);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive many files get same names'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $status = $worker->recv(
	[$tree . '/file', $tree . '/dir/other-file']
	)->wait();
    is($status, 0);

    ok(-f 'file');
    ok(-f 'other-file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    $status = unlink('file', 'other-file');
    ok($status);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive single file with target name'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $status = $worker->recv(
	[$tree . '/file'],
	TARGET => 'my-received-file'
	)->wait();
    is($status, 0);

    ok(-f 'my-received-file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    $status = unlink('my-received-file');
    ok($status);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive many files with target dir'} = sub
{
    plan tests => 6;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $status = mkdir('my-receive-dest');
    ok($status);

    $status = $worker->recv(
	[$tree . '/file', $tree . '/dir/other-file'],
	TARGET => 'my-receive-dest'
	)->wait();
    is($status, 0);

    ok(-f 'my-receive-dest/file');
    ok(-f 'my-receive-dest/other-file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    system('rm', '-rf', 'my-receive-dest');
    is($?, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive single file replace existing file'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $fh, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    return if (!open($fh, '>', 'my-replaced-file'));
    printf($fh 'some text');
    close($fh);

    $status = $worker->recv(
	[$tree . '/file'],
	TARGET => 'my-replaced-file'
	)->wait();
    is($status, 0);

    ok(-f 'my-replaced-file');
    ok(!(-s 'my-replaced-file'));

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    $status = unlink('my-replaced-file');
    ok($status);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive single directory'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $status = $worker->recv([$tree . '/dir'])->wait();
    is($status, 0);

    ok(-d 'dir');
    ok(-f 'dir/other-file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    system('rm', '-rf', 'dir');
    is($?, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive single directory with target name'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $status = $worker->recv(
	[$tree . '/dir'],
	TARGET => 'my-received-dir'
	)->wait();
    is($status, 0);

    ok(-d 'my-received-dir');
    ok(-f 'my-received-dir/other-file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    system('rm', '-rf', 'my-received-dir');
    is($?, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive single directory with target dir'} = sub
{
    plan tests => 6;

    my ($worker) = @_;
    my ($tree, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    $status = mkdir('my-dest-dir');
    ok($status);

    $status = $worker->recv(
	[$tree . '/dir'],
	TARGET => 'my-dest-dir'
	)->wait();
    is($status, 0);

    ok(-d 'my-dest-dir/dir');
    ok(-f 'my-dest-dir/dir/other-file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    system('rm', '-rf', 'my-dest-dir');
    is($?, 0);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'receive single directory with conflicting target'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($tree, $fh, $outter, $status);

    $tree = __make_remote_tree($worker);
    return if (!defined($tree));

    return if (!open($fh, '>', 'my-file'));
    printf($fh 'some text');
    close($fh);

    $outter = Minion::System::Process->new(sub {
	$status = $worker->recv(
	    [$tree . '/dir'],
	    TARGET => 'my-file'
	    )->wait();
	exit (0) if ($status == 0);
	exit (1);
    }, STDERR => '/dev/null')->wait();
    isnt($outter, 0);

    ok(-f 'my-file');

    $status = $worker->execute(['rm', '-rf', $tree])->wait();
    is($status, 0);

    $status = unlink('my-file');
    ok($status);
};


# Property tests ==============================================================

$TESTS{'list properties'} = sub
{
    plan tests => 2;

    my ($worker) = @_;
    my (@props);

    @props = $worker->list();

    ok(grep { defined($_) } @props);
    ok(grep { ref($_) eq '' } @props);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'get properties'} = sub
{
    plan tests => 3;

    my ($worker) = @_;
    my (@props, @values);

    @props = $worker->list();
    @values = map { $worker->get($_) } @props;

    is(scalar(@values), scalar(@props));
    ok(grep { defined($_) } @values);
    ok(grep { ref($_) eq '' } @values);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'set property'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($ret);

    ok(!grep { $_ eq 'my-property' } $worker->list());

    $ret = $worker->set('my-property', 'my-value');

    ok($ret);
    ok(grep { $_ eq 'my-property' } $worker->list());
    is($worker->get('my-property'), 'my-value');

    $ret = $worker->del('my-property');
    ok($ret);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'reset property'} = sub
{
    plan tests => 6;

    my ($worker) = @_;
    my ($ret);

    ok(!grep { $_ eq 'my-property' } $worker->list());

    $ret = $worker->set('my-property', 'my-value');
    ok($ret);

    $ret = $worker->set('my-property', 'my-new-value');
    ok($ret);

    ok(grep { $_ eq 'my-property' } $worker->list());
    is($worker->get('my-property'), 'my-new-value');

    $ret = $worker->del('my-property');
    ok($ret);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'set empty property'} = sub
{
    plan tests => 5;

    my ($worker) = @_;
    my ($ret);

    ok(!grep { $_ eq 'my-property' } $worker->list());

    $ret = $worker->set('my-property', '');

    ok($ret);
    ok(grep { $_ eq 'my-property' } $worker->list());
    is($worker->get('my-property'), '');

    $ret = $worker->del('my-property');
    ok($ret);
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'set property with empty name'} = sub
{
    plan tests => 3;

    my ($worker) = @_;
    my ($ret);

    ok(!grep { $_ eq '' } $worker->list());

    $ret = $worker->set('', 'my-value');

    ok(!$ret);
    ok(!grep { $_ eq '' } $worker->list());
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'set property with forbidden characters'} = sub
{
    plan tests => 31;

    my ($worker) = @_;
    my ($ret, @forbid, $c, $prop);

    @forbid = ('!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '=', ' ',
	       "\n", '<', '>', '?', '/', ',', '.', '+', '|', '\\', ';', '"',
	       "'", '`', '~', '{', '[', ']', '}');

    foreach $c (@forbid) {
	$prop = 'my-property' . $c;
	$ret = $worker->set($prop, 'my-value');
	ok(!$ret, $c);
    }
};

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

$TESTS{'del property'} = sub
{
    plan tests => 4;

    my ($worker) = @_;
    my ($ret);

    ok(!grep { $_ eq 'my-property' } $worker->list());

    $ret = $worker->set('my-property', 'my-value');
    ok($ret);

    $ret = $worker->del('my-property');

    ok($ret);
    ok(!grep { $_ eq 'my-property' } $worker->list());
};


1;
__END__
