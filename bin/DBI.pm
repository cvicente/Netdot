package Netdot::DBI;
use base 'Class::DBI';

## This file was generated from a script.  Do not edit. ##

Netdot::DBI->set_db('Main', 'dbi:mysql:netdot', 'netdot_user', 'netdot_pass');


##########################################
## Insert object in history table
##########################################


__PACKAGE__->
  add_trigger( 
	      before_update=>
	       sub {
		   my $self = shift;
		   my $class = ref ($self);
		   my (%current_data, $new_h_obj, $oid);
		   my $user = $ENV{REMOTE_USER} || "unknown";
		   my $dbobj = ( $class->retrieve_from_sql(qq{
		       id = "$self->id"
		   }) )[0];
		   foreach my $col ($self->columns){
		       next if ($col eq 'id');
		       $current_data{$col} = $dbobj->$col;
		   }
		   my $table = ref($self);
		   my $h_table = "$table" . "_history";
		   $oid = lc("$table" . "_id");
		   return unless eval { ## h_table might not exist
		       $new_h_obj = $h_table->create(\%current_data);
		       1;
		   };
		   $new_h_obj->set($oid, $self->id);
		   $new_h_obj->set("modifier", $user);
		   my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
		       $wday, $yday, $isdst) = localtime;
		   my $datetime = sprintf("%04d/%02d/%02d %02d:%02d:%02d",
					  $year+1900, $month+1, $day_of_month, $hours, $minutes, $seconds);
		   $new_h_obj->set("modified", $datetime);
		   $new_h_obj->update;
	       }
	     );




######################################################################
package Address;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Address' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / street1 street2 city state zip /);
__PACKAGE__->columns( Others => qw / info country pobox /);
__PACKAGE__->has_many( 'sites', 'Site' => 'address', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'persons', 'Person' => 'address', {on_delete=>"set-null"} );


######################################################################
package Address_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Address_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier street1 street2 city state zip /);
__PACKAGE__->columns( Others => qw / info country pobox address_id /);


######################################################################
package Availability;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Availability' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'sites', 'Site' => 'availability', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'entities', 'Entity' => 'availability', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'notify_emails', 'Contact' => 'notify_email', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'notify_pagers', 'Contact' => 'notify_pager', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'notify_voices', 'Contact' => 'notify_voice', {on_delete=>"set-null"} );


######################################################################
package Cable;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Cable' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name startsite startroom endsite endroom /);
__PACKAGE__->columns( Others => qw / info installdate owner numberofstrands length type /);
__PACKAGE__->has_a( type => 'CableType' );
__PACKAGE__->has_a( owner => 'Entity' );
__PACKAGE__->has_a( startsite => 'Site' );
__PACKAGE__->has_a( endsite => 'Site' );
__PACKAGE__->has_many( 'strands', 'CableStrand' => 'cable' );


######################################################################
package CableStrand;
use base 'Netdot::DBI';
__PACKAGE__->table( 'CableStrand' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name cable direction status /);
__PACKAGE__->columns( Others => qw / info description loss /);
__PACKAGE__->has_a( cable => 'Cable' );
__PACKAGE__->has_a( status => 'StrandStatus' );


######################################################################
package CableStrand_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'CableStrand_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier cable name direction /);
__PACKAGE__->columns( Others => qw / info status description cablestrand_id loss /);
__PACKAGE__->has_a( cable => 'Cable' );
__PACKAGE__->has_a( status => 'StrandStatus' );


######################################################################
package CableType;
use base 'Netdot::DBI';
__PACKAGE__->table( 'CableType' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'cables', 'Cable' => 'type', {on_delete=>"restrict"} );


######################################################################
package Cable_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Cable_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier name startsite endsite /);
__PACKAGE__->columns( Others => qw / info installdate owner cable_id numberofstrands length startroom endroom type /);
__PACKAGE__->has_a( type => 'CableType' );
__PACKAGE__->has_a( startsite => 'Site' );
__PACKAGE__->has_a( endsite => 'Site' );


######################################################################
package Circuit;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Circuit' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / cid connection nearend farend type vendor status /);
__PACKAGE__->columns( Others => qw / info installdate dlci speed /);
__PACKAGE__->has_a( type => 'CircuitType' );
__PACKAGE__->has_a( nearend => 'Interface' );
__PACKAGE__->has_a( farend => 'Interface' );
__PACKAGE__->has_a( connection => 'Connection' );
__PACKAGE__->has_a( vendor => 'Entity' );
__PACKAGE__->has_a( status => 'CircuitStatus' );


