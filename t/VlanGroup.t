use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Vlan');
	use_ok('Netdot::Model::VlanGroup'); 
}

my $group  = VlanGroup->insert({name        =>'Data', 
				description =>'Data Vlans',
				start_vid   =>'100',
				end_vid     =>'300',
			    });
isa_ok($group, 'Netdot::Model::VlanGroup', 'insert');

eval {
    VlanGroup->insert({name        =>'Data2', 
		       description =>'Data Vlans',
		       start_vid   =>'300',
		       end_vid     =>'400',
		   });
};
like($@, qr/overlaps/, 'overlapping insert');

$group->delete;
isa_ok($group, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

