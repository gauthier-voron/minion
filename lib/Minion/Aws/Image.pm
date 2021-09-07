package Minion::Aws::Image;

use strict;
use warnings;

use Carp qw(confess);

use Minion::Aws::Cli;
use Minion::Io::Util qw(output_function);
use Minion::System::Pgroup;
use Minion::System::WrapperFuture;


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $id, %opts) = @_;
    my ($value, $name, $description);

    confess() if (!defined($id));
    confess() if ($id !~ /^ami-[0-9a-f]+$/);

    if (defined($description = $opts{DESCRIPTION})) {
	confess() if (ref($description) ne '');
	delete($opts{DESCRIPTION});
    }

    if (defined($value = $opts{ERR})) {
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    }

    if (defined($name = $opts{NAME})) {
	confess() if (ref($name) ne '');
	delete($opts{NAME});
    }

    if (defined($value = $opts{REGION})) {
	confess if (ref($value) ne '');
	$self->{__PACKAGE__()}->{_region} = $value;
	delete($opts{REGION});
    } else {
	$self->{__PACKAGE__()}->{_region} =
	    Minion::Aws::Cli->get_region()->get();
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $self->{__PACKAGE__()}->{_id} = $id;
    $self->{__PACKAGE__()}->{_cache} = {
	_description => $description,
	_name => $name
    };

    return $self;
}


sub _err
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_err};
}

sub _log
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_log};
}

sub _lopts
{
    my ($self) = @_;
    my (%ret, $value);

    if (defined($value = $self->_err())) {
	$ret{ERR} = $value;
    }

    if (defined($value = $self->_log())) {
	$ret{LOG} = $value;
    }

    return %ret;
}


sub update
{
    my ($self, %opts) = @_;
    my ($cli, $opt, $value);

    confess(join(' ', keys(%opts))) if (%opts);

    $cli = Minion::Aws::Cli->describe_images(
	IDS    => [ $self->id() ],
	REGION => $self->region(),
	QUERY  => 'Images[0].{Name:Name,Description:Description}',
	$self->_lopts()
	);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;

	if (!defined($reply)) {
	    return undef;
	}

	$self->{__PACKAGE__()}->{_cache}->{_name} =
	    $reply->{'Name'};
	$self->{__PACKAGE__()}->{_cache}->{_description} =
	    $reply->{'Description'};

	return 1;
    });
}

sub status
{
    my ($self, %opts) = @_;
    my ($cli, $opt, $value);

    confess(join(' ', keys(%opts))) if (%opts);

    $cli = Minion::Aws::Cli->describe_images(
	IDS    => [ $self->id() ],
	REGION => $self->region(),
	QUERY  => 'Images[0].State',
	$self->_lopts()
	);

    return $cli;
}

sub _copy_nowait
{
    my ($self, $name, $region, $copts, $nopts) = @_;
    my ($cli);

    $cli = Minion::Aws::Cli->copy_image(
	$self->id(),
	$self->region(),
	$name,
	REGION => $region,
	%$copts, $self->_lopts()
	);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;
	my ($id);

	if (!defined($reply)) {
	    return undef;
	}

	$id = $reply->{'ImageId'};

	if (!defined($id)) {
	    return undef;
	}

	return Minion::Aws::Image->new(
	    $id,
	    NAME   => $name,
	    REGION => $region,
	    %$nopts
	    );
    });
}

sub _copy_wait
{
    my ($self, $name, $region, $copts, $nopts, $wait, $sleep) = @_;
    my (%outputs, %fopts, $value, $log);

    if (defined($value = $self->_err())) {
	$fopts{STDERR} = $value;
    }

    if (defined($value = $self->_log())) {
	push(@{$fopts{IO}}, [ \$log, '>', $value ]);
    }

    return Minion::System::ProcessFuture->new(sub {
	my ($copy, $id, $start, $status, %lopts);

	if (defined($log)) {
	    $lopts{LOG} = $log;
	}

	$copy = Minion::Aws::Cli->copy_image(
	    $self->id(),
	    $self->region(),
	    $name,
	    REGION => $region,
	    %$copts, %lopts
	    )->get();

	if (!defined($copy)) {
	    return;
	}

	$id = $copy->{'ImageId'};

	$start = time();

	while (($wait < 0) || ((time() - $start) < $wait)) {
	    $status = Minion::Aws::Cli->describe_images(
		IDS    => [ $id ],
		QUERY  => 'Images[0].State',
		REGION => $region,
		%lopts
		)->get();

	    if (defined($status) && ($status ne 'pending')) {
		last
	    }

	    sleep($sleep);
	}

	if (defined($status) && ($status eq 'available')) {
	    printf("%s", $id);
	}
    }, MAPOUT => sub {
	my ($reply) = @_;

	if (!defined($reply) || ($reply eq '')) {
	    return undef;
	}

	return Minion::Aws::Image->new(
	    $reply,
	    NAME   => $name,
	    REGION => $region,
	    %$nopts
	    );
    }, %fopts);
}

