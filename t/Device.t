use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Device'); }

my @macs = ('DEADDEADBEEF', 'DEADDEADDEAD', 'DEADBEEFDEAD');
my @ips = ('10.0.0.88', '10.0.0.99', '10.0.0.101');

sub cleanup{
    my @devs = Device->search_like(name=>'testdev%');
    foreach my $dev (@devs){
	my $peers = $dev->get_bgp_peers();
	foreach my $p (@$peers){
	    $p->entity->delete if $p->isa('Netdot::Model::Entity');
	}
	$dev->delete();
    }
    map { $_->delete() } map { PhysAddr->search(address=>$_) } @macs;
    map { $_->delete() } map { Ipblock->search(address=>$_) } @ips;
}
&cleanup();

my $dd = Netdot->config->get('DEFAULT_DNSDOMAIN');
my $ddn = (Zone->search(name=>$dd)->first)->name;

my $obj = Device->insert({name=>'testdev1'});
isa_ok($obj, 'Netdot::Model::Device', 'insert');

is($obj->short_name, 'testdev1', 'get short_name');
is($obj->fqdn, "testdev1.$ddn", 'fqdn');
is(Device->search(name=>"testdev1.$ddn")->first, $obj, 'search' );

my $obj2 = Device->insert({name=>'testdev2'});
ok(scalar(Device->search_like(name=>"test")) == 2, 'search_like' );

# This should give us $obj's name
my $rr = Device->assign_name(host=>'testdev1');
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

my $peers = $obj->get_bgp_peers();
is(($peers->[0])->id, $p->id, 'get_bgp_peers');

my $newints = $obj->add_interfaces(3);
my @ints = $obj->interfaces();
is($ints[0], $newints->[0], 'add_interfaces');

my $newip = $obj->add_ip('10.0.0.1');
is($newip->address, '10.0.0.1', 'add_ip');

# Test connected devices query
# First, create some fwt entries
my $tstamp = Netdot::Model->timestamp();
my $fwt = FWTable->insert({device=>$obj, tstamp=>$tstamp});
foreach my $i (0..2) {
    FWTableEntry->insert({
	fwtable => $fwt,
	interface => $ints[$i],
	physaddr => PhysAddr->insert({address=>$macs[$i]}),
			 });
}
my @fwtes = $fwt->entries();
is($fwtes[0]->interface, $ints[0]);
is($fwtes[0]->physaddr->address, $macs[0]);

# Then create some ARP entries
my $arpcache = ArpCache->insert({device=>$obj2, tstamp=>$tstamp});
my $arpint = Interface->insert({device=>$obj2, number=>'1', name=>'eth1'});
foreach my $i (0..2){
    ArpCacheEntry->insert({
	arpcache  => $arpcache,
	interface => $arpint,
	ipaddr    => Ipblock->insert({address=>$ips[$i]}),
	physaddr  => PhysAddr->search(address=>$macs[$i])->first,
			  });
}

# Give IPs DNS names
for my $ipaddr (@ips){
    my $name = $ipaddr;
    $name =~ s/\./-/g;
    RR->insert({type=>'A', name=>$name, ipblock=>$ipaddr});
}
my $connected = $obj->get_connected_devices();
is(ref($connected), 'HASH', 'get_connected_devices returns hashref');
my @macobjs = map { PhysAddr->search(address=>$_)->first } @macs;
my @ipobjs = map { Ipblock->search(address=>$_)->first } @ips;
is($connected->{$ints[0]->id}->{$macobjs[0]->id}->{mac}, $macs[0], 
   'get_connected_devices has mac address');
is($connected->{$ints[0]->id}->{$macobjs[0]->id}->{ip}->{$ipobjs[0]->id}->{fqdn}, 
   '10-0-0-88.defaultdomain', 'get_connected_devices has FQDN');
&cleanup();
