package install_diablo_dev;

use strict;
use warnings;

use Minion::System::Pgroup;
use Minion::System::Process;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};

my ($from) = @ARGV;
my ($pgrp, $worker, $proc, $idx, @outs, @errs, $ws);

$pgrp = Minion::System::Pgroup->new([]);

foreach $worker ($FLEET->members()) {
    my @cmd = (
	 'rsync', '-aAHX',
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

$idx = 0;

foreach $ws ($pgrp->waitall()) {
    if ($ws->exitstatus() != 0) {
	printf("rsync[%d] failed:\n", $idx);
	printf("%s%s\n", $outs[$idx], $errs[$idx]);
    }

    $idx += 1;
}

$proc = $RUNNER->run($FLEET, ['install-diablo-dev-worker' , 'diablo-sources']);
if ($proc->wait() != 0) {
    die ("cannot install diablo from source '$from' on workers");
}


1;
__END__

