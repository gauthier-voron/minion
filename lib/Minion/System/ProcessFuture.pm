package Minion::System::ProcessFuture;

use parent qw(Minion::System::Process);
use strict;
use warnings;

use Carp qw(confess);

use Minion::System::Process;


sub _init
{
    my ($self, $routine, %opts) = @_;
    my (%sopts, $opt, $value, $mapout);

    confess() if (!defined($routine));
    confess() if (!grep { ref($routine) eq $_ } qw(CODE ARRAY));

    foreach $opt (qw(IO STDIN STDERR)) {
	if (defined($value = $opts{$opt})) {
	    $sopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    if (defined($mapout = $opts{MAPOUT})) {
	confess() if (ref($mapout) ne 'CODE');
	delete($opts{MAPOUT});
    } else {
	$mapout = sub { return shift(); };
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $self->{__PACKAGE__()}->{_out} = '';
    $self->{__PACKAGE__()}->{_mapout} = $mapout;

    return $self->SUPER::_init(
	$routine, %sopts,
	STDOUT => \$self->{__PACKAGE__()}->{_out}
	);
}


sub out
{
    my ($self, @err) = @_;

    confess() if (@err);

    if (!defined($self->exitstatus())) {
	return undef;
    }

    return $self->{__PACKAGE__()}->{_out};
}

sub get
{
    my ($self, @err) = @_;
    my ($status, $out);

    confess() if (@err);

    $status = $self->exitstatus();

    if (!defined($status)) {
	$status = $self->wait();
    }

    if ($status != 0) {
	return undef;
    }

    return $self->{__PACKAGE__()}->{_mapout}->($self->out());
}


1;
__END__
