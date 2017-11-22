use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Interface'); }

my $test_dev = 'testdev1';
my @test_blocks = ('192.0.2.1', '192.0.2.0/26', '192.0.2.0/24');

sub cleanup{
    foreach my $addr (@test_blocks){
	$_->delete() for Ipblock->search(address=>$addr);
    }
    foreach my $dev (Device->search(name=>$test_dev)){
	$dev->delete() if $dev;
    }
}
&cleanup();

my $ints = Device->insert({name=>$test_dev})->add_interfaces(1);
my $iface = $ints->[0];
ok( $iface->isa('Netdot::Model::Interface') );
my %update_ip_args = (
    address => $test_blocks[0],
    subnet => $test_blocks[1],
    version => '4',
    add_subnets => 1,
    );
my $ip = $iface->update_ip(%update_ip_args);
ok( !defined Ipblock->search(address=>$test_blocks[1])->first, 
    'ignore_orphan_subnet' );

my $root = Ipblock->insert({address=>$test_blocks[2],
			   status=>'Container'});
$ip = $iface->update_ip(%update_ip_args);
ok( defined Ipblock->search(address=>$test_blocks[1])->first, 
    'add_non_orphan_subnet' );

# This avoids a common situation with Juniper routers
# that have interfaces with IPs in 10/8
$update_ip_args{subnet} = $test_blocks[2];
$iface->update_ip(%update_ip_args);
is($root->status->name, 'Container', 
   'update_ip cannot turn container into subnet');

&cleanup();
