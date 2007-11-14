use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Vlan');
	use_ok('Netdot::Model::VlanGroup'); 
}

my $group  = VlanGroup->insert({name        =>'Data', 
				description =>'Data Vlans',
				start       =>'100',
				end         =>'300',
			    });
isa_ok($group, 'Netdot::Model::VlanGroup', 'insert');
is(VlanGroup->search(name=>'Data')->first, $group, 'search' );


my $vlan = Vlan->insert({vid=>'100', description=>'Vlan 100'});
isa_ok($vlan, 'Netdot::Model::Vlan', 'insert');
is(Vlan->search(vid=>'100')->first, $vlan, 'search' );

is($vlan->vlangroup, $group, 'auto group assignment');

$vlan->delete;
isa_ok($vlan, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

$group->delete;
isa_ok($group, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

