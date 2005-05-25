package Netdot::DeviceManager;

=head1 NAME

Netdot::DeviceManager - Device-related Functions for Netdot

=head1 SYNOPSIS

  use Netdot::DeviceManager

  $dm = Netdot::DeviceManager->new();  

    # See if device exists
    my ($c, $d) = $dm->find_dev($host);
    
    # Fetch SNMP info
    my $dev = $dm->get_dev_info($host, $comstr);
    
    # Update database
    $o = $dm->update_device(%argv);

=cut

use lib "PREFIX/lib";
use Data::Dumper;

use lib "NVPREFIX/lib";
use NetViewer::RRD::SNMP::NV;

use base qw( Netdot::IPManager Netdot::DNSManager );
use strict;

#Be sure to return 1
1;

=head1 METHODS

=head2 new - Create a new DeviceManager object
 
    $dm = Netdot::DeviceManager->new(logfacility   => $logfacility,
				     snmpversion   => $version,
				     community     => $comstr,
				     retries       => $retries,
				     timeout       => $timeout,
				     );

=cut

sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    
    $self = $self->SUPER::new( %argv );

    $self->{'_snmpversion'}   = $argv{'snmpversion'}   || $self->{config}->{'DEFAULT_SNMPVERSION'};
    $self->{'_snmpcommunity'} = $argv{'community'}     || $self->{config}->{'DEFAULT_SNMPCOMMUNITY'};
    $self->{'_snmpretries'}   = $argv{'retries'}       || $self->{config}->{'DEFAULT_SNMPRETRIES'};
    $self->{'_snmptimeout'}   = $argv{'timeout'}       || $self->{config}->{'DEFAULT_SNMPTIMEOUT'};

    $self->{nv} = NetViewer::RRD::SNMP::NV->new(aliases     => "PREFIX/etc/categories",
						snmpversion => $self->{'_snmpversion'},
						community   => $self->{'_snmpcommunity'},
						retries     => $self->{'_snmpretries'},
						timeout     => $self->{'_snmptimeout'},
						);
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

    my ($c, $d) = $dm->find_dev($host);

=cut

sub find_dev {
    my ($self, $host) = @_;
    my ($device, $comstr);
    $self->error(undef);
    $self->_clear_output();

    if ($device = $self->getdevbyname($host)){
	my $msg = sprintf("Device %s exists in DB.  Will try to update.", $host);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg );
	$self->output($msg);
	$comstr = $device->community;
	$self->debug( loglevel => 'LOG_DEBUG',
		      message  => "Device has community: %s",
		      args     => [$comstr] );
    }elsif($self->getrrbyname($host)){
	my $msg = sprintf("Name %s exists but Device not in DB.  Will try to create.", $host);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg );
	$self->output($msg);
    }elsif(my $ip = $self->searchblock($host)){
	if ( $ip->interface && ($device = $ip->interface->device) ){
	    my $msg = sprintf("Device with address %s exists in DB. Will try to update.", $ip->address);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg );
	    $self->output($msg);
	    $comstr = $device->community;
	    $self->debug( loglevel => 'LOG_DEBUG',
			  message  => "Device has community: %s",
			  args     => [$comstr] );
	}else{
	    my $msg = sprintf("Address %s exists but Device not in DB.  Will try to create.", $host);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg );
	    $self->output($msg);
	    $self->output();
	}
    }else{
	$self->output(sprintf("Device %s not in DB.  Will try to create.", $host));
    }
    return ($comstr, $device);
}

=head2 update_device - Insert new Device/Update Device in Database

 This method can be called from Netdot s web components or 
 from independent scripts.  Should be able to update existing 
 devices or create new ones

  Required Args:
    host:   Name or ip address of host
    dev:    Hashref of device information
  Optional Args:
    comstr: SNMP community string (default "public")
    device: Existing 'Device' object 
  Returns:
    Device object


=cut

