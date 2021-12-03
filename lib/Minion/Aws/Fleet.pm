package Minion::Aws::Fleet;

use parent qw(Minion::Fleet);
use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);
use Time::Local;

use Minion::Aws::Cli;
use Minion::Aws::Event;
use Minion::Aws::Image;
use Minion::Aws::Instance;
use Minion::Fleet;
use Minion::System::WrapperFuture;


sub _init
{
    my ($self, $id, %opts) = @_;
    my ($value);

    confess() if (!defined($id));
    confess() if ($id !~ /^sfr(?:-[0-9a-f]+)+$/);

    $self->{__PACKAGE__()}->{_id} = $id;
    $self->{__PACKAGE__()}->{_cache} = {};

    if (defined($value = $opts{ERR})) {
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{IMAGE})) {
	confess() if (!blessed($value) || !$value->isa('Minion::Aws::Image'));
	$self->{__PACKAGE__()}->{_cache}->{_image} = $value;
	delete($opts{IMAGE});
    }

    if (defined($value = $opts{KEY})) {
	confess() if (ref($value) ne '');
	$self->{__PACKAGE__()}->{_cache}->{_key} = $value;
	delete($opts{KEY});
    }

    if (defined($value = $opts{LOG})) {
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    }

    if (defined($value = $opts{PRICE})) {
	confess() if ($value !~ /^\d+(?:\.\d+)?$/);
	$self->{__PACKAGE__()}->{_cache}->{_price} = $value;
	delete($opts{PRICE});
    }

    if (defined($value = $opts{REGION})) {
	$self->{__PACKAGE__()}->{_region} = $value;
	delete($opts{REGION});
    } else {
	$self->{__PACKAGE__()}->{_region} =
	    Minion::Aws::Cli->get_region()->get() ;
    }

    if (defined($value = $opts{SECGROUP})) {
	confess() if ($value !~ /^sg-[0-9a-f]+$/);
	$self->{__PACKAGE__()}->{_cache}->{_secgroup} = $value;
	delete($opts{SECGROUP});
    }

    if (defined($value = $opts{SIZE})) {
	confess() if ($value !~ /^\d+$/);
	$self->{__PACKAGE__()}->{_cache}->{_size} = $value;
	delete($opts{SIZE});
    }

    if (defined($value = $opts{TYPE})) {
	confess() if ($value !~ /^[a-z]\d(?:[a-z]+)?\.[a-z0-9]+$/);
	$self->{__PACKAGE__()}->{_cache}->{_type} = $value;
	delete($opts{TYPE});
    }

    if (defined($value = $opts{USER})) {
	$self->{__PACKAGE__()}->{_user} = $value;
	delete($opts{USER});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    return $self->SUPER::_init();
}


sub launch
{
    my ($class, $image, $type, %opts) = @_;
    my (%copts, %nopts, %iopts, $opt, $value, $logger_error, $cli);

    confess() if (!defined($image));
    confess() if ($image !~ /^ami-[0-9a-f]+$/);
    confess() if (!defined($type));
    confess() if ($type !~ /^[a-z]\d(?:[a-z]+)?\.[a-z0-9]+$/);

    if (defined($value = $opts{TIME})) {
	$copts{TIME} = $value;
	delete($opts{TIME});
    }

    if (defined($value = $opts{USER})) {
	$nopts{USER} = $value;
	delete($opts{USER});
    }

    foreach $opt (qw(ERR KEY LOG PRICE SECGROUP SIZE)) {
	if (defined($value = $opts{$opt})) {
	    $copts{$opt} = $value;
	    $nopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    if (defined($value = $opts{REGION})) {
	$copts{REGION} = $value;
	$nopts{REGION} = $value;
	$iopts{REGION} = $value;
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $cli = Minion::Aws::Cli->request_spot_fleet($image, $type, %copts);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;
	my $id = $reply->{'SpotFleetRequestId'};

	return $class->new(
	    $id,
	    IMAGE => Minion::Aws::Image->new($image, %iopts),
	    TYPE  => $type,
	    %nopts);
    });
}

sub cancel
{
    my ($self, @err) = @_;
    my (%copts, $id, $region, $cli);

    confess() if (@err);

    $cli = Minion::Aws::Cli->cancel_spot_fleet_requests(
	[ $self->id() ],
	REGION => $self->region(),
	$self->_lopts()
	);

    return $cli;
}


sub id
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_id};
}

