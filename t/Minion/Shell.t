use lib qw(. t/);
use strict;
use warnings;

use Test::More;

use Minion::TestWorker;

BEGIN
{
    use_ok('Minion::Shell');
};


my ($ntest, %tests, $name, $routine, $worker0, $worker1);

$ntest = 1;
%tests = Minion::TestWorker::tests();


# Shell on current working directory ------------------------------------------

$worker0 = Minion::Shell->new();
$worker1 = Minion::Shell->new();
$ntest += scalar(%tests);

while (($name, $routine) = each(%tests)) {
    subtest "current dir " . $name => sub { $routine->($worker0, $worker1) };
}


# Shell on explicit working directory -----------------------------------------

$worker0 = Minion::Shell->new(HOME => '/tmp');
$worker1 = Minion::Shell->new(HOME => '/tmp');
$ntest += scalar(%tests);

while (($name, $routine) = each(%tests)) {
    subtest "home dir " . $name => sub { $routine->($worker0, $worker1) };
}


done_testing($ntest);


__END__
