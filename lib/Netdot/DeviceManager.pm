package Netdot::DeviceManager;

=head1 NAME

Netdot::DeviceManager - Device-related Functions for Netdot

=head1 SYNOPSIS

  use Netdot::DeviceManager

  $dm = Netdot::DeviceManager->new();  

=cut

use lib "<<Make:LIB>>";
use Data::Dumper;

use SNMP::Info;

use base qw( Netdot );
use Netdot::IPManager;
use Netdot::DNSManager;
use strict;

#Be sure to return 1
1;

=head1 METHODS

=head2 new - Create a new DeviceManager object
 
    $dm = Netdot::DeviceManager->new(loglevel      => $loglevel,
				     logfacility   => $logfacility,
				     logident      => $logident,
				     foreground    => $foreground);

=cut

sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    my %libargs = (logfacility => $argv{'logfacility'},
		   loglevel    => $argv{'loglevel'},
		   logident    => $argv{'logident'},
		   foreground  => $argv{'foreground'});
    
    $self = $class->SUPER::new(%libargs);
    
  
    $self->{'_ipm'} =  Netdot::IPManager->new(%libargs);
    $self->{'_dns'} =  Netdot::DNSManager->new(%libargs);

    bless $self, $class;
    wantarray ? ( $self, '' ) : $self; 
}

=head2 output -  Store and get appended output for interactive use
    
    $dm->output("Doing this and that");
    print $dm->output();

=cut
   
sub output {
	my $self = shift;
    if (@_){ 
	$self->{'_output'} .= shift;
	$self->{'_output'} .= "\n";
    }
    return $self->{'_output'};
}

=head2 find_dev - Perform some preliminary checks to determine if a device exists

  Arguments:

    Hostname or IP address (string)

  Returns:

    If Device is found, returns hash reference with the following keys:
       device - Device object
       comstr - Community String
    If Device is not found, returns undef.

  Example:
    
    my $hashref = $dm->find_dev($host);

=cut

sub find_dev {
    my ($self, $host) = @_;
    $self->error(undef);
    my %r;

    if ($r{device} = $self->{'_dns'}->getdevbyname($host)){
	my $msg = sprintf("Device %s exists in DB.", $host);
	$self->debug( loglevel => 'LOG_NOTICE', message  => $msg );
	$r{comstr} = $r{device}->community;
    }elsif($self->{'_dns'}->getrrbyname($host)){
	my $msg = sprintf("Name %s exists but Device not in DB", $host);
	$self->debug( loglevel => 'LOG_NOTICE', message  => $msg );
	return;
    }elsif(my $ip = $self->{'_ipm'}->searchblocks_addr($host)){
	if ( $ip->interface && ($r{device} = $ip->interface->device) ){
	    my $msg = sprintf("Device with address %s exists in DB", $ip->address);
	    $self->debug( loglevel => 'LOG_NOTICE', message  => $msg );
	    $r{comstr} = $r{device}->community;
	}else{
	    my $msg = sprintf("Address %s exists but Device not in DB", $host);
	    $self->debug( loglevel => 'LOG_NOTICE', message  => $msg );
	}
    }else{
	my $msg = sprintf("Device %s not in DB", $host);
	$self->debug( loglevel => 'LOG_NOTICE', message  => $msg );
	return;
    }
    return \%r;
}

=head2 update_device - Insert new Device/Update Device in Database

 This method can be called from Netdot s web components or 
 from independent scripts.  Should be able to update existing 
 devices or create new ones

  Arguments:
    Hash ref with following keys
   (Required):
     host:       Name or ip address of host
   (Optional):
     info:       Hash with Device SNMP information.  
                 If not passed, this method will try to get it.
     owner:      Id of Owner Entity
     used_by:    Id of Entity that is using the device
     comstr:     SNMP community string (default "public")
     device:     Existing 'Device' object.  If string 'NEW' is passed, method will
                 not try to find the device object in the DB.
     addsubnets: When discovering routers, add subnets to database if they do not exist
     site:       Id of Site where Device is located
     user:       Netdot user calling the method 

  Returns:
    Device object

  Example:

=cut

