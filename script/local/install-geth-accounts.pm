package install_geth_accounts;

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray);

use Minion::System::Pgroup;
use Minion::System::Process;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};

my $PRIVATE = $ENV{MINION_PRIVATE};
my $KEYS_TXT_PATH = $PRIVATE . '/accounts.txt';
my $KEYS_JSON_PATH = $PRIVATE . '/accounts.json';

my ($number, $from, @err);
my ($pgrp, $proc);


# Parse options and check for sanity ------------------------------------------

GetOptionsFromArray(
    \@ARGV,
    'f|from=s'   => \$from,
    'n|number=i' => \$number
    );

@err = @ARGV;

if (@err) {
    die ("unexpected argument '" . shift(@err) . "'");
}

if (defined($from) && !(-d $from)) {
    die ("cannot find account directory '$from'");
}


# Import accounts from local directory ----------------------------------------

sub generate_json_accounts
{
    my ($txtpath, $jsonpath) = @_;
    my ($rfh, $wfh, $line, $address, $private, $sep);

    if (!open($rfh, '<', $txtpath)) {
	die ("cannot read '$txtpath' : $!");
    }

    if (!open($wfh, '>', $jsonpath)) {
	die ("cannot write '$jsonpath' : $!");
    }

    $sep = '[';

    while (defined($line = <$rfh>)) {
	chomp($line);

	if ($line !~ /^([0-9a-fA-F]+):([0-9a-f]+)$/) {
	    die ("accounts file '$txtpath' must be in format " .
		 "'hexaddress:hexprivate");
	}

	($address, $private) = ($1, $2);

	printf($wfh "%s\n", $sep);
	printf($wfh "    {\n");
        printf($wfh "        \"address\": \"0x%s\",\n", $address);
	printf($wfh "        \"private\": \"0x%s\"\n", $private);
	printf($wfh "    }");

	$sep = ',';
    }

    close($rfh);

    printf($wfh "\n]\n");

    close($wfh);
}

sub import_accounts
{
    my ($from, $number) = @_;
    my ($fh, $line, $count);

    if (defined($number)) {
	if (!open($fh, $from)) {
	    die ("cannot open accounts file '$from' : $!");
	}

	$count = 0;
	while (defined($line = <$fh>)) {
	    if ($count == $number) {
		last;
	    }
	}

	close($fh);

	if ($count < $number) {
	    die ("not enough entries in '$from' ($count) for the specified " .
		 "number ($number)");
	}
    }

    generate_json_accounts($from, $KEYS_JSON_PATH);

    $FLEET->execute([ 'mkdir', 'install' ], STDERRS => '/dev/null')->wait();
    $FLEET->execute(
	[ 'rm', '-rf', 'install/geth-accounts' ],
	STDERRS => '/dev/null'
	)->wait();

    $pgrp = $FLEET->execute([ 'mkdir', 'install/geth-accounts' ]);
    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	die ("cannot create install point on workers");
    }

    $pgrp = $FLEET->send(
	[ $from ],
	TARGETS => 'install/geth-accounts/accounts.txt'
	);
    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	die ("cannot send accounts on workers");
    }

    $pgrp = $FLEET->send(
	[ $KEYS_JSON_PATH ],
	TARGETS => 'install/geth-accounts/accounts.json'
	);
    if (grep { $_->exitstatus() != 0 } $pgrp->waitall()) {
	die ("cannot send json accounts on workers");
    }

    return 1;
}


# Generate accounts -----------------------------------------------------------

sub compute_accounts_subsets
{
    my ($number) = @_;
    my ($share, $rem, @procs, $worker, $job, $proc, @stats);

    $share = int($number / scalar($FLEET->members()));
    $rem = $number - $share * scalar($FLEET->members());

    foreach $worker ($FLEET->members()) {
	$job = $share + $rem;
	$rem = 0;
	if ($job == 0) {
	    continue;
	}

	$proc = $RUNNER->run(
	    $worker,
	    [ 'install-geth-accounts-worker', $job ]
	    );

	push(@procs, $proc);
    }

    @stats = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @stats) {
	die ("cannot generate accounts on workers");
    }
}

sub gather_accounts_subsets
{
    my ($path, $number) = @_;
    my (@procs, $worker, $proc, @stats, @subpaths, $subpath, $rfh,$wfh, $line);

    foreach $worker ($FLEET->members()) {
	$subpath = $PRIVATE . '/account-' . scalar(@procs) . '.txt';
	push(@subpaths, $subpath);

	$proc = $worker->recv(
	    [ 'install/geth-accounts/accounts.txt' ],
	    TARGET => $subpath
	    );
	push(@procs, $proc);
    }

    @stats = Minion::System::Pgroup->new(\@procs)->waitall();

    if (grep { $_->exitstatus() != 0 } @stats) {
	die ("cannot fetch accounts on workers");
    }

    if (!open($wfh, '>', $path)) {
	die ("cannot write accounts '$path' : $!");
    }

    foreach $subpath (@subpaths) {
	if (!open($rfh, '<', $subpath)) {
	    die ("cannot read accounts subset '$subpath' : $!");
	}

	while (defined($line = <$rfh>)) {
	    chomp($line);
	    printf($wfh "%s\n", $line);
	}

	close($rfh);

	unlink($subpath);
    }

    close($wfh);
}

sub generate_accounts
{
    my ($number) = @_;
    my ($subsets, $pgroup);

    if (!defined($number)) {
	$number = 1;
    }

    compute_accounts_subsets($number);

    gather_accounts_subsets($KEYS_TXT_PATH, $number);

    return import_accounts($KEYS_TXT_PATH);
}


if (defined($from)) {
    import_accounts($from, $number);
} else {
    generate_accounts($number);
}
__END__
