use strict;
use Test::More;
use lib "lib";

BEGIN { 
    use_ok('Netdot::Model::DhcpScope'); 
}

my $ip = '192.168.0.10';
my $net = '192.168.0.0/24';
my $global_name = 'dhcp_global_test';
my $mac = 'deaddeadbeef';

sub cleanup{
    foreach my $s ( ($ip, $net) ){
	my $i = Ipblock->search(address=>$s)->first;
	$i->delete if $i;
    }
    map { $_->delete } DhcpScope->retrieve_all;
}

&cleanup();

my $global = DhcpScope->insert({name=>$global_name, type=>'global'});
isa_ok($global, 'Netdot::Model::DhcpScope', 'can insert a global scope');

my $subnet = Ipblock->insert({address=>$net, status=>'Subnet'});
$subnet->enable_dhcp(container=>$global);
my $subnet_scope = $subnet->dhcp_scopes->first;

is($subnet_scope->name, '192.168.0.0 netmask 255.255.255.0', 'Subnet scope created');
my %attr_names = map { $_->name->name => 1 } $subnet_scope->attributes;
ok(exists $attr_names{'option broadcast-address'}, 'subnet gets broadcast');
ok(exists $attr_names{'option subnet-mask'}, 'subnet gets mask');

my $host_scope = DhcpScope->insert({
    container=>$global, type=>'host', 
    ipblock=>$ip, physaddr=>$mac});

isa_ok($host_scope, 'Netdot::Model::DhcpScope', 'can insert a host scope');
is($host_scope->name, $ip, 'host scope gets expected name');
is(DhcpScope->search(name=>$ip)->first, $host_scope, 'can search a scope by name' );
is(DhcpScope->search(type=>'host')->first, $host_scope, 'can search a scope by type' );
is($host_scope->container, $global, 'scope container matches global');

my $test_class_name = 'test_class_abc';
my $class_scope = DhcpScope->insert(
    {
	name => $test_class_name,
	type => 'class',
	container => $global,
	attributes => {
	    'next-server' => '192.0.2.1',
	    'filename' => '123abc'
	}
    }
    );

is($class_scope->name, $test_class_name, 'creates class with expected name');

my ($fh, $config);
open($fh, '>', \$config);
my $data = DhcpScope->_get_all_data();
DhcpScope->_print($fh, $global->id, $data);
close($fh);

my $dhcp_mac = PhysAddr->dhcpd_address($mac);
like($config, qr/host $ip/, 'config contains host');
like($config, qr/fixed-address $ip;/, 'config contains fixed-address statement');
like($config, qr/hardware ethernet $dhcp_mac;/, 'config contains mac');
like($config, qr/class "test_class_abc"/, 'config contains class');
like($config, qr/next-server 192.0.2.1;/, 'config contains attribute');
like($config, qr/filename "123abc";/, 'filename attribute has double quotes');

&cleanup();

done_testing();
