use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Device'); }

my $dd = Netdot->config->get('DEFAULT_DNSDOMAIN');
my $ddn = (Zone->search(name=>$dd)->first)->name;

my $obj = Device->insert({name=>'localhost'});
isa_ok($obj, 'Netdot::Model::Device', 'insert');

is($obj->short_name, 'localhost', 'get short_name');
is($obj->fqdn, "localhost.$ddn", 'fqdn');
is(Device->search(name=>"localhost.$ddn")->first, $obj, 'search' );

my $obj2 = Device->insert({name=>'localhost2'});
ok(scalar(Device->search_like(name=>"local")) == 2, 'search_like' );

# This should give us $obj's name
my $rr = Device->assign_name(host=>'localhost');
is($rr->id, $obj->name, 'assign_name');

my $testcl = ContactList->insert({name=>'testcl'});
my @cls = $obj->add_contact_lists($testcl);
is($cls[0]->contactlist->name, $testcl->name, 'add_contact_lists');
$testcl->delete;

$obj->update({layers=>'00000010'});
is($obj->has_layer(2), 1, 'has_layer');

my $p = $obj->update_bgp_peering( 
    peer=>{
	address   => '10.0.0.2',
	bgppeerid => '10.0.0.1',
	asname    => 'testAS',
	asnumber  => '1000',
	orgname   => 'testOrg'},
    old_peerings=>{} );
is($p->bgppeerid, '10.0.0.1', 'update_bgp_peering');

my $newints = $obj->add_interfaces(1);
my @ints = $obj->interfaces();
is($ints[0], $newints->[0], 'add_interfaces');

my $newip = $obj->add_ip('10.0.0.1');
is($newip->address, '10.0.0.1', 'add_ip');

my $peers = $obj->get_bgp_peers();
is(($peers->[0])->id, $p->id, 'get_bgp_peers');

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');
$obj2->delete;
