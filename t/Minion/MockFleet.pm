package Minion::MockFleet;

use parent qw(Minion::Fleet);
use strict;
use warnings;

use Carp qw(confess);

use Minion::Worker;


sub _init
{
    my ($self, %opts) = @_;

    if (!defined($self->SUPER::_init(%opts))) {
	return undef;
    }

    $self->{__PACKAGE__()}->{_mocklog} = [];

    return $self;
}


sub _log_mock
{
    my ($self, $entry) = @_;

    push(@{$self->{__PACKAGE__()}->{_mocklog}}, $entry);
}

sub mock_log
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_mocklog};
}


sub members
{
    my ($self, @err) = @_;

    confess() if (@err);

    $self->_log_mock(['members']);

    return ();
}

sub execute
{
    my ($self, $cmd, %opts) = @_;

    $self->_log_mock(['execute', [ @$cmd ], { %opts }]);

    return ();
}

sub send
{
    my ($self, $sources, %opts) = @_;

    $self->_log_mock(['send', [ @$sources ], { %opts }]);

    return ();
}

sub recv
{
    my ($self, $sources, %opts) = @_;

    $self->_log_mock(['recv', [ @$sources ], { %opts }]);

    return ();
}

1;
__END__
