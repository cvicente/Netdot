use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Zone'); }

my $obj = Zone->insert({name=>'domain.name'});
isa_ok($obj, 'Netdot::Model::Zone', 'insert');

is(Zone->search(name=>'sub.domain.name')->first, $obj, 'search scalar' );
is_deeply([Zone->search(name=>'sub.domain.name')], [$obj], 'search array' );
is(Zone->search(name=>'fake')->first, undef, 'search empty scalar' );
is_deeply([Zone->search(name=>'fake')], [], 'search empty array' );

is(Zone->search_like(name=>'domain.name')->first, $obj, 'search_like scalar' );
is_deeply([Zone->search_like(name=>'domain.name')], [$obj], 'search_like array' );
is(Zone->search_like(name=>'fake')->first, undef, 'search_like empty scalar' );
is_deeply([Zone->search_like(name=>'fake')], [], 'search_like empty array' );

my $serial = $obj->serial;
$obj->update_serial();
is($obj->serial, $serial+1, 'update_serial');

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');
