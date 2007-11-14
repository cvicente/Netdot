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

# This should fail because the ranges overlap
eval {
    VlanGroup->insert({name        =>'Data2', 
		       description =>'Data Vlans',
		       start       =>'300',
		       end         =>'400',
		   });
};

like($@, qr/overlaps/, 'overlapping insert');

# This should fail because the ranges overlap
eval {
    VlanGroup->insert({name        =>'Data3', 
		       description =>'Data Vlans',
		       start       =>'0',
		       end         =>'101',
		   });
};

like($@, qr/overlaps/, 'overlapping insert');

$group->delete;
isa_ok($group, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