######################################################################
package CircuitStatus;
use base 'Netdot::DBI';
__PACKAGE__->table( 'CircuitStatus' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'circuits', 'Circuit' => 'status', {on_delete=>"restrict"} );


######################################################################
package CircuitType;
use base 'Netdot::DBI';
__PACKAGE__->table( 'CircuitType' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'circuits', 'Circuit' => 'type', {on_delete=>"restrict"} );


######################################################################
package Circuit_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Circuit_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier cid connection nearend farend type vendor status /);
__PACKAGE__->columns( Others => qw / info installdate circuit_id dlci speed /);
__PACKAGE__->has_a( type => 'CircuitType' );
__PACKAGE__->has_a( nearend => 'Interface' );
__PACKAGE__->has_a( farend => 'Interface' );
__PACKAGE__->has_a( connection => 'Connection' );
__PACKAGE__->has_a( vendor => 'Entity' );
__PACKAGE__->has_a( status => 'CircuitStatus' );


######################################################################
package ComponentType;
use base 'Netdot::DBI';
__PACKAGE__->table( 'ComponentType' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'devices', 'Device' => 'component_type', {on_delete=>"restrict"} );


######################################################################
package Connection;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Connection' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name entity nearend farend /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_a( nearend => 'Site' );
__PACKAGE__->has_a( farend => 'Site' );
__PACKAGE__->has_a( entity => 'Entity' );
__PACKAGE__->has_many( 'circuits', 'Circuit' => 'connection', {on_delete=>"set-null"} );


######################################################################
package Connection_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Connection_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier name entity nearend farend /);
__PACKAGE__->columns( Others => qw / info connection_id /);
__PACKAGE__->has_a( nearend => 'Site' );
__PACKAGE__->has_a( farend => 'Site' );
__PACKAGE__->has_a( entity => 'Entity' );


######################################################################
package Contact;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Contact' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / person contacttype contactlist /);
__PACKAGE__->columns( Others => qw / info notify_email notify_voice notify_pager /);
__PACKAGE__->has_a( contactlist => 'ContactList' );
__PACKAGE__->has_a( contacttype => 'ContactType' );
__PACKAGE__->has_a( person => 'Person' );
__PACKAGE__->has_a( notify_email => 'Availability' );
__PACKAGE__->has_a( notify_pager => 'Availability' );
__PACKAGE__->has_a( notify_voice => 'Availability' );


######################################################################
package ContactList;
use base 'Netdot::DBI';
__PACKAGE__->table( 'ContactList' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name info /);
__PACKAGE__->has_many( 'contacts', 'Contact' => 'contactlist' );
__PACKAGE__->has_many( 'entities', 'Entity' => 'contactlist', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'devices', 'Device' => 'contactlist', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'sites', 'Site' => 'contactlist', {on_delete=>"set-null"} );


######################################################################
package ContactType;
use base 'Netdot::DBI';
__PACKAGE__->table( 'ContactType' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'contacts', 'Contact' => 'contacttype', {on_delete=>"restrict"} );


######################################################################
package Contact_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Contact_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier contacttype person /);
__PACKAGE__->columns( Others => qw / info notify_email notify_voice contactlist notify_pager contact_id /);
__PACKAGE__->has_a( contactlist => 'ContactList' );
__PACKAGE__->has_a( contacttype => 'ContactType' );
__PACKAGE__->has_a( person => 'Person' );
__PACKAGE__->has_a( notify_email => 'Availability' );
__PACKAGE__->has_a( notify_pager => 'Availability' );
__PACKAGE__->has_a( notify_voice => 'Availability' );


######################################################################
package Device;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Device' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name type productname /);
__PACKAGE__->columns( Others => qw / room sw_version community entity physaddr maint_covered user inventorynumber component_type info sysdescription part_of managed site rack oobname contactlist aliases oobnumber serialnumber dateinstalled /);
__PACKAGE__->has_a( type => 'DeviceType' );
__PACKAGE__->has_a( entity => 'Entity' );
__PACKAGE__->has_a( contactlist => 'ContactList' );
__PACKAGE__->has_a( user => 'Person' );
__PACKAGE__->has_a( component_type => 'ComponentType' );
__PACKAGE__->has_a( productname => 'Product' );
__PACKAGE__->has_a( part_of => 'Device' );
__PACKAGE__->has_a( site => 'Site' );
__PACKAGE__->has_many( 'interfaces', 'Interface' => 'device' );
__PACKAGE__->has_many( 'services', 'DeviceService' => 'device' );
__PACKAGE__->has_many( 'parts', 'Device' => 'part_of' );


