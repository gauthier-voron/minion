package Minion::System::Waitable;

use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);


sub comply
{
    my ($class, $obj, @err) = @_;

    confess() if (@err);
    confess() if (!defined($obj));

    if (blessed($obj) &&
	$obj->can('exitstatus') &&
	$obj->can('wait') &&
	$obj->can('trywait')) {

	return 1;

    }

    return 0;
}


1;
__END__
