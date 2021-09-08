package Minion::Aws::Instance;

use parent qw(Minion::Ssh);
use strict;
use warnings;

use Carp qw(confess);

use Minion::Aws::Cli;
use Minion::Ssh;


sub __check_ip4
{
    my ($ip) = @_;
    my ($i0, $i1, $i2, $i3, $mask);

    confess() if (!defined($ip));

    if ($ip =~ m|^(\d+)\.(\d+)\.(\d+)\.(\d+)(?:/(\d+))?$|) {
	($i0, $i1, $i2, $i3, $mask) = ($1, $2, $3, $4, $5);

	if (defined($mask) && ($mask > 32)) {
	    return 0;
	}

	if (($i0 < 256) && ($i1 < 256) && ($i2 < 256) && ($i3 < 256)) {
	    return 1;
	} else {
	    return 0;
	}
    } else {
	return 0;
    }
}


sub _init
{
    my ($self, $instance_id, $public_ip, $private_ip, $fleet_id, %opts) = @_;
    my (%sopts, $opt, $value);

    confess() if ($instance_id !~ /^i-[0-9a-f]+$/);
    confess() if (!__check_ip4($public_ip));
    confess() if (!__check_ip4($private_ip));
    confess() if ($fleet_id !~ /^sfr(?:-[0-9a-f]+)+$/);

    if (defined($value = $opts{REGION})) {
	$self->{__PACKAGE__()}->{_region} = $value;
	delete($opts{REGION});
    } else {
	$self->{__PACKAGE__()}->{_region} =
	    Minion::Aws::Cli->get_region()->get();
    }

    foreach $opt (qw(ERR LOG USER)) {
	if (defined($value = $opts{$opt})) {
	    $sopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $self->{__PACKAGE__()}->{_instance_id} = $instance_id;
    $self->{__PACKAGE__()}->{_public_ip} = $public_ip;
    $self->{__PACKAGE__()}->{_private_ip} = $private_ip;
    $self->{__PACKAGE__()}->{_fleet_id} = $fleet_id;

    return $self->SUPER::_init(
	$public_ip,
	ALIASES => {
	    'aws:id'         => sub { return $self->id() },
	    'aws:public-ip'  => sub { return $self->public_ip() },
	    'aws:private-ip' => sub { return $self->private_ip() },
	    'aws:region'     => sub { return $self->region() }
	}, %sopts);
}


sub id
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_instance_id};
}

sub public_ip
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_public_ip};
}

sub private_ip
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_private_ip};
}

sub region
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_region};
}


1;
__END__

