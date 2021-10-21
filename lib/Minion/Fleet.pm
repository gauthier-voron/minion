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
    my (@members, $member, $opt, $value, $i);
    my ($ret, $proc, @moptss, $mopts);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$cmd);

    @members = $self->members();

    foreach $member (@members) {
	push(@moptss, {});
    }

    foreach $opt (qw(STDIN STDOUT STDERR)) {
	if (defined($value = $opts{$opt . 'S'})) {
	    if (ref($value) eq 'ARRAY') {
		confess() if (scalar(@$value) != scalar(@members));
		for ($i = 0; $i < scalar(@$value); $i++) {
		    $moptss[$i]->{$opt} = $value->[$i];
		}
	    } else {
		for ($i = 0; $i < scalar(@members); $i++) {
		    $moptss[$i]->{$opt} = $value;
		}
	    }
	    delete($opts{$opt . 'S'});
	}
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $ret = Minion::System::Pgroup->new([]);

    foreach $member (@members) {
	$mopts = shift(@moptss);
	$proc = $member->execute($cmd, %$mopts);
	$ret->add($proc);
    }

    return $ret;
}

sub send
{
    my ($self, $sources, %opts) = @_;
    my (@members, $member, $value, $i);
    my (@moptss, $mopts, $proc, $ret);

    confess() if (!defined($sources));
    confess() if (ref($sources) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$sources);

    @members = $self->members();

    foreach $member (@members) {
	push(@moptss, {});
    }

    if (defined($value = $opts{TARGETS})) {
	if (ref($value) eq 'ARRAY') {
	    confess() if (scalar(@$value) != scalar(@members));
	    for ($i = 0; $i < scalar(@$value); $i++) {
		$moptss[$i]->{TARGET} = $value->[$i];
	    }
	} else {
	    for ($i = 0; $i < scalar(@members); $i++) {
		$moptss[$i]->{TARGET} = $value;
	    }
	}
	delete($opts{TARGETS});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $ret = Minion::System::Pgroup->new([]);

    foreach $member (@members) {
	$mopts = shift(@moptss);
	$proc = $member->send($sources, %$mopts);
	$ret->add($proc);
    }

    return $ret;
}

sub recv
{
    my ($self, $sources, %opts) = @_;
    my (@members, $member, $value, $i);
    my (@moptss, $mopts, $ret, $proc);

    confess() if (!defined($sources));
    confess() if (ref($sources) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$sources);

    @members = $self->members();

    foreach $member (@members) {
	push(@moptss, {});
    }

    if (defined($value = $opts{TARGETS})) {
	if (ref($value) eq 'ARRAY') {
	    confess() if (scalar(@$value) != scalar(@members));
	    for ($i = 0; $i < scalar(@$value); $i++) {
		$moptss[$i]->{TARGET} = $value->[$i];
	    }
	} else {
	    for ($i = 0; $i < scalar(@members); $i++) {
		$moptss[$i]->{TARGET} = $value;
	    }
	}
	delete($opts{TARGETS});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $ret = Minion::System::Pgroup->new([]);

    foreach $member (@members) {
	$mopts = shift(@moptss);
	$proc = $member->recv($sources, %$mopts);
	$ret->add($proc);
    }

    return $ret;
}


1;
__END__
