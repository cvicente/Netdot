use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Interface'); }

my @test_devs = ('testdev1');
my @test_blocks = ('192.0.2.1', '192.0.2.0/26', '192.0.2.0/24');

sub cleanup{
    foreach my $name (@test_devs){
	$_->delete() for Device->search(name=>$name);
    }
    foreach my $addr (@test_blocks){
	$_->delete() for Ipblock->search(address=>$addr);
    }
}
&cleanup();

my $dev = Device->insert({name=>'localhost'});
my $iface = @{$dev->add_interfaces(1)}[0];

my %update_ip_args = (
    address => $test_blocks[0],
    version => '4',
    subnet => $test_blocks[1],
    add_subnets => 1,
    );
my $ip = $iface->update_ip(%update_ip_args);
ok( !defined Ipblock->search(address=>$test_blocks[1])->first, 
    'ignore_orphan_subnet' );

my $root = Ipblock->insert({address=>$test_blocks[2]});
my $ip = $iface->update_ip(%update_ip_args);
ok( defined Ipblock->search(address=>$test_blocks[1])->first, 
    'add_non_orphan_subnet' );

&cleanup();
