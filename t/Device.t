use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Device'); }

sub cleanup{
    my @devs = Device->search_like(name=>'localhost%');
    foreach my $dev (@devs){
	my $peers = $dev->get_bgp_peers();
	foreach my $p (@$peers){
	    $p->entity->delete if $p->isa('Netdot::Model::Entity');
	}
	$dev->delete();
    }
}
&cleanup();

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

# BGP Peerings
my $p = $obj->update_bgp_peering(
    peer=>{
	address   => '10.0.0.2',
	bgppeerid => '10.0.0.1',
	asname    => 'testAS',
	asnumber  => '1000',
	orgname   => 'testOrg'},
    old_peerings=>{} );
is($p->bgppeerid, '10.0.0.1', 'update_bgp_peering');
is($p->entity->name, 'testAS (1000)', 'peer_entity_name');
is($p->entity->asnumber, '1000', 'peer_entity_asn');

my $p2 = $obj->update_bgp_peering(
    peer=>{
	address   => '192.0.2.1',
	bgppeerid => '192.0.2.100',
	asname    => 'another_name',
	asnumber  => '1000'},
    old_peerings=>{} );
is($p->entity->id, $p2->entity->id, 'find_entity_by_asn');

# Change the entity's AS
$p->entity->update(asn=>'2000');
my $p3 = $obj->update_bgp_peering(
    peer=>{
	address   => '192.0.2.2',
	bgppeerid => '192.0.2.200',
	asname    => 'testAS',
	asnumber  => '1000'},
    old_peerings=>{} );
is($p->entity->id, $p3->entity->id, 'find_entity_by_name');
is($p->entity->asnumber, '1000', 'entity ASN is restored');

my $newints = $obj->add_interfaces(1);
my @ints = $obj->interfaces();
is($ints[0], $newints->[0], 'add_interfaces');

my $newip = $obj->add_ip('10.0.0.1');
is($newip->address, '10.0.0.1', 'add_ip');

my $peers = $obj->get_bgp_peers();
is(($peers->[0])->id, $p->id, 'get_bgp_peers');

&cleanup();