sub region
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_region};
}

sub user
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_user};
}


sub _log
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_log};
}

sub _err
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_err};
}

sub _lopts
{
    my ($self) = @_;
    my (%lopts, $value);

    if (defined($value = $self->_err())) {
	$lopts{ERR} = $value;
    }

    if (defined($value = $self->_log())) {
	$lopts{LOG} = $value;
    }

    return %lopts;
}


sub __make_event_from_history
{
    my ($event) = @_;
    my ($info, $type, $time, $message, $subtype);
    my ($sec, $min, $hour, $day, $month, $year);

    $info = $event->{'EventInformation'};
    $type = $event->{'EventType'};
    $time = $event->{'Timestamp'};

    if (defined($info)) {
	$message = $info->{'EventDescription'};
	$subtype = $info->{'EventSubType'};

	if (defined($subtype)) {
	    $type = $subtype;
	}
    }

    if ($time =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?Z$/) {
	($year, $month, $day, $hour, $min, $sec) = ($1, $2, $3, $4, $5, $6);
	$month -= 1;
	$year -= 1900;
	$time = timegm($sec, $min, $hour, $day, $month, $year);
    } else {
	$time = 0;
    }

    return Minion::Aws::Event->new($time, $type, $message);
}

sub history
{
    my ($self, @err) = @_;
    my ($cli);

    confess() if (@err);

    $cli = Minion::Aws::Cli->describe_spot_fleet_request_history(
	$self->id(), 3600 * 24 * 365,
	REGION => $self->region(),
	$self->_lopts()
	);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;

	return [
	    map { __make_event_from_history($_) }
	    @{$reply->{'HistoryRecords'}}
	    ];
    });
}


sub _make_instance_from_info
{
    my ($self, $info, $iopts) = @_;
    my ($id, $public_ip, $private_ip) = split(':', $info);
    my ($opt);

    return Minion::Aws::Instance->new(
	$id, $public_ip, $private_ip, $self->id(),
	%$iopts
	);
}

sub instances
{
    my ($self, %opts) = @_;
    my (%outputs, %copts, %fopts, %iopts, $opt, $value, $log);

    %iopts = $self->_lopts();

    foreach $opt (qw(ERR LOG)) {
	if (defined($value = $opts{$opt})) {
	    $iopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $iopts{REGION} = $self->region();

    if (defined($value = $self->user())) {
	$iopts{USER} = $value;
    }

    if (defined($value = $self->_err())) {
	$fopts{STDERR} = $value;
    }

    if (defined($value = $self->_log())) {
	push(@{$fopts{IO}}, [ \$log, '>', $value ]);
    }

    my $ret = Minion::System::ProcessFuture->new(sub {
	my ($ids, $desc, $rdesc, $idesc, $field);

	if (defined($log)) {
	    $copts{LOG} = $log;
	}

	$ids = Minion::Aws::Cli->describe_spot_fleet_instances(
	    $self->id(),
	    QUERY  => 'ActiveInstances[*].InstanceId',
	    REGION => $self->region(),
	    %copts
	    )->get();

	if (!defined($ids)) {
	    exit (1);
	} elsif (scalar(@$ids) == 0) {
	    exit (0);
	}

	my $tmp = Minion::Aws::Cli->describe_instances(
	    IDS    => [ @$ids ],
	    QUERY  => 'Reservations[*].Instances[*].[' .
	              'InstanceId,' .
	              'PublicIpAddress,' .
	              'PrivateIpAddress' .
	              ']',
	    REGION => $self->region(),
	    %copts
	    );
	$desc = $tmp->get();

	if (!defined($desc)) {
	    exit (1);
	}

	foreach $rdesc (@$desc) {
	    foreach $idesc (@$rdesc) {
		next if (grep { !defined($_) || ($_ eq '') } @$idesc);
	    
		printf("%s\n", join(':', @$idesc));
	    }
	}
    }, MAPOUT => sub {
	my ($reply) = @_;
	my ($ret);

	$ret = [ map { $self->_make_instance_from_info($_, \%iopts) }
		 split("\n", $reply) ];

	$self->{__PACKAGE__()}->{_cache}->{_members} = $ret;

	return $ret;
    }, %fopts);

    return $ret;
}


sub status
{
    my ($self, @err) = @_;
    my ($cli);

    confess() if (@err);

    $cli = Minion::Aws::Cli->describe_spot_fleet_requests(
	IDS    => [ $self->id() ],
	QUERY  => 'SpotFleetRequestConfigs[*].SpotFleetRequestState',
	REGION => $self->region(),
	$self->_lopts()
	);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;

	return $reply->[0];
    });
}


