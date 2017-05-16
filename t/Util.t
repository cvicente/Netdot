use strict;
use Test::More qw(no_plan);
use lib "lib";
use Netdot;

BEGIN { use_ok('Netdot::Util::DNS'); }

my $dns = Netdot::Util::DNS->new();
isa_ok($dns, 'Netdot::Util::DNS', 'constructor');

# Note, these are the addresses for the K root server. 
# No guarantee that they won't change
my $ipv4 = '193.0.14.129';
my $ipv6 = '2001:7fd::1';
my $name = 'k.root-servers.net';

is($dns->resolve_ip($ipv4), $name, 'resolve_ip_v4');
is($dns->resolve_ip($ipv6), $name, 'resolve_ip_v6');
my @addresses = $dns->resolve_name($name);
is($addresses[0], $ipv4, 'resolve_name_ipv4');
is($addresses[1], $ipv6, 'resolve_name_ipv6');

is(($dns->resolve_name($name, {v4_only=>1}))[0], $ipv4, 'resolve_name_ipv4_only');
is(($dns->resolve_name($name, {v6_only=>1}))[0], $ipv6, 'resolve_name_ipv6_only');

