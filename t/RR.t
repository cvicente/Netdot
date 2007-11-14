use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::RR'); }

my $obj = RR->insert({name=>'record', zone=>'test.zone'});
isa_ok($obj, 'Netdot::Model::RR', 'insert');

is(RR->search(name=>'record.test.zone')->first, $obj, 'search' );

is($obj->get_label, 'record.test.zone', 'get_label');

my $zone = $obj->zone;
$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');
$zone->delete;
