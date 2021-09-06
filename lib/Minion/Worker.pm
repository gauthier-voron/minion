package Minion::Worker;

use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);


sub comply
{
    my ($class, $obj, @err) = @_;

    confess() if (@err);
    confess() if (!defined($obj));

    if (blessed($obj) &&
	$obj->can('execute') &&
	$obj->can('send') &&
	$obj->can('recv') &&
	$obj->can('list') &&
	$obj->can('get') &&
	$obj->can('set') &&
	$obj->can('del')) {

	return 1;

    }

    return 0;
}

sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, %opts) = @_;
    my ($aliases, $properties, $key);

    if (defined($aliases = $opts{ALIASES})) {
	confess() if (ref($aliases) ne 'HASH');
	confess() if (grep { ref($_) ne '' } keys(%$aliases));
	confess() if (grep { ref($_) ne 'CODE' } values(%$aliases));
	delete($opts{ALIASES});
    } else {
	$aliases = {};
    }

    if (defined($properties = $opts{PROPERTIES})) {
	confess() if (ref($properties) ne 'HASH');
	confess() if (grep { ref($_) ne '' } keys(%$properties));
	confess() if (grep { ref($_) ne '' } values(%$properties));
	delete($opts{PROPERTIES});
    } else {
	$properties = {};
    }

    confess(join(' ', keys(%opts))) if (%opts);

    foreach $key (keys(%$properties)) {
	confess() if (grep { $_ eq $key } keys(%$aliases));
    }

    $self->{__PACKAGE__()}->{_aliases} = { %$aliases };
    $self->{__PACKAGE__()}->{_properties} = { %$properties };

    return $self;
}

# sub execute
# {
#     confess('not implemeted');
# }

# sub send
# {
#     confess('not implemeted');
# }

# sub recv
# {
#     confess('not implemeted');
# }

sub list
{
    my ($self, @err) = @_;

    confess() if (@err);

    return (
	keys(%{$self->{__PACKAGE__()}->{_aliases}}),
	keys(%{$self->{__PACKAGE__()}->{_properties}})
	);
}

sub get
{
    my ($self, $key, @err) = @_;
    my ($ret);

    confess() if (@err);
    confess() if (!defined($key));
    confess() if (ref($key) ne '');

    $ret = $self->{__PACKAGE__()}->{_aliases}->{$key};

    if (defined($ret)) {
	return $ret->();
    }

    return $self->{__PACKAGE__()}->{_properties}->{$key};
}

sub set
{
    my ($self, $key, $value, @err) = @_;
    my ($alias);

    confess() if (@err);
    confess() if (!defined($key));
    confess() if (ref($key) ne '');
    confess() if (!defined($value));
    confess() if (ref($value) ne '');

    if (($key =~ /\n/ms) || ($key !~ /^[-_:0-9a-zA-Z]+$/ms)) {
	return 0;
    }

    $alias = $self->{__PACKAGE__()}->{_aliases}->{$key};

    if (defined($alias)) {
	return 0;
    }

    $self->{__PACKAGE__()}->{_properties}->{$key} = $value;

    return 1;
}

sub del
{
    my ($self, $key, @err) = @_;
    my ($alias, $value);

    confess() if (@err);
    confess() if (!defined($key));
    confess() if (ref($key) ne '');

    $alias = $self->{__PACKAGE__()}->{_aliases}->{$key};

    if (defined($alias)) {
	return 0;
    }

    delete($self->{__PACKAGE__()}->{_properties}->{$key});

    return 1;
}


1;
__END__
