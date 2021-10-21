package Minion::StaticFleet;

use parent qw(Minion::Fleet);
use strict;
use warnings;

use Carp qw(confess);

use Minion::Fleet;
use Minion::Worker;


sub _init
{
    my ($self, $workers, @err) = @_;

    confess() if (@err);
    confess() if (!defined($workers));
    confess() if (ref($workers) ne 'ARRAY');
    confess() if (grep { !Minion::Worker->comply($_) } @$workers);

    $self->{__PACKAGE__()}->{_members} = [ @$workers ];

    return $self->SUPER::_init();
}

sub members
{
    my ($self, @err) = @_;

    confess() if (@err);

    return @{$self->{__PACKAGE__()}->{_members}};
}


1;
__END__
