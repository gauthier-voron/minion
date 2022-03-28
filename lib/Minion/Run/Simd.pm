package Minion::Run::Simd;

use strict;
use warnings;

use Carp qw(confess);
use File::Copy;
use File::Path qw(remove_tree);
use File::Temp;

use Minion::System::Pgroup;
use Minion::Worker;


use constant {
    REMOTE_TRUNK_PATH => '.minion-simd',
    REMOTE_TASK_PATH  => '.minion-simd-task',
};

sub REMOTE_DATA_PATH
{
    my ($root) = @_;

    return $root . '/data';
}


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $runner, $workers, %opts) = @_;
    my ($localdata, $sharedata, $value);

    confess() if (!defined($runner));
    confess() if (!defined($workers));
    confess() if (ref($workers) ne 'ARRAY');
    confess() if (grep { !Minion::Worker->comply($_) } @$workers);
    confess(join(' ', keys(%opts))) if (%opts);

    $localdata = File::Temp->newdir('minion.simd.XXXXXX', SUFFIX => '.d');
    $sharedata = $localdata . '/shared';

    if (!mkdir($sharedata)) {
	return undef;
    }

    $self->{__PACKAGE__()}->{_runner} = $runner;
    $self->{__PACKAGE__()}->{_workers} = [ @$workers ];
    $self->{__PACKAGE__()}->{_local} = $localdata;
    $self->{__PACKAGE__()}->{_share} = $sharedata;

    return $self;
}


sub add
{
    my ($self, $worker, @err) = @_;

    confess() if (!defined($worker));
    confess() if (!Minion::Worker->comply($worker));
    confess() if (@err);

    push(@{$self->{__PACKAGE__()}->{_workers}}, $worker);

    return 1;
}

sub shared
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_share};
}


sub _send_simd_files
{
    my ($self, $cmd) = @_;
    my ($workers, $trunks, $paths, $pgrp, $proc, $i);

    $workers = $self->{__PACKAGE__()}->{_workers};
    $trunks = $self->{__PACKAGE__()}->{_runner}->resolve($workers, [ 'simd' ]);
    $paths = $self->{__PACKAGE__()}->{_runner}->resolve($workers, $cmd);

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < scalar(@$workers); $i++) {
	$proc = $workers->[$i]->send(
	    [ $trunks->[$i] ],
	    TARGET => REMOTE_TRUNK_PATH
	    );
	$pgrp->add($proc);

	$proc = $workers->[$i]->send(
	    [ $paths->[$i] ],
	    TARGET => REMOTE_TASK_PATH
	    );
	$pgrp->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	return 0;
    }

    return 1;
}

sub _run_remote_simd_setup
{
    my ($self) = @_;
    my ($workers, $pgrp, $proc, $i, @roots, $root, @setupcmd);

    $workers = $self->{__PACKAGE__()}->{_workers};

    if (substr(REMOTE_TRUNK_PATH, 0, 1) eq '/') {
	push(@setupcmd, REMOTE_TRUNK_PATH);
    } else {
	push(@setupcmd, './' . REMOTE_TRUNK_PATH);
    }

    push(@setupcmd, 'setup', REMOTE_TASK_PATH, scalar(@$workers));

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < scalar(@$workers); $i++) {
	push(@roots, '');

	$proc = $workers->[$i]->execute(\@setupcmd, STDOUT => \$roots[$i]);

	$pgrp->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	return undef;
    }

    for ($i = 0; $i < scalar(@$workers); $i++) {
	chomp($roots[$i]);
    }

    return \@roots;
}

sub _init_local_data
{
    my ($self) = @_;
    my ($localdata, $sharedata, $num, $i, $j, $dest);

    $localdata = $self->{__PACKAGE__()}->{_local};
    $sharedata = $self->{__PACKAGE__()}->{_share};
    $num = scalar(@{$self->{__PACKAGE__()}->{_workers}});

    for ($i = 0; $i < $num; $i++) {
	if (!mkdir($localdata . '/' . $i)) {
	    return 0;
	}

	for ($j = 0; $j < $num; $j++) {
	    $dest = $localdata . '/' . $i . '/' . $j;

	    if (($i == 0) && ($j == 0)) {
		if (!rename($sharedata, $dest)) {
		    return 0;
		}
	    } elsif (!mkdir($dest)) {
		return 0;
	    }
	}
    }

    return 1;
}

