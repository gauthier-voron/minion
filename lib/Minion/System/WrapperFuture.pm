package Minion::System::WrapperFuture;

use strict;
use warnings;

use Carp qw(confess);

use Minion::System::Future;


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $inner, %opts) = @_;
    my ($mapout);

    confess() if (!defined($inner));
    confess() if (!Minion::System::Future->comply($inner));

    $mapout = sub { return shift(); };

    if (defined($mapout = $opts{MAPOUT})) {
	confess() if (ref($mapout) ne 'CODE');
	delete($opts{MAPOUT});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $self->{__PACKAGE__()}->{_inner} = $inner;
    $self->{__PACKAGE__()}->{_mapout} = $mapout;

    return $self;
}


sub exitstatus
{
    my ($self, @args) = @_;

    return $self->{__PACKAGE__()}->{_inner}->exitstatus(@args);
}

sub wait
{
    my ($self, @args) = @_;

    return $self->{__PACKAGE__()}->{_inner}->wait(@args);
}

sub trywait
{
    my ($self, @args) = @_;

    return $self->{__PACKAGE__()}->{_inner}->trywait(@args);
}

sub get
{
    my ($self, @args) = @_;
    my ($ret);

    $ret = $self->{__PACKAGE__()}->{_inner}->get();

    if (!defined($ret)) {
	return undef;
    }

    return $self->{__PACKAGE__()}->{_mapout}->($ret);
}


1;
__END__
