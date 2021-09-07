package Minion::System::ReactItem;

use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);

use Minion::Io::Handle;


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $handle, $code, @err) = @_;

    confess() if (@err);
    confess() if (!defined($handle));
    confess() if (!defined($code));
    confess() if (!blessed($handle)||!$handle->isa('Minion::Io::Handle'));
    confess() if (ref($code) ne 'CODE');

    $self->{__PACKAGE__()}->{_handle} = $handle;
    $self->{__PACKAGE__()}->{_code} = $code;
    $self->{__PACKAGE__()}->{_buffer} = undef;
    $self->{__PACKAGE__()}->{_offset} = 0;

    return $self;
}


sub update
{
    my ($self, $buffer, $offset, @err) = @_;

    confess() if (@err);
    confess() if (!defined($offset));
    confess() if (defined($buffer) && (ref($buffer) ne ''));
    confess() if ($offset !~ /^\d+$/);

    $self->{__PACKAGE__()}->{_buffer} = $buffer;
    $self->{__PACKAGE__()}->{_offset} = $offset;

    return 1;
}


sub handle
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_handle};
}

sub code
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_code};
}

sub buffer
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_buffer};
}

sub offset
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_buffer};
}


1;
__END__
