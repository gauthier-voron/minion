package Minion::System::Pgroup;

use strict;
use warnings;

use Carp qw(confess);
use Time::HiRes qw(usleep);

use Minion::System::Waitable;


sub _check_member_type
{
    my ($self, $member) = @_;

    return Minion::System::Waitable->comply($member);
}

sub _check_member_state
{
    my ($self, $member) = @_;

    return !defined($member->exitstatus());
}


sub new
{
    my ($class, @args) = @_;
    my $self = bless({}, $class);

    return $self->_init(@args);
}

sub _init
{
    my ($self, $members, @err) = @_;
    my (%ms, $member);

    confess() if (@err);
    confess() if (!defined($members));
    confess() if (ref($members) ne 'ARRAY');
    confess() if (grep { !$self->_check_member_type($_); } @$members);

    foreach $member (@$members) {
	if (!$self->_check_member_state($member)) {
	    return undef;
	}

	$ms{$member} = $member;
    }

    $self->{__PACKAGE__()}->{_members} = \%ms;

    return $self;
}


sub size
{
    my ($self, @err) = @_;

    confess() if (@err);

    return scalar(%{$self->{__PACKAGE__()}->{_members}});
}

sub members
{
    my ($self, @err) = @_;

    confess() if (@err);

    return values(%{$self->{__PACKAGE__()}->{_members}});
}


sub add
{
    my ($self, $member, @err) = @_;
    my ($members, $pid, %cache);

    confess() if (@err);
    confess() if (!defined($member));
    confess() if (!$self->_check_member_type($member));

    if (!$self->_check_member_state($member)) {
	return 0;
    }

    $members = $self->{__PACKAGE__()}->{_members};

    if (exists($members->{$member})) {
	return 0;
    }

    $members->{$member} = $member;

    return 1;
}

sub remove
{
    my ($self, $member, @err) = @_;
    my ($members, $pid, %cache);

    confess() if (@err);
    confess() if (!defined($member));
    confess() if (!$self->_check_member_type($member));

    $members = $self->{__PACKAGE__()}->{_members};

    if (!exists($members->{$member})) {
	return 0;
    }

    delete($members->{$member});

    return 1;
}


sub wait
{
    my ($self, @err) = @_;
    my (@list, $member, $ret, %nlist);

    confess() if (@err);

    $ret = undef;

    while (!defined($ret)) {
	@list = $self->members();
	%nlist = ();

	foreach $member (@list) {
	    if (defined($member->exitstatus())) {
		next;
	    }

	    if (!defined($ret)) {
		$ret = $member->trywait();

		if (defined($ret)) {
		    $ret = $member;
		    next;
		}
	    }

	    $nlist{$member} = $member;
	}

	if (scalar(%nlist) == 0) {
	    last;
	}

	usleep(10_000);
    }

    $self->{__PACKAGE__()}->{_members} = \%nlist;

    return $ret;
}

sub waitall
{
    my ($self, @err) = @_;
    my (@ret, $member);

    while ($self->size() > 0) {
	$member = $self->wait();

	if (defined($member)) {
	    push(@ret, $member);
	}
    }

    return @ret;
}


1;
__END__