######################################################################
package DeviceService;
use base 'Netdot::DBI';
__PACKAGE__->table( 'DeviceService' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / device service /);
__PACKAGE__->has_a( device => 'Device' );
__PACKAGE__->has_a( service => 'Service' );


######################################################################
package DeviceType;
use base 'Netdot::DBI';
__PACKAGE__->table( 'DeviceType' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'devices', 'Device' => 'type', {on_delete=>"restrict"} );


######################################################################
package Device_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Device_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier name type /);
__PACKAGE__->columns( Others => qw / room sw_version community entity physaddr maint_covered user inventorynumber component_type info part_of sysdescription managed device_id site rack oobname contactlist serialnumber oobnumber aliases productname dateinstalled /);
__PACKAGE__->has_a( type => 'DeviceType' );
__PACKAGE__->has_a( entity => 'Entity' );
__PACKAGE__->has_a( contactlist => 'ContactList' );
__PACKAGE__->has_a( user => 'Person' );
__PACKAGE__->has_a( component_type => 'ComponentType' );
__PACKAGE__->has_a( productname => 'Product' );
__PACKAGE__->has_a( part_of => 'Device' );
__PACKAGE__->has_a( site => 'Site' );


######################################################################
package Entity;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Entity' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name type /);
__PACKAGE__->columns( Others => qw / maint_contract bgppeerip availability info acctnumber autsys contactlist aliases /);
__PACKAGE__->has_a( contactlist => 'ContactList' );
__PACKAGE__->has_a( availability => 'Availability' );
__PACKAGE__->has_a( type => 'EntityType' );
__PACKAGE__->has_many( 'connections', 'Connection' => 'entity' );
__PACKAGE__->has_many( 'sites', 'EntitySite' => 'entity' );
__PACKAGE__->has_many( 'products', 'Product' => 'manufacturer' );
__PACKAGE__->has_many( 'subnets', 'Subnet' => 'entity', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'cables', 'Cable' => 'owner', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'devices', 'Device' => 'entity', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'persons', 'Person' => 'entity' );


######################################################################
package EntitySite;
use base 'Netdot::DBI';
__PACKAGE__->table( 'EntitySite' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / entity site /);
__PACKAGE__->has_a( entity => 'Entity' );
__PACKAGE__->has_a( site => 'Site' );


######################################################################
package EntityType;
use base 'Netdot::DBI';
__PACKAGE__->table( 'EntityType' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'entities', 'Entity' => 'type', {on_delete=>"restrict"} );


######################################################################
package Entity_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Entity_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier name type /);
__PACKAGE__->columns( Others => qw / maint_contract bgppeerip availability info acctnumber autsys contactlist entity_id aliases /);
__PACKAGE__->has_a( contactlist => 'ContactList' );
__PACKAGE__->has_a( availability => 'Availability' );
__PACKAGE__->has_a( type => 'EntityType' );


######################################################################
package Interface;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Interface' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / number name device description /);
__PACKAGE__->columns( Others => qw / status speed physaddr info managed type /);
__PACKAGE__->has_a( device => 'Device' );
__PACKAGE__->has_many( 'ips', 'Ip' => 'interface' );
__PACKAGE__->has_many( 'parents', 'InterfaceDep' => 'child' );
__PACKAGE__->has_many( 'children', 'InterfaceDep' => 'parent' );
__PACKAGE__->has_many( 'nearcircuits', 'Circuit' => 'nearend', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'farcircuits', 'Circuit' => 'farend', {on_delete=>"set-null"} );


######################################################################
package InterfaceDep;
use base 'Netdot::DBI';
__PACKAGE__->table( 'InterfaceDep' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / parent child /);
__PACKAGE__->has_a( parent => 'Interface' );
__PACKAGE__->has_a( child => 'Interface' );


######################################################################
package Interface_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Interface_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / number name device description modified modifier /);
__PACKAGE__->columns( Others => qw / status speed physaddr info interface_id managed type /);
__PACKAGE__->has_a( device => 'Device' );


