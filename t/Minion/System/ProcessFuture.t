use strict;
use warnings;

use Test::More tests => 22;
use Time::HiRes qw(usleep);

BEGIN
{
    use_ok('Minion::System::Future');
    use_ok('Minion::System::ProcessFuture');
};


{
    my $forked = Minion::System::ProcessFuture->new(sub { printf("ok\n"); });
    my $execed = Minion::System::ProcessFuture->new(['echo', 'ok']);

    isnt($forked->pid(), 0, 'forked non-zero pid');
    isnt($execed->pid(), 0, 'execed non-zero pid');

    is($forked->exitstatus(), undef, 'forked undef exit status before wait');
    is($execed->exitstatus(), undef, 'execed undef exit status before wait');

    is($forked->out(), undef, 'forked undef out before wait');
    is($execed->out(), undef, 'execed undef out before wait');

    is($forked->get(), "ok\n", 'forked correct future value');
    is($execed->get(), "ok\n", 'execed correct future value');

    is($forked->exitstatus(), 0, 'forked get triggers wait');
    is($execed->exitstatus(), 0, 'execed get triggers wait');

    is($forked->out(), "ok\n", 'forked correct out value');
    is($execed->out(), "ok\n", 'execed correct out value');

    ok(Minion::System::Future->comply($forked), 'forked is future');
    ok(Minion::System::Future->comply($execed), 'execed is future');
}

{
    my $longwait = Minion::System::ProcessFuture->new(sub {
	usleep(100_000);
	printf("ok\n");
    });

    my $value = $longwait->get();

    is($value, "ok\n", 'future get automatically waits');
    is($longwait->out(), "ok\n", 'future out automatically updated');
}

{
    my $mapped = Minion::System::ProcessFuture->new(sub {
	printf("7 4 9 1 12\n");
    }, MAPOUT => sub { chomp(@_); return [ split(/\s+/, shift()) ]; });

    my $value = $mapped->get();

    is_deeply($value, [ 7, 4, 9, 1, 12 ], 'mapped value is correct');
    is($mapped->out(), "7 4 9 1 12\n", 'out of mapped future is correct');
}

{
    my $counter = 0;
    my $mapped = Minion::System::ProcessFuture->new(sub {}, MAPOUT => sub {
	$counter += 1;
    });

    $mapped->get();

    is($counter, 1, 'mapping routine has side effects');

    $mapped->get();

    is($counter, 2, 'mapping routine executed for each get call');
}