sub update_device {
    my ($self, $argv) = @_;
    my ($host, $info);
    $self->_clear_output();

    unless ( $host = $argv->{host} ){
	$self->error("Missing required arguments");
	$self->debug(loglevel => 'LOG_ERR',
		     message => $self->error);
	return 0;
    }

    my $device    = $argv->{device} if ( $argv->{device} ne 'NEW' ) ;
    my $comstr    = $argv->{comstr} || "public";
    
    if ( ! $device && $argv->{device} ne 'NEW' ){
	# A device object wasn't passed, so figure out if it exists
	if ( my $res = $self->find_dev($host) ){
	    $device = $res->{device};
	    $comstr = $res->{comstr};
	}
    }
    # Add this field to the Device table
    my $snmpversion;
#    if ($device && $device->snmpversion){
#	$snmpversion = $device->snmpversion;
#    }else{
	$snmpversion = $self->{'_snmpversion'};
#    }
    unless ( $info = $argv->{info} ){
	##############################################
	# Fetch SNMP info from device
	$info = $self->get_dev_info(host=>$host, comstr=>$comstr, version=>$snmpversion);
	unless ($info){
	    # error should be set
	    $self->debug( loglevel => 'LOG_ERR',
			  message  => $self->error);
	    return 0;
	}
    }

    # Hash to be passed to insert/update function
    my %devtmp;
    $devtmp{sysdescription} = $info->{sysdescription} || "";

    my @cls;
    my %ifs;
    my %bgppeers;
    my %dbips;

    if ( $device ){ # Device exists in DB

	################################################     
	# Keep a hash of stored Interfaces for this Device
	map { $ifs{ $_->id } = $_ } $device->interfaces();

	# Get all stored IPs 
	map { $dbips{$_->address} = $_->id } map { $ifs{$_}->ips() } keys %ifs;

	# Remove invalid dependencies
	foreach my $ifid (keys %ifs){
	    my $if = $ifs{$ifid};
	    foreach my $dep ( $if->parents() ){		
		unless ( $dep->parent->device ){
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => "%s: Interface %s,%s has invalid parent %s. Removing.",
				  args => [$host, $if->number, $if->name, $dep->parent] );
		    $self->remove(table=>"InterfaceDep", id => $dep->id);
		    next;
		}
	    }
	    foreach my $dep ( $if->children() ){
		unless ( $dep->child->device ){
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => "%s: Interface %s,%s has invalid child %s. Removing.",
				  args => [$host, $if->number, $if->name,$dep->child] );
		    $self->remove(table=>"InterfaceDep", id => $dep->id);
		    next;
		}
	    }
	}

    }else{   # Device does not exist in DB
	$devtmp{community}      = $comstr;
	$devtmp{owner}          = $argv->{owner}          || 0;
	$devtmp{used_by}        = $argv->{used_by}        || 0;
	$devtmp{site}           = $argv->{site}           || 0;

	if ( defined ($argv->{user}) ){
	    $devtmp{info} = "Added to Netdot by $argv->{user}";
	}
	
	if ( ! $argv->{contacts} ){
	    my $default_cl;
	    unless ( $default_cl = (ContactList->search(name=>$self->{config}->{DEFAULT_CONTACTLIST}))[0] ){
		$self->debug( loglevel => 'LOG_ERR',
			      message  => "%s: Default Contact List not found: %s",
			      args     => [$host, $self->{config}->{DEFAULT_CONTACTLIST}] );
	    }
	    push @cls, $default_cl;
	}else{
	    if (!ref($argv->{contacts})){
		# Only one was selected, so it is a scalar
		push @cls, $argv->{contacts};
	    }elsif( ref($argv->{contacts}) eq "ARRAY" ){
		@cls = @{ $argv->{contacts} };
	    }else{
		$self->debug( loglevel => 'LOG_ERR',
			      message  => "%s: A contacts arg was passed, but was not valid: %s",
			      args     => [$host, $argv->{contacts}] );
	    }
	}
	
    }

    ##############################################
    # Make sure name is in DNS

    my $rr;
    if ( $rr = $self->{'_dns'}->getrrbyname($host) ) {
	my $msg = sprintf("Name %s exists in DB. Pointing to it", $host);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg);
	$devtmp{name} = $rr;
    }elsif($device && $device->name && $device->name->name){
	my $msg = sprintf("Device %s exists in DB as %s. Keeping existing name", $host, $device->name->name);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg);
	$devtmp{name} = $device->name;
	$rr = $device->name;
	$host = $device->name->name;
    }else{
	# Check if hostname is an ip address (v4 or v6)
	if ( $host =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/ ||
	     $host =~ /:/){
	    # It is, so look it up
	    my $name;
	    if ( $name = $self->resolve_ip($host) ){
		my $msg = sprintf("Name associated with %s: %s", $host, $name );
		$self->debug( loglevel => 'LOG_DEBUG',
			      message  => $msg
			      );	    
		# Use this name instead
		$host = $name;
	    }else{
		my $msg = sprintf("%s", $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg
			      );	    
		$self->error($msg);	
	    }
	}
	if ($rr = $self->{'_dns'}->insert_rr(name => $host)){

	    my $msg = sprintf("Inserted DNS name %s into DB", $host);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );	    
	    $self->output($msg);
	    $devtmp{name} = $rr;
	}else{
	    my $msg = sprintf("Could not insert DNS entry %s: %s", $host, $self->error);
	    $self->debug( loglevel => 'LOG_ERR',
			  message  => $msg
			  );	    
	    $self->error($msg);
	    return 0;
	}
    }
    # We'll use these later when adding A records for each address
    my %hostnameips;
    if (my @addrs = $self->{'_dns'}->resolve_name($rr->name)){
	map { $hostnameips{$_} = "" } @addrs;
	
	my $msg = sprintf("%s: Addresses associated with hostname: %s", $host, (join ", ", keys %hostnameips) );
	$self->debug( loglevel => 'LOG_DEBUG',
		      message  => $msg
		      );	    
    }else{
	my $msg = sprintf("%s", $self->error);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg
		      );	    
	$self->error($msg);	
    }
    ###############################################
    # Try to assign Product based on SysObjectID

    if( $info->{sysobjectid} ){
	if ( my $prod = (Product->search( sysobjectid => $info->{sysobjectid} ))[0] ) {
	    my $msg = sprintf("%s: SysID matches existing %s", $host, $prod->name);
	    $self->debug( loglevel => 'LOG_INFO',message  => $msg );
	    $devtmp{productname} = $prod->id;
	    
	}else{
	    ###############################################
	    # Create a new product entry
	    my $msg = sprintf("%s: New product with SysID %s.  Adding to DB", $host, $info->{sysobjectid});
	    $self->debug( loglevel => 'LOG_INFO', message  => $msg );
	    $self->output( $msg );	
	    
	    ###############################################
	    # Check if Manufacturer Entity exists or can be added
	    
	    my $oid = $info->{enterprise};
	    my $ent;
	    if($ent = (Entity->search( oid => $oid ))[0] ) {
		$self->debug( loglevel => 'LOG_INFO',
			      message  => "Manufacturer OID matches %s", 
			      args     => [$ent->name]);
	    }else{
		$self->debug( loglevel => 'LOG_INFO',
			      message  => "Entity with Enterprise OID %s not found. Creating", 
			      args => [$oid]);
		my $t;
		unless ( $t = (EntityType->search(name => "Manufacturer"))[0] ){
		    $t = 0; 
		}
		my $entname = $info->{manufacturer} || $oid;
		if ( ($ent = $self->insert(table => 'Entity', 
					   state => { name => $entname,
						      oid  => $oid,
						      type => $t }) ) ){
		    my $msg = sprintf("Created Entity: %s. ", $entname);
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => $msg );		
		}else{
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => "Could not create new Entity: %s: %s",
				  args     => [$entname, $self->error],
				  );
		    $ent = 0;
		}
	    }
	    ###############################################
	    # Try to guess product type
	    # First based on name, then on some key oids
	    
	    my $type;
	    my $typename;
	    foreach my $str ( keys %{ $self->{config}->{DEV_NAME2TYPE} } ){
		if ( $host =~ /$str/ ){
		    $typename = $self->{config}->{DEV_NAME2TYPE}->{$str};
		}
	    } 
	    if ( $typename ){
		$type = (ProductType->search(name=>$typename))[0];	    
	    }else{
		if ( $info->{router} ){
		    $type = (ProductType->search(name=>"Router"))[0];
		}elsif ( $info->{hub} ){
		    $type = (ProductType->search(name=>"Hub"))[0];
		}elsif ( $info->{dot11} ){
		    $type = (ProductType->search(name=>"Access Point"))[0];
		}elsif ( scalar $info->{interface} ){
		    $type = (ProductType->search(name=>"Switch"))[0];
		}
	    }
	    my %prodtmp = ( name         => $info->{productname} || $info->{model},
			    description  => $info->{productname},
			    sysobjectid  => $info->{sysobjectid},
			    type         => $type->id,
			    manufacturer => $ent,
			    );
	    my $newprodid;
	    if ( ($newprodid = $self->insert(table => 'Product', state => \%prodtmp)) ){
		my $msg = sprintf("%s: Created product: %s.  Guessing type is %s.", $host, $prodtmp{name}, $type->name);
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => $msg );		
		$self->output($msg);
		$devtmp{productname} = $newprodid;
	    }else{
		$self->debug( loglevel => 'LOG_ERR',
			      message  => "%s: Could not create new Product: %s: %s",
			      args     => [$host, $prodtmp{name}, $self->error],
			      );		
		$devtmp{productname} = 0;
	    }
	}
    }else{
	$devtmp{productname} = 0;
    }

    ###############################################
    # Update/add PhsyAddr for Device
    
    if( defined $info->{physaddr} ) {
	# Look it up
	if ( my $phy = (PhysAddr->search(address => $info->{physaddr}))[0] ){
	    if ( my $otherdev = ($phy->devices)[0] ){
		#
		# At least another device exists that has that address
		# 
		if ( ! $device || ( $device && $device->id != $otherdev->id ) ){
		    my $name = (defined($otherdev->name->name))? $otherdev->name->name : $otherdev->id;
		    $self->error( sprintf("%s: PhysAddr %s belongs to existing device: %s. Aborting", 
					  $host, $info->{physaddr}, $name ) ); 
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => $self->error,
				  );
		    return 0;
		}
	    }else{
		#
		# The address exists but it's not the base bridge address of any other device
		# (maybe discovered in fw tables/arp cache)
		# Just point to it from this Device
		#
		$devtmp{physaddr} = $phy->id;
		$self->update( object => $phy, 
			       state  => {last_seen => $self->timestamp },
			       );
	    }
	    $self->debug( loglevel => 'LOG_INFO',
			  message  => "%s, Pointing to existing %s as base bridge address",
			  args => [$host, $info->{physaddr}],
			  );		
	    #
	    # address is new.  Add it
	    #
	}else{
	    my %phaddrtmp = ( address    => $info->{physaddr},
			      first_seen => $self->timestamp,
			      last_seen  => $self->timestamp,
			      );
	    my $newphaddr;
	    if ( ! ($newphaddr = $self->insert(table => 'PhysAddr', state => \%phaddrtmp)) ){
		$self->debug( loglevel => 'LOG_ERR',
			      message  => "%s, Could not create new PhysAddr: %s: %s",
			      args => [$host, $phaddrtmp{address}, $self->error],
			      );
		$devtmp{physaddr} = 0;
	    }else{
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => "%s: Added new PhysAddr: %s",
			      args => [$host, $phaddrtmp{address}],
			      );		
		$devtmp{physaddr} = $newphaddr;
	    }
	}
    }else{
	$self->debug( loglevel => 'LOG_INFO',
		      message  => "%s did not return dot1dBaseBridgeAddress",
		      args => [$host],
		      );
	$devtmp{physaddr} = 0;
    }
    ###############################################
    # Serial Number
    
    if( defined $info->{serialnumber} ) {
	if ( my $otherdev = (Device->search(serialnumber => $info->{serialnumber}))[0] ){
	    if ( ! $device || ($device && $device->id != $otherdev->id) ){
		my $othername = (defined $otherdev->name && defined $otherdev->name->name) ? 
		    $otherdev->name->name : $otherdev->id;
		$self->error( sprintf("%s: S/N %s belongs to existing device: %s. Aborting.", 
				      $host, $info->{serialnumber}, $othername) ); 
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $self->error,
			      );
		return 0;
	    }
	}
	$devtmp{serialnumber} = $info->{serialnumber};
    }else{
	$self->debug( loglevel => 'LOG_INFO',
		      message  => "%s: Did not return serial number",
		      args     => [$host]);

	# If device exists in DB, and we have a serial number, remove it.
	# Most likely it's being replaced with a different unit

	if ( $device && $device->serialnumber ){
	    $devtmp{serialnumber} = "";
	}
    }
    ###############################################
    # Basic BGP info
    if( defined $info->{bgplocalas} ){
	$self->debug( loglevel => 'LOG_DEBUG',
		      message  => "BGP Local AS is %s", 
		      args     => [$info->{bgplocalas}] );
	
	$devtmp{bgplocalas} = $info->{bgplocalas};
    }
    if( defined $info->{bgpid} ){
	$self->debug( loglevel => 'LOG_DEBUG',
		      message  => "BGP ID is %s", 
		      args     => [$info->{bgpid}] );
	
	$devtmp{bgpid} = $info->{bgpid};
    }
    ###############################################
    #
    # Update/Add Device
    #
    ###############################################
    
    if ( $device ){
	$devtmp{lastupdated} = $self->timestamp;
	unless( $self->update( object => $device, state => \%devtmp ) ) {
	    $self->error( sprintf("%s: Error updating: %s", $host, $self->error) ); 
	    $self->debug( loglevel => 'LOG_ERR',
			  message  => $self->error,
			  );
	    return 0;
	}
    }else{
	# Some Defaults
	# 
	$devtmp{monitored}        = 1;
	$devtmp{snmp_managed}     = 1;
	$devtmp{canautoupdate}    = 1;
	$devtmp{customer_managed} = 0;
	$devtmp{natted}           = 0;
	$devtmp{dateinstalled}    = $self->timestamp;
	my $newdevid;
	unless( $newdevid = $self->insert( table => 'Device', state => \%devtmp ) ) {
	    $self->error( sprintf("%s: Error creating: %s", $host, $self->error) ); 
	    $self->debug( loglevel => 'LOG_ERR',
			  message  => $self->error );
	    return 0;
	}
	$self->debug( loglevel => 'LOG_DEBUG', 
		      message  =>  "%s: Created Device id %s",
		      args     => [$host, $newdevid] );

	$device = Device->retrieve($newdevid);
    }
    
    ##############################################
    # Assign contact lists
    
    foreach my $cl ( @cls ){
	my $dcid;
	unless ( $dcid = $self->insert(table=>"DeviceContacts", 
				       state=>{device=>$device->id, contactlist=>$cl} ) ){
	    $self->error( sprintf("%s: Error creating DeviceContact: %s", $host, $self->error) ); 
	    $self->debug( loglevel => 'LOG_ERR', message  => $self->error );
	    return 0;
	}
	$self->debug( loglevel => 'LOG_DEBUG', 
		      message  =>  "%s: Created DeviceContact id %s",
		      args     => [$host, $dcid] );
    }
		     
    ##############################################
    #
    # for each interface just discovered...
    #
    ##############################################
    
    my (%newips, %dbvlans, %ifvlans, @nonrrs);
    
    my %IFFIELDS = ( number           => "",
		     name             => "",
		     type             => "",
		     description      => "",
		     speed            => "",
		     admin_status     => "",
		     oper_status      => "",
		     admin_duplex     => "",
		     oper_duplex      => "");

    foreach my $newif ( sort { $a <=> $b } keys %{ $info->{interface} } ) {

	############################################
	# set up IF state data
	my( %iftmp, $if );
	$iftmp{device} = $device->id;
	
	foreach my $field ( keys %{ $info->{interface}->{$newif} } ){
	    if (exists $IFFIELDS{$field}){
		$iftmp{$field} = $info->{interface}->{$newif}->{$field};
	    }
	}
	###############################################
	# Update/add PhsyAddr for Interface
	if (defined (my $addr = $info->{interface}->{$newif}->{physaddr})){
	    # Check if it's valid
	    if ( ! $self->validate_phys_addr($addr) ){
		my $msg = sprintf("%s: interface %s: %s is not a valid address", 
				  $host, $iftmp{name}, $addr);
		$self->error($msg);
		$self->debug( loglevel => 'LOG_DEBUG', message => $msg );
	    }	
	    # Look it up
	    if (my $phy = (PhysAddr->search(address => $addr))[0] ){
		#
		# The address exists 
		# Just point to it from this Interface
		#
		$iftmp{physaddr} = $phy->id;
		$self->update( object => $phy, 
			     state => {last_seen => $self->timestamp} );
		$self->debug( loglevel => 'LOG_INFO',
			      message  => "%s: Interface %s,%s has existing PhysAddr %s",
			      args => [$host, $iftmp{number}, $iftmp{name}, $addr],
			      );		
		#
		# address is new.  Add it
		#
	    }else{
		my %phaddrtmp = ( address    => $addr,
				  first_seen => $self->timestamp,
				  last_seen  => $self->timestamp,
				  );
		my $newphaddr;
		if ( ! ($newphaddr = $self->insert(table => 'PhysAddr', state => \%phaddrtmp)) ){
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => "%s: Could not create PhysAddr %s for Interface %s,%s: %s",
				  args     => [$host, $phaddrtmp{address}, $iftmp{number}, $iftmp{name}, 
					       $self->error],
				  );
		    $iftmp{physaddr} = 0;
		}else{
		    $self->debug( loglevel => 'LOG_INFO',
				  message  => "%s: Added new PhysAddr %s for Interface %s,%s",
				  args => [$host, $phaddrtmp{address}, $iftmp{number}, $iftmp{name}],
				  );		
		    $iftmp{physaddr} = $newphaddr;
		}
	    }
	}
	############################################
	# Add/Update interface
	if ( $if = (Interface->search(device => $device->id, number => $iftmp{number}))[0] ) {
	    delete( $ifs{ $if->id } );

	    # Check if description can be overwritten
	    if ( ! $if->overwrite_descr ){
		delete $iftmp{description};
	    }
	    # Update
	    unless( $self->update( object => $if, state => \%iftmp ) ) {
		my $msg = sprintf("%s: Could not update Interface %s,%s: ", 
				  $host, $iftmp{number}, $iftmp{name}, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }
	} else {
	    # Interface does not exist.  Add it.
	    
	    # Set some defaults
	    $iftmp{speed}           ||= 0; #can't be null
	    $iftmp{monitored}       ||= $self->{config}->{IF_MONITORED};
	    $iftmp{snmp_managed}    ||= $self->{config}->{IF_SNMP};
	    $iftmp{overwrite_descr} ||= $self->{config}->{IF_OVERWRITE_DESCR};
	    
	    my $unkn = (MonitorStatus->search(name=>"Unknown"))[0];
	    $iftmp{monitorstatus} = ( $unkn ) ? $unkn->id : 0;
	    
	    if ( ! (my $ifid = $self->insert( table => 'Interface', 
					      state => \%iftmp )) ) {
		my $msg = sprintf("%s: Error inserting Interface %s,%s: %s", 
			       $host, $iftmp{number}, $iftmp{name}, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }else{
		unless( $if = Interface->retrieve($ifid) ) {
		    my $msg = sprintf("%s: Couldn't retrieve Interface id %s", $host, $ifid);
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => $msg );
		    $self->output($msg);
		    next;
		}
		my $msg = sprintf("%s: Inserted Interface %s,%s ", 
				  $host, $iftmp{number}, $iftmp{name} );
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => $msg,
			      );
		$self->output($msg);
	    }
	    
	}
	################################################################
	# Get all stored VLAN memberships (these are join tables);
	#
	map { $dbvlans{$_->id} = '' } $if->vlans();

	##############################################
	# Add/Update VLANs

	foreach my $vid ( keys %{ $info->{interface}->{$newif}->{vlans} } ){
	    my $vname = $info->{interface}->{$newif}->{vlans}->{$vid};
	    my $vo;
	    # look it up
	    unless ($vo = (Vlan->search(vid =>$vid))[0]){
		#create
		if ( ! (my $vobjid = $self->insert(table => "Vlan", state => { vid => $vid, description => $vname } ) ) ) {
		    my $msg = sprintf("%s: Could not insert Vlan %s: %s", 
				      $host, $vo->description, $self->error);
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => $msg,
				  );
		    $self->output($msg);
		    next;
		}else {
		    $vo = Vlan->retrieve($vobjid);
		    my $msg = sprintf("%s: Inserted VLAN %s", $host, $vo->description);
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => $msg,
				  );
		    $self->output($msg);
		    next;
		}
	    }

	    # verify membership
	    #
	    my %ivtmp = ( interface => $if->id, vlan => $vo->id );
	    my $iv;
	    unless ( $iv = (InterfaceVlan->search(\%ivtmp))[0] ){
		unless ( $iv = $self->insert(table => "InterfaceVlan", state => \%ivtmp ) ){
		    my $msg = sprintf("%s: Could not insert InterfaceVlan join %s:%s: %s", 
				      $host, $if->name, $vo->vid, $self->error);
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => $msg,
				  );
		    $self->output($msg);
		}else{
		    my $msg = sprintf("%s: Assigned Interface %s,%s to VLAN %s", 
				      $host, $if->number, $if->name, $vo->description);
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => $msg,
				  );
		}
	    }else {
		my $msg = sprintf("%s: Interface %s,%s already member of vlan %s", 
				  $host, $if->number, $if->name, $vo->vid);
		$self->debug( loglevel => 'LOG_DEBUG',
			      message  => $msg,
			      );
		delete $dbvlans{$iv->id};
	    }
	}

	################################################################
	# Add/Update IPs
	
	if( exists( $info->{interface}->{$newif}->{ips} ) && ! $device->natted ) {	    

	    foreach my $newip ( sort keys %{ $info->{interface}->{$newif}->{ips} } ){
		my( $maskobj, $subnet, $ipdbobj );
		my $version = ($newip =~ /:/) ? 6 : 4; # lame
		my $prefix = ($version == 6) ? 128 : 32;

		########################################################
		# Create subnet if device is a router (ipForwarding true)
		# and addsubnets flag is on

		if ( $info->{router} && $argv->{addsubnets} ){
		    my $newmask;
		    if ( $newmask = $info->{interface}->{$newif}->{ips}->{$newip} ){
			my $subnetaddr = $self->{'_ipm'}->getsubnetaddr($newip, $newmask);
			if ( $subnetaddr ne $newip ){
			    if ( ! ($self->{'_ipm'}->searchblocks_addr($subnetaddr, $newmask)) ){
				my %state = (address     => $subnetaddr, 
					     prefix      => $newmask, 
					     statusname  => "Subnet");
				# Check if subnet should inherit device info
				if ( $argv->{subnets_inherit} ){
				    $state{owner}   = $device->owner;
				    $state{used_by} = $device->used_by;
				}
				unless( $self->{'_ipm'}->insertblock(%state) ){
				    my $msg = sprintf("%s: Could not insert Subnet %s/%s: %s", 
						      $host, $subnetaddr, $newmask, $self->error);
				    $self->debug(loglevel => 'LOG_ERR',
						 message  => $msg );
				}else{
				    my $msg = sprintf("%s: Created Subnet %s/%s", $host, $subnetaddr, $newmask);
				    $self->debug(loglevel => 'LOG_NOTICE',
						 message  => $msg );
				    $self->output($msg);
				}
			    }else{
				my $msg = sprintf("%s: Subnet %s/%s already exists", $host, $subnetaddr, $newmask);
				$self->debug( loglevel => 'LOG_DEBUG',
					      message  => $msg );
			    }
			}else{
			    # do nothing
			    # This is probably a /32 address (loopback interface)
			}
		    }
		}
		# 
		# Keep all discovered ips in a hash
		$newips{$newip} = $if;
		my $ipobj;
		if ( my $ipid = $dbips{$newip} ){
		    #
		    # update
		    my $msg = sprintf("%s: IP %s/%s exists. Updating", $host, $newip, $prefix);
		    $self->debug( loglevel => 'LOG_DEBUG',
				  message  => $msg );
		    delete( $dbips{$newip} );
		    
		    unless( $ipobj = $self->{'_ipm'}->updateblock(id           => $ipid, 
								  statusname   => "Static",
								  interface    => $if->id )){
			my $msg = sprintf("%s: Could not update IP %s/%s: %s", $host, $newip, $prefix, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg );
			$self->output($msg);
			next;
		    }

		}elsif ( $ipobj = $self->{'_ipm'}->searchblocks_addr($newip) ){
		    # IP exists but not linked to this interface
		    # update
		    my $msg = sprintf("%s: IP %s/%s exists but not linked to %s. Updating", 
				      $host, $newip, $prefix, $if->name);
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => $msg );
		    unless( $ipobj = $self->{'_ipm'}->updateblock(id         => $ipobj->id, 
								  statusname => "Static",
								  interface  => $if->id )){
			my $msg = sprintf("%s: Could not update IP %s/%s: %s", 
					  $host, $newip, $prefix, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg );
			next;
		    }
		}else {
		    #
		    # Create a new Ip
		    unless( $ipobj = $self->{'_ipm'}->insertblock(address    => $newip, 
								  prefix     => $prefix, 
								  statusname => "Static",
								  interface  => $if->id)){
			my $msg = sprintf("%s: Could not insert IP %s: %s", 
					  $host, $newip, $self->error);
			$self->debug( loglevel => 'LOG_ERR', message  => $msg );
			next;
		    }else{
			my $msg = sprintf("%s: Inserted IP %s", $host, $newip);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg );
			$self->output($msg);
		    }
		}
	    } # foreach newip
	} #if ips found 
    } #foreach $newif


    ########################################################
    #
    # Create A records for each ip address discovered
    #
    ########################################################
 
    my @devips = $self->getdevips($device);

    # The reason for the reverse order is that most often the lowest
    # address is a virtual address (such as when a router uses VRRP or HSRP)
    # For that virtual address, the user might want to manually assign a custom name.
    # This way, the higher address gets to keep the shorter name (without the 
    # ip address appended)
    # Otherwise, this has no adverse effects

    foreach my $ipobj ( reverse @devips ){

	# Determine what DNS name this IP will have
	my $name = $self->_canonicalize_int_name($ipobj->interface->name);
	if ( $ipobj->interface->ips > 1 
	     ||  $self->{'_dns'}->getrrbyname($name) ){
	    # Interface has more than one ip
	    # or somehow this name is already used.
	    # Append the ip address to the name to make it unique
	    $name .= "-" . $ipobj->address;
	}
	# Append device name
	# Remove any possible prefixes added
	# e.g. loopback0.devicename -> devicename
	my $suffix = $device->name->name;
	$suffix =~ s/^.*\.(.*)/$1/;
	$name .= "." . $suffix ;
	
	my @arecords = $ipobj->arecords;
	if ( ! @arecords  ){
	    
	    ################################################
	    # Is this the only ip in this device,
	    # or is this the address associated with the
	    # hostname?
	    
	    if ( (scalar @devips) == 1 || exists $hostnameips{$ipobj->address} ){
		
		# We should already have an RR created
		# Create the A record to link that RR with this ipobj
		if ( $device->name ){
		    unless ($self->{'_dns'}->insert_a_rr(rr => $device->name, 
							 ip => $ipobj)){
			my $msg = sprintf("%s: Could not insert DNS A record for %s: %s", 
					  $host, $ipobj->address, $self->error);
			$self->debug(loglevel => 'LOG_ERR',
				     message  => $msg );
			$self->output($msg);
		    }else{
			my $msg = sprintf("%s: Inserted DNS A record for %s: %s", 
					  $host, $ipobj->address, $device->name->name);
			$self->debug(loglevel => 'LOG_NOTICE',
				     message  => $msg );
			$self->output($msg);
		    }
		}
	    }else{
		# Insert necessary records
		unless ($self->{'_dns'}->insert_a_rr(name => $name,
						     ip   => $ipobj)){
		    my $msg = sprintf("%s: Could not insert DNS A record for %s: %s", 
				      $host, $ipobj->address, $self->error);
		    $self->debug(loglevel => 'LOG_ERR',
				 message  => $msg );
		    $self->output($msg);
		}else{
		    my $msg = sprintf("%s: Inserted DNS A record for %s: %s", 
				      $host, $ipobj->address, $name);
		    $self->debug(loglevel => 'LOG_NOTICE',
				 message  => $msg );
		    $self->output($msg);
		}
	    }
	}else{ 
	    # "A" records exist.  Update names
	    if ( (scalar @arecords) > 1 ){
		# There's more than one A record for this IP
		# To avoid confusion, don't update and log.
		my $msg = sprintf("%s: IP %s has more than one A record. Will not update name.", 
				  $host, $ipobj->address);
		$self->debug(loglevel => 'LOG_WARNING',
			     message  => $msg );
		$self->output($msg);
	    }else{
		my $rr = $arecords[0]->rr;
		# We won't update the RR that the device name points to
		# Also, don't bother if name hasn't changed
		if ( $rr->id != $device->name->id 
		     && $rr->name ne $name
		     && $rr->auto_update ){
		    unless ( $self->update(object => $rr, state => {name => $name} )){
			my $msg = sprintf("%s: Could not update RR %s: %s", 
					  $host, $rr->name, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg,
				      );
			$self->output($msg);
		    }else{
			my $msg = sprintf("%s: Updated DNS record for %s: %s", 
					  $host, $ipobj->address, $name);
			$self->debug(loglevel => 'LOG_NOTICE',
				     message  => $msg );
			$self->output($msg);
		    }
		}
	    }
	}
    } #foreach $ipobj
    
    
    ##############################################
    #
    # remove each interface that no longer exists
    #
    ##############################################

    ## Do not remove manually-added ports for these hubs
    unless ( exists $info->{sysobjectid} 
	     && exists($self->{config}->{IGNOREPORTS}->{$info->{sysobjectid}} )){
	
	foreach my $nonif ( keys %ifs ) {
	    my $ifobj = $ifs{$nonif};

	    # Get RRs before deleting interface
	    map { push @nonrrs, $_->rr } map { $_->arecords } $ifobj->ips;
	    
	    my $msg = sprintf("%s: Interface %s,%s no longer exists.  Removing.", 
			      $host, $ifobj->number, $ifobj->name);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );
	    $self->output($msg);

	    ##################################################
	    # Notify of orphaned circuits
	    #
	    my @circuits;
	    map { push @circuits, $_ } $ifobj->nearcircuits;
	    map { push @circuits, $_ } $ifobj->farcircuits;

	    if ( @circuits ){
		my $msg = sprintf("%s: You might want to revise the following circuits: %s", $host, 
				  (join ', ', map { $_->cid } @circuits) );
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => $msg,
			      );
		$self->output($msg);
	    }

	    unless( $self->remove( table => "Interface", id => $nonif ) ) {
		my $msg = sprintf("%s: Could not remove Interface %s,%s: %s", 
				  $host, $ifobj->number, $ifobj->name, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }
	}
    }

    ##############################################
    #
    # remove each ip address that no longer exists
    #
    ##############################################
    unless ( $device->natted ){
	foreach my $nonip ( keys %dbips ) {
	    my $msg = sprintf("%s: Removing old IP %s", 
			      $host, $nonip);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );
	    $self->output($msg);		

	    my $ip = Ipblock->retrieve($dbips{$nonip});

	    # Get RRs before deleting object
	    map { push @nonrrs, $_->rr } $ip->arecords;

	    unless( $self->removeblock( id => $ip->id ) ) {
		my $msg = sprintf("%s: Could not remove IP %s: %s", 
				  $host, $nonip, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }
	}
    }

    ##############################################
    #
    # remove old RRs if they no longer have any
    # addresses associated
    #
    ##############################################
    
    foreach my $rr ( @nonrrs ){
	if ( (! $rr->arecords) && ($rr->id != $device->name->id) ){
	    # Assume the name can go
	    # since it has no addresses associated
	    my $msg = sprintf("%s: Removing old RR: %s", 
			      $host, $rr->name );
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );
	    $self->output($msg);		
	    unless( $self->remove( table => "RR",  id => $rr->id ) ) {
		my $msg = sprintf("%s: Could not remove RR %s: %s", 
				  $host, $rr->name, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
	    }
	}
    }

    ##############################################
    #
    # remove each vlan membership that no longer exists
    #
    ##############################################
    
    foreach my $nonvlan ( keys %dbvlans ) {
	my $iv = InterfaceVlan->retrieve($nonvlan);
	my $msg = sprintf("%s: Vlan membership %s:%s no longer exists.  Removing.", 
			  $host, $iv->interface->name, $iv->vlan->vid);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg,
		      );
	unless( $self->remove( table => 'InterfaceVlan', id => $iv->id ) ) {
	    my $msg = sprintf("%s: Could not remove InterfaceVlan %s: %s", 
			      $host, $iv->id, $self->error);
	    $self->debug( loglevel => 'LOG_ERR',
			  message  => $msg,
			  );
	    $self->output($msg);
	    next;
	}
    }

    ###############################################################
    #
    # Add/Delete BGP Peerings
    #
    ###############################################################

    if ( $self->{config}->{ADD_BGP_PEERS} ){

	################################################     
	# Keep a hash of current peerings for this Device
	#
	map { $bgppeers{ $_->id } = '' } $device->bgppeers();
	
	################################################
	# For each discovered peer
	#
	foreach my $peer ( keys %{$info->{bgppeer}} ){
	    my $p; # bgppeering object

	    # Check if peering exists
	    unless ( $p = (BGPPeering->search( device => $device->id,
					       bgppeeraddr => $peer ))[0] ){
		# Doesn't exist.  
		# Check if we have some Entity info
		next unless ( exists ($info->{bgppeer}->{$peer}->{asname}) ||
			      exists ($info->{bgppeer}->{$peer}->{orgname})
			      ); 
		my $ent;
		# Check if Entity exists
		unless ( ( $ent = (Entity->search( asnumber => $info->{bgppeer}->{$peer}->{asnumber}))[0] ) ||  
			 ( $ent = (Entity->search( asname   => $info->{bgppeer}->{$peer}->{asname}))  [0] ) ||  
			 ( $ent = (Entity->search( name     => $info->{bgppeer}->{$peer}->{orgname})) [0] )
			 ){
		    
		    # Doesn't exist. Create Entity
		    my $msg = sprintf("%s: Entity %s (%s) not found. Creating", 
				      $host, $info->{bgppeer}->{$peer}->{orgname}, $info->{bgppeer}->{$peer}->{asname});
		    $self->debug( loglevel => 'LOG_INFO',
				  message  => $msg );
		    my $t;
		    unless ( $t = (EntityType->search(name => "Peer"))[0] ){
			$t = 0; 
		    }
		    my $entname = $info->{bgppeer}->{$peer}->{orgname} || $info->{bgppeer}->{$peer}->{asname} ;
		    $entname .= "($info->{bgppeer}->{$peer}->{asnumber})";

		    if ( my $entid = $self->insert(table => 'Entity', 
						   state => { name     => $entname,
							      asname   => $info->{bgppeer}->{$peer}->{asname},
							      asnumber => $info->{bgppeer}->{$peer}->{asnumber},
							      type => $t }) ){
			my $msg = sprintf("%s: Created Peer Entity: %s. ", $host, $entname);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg );		
			$ent = Entity->retrieve($entid);
		    }else{
			my $msg = sprintf("%s: Could not create new Entity: %s: %s", 
					  $host, $entname, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg,
				      );
			$self->output($msg);
			$ent = 0;
		    }
		}

		# Create Peering
		if ( $ent ){
		    my %ptmp = (device      => $device,
				entity      => $ent,
				bgppeerid   => $info->{bgppeer}->{$peer}->{bgppeerid},
				bgppeeraddr => $peer,
				monitored     => 1,
				);
		    if ( ($p = $self->insert(table => 'BGPPeering', 
					     state => \%ptmp ) ) ){
			my $msg = sprintf("%s: Created Peering with: %s. ", $host, $ent->name);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg );
			$self->output($msg);
		    }else{
			my $msg = sprintf("%s: Could not create Peering with : %s: %s",
					  $host, $ent->name, $self->error );
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg,
				      );
		    }
		}
	    }else{
		# Peering Exists.  Delete from list
		delete $bgppeers{$p->id};
	    }
	}
	
	##############################################
	# remove each BGP Peering that no longer exists
	
	foreach my $nonpeer ( keys %bgppeers ) {
	    my $p = BGPPeering->retrieve($nonpeer);
	    my $msg = sprintf("%s: BGP Peering with %s (%s) no longer exists.  Removing.", 
			      $host, $p->entity->name, $p->bgppeeraddr);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );
	    $self->output($msg);		
	    unless( $self->remove( table => 'BGPPeering', id => $nonpeer ) ) {
		my $msg = sprintf("%s, Could not remove BGPPeering %s: %s", 
				  $host, $p->id, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }
	}

    } # endif ADD_BGP_PEERS
    
    # END 

    my $msg = sprintf("Discovery of %s completed", $host);
    $self->debug( loglevel => 'LOG_NOTICE', message  => $msg );
    return $device;
}