sub copy
{
    my ($self, $name, %opts) = @_;
    my (%copts, %nopts, $region, $description, $opt, $value, $wait, $sleep);

    if (defined($value = $opts{DESCRIPTION})) {
	confess() if (ref($value) ne '');
	$copts{DESCRIPTION} = $value;
	$nopts{DESCRIPTION} = $value;
	delete($opts{DESCRIPTION});
    }

    if (defined($value = $opts{REGION})) {
	confess() if (ref($value) ne '');
	$region = $value;
	delete($opts{REGION});
    } else {
	$region = Minion::Aws::Cli->get_region()->get();
    }

    if (defined($value = $opts{SLEEP})) {
	confess() if ($wait !~ /^?\d+$/);
	$sleep = $value;
	delete($opts{SLEEP});
    } else {
	$sleep = 30;
    }

    if (defined($value = $opts{WAIT})) {
	confess() if ($value !~ /^-?\d+$/);
	$wait = $value;
	delete($opts{WAIT});
    } else {
	$wait = -1;
    }

    foreach $opt (qw(ERR LOG)) {
	if (defined($value = $opts{$opt})) {
	    $nopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    if ($wait != 0) {
	return $self->_copy_wait($name, $region,
				 \%copts, \%nopts,
				 $wait, $sleep);
    } else {
	return $self->_copy_nowait($name, $region,
				   \%copts, \%nopts);
    }
}


sub delete
{
    my ($self, %opts) = @_;
    my (%outputs, %fopts, $value, $log);

    if (defined($value = $self->_err())) {
	$fopts{STDERR} = $value;
    }

    if (defined($value = $self->_log())) {
	push(@{$fopts{IO}}, [ \$log, '>', $value ]);
    }

    return Minion::System::ProcessFuture->new(sub {
	my ($id, $region, $snapshots, $deregister, $snap, @deletes, $delete);
	my (%lopts);

	if (defined($log)) {
	    $lopts{LOG} = $log;
	}

	$id = $self->id();
	$region = $self->region();

	$snapshots = Minion::Aws::Cli->describe_images(
	    IDS    => [ $id ],
	    QUERY  => 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId',
	    REGION => $region,
	    %lopts
	    )->get();

	if (!defined($snapshots)) {
	    exit (1);
	}

	$deregister = Minion::Aws::Cli->deregister_image(
	    $id,
	    REGION => $region,
	    %lopts
	    )->get();

	if (!defined($deregister)) {
	    exit (1);
	}

	foreach $snap (@$snapshots) {
	    $delete = Minion::Aws::Cli->delete_snapshot(
		$snap,
		REGION => $region,
		%lopts
		);

	    push(@deletes, $delete);
	}

	Minion::System::Pgroup->new(\@deletes)->waitall();
    }, MAPOUT => sub { return 1; }, %fopts);
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

sub name
{
    my ($self, @err) = @_;
    my ($ret);

    confess() if (@err);

    $ret = $self->{__PACKAGE__()}->{_cache}->{_name};

    if (!defined($ret)) {
	$self->update()->get();
	$ret = $self->{__PACKAGE__()}->{_cache}->{_name};
    }

    return $ret;
}

sub description
{
    my ($self, @err) = @_;
    my ($ret);

    confess() if (@err);

    $ret = $self->{__PACKAGE__()}->{_cache}->{_description};

    if (!defined($ret)) {
	$self->update()->get();
	$ret = $self->{__PACKAGE__()}->{_cache}->{_description};
    }

    return $ret;
}


1;
__END__

