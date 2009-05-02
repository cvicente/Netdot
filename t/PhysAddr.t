use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::PhysAddr'); }

my $obj = PhysAddr->insert({address=>'DE:AD:DE:AD:BE:EF'});
isa_ok($obj, 'Netdot::Model::PhysAddr', 'insert');

is($obj->address, 'DEADDEADBEEF', 'address');
is($obj->colon_address, 'DE:AD:DE:AD:BE:EF', 'address');
