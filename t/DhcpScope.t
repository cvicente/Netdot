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
    my $d = DhcpScope->search(name=>$global_name)->first;
    $d->delete if $d;
}

&cleanup();

my $global = DhcpScope->insert({name=>$global_name, type=>'global'});
isa_ok($global, 'Netdot::Model::DhcpScope', 'can insert a global scope');

my $subnet = Ipblock->insert({address=>$net, status=>'Subnet'});
$subnet->enable_dhcp(container=>$global);

my $scope = DhcpScope->insert(
    {container=>$global, name=>$ip, type=>'host', 
     ipblock=>$ip, physaddr=>$mac});

isa_ok($scope, 'Netdot::Model::DhcpScope', 'can insert a host scope');

is(DhcpScope->search(name=>$ip)->first, $scope, 'can search a scope by name' );
is($scope->container, $global, 'scope container matches global');

&cleanup();

done_testing();
