use strict;
use Test::More qw(no_plan);
use Test::Exception;
use lib "lib";

BEGIN { use_ok('Netdot::Model::ArpCacheEntry'); }

my @macs = ('DEADDEADBEEF', 'BEEFDEADBEEF');
my @ips = ('10.0.0.10', '10.0.0.20');
my $testdev = 'testdev1';

sub cleanup {
    map { $_->delete } map { PhysAddr->search(address=>$_) } @macs;
    map { $_->delete } map { Ipblock->search(address=>$_) } @ips;
    map { $_->delete } Device->search(name=>$testdev);
}

&cleanup();
my $dev = Device->insert({name=>$testdev});
my $ints = $dev->add_interfaces(2);
my $tstamp = Netdot::Model->timestamp();
my $arp_cache = ArpCache->insert({device=>$dev, tstamp=>$tstamp});
is($dev->arp_caches->first, $arp_cache->id, 'Device has ARP table');
my @ips_dec = map { Ipblock->insert({address=>$_})->address_numeric } @ips;
my @arp_data;
foreach my $i (0..1){
    $arp_data[$i] = {
	arpcache => $arp_cache->id,
	interface => $ints->[$i]->id,
	physaddr => $macs[$i],
	ipaddr => $ips_dec[$i],
	version => 4
    };
}

throws_ok { ArpCacheEntry->fast_insert(list=>\@arp_data) } qr/cannot be null/, 
    'fast_insert throws exception';

my @physaddrs = map { PhysAddr->insert({address=>$_}) } @macs;
ArpCacheEntry->fast_insert(list=>\@arp_data);
my @entries = $arp_cache->entries();
foreach my $i (0..1){
    is($entries[$i]->interface, $ints->[$i], 'entry has interface');
    is($entries[$i]->physaddr, $physaddrs[$i], 'entry has physaddr');
    is($entries[$i]->ipaddr->address, $ips[$i], 'entry has ip');
}
&cleanup();
