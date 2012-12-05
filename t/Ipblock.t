use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Ipblock'); }

my $container = Ipblock->insert({
    address => "192.0.2.0",
    prefix  => '24',
    version => 4,
    status  => 'Container',
});
is($container->status->name, 'Container', 'insert container');

my $subnet = Ipblock->insert({
    address => "192.0.2.0",
    prefix  => '25',
    version => 4,
    status  => 'Subnet',
});
is($subnet->status->name, 'Subnet', 'insert subnet');

my $address = Ipblock->insert({
    address => "192.0.2.10",
    prefix  => '32',
    version => 4,					 
    status  => 'Static',
});

is($address->status->name, 'Static', 'insert address');

is($address->is_address, 1, 'is_address');

is($address->parent, $subnet, 'address/subnet hierarchy');
is($subnet->parent, $container, 'subnet/container hierarchy');

is($address->address, '192.0.2.10', 'address method');
is($address->address_numeric, '3221225994', 'address_numeric method');
is($address->prefix, '32', 'prefix method');

is($subnet->num_addr(), '126', 'num_addr');
is($subnet->address_usage(), '6', 'address_usage');

is($container->subnet_usage(), '128', 'subnet_usage');

is($address->get_label(), '192.0.2.10', 'address label');
is($subnet->get_label(), '192.0.2.0/25', 'subnet label');

is(Ipblock->search(address=>'192.0.2.0', prefix=>'25')->first, $subnet, 'search' );

is(scalar(Ipblock->search_like(address=>'192.0')), 8, 'search_like' );

$subnet->update({description=>'test subnet'});
is(((Ipblock->keyword_search('test subnet'))[0])->id, $subnet->id, 'keyword_search');

my $descr = 'test blocks';
$container->update({description=>$descr, recursive=>1});
is($container->description, $descr, 'update_recursive');
my $subnet_id = $subnet->id;
undef($subnet);
$subnet = Ipblock->retrieve($subnet_id);
is($subnet->description, $descr, 'update_recursive');
my $address_id = $address->id;
undef($address);
$address = Ipblock->retrieve($address_id);
is($address->description, $descr, 'update_recursive');

my @ancestors = $address->get_ancestors();
is($ancestors[0], $subnet, 'get_ancestors');
is($ancestors[1], $container, 'get_ancestors');
 
my ($s,$p) = Ipblock->get_subnet_addr( address => $address->address,
				       prefix  => 25 );
is($s, $subnet->address, 'get_subnet_addr');

my $hosts = Ipblock->get_host_addrs( $subnet->address ."/". $subnet->prefix );
is($hosts->[0], '192.0.2.1', 'get_host_addrs');

ok(Ipblock->is_loopback('127.0.0.1'), 'is_loopback_v4');
ok(Ipblock->is_loopback('::1'), 'is_loopback_v6');
ok(Ipblock->is_multicast('239.255.0.1'), 'is_multicast_v4');
ok(Ipblock->is_multicast('FF02::1'), 'is_multicast_v6');
ok(Ipblock->is_link_local('fe80:abcd::1234'), 'is_link_local');

is(Ipblock->get_covering_block(address=>'192.0.2.5', prefix=>'32'), $subnet,
   'get_covering_block');


is(Ipblock->numhosts(24), 256, 'numhosts');

{
    use bigint;
    is(Ipblock->numhosts_v6(64), 18446744073709551616, 'numhosts_v6');
}
is(Ipblock->shorten(ipaddr=>'192.0.0.34',mask=>'16'), '0.34', 'shorten');

is(Ipblock->subnetmask(256), 24, 'subnetmask');

is(Ipblock->subnetmask_v6(4), 126, 'subnetmask_v6');

is($subnet->get_next_free, '192.0.2.6', 'get_next_free');
is($subnet->get_next_free(strategy=>'last'), '192.0.2.126', 'get_next_free_last');