sub update
{
    my ($self, @err) = @_;
    my ($cli);

    confess() if (@err);

    $cli = Minion::Aws::Cli->describe_spot_fleet_requests(
	IDS    => [ $self->id() ],
	REGION => $self->region(),
	QUERY  => 'SpotFleetRequestConfigs[0].SpotFleetRequestConfig.{' .
	          'Image:LaunchSpecifications[0].ImageId,' .
	          'Key:LaunchSpecifications[0].KeyName,' .
	          'Price:SpotPrice,' .
	          'Sg:LaunchSpecifications[0].SecurityGroups[0].GroupId,' .
	          'Size:TargetCapacity,' .
	          'Type:LaunchSpecifications[0].InstanceType' .
	          '}',
	$self->_lopts()
	);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;

	if (!defined($reply)) {
	    return undef;
	}

	$self->{__PACKAGE__()}->{_cache}->{_image} = Minion::Aws::Image->new(
	    $reply->{'Image'},
	    REGION => $self->region()
	    );

	$self->{__PACKAGE__()}->{_cache}->{_key} = $reply->{'Key'};
	$self->{__PACKAGE__()}->{_cache}->{_price} = $reply->{'Price'};
	$self->{__PACKAGE__()}->{_cache}->{_secgroup} = $reply->{'Sg'};
	$self->{__PACKAGE__()}->{_cache}->{_size} = $reply->{'Size'};
	$self->{__PACKAGE__()}->{_cache}->{_type} = $reply->{'Type'};

	return 1;
    });
}

sub _get_cached
{
    my ($self, $name, @err) = @_;
    my ($ret);

    confess() if (@err);

    $ret = $self->{__PACKAGE__()}->{_cache}->{$name};

    if (!defined($ret)) {
	$self->update()->get();
	$ret = $self->{__PACKAGE__()}->{_cache}->{$name};
    }

    return $ret;
}

sub image
{
    my ($self, @args) = @_;

    return $self->_get_cached('_image', @args);
}

sub key
{
    my ($self, @args) = @_;

    return $self->_get_cached('_key', @args);
}

sub price
{
    my ($self, @args) = @_;

    return $self->_get_cached('_price', @args);
}

sub secgroup
{
    my ($self, @args) = @_;

    return $self->_get_cached('_secgroup', @args);
}

sub size
{
    my ($self, @args) = @_;

    return $self->_get_cached('_size', @args);
}

sub type
{
    my ($self, @args) = @_;

    return $self->_get_cached('_type', @args);
}


sub members
{
    my ($self, @err) = @_;
    my ($members, $size);

    confess() if (@err);

    $members = $self->{__PACKAGE__()}->{_cache}->{_members};
    $size = $self->size();

    while (!defined($members) || (scalar(@$members) < $size)) {
	$self->instances()->get();
	$members = $self->{__PACKAGE__()}->{_cache}->{_members};
    }

    return @$members;
}


1;
__END__