sub get_dev_info {
    my ($self, %argv) = @_;
    my ($host, $comstr, $version, $timeout, $retries) = ($argv{host}, $argv{comstr}, 
							 $argv{version}, $argv{timeout}, 
							 $argv{retries});
    $self->_clear_output();
    
    my %sinfoargs = ( AutoSpecify => 1,
		      Debug       => 0,
		      DestHost    => $host,
		      Community   => $comstr  || $self->{config}->{'DEFAULT_SNMPCOMMUNITY'},
		      Version     => $version || $self->{config}->{'DEFAULT_SNMPVERSION'},
		      timeout     => (defined $timeout) ? $timeout : $self->{config}->{'DEFAULT_SNMPTIMEOUT'},
		      retries     => (defined $retries) ? $retries : $self->{config}->{'DEFAULT_SNMPRETRIES'},
		      );

    my $sinfo;
    unless ( $sinfo = SNMP::Info->new(%sinfoargs) ){ 
	$self->error("Can't connect to $host with community $comstr");
	return 0; 
    }
    
    if ( my $err = $sinfo->error ){
	$self->error("Error connecting to $host: $err");
	return 0;
    }
    $self->debug(loglevel => 'LOG_NOTICE', message => "Contacted $host" );

    my $class = $sinfo->class();
    $self->debug(loglevel => 'LOG_DEBUG', message => "$host SNMP::Info class: $class" );

    # I want to do my own munging for certain things
    my $munge = $sinfo->munge();
    delete $munge->{'i_speed'}; # I store these as integers in the db.  Munge at display
    $munge->{'i_mac'} = sub{ return $self->_readablehex(@_) };
    $munge->{'mac'}   = sub{ return $self->_readablehex(@_) };

    my %dev;

    ################################################################
    # SNMP::Info methods that return hash refs
    my @SMETHODS = ( 'e_descr',
		     'interfaces', 'i_type', 'i_description', 'i_speed', 'i_up', 'i_up_admin', 'i_duplex', 
		     'ip_index', 'ip_netmask', 'i_mac',
		     'i_vlan', 'qb_v_name', 'hp_v_name', 'v_name',
		     'bgp_peers', 'bgp_peer_id', 'bgp_peer_as');
    my %hashes;
    foreach my $method ( @SMETHODS ){
	$hashes{$method} = $sinfo->$method;
    }

    ################################################################
    # Device's global vars
    $dev{sysobjectid} = $sinfo->id;
    $dev{sysobjectid} =~ s/^\.(.*)/$1/;  #Remove unwanted first dot

    if ( exists($self->{config}->{IGNOREDEVS}->{$dev{sysobjectid}} ) ){
	my $msg = sprintf("Product id %s set to be ignored", $dev{sysobjectid});
	$self->error($msg);
	$self->debug( loglevel => 'LOG_NOTICE', message => $msg );
	return 0;
    }

    $dev{enterprise}     = $dev{sysobjectid};
    $dev{enterprise}     =~ s/(1\.3\.6\.1\.4\.1\.\d+).*/$1/;
    $dev{model}          = $sinfo->model();
    $dev{os}             = $sinfo->os_ver();
    $dev{physaddr}       = $sinfo->mac();
    # Check if it's valid
    if ( ! $self->validate_phys_addr($dev{physaddr}) ){
	my $msg = sprintf("%s has invalid MAC: %s", $host, $dev{physaddr});
	$self->debug( loglevel => 'LOG_DEBUG', message => $msg );
	delete $dev{physaddr};
    }	
    $dev{sysname}        = $sinfo->name();
    $dev{sysdescription} = $sinfo->description();
    $dev{syscontact}     = $sinfo->contact();
    $dev{syslocation}    = $sinfo->location();
    $dev{productname}    = $hashes{'e_descr'}->{1};
    $dev{manufacturer}   = $sinfo->vendor();
    $dev{serialnumber}   = $sinfo->serial();
    $dev{router}         = ($sinfo->ipforwarding eq 'forwarding') ? 1 : 0;
    if ( $dev{router} ){
	$dev{bgplocalas} =  $sinfo->bgp_local_as();
	$dev{bgpid}      =  $sinfo->bgp_id();
    }
#    $dev{dot11} = 1 if ();
    $dev{hub} = 1 if ( $class =~ /Layer1/ );

    ################################################################
    # Interface stuff
    
    # Netdot Interface field name to SNMP::Info method conversion table
    my %IFFIELDS = ( name            => "interfaces",
		     type            => "i_type",
		     description     => "i_descr",
		     speed           => "i_speed",
		     admin_status    => "i_up",
		     oper_status     => "i_up_admin", 
		     physaddr        => "i_mac", 
		     oper_duplex     => "i_duplex",
		     admin_duplex    => "i_duplex_admin",
		     );
    
    ##############################################
    # for each interface discovered...
    foreach my $iid (sort { $a <=> $b } keys %{ $hashes{interfaces} } ){
	# check whether it should be ignored
	if ( defined $self->{config}->{IFRESERVED} ){
	    my $name    = $hashes{interfaces}->{$iid};
	    my $ignored = $self->{config}->{IFRESERVED};
	    if ( $name =~ /$ignored/i ){
		$self->debug( loglevel => 'LOG_DEBUG', 
			      message  =>  "Ignoring interface %s",
			      args     => [$name] );
		next;
	    }
	}
	# Store values in our info hash
	$dev{interface}{$iid}{number} = $iid;
	foreach my $field ( keys %IFFIELDS ){
	    $dev{interface}{$iid}{$field} = $hashes{$IFFIELDS{$field}}->{$iid} 
	    if ( defined($hashes{$IFFIELDS{$field}}->{$iid}) && 
		 $hashes{$IFFIELDS{$field}}->{$iid} =~ /\w+/ );
	}
	# Check if physaddr is valid
	my $physaddr = $dev{interface}{$iid}{physaddr};
	if ( ! $self->validate_phys_addr($physaddr) ){
	    my $msg = sprintf("Int %s has invalid MAC: %s", $iid, $physaddr);
	    $self->debug( loglevel => 'LOG_DEBUG', message => $msg );
	    delete $dev{interface}{$iid}{physaddr};
	}	
	# IP addresses and masks 
	# (mask is the value for each ip address key)
	foreach my $ip ( keys %{ $hashes{'ip_index'} } ){
	    $dev{interface}{$iid}{ips}{$ip} = $hashes{'ip_netmask'}->{$ip} 
	    if ($hashes{'ip_index'}->{$ip} eq $iid);
	}
  
	################################################################
	# Vlan info
	my ($vid, $vname);
	# Fix this in SNMP::Info.  Should provide standard method for 
	# the VLAN name as well (v_name)
	if ( $vid = $hashes{'i_vlan'}->{$iid} ){
	    $vname = $hashes{'qb_v_name'}->{$iid} || # Standard MIB
		$hashes{'hp_v_name'}->{$iid}      || # HP MIB
		$hashes{'v_name'}->{$iid}         || # Cisco et al.
		$vid;                                # Just use the ID as name
	    $dev{interface}{$iid}{vlans}{$vid} = $vname;
	}
    }
    
    if ( $self->{config}->{ADD_BGP_PEERS} ){

	##############################################
	# for each BGP Peer discovered...
	my %qcache;  #Cache queries for the same AS

	foreach my $peer ( keys %{ $hashes{'bgp_peers'} } ) {
	    $dev{bgppeer}{$peer}{bgppeerid} = $hashes{'bgp_peer_id'}->{$peer};
	    my $asn = $hashes{'bgp_peer_as'}->{$peer};
	    $dev{bgppeer}{$peer}{asnumber}  = $asn;
	    $dev{bgppeer}{$peer}{asname}    = "AS $asn";
	    $dev{bgppeer}{$peer}{orgname}   = "AS $asn";
	    
	    if ( $self->{config}->{DO_WHOISQ} ){
		# Query any configured WHOIS servers for more info about this AS
		# But first check if ithas been found already
		if ( exists $qcache{$asn} ){
		    foreach my $key ( keys %{$qcache{$asn}} ){
			$dev{bgppeer}{$peer}{$key} = $qcache{$asn}{$key};
		    }
		}else{
		    foreach my $server ( keys %{$self->{config}->{WHOISQ}} ){
			my $cmd = "whois -h $server AS$asn";
			$self->debug(loglevel =>'LOG_DEBUG',
				     message  =>"Querying: $cmd");
			my @lines = `$cmd`;
			if ( grep /No.*found/i, @lines ){
			    $self->debug(loglevel =>'LOG_DEBUG',
					 message  =>"$server: AS$asn not found");
			}else{
			    foreach my $key ( keys %{$self->{config}->{WHOISQ}->{$server}} ){
				my $exp = $self->{config}->{WHOISQ}->{$server}->{$key};
				if ( my @l = grep /^$exp/, @lines ){
				    my (undef, $val) = split /:\s+/, $l[0]; #first line
				    $val =~ s/\s*$//;
				    $self->debug(loglevel =>'LOG_DEBUG',
						 message  =>"$server: Found $exp: $val");
				    $qcache{$asn}{$key} = $val;
				    $dev{bgppeer}{$peer}{$key} = $val;
				}
			    }
			    last;
			}
		    }
		}
	    }
	}
    }
    
    return \%dev;
}


