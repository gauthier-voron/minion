package deploy_diem;

use strict;
use warnings;

use File::Copy;

use Minion::Run::Simd;


my $FLEET = $_;
my %PARAMS = @_;
my $RUNNER = $PARAMS{RUNNER};
my $DIEM_PATH = $ENV{MINION_SHARED} . '/diem';
my $ROLE_PATH = $DIEM_PATH . '/behaviors.txt';

sub generate_setup
{
    my ($path, $workers, $target) = @_;
    my ($ifh, $ofh, $line, $ip, $port, $worker, %groups, $tags);

    if (!open($ifh, '<', $path)) {
	return 0;
    }

    while (defined($line = <$ifh>)) {
	chomp($line);

	if ($line =~ /^([^:]+):(\d+)$/) {
	    ($ip, $port) = ($1, $2);
	} else {
	    close($ifh);
	    return 0;
	}

	$tags = undef;

	foreach $worker (@$workers) {
	    if ($worker->get('ssh:host') ne $ip) {
		next;
	    }

	    if ($worker->can('region')) {
		$tags = $worker->region();
	    } else {
		$tags = 'generic-region';
	    }

	    push(@{$groups{$tags}}, $line);
	}

	if (!defined($tags)) {
	    push(@{$groups{''}}, $line);
	}
    }

    close($ifh);

    if (!open($ofh, '>', $target)) {
	return 0;
    }

    printf($ofh "interface: \"diem\"\n");
    printf($ofh "\n");
    printf($ofh "confirm: \"pollblk\"\n");
    printf($ofh "\n");
    printf($ofh "endpoints:\n");

    foreach $tags (keys(%groups)) {
	printf($ofh "\n");
	printf($ofh "  - addresses:\n");
	foreach $line (@{$groups{$tags}}) {
	    printf($ofh "    - %s\n", $line);
	}
	printf($ofh "    tags:\n");
	foreach $line (split("\n", $tags)) {
	    printf($ofh "    - %s\n", $line);
	}
    }

    close($ofh);

    return 1;
}

sub deploy_diem
{
    my ($simd, $fh, $line, $ip, %workers, $worker, $assigned, @workers);

	if (!(-e $ROLE_PATH)) {
	return 1;
    }

    if (!open($fh, '<', $ROLE_PATH)) {
	return 0;
    }

    $simd = Minion::Run::Simd->new($RUNNER, []);

    while (defined($line = <$fh>)) {
	chomp($line);
	$ip = (split(':', $line))[0];

	if (exists($workers{$ip})) {
	    next;
	}

	$assigned = undef;

	foreach $worker ($FLEET->members()) {
	    if ($worker->can('public_ip') && ($worker->public_ip() eq $ip)) {
		$assigned = $worker;
		last;
	    } elsif ($worker->can('host') && ($worker->host() eq $ip)) {
		$assigned = $worker;
		last;
	    }
	}

	if (!defined($assigned)) {
	    die ("cannot find worker with ip '$ip' in deployment fleet");
	}

	$simd->add($assigned);
	push(@workers, $assigned);
    }

    close($fh);

    if (!move($ROLE_PATH, $simd->shared())) {
	return 0;
    }

    if (!$simd->run([ 'deploy-diem-worker' ])) {
	return 0;
    }

    if (!generate_setup($simd->shared() . '/nodes.conf', \@workers,
			$DIEM_PATH . '/setup.yaml')) {
	return 0;
    }

    if (!unlink($simd->shared() . '/nodes.conf')) {
	return 0;
    }

    if (!move($simd->shared() . '/accounts.yaml',
	      $DIEM_PATH . '/accounts.yaml')) {
	return 0;
    }

    system('ls', '-lR', $simd->shared());
    system('ls', '-lR', $DIEM_PATH);

    return 1;
}


deploy_diem();
__END__
