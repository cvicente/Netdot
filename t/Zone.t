use strict;
use Test::More qw(no_plan);
use lib "lib";

my $DOMAIN = 'test.tld';
my $SUB_DOMAIN = 'sub.'. $DOMAIN;

BEGIN { use_ok('Netdot::Model::Zone'); }

my $obj = Zone->insert({name=>$DOMAIN});
isa_ok($obj, 'Netdot::Model::Zone', 'insert');

is(Zone->search(name=>$SUB_DOMAIN)->first, $obj, 'search scalar');
is_deeply([Zone->search(name=>$SUB_DOMAIN)], [$obj], 'search array' );
is(Zone->search(name=>'fake')->first, undef, 'search empty scalar' );
is_deeply([Zone->search(name=>'fake')], [], 'search empty array' );

my $SUBSTR = substr($DOMAIN, 0, 3);
is(Zone->search_like(name=>$SUBSTR)->first, $obj, 'search_like scalar');
is_deeply([Zone->search_like(name=>$SUBSTR)], [$obj], 'search_like array' );
is(Zone->search_like(name=>'fake')->first, undef, 'search_like empty scalar' );
is_deeply([Zone->search_like(name=>'fake')], [], 'search_like empty array' );

my $serial = $obj->serial;
$obj->update_serial();
is($obj->serial, $serial+1, 'update_serial');

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');
