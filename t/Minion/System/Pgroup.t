use strict;
use warnings;

use Test::More tests => 30;

BEGIN
{
    use_ok('Minion::System::Pgroup');
    use_ok('Minion::System::Process');
};


{
    my $p0 = Minion::System::Process->new(sub {});
    my $p1 = Minion::System::Process->new(sub { sleep(10); });
    my $pgroup = Minion::System::Pgroup->new([ $p0, $p1 ]);

    is($pgroup->size(), 2, 'group size');
    ok((scalar($pgroup->members()) == 2) &&
       (grep { $_->pid() == $p0->pid() } $pgroup->members()) &&
       (grep { $_->pid() == $p1->pid() } $pgroup->members()),
       'group list members');

    is($pgroup->wait(), $p0, 'wait one process in the group');
    is($pgroup->size(), 1, 'group size after one wait');

    $p1->kill();

    is($pgroup->wait(), $p1, 'wait the other process in the group');
    is($pgroup->size(), 0, 'group size after second wait');

    is($pgroup->wait(), undef, 'no more process in the group');


    my $p2 = Minion::System::Process->new(sub {});

    ok($pgroup->add($p2), 'can add process dynamically');
    is($pgroup->size(), 1, 'size changes after add');

    ok(! $pgroup->add($p2), 'cannot add same process twice');
    is($pgroup->size(), 1, 'size does not changes after failed add');

    ok($pgroup->remove($p2), 'can remove process dynamically');
    is($pgroup->size(), 0, 'size changes after remove');
    

    my $p3 = Minion::System::Process->new(sub {});

    $pgroup->add($p2);
    $pgroup->add($p3);

    ok(! $pgroup->remove($p0), 'cannot remove process not in the group');
    ok(! $pgroup->add($p0), 'cannot add finished process');

    my @lst = $pgroup->waitall();
    is(scalar(@lst), 2, 'can wait all members in the group');

    ok(! $pgroup->wait(), 'cannot wait on empty group');


    my $p4 = Minion::System::Process->new(sub {});

    $pgroup->add($p4);
    $p4->wait();

    is($pgroup->size(), 1, 'group size is trivial');
    ok(! $pgroup->wait(), 'cannot wait already finished process');
    is($pgroup->size(), 0, 'finished members removed after wait');

    my $p5 = Minion::System::Process->new(sub {});
    my $p6 = Minion::System::Process->new(sub { sleep(10); });
    my (@full);

    $pgroup = Minion::System::Pgroup->new([ [ $p5, 'p5' ], [ $p6, 'p6' ] ]);

    is($pgroup->size(), 2, 'group size for full members');
    ok((scalar($pgroup->fullmembers()) == 2) &&
       (grep { $_->[0]->pid() == $p5->pid() } $pgroup->fullmembers()) &&
       (grep { $_->[0]->pid() == $p6->pid() } $pgroup->fullmembers()),
       'group list full members');

    @full = $pgroup->wait();
    is($full[0], $p5 , 'wait one process in the group as full member');
    is($full[1], 'p5' , 'wait one process values in the group');

    $p6->kill();

    @full = $pgroup->wait();
    is($full[0], $p6, 'wait the other process in the group as full member');
    is($full[1], 'p6', 'wait the other process values in the group');
    is($pgroup->size(), 0, 'group of full members size after second wait');

    @full = $pgroup->wait();
    is(scalar(@full), 0, 'no more process in the group of full members');
}
