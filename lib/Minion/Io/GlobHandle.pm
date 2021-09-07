package Minion::Io::GlobHandle;

use parent qw(Minion::Io::Handle);
use strict;
use warnings;

use Carp qw(confess);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Scalar::Util qw(openhandle);

use Minion::Io::Handle;


sub _init
{
    my ($self, $fh, %opts) = @_;

    confess() if (!defined($fh));
    confess() if (ref($fh) ne 'GLOB');
    confess(join(' ', keys(%opts))) if (%opts);

    $self->{__PACKAGE__()}->{_fh} = $fh;

    return $self;
}


sub _fh
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_fh};
}


sub autoflush
{
    my ($self, $bool, @err) = @_;
    my ($old);

    confess() if (@err);
    confess() if (!defined($bool));
    confess() if (ref($bool) ne '');

    {
	$old = select($self->_fh());
	$| = $bool;
	select($old);
    }

    return 1;
}

sub blocking
{
    my ($self, $bool, @err) = @_;
    my ($fh, $flags);

    confess() if (@err);
    confess() if (!defined($bool));
    confess() if (ref($bool) ne '');

    $fh = $self->_fh();

    $flags = fcntl($fh, F_GETFL, 0);

    if ($bool) {
	$flags &= ~O_NONBLOCK;
    } else {
	$flags |= O_NONBLOCK;
    }

    fcntl($fh, F_SETFL, $flags);

    return 1;
}

sub close
{
    my ($self, @err) = @_;

    confess() if (@err);

    return close($self->_fh());
}

sub fcntl
{
    my ($self, $function, $scalar, @err) = @_;

    confess() if (@err);

    return fcntl($self->_fh(), $function, $scalar);
}

sub fileno
{
    my ($self, @err) = @_;

    confess() if (@err);

    return fileno($self->_fh());
}

sub opened
{
    my ($self, @err) = @_;

    confess() if (@err);

    if (defined(openhandle($self->_fh()))) {
	return 1;
    } else {
	return 0;
    }
}

sub printf
{
    my ($self, @args) = @_;
    my ($fh);

    $fh = $self->_fh();

    return printf($fh @args);
}

sub read
{
    my ($self, $_scalar, $length, $offset, @err) = @_;

    confess() if (@err);

    if (defined($offset)) {
	return read($self->_fh(), $_[1], $length, $offset);
    } else {
	return read($self->_fh(), $_[1], $length);
    }
}

sub sysread
{
    my ($self, $_scalar, $length, $offset, @err) = @_;

    confess() if (@err);

    if (defined($offset)) {
	return sysread($self->_fh(), $_[1], $length, $offset);
    } else {
	return sysread($self->_fh(), $_[1], $length);
    }
}

sub syswrite
{
    my ($self, $scalar, $length, $offset) = @_;

    if (defined($offset)) {
	return syswrite($self->_fh(), $scalar, $length, $offset);
    } elsif (defined($length)) {
	return syswrite($self->_fh(), $scalar, $length);
    } else {
	return syswrite($self->_fh(), $scalar);
    }
}


1;
__END__
