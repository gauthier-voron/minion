package Minion::Fleet;

use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);

use Minion::System::Pgroup;


sub comply
{
    my ($class, $obj, @err) = @_;

    confess() if (@err);
    confess() if (!defined($obj));

    if (blessed($obj) &&
	$obj->can('execute') &&
	$obj->can('send') &&
	$obj->can('members')) {

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
    my ($self, @err) = @_;

    confess() if (@err);

    return $self;
}


# sub members
# {
#     my ($self, @err) = @_;

#     confess('not implemented');
# }

sub execute
{
    my ($self, $cmd, %opts) = @_;
    my (%mopts, $opt, $value, @members, $member, $ret, $proc);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$cmd);

    foreach $opt (qw(STDIN STDOUT STDERR)) {
	if (defined($value = $opts{$opt})) {
	    $mopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    @members = $self->members();
    $ret = Minion::System::Pgroup->new([]);

    foreach $member (@members) {
	$proc = $member->execute($cmd, %mopts);
	$ret->add($proc);
    }

    return $ret;
}

sub send
{
    my ($self, $sources, %opts) = @_;
    my (%mopts, $opt, $value, @members, $member, $ret, $proc);

    confess() if (!defined($sources));
    confess() if (ref($sources) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$sources);

    foreach $opt (qw(TARGET)) {
	if (defined($value = $opts{$opt})) {
	    $mopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    @members = $self->members();
    $ret = Minion::System::Pgroup->new([]);

    foreach $member (@members) {
	$proc = $member->send($sources, %mopts);
	$ret->add($proc);
    }

    return $ret;
}


1;
__END__