=head2 getdevips  - Get all IP addresses configured in a device
   
  Arguments:
    id of the device
    sort field
  Returns:
    array of Ipblock objects

=cut

sub getdevips {
    my ($self, $id, $ipsort) = @_;
    my @ips;
    $ipsort ||= "address";
    if ( $ipsort eq "address" ){
	if ( @ips = Ipblock->search_devipsbyaddr( $id ) ){
	    return @ips;
	}
    }elsif ( $ipsort eq "interface" ){
	if ( @ips = Ipblock->search_devipsbyint( $id ) ){
	    return @ips;
	}
    }else{
	$self->error("invalid sort criteria: $ipsort");
	return;
    }
    return;
}

=head2 getdevsubnets  - Get all the subnets in which a given device has any addresses
   
  Arguments:
    id of the device
  Returns:
    hash of Ipblock objects, keyed by id

=cut

sub getdevsubnets {
    my ($self, $id) = @_;
    my %subnets;
    foreach my $ip ( $self->getdevips($id) ){
	my $subnet;
	if ( ($subnet = $ip->parent) && 
	     $subnet->status->name eq "Subnet"){
	    $subnets{$subnet->id} = $subnet;
	}
    }
    return %subnets;
}

=head2 getproductsbytype  - Get all products of given type
   
  Arguments:
    id of ProductType
    if id is 0, return products with no type set
  Returns:
    array of Product objects

=cut

sub getproductsbytype {
    my ($self, $id) = @_;
    my @objs;
    if ( $id ){
	if ( @objs = Product->search_bytype( $id ) ){
	    return @objs;
	}
    }else{
	if ( @objs = Product->search_notype() ){
	    return @objs;
	}
    }
    return;
}

=head2 getdevsbytype  - Get all devices of given type
   
  Arguments:
    id of ProductType
    if id is 0, return products with no type set
  Returns:
    array of Device objects

=cut

sub getdevsbytype {
    my ($self, $id) = @_;
    my @objs;
    if ( $id ){
	if ( @objs = Device->search_bytype( $id ) ){
	    return @objs;
	}
    }
    return;
}

=head2 add_interfaces - Manually add a number of interfaces to an existing device

The new interfaces will be added with numbers starting after the highest existing 
interface number

Arguments:
    Device id
    Number of interfaces
Returns:
    True or False

=cut

sub add_interfaces {
    my ($self, $id, $num) = @_;
    unless ( $num > 0 ){
	$self->error("Invalid number of Interfaces to add: $num");
	return 0;
    }
    # Determine highest numbered interface in this device
    my $device;
    unless ( $device =  Device->retrieve($id) ){
	$self->error("add_interfaces: Could not retrieve Device id $id");
    }
    my @ints;
    my $start;
    if ( scalar ( @ints = sort { $b->number <=> $a->number } $device->interfaces ) ){
	$start = int ( $ints[0]->number );
    }else{
	$start = 0;
    }
    my %tmp = ( device => $id, number => $start);
    my $i;
    for ($i = 0; $i < $num; $i++){
	$tmp{number}++;
	if (!($self->insert(table => "Interface", state => \%tmp)) ){
	    $self->error(sprintf("add_interfaces: %s", $self->error));
	    return 0;
	}
    }
    return 1;
}

