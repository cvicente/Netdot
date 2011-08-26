use strict;
use Test::More qw(no_plan);
use lib "lib";
use Netdot::Model::Ipblock;

my $sub1 = Ipblock->insert({
    address => "12.0.0.0",
    prefix  => '24',
    version => 4,
    status  => 'Subnet',
});

eval {
    Ipblock->insert({
        address => "12.0.0.0",
        prefix  => '25',
        version => 4,
        status  => 'Subnet',
    });
};
ok($@);

my $sub2 = Ipblock->search(address => '12.0.0.0/25')->first;
is($sub2, undef);

$sub1->delete;
