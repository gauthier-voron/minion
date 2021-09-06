package Minion::System::Future;

use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);

use Minion::System::Waitable;


sub comply
{
    my ($class, $obj, @err) = @_;

    confess() if (@err);
    confess() if (!defined($obj));

    if (Minion::System::Waitable->comply($obj) &&
	$obj->can('get')) {

	return 1;

    }

    return 0;
}


1;
__END__
