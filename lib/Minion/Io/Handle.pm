package Minion::Io::Handle;

use strict;
use warnings;

use Carp qw(confess);
use Fcntl;
use Scalar::Util qw(blessed);

use Minion::Io::GlobHandle;
use Minion::Io::WrapperHandle;


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $fh, @args) = @_;

    confess() if (!defined($fh));

    if (ref($fh) eq 'GLOB') {
	return Minion::Io::GlobHandle->new($fh, @args);
    }

    if (blessed($fh)) {
	if ($fh->isa(__PACKAGE__())) {
	    return $fh;
	}
	if ($fh->isa('IO::Handle')) {
	    return Minion::Io::WrapperHandle->new($fh, @args);
	}
    }

    confess();
}

sub mode
{
    my ($self, @err) = @_;

    confess() if (@err);

    return { 0 => 'r', 1 => 'w', 2 => 'rw' }->{$self->fcntl(F_GETFL, 0) & 3};
}


1;
__END__
