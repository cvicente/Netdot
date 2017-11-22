package Netdot::Model::Interface;

use base 'Netdot::Model';
use warnings;
use strict;

my $MAC  = Netdot->get_mac_regex();
my $logger = Netdot->log->get_logger('Netdot::Model::Device');

my %SPEED_MAP = ('1536000'     => 'T1',
		 '1544000'     => 'T1',
		 '3072000'     => 'Dual T1',
		 '3088000'     => 'Dual T1',
		 '44210000'    => 'T3',
		 '44736000'    => 'T3',
		 '45045000'    => 'DS3',
		 '46359642'    => 'DS3',
		 '149760000'   => 'ATM on OC-3',
		 '155000000'   => 'OC-3',
		 '155519000'   => 'OC-3',
		 '155520000'   => 'OC-3',
		 '599040000'   => 'ATM on OC-12',
		 '622000000'   => 'OC-12',
		 '622080000'   => 'OC-12',
    );

#Be sure to return 1
1;

=head1 NAME

Netdot::Model::Interface

=head1 CLASS METHODS
=cut

################################################################

=head2 insert - Insert Interface object

    We override the insert method for extra functionality

  Arguments: 
    Hash ref with Interface  fields
  Returns:   
    New Interface object
  Examples:

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    
    # Set some defaults
    $argv->{speed}       ||= 0;
    $argv->{doc_status}  ||= 'manual';

    $argv->{snmp_managed} = $class->config->get('IF_SNMP') 
	unless defined $argv->{snmp_managed};
    
    $argv->{overwrite_descr} = $class->config->get('IF_OVERWRITE_DESCR') 
	unless defined $argv->{overwrite_descr};
    
    $argv->{monitored} = 0 unless defined $argv->{monitored};
    
    $argv->{auto_dns} = $class->config->get('UPDATE_DEVICE_IP_NAMES') 
	unless defined $argv->{auto_dns};
    
    my $unknown_status = (MonitorStatus->search(name=>"Unknown"))[0];
    $argv->{monitorstatus} = ($unknown_status)? $unknown_status->id : undef;
    
    return $class->SUPER::insert( $argv );
}

################################################################

=head2 - find_duplex_mismatches - Finds pairs of interfaces with duplex and/or speed mismatch

  Arguments: 
    None
  Returns:   
    Array of arrayrefs containing pairs of interface id's
  Examples:
    my @list = Interface->find_duplex_mismatches();
=cut

