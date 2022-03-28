package Minion::System::Pgroup;

use strict;
use warnings;

use Carp qw(confess);
use Time::HiRes qw(usleep);

use Minion::System::Waitable;


sub _check_member_type
{
    my ($member) = @_;

    if (ref($member) eq 'ARRAY') {
	return ((scalar(@$member) >= 1) &&
		Minion::System::Waitable->comply($member->[0]));

    } else {
	return Minion::System::Waitable->comply($member);
    }
}

sub _check_member_state
{
    my ($member) = @_;

    if (ref($member) eq 'ARRAY') {
	return !defined($member->[0]->exitstatus());
    } else {
	return !defined($member->exitstatus());
    }
}

sub _wrap_member
{
    my ($member) = @_;

    if (ref($member) eq 'ARRAY') {
	return $member;
    } else {
	return [ $member ];
    }
}

sub _get_member_process
{
    my ($member) = @_;

    return $member->[0];
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
    my (%ms, $member, $wrapped);

    confess() if (@err);
    confess() if (!defined($members));
    confess() if (ref($members) ne 'ARRAY');
    confess() if (grep { !_check_member_type($_); } @$members);

    foreach $member (@$members) {
	if (!_check_member_state($member)) {
	    return undef;
	}

	$wrapped = _wrap_member($member);

	$ms{_get_member_process($wrapped)} = $wrapped;
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

sub fullmembers
{
    my ($self, @err) = @_;

    confess() if (@err);

    return values(%{$self->{__PACKAGE__()}->{_members}});
}

sub members
{
    my ($self, @err) = @_;

    confess() if (@err);

    return map { _get_member_process($_) }
           values(%{$self->{__PACKAGE__()}->{_members}});
}


sub add
{
    my ($self, $member, @err) = @_;
    my ($members, $pid, %cache);

    confess() if (@err);
    confess() if (!defined($member));
    confess() if (!_check_member_type($member));

    if (!_check_member_state($member)) {
	return 0;
    }

    $members = $self->{__PACKAGE__()}->{_members};

    if (exists($members->{$member})) {
	return 0;
    }

    $member = _wrap_member($member);

    $members->{_get_member_process($member)} = $member;

    return 1;
}

sub remove
{
    my ($self, $member, @err) = @_;
    my ($members, $pid, %cache);

    confess() if (@err);
    confess() if (!defined($member));
    confess() if (!_check_member_type($member));

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
	@list = $self->fullmembers();
	%nlist = ();

	foreach $member (@list) {
	    if (defined(_get_member_process($member)->exitstatus())) {
		next;
	    }

	    if (!defined($ret)) {
		$ret = _get_member_process($member)->trywait();

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

    if (wantarray()) {
	if (defined($ret)) {
	    return @$ret;
	} else {
	    return ();
	}
    } else {
	if (defined($ret)) {
	    return _get_member_process($ret);
	} else {
	    return undef;
	}
    }
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
