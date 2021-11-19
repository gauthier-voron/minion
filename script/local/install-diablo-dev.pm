package install_diablo_dev;

use strict;
use warnings;

use Minion::System::Pgroup;
use Minion::System::Process;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};

my ($from) = @ARGV;
my ($pgrp, $worker, $proc, $idx, @outs, @errs, $ws, $retry, $failed);

$retry = 0;

loop: while (1) {
    $pgrp = Minion::System::Pgroup->new([]);

    foreach $worker ($FLEET->members()) {
	my @cmd = (
	    'rsync', '-aAHXv',
	    '-e', 'ssh -o StrictHostKeyChecking=no ' .
	              '-o UserKnownHostsFile=/dev/null ' .
	              '-o LogLevel=ERROR',
	    $from . '/',
	    'ubuntu@' . $worker->public_ip() . ':diablo-sources/'
	    );

	$idx = scalar(@outs);

	push(@outs, '');
	push(@errs, '');

	$proc = Minion::System::Process->new(
	    \@cmd,
	    STDOUT => \$outs[$idx],
	    STDERR => \$errs[$idx]
	    );

	$pgrp->add($proc);
    }

    if ($retry == 0) {
	foreach $ws ($pgrp->waitall()) {
	    if ($ws->exitstatus() != 0) {
		$proc = $RUNNER->run(
		    $FLEET,
		    [ 'install-diablo-dev-worker' ]);
		if ($proc->wait() != 0) {
		    die ("cannot install diablo on workers");
		}

		$retry = 1;
		next loop;
	    }
	}
    } else {
	$idx = 0;
	$failed = 0;
	foreach $ws ($pgrp->waitall()) {
	    if ($ws->exitstatus() != 0) {
		printf(STDOUT "%s", $outs[$idx]);
		printf(STDERR "%s", $errs[$idx]);
		$failed += 1;
	    }
	    $idx += 1;
	}

	if ($failed > 0) {
	    die ("$failed workers failed to sync");
	}
    }

    last;
}

$proc = $RUNNER->run($FLEET, ['install-diablo-dev-worker' , 'diablo-sources']);
if ($proc->wait() != 0) {
    die ("cannot install diablo from source '$from' on workers");
}


1;
__END__

