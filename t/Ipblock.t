use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Ipblock'); }

my $container = Ipblock->insert({
    address => "192.168.0.0",
    prefix  => '16',
    version => 4,
    status  => 'Container',
});
is($container->status->name, 'Container', 'insert container');


my $subnet = Ipblock->insert({
    address => "192.168.60.0",
    prefix  => '23',
    version => 4,
    status  => 'Subnet',
});
is($subnet->status->name, 'Subnet', 'insert subnet');

my $address = Ipblock->insert({
    address => "192.168.60.27",
    prefix  => '32',
    version => 4,					 
    status  => 'Static',
});

is($address->status->name, 'Static', 'insert address');

is($address->is_address, 1, 'is_address');

is($address->parent, $subnet, 'address/subnet hierarchy');
is($subnet->parent, $container, 'subnet/container hierarchy');

is($address->address, '192.168.60.27', 'address method');
is($address->address_numeric, '3232250907', 'address_numeric method');
is($address->prefix, '32', 'prefix method');

is($subnet->num_addr(), '510', 'num_addr');
is($subnet->address_usage(), '1', 'num_addr');

is($container->subnet_usage(), '512', 'num_addr');

is($address->get_label(), '192.168.60.27', 'address label');
is($subnet->get_label(), '192.168.60.0/23', 'subnet label');

is(Ipblock->search(address=>'192.168.60.0', prefix=>'23')->first, $subnet, 'search' );

is(scalar(Ipblock->search_like(address=>'192.168')), 3, 'search_like' );

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
				       prefix  => 23 );
is($s, $subnet->address, 'get_subnet_addr');

my $hosts = Ipblock->get_host_addrs( $subnet->address ."/". $subnet->prefix );
is($hosts->[0], '192.168.60.1', 'get_host_addrs');

ok(Ipblock->is_loopback('127.0.0.1'), 'is_loopback_v4');
ok(Ipblock->is_loopback('::1'), 'is_loopback_v6');
ok(Ipblock->is_multicast('239.255.0.1'), 'is_multicast_v4');
ok(Ipblock->is_multicast('FF02::1'), 'is_multicast_v6');

is(Ipblock->get_covering_block(address=>'192.168.60.5', prefix=>'32'), $subnet,
   'get_covering_block');

is(Ipblock->get_roots(), $container, 'get_roots');

is(Ipblock->numhosts(24), 256, 'numhosts');

{
    use bigint;
    is(Ipblock->numhosts_v6(64), 18446744073709551616, 'numhosts_v6');
}
is(Ipblock->shorten(ipaddr=>'192.0.0.34',mask=>'16'), '0.34', 'shorten');

is(Ipblock->subnetmask(256), 24, 'subnetmask');

is(Ipblock->subnetmask_v6(4), 126, 'subnetmask_v6');

is($subnet->get_next_free, '192.168.60.1', 'get_next_free');
is($subnet->get_next_free(strategy=>'last'), '192.168.61.254', 'get_next_free');

my $all = Ipblock->retrieve_all_hashref();
is($all->{$container->address_numeric}, $container->id, 'retrieve_all_hashref');
is($all->{$subnet->address_numeric}, $subnet->id, 'retrieve_all_hashref');
is($all->{$address->address_numeric}, $address->id, 'retrieve_all_hashref');

# TODO: fast_update


# Delete all records
$container->delete(recursive=>1);
isa_ok($container, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

