package Netdot::Model::Interface;

use base 'Netdot::Model';
use warnings;
use strict;

my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();
my $MAC  = Netdot->get_mac_regex();
my $logger = Netdot->log->get_logger('Netdot::Model::Device');

#Be sure to return 1
1;

=head1 NAME

Netdot::Model::Interface

=head1 SYNOPSIS


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
    my ($self, $argv) = @_;
    $self->isa_class_method('insert');
    
    # Set some defaults
    $argv->{speed}           ||= 0;
    $argv->{monitored}       ||= $self->config->get('IF_MONITORED');
    $argv->{snmp_managed}    ||= $self->config->get('IF_SNMP');
    $argv->{overwrite_descr} ||= $self->config->get('IF_OVERWRITE_DESCR');
    
    my $unkn = (MonitorStatus->search( name=>"Unknown" ))[0];
    $argv->{monitorstatus} = ( $unkn ) ? $unkn->id : 0;

    return $self->SUPER::insert( $argv );
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
    my $mism;
    my $dbh = $class->db_Main();
    eval {
	my $sth = $dbh->prepare_cached("SELECT i.id, r.id
                                        FROM interface i, interface r
                                        WHERE i.neighbor=r.id 
                                        AND (i.oper_duplex!=r.oper_duplex 
                                        OR ((i.speed!=0 AND r.speed!=0) AND (i.speed!=r.speed)))");
	$sth->execute();
	$mism = $sth->fetchall_arrayref;
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    # SQL returns pairs in both orders. Until I figure out how 
    # to get SQL to return unique pairs...
    if ( $mism ){
	my (%seen, @res);
	foreach my $pair ( @$mism ){
	    next if ( exists $seen{$pair->[0]} || exists $seen{$pair->[1]} );
	    push @res, $pair;
	    $seen{$pair->[0]}++;
	    $seen{$pair->[1]}++;
	}
	return \@res;
    }else{
	return;
    }
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
    
    ##################################################
    # Alert about attached circuits
    #
    my @circuits;
    map { push @circuits, $_ } $self->nearcircuits;
    map { push @circuits, $_ } $self->farcircuits;
    
    if ( scalar @circuits ){
	$logger->warn( sprintf("The following circuits are now missing one or more endpoints: %s", 
			       (join ', ', map { $_->cid } @circuits) ) );
    }
    $self->SUPER::delete();
    return 1;
}

############################################################################
=head2 add_neighbor
    
  Arguments:
    Hash with following key/value pairs:
    neighbor  - Neighbor's Interface id
    score     - Optional score obtained from Topology discovery code (for logging)
    fixed     - (bool) Whether relationship should be removed by automated processes
  Returns:
    True
  Example:
    $interface->add_neighbor($id);

=cut
sub add_neighbor{
    my ($self, %argv) = @_;
    $self->isa_object_method('add_neighbor');
    my $nid   = $argv{id}    || $self->throw_fatal("Missing required argument: id");
    my $score = $argv{score} || 'n/a';
    my $fixed = $argv{fixed} || 0;

    my $neighbor = Interface->retrieve($nid) 
	|| $self->throw_fatal("Cannot retrieve Interface id $nid");
	
    unless ( int($self->neighbor) && int($neighbor->neighbor) && 
	     $self->neighbor->id == $neighbor->id && $neighbor->neighbor->id == $self->id ){
	$logger->info(sprintf("Adding new neighbors: %s <=> %s, score: %s", 
			      $self->get_label, $neighbor->get_label, $score));
	if ( $self->neighbor && $self->neighbor_fixed ){
	    $logger->warn(sprintf("%s has been manually fixed to %s", $self->get_label, 
				  $self->neighbor->get_label));
	}elsif ( $neighbor->neighbor && $neighbor->neighbor_fixed ) {
	    $logger->warn(sprintf("%s has been manually fixed to %s", $neighbor->get_label, 
				  $neighbor->neighbor->get_label));
	}else{
	    $self->update({neighbor=>$neighbor, neighbor_fixed=>$fixed});
	}
    }
    return 1;
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
    if ( int($self->neighbor) ){
	my $nei = $self->neighbor;
	return $self->update({neighbor=>0});
    }
}

############################################################################
=head2 update - Update Interface
    
    We override the update method for extra functionality:
      - When adding neighbor relationships, make them bi-directional
  Arguments:
    Hash ref with Interface fields
    We add an extra 'reciprocal' flag to avoid infinite loops
  Returns:
    See Class::DBI::update()
  Example:
    $interface->update( \%data );

=cut
sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');    
    my $class = ref($self);
    # Neighbor updates are reciprocal unless told otherwise
    my $nr = defined($argv->{reciprocal}) ? $argv->{reciprocal} : 1;

    if ( exists $argv->{neighbor} ){
	my $nid = int($argv->{neighbor});
	if ( $nid == $self->id ){
	    $self->throw_user(sprintf("%s: interface cannot be neighbor of itself", $self->get_label));
	}
	my $current_neighbor = ( $self->neighbor ) ? $self->neighbor->id : 0;
	if ( $nid != $current_neighbor ){
	    # We might still want to set a virtual interface's neighbor to 0
	    # If we are correcting an error
	    if ( $nid ){
		if ( $self->type && ($self->type eq "53" || $self->type eq "propVirtual") ){
		    $self->throw_user(sprintf("%s: Virtual interfaces cannot have neighbors",
					      $self->get_label));
		}
	    }
	    if ( $nr ){
		if ( $nid ){
		    # Update my neighbor
		    my $neighbor = $class->retrieve($nid);
		    my %args = (neighbor=>$self, reciprocal=>0);
		    $args{neighbor_fixed} = $argv->{neighbor_fixed} if exists $argv->{neighbor_fixed};
		    $neighbor->update(\%args);
		}else{
		    # I'm basically removing my current neighbor
		    # Tell the neighbor to remove me.
		    # Also make sure the neighbor_fixed flag is off on both sides
		    if (int($self->neighbor)){
			$self->neighbor->update({neighbor=>0, neighbor_fixed=>0, reciprocal=>0});
			$logger->info(sprintf("Removing neighbors: %s <=> %s", 
					      $self->get_label, $self->neighbor->get_label));
		    }
		    $argv->{neighbor_fixed} = 0;
		}
	    }
	}
    }
    delete $argv->{reciprocal};
    return $self->SUPER::update($argv);
}