sub _setup_simd
{
    my ($self, $cmd) = @_;
    my ($remtrunk, $rempath, $remdata, $roots);

    if (!$self->_init_local_data()) {
	return undef;
    }

    if (!$self->_send_simd_files($cmd)) {
	return undef;
    }

    $roots = $self->_run_remote_simd_setup();
    if (!defined($roots)) {
	return undef;
    }

    if (!$self->_push_files($roots)) {
	return undef;
    }

    return $roots;
}

sub _teardown_simd
{
    my ($self, $roots) = @_;
    my ($workers, $localdata, $sharedata, $pgrp, $proc, $i, @cmd);

    $workers = $self->{__PACKAGE__()}->{_workers};
    $localdata = $self->{__PACKAGE__()}->{_local};
    $sharedata = $self->{__PACKAGE__()}->{_share};

    if (substr(REMOTE_TRUNK_PATH, 0, 1) eq '/') {
	push(@cmd, REMOTE_TRUNK_PATH);
    } else {
	push(@cmd, './' . REMOTE_TRUNK_PATH);
    }

    push(@cmd, 'clean');

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < scalar(@$workers); $i++) {
	$proc = $workers->[$i]->execute([
	    @cmd, $roots->[$i]
	]);

	$pgrp->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	return 0;
    }

    if (!rename($localdata . '/0/0', $sharedata)) {
	return 0;
    }

    return 1;
}

sub syncfrom
{
    my ($worker, $source, $target) = @_;
    my ($value, $clear);

    confess() if (!defined($source));
    confess() if (!defined($target));

    if (-e $target) {
	if (system('rm', '-rf', $target)) {
	    return Minion::System::Process->new(sub { exit (1); });
	}
    }

    return $worker->recv([ $source ], TARGET => $target);
}

sub _fetch_files
{
    my ($self, $roots) = @_;
    my ($workers, $localdata, $pgrp, $proc, $i);

    $workers = $self->{__PACKAGE__()}->{_workers};
    $localdata = $self->{__PACKAGE__()}->{_local};

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < scalar(@$workers); $i++) {
	$proc = syncfrom(
	    $workers->[$i],
	    REMOTE_DATA_PATH($roots->[$i]),
	    $localdata . '/' . $i,
	    );

	$pgrp->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	return 0;
    }

    return 1;
}

sub syncto
{
    my ($worker, $source, $target) = @_;

    confess() if (!defined($source));
    confess() if (!defined($target));

    return Minion::System::Process->new(sub {
	$worker->execute([ 'rm', '-rf', $target ])->wait();
	return $worker->send([ $source ], TARGET => $target)->wait();
    });
}

sub _push_files
{
    my ($self, $roots) = @_;
    my ($workers, $localdata, $pgrp, $proc, $i);

    $workers = $self->{__PACKAGE__()}->{_workers};
    $localdata = $self->{__PACKAGE__()}->{_local};

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < scalar(@$workers); $i++) {
	$proc = syncto(
	    $workers->[$i],
	    $localdata . '/' . $i,
	    REMOTE_DATA_PATH($roots->[$i])
	    );

	$pgrp->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	return 0;
    }

    return 1;
}

sub _start_simd
{
    my ($self, $cmd, $roots) = @_;
    my ($workers, @procs, $proc, $i, @args, @startcmd);

    $workers = $self->{__PACKAGE__()}->{_workers};

    if (substr(REMOTE_TRUNK_PATH, 0, 1) eq '/') {
	push(@startcmd, REMOTE_TRUNK_PATH);
    } else {
	push(@startcmd, './' . REMOTE_TRUNK_PATH);
    }

    push(@startcmd, 'start');

    @args = @$cmd;
    shift(@args);

    for ($i = 0; $i < scalar(@$workers); $i++) {
	$proc = $workers->[$i]->execute([
	    @startcmd, $roots->[$i], $i, scalar(@$workers), @args
	]);

	push(@procs, $proc);
    }

    return \@procs;
}

