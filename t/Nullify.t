use strict;
use warnings;
use Test::More qw(no_plan);
use lib "lib";
use Data::Dumper;

BEGIN { use_ok('Netdot::Model'); }

my $s = Ipblock->search(address=>'1.1.1.0')->first;
$s->delete if $s;

my $subnet = Ipblock->insert({address => '1.1.1.0',
                              prefix => 24,
                              status => 'Subnet'});
my $s_id = $subnet->id;

my $vlan = Vlan->insert({name => 'test vlan',
			 vid => 1});
ok(defined $vlan, "vlan insert");

$subnet->update({vlan => $vlan});
is($subnet->vlan, $vlan, 'set vlan to subnet');

$vlan->delete;
undef $subnet;
$subnet = Ipblock->retrieve($s_id);
is($subnet->vlan, undef, 'nullify');
$subnet->delete;
