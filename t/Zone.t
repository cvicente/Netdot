use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Zone'); }

my $obj = Zone->insert({name=>'domain.name'});
isa_ok($obj, 'Netdot::Model::Zone', 'insert');

is(Zone->search(name=>'sub.domain.name')->first, $obj, 'search' );

my $serial = $obj->serial;
$obj->update();
is($obj->serial, $serial+1, 'update');

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');
