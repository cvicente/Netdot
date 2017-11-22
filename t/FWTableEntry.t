use strict;
use Test::More qw(no_plan);
use Test::Exception;
use lib "lib";

BEGIN { use_ok('Netdot::Model::FWTableEntry'); }

my @macs = ('DEADDEADBEEF', 'BEEFDEADBEEF');
my $testdev = 'testdev1';

sub cleanup {
    map { $_->delete } map { PhysAddr->search(address=>$_) } @macs;
    map { $_->delete } Device->search(name=>$testdev);
}
&cleanup();
my $dev = Device->insert({name=>$testdev});
my $ints = $dev->add_interfaces(2);
my $tstamp = Netdot::Model->timestamp();
my $fwt = FWTable->insert({device=>$dev, tstamp=>$tstamp});
is($dev->forwarding_tables->first, $fwt->id, 'Device has fwtable');
my @fwt_data;
foreach my $i (0..1){
    $fwt_data[$i] = {
	fwtable => $fwt->id,
	interface => $ints->[$i]->id,
	physaddr => $macs[$i],
    };
}

throws_ok { FWTableEntry->fast_insert(list=>\@fwt_data) } qr/cannot be null/, 
    'fast_insert throws exception';

my @physaddrs = map { PhysAddr->insert({address=>$_}) } @macs;
FWTableEntry->fast_insert(list=>\@fwt_data);
my @entries = $fwt->entries();
foreach my $i (0..1){
    is($entries[$i]->interface, $ints->[$i], 'entry has interface');
    is($entries[$i]->physaddr, $physaddrs[$i], 'entry has physaddr');
}
&cleanup();