sub update_device {
    my ($self, %argv) = @_;
    my ($host, $comstr, %dev);
    $self->_clear_output();

    unless ( ($host = $argv{host}) && (%dev = %{$argv{dev}}) ){
	$self->error( sprintf("Missing required arguments") );
	$self->debug(loglevel => 'LOG_ERR',
		     message => $self->error);
	return 0;
    }
    my $device = $argv{device} || "";
    $argv{entity}              ||= 0;
    $argv{site}                ||= 0;

    my $default_contactlist;
    my $default_contactlist_id;
    if ( $default_contactlist = (ContactList->search(name=>$self->{config}->{DEFAULT_CONTACTLIST}))[0] ){
	$default_contactlist_id = $default_contactlist->id;
    }else{
	$default_contactlist_id = 0;
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => "Default Conctact List not found: %s",
		      args     => [$self->{config}->{DEFAULT_CONTACTLIST}] );
    }
    $argv{contactlist}         ||= $default_contactlist_id;

    my %devtmp;
    $devtmp{sysdescription} = $dev{sysdescription} || "";
    $devtmp{community}      = $argv{comstr}        || "";

    my %ifs;
    my %dbifdeps;
    my %bgppeers;

    if ( $device ){
	################################################     
	# Keep a hash of stored Interfaces for this Device
	map { $ifs{ $_->id } = $_ } $device->interfaces();
	
	# 
	# Get all stored interface dependencies, associate with ip
	# 

	foreach my $ifid (keys %ifs){
	    my $if = $ifs{$ifid};
	    foreach my $dep ( $if->parents() ){		
		unless ( $dep->parent->device ){
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => "Interface %s,%s has invalid parent %s. Removing.",
				  args => [$if->number, $if->name, $dep->parent] );
		    $self->remove(table=>"InterfaceDep", id => $dep->parent);
		    next;
		}
		foreach my $ip ( $if->ips() ){
		    $dbifdeps{$if->id}{$ip->address} = $dep;
		    $self->debug( loglevel => 'LOG_DEBUG',
				  message  => "Interface %s,%s with ip %s has parent %s:%s",
				  args => [$if->number, $if->name, $ip->address, 
					   $dep->parent->device->name->name, 
					   $dep->parent->name] );
		}
	    }
	    foreach my $dep ( $if->children() ){
		unless ( $dep->child->device ){
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => "Interface %s,%s has invalid child %s. Removing.",
				  args => [$if->number, $if->name,$dep->child] );
		    $self->remove(table=>"InterfaceDep", id => $dep->child);
		    next;
		}
		foreach my $ip ( $if->ips() ){
		    $dbifdeps{$if->id}{$ip->address} = $dep;
		    $self->debug( loglevel => 'LOG_DEBUG',
				  message  => "Interface %s,%s with ip %s has child %s:%s",
				  args => [$if->number, $if->name, $ip->address, 
					   $dep->child->device->name->name, 
					   $dep->child->name] );
		}
	    }
	}

	$devtmp{entity}      = $device->entity;
	$devtmp{site}        = $device->site;
	$devtmp{contactlist} = $device->contactlist;

    }else{
	$devtmp{entity}      = $argv{entity};
	$devtmp{site}        = $argv{site};
	$devtmp{contactlist} = $argv{contactlist};
    }

    ##############################################
    # Make sure name is in DNS

    my $rr;
    if ( $rr = $self->getrrbyname($host) ) {
	my $msg = sprintf("Name %s exists in DB. Pointing to it", $host);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg);
	$devtmp{name} = $rr;
    }elsif($device && $device->name && $device->name->name){
	my $msg = sprintf("Device %s exists in DB as %s. Keeping existing name", $host, $device->name->name);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg);
	$self->output($msg);
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
	if ($rr = $self->insert_rr(name        => $host, 
				   contactlist => $devtmp{contactlist})){

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
    if (my @addrs = $self->resolve_name($rr->name)){
	map { $hostnameips{$_} = "" } @addrs;
	
	my $msg = sprintf("Addresses associated with hostname: %s", (join ", ", keys %hostnameips) );
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

    if( $dev{sysobjectid} ){
	if ( my $prod = (Product->search( sysobjectid => $dev{sysobjectid} ))[0] ) {
	    my $msg = sprintf("SysID matches existing %s", $prod->name);
	    $self->debug( loglevel => 'LOG_INFO',message  => $msg );
	    $devtmp{productname} = $prod->id;
	    
	}else{
	    ###############################################
	    # Create a new product entry
	    my $msg = sprintf("New product with SysID %s.  Adding to DB", $dev{sysobjectid});
	    $self->debug( loglevel => 'LOG_INFO', message  => $msg );
	    $self->output( $msg );	
	    
	    ###############################################
	    # Check if Manufacturer Entity exists or can be added
	    
	    my $oid = $dev{enterprise};
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
		my $entname = $dev{manufacturer} || $oid;
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
		if ( $dev{router} ){
		    $type = (ProductType->search(name=>"Router"))[0];
		}elsif ( $dev{hub} ){
		    $type = (ProductType->search(name=>"Hub"))[0];
		}elsif ( $dev{dot11} ){
		    $type = (ProductType->search(name=>"Access Point"))[0];
		}elsif ( scalar $dev{interface} ){
		    $type = (ProductType->search(name=>"Switch"))[0];
		}
	    }
	    my %prodtmp = ( name         => $dev{productname} || $dev{sysobjectid},
			    description  => $dev{productname} || $dev{sysdescription},
			    sysobjectid  => $dev{sysobjectid},
			    type         => $type->id,
			    manufacturer => $ent,
			    );
	    my $newprodid;
	    if ( ($newprodid = $self->insert(table => 'Product', state => \%prodtmp)) ){
		my $msg = sprintf("Created product: %s.  Guessing type is %s.", $prodtmp{name}, $type->name);
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => $msg );		
		$self->output($msg);
		$devtmp{productname} = $newprodid;
	    }else{
		$self->debug( loglevel => 'LOG_ERR',
			      message  => "Could not create new Product: %s: %s",
			      args     => [$prodtmp{name}, $self->error],
			      );		
		$devtmp{productname} = 0;
	    }
	}
    }else{
	$devtmp{productname} = 0;
    }

    ###############################################
    # Update/add PhsyAddr for Device
    
    if( defined $dev{physaddr} ) {
	# Look it up
	if (my $phy = (PhysAddr->search(address => $dev{physaddr}))[0] ){
	    if ( ! $device ){
		if ( my $otherdev = (Device->search(physaddr => $phy->id))[0] ){
		    #
		    # Another device exists that has that address
		    # 
		    my $name = (defined($otherdev->name->name))? $otherdev->name->name : $otherdev->id;
		    $self->error( sprintf("PhysAddr %s belongs to existing device %s. Aborting", 
					  $dev{physaddr}, $name ) ); 
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => $self->error,
				  );
		    return 0;
		}
	    }else{
		#
		# The address exists (maybe discovered in fw tables/arp cache)
		# Just point to it from this Device
		#
		$devtmp{physaddr} = $phy->id;
		$self->update( object => $phy, 
			       state  => {last_seen => $self->timestamp },
			       );
	    }
	    $self->debug( loglevel => 'LOG_INFO',
			  message  => "Pointing to existing %s as base bridge address",
			  args => [$dev{physaddr}],
			  );		
	    #
	    # address is new.  Add it
	    #
	}else{
	    my %phaddrtmp = ( address => $dev{physaddr},
			      first_seen => $self->timestamp,
			      last_seen => $self->timestamp,
			      );
	    my $newphaddr;
	    if ( ! ($newphaddr = $self->insert(table => 'PhysAddr', state => \%phaddrtmp)) ){
		$self->debug( loglevel => 'LOG_ERR',
			      message  => "Could not create new PhysAddr: %s: %s",
			      args => [$phaddrtmp{address}, $self->error],
			      );
		$devtmp{physaddr} = 0;
	    }else{
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => "Added new PhysAddr: %s",
			      args => [$phaddrtmp{address}],
			      );		
		$devtmp{physaddr} = $newphaddr;
	    }
	}
    }else{
	$self->debug( loglevel => 'LOG_INFO',
		      message  => "Device did not return dot1dBaseBridgeAddress",
		      );		
    }
    ###############################################
    # Serial Number
    
    if( defined $dev{serialnumber} ) {
	if ( my $otherdev = (Device->search(serialnumber => $dev{serialnumber}))[0] ){
	    if ( defined($device) && $device != $otherdev ){
		my $othername = (defined $otherdev->name && defined $otherdev->name->name) ? 
		    $otherdev->name->name : $otherdev->id;
		$self->error( sprintf("S/N %s belongs to existing device %s. Aborting.", 
				      $dev{serialnumber}, $othername) ); 
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $self->error,
			      );
		return 0;
	    }
	}
	$devtmp{serialnumber} = $dev{serialnumber};
    }else{
	$self->debug( loglevel => 'LOG_INFO',
		      message  => "Device did not return serial number",
		      );		
    }
    ###############################################
    # Update/Add Device
    
    if ( $device ){
	$devtmp{lastupdated} = $self->timestamp;
	unless( $self->update( object => $device, state => \%devtmp ) ) {
	    $self->error( sprintf("Error updating device %s: %s", $host, $self->error) ); 
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
	    $self->error( sprintf("Error creating device %s: %s", $host, $self->error) ); 
	    $self->debug( loglevel => 'LOG_ERR',
			  message  => $self->error,
			  );
	    return 0;
	}
	$device = Device->retrieve($newdevid);
    }

    ##############################################
    # for each interface just discovered...

    my (%dbips, %newips, %dbvlans, %ifvlans, %name2int);

    foreach my $newif ( sort { $a <=> $b } keys %{ $dev{interface} } ) {

	############################################
	# set up IF state data
	my( %iftmp, $if );
	$iftmp{device} = $device->id;

	my %IFFIELDS = ( number           => "",
			 name             => "",
			 type             => "",
			 description      => "",
			 speed            => "",
			 admin_status     => "",
			 oper_status      => "",
			 admin_duplex     => "",
			 oper_duplex      => "");
	
	foreach my $field ( keys %{ $dev{interface}{$newif} } ){
	    if (exists $IFFIELDS{$field}){
		$iftmp{$field} = $dev{interface}{$newif}{$field};
	    }
	}

	###############################################
	# Update/add PhsyAddr for Interface
	if (defined (my $addr = $dev{interface}{$newif}{physaddr})){
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
			      message  => "Interface %s,%s has existing PhysAddr %s",
			      args => [$iftmp{number}, $iftmp{name}, $addr],
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
				  message  => "Could not create new PhysAddr %s for Interface %s,%s: %s",
				  args     => [$phaddrtmp{address}, 
					       $iftmp{number}, 
					       $iftmp{name}, 
					       $self->error],
				  );
		    $iftmp{physaddr} = 0;
		}else{
		    $self->debug( loglevel => 'LOG_INFO',
				  message  => "Added new PhysAddr %s for Interface %s,%s",
				  args => [$phaddrtmp{address}, $iftmp{number}, $iftmp{name}],
				  );		
		    $iftmp{physaddr} = $newphaddr;
		}
	    }
	}
	############################################
	# Add/Update interface
	if ( $if = (Interface->search(device => $device->id, 
				      number => $iftmp{number}))[0] ) {
	    delete( $ifs{ $if->id } );
	    
	    unless( $self->update( object => $if, state => \%iftmp ) ) {
		my $msg = sprintf("Could not update Interface %s,%s: .", 
				  $iftmp{number}, $iftmp{name}, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }
	} else {

	    $iftmp{speed}          ||= 0; #can't be null
	    $iftmp{monitored}      ||= $self->{config}->{IF_MONITORED};
	    $iftmp{snmp_managed}   ||= $self->{config}->{IF_SNMP};

	    my $unknown_status;
	    my $unknown_status_id;
	    if ( $unknown_status = (MonitorStatus->search(name=>"Unknown"))[0]){
		$unknown_status_id = $unknown_status->id;
	    }else{
		$unknown_status_id = 0
	    }
	    $iftmp{monitorstatus}  ||= $unknown_status_id;
	    
	    if ( ! (my $ifid = $self->insert( table => 'Interface', 
					    state => \%iftmp )) ) {
		my $msg = sprintf("Error inserting Interface %s,%s: %s", 
			       $iftmp{number}, $iftmp{name}, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }else{
		unless( $if = Interface->retrieve($ifid) ) {
		    my $msg = sprintf("Couldn't retrieve Interface id %s", $ifid);
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => $msg );
		    $self->output($msg);
		    next;
		}
		my $msg = sprintf("Inserted Interface %s,%s ", $iftmp{number}, $iftmp{name} );
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => $msg,
			      );
		$self->output($msg);
	    }
	    
	}
	################################################################
	# Keep a hash of VLAN membership
	# We'll Add/Update at the end
	
	if( exists( $dev{interface}{$newif}{vlans} ) ) {
	    foreach my $vid ( keys %{ $dev{interface}{$newif}{vlans} } ){
		my $vname = $dev{interface}{$newif}{vlans}{$vid};
		push @{$ifvlans{$vid}{$vname}}, $if->id;
	    }
	}
	# 
	# Get all stored VLAN memberships (these are join tables);
	#
	map { $dbvlans{$_->interface->id} = $_->id } $if->vlans();

	################################################################
	# Add/Update IPs
	
	if( exists( $dev{interface}{$newif}{ips} ) && ! $device->natted ) {	    
	    # Get all stored IPs belonging to this Interface
	    #
	    map { $dbips{$_->address} = $_->id } $if->ips();

	    foreach my $newip ( sort keys %{ $dev{interface}{$newif}{ips} } ){
		my( $maskobj, $subnet, $ipdbobj );
		my $version = ($newip =~ /:/) ? 6 : 4;
		my $prefix = ($version == 6) ? 128 : 32;

		########################################################
		# Create subnet if device is a router (ipForwarding true)
		# and addsubnets flag is on

		if ( $dev{router} && $argv{addsubnets}){
		    my $newmask;
		    if ( $newmask = $dev{interface}{$newif}{ips}{$newip} ){
			my $subnetaddr = $self->getsubnetaddr($newip, $newmask);
			if ( $subnetaddr ne $newip ){
			    if ( ! ($self->searchblock($subnetaddr, $newmask)) ){
				unless( $self->insertblock(address     => $subnetaddr, 
							   prefix      => $newmask, 
							   statusname  => "Subnet",
							   ) ){
				    my $msg = sprintf("Could not insert Subnet %s/%s: %s", 
						      $subnetaddr, $newmask, $self->error);
				    $self->debug(loglevel => 'LOG_ERR',
						 message  => $msg );
				}else{
				    my $msg = sprintf("Created Subnet %s/%s", $subnetaddr, $newmask);
				    $self->debug(loglevel => 'LOG_NOTICE',
						 message  => $msg );
				    $self->output($msg);
				}
			    }else{
				my $msg = sprintf("Subnet %s/%s already exists", $subnetaddr, $newmask);
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
		    my $msg = sprintf("%s's IP %s/%s exists. Updating", $if->name, $newip, $prefix);
		    $self->debug( loglevel => 'LOG_DEBUG',
				  message  => $msg );
		    delete( $dbips{$newip} );
		    
		    unless( $ipobj = $self->updateblock(id           => $ipid, 
							statusname   => "Static",
							interface    => $if->id )){
			my $msg = sprintf("Could not update IP %s/%s: %s", $newip, $prefix, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg );
			$self->output($msg);
			next;
		    }

		}elsif ( $ipobj = $self->searchblock($newip) ){
		    # IP exists but not linked to this interface
		    # update
		    my $msg = sprintf("IP %s/%s exists but not linked to %s. Updating", 
				      $newip, $prefix, $if->name);
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => $msg );
		    unless( $ipobj = $self->updateblock(id         => $ipobj->id, 
							statusname => "Static",
							interface  => $if->id )){
			my $msg = sprintf("Could not update IP %s/%s: %s", $newip, $prefix, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg );
			next;
		    }
		}else {
		    #
		    # Create a new Ip
		    unless( $ipobj = $self->insertblock(address    => $newip, 
							prefix     => $prefix, 
							statusname => "Static",
							interface  => $if->id)){
			my $msg = sprintf("Could not insert IP %s: %s", $newip, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg );
			next;
		    }else{
			my $msg = sprintf("Inserted IP %s", $newip);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg );
			$self->output($msg);
		    }
		}
		########################################################
		# Create A records for each ip address discovered
		# 
		unless ( $ipobj->arecords ){
		    
		    ################################################
		    # Is this the only ip in this device,
		    # or is this the address associated with the
		    # hostname?
		    
		    my $numips = 0;
		    map { map { $numips++ } keys %{ $dev{interface}{$_}{ips} } } keys %{ $dev{interface} };

		    if ( $numips == 1 || exists $hostnameips{$ipobj->address} ){

			# We should already have an RR created
			# Create the A record to link that RR with this ipobj
			if ( $device->name ){
			    unless ($self->insert_a(rr          => $device->name, 
						    ip          => $ipobj,
						    contactlist => $device->contactlist)){
				my $msg = sprintf("Could not insert DNS A record for %s: %s", 
						  $ipobj->address, $self->error);
				$self->debug(loglevel => 'LOG_ERR',
					     message  => $msg );
				$self->output($msg);
			    }else{
				my $msg = sprintf("Created DNS A record for %s: %s", 
						  $newip, $device->name->name);
				$self->debug(loglevel => 'LOG_NOTICE',
					     message  => $msg );
				$self->output($msg);
			    }
			}
		    }else{
			# Insert necessary records
			my $name = $self->_canonicalize_int_name($ipobj->interface->name);
			if ( exists $name2int{$name} ){
			    # Interface has more than one ip
			    # Append the ip address to the name to make it unique
			    $name .= "-" . $ipobj->address;
			}
			# Keep record
			$name2int{$name} = $ipobj->interface->name; 
			# Append device name
			# Remove any possible prefixes added
			# e.g. loopback0.devicename -> devicename
			my $suffix = $device->name->name;
			$suffix =~ s/^.*\.(.*)/$1/;
			$name .= "." . $suffix ;
			unless ($self->insert_a(name        => $name,
						       ip          => $ipobj,
						       contactlist => $device->contactlist
						       )){
			    my $msg = sprintf("Could not insert DNS A record for %s: %s", 
					      $ipobj->address, $self->error);
			    $self->debug(loglevel => 'LOG_ERR',
					 message  => $msg );
			    $self->output($msg);
			}else{
			    my $msg = sprintf("Created DNS A record for %s: %s", 
					      $newip, $name);
			    $self->debug(loglevel => 'LOG_NOTICE',
					 message  => $msg );
			    $self->output($msg);
			}
		    }
		} # unless ipobj->arecords
	    } # foreach newip
	} #if ips found 
    } #foreach $newif
    
    ##############################################
    # remove each interface that no longer exists
    #
    ## Do not remove manually-added ports for these hubs
    unless ( exists $dev{sysobjectid} 
	     && exists($self->{config}->{IGNOREPORTS}->{$dev{sysobjectid}} )){
	
	foreach my $nonif ( keys %ifs ) {
	    my $ifobj = $ifs{$nonif};

	    ############################################################################
	    # Before removing, try to maintain dependencies finding another
	    # interface (any) that has one of this interface's ips
	    if (exists $dbifdeps{$nonif}){
		my $msg = sprintf("Interface %s,%s had dependency. Will try to maintain", 
				  $ifobj->number, $ifobj->name);
		$self->debug( loglevel => 'LOG_NOTICE',
			      message  => $msg,
			      );
		my $found = 0;
		foreach my $oldipaddr (keys %{$dbifdeps{$nonif}} ){
		    foreach my $newaddr (keys %newips ){
			if (exists ($newips{$oldipaddr}) ){
			    my $newif = $newips{$oldipaddr};
			    my $msg = sprintf("IP address %s is now on %s,%s.", 
					      $oldipaddr, $newif->number, $newif->name);
			    $self->debug( loglevel => 'LOG_DEBUG',
					  message  => $msg,
					  );
			    my $ifdep = $dbifdeps{$nonif}{$oldipaddr};
			    my ($role, $rel);
			    if ($ifdep->parent->id eq $nonif) {
				$role = "parent"; 
				$rel = "child" ; 
			    }else{
				$role = "child"; 
				$rel = "parent"; 
			    }
			    unless ( $self->update(object => $ifdep, state => {$role => $newif} )){
				my $msg = sprintf("Could not update Dependency for %s: %s", 
						  $nonif, $self->error);
				$self->debug( loglevel => 'LOG_ERR',
					      message  => $msg,
					      );
				$self->output($msg);
			    }else{
				my $msg = sprintf("%s,%s is now %s of %s", 
						  $newif->number, $newif->name, $role, 
						  $ifdep->$rel->number, $ifdep->$rel->name);
				$self->debug( loglevel => 'LOG_ERR',
					      message  => $msg,
					      );
				
			    }
			    $found = 1;
			    last;
			}
		    }
		    if (! $found ){
			my $msg = sprintf("Found no interfaces with one of %s's addresses", $nonif);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg,
				      );
		    }
		}
	    }
	    my $msg = sprintf("Interface %s,%s no longer exists.  Removing.", $ifobj->number, $ifobj->name);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );
	    $self->output($msg);
	    unless( $self->remove( table => "Interface", id => $nonif ) ) {
		my $msg = sprintf("Could not remove Interface %s,%s: %s", 
				  $ifobj->number, $ifobj->name, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }
	}
    }
    ##############################################
    # Add/Update VLANs
    foreach my $vid (keys %ifvlans){
	foreach my $vname (keys %{$ifvlans{$vid}}){
	    my $vo;
	    # look it up
	    unless ($vo = (Vlan->search(vid =>$vid))[0]){
		#create
		my %votmp = ( vid         => $vid,
			      description => $vname );
		if ( ! (my $vobjid = $self->insert (table => "Vlan", state => \%votmp)) ) {
		    my $msg = sprintf("Could not insert Vlan %s: %s", 
				      $vo->description, $self->error);
		    $self->debug( loglevel => 'LOG_ERR',
				  message  => $msg,
				  );
		    $self->output($msg);
		    next;
		}else {
		    $vo = Vlan->retrieve($vobjid);
		    my $msg = sprintf("Inserted VLAN %s", $vo->description);
		    $self->debug( loglevel => 'LOG_NOTICE',
				  message  => $msg,
				  );
		    $self->output($msg);
		}
	    }
	    # verify joins
	    foreach my $ifid ( @{ $ifvlans{$vid}{$vname} } ){
		my $if = Interface->retrieve($ifid);
		if( ! exists $dbvlans{$ifid} ){
		    my %jtmp = (interface => $if, vlan => $vo);
		    unless ( my $j = $self->insert(table => "InterfaceVlan", state => \%jtmp) ){
			my $msg = sprintf("Could not insert InterfaceVlan join %s:%s: %s", 
					  $if->name, $vo->vid, $self->error);
			$self->debug( loglevel => 'LOG_ERR',
				      message  => $msg,
				      );
			$self->output($msg);
		    }else{
			my $msg = sprintf("Assigned Interface %s,%s to VLAN %s", 
					  $if->number, $if->name, $vo->description);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg,
				      );
		    }
		}else {
		    my $msg = sprintf("Interface %s,%s already part of vlan %s", 
				      $if->number, $if->name, $vo->vid);
		    $self->debug( loglevel => 'LOG_DEBUG',
				  message  => $msg,
				  );
		    delete $dbvlans{$ifid};
		}
	    }
	}
    }
    
    ##############################################
    # remove each ip address that no longer exists
    
    unless ( $device->natted ){
	foreach my $nonip ( keys %dbips ) {
	    my $msg = sprintf("IP %s no longer exists.  Removing.", 
			      $nonip);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );
	    $self->output($msg);		
	    unless( $self->removeblock( id => $dbips{$nonip} ) ) {
		my $msg = sprintf("Could not remove IP %s: %s", 
				  $nonip, $self->error);
		$self->debug( loglevel => 'LOG_ERR',
			      message  => $msg,
			      );
		$self->output($msg);
		next;
	    }
	}
    }

    ##############################################
    # remove each vlan membership that no longer exists
    
    foreach my $nonvlan ( keys %dbvlans ) {
	my $j = InterfaceVlan->retrieve($dbvlans{$nonvlan});
	my $msg = sprintf("Vlan membership %s:%s no longer exists.  Removing.", 
			  $j->interface->name, $j->vlan->vid);
	$self->debug( loglevel => 'LOG_NOTICE',
		      message  => $msg,
		      );
	unless( $self->remove( table => 'InterfaceVlan', id => $nonvlan ) ) {
	    my $msg = sprintf("Could not remove InterfaceVlan %s: %s", 
			      $j->id, $self->error);
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
	foreach my $peer ( keys %{$dev{bgppeer}} ){
	    my $p; # bgppeering object

	    # Check if peering exists
	    unless ( $p = (BGPPeering->search( device => $device->id,
					       bgppeeraddr => $peer ))[0] ){
		# Doesn't exist.  
		# Check if we have some Entity info
		next unless ( exists ($dev{bgppeer}{$peer}{asname}) ||
			      exists ($dev{bgppeer}{$peer}{orgname})
			      ); 
		my $ent;
		# Check if Entity exists
		unless ( ( $ent = (Entity->search( asnumber => $dev{bgppeer}{$peer}{asnumber}))[0] ) ||  
			 ( $ent = (Entity->search( asname   => $dev{bgppeer}{$peer}{asname}))  [0] ) ||  
			 ( $ent = (Entity->search( name     => $dev{bgppeer}{$peer}{orgname})) [0] )
			 ){
		    
		    # Doesn't exist. Create Entity
		    my $msg = sprintf("Entity %s (%s) not found. Creating", 
				      $dev{bgppeer}{$peer}{orgname}, $dev{bgppeer}{$peer}{asname});
		    $self->debug( loglevel => 'LOG_INFO',
				  message  => $msg );
		    my $t;
		    unless ( $t = (EntityType->search(name => "Peer"))[0] ){
			$t = 0; 
		    }
		    my $entname = $dev{bgppeer}{$peer}{orgname} || $dev{bgppeer}{$peer}{asname} ;
		    $entname .= "($dev{bgppeer}{$peer}{asnumber})";

		    if ( my $entid = $self->insert(table => 'Entity', 
						   state => { name     => $entname,
							      asname   => $dev{bgppeer}{$peer}{asname},
							      asnumber => $dev{bgppeer}{$peer}{asnumber},
							      type => $t }) ){
			my $msg = sprintf("Created Peer Entity: %s. ", $entname);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg );		
			$ent = Entity->retrieve($entid);
		    }else{
			my $msg = sprintf("Could not create new Entity: %s: %s",$entname, $self->error);
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
				bgppeerid   => $dev{bgppeer}{$peer}{bgppeerid},
				bgppeeraddr => $peer,
				monitored     => 1,
				);
		    if ( ($p = $self->insert(table => 'BGPPeering', 
					     state => \%ptmp ) ) ){
			my $msg = sprintf("Created Peering with: %s. ", $ent->name);
			$self->debug( loglevel => 'LOG_NOTICE',
				      message  => $msg );
			$self->output($msg);
		    }else{
			my $msg = sprintf("Could not create Peering with : %s: %s",
					  $ent->name, $self->error );
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
	    my $msg = sprintf("BGP Peering with %s (%s) no longer exists.  Removing.", 
			      $p->entity->name, $p->bgppeeraddr);
	    $self->debug( loglevel => 'LOG_NOTICE',
			  message  => $msg,
			  );
	    $self->output($msg);		
	    unless( $self->remove( table => 'BGPPeering', id => $nonpeer ) ) {
		my $msg = sprintf("Could not remove BGPPeering %s: %s", 
				  $p->id, $self->error);
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
    $self->debug( loglevel => 'LOG_NOTICE',
		  message  => $msg );
    return $device;
}

=head2 get_dev_info - Get SNMP info from Device
 
 Use the SNMP libraries to get a hash with the device information
 This should hide all possible underlying SNMP code logic from our
 device insertion/update code

 Required Args:
   host:  name or ip address of host to query
   comstr: SNMP community string
 Optional args:
  

=cut

sub get_dev_info {
    my ($self, $host, $comstr) = @_;
    $self->_clear_output();

    $self->{nv}->build_config( "device", $host, $comstr );
    my (%nv, %dev);
    unless( (%nv  = $self->{nv}->get_device( "device", $host )) &&
	    exists $nv{sysUpTime} ) {
	$self->error(sprintf ("Could not reach device %s", $host) );
	$self->debug(loglevel => 'LOG_ERR',
		     message => $self->error, 
		     );
	return 0;
    }
    if ( $nv{sysUpTime} < 0 ) {
	$self->error( sprintf("Device %s did not respond", $host) );
	$self->debug( loglevel => 'LOG_ERR',
		      message => $self->error);
	return 0;
    }
    my $msg = sprintf("Contacted Device %s", $host);
    $self->debug( loglevel => 'LOG_NOTICE',
		  message => $msg );
    $self->output($msg);


    ################################################################
    # Device's global vars

    if ( $self->_is_valid($nv{sysObjectID}) ){
	$dev{sysobjectid} = $nv{sysObjectID};
	$dev{sysobjectid} =~ s/^\.(.*)/$1/;  #Remove unwanted first dot
	$dev{enterprise} = $dev{sysobjectid};
	$dev{enterprise} =~ s/(1\.3\.6\.1\.4\.1\.\d+).*/$1/;

    }
    if ( $self->_is_valid($nv{sysName}) ){
	$dev{sysname} = $nv{sysName};
    }
    if ( $self->_is_valid($nv{sysDescr}) ){
	$dev{sysdescription} = $nv{sysDescr};
    }
    if ( $self->_is_valid($nv{sysContact}) ){
	$dev{syscontact} = $nv{sysContact};
    }
    if ( $self->_is_valid($nv{sysLocation}) ){
	$dev{syslocation} = $nv{sysLocation};
    }
    ################################################################
    # Does it route?
    if ( $self->_is_valid($nv{ipForwarding}) && $nv{ipForwarding} == 1 ){
	$dev{router} = 1;
    }
    ################################################################
    # Is it an access point?
    if ( $self->_is_valid($nv{dot11StationID}) ){
	$dev{dot11} = 1;
    }
    if( $self->_is_valid($nv{dot1dBaseBridgeAddress})  ) {
	# Canonicalize address
	$dev{physaddr} = $self->_readablehex($nv{dot1dBaseBridgeAddress});
    }
    if( $self->_is_valid($nv{entPhysicalDescr}) ) {
	$dev{productname} = $nv{entPhysicalDescr};
    }elsif( $self->_is_valid($nv{sysDescr}) ){
	# Try and use the first 4 words of sysDescr as productname
	# 
	my @words = split /\s+/, $nv{sysDescr};
	$dev{productname} = join " ", @words[0..3];
    }
    if( $self->_is_valid($nv{entPhysicalMfgName}) ) {
	$dev{manufacturer} = $nv{entPhysicalMfgName};
    }
    if( $self->_is_valid($nv{entPhysicalSerialNum}) ) {
	$dev{serialnumber} = $nv{entPhysicalSerialNum};
    }


    ################################################################
    # Interface status (oper/admin)

    my %IFSTATUS = ( '1' => 'up',
		     '2' => 'down' );

    ################################################################
    # MAU-MIB's ifMauType to half/full translations

    my %MAU2DUPLEX = ( '.1.3.6.1.2.1.26.4.10' => "half",
		       '.1.3.6.1.2.1.26.4.11' => "full",
		       '.1.3.6.1.2.1.26.4.12' => "half",
		       '.1.3.6.1.2.1.26.4.13' => "full",
		       '.1.3.6.1.2.1.26.4.15' => "half",
		       '.1.3.6.1.2.1.26.4.16' => "full",
		       '.1.3.6.1.2.1.26.4.17' => "half",
		       '.1.3.6.1.2.1.26.4.18' => "full",
		       '.1.3.6.1.2.1.26.4.19' => "half",
		       '.1.3.6.1.2.1.26.4.20' => "full",
		       '.1.3.6.1.2.1.26.4.21' => "half",
		       '.1.3.6.1.2.1.26.4.22' => "full",
		       '.1.3.6.1.2.1.26.4.23' => "half",
		       '.1.3.6.1.2.1.26.4.24' => "full",
		       '.1.3.6.1.2.1.26.4.25' => "half",
		       '.1.3.6.1.2.1.26.4.26' => "full",
		       '.1.3.6.1.2.1.26.4.27' => "half",
		       '.1.3.6.1.2.1.26.4.28' => "full",
		       '.1.3.6.1.2.1.26.4.29' => "half",
		       '.1.3.6.1.2.1.26.4.30' => "full",
		       );
    
    ################################################################
    # Map dot3StatsDuplexStatus

    my %DOT3DUPLEX = ( 1 => "na",
		       2 => "half",
		       3 => "full",
		       );

    ################################################################
    # Catalyst's portDuplex to half/full translations

    my %CATDUPLEX = ( 1 => "half",
		      2 => "full",
		      3 => "auto",  #(*)
		      4 => "auto",
		      );
    # (*) MIB says "disagree", but we can assume it was auto and the other 
    # end wasn't
    
    my @ifrsv = @{ $self->{config}->{'IFRESERVED'} };
    
    $self->debug( loglevel => 'LOG_DEBUG',
		  message => "Ignoring Interfaces: %s", 
		  args => [ join ', ', @ifrsv ] );	    	 
    
    ##############################################
    # Netdot to Netviewer field name translations

    my %IFFIELDS = ( number            => "instance",
		     name              => "name",
		     type              => "ifType",
		     description       => "descr",
		     speed             => "ifSpeed",
		     admin_status      => "ifAdminStatus",
		     oper_status       => "ifOperStatus" );


    ##############################################
    # for each interface discovered...
    
    foreach my $newif ( keys %{ $nv{interface} } ) {
	############################################
	# check whether should skip IF
	my $skip = 0;
	foreach my $n ( @ifrsv ) {
	    if( $nv{interface}{$newif}{name} =~ /$n/ ) { $skip = 1; last }
	}
	next if( $skip );

	foreach my $dbname ( keys %IFFIELDS ) {
	    if( $dbname =~ /status/ ) {
		my $val = $nv{interface}{$newif}{$IFFIELDS{$dbname}};
		if( $val =~ /\d+/ ){
		    $dev{interface}{$newif}{$dbname} = $IFSTATUS{$val};
		}else{
		    # Netviewer changes it in some cases.
		    # Just use the value
		    $dev{interface}{$newif}{$dbname} = $val;	    
		}
	    }elsif( $dbname eq "description" ) {
		# Ignore these descriptions
		if ( $nv{interface}{$newif}{$IFFIELDS{$dbname}} ne "-" &&
		    $nv{interface}{$newif}{$IFFIELDS{$dbname}} ne "not assigned" ) {
		    $dev{interface}{$newif}{$dbname} = $nv{interface}{$newif}{$IFFIELDS{$dbname}};
		}
	    }else {
		$dev{interface}{$newif}{$dbname} = $nv{interface}{$newif}{$IFFIELDS{$dbname}};
	    }
	}
	if ( $self->_is_valid($nv{interface}{$newif}{ifPhysAddress}) ){
	    $dev{interface}{$newif}{physaddr} = $self->_readablehex($nv{interface}{$newif}{ifPhysAddress});
	}
	################################################################
	# Set Oper Duplex mode
	my ($opdupval, $opdup);
	################################################################
	if( $self->_is_valid($nv{interface}{$newif}{ifMauType}) ){
	    ################################################################
	    # ifMauType
	    $opdupval = $nv{interface}{$newif}{ifMauType};
	    $opdup = $MAU2DUPLEX{$opdupval} || "";

	}
	if( $self->_is_valid($nv{interface}{$newif}{ifSpecific}) && !($opdup) ){
	    ################################################################
	    # ifSpecific
	    $opdupval = $nv{interface}{$newif}{ifSpecific};
	    $opdup = $MAU2DUPLEX{$opdupval} || "";

	}
	if( $self->_is_valid($nv{interface}{$newif}{dot3StatsDuplexStatus}) && !($opdup) ){
	    ################################################################
	    # dot3Stats
	    $opdupval = $nv{interface}{$newif}{dot3StatsDuplexStatus};
	    $opdup = $DOT3DUPLEX{$opdupval} || "";

	}
	if( $self->_is_valid($nv{interface}{$newif}{portDuplex}) && !($opdup) ){
	    ################################################################
	    # Catalyst
	    $opdupval = $nv{interface}{$newif}{portDuplex};
	    $opdup = $CATDUPLEX{$opdupval} || "";
	}
	$dev{interface}{$newif}{oper_duplex} = $opdup || "na" ;  	    

	################################################################
	# Set Admin Duplex mode
	my ($admindupval, $admindup);
	################################################################
	# Standard MIB
	if ($self->_is_valid($nv{interface}{$newif}{ifMauDefaultType})){
	    $admindupval = $nv{interface}{$newif}{ifMauDefaultType};
	    $admindup= $MAU2DUPLEX{$admindupval} || 0;
	}
	$dev{interface}{$newif}{admin_duplex} = $admindup || "na";

	####################################################################
	# IP addresses and masks 
	# (mask is the value for each ip address key)
	foreach my $ip( keys %{ $nv{interface}{$newif}{ipAdEntIfIndex}}){
	    $dev{interface}{$newif}{ips}{$ip} = $nv{interface}{$newif}{ipAdEntIfIndex}{$ip};
	}

	################################################################
	# Vlan info
	my ($vid, $vname);
	################################################################
	# Standard MIB
	if( $self->_is_valid( $nv{interface}{$newif}{dot1qPvid} ) ) {
	    $vid = $nv{interface}{$newif}{dot1qPvid};
	    $vname = ( $self->_is_valid($nv{interface}{$newif}{dot1qVlanStaticName}) ) ? 
		$nv{interface}{$newif}{dot1qVlanStaticName} : $vid;
	    $dev{interface}{$newif}{vlans}{$vid} = $vname;
	    ################################################################
	    # HP
	}elsif( $self->_is_valid( $nv{interface}{$newif}{hpVlanMemberIndex} ) ){
	    $vid = $nv{interface}{$newif}{hpVlanMemberIndex};
	    $vname = ( $self->_is_valid($nv{interface}{$newif}{hpVlanIdentName}) ) ?
		$nv{interface}{$newif}{hpVlanIdentName} : $vid;
	    $dev{interface}{$newif}{vlans}{$vid} = $vname;
	    ################################################################
	    # Cisco
	}elsif( $self->_is_valid( $nv{interface}{$newif}{vmVlan} )){
	    $vid = $nv{interface}{$newif}{vmVlan};
	    $vname = ( $self->_is_valid($nv{cviRoutedVlan}{$vid.0}{name}) ) ? 
		$nv{cviRoutedVlan}{$vid.0}{name} : $vid;
	    $dev{interface}{$newif}{vlans}{$vid} = $vname;
	}

    }
    ##############################################
    # for each hubport discovered...
    if ( scalar ( my @hubports = keys %{ $nv{hubPorts} } ) ){
	$dev{hub} = 1;
	if ( ! exists($self->{config}->{IGNOREPORTS}->{$dev{sysobjectid}}) ){
	    foreach my $newport ( @hubports ) {
		$dev{interface}{$newport}{name}         = $newport;
		$dev{interface}{$newport}{number}       = $newport;
		$dev{interface}{$newport}{speed}        = "10 Mbps"; #most likely
		$dev{interface}{$newport}{oper_duplex}  = "na";
		$dev{interface}{$newport}{admin_duplex} = "na";
		$dev{interface}{$newport}{oper_status}  = "na";
		$dev{interface}{$newport}{admin_status} = "na";
	    }
	}
    }
    
    if ( $self->{config}->{ADD_BGP_PEERS} ){
	##############################################
	# for each BGP Peer discovered...
	
	foreach my $peer ( keys %{ $nv{bgpPeer} } ) {
	    
	    $dev{bgppeer}{$peer}{bgppeerid} = $nv{bgpPeer}{$peer}{bgpPeerIdentifier};
	    my $asn = $nv{bgpPeer}{$peer}{bgpPeerRemoteAs};
	    $dev{bgppeer}{$peer}{asnumber} = $asn;
	    
	    # Query any configured WHOIS servers for more info
	    #
	    if ( $self->{config}->{DO_WHOISQ} ){
		my $found = 0;
		foreach my $host ( keys %{$self->{config}->{WHOISQ}} ){
		    last if $found;
		    my @lines = `whois -h $host AS$asn`;
		    foreach (@lines){
			foreach my $key ( keys %{$self->{config}->{WHOISQ}->{$host}} ){
			    if (/No entries found/i){
				last;
			    }
			    my $exp = $self->{config}->{WHOISQ}->{$host}->{$key};
			    if ( /$exp/ ){
				my (undef, $val) = split /:\s+/, $_; 
				chomp($val);
				$dev{bgppeer}{$peer}{$key} = $val;
				$found = 1;
			    }
			}
		    }
		}
		unless ( $found ){
		    $dev{bgppeer}{$peer}{asname} = "AS $asn";
		    $dev{bgppeer}{$peer}{orgname} = "AS $asn";		    
		}
	    }else{
		$dev{bgppeer}{$peer}{asname} = "AS $asn";
		$dev{bgppeer}{$peer}{orgname} = "AS $asn";
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

=head2 interfaces_by_number - Retrieve interfaces from a Device and sort by number.  
                              Handles the case of port numbers with dots (hubs)

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub interfaces_by_number {
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

=head2 interfaces_by_name - Retrieve interfaces from a Device and sort by name.  


Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub interfaces_by_name {
    my ( $self, $o ) = @_;
    my @ifs;
    my $id = $o->id;
    eval {
	@ifs = Interface->search_ifsbyname($id);
    };
    if ($@){
	$self->error("$@");
	return;
    }
    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_speed - Retrieve interfaces from a Device and sort by speed.  

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub interfaces_by_speed {
    my ( $self, $o ) = @_;
    my @ifs;
    my $id = $o->id;
    eval {
	@ifs = Interface->search_ifsbyspeed($id);
    };
    if ($@){
	$self->error("$@");
	return;
    }
    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_vlan - Retrieve interfaces from a Device and sort by vlan ID

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

Note: If the interface has/belongs to more than one vlan, sort function will only
use one of the values.

=cut

sub interfaces_by_vlan {
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

=head2 interfaces_by_descr - Retrieve interfaces from a Device and sort by description

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub interfaces_by_descr {
    my ( $self, $o ) = @_;
    my @ifs;
    my $id = $o->id;
    eval {
	@ifs = Interface->search_ifsbydescr($id);
    };
    if ($@){
	$self->error("$@");
	return;
    }
    return unless scalar @ifs;
    return @ifs;
}

=head2 interfaces_by_jack - Retrieve interfaces from a Device and sort by Jack id

Arguments:  Device object
Returns:    Sorted array of interface objects or undef if error.

=cut

sub interfaces_by_jack {
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

=head2 bgppeers_by_ip - Retrieve BGP peers and sort by remote IP

Arguments:  Device object
Returns:    Sorted array of BGPPeering objects or undef if error.

=cut

sub bgppeers_by_ip {
    my ( $self, $o ) = @_;
    my @peers;
    unless ( @peers = $o->bgppeers() ){
	return ;
    }

    ##############################################
    # To do: 
    # Factor out the sub inside the sort function

    @peers = map { $_->[1] } 
    sort ( { pack("C4"=>$a->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) 
		 cmp pack("C4"=>$b->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/); }  
	   map { [$_->bgppeeraddr, $_] } @peers );

    return unless scalar @peers;
    return @peers;
}

=head2 bgppeers_by_id - Retrieve BGP peers and sort by BGP ID

Arguments:  Device object
Returns:    Sorted array of BGPPeering objects or undef if error.

=cut

sub bgppeers_by_id {
    my ( $self, $o ) = @_;
    my @peers;
    my $id = $o->id;
    unless ( @peers = $o->bgppeers() ){
	return ;
    }
    ##############################################
    # To do: 
    # Factor out the sub inside the sort function

    @peers = map { $_->[1] } 
    sort ( { pack("C4"=>$a->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) 
		 cmp pack("C4"=>$b->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/); }  
	   map { [$_->bgppeerid, $_] } @peers );
    
    return unless scalar @peers;
    return @peers;
}

=head2 bgppeers_by_entity - Retrieve BGP peers and sort by Entity name, AS number or AS Name

Arguments:  Device object, Entity table field
Returns:    Sorted array of BGPPeering objects or undef if error.

=cut

sub bgppeers_by_entity {
    my ( $self, $o, $field ) = @_;
    $field ||= "name";
    unless ( $field eq "name" || $field eq "asnumber" || $field eq "asname" ){
	$self->error("Invalid Entity field: $field");
	return;
    }
    my $sortsub = ($field eq "asnumber") ? sub{$a->entity->$field <=> $b->entity->$field} : sub{$a->entity->$field cmp $b->entity->$field};
    my @peers;
    unless ( @peers = $o->bgppeers() ){
	return ;
    }
    @peers = sort $sortsub @peers;
    return unless scalar @peers;
    return @peers;
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
# _is_valid
# 
# Returns:
#   true if valid, false otherwise
#####################################################################
sub _is_valid {
    my ($self, $v) = @_;
    
    if ( defined($v) && (length($v) > 0) && ($v !~ /nosuch/i) ){
	return 1;
    }
    return 0;
}

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
    my $h = sprintf('%s', unpack('H*', $v));
    return uc($h);
}

#####################################################################
# Canonicalize Interface Name (for DNS)
#####################################################################
sub _canonicalize_int_name {
    my ($self, $name) = @_;

    my %ABBR = % {$self->{config}->{IF_DNS_ABBR} };
    foreach my $ab (keys %ABBR){
	$name =~ s/$ab/$ABBR{$ab}/i;
    }
    $name =~ s/\/|\.|\s+/-/g;
    return lc( $name );
}
