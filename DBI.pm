package Netdot::DBI;

use base 'Class::DBI';

our $VERSION = 20030415;

Netdot::DBI->set_db('Main', 'dbi:mysql:netdot', 'netdot_user', 'netdot_pass');

__PACKAGE__->
  add_trigger( 
	      before_delete=>
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
package Address;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Address' );
__PACKAGE__->columns( All => qw /id street1 street2 poBox city state zip country info disabled/ );

__PACKAGE__->has_many( 'vendors', 'Vendor' => 'address');
__PACKAGE__->has_many( 'sites', 'Site' => 'address');
__PACKAGE__->has_many( 'persons', 'Person' => 'address');
__PACKAGE__->has_many( 'peers', 'Peer' => 'address' );
__PACKAGE__->has_many( 'customers', 'Customer' => 'address' );


######################################################################
package Availability;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Availability' );
__PACKAGE__->columns( All => qw/id name info disabled/ );

__PACKAGE__->has_many( 'customers', 'Customer' => 'availability');
__PACKAGE__->has_many( 'sites', 'Site' => 'availability' );
__PACKAGE__->has_many( 'persons', 'Person' => 'availability' );
__PACKAGE__->has_many( 'peers', 'Peer' => 'availability' );


######################################################################
package Circuit;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Circuit' );
__PACKAGE__->columns( All => qw/id cid vendor startSite endSite type speed installDate connection status info/ );

__PACKAGE__->has_a( type => 'CircuitType' );
__PACKAGE__->has_a( startSite => 'Site' );
__PACKAGE__->has_a( endSite => 'Site' );
__PACKAGE__->has_a( connection => 'Connection' );
__PACKAGE__->has_a( vendor => 'Vendor' );
__PACKAGE__->has_a( status => 'Status' );


######################################################################
package CircuitType;
use base 'Netdot::DBI';

__PACKAGE__->table( 'CircuitType' );
__PACKAGE__->columns( All => qw/id name info disabled/ );

__PACKAGE__->has_many( 'circuits', 'Circuit' => 'type' );


######################################################################
package Connection;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Connection' );
__PACKAGE__->columns( All => qw /id name customer startSite endSite info disabled/ );

__PACKAGE__->has_a( 'startSite' => 'Site' );
__PACKAGE__->has_a( 'endSite' => 'Site' );
__PACKAGE__->has_a( 'customer' => 'Customer' );
__PACKAGE__->has_many( 'circuits', 'Circuit' => 'connection' );


######################################################################
package ContactInfo;
use base 'Netdot::DBI';

__PACKAGE__->table( 'ContactInfo' );
__PACKAGE__->columns( All => qw /id contactType contactPool person email office home cell pager emailPager fax info / );

__PACKAGE__->has_a( contactPool => 'ContactPool' );
__PACKAGE__->has_a( contactType => 'ContactType' );
__PACKAGE__->has_a( person => 'Person' );


######################################################################
package ContactPool;
use base 'Netdot::DBI';

__PACKAGE__->table( 'ContactPool' );
__PACKAGE__->columns( All => qw /id name info disabled/);

__PACKAGE__->has_many( 'contactinfos', 'ContactInfo' => 'contactPool' );
__PACKAGE__->has_many( 'customers', 'Customer' => 'contactPool' );
__PACKAGE__->has_many( 'peers', 'Peer' => 'contactPool' );
__PACKAGE__->has_many( 'nodes', 'Node' => 'contactPool' );
__PACKAGE__->has_many( 'vendors', 'Vendor' => 'contactPool' );
__PACKAGE__->has_many( 'sites', 'Site' => 'contactPool' );


######################################################################
package ContactType;
use base 'Netdot::DBI';

__PACKAGE__->table( 'ContactType' );
__PACKAGE__->columns( All => qw /id name info disabled / );

__PACKAGE__->has_many( 'contactinfos', 'ContactInfo' => 'contactType' );


######################################################################
package Customer;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Customer' );
__PACKAGE__->columns( All => qw/id name availability address contactPool info disabled/ );

__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_a( contactPool => 'ContactPool' );
__PACKAGE__->has_a( availability => 'Availability' );
__PACKAGE__->has_many( 'customers', 'Customer' => 'customer' );
__PACKAGE__->has_many( 'jncustomersites', 'JnCustomerSite' => 'customer' );
__PACKAGE__->has_many( 'nodes', 'Node' => 'customer' );



######################################################################
package Interface;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Interface' );
__PACKAGE__->columns( All => qw/id nodeId hostName physAddr ifIndex ifType ifDescr ifSpeed ifStatus info disabled/ );

__PACKAGE__->has_a( nodeID => 'Node' );
__PACKAGE__->has_many( 'ips', 'Ip' => 'interface' );
__PACKAGE__->has_many( 'parentinterfacedeps', 'InterfaceDep' => 'parent');
__PACKAGE__->has_many( 'childinterfacedeps', 'InterfaceDep' => 'child');


######################################################################
package InterfaceDep;
use base 'Netdot::DBI';

__PACKAGE__->table( 'InterfaceDep' );
__PACKAGE__->columns( All => qw/id parent child/ );

__PACKAGE__->has_a( parent => 'Interface' );
__PACKAGE__->has_a( child => 'Interface' );


######################################################################
package Ip;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Ip' );
__PACKAGE__->columns( All => qw/id interface address mask/ );

__PACKAGE__->has_a( 'interface' => 'Interface' );


######################################################################
package JnNodeService;
use base 'Netdot::DBI';

__PACKAGE__->table( 'JnNodeService' );
__PACKAGE__->columns( All => qw/id node service/ );

__PACKAGE__->has_a( node => 'Node' );
__PACKAGE__->has_a( service => 'Service' );


######################################################################
package JnCustomerSite;
use base 'Netdot::DBI';

__PACKAGE__->table( 'JnCustomerSite' );
__PACKAGE__->columns( All => qw/id customer site/ );

__PACKAGE__->has_a( customer => 'Customer' );
__PACKAGE__->has_a( site => 'Site' );


######################################################################
package Model;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Model' );
__PACKAGE__->columns( All => qw/id name vendor info/ );

__PACKAGE__->has_a( vendor => 'Vendor' );


######################################################################
package Node;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Node' );
__PACKAGE__->columns( All => qw/id name type sysDescription serialNumber site customer room rack dateInstalled sw_version contactPool info disabled/ );

__PACKAGE__->has_a( site => 'Site' );
__PACKAGE__->has_a( customer => 'Customer' );
__PACKAGE__->has_a( contactPool => 'ContactPool' );
__PACKAGE__->has_a( type => 'NodeType' );
__PACKAGE__->has_many( 'interfaces', 'Interface' => 'nodeID' );
__PACKAGE__->has_many( 'jnnodeservices', 'JnNodeService' => 'node' );


######################################################################
package NodeType;
use base 'Netdot::DBI';

__PACKAGE__->table( 'NodeType' );
__PACKAGE__->columns( All => qw/id name info disabled/ );

__PACKAGE__->has_many( 'nodes', 'Node' => 'type' );


######################################################################
package Peer;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Peer' );
__PACKAGE__->columns( All => qw/id name autSys ip address contactPool info/ );

__PACKAGE__->has_a( ip => 'Ip' );
__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_a( contactPool => 'ContactPool' );



######################################################################
package Person;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Person' );
__PACKAGE__->columns( All => qw /id firstName lastName position department address availability info disabled / );

__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_a( availability => 'Availability' );
__PACKAGE__->has_many( 'contactinfos', 'ContactInfo' => 'person' );


######################################################################
package Service;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Service' );
__PACKAGE__->columns( All => qw/id name disabled/ );

__PACKAGE__->has_many( 'jnnodeservices', 'JnNodeService' => 'service' );


######################################################################
package Site;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Site' );
__PACKAGE__->columns( All => qw/id name availability address contactPool info disabled /);

__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_a( availability => 'Availability' );
__PACKAGE__->has_a( contactPool => 'ContactPool' );
__PACKAGE__->has_many( 'startcircuits', 'Circuit' => 'startSite' );
__PACKAGE__->has_many( 'endcircuits', 'Circuit' => 'endSite' );
__PACKAGE__->has_many( 'startconnections', 'Connection' => 'startSite' );
__PACKAGE__->has_many( 'endconnections', 'Connection' => 'endSite' );
__PACKAGE__->has_many( 'jncustomersites', 'JnCustomerSite' => 'site' );
__PACKAGE__->has_many( 'nodes', 'Node' => 'site' );


######################################################################
package Status;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Status' );
__PACKAGE__->columns( All => qw/id name info disabled/ );

__PACKAGE__->has_many( 'circuits', 'Circuit' => 'status' );


######################################################################
package Vendor;
use base 'Netdot::DBI';

__PACKAGE__->table( 'Vendor' );
__PACKAGE__->columns( All => qw/id name contactPool acctNumber address info disabled/ );

__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_a( contactPool => 'ContactPool' );
__PACKAGE__->has_many( 'circuits', 'Circuit' => 'vendor' );
__PACKAGE__->has_many( 'models', 'Model' => 'vendor' );



######################################################################
# be sure to return 1
1;


######################################################################
#  $Log: DBI.pm,v $
#  Revision 1.16  2003/04/15 21:50:01  netdot
#  couple more bugfixes: another 'qw' forgot in Availability and misnamed
#  column in Customer (s/hours/availability/)
#
#  Revision 1.15  2003/04/15 21:36:35  netdot
#  removed tables() function.  Use DBI::tables() instead.
#
#  Revision 1.14  2003/04/15 21:13:48  netdot
#  fixed another bug in Peer package -- forgot 'qw'.
#
#  Revision 1.13  2003/04/15 21:02:08  netdot
#  added tables() to base class.  I need a way to discover all the tables
#  in the database -- don't see a way to do that in Class::DBI.  Fixed
#  bug in package Peer.
#
#  Revision 1.12  2003/04/14 23:32:44  netdot
#  added disabled column to those classes with has_many relationships
#
#  Revision 1.11  2003/04/10 23:53:20  netdot
#  reflected change in netdot.schema.  Ip has_a Interface; Interface
#  has_many Ip.
#
#  Revision 1.10  2003/04/10 23:28:27  netdot
#  added the rest of the classes and completed the relationships between
#  all of them
#
#  Revision 1.9  2003/04/10 21:51:26  netdot
#  updated column names to new naming convention
#
#  Revision 1.8  2003/04/10 21:41:36  netdot
#  added a few more classes
#
#  Revision 1.7  2003/04/10 16:45:18  netdot
#  no changes on this rev; just sorting packages in alphabetical listing
#
#  Revision 1.6  2003/04/10 16:41:54  netdot
#  fleshing out has_a relationships for existing classes.
#
#  Revision 1.5  2003/04/10 00:37:15  netdot
#  fleshing out definitions of each class.
#
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
