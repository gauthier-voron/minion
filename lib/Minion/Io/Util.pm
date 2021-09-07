package Minion::Io::Util;

use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(output_function);


sub output_function
{
    my ($output, @err) = @_;
    my ($ref, $fh);

    confess() if (@err);
    confess() if (!defined($output));

    $ref = ref($output);

    if ($ref eq '') {
	if (!open($fh, '>>', $output)) {
	    return undef;
	}

	return sub {
	    my ($data) = @_;

	    if (defined($data)) {
		printf($fh "%s", $data);
	    } else {
		close($fh);
	    }
	};
    } elsif ($ref eq 'SCALAR') {
	return sub {
	    my ($data) = @_;

	    if (defined($data)) {
		$$output .= $data;
	    }
	};
    } elsif ($ref eq 'GLOB') {
	return sub {
	    my ($data) = @_;

	    if (defined($data)) {
		printf($output "%s", $data);
	    }
	};
    } elsif (blessed($output) && $output->can('printf')) {
	return sub {
	    my ($data) = @_;

	    if (defined($data)) {
		$output->printf("%s", $data);
	    }
	};
    } elsif ($ref eq 'CODE') {
	return $output;
    } else {
	confess();
    }
}


1;
__END__