is(($subnet->get_dot_arpa_names)[0], '0-25.2.0.192.in-addr.arpa', 'get_dot_arpa_names_v4_25');

my $subnet2 = Ipblock->insert({
    address => "192.0.2.160",
    prefix  => '27',
    version => 4,
    status  => 'Subnet',
});
is(($subnet2->get_dot_arpa_names)[0], '160-27.2.0.192.in-addr.arpa', 'get_dot_arpa_names_v4_27');

# my $subnet3 = Ipblock->insert({
#     address => "169.254.100.0",
#     prefix  => '23',
#     version => 4,
#     status  => 'Subnet',
# });
# my @arpa_names = ('100.254.169.in-addr.arpa', '101.254.169.in-addr.arpa');
# my @a = $subnet3->get_dot_arpa_names();
# is($a[0], $arpa_names[0], 'get_dot_arpa_names_v4_23');
# is($a[1], $arpa_names[1], 'get_dot_arpa_names_v4_23');

my $blk = Ipblock->insert({
    address => "8.0.0.0",
    prefix  => '7',
    version => 4,
    status  => 'Container',
});
my @arpa_names = ('8.in-addr.arpa', '9.in-addr.arpa');
my @a = $blk->get_dot_arpa_names();
is($a[0], $arpa_names[0], 'get_dot_arpa_names_v4_7');
is($a[1], $arpa_names[1], 'get_dot_arpa_names_v4_7');
$blk->delete();

my $v6container = Ipblock->insert({
    address => "2001:0db8::",
    prefix  => '32',
    version => 6,
    status  => 'Container',
});

is(($v6container->get_dot_arpa_names)[0], '8.b.d.0.1.0.0.2.ip6.arpa', 'get_dot_arpa_name_v6_32');

my $v6subnet = Ipblock->insert({
    address => "2001:0db8::",
    prefix  => '62',
    version => 6,
    status  => 'Subnet',
});

is($v6subnet->parent, $v6container, 'v6_parent');

is(($v6subnet->get_dot_arpa_names)[0], '0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa', 
   'get_dot_arpa_name_v6_62');
is(($v6subnet->get_dot_arpa_names)[1], '1.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa', 
   'get_dot_arpa_name_v6_62');
is(($v6subnet->get_dot_arpa_names)[2], '2.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa', 
   'get_dot_arpa_name_v6_62');
is(($v6subnet->get_dot_arpa_names)[3], '3.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa', 
'get_dot_arpa_name_v6_62');

my $v6container3 = Ipblock->insert({
    address => "2001:0db8::",
    prefix  => '48',
    version => 6,
    status  => 'Container',
});

is($v6container3->parent, $v6container,  'v6_parent2');
# Refresh object to avoid looking at old data
my $tmpid = $v6subnet->id;
$v6subnet = undef;
$v6subnet = Ipblock->retrieve($tmpid);
is($v6subnet->parent, $v6container3, 'v6_parent3');

is($v6subnet->get_next_free, '2001:db8::6', 'get_next_free_v6');
is($v6subnet->get_next_free(strategy=>'last'), '2001:db8:0:3:ffff:ffff:ffff:fffe', 'get_next_free_last_v6');

is(Ipblock->matches_v4($address->address), 1, 'matches_v4_1');
is(Ipblock->matches_v4($v6subnet->address), 0, 'matches_v4_2');


is(Ipblock->matches_v6($v6subnet->address), 1, 'matches_v6_1');
is(Ipblock->matches_v6($address->address), 0, 'matches_v6_2');

is(Ipblock->matches_ip($v6subnet->address), 1, 'matches_ip_1');
is(Ipblock->matches_ip($address->address), 1, 'matches_ip_2');

my $ar1 = Ipblock->matches_cidr($address->cidr);
my $ar2 = ($address->address, $address->prefix);
is_deeply(\$ar1, \$ar2, 'matches_cidr_1');

# Delete all records
$container->delete(recursive=>1);
$v6container->delete(recursive=>1);
isa_ok($container, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