############################################################################
=head2 snmp_update - Update Interface using SNMP info

  Arguments:  
    Hash with the following keys:
    info          - Hash ref with SNMP info about interface
    add_subnets   - Whether to add subnets automatically
    subs_inherit  - Whether subnets should inherit info from the Device
    ipv4_changed  - Scalar ref.  Set if IPv4 info changes
    ipv6_changed  - Scalar ref.  Set if IPv6 info changes
    stp_instances - Hash ref with device STP info
  Returns:    
    Interface object
  Example:
    $if->snmp_update(info         => $info->{interface}->{$newif},
		     add_subnets  => $add_subnets,
		     subs_inherit => $subs_inherit,
		     ipv4_changed => \$ipv4_changed,
		     ipv6_changed => \$ipv6_changed,
		     );
=cut
sub snmp_update {
    my ($self, %args) = @_;
    $self->isa_object_method('snmp_update');
    my $class = ref($self);
    my $newif = $args{info};
    my $label  = $self->get_label;
    my %iftmp;
    # Remember these are scalar refs.
    my ( $ipv4_changed, $ipv6_changed ) = @args{'ipv4_changed', 'ipv6_changed'};

    ############################################
    # Fill in standard fields
    my @stdfields = qw( number name type description speed admin_status 
		        oper_status admin_duplex oper_duplex stp_id 
   		        bpdu_guard_enabled bpdu_filter_enabled loop_guard_enabled root_guard_enabled
                        dp_remote_id dp_remote_ip dp_remote_port dp_remote_type
                      );
    
    foreach my $field ( @stdfields ){
	$iftmp{$field} = $newif->{$field} if exists $newif->{$field};
    }

    ############################################
    # Update PhysAddr
    if ( ! $newif->{physaddr} ){
	$iftmp{physaddr} = 0;
    }else{
	my $addr = $newif->{physaddr};
	my $physaddr;
	eval {
	    $physaddr = PhysAddr->find_or_create({address=>$addr}); 
	};
	if ( my $e = $@ ){
	    $logger->debug(sprintf("%s: Could not insert PhysAddr %s: %s", 
				   $label, $addr, $e));
	}else{
	    $iftmp{physaddr} = $physaddr->id;
	}
    }
    
    # Check if description can be overwritten
    delete $iftmp{description} if !($self->overwrite_descr) ;

    ############################################
    # Update

    my $r = $self->update( \%iftmp );
    $logger->debug(sub{ sprintf("%s: Interface %s (%s) updated", 
				$label, $self->number, $self->name) }) if $r;
    

    ##############################################
    # Update VLANs
    #
    # Get our current vlan memberships
    # InterfaceVlan objects
    #
    if ( exists $newif->{vlans} ){
	my %oldvlans;
	map { $oldvlans{$_->id} = $_ } $self->vlans();
	
	# InterfaceVlan STP fields and their methods
	my %IVFIELDS = ( stp_des_bridge => 'i_stp_bridge',
			 stp_des_port   => 'i_stp_port',
			 stp_state      => 'i_stp_state',
	    );
	
	foreach my $newvlan ( keys %{ $newif->{vlans} } ){
	    my $vid   = $newif->{vlans}->{$newvlan}->{vid} || $newvlan;
	    my $vname = $newif->{vlans}->{$newvlan}->{vname};
	    my $vo;
	    my %vdata;
	    $vdata{vid}   = $vid;
	    $vdata{name}  = $vname if defined $vname;
	    if ( $vo = Vlan->search(vid => $vid)->first ){
		# update in case named changed
		# (ignore default vlan 1)
		if ( defined $vdata{name} && defined $vo->name && 
		     $vdata{name} ne $vo->name && $vo->vid ne "1" ){
		    my $r = $vo->update(\%vdata);
		    $logger->debug(sub{ sprintf("%s: VLAN %s name updated: %s", $label, $vo->vid, $vo->name) })
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
		$logger->info(sprintf("%s: Assigned Interface %s (%s) to VLAN %s", 
				      $label, $self->number, $self->name, $vo->vid));
	    }

	    # Insert STP information for this interface on this vlan
	    my $stpinst = $newif->{vlans}->{$newvlan}->{stp_instance};
	    next unless defined $stpinst;
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
		     (my $v = $args{stp_instances}->{$stpinst}->{$method}->{$newif->{number}}) ){
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
	    $logger->info( sprintf("%s: membership with VLAN %s no longer exists.  Removing.", 
				   $label, $iv->vlan->vid) );
	    $iv->delete();
	}
    }

    ################################################################
    # Update IPs
    #
    if ( exists( $newif->{ips} ) ) {

	# For SubnetVlan assignments
	my @ivs  = $self->vlans;
	my $vlan = $ivs[0]->vlan if ( scalar(@ivs) == 1 ); 
	
	foreach my $newip ( keys %{ $newif->{ips} } ){
	    if ( my $address = $newif->{ips}->{$newip}->{address} ){
		my %iargs   =  (address      => $address,
				mask         => $newif->{ips}->{$newip}->{mask},
				add_subnets  => $args{add_subnets},
				subs_inherit => $args{subs_inherit},
				ipv4_changed => $ipv4_changed,
				ipv6_changed => $ipv6_changed,
		    );
		$iargs{vlan} = $vlan if $vlan;
		$self->update_ip(%iargs);
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
    mask         - Dotted quad mask
    add_subnets  - Flag.  Add subnet if necessary (only for routers)
    subs_inherit - Flag.  Have subnet inherit some Device information
    ipv4_changed - Scalar ref.  Set if IPv4 info changes
    ipv6_changed - Scalar ref.  Set if IPv6 info changes
    vlan         - Vlan ID (for Subnet to Vlan mapping)
    
  Returns:
    Updated Ipblock object
  Example:
    
=cut
sub update_ip {
    my ($self, %args) = @_;
    $self->isa_object_method('update_ip');

    my $address = $args{address};
    $self->throw_fatal("Missing required arguments: address") unless ( $address );
    # Remember these are scalar refs.
    my ( $ipv4_changed, $ipv6_changed ) = @args{'ipv4_changed', 'ipv6_changed'};

    my $label = $self->get_label;
    
    my $version = ($address =~ /$IPV4/) ?  4 : 6;
    my $prefix  = ($version == 4)  ? 32 : 128;
    
    my $isrouter = 0;
    if ( $self->device->product_type && $self->device->product_type eq "Router" ){
	$isrouter = 1;
    }

    # If given a mask, we might have to add a subnet
    if ( (my $mask = $args{mask}) && $args{add_subnets} && $isrouter ){
	# Create a subnet if necessary
	my ($subnetaddr, $subnetprefix) = Ipblock->get_subnet_addr(address => $address, 
								   prefix  => $mask );
	
	# Do not bother with loopbacks
	if ( Ipblock->is_loopback($subnetaddr, $subnetprefix) ){
	    $logger->debug("$label: IP $subnetaddr/$subnetprefix is a loopback. Skipping.");
	    return;
	}
	
	if ( $subnetaddr ne $address ){
	    my %iargs;
	    $iargs{status} = 'Subnet' ;
	    
	    # If we have a VLAN, make the relationship
	    $iargs{vlan} = $args{vlan} if defined $args{vlan};
	    
	    # Check if subnet should inherit device info
	    if ( $args{subs_inherit} ){
		$iargs{owner}   = $self->device->owner;
		$iargs{used_by} = $self->device->used_by;
	    }

	    if ( my $subnet = Ipblock->search(address => $subnetaddr, 
					      prefix  => $subnetprefix)->first ){
		
		$logger->debug(sub{ sprintf("%s: Block %s/%s already exists", 
					    $label, $subnetaddr, $subnetprefix)} );
		
		# Skip validation for speed, since the block already exists
		$iargs{validate} = 0;

		$subnet->update(\%iargs);
	    }else{
		$logger->debug(sub{ sprintf("Subnet %s/%s does not exist.  Inserting.", $subnetaddr, $subnetprefix) });

		# IP tree will be rebuilt at the end of the Device update
		$iargs{address}        = $subnetaddr;
		$iargs{prefix}         = $subnetprefix;
		$iargs{no_update_tree} = 1;
		
		# Ipblock validation might throw an exception
		my $newblock;
		eval {
		    $newblock = Ipblock->insert(\%iargs);
		};
		if ( my $e = $@ ){
		    $logger->error(sprintf("%s: Could not insert Subnet %s/%s: %s", 
					   $label, $subnetaddr, $subnetprefix, $e));
		}else{
		    $logger->info(sprintf("%s: Created Subnet %s/%s", 
					  $label, $subnetaddr, $subnetprefix));
		    my $version = $newblock->version;
		    if ( $version == 4 ){
			$$ipv4_changed = 1;
		    }elsif ( $version == 6 ){
			$$ipv6_changed = 1;
		    }
		}
	    }
	}
    }
    
    # Do not bother with loopbacks
    if ( Ipblock->is_loopback($address) ){
	$logger->debug("$label: IP $address is a loopback. Will not insert.");
	return;
    }
	
    my $ipobj;
    if ( $ipobj = Ipblock->search(address=>$address)->first ){

	# update
	$logger->debug(sub{ sprintf("%s: IP %s/%s exists. Updating", 
				    $label, $address, $prefix) });
	
	# Notice that this is basically to confirm that the IP belongs
	# to this interface and that the status is set to Static.  
	# Therefore, it's very unlikely that the object won't pass 
	# validation, so we skip it to speed things up.
	$ipobj->update({ status     => "Static",
			 interface  => $self,
			 validate   => 0,
		       });
    }else {
	# Create a new Ip
	$logger->debug(sub{ sprintf("%s: IP %s/%s does not exist. Inserting", 
				    $label, $address, $prefix) });
	
	# This could also go wrong, but we don't want to bail out
	eval {
	    $ipobj = Ipblock->insert({address => $address, prefix => $prefix, 
				      status  => "Static", interface  => $self});
	};
	if ( my $e = $@ ){
	    $logger->debug("$label: $e");
	    return;
	}else{
	    $logger->info(sprintf("%s: Inserted IP %s", $label, $ipobj->address));
	    my $version = $ipobj->version;
	    if ( $version == 4 ){
		$$ipv4_changed = 1;
	    }elsif ( $version == 6 ){
		$$ipv6_changed = 1;
	    }
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
sub get_label{
    my ($self) = @_;
    $self->isa_object_method('get_label');
    return unless $self->id;
    my $label = sprintf("%s [%s]", $self->device->get_label, $self->name);
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 University of Oregon, all rights reserved.

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

