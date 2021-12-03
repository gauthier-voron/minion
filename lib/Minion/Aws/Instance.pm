package Minion::Aws::Instance;

use parent qw(Minion::Ssh);
use strict;
use warnings;

use Carp qw(confess);

use Minion::Aws::Cli;
use Minion::Ssh;
use Minion::System::ProcessFuture;


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

    if (defined($value = $opts{ERR})) {
	$sopts{ERR} = $value;
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$sopts{LOG} = $value;
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGION})) {
	$self->{__PACKAGE__()}->{_region} = $value;
	delete($opts{REGION});
    } else {
	$self->{__PACKAGE__()}->{_region} =
	    Minion::Aws::Cli->get_region()->get();
    }

    if (defined($value = $opts{USER})) {
	$sopts{USER} = $value;
	delete($opts{USER});
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


sub snapshot
{
    my ($self, $name, %opts) = @_;
    my (%copts, $value, $cli);

    confess() if (!defined($name));

    if (defined($value = $opts{DESCRIPTION})) {
	$copts{DESCRIPTION} = $value;
	delete($opts{DESCRIPTION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$copts{ERR} = $value;
    }

    if (defined($value = $self->{__PACKAGE__()}->{_log})) {
	$copts{LOG} = $value;
    }

    $cli = Minion::Aws::Cli->create_image($self->id(), $name, %copts);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;
	my $id = $reply->{'ImageId'};

	return Minion::Aws::Image->new($id, REGION => $self->region());
    });
}

sub resize
{
    my ($self, $size, @err) = @_;
    my (%fopts, %copts, $value, $log);

    confess() if (@err);
    confess() if (!defined($size));
    confess() if (ref($size) ne '');
    confess() if ($size !~ /^\d+$/);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$fopts{STDERR} = $value;
    }

    if (defined($value = $self->{__PACKAGE__()}->{_log})) {
	push(@{$fopts{IO}}, [ \$log, '>', $value ]);
    }

    return Minion::System::ProcessFuture->new(sub {
	my ($volume, $cli, $mstate);

	if (defined($log)) {
	    $copts{LOG} = $log;
	}

	$volume = Minion::Aws::Cli->describe_volumes(
	    FILTERS => { 'attachment.instance-id' => $self->id() },
	    QUERY   => 'Volumes[0].Attachments[0].VolumeId',
	    REGION  => $self->region(),
	    %copts
	    )->get();

	if (!defined($volume)) {
	    exit (1);
	}

	$cli = Minion::Aws::Cli->modify_volume(
	    $volume,
	    REGION => $self->region(),
	    SIZE   => $size,
	    %copts);
	if ($cli->wait() != 0) {
	    exit ($cli->exitstatus() >> 8);
	}

	$mstate = 'modifying';

	while ($mstate eq 'modifying') {
	    $mstate = Minion::Aws::Cli->describe_volumes_modifications(
		IDS    => [ $volume ],
		QUERY  => 'VolumesModifications[0].ModificationState',
		REGION => $self->region(),
		%copts
		)->get();

	    if (!defined($mstate)) {
		exit (1);
	    }

	    sleep(5);
	}
    }, %fopts);
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

