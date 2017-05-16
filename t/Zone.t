use strict;
use Test::More qw(no_plan);
use Test::Exception;
use lib "lib";

my $DOMAIN = 'test.tld';
my $SUB_DOMAIN = 'sub.'. $DOMAIN;

BEGIN { use_ok('Netdot::Model::Zone'); }

my $obj = Zone->insert({name=>$DOMAIN});
isa_ok($obj, 'Netdot::Model::Zone', 'insert');

lives_and { is(Zone->_dot_arpa_to_ip('1.in-addr.arpa'), '1.0.0.0/8', 'IPv4 /8 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('2.1.in-addr.arpa'), '1.2.0.0/16', 'IPv4 /16 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('3.2.1.in-addr.arpa'), '1.2.3.0/24', 'IPv4 /24 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('4.3.2.1.in-addr.arpa'), '1.2.3.4/32', 'IPv4 /32 .arpa zone to address') };

lives_and { is(Zone->_dot_arpa_to_ip('1.ip6.arpa'), '1000::/4', 'IPv6 /4 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('2.1.ip6.arpa'), '1200::/8', 'IPv6 /8 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('3.2.1.ip6.arpa'), '1230::/12', 'IPv6 /12 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('4.3.2.1.ip6.arpa'), '1234::/16', 'IPv6 /16 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('5.4.3.2.1.ip6.arpa'), '1234:5000::/20', 'IPv6 /20 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('6.5.4.3.2.1.ip6.arpa'), '1234:5600::/24', 'IPv6 /24 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('7.6.5.4.3.2.1.ip6.arpa'), '1234:5670::/28', 'IPv6 /28 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('8.7.6.5.4.3.2.1.ip6.arpa'), '1234:5678::/32', 'IPv6 /32 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('9.8.7.6.5.4.3.2.1.ip6.arpa'), '1234:5678:9000::/36', 'IPv6 /36 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('a.9.8.7.6.5.4.3.2.1.ip6.arpa'), '1234:5678:9a00::/40', 'IPv6 /40 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('b.a.9.8.7.6.5.4.3.2.1.ip6.arpa'), '1234:5678:9ab0::/44', 'IPv6 /44 .arpa zone to address') };
lives_and { is(Zone->_dot_arpa_to_ip('c.b.a.9.8.7.6.5.4.3.2.1.ip6.arpa'), '1234:5678:9abc::/48', 'IPv6 /48 .arpa zone to address') };

is(Zone->search(name=>$SUB_DOMAIN)->first, $obj, 'search scalar');
is_deeply([Zone->search(name=>$SUB_DOMAIN)], [$obj], 'search array' );

is(Zone->search(name=>'fake')->first, undef, 'search empty scalar' );
is_deeply([Zone->search(name=>'fake')], [], 'search empty array' );

my $SUBSTR = substr($DOMAIN, 0, 3);
is(Zone->search_like(name=>$SUBSTR)->first, $obj, 'search_like scalar');
is_deeply([Zone->search_like(name=>$SUBSTR)], [$obj], 'search_like array' );
is(Zone->search_like(name=>'fake')->first, undef, 'search_like empty scalar' );
is_deeply([Zone->search_like(name=>'fake')], [], 'search_like empty array' );

my $serial = $obj->serial;
$obj->update_serial();
is($obj->serial, $serial+1, 'update_serial');

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');
