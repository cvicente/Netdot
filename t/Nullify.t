use strict;
use warnings;
use Test::More qw(no_plan);
use lib "lib";
use Data::Dumper;

BEGIN { use_ok('Netdot::Model'); }

# Ipblock
my $subnet = Ipblock->insert({address => '1.1.1.0',
                              prefix => 24,
                              status => 'Subnet'});
my $subnet_id = $subnet->id;
ok(defined $subnet, 'subnet insert');

$subnet->set('description', 'test1');
diag("update without params returns ", $subnet->update);
undef $subnet;
$subnet = Ipblock->retrieve($subnet_id);
is($subnet->description, 'test1', 'update without params');

diag("update with params returns ", $subnet->update({description => 'test2'}));
undef $subnet;
$subnet = Ipblock->retrieve($subnet_id);
is($subnet->description, 'test2', 'update with params');

eval {
    my $vlan = Vlan->insert({name => 'test vlan',
                             vid => 1});
    ok(defined $vlan, "vlan insert");

    $subnet->update({vlan => $vlan});
    is($subnet->vlan, $vlan, 'set vlan to subnet');

    $vlan->delete;
    undef $subnet;
    $subnet = Ipblock->retrieve($subnet_id);
    is($subnet->vlan, 0, 'nullify');
};
fail($@) if $@;

$subnet->delete;