sub _wait_fence
{
    my ($self, $procs, $roots, $op) = @_;
    my ($workers, $pgrp, $proc, $i, @cmd, $npoll, $err, @info, $type);

    $workers = $self->{__PACKAGE__()}->{_workers};

    if (substr(REMOTE_TRUNK_PATH, 0, 1) eq '/') {
	push(@cmd, REMOTE_TRUNK_PATH);
    } else {
	push(@cmd, './' . REMOTE_TRUNK_PATH);
    }

    push(@cmd, $op);

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < scalar(@$procs); $i++) {
	$pgrp->add([ $procs->[$i], 'proc', $i ]);
    }

    for ($i = 0; $i < scalar(@$workers); $i++) {
	$proc = $workers->[$i]->execute([
	    @cmd, $roots->[$i]
	]);

	$pgrp->add([ $proc, 'poll', $i ]);
    }

    $npoll = scalar(@$workers);
    $err = 0;

    while ($npoll > 0) {
	@info = $pgrp->wait();

	if (scalar(@info) == 0) {
	    last;
	}

	($proc, $type, $i) = @info;

	if ($type ne 'poll') {
	    next;
	}

	if ($proc->exitstatus() != 0) {
	    $err = 1;
	}

	$npoll -= 1;
    }

    if ($err) {
	return 0;
    }

    return 1;
}

sub _fuse_files
{
    my ($self, $num) = @_;
    my ($localdata, $fusedata, $pgrp, $proc, $i, $j, $ret);

    $localdata = $self->{__PACKAGE__()}->{_local};
    $fusedata = File::Temp->newdir('minion.simd.XXXXXX', SUFFIX => '.d');

    for ($i = 0; $i < $num; $i++) {
	if (!mkdir($fusedata . '/' . $i)) {
	    return 0;
	}

	for ($j = 0; $j < $num; $j++) {
	    if ($i != $j) {
		if (!mkdir($fusedata . '/' . $i . '/' . $j)) {
		    return 0;
		}
	    }
	}
    }

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < $num; $i++) {
	$proc =  Minion::System::Process->new(sub {
	    for ($j = 0; $j < $num; $j++) {
		$ret = Minion::System::Process->new([
		    'rsync', '-aAHXzc',
		    $localdata . '/' . $j . '/' . $i . '/',
		    $fusedata . '/' . $i . '/' . $i . '/'
		])->wait();

		if ($ret != 0) {
		    exit (1);
		}
	    }
	});

	$pgrp->add($proc);
    }

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	return 0;
    }

    if (!remove_tree($localdata)) {
	return 0;
    }

    if (!rename($fusedata, $localdata)) {
	return 0;
    }

    return 1;
}

sub _sync_fence
{
    my ($self, $roots) = @_;

    if (!$self->_fetch_files($roots)) {
	return 0;
    }

    if (!$self->_fuse_files(scalar(@$roots))) {
	return 0;
    }

    if (!$self->_push_files($roots)) {
	return 0;
    }

    return 1;
}

sub _notify_fence_done
{
    my ($self, $roots) = @_;
    my ($workers, $pgrp, $proc, $i, @cmd);

    $workers = $self->{__PACKAGE__()}->{_workers};

    if (substr(REMOTE_TRUNK_PATH, 0, 1) eq '/') {
	push(@cmd, REMOTE_TRUNK_PATH);
    } else {
	push(@cmd, './' . REMOTE_TRUNK_PATH);
    }

    push(@cmd, 'synced');

    $pgrp = Minion::System::Pgroup->new([]);

    for ($i = 0; $i < scalar(@$workers); $i++) {
	$proc = $workers->[$i]->execute([
	    @cmd, $roots->[$i]
	]);

	$pgrp->add([ $proc, $i ]);
    }

    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	return 0;
    }

    return 1;
}

sub _coordinate_fence
{
    my ($self, $procs, $roots) = @_;

    if (!$self->_wait_fence($procs, $roots, 'poll')) {
	return 1;
    }

    while (1) {
	if (!$self->_sync_fence($roots)) {
	    return 0;
	}

	if (!$self->_wait_fence($procs, $roots, 'repoll')) {
	    return 1;
	}
    }

    return 1;
}

sub run
{
    my ($self, $cmd) = @_;
    my ($roots, $procs);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (scalar(@$cmd) < 1);

    $roots = $self->_setup_simd($cmd);
    if (!defined($roots)) {
	return 0;
    }

    $procs = $self->_start_simd($cmd, $roots);
    if (!defined($procs)) {
	$self->_teardown_simd($roots);
	return 0;
    }

    if (!$self->_coordinate_fence($procs, $roots)) {
	$self->_teardown_simd($roots);
	return 0;
    }

    if (!$self->_fetch_files($roots)) {
	return 0;
    }

    if (!$self->_teardown_simd($roots)) {
	return 0;
    }

    return 1;
}


1;
__END__