=head2 ints_by_number - Retrieve interfaces from a Device and sort by number.  
                              Handles the case of port numbers with dots (hubs)

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub ints_by_number {
    my ( $self, $o ) = @_;
    my @ifs;
    unless ( @ifs = $o->interfaces() ){
	return ;
    }
    # Add a fake '.0' after numbers with no dots, and then
    # split in two and sort first part and then second part
    # (i.e: 1.10 goes after 1.2)
    my @tmp;
    foreach my $if ( @ifs ) {
	my $num = $if->number;
	if ($num !~ /\./ ){
	    $num .= '.0';
	}
	push @tmp, [(split /\./, $num), $if];
    }	
    @ifs = map { $_->[2] } sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @tmp;

    return unless scalar @ifs;
    return @ifs;
}

=head2 ints_by_name - Retrieve interfaces from a Device and sort by name.  

This method deals with the problem of sorting Interface names that contain numbers.
Simple alphabetical sorting does not yield useful results.

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub ints_by_name {
    my ( $self, $o ) = @_;
    my @ifs = $o->interfaces;
    
    # The following was borrowed from Netviewer
    # and was slightly modified to handle Netdot Interface objects.
    @ifs = ( map { $_->[0] } sort { 
	       $a->[1] cmp $b->[1]
	    || $a->[2] <=> $b->[2]
	    || $a->[3] <=> $b->[3]
	    || $a->[4] <=> $b->[4]
	    || $a->[5] <=> $b->[5]
	    || $a->[6] <=> $b->[6]
	    || $a->[7] <=> $b->[7]
	    || $a->[8] <=> $b->[8]
	    || $a->[0]->name cmp $b->[0]->name }  
	     map{ [ $_, $_->name =~ /^([^\d]+)\d/, 
		    ( split( /[^\d]+/, $_->name ))[0,1,2,3,4,5,6,7,8] ] } @ifs);
    
    return unless scalar @ifs;
    return @ifs;

}

