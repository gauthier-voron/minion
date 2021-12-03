package Minion::Aws::Cli;

use parent qw(Minion::System::ProcessFuture);
use strict;
use warnings;

use Carp qw(confess);
use File::Temp qw(tempfile);
use JSON;

use Minion::Io::Util qw(output_function);
use Minion::System::Process;
use Minion::System::ProcessFuture;


sub _init
{
    my ($self, $routine, %opts) = @_;
    my (%sopts, $value, $opt);

    confess() if (!defined($routine));
    confess() if (!grep { ref($routine) eq $_ } qw(CODE ARRAY));

    $sopts{MAPOUT} = sub { return decode_json(shift()); };

    foreach $opt (qw(STDIN STDERR MAPOUT)) {
	if (defined($value = $opts{$opt})) {
	    $sopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    return $self->SUPER::_init($routine, %sopts);
}


# =============================================================================


sub __aws_base_command
{
    return ('aws', '--output', 'json');
}

sub __encode_json
{
    my ($input) = @_;
    my ($fh, $path);

    ($fh, $path) = tempfile('minion.aws.XXXXXX', SUFFIX => '.json');
    printf($fh "%s", encode_json($input));
    close($fh);

    return $path;
}

sub __encode_time
{
    my ($sec, $min, $hour, $day, $month, $year) = @_;

    return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ",
		   $year, $month, $day, $hour, $min, $sec);
}

sub __encode_time_from_now
{
    my ($s) = @_;
    my ($sec, $min, $hour, $day, $month, $year) = gmtime(time() + $s);

    $year += 1900;
    $month += 1;

    return __encode_time($sec, $min, $hour, $day, $month, $year);
}

sub __format_cmd
{
    my ($cmd, @paths) = @_;
    my ($msg, $path, $fh, $line);

    $msg = join(' ', @$cmd) . "\n";

    foreach $path (@paths) {
	if (!open($fh, '<', $path)) {
	    $msg .= '  ' . $path . ": $!\n";
	} else {
	    $msg .= '  ' . $path . ":\n";

	    while (defined($line = <$fh>)) {
		chomp($line);
		$msg .= '    ' . $line . "\n";
	    }

	    close($fh);
	}
    }

    return $msg;
}


sub get_role
{
    my ($class, $name, @err) = @_;
    my (@command);

    confess() if (@err);
    confess() if (!defined($name));
    confess() if (ref($name) ne '');

    @command = (
	__aws_base_command, 'iam', 'get-role',
	'--role-name', $name
	);

    return $class->new(\@command);
}


my $__CACHE_IAM_FLEET_ROLE;

sub __get_iam_fleet_role
{
    my ($cmd, $res);

    if (!defined($__CACHE_IAM_FLEET_ROLE)) {
	$cmd = __PACKAGE__()->get_role('aws-ec2-spot-fleet-tagging-role');
	$res = $cmd->get();

	if (!defined($res)) {
	    return undef;
	}

	$__CACHE_IAM_FLEET_ROLE = $res->{'Role'}->{'Arn'};
    }

    return $__CACHE_IAM_FLEET_ROLE;
}


sub get_region
{
    my ($class, @err) = @_;
    my (@command);

    confess() if (@err);

    @command = (
	__aws_base_command, 'configure', 'get', 'region'
	);

    return $class->new(\@command, MAPOUT => sub {
	my ($out) = @_;
	chomp($out);
	return $out;
    });
}


sub cancel_spot_fleet_requests
{
    my ($class, $ids, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($ids));
    confess() if (ref($ids) ne 'ARRAY');
    confess() if (grep { ! m/^sfr(?:-[0-9a-f]+)+$/ } @$ids);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'cancel-spot-fleet-requests',
	'--spot-fleet-request-ids', encode_json($ids)
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    if (defined($value = $opts{TERMINATE})) {
	if ($value) {
	    push(@command, '--terminate-instances');
	} else {
	    push(@command, '--no-terminate-instances');
	}
	delete($opts{TERMINATE});
    } else {
	push(@command, '--terminate-instances');
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub copy_image
{
    my ($class, $id, $region, $name, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($id));
    confess() if ($id !~ /^ami-[0-9a-f]+$/);
    confess() if (!defined($region));
    confess() if (ref($region) ne '');
    confess() if (!defined($name));
    confess() if (ref($name) ne '');

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'copy-image',
	'--name', $name,
	'--source-image-id', $id,
	'--source-region', $region
	);

    if (defined($value = $opts{DESCRIPTION})) {
	confess() if (ref($value) ne '');
	push(@command, '--description', $value);
	delete($opts{DESCRIPTION});
    }

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub create_image
{
    my ($class, $id, $name, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($id));
    confess() if ($id !~ /^i-[0-9a-f]+$/);
    confess() if (!defined($name));
    confess() if (ref($name) ne '');

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'create-image',
	'--instance-id', $id,
	'--name', $name
	);

    if (defined($value = $opts{DESCRIPTION})) {
	confess() if (ref($value) ne '');
	push(@command, '--description', $value);
	delete($opts{DESCRIPTION});
    }

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub delete_snapshot
{
    my ($class, $id, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($id));
    confess() if ($id !~ /^snap-[0-9a-f]+$/);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'delete-snapshot',
	'--snapshot-id', $id
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts, MAPOUT => sub { return 1; });
}

sub deregister_image
{
    my ($class, $id, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($id));
    confess() if ($id !~ /^ami-[0-9a-f]+$/);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'deregister-image',
	'--image-id', $id
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts, MAPOUT => sub { return 1; });
}

sub describe_images
{
    my ($class, %opts) = @_;
    my (%copts, @command, $dict, $value, $key, $logger);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'describe-images'
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($dict = $opts{FILTERS})) {
	confess() if (ref($dict) ne 'HASH');
	while (($key, $value) = each(%$dict)) {
	    push(@command, '--filters', 'Name=' . $key . ',Values=' .
		 encode_json($value));
	}
	delete($opts{FILTERS});
    }

    if (defined($value = $opts{IDS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ! m/^ami-[0-9a-f]+$/ } @$value);
	push(@command, '--image-ids', encode_json($value));
	delete($opts{IDS});
    }

    if (defined($value = $opts{INCLUDE_DEPRECATED})) {
	if ($value) {
	    push(@command, '--include-deprecated');
	} else {
	    push(@command, '--no-include-deprecated');
	}
	delete($opts{INCLUDE_DEPRECATED});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{OWNERS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ref($_) ne '' } @$value);
	push(@command, '--owners', encode_json($value));
	delete($opts{OWNERS});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_instances
{
    my ($class, %opts) = @_;
    my (%copts, @command, $dict, $value, $key, $logger);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'describe-instances'
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($dict = $opts{FILTERS})) {
	confess() if (ref($dict) ne 'HASH');
	while (($key, $value) = each(%$dict)) {
	    push(@command, '--filters', 'Name=' . $key . ',Values=' .
		 encode_json($value));
	}
	delete($opts{FILTERS});
    }

    if (defined($value = $opts{IDS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ! m/^i-[0-9a-f]+$/ } @$value);
	push(@command, '--instance-ids', encode_json($value));
	delete($opts{IDS});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_regions
{
    my ($class, %opts) = @_;
    my (%copts, @command, $value, $logger);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'describe-regions'
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_security_groups
{
    my ($class, %opts) = @_;
    my (%copts, @command, $value, $logger);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'describe-security-groups'
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{IDS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ! m/^sg-[0-9a-f]+$/ } @$value);
	push(@command, '--group-ids', encode_json($value));
	delete($opts{IDS});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{NAMES})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ref($_) ne '' } @$value);
	push(@command, '--group-names', encode_json($value));
	delete($opts{NAMES});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_spot_fleet_instances
{
    my ($class, $id, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($id));
    confess() if ($id !~ /^sfr(?:-[0-9a-f]+)+$/);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'describe-spot-fleet-instances',
	'--spot-fleet-request-id', $id
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_spot_fleet_requests
{
    my ($class, %opts) = @_;
    my (%copts, @command, $value, $logger);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'describe-spot-fleet-requests'
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{IDS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ! m/^sfr(?:-[0-9a-f]+)+$/ } @$value);
	push(@command, '--spot-fleet-request-ids', encode_json($value));
	delete($opts{IDS});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_spot_fleet_request_history
{
    my ($class, $id, $since, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($id));
    confess() if ($id !~ /^sfr(?:-[0-9a-f]+)+$/);
    confess() if (!defined($since));
    confess() if ($since !~ /^-?\d+$/);
    return if ($since <= 0);

    $logger = sub {};

    @command = (
	__aws_base_command(), 'ec2', 'describe-spot-fleet-request-history',
	'--spot-fleet-request-id', $id,
	'--start-time', __encode_time_from_now(-$since)
	);
    
    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    if (defined($value = $opts{TYPE})) {
	confess() if (!grep { $value eq $_ } qw(
           instanceChange fleetRequestChange error information
        ));
	push(@command, '--event-type', $value);
	delete($opts{TYPE});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_volumes
{
    my ($class, %opts) = @_;
    my (%copts, @command, $logger, $value, $dict, $key);

    $logger = sub {};

    @command = (__aws_base_command(), 'ec2', 'describe-volumes');

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($dict = $opts{FILTERS})) {
	confess() if (ref($dict) ne 'HASH');
	while (($key, $value) = each(%$dict)) {
	    push(@command, '--filters', 'Name=' . $key . ',Values=' .
		 encode_json($value));
	}
	delete($opts{FILTERS});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub describe_volumes_modifications
{
    my ($class, %opts) = @_;
    my (%copts, @command, $logger, $value, $dict, $key);

    $logger = sub {};

    @command = (__aws_base_command(), 'ec2', 'describe-volumes-modifications');

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($dict = $opts{FILTERS})) {
	confess() if (ref($dict) ne 'HASH');
	while (($key, $value) = each(%$dict)) {
	    push(@command, '--filters', 'Name=' . $key . ',Values=' .
		 encode_json($value));
	}
	delete($opts{FILTERS});
    }

    if (defined($value = $opts{IDS})) {
	confess() if (ref($value) ne 'ARRAY');
	confess() if (grep { ! m/^vol-[0-9a-f]+$/ } @$value);
	push(@command, '--volume-ids', encode_json($value));
	delete($opts{IDS});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{QUERY})) {
	confess() if (ref($value) ne '');
	push(@command, '--query', $value);
	delete($opts{QUERY});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub modify_volume
{
    my ($class, $id, %opts) = @_;
    my (%copts, @command, $logger, $value);

    confess() if (!defined($id));
    confess() if ($id !~ /^vol-[0-9a-f]+$/);

    $logger = sub {};

    @command = (__aws_base_command(), 'ec2', 'modify-volume', '--volume-id',
		$id);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	push(@command, '--region', $value);
	delete($opts{REGION});
    }

    if (defined($value = $opts{SIZE})) {
	confess() if (ref($value) ne '');
	confess() if ($value !~ /^\d+$/);
	push(@command, '--size', $value);
	delete($opts{SIZE});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub request_spot_fleet
{
    my ($class, $image, $type, %opts) = @_;
    my (%copts, @command, %config, %spec, $path, $value, $region, $logger);

    confess() if (!defined($image));
    confess() if ($image !~ /^ami-[0-9a-f]+$/);
    confess() if (!defined($type));
    confess() if ($type !~ /^[a-z]\d(?:[a-z]+)?\.[a-z0-9]+$/);

    $logger = sub {};

    $config{'TargetCapacity'} = 1;
    $config{'TerminateInstancesWithExpiration'} = \1;

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{KEY})) {
	confess() if (ref($value) ne '');
	$spec{'KeyName'} = $value;
	delete($opts{KEY});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{PRICE})) {
	confess() if ($value !~ /^-?\d+(?:\.\d+)?$/);
	return if ($value <= 0);
	$config{'SpotPrice'} = "$value";
	delete($opts{PRICE});
    }

    if (defined($value = $opts{REGION})) {
	confess() if ($value !~ /^\S+$/);
	$region = $value;
	delete($opts{REGION});
    }

    if (defined($value = $opts{SECGROUP})) {
	confess() if ($value !~ /^sg-[0-9a-f]+$/);
	$spec{'SecurityGroups'} = [ { 'GroupId' => $value } ];
	delete($opts{SECGROUP});
    }

    if (defined($value = $opts{SIZE})) {
	confess() if ($value !~ /^-?\d+$/);
	return if ($value <= 0);
	$config{'TargetCapacity'} = int($value);
	delete($opts{SIZE});
    }

    if (defined($value = $opts{TIME})) {
	confess() if ($value !~ /^-?\d+$/);
	return if ($value <= 0);
	$config{'ValidUntil'} = __encode_time_from_now($value);
	delete($opts{TIME});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $spec{'ImageId'} = $image;
    $spec{'InstanceType'} = $type;

    $config{'LaunchSpecifications'} = [ \%spec ];
    $config{'IamFleetRole'} = __get_iam_fleet_role();

    $path = __encode_json(\%config);

    @command = (
	__aws_base_command(), 'ec2', 'request-spot-fleet',
	'--spot-fleet-request-config', 'file://' . $path
	);

    if (defined($region)) {
	push(@command, '--region', $region);
    }

    $logger->(__format_cmd(\@command, $path));

    return $class->new(sub {
	my $ecode = Minion::System::Process->new(\@command)->wait();

	unlink($path);

	exit ($ecode >> 8);
    }, %copts);
}


1;
__END__
