package Netdot::DBI;

use base 'Class::DBI';

Netdot::DBI->set_db('Main', 'dbi:mysql:netdot', 'netdot_user', 'netdot_pass');

__PACKAGE__->
  add_trigger( before_delete=>
	       sub {
		 my $self = shift;
		 my $class   = ref($self);
		 my %cascade = %{ $class->__hasa_list || {} };
		 foreach my $remote (keys %cascade) {
		   foreach ($remote->search($cascade{$remote} => $self->id)){
		     $_->set($cascade{$remote}, 'NULL');
		     $_->update;
		   }
		 }
	       }
	     );


######################################################################
package Circuit;
use base 'Netdot::DBI';

__PACKAGE__->table('Circuit');

__PACKAGE__->columns(All => qw/ id CID Vendor StartSite EndSite Type Speed InstallDate Connection Info /);

__PACKAGE__->has_a(Type => 'CircuitType');
__PACKAGE__->has_a(StartSite => 'Site');
__PACKAGE__->has_a(EndSite => 'Site');
__PACKAGE__->has_a(Connection => 'Connection');
__PACKAGE__->has_a(Vendor => 'Vendor');


######################################################################
package CircuitType;
use base 'Netdot::DBI';

__PACKAGE__->table('CircuitType');

__PACKAGE__->columns(All => qw/id Name Info /);

__PACKAGE__->has_many('circuits', 'Circuit' => 'Type');


######################################################################
package Connection;
use base 'Netdot::DBI';

__PACKAGE__->table('Connection');
__PACKAGE__->columns(All => qw /id Name Customer StartSite EndSite Info /);

__PACKAGE__->has_a('StartSite' => 'Site');
__PACKAGE__->has_a('EndSite' => 'Site');
__PACKAGE__->has_many('circuits', 'Circuit' => 'Connection');


######################################################################
package Vendor;
use base 'Netdot::DBI';

__PACKAGE__->table('Vendor');

__PACKAGE__->columns(All => qw/id Name Contactpool AcctNumber Address Info/);
__PACKAGE__->has_a(Address => 'Address');
__PACKAGE__->has_many('circuits', 'Circuit' => 'Vendor');


######################################################################
package Site;
use base 'Netdot::DBI';

__PACKAGE__->table('Site');

__PACKAGE__->columns(All => qw/id Name Availability Address ContactPool Info /);

__PACKAGE__->has_a(Address => 'Address');
__PACKAGE__->has_many('startcircuits', 'Circuit' => 'StartSite');
__PACKAGE__->has_many('endcircuits', 'Circuit' => 'EndSite');
__PACKAGE__->has_many('startconnections', 'Connection' => 'StartSite');
__PACKAGE__->has_many('endconnections', 'Connection' => 'EndSite');


######################################################################
package Address;
use base 'Netdot::DBI';

__PACKAGE__->table('Address');
__PACKAGE__->columns(All => qw /id Street1 Street2 POBox City State Zip Country Info /);

__PACKAGE__->has_many('vendors', 'Vendor' => 'Address');
__PACKAGE__->has_many('sites', 'Site' => 'Address');
__PACKAGE__->has_many('persons', 'Person' => 'Address');


######################################################################
package ContactPool;
use base 'Netdot::DBI';

__PACKAGE__->table('ContactPool');
__PACKAGE__->columns(All => qw /id Name Info /);

__PACKAGE__->has_many('vendors', 'Vendor' => 'ContactPool');
__PACKAGE__->has_many('sites', 'Site' => 'ContactPool');
__PACKAGE__->has_many('contactinfos', 'ContactInfo' => 'ContactPool');


######################################################################
package ContactInfo;
use base 'Netdot::DBI';

__PACKAGE__->table('ContactInfo');
__PACKAGE__->columns(All => qw /id ContactType ContactPool Person Email Office Home Cell Pager 
		     EmailPager Fax Info /);

__PACKAGE__->has_a(ContactType => 'ContactPool');
__PACKAGE__->has_a(ContactType => 'ContactType');
__PACKAGE__->has_a(Person => 'Person');


######################################################################
package ContactType;
use base 'Netdot::DBI';

__PACKAGE__->table('ContactType');
__PACKAGE__->columns(All => qw /id Name Info /);

__PACKAGE__->has_many('contactinfos', 'ContactInfo' => 'ContactType');


######################################################################
package Person;
use base 'Netdot::DBI';

__PACKAGE__->table('Person');
__PACKAGE__->columns(All => qw /id FirstName LastName Position Department Address Availability Info /);

__PACKAGE__->has_a(Address => 'Address');
__PACKAGE__->has_many('contactinfos', 'ContactInfo' => 'Person');


######################################################################
# be sure to return 1
1;


######################################################################
#  $Log: DBI.pm,v $
#  Revision 1.4  2003/04/09 20:59:40  netdot
#  adding landmarks
#
#  Revision 1.3  2003/04/08 22:59:51  netdot
#  testing trigger
#
#  Revision 1.2  2003/04/08 17:47:45  netdot
#  just checking in....
#
#  Revision 1.1  2003/04/08 17:35:24  netdot
#  Initial revision
#
