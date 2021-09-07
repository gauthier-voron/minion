package Minion::Io::WrapperHandle;

use parent qw(Minion::Io::Handle);
use strict;
use warnings;

use Carp qw(confess);
use Fcntl;

use Minion::Io::Handle;


sub _init
{
    my ($self, $fh, %opts) = @_;

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
    my ($self, @args) = @_;

    return $self->_fh()->autoflush(@args);
}

sub blocking
{
    my ($self, @args) = @_;

    return $self->_fh()->blocking(@args);
}

sub close
{
    my ($self, @args) = @_;

    return $self->_fh()->close(@args);
}

sub fcntl
{
    my ($self, @args) = @_;

    return $self->_fh()->fcntl(@args);
}

sub fileno
{
    my ($self, @args) = @_;

    return $self->_fh()->fileno(@args);
}

sub opened
{
    my ($self, @args) = @_;

    return $self->_fh()->opened(@args);
}

sub printf
{
    my ($self, @args) = @_;

    return $self->_fh()->printf(@args);
}

sub read
{
    my ($self, @args) = @_;

    return $self->_fh()->read(@args);
}

sub sysread
{
    my ($self, @args) = @_;

    return $self->_fh()->sysread(@args);
}

sub syswrite
{
    my ($self, @args) = @_;

    return $self->_fh()->syswrite(@args);
}


1;
__END__
