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
my $rr = Device->assign_name('localhost');
is($rr->id, $obj->name, 'assign_name');

my $testcl = ContactList->insert({name=>'testcl'});
my @cls = $obj->add_contact_lists($testcl);
is($cls[0]->contactlist->name, $testcl->name, 'add_contact_lists');
$testcl->delete;

$obj->update({layers=>'00000010'});
is($obj->has_layer(2), 1, 'has_layer');

my $sn = '00112233';
$obj2->update({serialnumber=>$sn});
eval{
    $obj->update_serial_number($sn);
};
my $e;
ok($e = $@, 'update_serial_number');
like($e, qr/belongs to existing device/, 'update_serial_number');

my $p = $obj->update_bgp_peering( peer=>{bgppeerid =>'10.0.0.1',
					 asname    => 'testAS',
					 asnumber  => '1000',
					 orgname   => 'testOrg'},
				  oldpeerings=>{} );
is($p->bgppeerid, '10.0.0.1', 'update_bgp_peering');

my $mac = 'DEADDEADBEEF';
$obj2->update_base_mac($mac);
is($obj2->physaddr->address, $mac, 'update_base_mac');

eval{
    $obj->update_base_mac($mac);
};
ok($e = $@, 'update_base_mac');
like($e, qr/belongs to existing device/, 'update_base_mac');

my $newints = $obj->add_interfaces(1);
my $newip = $obj->add_ip('10.0.0.1');
is($newip->address, '10.0.0.1', 'add_ip');

my $newsub = Ipblock->insert({address=>'10.0.0.0', prefix=>24, status=>'Subnet'});
my $subs = $obj->get_subnets();
ok(exists $subs->{$newsub->id}, 'get_subnets');

my $ints = $obj->get_interfaces();
is($ints->[0], $newints->[0], 'get_interfaces');

my $peers = $obj->get_bgp_peers();
is(($peers->[0])->id, $p->id, 'get_bgp_peers');

$newsub->delete;
$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');
$obj2->delete;