######################################################################
package Ip;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Ip' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / address mask interface /);
__PACKAGE__->columns( Others => qw / subnet /);
__PACKAGE__->has_a( interface => 'Interface' );
__PACKAGE__->has_a( subnet => 'Subnet' );
__PACKAGE__->has_many( 'names', 'Name' => 'ip' );


######################################################################
package Ip_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Ip_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier address mask interface /);
__PACKAGE__->columns( Others => qw / ip_id subnet /);
__PACKAGE__->has_a( interface => 'Interface' );
__PACKAGE__->has_a( subnet => 'Subnet' );


######################################################################
package Meta;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Meta' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Others => qw / columnorder columnorderbrief isjoin linksfrom name description linksto label columntypes /);


######################################################################
package Name;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Name' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name ip /);
__PACKAGE__->has_a( ip => 'Ip' );


######################################################################
package Name_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Name_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier name ip /);
__PACKAGE__->columns( Others => qw / name_id /);
__PACKAGE__->has_a( ip => 'Ip' );


######################################################################
package Netviewer;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Netviewer' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Others => qw / value name /);


######################################################################
package NvIfReserved;
use base 'Netdot::DBI';
__PACKAGE__->table( 'NvIfReserved' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Others => qw / name /);


######################################################################
package Person;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Person' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / lastname firstname office entity /);
__PACKAGE__->columns( Others => qw / position email availability fax address cell home info emailpager aliases pager /);
__PACKAGE__->has_a( entity => 'Entity' );
__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_many( 'roles', 'Contact' => 'person' );
__PACKAGE__->has_many( 'devices', 'Device' => 'user', {on_delete=>"set-null"} );


######################################################################
package Person_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Person_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier lastname firstname position entity /);
__PACKAGE__->columns( Others => qw / email availability fax address cell home info person_id emailpager office aliases pager /);
__PACKAGE__->has_a( entity => 'Entity' );
__PACKAGE__->has_a( address => 'Address' );


######################################################################
package Product;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Product' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name description manufacturer /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_a( manufacturer => 'Entity' );
__PACKAGE__->has_many( 'devices', 'Device' => 'productname', {on_delete=>"restrict"} );


######################################################################
package Product_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Product_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier name description manufacturer /);
__PACKAGE__->columns( Others => qw / product_id info /);
__PACKAGE__->has_a( manufacturer => 'Entity' );


######################################################################
package Service;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Service' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'devices', 'DeviceService' => 'service' );


######################################################################
package Site;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Site' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name address /);
__PACKAGE__->columns( Others => qw / availability info contactlist aliases /);
__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_a( availability => 'Availability' );
__PACKAGE__->has_a( contactlist => 'ContactList' );
__PACKAGE__->has_many( 'nearconnections', 'Connection' => 'nearend' );
__PACKAGE__->has_many( 'farconnections', 'Connection' => 'farend' );
__PACKAGE__->has_many( 'entities', 'EntitySite' => 'site', {on_delete=>"set-null"} );
__PACKAGE__->has_many( 'devices', 'Device' => 'site', {on_delete=>"set-null"} );


######################################################################
package Site_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Site_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier name address /);
__PACKAGE__->columns( Others => qw / site_id availability info contactlist aliases /);
__PACKAGE__->has_a( address => 'Address' );
__PACKAGE__->has_a( availability => 'Availability' );
__PACKAGE__->has_a( contactlist => 'ContactList' );


######################################################################
package StrandStatus;
use base 'Netdot::DBI';
__PACKAGE__->table( 'StrandStatus' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / name /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_many( 'strands', 'CableStrand' => 'status', {on_delete=>"restrict"} );


######################################################################
package Subnet;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Subnet' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / address prefix entity description /);
__PACKAGE__->columns( Others => qw / info /);
__PACKAGE__->has_a( entity => 'Entity' );
__PACKAGE__->has_many( 'ips', 'Ip' => 'subnet', {on_delete=>"restrict"} );


######################################################################
package Subnet_history;
use base 'Netdot::DBI';
__PACKAGE__->table( 'Subnet_history' );
__PACKAGE__->columns( Primary => qw / id /);
__PACKAGE__->columns( Essential => qw / modified modifier address prefix entity description /);
__PACKAGE__->columns( Others => qw / subnet_id info /);
__PACKAGE__->has_a( entity => 'Entity' );

#Be sure to return 1
1;
