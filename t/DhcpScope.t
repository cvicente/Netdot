use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { 
    use_ok('Netdot::Model::DhcpScope'); 
}

my $ip = '192.168.0.10';

my $global = DhcpScope->insert({name=>'dhcp_server', type=>'global'});
my $scope = DhcpScope->insert({container=>$global, name=>$ip, type=>'host', ipblock=>$ip, physaddr=>'deaddeadbeef'});
isa_ok($scope, 'Netdot::Model::DhcpScope', 'insert_scope');
is(DhcpScope->search(name=>$ip)->first, $scope, 'search' );
is($scope->container, $global, 'container');

$global->delete;