=head2 ints_by_speed - Retrieve interfaces from a Device and sort by speed.  

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub ints_by_speed {
    my ( $self, $o ) = @_;
    my $id = $o->id;
    my @ifs = Interface->search( device => $id, {order_by => 'speed'});

    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_vlan - Retrieve interfaces from a Device and sort by vlan ID

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

Note: If the interface has/belongs to more than one vlan, sort function will only
use one of the values.

=cut

sub ints_by_vlan {
    my ( $self, $o ) = @_;
    my @ifs;
    unless ( @ifs = $o->interfaces() ){
	return ;
    }
    my @tmp = map { [ ($_->vlans) ? ($_->vlans)[0]->vlan->vid : 0, $_] } @ifs;
	
    @ifs = map { $_->[1] } sort { $a->[0] <=> $b->[0] } @tmp;

    return unless scalar @ifs;
    return @ifs;
}

sub ints_by_jack {
    my ( $self, $o ) = @_;
    my @ifs;
    unless ( @ifs = $o->interfaces() ){
	return ;
    }
    my @tmp = map { [ ($_->jack) ? $_->jack->jackid : 0, $_] } @ifs;
	
    @ifs = map { $_->[1] } sort { $a->[0] cmp $b->[0] } @tmp;

    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_descr - Retrieve interfaces from a Device and sort by description

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub ints_by_descr {
    my ( $self, $o ) = @_;
    my $id = $o->id;
    my @ifs = Interface->search( device => $id, {order_by => 'description'});

    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_monitored - Retrieve interfaces from a Device and sort by 'monitored' field

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub ints_by_monitored {
    my ( $self, $o ) = @_;
    my $id = $o->id;
    my @ifs = Interface->search( device => $id, {order_by => 'monitored DESC'});

    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_snmp - Retrieve interfaces from a Device and sort by 'snmp_managed' field

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub ints_by_snmp {
    my ( $self, $o ) = @_;
    my $id = $o->id;
    my @ifs = Interface->search( device => $id, {order_by => 'snmp_managed DESC'});

    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_jack - Retrieve interfaces from a Device and sort by Jack id

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

=head2 get_interfaces - Wrapper function to retrieve interfaces from a Device

Will call different methods depending on the sort field specified

Arguments:  Device object, sort field: [number|name|speed|vlan|jack|descr|monitored|snmp]
Returns:    Sorted array of interface objects or undef if error.

=cut

sub get_interfaces {
    my ( $self, $o, $sortby ) = @_;
    unless ( ref($o) eq "Device" ){
	self->error("get_interfaces: First parameter must be a Device object");
	return;
    }
    my @ifs;

    if ( $sortby eq "number" ){
	@ifs = $self->ints_by_number($o);
    }elsif ( $sortby eq "name" ){
	@ifs = $self->ints_by_name($o);
    }elsif( $sortby eq "speed" ){
	@ifs = $self->ints_by_speed($o);
    }elsif( $sortby eq "vlan" ){
	@ifs = $self->ints_by_vlan($o);
    }elsif( $sortby eq "jack" ){
	@ifs = $self->ints_by_jack($o);
    }elsif( $sortby eq "descr"){
	@ifs = $self->ints_by_descr($o);
    }elsif( $sortby eq "monitored"){
	@ifs = $self->ints_by_monitored($o);
    }elsif( $sortby eq "snmp"){
	@ifs = $self->ints_by_snmp($o);
    }else{
	$self->error("get_interfaces: Unknown sort field: $sortby");
	return;
    }

    return unless scalar @ifs;
    return @ifs;
}

=head2 bgppeers_by_ip - Sort by remote IP

Arguments:  Array ref of BGPPeering objects
Returns:    Sorted array of BGPPeering objects or undef if error.

=cut

sub bgppeers_by_ip {
    my ( $self, $peers ) = @_;

    my @peers = map { $_->[1] } 
    sort ( { pack("C4"=>$a->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) 
		 cmp pack("C4"=>$b->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/); }  
	   map { [$_->bgppeeraddr, $_] } @$peers );
 
    wantarray ? ( @peers ) : $peers[0]; 
}

=head2 bgppeers_by_id - Sort by BGP ID

Arguments:  Array ref of BGPPeering objects
Returns:    Sorted array of BGPPeering objects or undef if error.

=cut

sub bgppeers_by_id {
    my ( $self, $peers ) = @_;

    my @peers = map { $_->[1] } 
    sort ( { pack("C4"=>$a->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) 
		 cmp pack("C4"=>$b->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/); }  
	   map { [$_->bgppeerid, $_] } @$peers );
    
    wantarray ? ( @peers ) : $peers[0]; 
}

=head2 bgppeers_by_entity - Sort by Entity name, AS number or AS Name

Arguments:  
    Array ref of BGPPeering objects, 
    Entity table field to sort by [name|asnumber|asname]
Returns:    Sorted array of BGPPeering objects or undef if error.

=cut

sub bgppeers_by_entity {
    my ( $self, $peers, $sort ) = @_;
    $sort ||= "name";
    unless ( $sort =~ /name|asnumber|asname/ ){
	$self->error("Invalid Entity field: $sort");
	return;
    }
    my $sortsub = ($sort eq "asnumber") ? sub{$a->entity->$sort <=> $b->entity->$sort} : sub{$a->entity->$sort cmp $b->entity->$sort};
    my @peers = sort $sortsub @$peers;
    
    wantarray ? ( @peers ) : $peers[0]; 

}


=head2 get_bgp_peers - Retrieve BGP peers that match certain criteria and sort them

    my @localpeers = $dm->get_bgpeers(device=>$o, type=>1, sort=>"name");

Arguments:  (Hash ref)
  device:   Device object (required)
  entity:   Return peers whose entity name matches 'entity'
  id:       Return peers whose ID matches 'id'
  ip:       Return peers whose Remote IP  matches 'ip'
  as:       Return peers whose AS matches 'as'
  type      Return peers of type [internal|external|all]
  sort:     [entity|asnumber|asname|id|ip]
  
Returns:    Sorted array of BGPPeering objects, undef if none found or if error.

=cut

sub get_bgp_peers {
    my ( $self, %args ) = @_;
    unless ( $args{device} || ref($args{device}) ne "Device" ){
	$self->error("get_bgp_peers: Device object required");
	return;
    }
    my $o = $args{device};
    $args{type} ||= "all";
    $args{sort} ||= "entity";
    my @peers;
    if ( $args{entity} ){
	@peers = grep { $_->entity->name eq $args{entity} } $o->bgppeers;
    }elsif ( $args{id} ){
	@peers = grep { $_->bgppeerid eq $args{id} } $o->bgppeers;	
    }elsif ( $args{ip} ){
	@peers = grep { $_->bgppeeraddr eq $args{id} } $o->bgppeers;	
    }elsif ( $args{as} ){
	@peers = grep { $_->asnumber eq $args{as} } $o->bgppeers;	
    }elsif ( $args{type} ){
	if ( $args{type} eq "internal" ){
	    @peers = grep { $_->entity->asnumber == $o->bgplocalas } $o->bgppeers;
	}elsif ( $args{type} eq "external" ){
	    @peers = grep { $_->entity->asnumber != $o->bgplocalas } $o->bgppeers;
	}elsif ( $args{type} eq "all" ){
	    @peers = $o->bgppeers;
	}else{
	    $self->error("get_bgp_peers: Invalid type: $args{type}");
	    return;
	}
    }elsif ( ! $args{sort} ){
	$self->error("get_bgp_peers: Missing or invalid search criteria");
	return;
    }
    if ( $args{sort} =~ /entity|asnumber|asname/ ){
	$args{sort} =~ s/entity/name/;
	return $self->bgppeers_by_entity(\@peers, $args{sort});
    }elsif( $args{sort} eq "ip" ){
	return $self->bgppeers_by_ip(\@peers);
    }elsif( $args{sort} eq "id" ){
	return $self->bgppeers_by_id(\@peers);
    }else{
	$self->error("get_bgp_peers: Invalid sort argument: $args{sort}");
	return;
    }
}


=head2 convert_ifspeed - Convert ifSpeed to something more readable


Arguments:  ifSpeed value (integer)
Returns:    Human readable speed string or n/a

=cut

sub convert_ifspeed {
    my ($self, $speed) = @_;
    
    my %SPEED_MAP = ('56000'       => '56 kbps',
		     '64000'       => '64 kbps',
		     '1500000'     => '1.5 Mbps',
		     '1536000'     => 'T1',      
		     '1544000'     => 'T1',
		     '2000000'     => '2.0 Mbps',
		     '2048000'     => '2.048 Mbps',
		     '3072000'     => 'Dual T1',
		     '3088000'     => 'Dual T1',   
		     '4000000'     => '4.0 Mbps',
		     '10000000'    => '10 Mbps',
		     '11000000'    => '11 Mbps',
		     '20000000'    => '20 Mbps',
		     '16000000'    => '16 Mbps',
		     '16777216'    => '16 Mbps',
		     '44210000'    => 'T3',
		     '44736000'    => 'T3',
		     '45000000'    => '45 Mbps',
		     '45045000'    => 'DS3',
		     '46359642'    => 'DS3',
		     '54000000'    => '54 Mbps',
		     '64000000'    => '64 Mbps',
		     '100000000'   => '100 Mbps',
		     '149760000'   => 'ATM on OC-3',
		     '155000000'   => 'OC-3',
		     '155519000'   => 'OC-3',
		     '155520000'   => 'OC-3',
		     '400000000'   => '400 Mbps',
		     '599040000'   => 'ATM on OC-12', 
		     '622000000'   => 'OC-12',
		     '622080000'   => 'OC-12',
		     '1000000000'  => '1 Gbps',
		     '10000000000' => '10 Gbps',
		     );
    if ( exists $SPEED_MAP{$speed} ){
	return $SPEED_MAP{$speed};
    }else{
	return "n/a";
    }
}

#####################################################################
# Private methods
#####################################################################

#####################################################################
# Compare Quad IP addresses
# 
# Assumes ddd.ddd.ddd.ddd format. "borrowed" from
# http://www.sysarch.com/perl/sort_paper.html
#####################################################################
#sub _compare_ip($self){
#    pack("C4"=>$a =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) cmp pack("C4"=>$b =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/);
#}

#####################################################################
# Clear output buffer
#####################################################################
sub _clear_output {
    my $self = shift;
    $self->{'_output'} = undef;
}

#####################################################################
# Convert hex values returned from SNMP into a readable string
#####################################################################
sub _readablehex {
    my ($self, $v) = @_;
    return uc( sprintf('%s', unpack('H*', $v)) );
}

#####################################################################
# Canonicalize Interface Name (for DNS)
#####################################################################
sub _canonicalize_int_name {
    my ($self, $name) = @_;

    my %ABBR = % {$self->{config}->{IF_DNS_ABBR} };
    foreach my $ab (keys %ABBR){
	$name =~ s/^$ab/$ABBR{$ab}/i;
    }
    $name =~ s/\/|\.|\s+/-/g;
    return lc( $name );
}
