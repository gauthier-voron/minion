package Minion::Aws::Event;

use strict;
use warnings;

use Carp qw(confess);


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $time, $type, $message, @err) = @_;

    confess() if (@err);
    confess() if (!defined($time));
    confess() if (!defined($type));
    confess() if ($time !~ /^\d+$/);
    confess() if (ref($type) ne '');
    confess() if (defined($message) && (ref($message) ne ''));

    $self->{__PACKAGE__()}->{_time} = $time;
    $self->{__PACKAGE__()}->{_type} = $type;
    $self->{__PACKAGE__()}->{_message} = $message;

    return $self;
}


sub time
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_time};
}

sub type
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_type};
}

sub message
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_message};
}


1;
__END__

