package Minion::Aws;

use strict;
use warnings;

use Carp qw(confess);

use Minion::Aws::Cli;
use Minion::Aws::Image;
use Minion::Io::Util qw(output_function);
use Minion::System::Pgroup;
use Minion::System::ProcessFuture;


require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
    find_images
    find_secgroups
    regions
);


sub find_images
{
    my ($str, %opts) = @_;
    my (@regions, $value, %outputs, %fopts, $log);

    if (defined($value = $opts{ERR})) {
	$fopts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	push(@{$fopts{IO}}, [ \$log, '>', $value ]);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGIONS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (scalar(@$value) < 1);
	@regions = @$value;
	delete($opts{REGIONS});
    } else {
	@regions = @{regions()};
    }

    confess(join(' ', keys(%opts))) if (%opts);

    return Minion::System::ProcessFuture->new(sub {
	my (%requests, @allreqs, $request, $field, $region, $result, $img);
	my (%copts);

	if (defined($log)) {
	    $copts{LOG} = $log;
	}

	foreach $region (@regions) {
	    foreach $field (qw(name description)) {
		$request = Minion::Aws::Cli->describe_images(
		    FILTERS => {
			$field => $str
		    },
		    QUERY => 'Images[*].{' .
			'Architecture:Architecture,' .
			'CreationDate:CreationDate,' .
			'Description:Description,' .
			'ImageId:ImageId,' .
		        'Name:Name,' .
		        'ProductCodes:ProductCodes' .
			'}',
		    REGION => $region,
		    %copts
		    );

		$requests{$region}->{$field} = $request;
		push(@allreqs, $request);
	    }
	}

	Minion::System::Pgroup->new(\@allreqs)->waitall();

	foreach $region (@regions) {
	    foreach $field (qw(name description)) {
		$request = $requests{$region}->{$field};
		$result = $request->get();

		if (!defined($result) || (scalar(@$result) < 1)) {
		    $result = undef;
		} else {
		    last;
		}
	    }

	    if (!defined($result)) {
		printf("\n");
		next;
	    }

	    $img = (sort { $b->{'CreationDate'} cmp $a->{'CreationDate'} }
		    grep { !defined($_->{'ProductCodes'}) }
		    grep { $_->{'Architecture'} eq 'x86_64' }
		    @$result)[0];

	    printf("%s:%s:%s\n", $img->{'ImageId'}, $img->{'Name'},
		   $img->{'Description'});
	}
    }, MAPOUT => sub {
	my ($res) = @_;
	my (%ret, @lines, $line, $region, $id, $name, $description);

	@lines = split("\n", $res);

	foreach $region (@regions) {
	    $line = shift(@lines);

	    if (defined($line)) {
		($id, $name, $description) = split(':', $line);
	    } else {
		$id = undef;
	    }

	    if (defined($id)) {
		$ret{$region} = Minion::Aws::Image->new(
		    $id,
		    DESCRIPTION => $description,
		    NAME => $name,
		    REGION => $region
		    );
	    } else {
		$ret{$region} = undef;
	    }
	}

	return \%ret;
    }, %fopts);
}


sub find_secgroups
{
    my ($name, %opts) = @_;
    my ($value, @regions, $region, %fopts, $log);

    if (defined($value = $opts{ERR})) {
	$fopts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	push(@{$fopts{IO}}, [ \$log, '>', $value ]);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGIONS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (scalar(@$value) < 1);
	@regions = @$value;
	delete($opts{REGIONS});
    } else {
	@regions = @{regions()};
    }

    confess(join(' ', keys(%opts))) if (%opts);

    return Minion::System::ProcessFuture->new(sub {
	my (@requests, $request, $result, $group, $id);

	foreach $region (@regions) {
	    $request = Minion::Aws::Cli->describe_security_groups(
		QUERY  => 'SecurityGroups[*].{' .
		    'GroupId:GroupId,' .
		    'GroupName:GroupName' .
		    '}',
		REGION => $region
		);
	    push(@requests, $request);
	}

	Minion::System::Pgroup->new(\@requests)->waitall();

	foreach $region (@regions) {
	    $request = shift(@requests);
	    $result = $request->get();

	    if (!defined($result)) {
		printf("\n");
		next;
	    }

	    $id = undef;

	    foreach $group (@$result) {
		if ($group->{'GroupName'} eq $name) {
		    $id = $group->{'GroupId'};
		    last;
		}
	    }

	    if (!defined($id)) {
		printf("\n");
		next;
	    }

	    printf("%s\n", $id);
	}
    }, MAPOUT => sub {
	my ($res) = @_;
	my (%ret, @lines, $line, $id);

	@lines = split("\n", $res);

	foreach $region (@regions) {
	    $line = shift(@lines);

	    if (defined($line)) {
		chomp($line);

		if ($line ne '') {
		    $ret{$region} = $line;
		    next;
		}
	    }

	    $ret{$region} = undef;
	}

	return \%ret;
    }, %fopts);
}


sub regions
{
    my (%opts) = @_;

    confess(join(' ', keys(%opts))) if (%opts);

    return Minion::Aws::Cli->describe_regions(
	QUERY => 'Regions[*].RegionName'
	)->get();
}


1;
__END__