sub find_duplex_mismatches {
    my ($class) = @_;
    $class->isa_class_method('find_duplex_mismatches');
    my $dbh = $class->db_Main();
    my $mismatches = $dbh->selectall_arrayref("SELECT  i.id, r.id
                                               FROM    interface i, interface r
                                               WHERE   i.id<=r.id
                                                 AND   i.neighbor=r.id  
                                                 AND   i.oper_status='up'
                                                 AND   r.oper_status='up'
                                                 AND   i.oper_duplex!=''
                                                 AND   r.oper_duplex!=''
                                                 AND   i.oper_duplex!='unknown'
                                                 AND   r.oper_duplex!='unknown'
                                                 AND   i.oper_duplex!=r.oper_duplex");

    if ( $mismatches ){
	my @pairs = @$mismatches;
	#
	# Ignore devices that incorrectly report their settings
	my @results;
	if ( my $ignored_list = $class->config->get('IGNORE_DUPLEX') ){
	    my %ignored;
	    foreach my $id ( @$ignored_list){
		$ignored{$id} = 1;
	    }
	    foreach my $pair ( @pairs ){
		my $match = 0;
		foreach my $ifaceid ( @$pair ){
		    my $iface = Interface->retrieve($ifaceid) 
			|| $class->throw_fatal("Model::Interface::find_duplex_mismatches: Cannot retrieve Interface id $ifaceid");
		    if ( $iface->device && $iface->device->product 
			 && $iface->device->product->sysobjectid 
			 && exists $ignored{$iface->device->product->sysobjectid} ){
			$match = 1;
			last;
		    }
		}
		push @results, $pair unless $match;
	    }
	}else{
	    return \@pairs;
	}
	return \@results;
    }else{
	return;
    }
}


################################################################

=head2 - find_vlan_mismatches

    Use topology information to determine if VLAN memmbership
    of connected interfaces does not correspond

  Arguments: 
    None
  Returns:   
    Hasref
  Examples:
    my $v = Interface->find_vlan_mismatches();
=cut

sub find_vlan_mismatches {
    my ($class) = @_;
    my $dbh = $class->db_Main;
    my $rows = $dbh->selectall_arrayref("
    SELECT i1.id, i2.id, v1.vid, v2.vid
    FROM   interface i1, interface i2, 
	   interfacevlan iv1, interfacevlan iv2,
	   vlan v1, vlan v2
    WHERE  i1.neighbor=i2.id 
    AND    i1.id < i2.id
    AND    iv1.interface=i1.id AND iv2.interface=i2.id
    AND    iv1.vlan=v1.id AND iv2.vlan=v2.id");

    my %x; my %y; my %lks;

    foreach my $row ( @$rows ){
	my ($i1, $i2, $v1, $v2) = @$row;
	$lks{$i1} = $i2;
	$lks{$i2} = $i1;
	$x{$i1}{$v1} = 1;
	$y{$i2}{$v2} = 1;
    }

    my %res; my %seen;
    foreach my $i ( keys %x ){
	next if $seen{$i};
	my $n = $lks{$i}; 
	$seen{$i} = 1; $seen{$n} = 1;
	my @l1 = sort { $a <=> $b } keys %{$x{$i}};
	my @l2 = sort { $a <=> $b } keys %{$y{$n}};
	if ( scalar(@l1) == 1 && scalar(@l2) == 1 ){
	    # Assume that one vlan on each side
	    # means that they are both the native vlan
	    next;
	}
	my $vlx = join ', ', @l1;
	my $vly = join ', ', @l2;
	if ( $vlx ne $vly ){
	    my $i_name = $class->retrieve($i)->get_label;
	    my $n_name = $class->retrieve($n)->get_label;
	    $res{$i}{name}    = $i_name;
	    $res{$i}{vlans}   = $vlx;
	    $res{$i}{n_id}    = $n;
	    $res{$i}{n_name}  = $n_name;
	    $res{$i}{n_vlans} = $vly;
	}
    }
    return \%res;
}


#################################################################

=head2 - dev_name_number - Hash all interfaces by device, name and number

  Arguments: 
    None
  Returns:   
    Hash ref of hash refs
  Examples:
    my $map = Interface->dev_name_number();

=cut

sub dev_name_number {
    my ($class) = @_;
    $class->isa_class_method('dev_name_number');

    # Build the SQL query
    $logger->debug(sub{ "Interface::dev_name_number: Retrieving all interfaces" });

    my $dbh = $class->db_Main;
    my $sth = $dbh->prepare_cached("SELECT i.id, i.number, i.name, d.id 
                                      FROM device d, interface i 
                                     WHERE i.device=d.id");	
    $sth->execute();
    my $aref = $sth->fetchall_arrayref;

    # Build the hash
    my %map;
    foreach my $row ( @$aref ){
	my ($iid, $inum, $iname, $did) = @$row;
	$map{$did}{number}{$inum} = $iid if defined $inum;
	$map{$did}{name}{$iname}  = $iid if defined $iname;
    }
    $logger->debug(sub{ "Interface::dev_name_number ...done" });

    return \%map;
    
}


=head1 OBJECT METHODS
=cut

################################################################

=head2 delete - Delete object

    We override the delete method for extra functionality

  Arguments: 
    None
  Returns:   
    True if sucessful
  Examples:
    $interface->delete();

=cut

sub delete {
    my $self = shift;
    $self->isa_object_method('delete');
    
    foreach my $neighbor ( $self->neighbors ){
	$neighbor->SUPER::update({neighbor=>undef, neighbor_fixed=>0, neighbor_missed=>0});
    }

    return $self->SUPER::delete();
}

############################################################################

=head2 add_neighbor
    
  Arguments:
    Hash with following key/value pairs:
    id        - Neighbor's Interface id
    score     - Optional score obtained from Topology discovery code (for logging)
    fixed     - (bool) Whether relationship should be removed by automated processes
  Returns:
    True if neighbor was successfully added
  Example:
    $interface->add_neighbor($id);

=cut

sub add_neighbor{
    my ($self, %argv) = @_;
    $self->isa_object_method('add_neighbor');
    my $nid   = $argv{id}    || $self->throw_fatal("Model::Interface::add_neighbor: Missing required argument: id");
    my $score = $argv{score} || 'n/a';
    my $fixed = $argv{fixed} || 0;

    if ( $nid == $self->id ){
	$self->throw_user(sprintf("%s: interface cannot be neighbor of itself", $self->get_label));
    }

    my $neighbor = Interface->retrieve($nid) 
	|| $self->throw_fatal("Model::Interface::add_neighbor: Cannot retrieve Interface id $nid");
    
    if ( $self->neighbor && $neighbor->neighbor 
	 && $self->neighbor->id == $neighbor->id 
	 && $neighbor->neighbor->id == $self->id ){
	
	return 1;
    }
    
    $logger->debug(sub{sprintf("Adding new neighbors: %s <=> %s, score: %s", 
			       $self->get_label, $neighbor->get_label, $score)});
    
    if ( $self->neighbor && $self->neighbor_fixed ){
	$self->throw_user(sprintf("%s has been manually linked to %s", 
				  $self->get_label, $self->neighbor->get_label));
	
    }elsif ( $neighbor->neighbor && $neighbor->neighbor_fixed ) {
	$self->throw_user(sprintf("%s has been manually linked to %s", 
				  $neighbor->get_label, $neighbor->neighbor->get_label));

    }else{
	# Make sure all neighbor relationships are cleared before going on
	$self->remove_neighbor();
	$neighbor->remove_neighbor();
	
	$self->SUPER::update({neighbor        => $neighbor->id, 
			      neighbor_fixed  => $fixed, 
			      neighbor_missed => 0});
	
	$neighbor->SUPER::update({neighbor        => $self->id, 
				  neighbor_fixed  => $fixed, 
				  neighbor_missed => 0});
	
	$logger->info(sprintf("Added new neighbors: %s <=> %s, score: %s", 
			      $self->get_label, $neighbor->get_label, $score));
	return 1;
    }
}


############################################################################

=head2 remove_neighbor
    
  Arguments:
    None
  Returns:
    See update method
  Example:
    $interface->remove_neighbor();

=cut

sub remove_neighbor{
    my ($self) = @_;

    my %args = (
	neighbor        => undef,
	neighbor_fixed  => 0, 
	neighbor_missed => 0
	);

    # Unset neighbor field in all interfaces that have
    # me as their neighbor
    map { $_->SUPER::update(\%args) } $self->neighbors;
    
    # Unset my own neighbor field
    return $self->SUPER::update(\%args);
}

############################################################################

=head2 update - Update Interface
    
  Arguments:
    Hash ref with Interface fields
  Returns:
    See Class::DBI::update()
  Example:
    $interface->update( \%data );

=cut

sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');    
    my $class = ref($self);
    
    if ( exists $argv->{neighbor} ){
	if ( !$argv->{neighbor} ){
	    $self->remove_neighbor();
	}else{
	    $self->add_neighbor(id    => $argv->{neighbor},
				fixed => $argv->{neighbor_fixed});
	}
    }
    delete $argv->{neighbor};
    return $self->SUPER::update($argv);
}

############################################################################

=head2 snmp_update - Insert/Update Interface using SNMP info

  Arguments:  
    Hash with the following keys:
    column        - Any of Interface table columns
    snmp_info     - Hash ref with SNMP info about interface
    add_subnets   - Whether to add subnets automatically
    subs_inherit  - Whether subnets should inherit info from the Device
    stp_instances - Hash ref with device STP info
  Returns:    
    Interface object
  Examples:
    # Instance call
    $if->snmp_update(snmp_info    => $info->{interface}->{$newif},
		     add_subnets  => $add_subnets,
		     subs_inherit => $subs_inherit,
		     );
    # Class call
    my $new = Ipblock->snmp_update(%args, snmp_info=>$info, ...);

=cut

sub snmp_update {
    my ($self, %args) = @_;
    my $info  = $args{snmp_info};
    my %iftmp = (doc_status => 'snmp');

    # Table column values can be arguments or keys in the snmp_info hash
    foreach my $field ( $self->meta_data->get_column_names ){
	$iftmp{$field} = $args{$field}   if exists $args{$field};
	$iftmp{$field} = $info->{$field} if exists $info->{$field};
    }
    
    ############################################
    # Update PhysAddr
    $iftmp{physaddr} = undef;
    if ( my $addr = $info->{physaddr} ){
	my $physaddr = PhysAddr->search(address=>$addr)->first;
	if ( $physaddr ){
	    $physaddr->update({last_seen=>$self->timestamp, static=>1});
	}else{
	    eval {
		$physaddr = PhysAddr->insert({address=>$addr, static=>1}); 
	    };
	    if ( my $e = $@ ){
		$logger->warn("Could not insert interface MAC: $e");
	    }
	}
	$iftmp{physaddr} = $physaddr->id if $physaddr;
    }


    ############################################
    # Insert/Update
    my $class;
    if ( $class = ref($self) ){

	# Check if description can be overwritten
	delete $iftmp{description} if !($self->overwrite_descr) ;
	
	my $r = $self->update( \%iftmp );
	my $d = $self->device->get_label;
	if ( $r && $self->number && $self->name ){
	    $logger->debug(sub{ sprintf("%s: Interface %s (%s) updated", 
					$d, $self->number, $self->name) });
	}
    }else{
	$class = $self;
	$self = $class->insert(\%iftmp);
	my $d = $self->device->get_label;
	$logger->info(sprintf("%s: Interface %s (%s) updated", 
			      $d, $self->number, $self->name));
	
    }
    my $label = $self->get_label;
    
    ##############################################
    # Update VLANs
    #
    # Get our current vlan memberships
    # InterfaceVlan objects
    #
    if ( exists $info->{vlans} ){
	my %oldvlans;
	map { $oldvlans{$_->id} = $_ } $self->vlans();
	
	# InterfaceVlan STP fields and their methods
	my %IVFIELDS = ( stp_des_bridge => 'i_stp_bridge',
			 stp_des_port   => 'i_stp_port',
			 stp_state      => 'i_stp_state',
	    );
	
	foreach my $newvlan ( keys %{ $info->{vlans} } ){
	    my $vid   = $info->{vlans}->{$newvlan}->{vid} || $newvlan;
	    next unless $vid;
	    my $vname = $info->{vlans}->{$newvlan}->{vname};
	    my $vo;
	    my %vdata;
	    $vdata{vid}   = $vid;
	    $vdata{name}  = $vname if defined $vname;
	    if ( $vo = Vlan->search(vid => $vid)->first ){
		# update if name wasn't set (ignore default vlan 1)
		if ( !defined $vo->name && defined $vdata{name} && $vo->vid ne "1" ){
		    my $r = $vo->update(\%vdata);
		    $logger->debug(sub{ sprintf("%s: VLAN %s name updated: %s", 
						$label, $vo->vid, $vo->name) })
			if $r;
		}
	    }else{
		# create
		$vo = Vlan->insert(\%vdata);
		$logger->info(sprintf("%s: Inserted VLAN %s", $label, $vo->vid));
	    }
	    # Now verify membership
	    #
	    my %ivtmp = ( interface => $self->id, vlan => $vo->id );
	    my $iv;
	    if  ( $iv = InterfaceVlan->search( \%ivtmp )->first ){
		delete $oldvlans{$iv->id};
	    }else {
		# insert
		$iv = InterfaceVlan->insert( \%ivtmp );
		$logger->debug(sub{sprintf("%s: Assigned Interface %s (%s) to VLAN %s", 
					   $label, $self->number, $self->name, $vo->vid)});
	    }

	    # Insert STP information for this interface on this vlan
	    my $stpinst = $info->{vlans}->{$newvlan}->{stp_instance};
	    unless ( defined $stpinst ){
		$logger->debug(sub{sprintf("%s: VLAN %s not mapped to any STP instance", 
					   $label, $newvlan)});
		next;
	    }

	    my $instobj;
	    # In theory, this happens after the STP instances have been updated on this device
	    $instobj = STPInstance->search(device=>$self->device, number=>$stpinst)->first;
	    unless ( $instobj ){
		$logger->warn("$label: Cannot find STP instance $stpinst");
		next;
	    }
	    my %uargs;
	    foreach my $field ( keys %IVFIELDS ){
		my $method = $IVFIELDS{$field};
		if ( exists $args{stp_instances}->{$stpinst}->{$method} &&
		     (my $v = $args{stp_instances}->{$stpinst}->{$method}->{$info->{number}}) ){
		    $uargs{$field} = $v;
		}
	    }
	    if ( %uargs ){
		$iv->update({stp_instance=>$instobj, %uargs});
		$logger->debug(sub{ sprintf("%s: Updated STP info on VLAN %s", 
					    $label, $vo->vid) });
	    }
	}    
	# Remove each vlan membership that no longer exists
	#
	foreach my $oldvlan ( keys %oldvlans ) {
	    my $iv = $oldvlans{$oldvlan};
	    $logger->debug(sub{sprintf("%s: membership with VLAN %s no longer exists.  Removing.", 
				   $label, $iv->vlan->vid)});
	    $iv->delete();
	}
    }

    ################################################################
    # Update IPs
    #
    if ( exists( $info->{ips} ) ) {

	# For Subnet->vlan assignments
	my $vlan = 0;
	my @ivs  = $self->vlans;
	$vlan = $ivs[0]->vlan if ( scalar(@ivs) == 1 ); 

	my $name = $self->name;

	# For layer3 switches with virtual VLAN interfaces
	if ( !$vlan && $self->device->ipforwarding ){
	    my $vid;

	    if ( $name && $name =~ /Vlan(\d+)/o ){
		# This works mostly for Cisco Catalyst stuff
		$vid = $1;
	    }elsif ( $self->type eq '135' # See IF-MIB
		     && $name && $name =~ /\.(\d+)$/o ){
		# This works for Juniper stuff or anything
		# with sub-interfaces. It assumes that
		# the sub-interface number matches the VLAN id
		$vid = $1;
	    }
	    $vlan = Vlan->search(vid=>$vid)->first;
	}

	foreach my $newip ( keys %{ $info->{ips} } ){
	    if ( my $address = $info->{ips}->{$newip}->{address} ){
		my %iargs   =  (address      => $address,
				version      => $info->{ips}->{$newip}->{version},
				subnet       => $info->{ips}->{$newip}->{subnet},
				add_subnets  => $args{add_subnets},
				subs_inherit => $args{subs_inherit},
		    );
		$iargs{vlan} = $vlan if $vlan;
		if ( $self->ignore_ip ){
		    $logger->debug(sub{sprintf("%s: Ignoring IP information", $label)});
		}else{
		    $self->update_ip(%iargs);
		}
	    }
	}
    } 
    return $self;
}

############################################################################

=head2 update_ip - Update IP adddress for this interface

  Arguments:
    Hash with the following keys:
    address      - Dotted quad ip address
    version      - 4 or 6
    subnet       - Subnet CIDR
    add_subnets  - Flag.  Add subnet if necessary (only for routers)
    subs_inherit - Flag.  Have subnet inherit some Device information
    vlan         - Vlan ID (for Subnet to Vlan mapping)
    
  Returns:
    Updated Ipblock object
  Example:
    
=cut

sub update_ip {
    my ($self, %args) = @_;
    $self->isa_object_method('update_ip');

    my $address = $args{address};
    my $version = $args{version};
    $self->throw_fatal("Model::Interface::update_ip: Missing required arguments: address, version") 
	unless ( $address && $version );
    
    my $label = $self->get_label;
    
    # Do not bother with loopbacks
    if ( Ipblock->is_loopback($address) ){
	$logger->debug(sub{"$label: IP $address is a loopback. Skipping."});
	return;
    }
    
    if ( $args{subnet} ){
	$logger->debug(sub{sprintf("%s: Subnet configured in interface is %s", 
				   $label, $args{subnet})});
    }
		   
    # We might have to add a subnet
    if ( $args{add_subnets} && (my $subnet = $args{subnet}) ){
	my ($subnetaddr, $subnetprefix);
	if ( $subnet =~ /^(.+)\/(\d+)$/ ){
	    ($subnetaddr, $subnetprefix) = ($1, $2);
	}else{
	    $self->throw_fatal("Model::Interface::update_ip: Invalid subnet: $subnet");
	}

	# Make sure we compare the same formatting
	my $subnet_netaddr = Ipblock->netaddr(address=>$subnetaddr, prefix=>$subnetprefix);
	my $address_netaddr = Ipblock->netaddr(address=>$address);

	if ( $subnet_netaddr->addr ne $address_netaddr->addr || 
	     ($version == 4 && $subnetprefix == 31) ){
	    my %iargs;
	    $iargs{status} = 'Subnet' ;
	    
	    # If we have a VLAN, make the relationship
	    $iargs{vlan} = $args{vlan} if defined $args{vlan};
	    
	    if ( my $block = Ipblock->search(address => $subnetaddr, 
					     version => $version,
					     prefix  => $subnetprefix)->first ){
		
		$logger->debug(sub{ sprintf("%s: Block %s already exists", 
					    $label, $block->get_label)} );
		
		# Add description from interface if not set
		$iargs{description} = $self->description 
		    if ( !defined $block->description || $block->description eq "" );

		$iargs{last_seen} = $self->timestamp;

		# Ipblock validation might throw an exception
		eval{
		    $block->update(\%iargs);
		};
		if ( my $e = $@ ){
		    $logger->warn(sprintf("%s: Could not update block %s: %s",
					  $label, $block->get_label, $e));
		}else{
		    $logger->debug(sprintf("%s: Updated Subnet %s",
					   $label, $block->get_label));
		}
	    }else{
		if ($self->config->get('IGNORE_ORPHAN_SUBNETS') && 
		    !Ipblock->get_covering_block(address=>$subnetaddr,
						 prefix=>$subnetprefix)){

		    $logger->debug(sub{ sprintf("Ignoring orphan subnet: %s/%s.",
						$subnetaddr, $subnetprefix) });
		}else{

		    $logger->debug(sub{ sprintf("Inserting new subnet: %s/%s",
						$subnetaddr, $subnetprefix) });

		    $iargs{address}     = $subnet_netaddr->addr;
		    $iargs{prefix}      = $subnet_netaddr->masklen;
		    $iargs{version}     = $version;
		    $iargs{description} = $self->description;
		    $iargs{first_seen}  = $self->timestamp;
		    $iargs{last_seen}   = $iargs{first_seen};

		    # Check if subnet should inherit device info
		    if ( $args{subs_inherit} ){
			$iargs{owner}   = $self->device->owner;
			$iargs{used_by} = $self->device->used_by;
		    }

		    # Ipblock validation might throw an exception
		    my $newblock;
		    eval {
			$newblock = Ipblock->insert(\%iargs);
		    };
		    if ( my $e = $@ ){
			$logger->error(sprintf("%s: Could not insert Subnet %s/%s: %s",
					       $label, $subnet_netaddr->addr, $subnet_netaddr->masklen, $e));
		    }else{
			$logger->info(sprintf("%s: Created Subnet %s/%s",
					      $label, $subnetaddr, $subnetprefix));
		    }
		}
	    }
	}
    }

    # Now work on the address itself
    my $prefix  = ($version == 4)  ? 32 : 128;
    my $ipobj;
    if ( $ipobj = Ipblock->search(address => $address, 
				  prefix  => $prefix, 
				  version => $version)->first ){

	# update
	$logger->debug(sub{ sprintf("%s: IP %s/%s exists. Updating", 
				    $label, $address, $prefix) });
	
	# Notice that this is basically to confirm that the IP belongs
	# to this interface.  
	# Therefore, it's very unlikely that the object won't pass 
	# validation, so we skip it to speed things up.
	my %args = (interface => $self, validate => 0, last_seen=>$self->timestamp);
	if ( !($ipobj->status) || 
	     ($ipobj->status->name ne 'Static' && $ipobj->status->name ne 'Dynamic') ){
	    $args{status} = 'Static';
	}
	$ipobj->update(\%args);
    }else {
	# Create a new IP
	# This could also go wrong, but we don't want to bail out
	eval {
	    $ipobj = Ipblock->insert({address => $address, prefix    => $prefix, 
				      status  => "Static", interface => $self,
				      version => $version, 
				     });
	};
	if ( my $e = $@ ){
	    $logger->warn(sprintf("%s: Could not insert IP %s: %s", 
				   $label, $address, $e));
	    return;
	}else{
	    $logger->info(sprintf("%s: Inserted new IP %s", $label, $ipobj->address));
	    my $version = $ipobj->version;
	}
    }
    return $ipobj;
}

############################################################################

=head2 speed_pretty - Convert ifSpeed to something more readable

  Arguments:  
    None
  Returns:    
    Human readable speed string or n/a

=cut

sub speed_pretty {
    my ($self) = @_;
    $self->isa_object_method('speed_pretty');
    my $speed = $self->speed;

    if ( exists $SPEED_MAP{$speed} ){
	return $SPEED_MAP{$speed};
    }else{
	# ifHighSpeed (already translated to bps)
	my $fmt = "%d bps";
	if ( $speed > 9999999999999 ){
	    $fmt = "%d Tbps";
	    $speed /= 1000000000000;
	} elsif ( $speed > 999999999999 ){
	    $fmt = "%.1f Tbps";
	    $speed /= 1000000000000.0;
	} elsif ( $speed > 9999999999 ){
	    $fmt = "%d Gbps";
	    $speed /= 1000000000;
	} elsif ( $speed > 999999999 ){
	    $fmt = "%.1f Gbps";
	    $speed /= 1000000000.0;
	} elsif ( $speed > 9999999 ){
	    $fmt = "%d Mbps";
	    $speed /= 1000000;
	} elsif ( $speed > 999999 ){
	    $fmt = "%d Mbps";
	    $speed /= 1000000.0;
	} elsif ( $speed > 99999 ){
	    $fmt = "%d Kbps";
	    $speed /= 100000;
	} elsif ( $speed > 9999 ){
	    $fmt = "%d Kbps";
	    $speed /= 100000.0;
	}
	return sprintf($fmt, $speed);
    }
}

############################################################################

=head2 get_label

    Override get_label from base class

=cut

sub get_label{
    my ($self) = @_;
    $self->isa_object_method('get_label');
    return unless ( $self->id && $self->device );
    my $name = $self->name || $self->number;
    my $label = sprintf("%s [%s]", $self->device->get_label, $name);
    return $label;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut

