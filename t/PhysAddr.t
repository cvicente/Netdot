use strict;
use Test::More;
use Test::Exception;
use lib "lib";

BEGIN { use_ok('Netdot::Model::PhysAddr'); }

my @tst_addrs = qw(DEADDEADBEEF DEEDBEEDFEED 00211CAABBCC);
# Clean up sub called at beginning and end
sub test_cleanup {
    foreach my $ta ( @tst_addrs ){
	my $a = PhysAddr->search(address=>$ta)->first;
	$a->delete if $a;
    }
}
&test_cleanup();

my $obj = PhysAddr->insert({address=>'DE:AD:DE:AD:BE:EF'});
isa_ok($obj, 'Netdot::Model::PhysAddr', 'insert inserts');

is($obj->address, $tst_addrs[0], 'address returns address');

my $searched = PhysAddr->search(address=>$tst_addrs[0])->first;
is($obj->id, $searched->id, 'search searches full address');

my $sl = PhysAddr->search_like(address=>'DEADBEEF')->first;
is($obj->id, $sl->id, 'search_like searches partial address');

my $hr = PhysAddr->retrieve_all_hashref();
ok(ref($hr) eq 'HASH', 'retrieve_all_hashref returns hashref');

my $tstamp = '2016-08-08 00:00:00';
PhysAddr->fast_update({$tst_addrs[1] => 1}, 
		      $tstamp);

my $one = PhysAddr->search(address=>$tst_addrs[1])->first;
is($one->address, $tst_addrs[1], 'fast_update inserts address');
is($one->last_seen, $tstamp, 'fast_update inserts timestamp');

throws_ok { PhysAddr->validate("") } qr/undefined/, 
    'validate throws undefined';

throws_ok { PhysAddr->validate('qwerty') } qr/illegal chars or size/, 
    'validate throws illegal';

throws_ok { PhysAddr->validate('AAAAAAAAAAAA') } qr/bogus/, 
    'validate throws bogus';

throws_ok { PhysAddr->validate('00005E00FFFF') } qr/VRRP/, 
    'validate throws VRRP';

throws_ok { PhysAddr->validate('00000C07AC00') } qr/HSRP/, 
    'validate throws HSRP';

throws_ok { PhysAddr->validate('01005E401001') } qr/multicast/, 
    'validate throws multicast';

ok(ref(PhysAddr->from_interfaces) eq 'HASH', 
   'from_interfaces returns hashref');

ok(ref(PhysAddr->from_devices) eq 'HASH', 
   'from_devices returns hashref');

ok(ref(PhysAddr->infrastructure) eq 'HASH', 
   'infrastructure returns hashref');

ok(ref(PhysAddr->map_all_to_ints) eq 'HASH', 
   'map_all_to_ints returns hashref');

my($h, $c) = PhysAddr->vendor_count();
ok(ref($h) eq 'HASH', 'vendor_count returns hashref first');
is($c, 2, 'vendor_count returns total second');

is($obj->oui, 'DEADDE', 'oui returns first two octets');
my $cisco_mac = PhysAddr->insert({address=>'00211CAABBCC'});
ok($cisco_mac->vendor =~ qr/Cisco Systems/, 'vendor returns correct name');

throws_ok { PhysAddr->format_address('blah'=>undef) } qr/Missing argument/, 
    'format_address throws missing argument';

is(PhysAddr->format_address(address=>$tst_addrs[0]), $tst_addrs[0],
    'format_address no args returns default format');

is(PhysAddr->format_address(
       address         => $tst_addrs[0],
       format_caseness => 'lower'), 
   lc($tst_addrs[0]),
    'format_address no args returns lowercase');

is(PhysAddr->format_address(
            address                   => $tst_addrs[0],
            format_caseness           => 'lower',
            format_delimiter_string   => '.',
            format_delimiter_interval => 4,
        ),
        'dead.dead.beef', 'format_address cisco format');

is(PhysAddr->dhcpd_address($tst_addrs[0]), 'DE:AD:DE:AD:BE:EF', 
   'dhcpd_address returns colon-separated format');

&test_cleanup();

done_testing();
