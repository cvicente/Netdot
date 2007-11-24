package Netdot::Model::Interface;

use base 'Netdot::Model';
use warnings;
use strict;

my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();

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
=head2 update - Update Interface
    
    We override the update method for extra functionality:
      - When adding neighbor relationships, make them bi-directional
  Arguments:
    Hash ref with Interface fields
    We add an extra 'reciprocal' flag to avoid infinite loops
  Returns:
    Updated Interface object
  Example:
    $interface->update( \%data );

=cut
sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');    
    my $class = ref($self);
    my $nr = defined($argv->{reciprocal}) ? $argv->{reciprocal} : 1;

    if ( exists $argv->{neighbor} ){
	if ( $self->type ne "53" && $self->type ne "propVirtual" ){
	    my $nid = int($argv->{neighbor});
	    if ( $nid == $self->id ){
		$self->throw_user("An interface cannot be a neighbor of itself");
	    }
	    my $current_neighbor = ( $self->neighbor ) ? $self->neighbor->id : 0;
	    if ( $nid != $current_neighbor ){
		if ( $nr ){
		    if ( $nid ){
			my $neighbor = $class->retrieve($nid);
			$neighbor->update({neighbor=>$self, reciprocal=>0});
		    }else{
			# I'm basically removing my current neighbor
			# Tell the neighbor to remove me
			$self->neighbor->update({neighbor=>0, reciprocal=>0}) if ($self->neighbor);
		    }
		}
	    }
	}else{
	    $self->throw_user("Virtual interfaces cannot have neighbors");
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
    my $host  = $self->device->fqdn;
    my %iftmp;
    # Remember these are scalar refs.
    my ( $ipv4_changed, $ipv6_changed ) = @args{'ipv4_changed', 'ipv6_changed'};

    ############################################
    # Fill in standard fields
    my @stdfields = qw(number name type description speed admin_status 
		    oper_status admin_duplex oper_duplex);
    
    foreach my $field ( @stdfields ){
	$iftmp{$field} = $newif->{$field} if exists $newif->{$field};
    }


    ############################################
    # Update PhysAddr
    if ( !defined $newif->{physaddr} ){
	if ( $self->physaddr ){
	    # This seems unlikely, but...
	    $logger->info(sprintf("%s: PhysAddr %s no longer in %s.  Removing"), 
			  $self->device->fqdn, $newif->{physaddr}, $self->number);
	    $self->physaddr->delete;
	}
    }else{
	my $addr = $newif->{physaddr};
	# Check if it's valid
	if ( ! PhysAddr->validate( $addr ) ){
	    $logger->warn(sprintf("%s: Interface %s: PhysAddr: %s is not valid"),
			  $self->device->name, $self->name, $addr);
	}else{
	    # Look it up
	    my $physaddr;
	    if ( my $physaddr = PhysAddr->search(address => $addr)->first ){
		# The address exists.
		# Make sure to update the timestamp
		# and reference it from this Interface
		$physaddr->update({last_seen=>$self->timestamp});
		$logger->debug(sprintf("%s: Interface %s (%s) has existing PhysAddr: %s",
				       $self->device->fqdn, $self->number, $self->name, $addr ));
	    }else{
		# address is new.  Add it
		$physaddr = PhysAddr->insert({ address => $addr }); 
		$logger->info(sprintf("%s: Added new PhysAddr %s for Interface %s (%s)",
				      $host, $addr, $iftmp{number}, $iftmp{name})),
	    }
	    $iftmp{physaddr} = $physaddr;
	}
    }

    # Check if description can be overwritten
    delete $iftmp{description} if !($self->overwrite_descr) ;

    ############################################
    # Update

    $self->update( \%iftmp );
    
    ##############################################
    # Update VLANs
    #
    # Get our current vlan memberships
    # InterfaceVlan objects (joins)
    #
    if ( exists $newif->{vlans} ){
	my %oldvlans;
	map { $oldvlans{$_->id} = $_ } $self->vlans();
	
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
		    $vo->update(\%vdata);
		    $logger->debug(sprintf("%s: VLAN %s name updated: %s", $host, $vo->vid, $vo->name));		
		}
	    }else{
		# create
		$vo = Vlan->insert(\%vdata);
		$logger->info(sprintf("%s: Inserted VLAN %s", $host, $vo->vid));
	    }
	    # Now verify membership
	    #
	    my %ivtmp = ( interface => $self->id, vlan => $vo->id );
	    my $iv;
	    if  ( $iv = InterfaceVlan->search( \%ivtmp )->first ){
		$logger->debug(sprintf("%s: Interface %s (%s) already member of vlan %s", 
				       $host, $self->number, $self->name, $vo->vid));
		delete $oldvlans{$iv->id};
	    }else {
		# insert
		$iv = InterfaceVlan->insert( \%ivtmp );
		$logger->info(sprintf("%s: Assigned Interface %s (%s) to VLAN %s", 
				      $host, $self->number, $self->name, $vo->vid));
	    }
	}
	# Remove each vlan membership that no longer exists
	#
	foreach my $oldvlan ( keys %oldvlans ) {
	    my $iv = $oldvlans{$oldvlan};
	    $logger->info( sprintf("%s: Vlan membership %s:%s no longer exists.  Removing.", 
				   $host, $iv->interface->name, $iv->vlan->vid) );
	    $iv->delete();
	}
    }

    ################################################################
    # Update IPs
    #
    if ( exists( $newif->{ips} ) ) {
	foreach my $newip ( keys %{ $newif->{ips} } ){
	    my $address = $newif->{ips}->{$newip}->{address};
	    my $mask    = $newif->{ips}->{$newip}->{mask};
	       
	    $self->update_ip( address      => $address,
			      mask         => $mask,
			      add_subnets  => $args{add_subnets},
			      subs_inherit => $args{subs_inherit},
			      ipv4_changed => $ipv4_changed,
			      ipv6_changed => $ipv6_changed,
			      );
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

    my $host = $self->device->fqdn;
    
    my $version = ($address =~ /$IPV4/) ?  4 : 6;
    my $prefix  = ($version == 4)  ? 32 : 128;
    
    my $isrouter = 0;
    if ( defined($self->device->product) && defined($self->device->product->type->name) && 
	 $self->device->product->type->name eq "Router" ){
	$isrouter = 1;
    }
    
    # If given a mask, we might have to add subnets and stuff
    if ( my $mask = $args{mask} ){
	if ( $args{add_subnets} && $isrouter ){
	    # Create a subnet if necessary

	    my ($subnetaddr, $subnetprefix) = Ipblock->get_subnet_addr(address => $address, 
								       prefix  => $mask );
	    $logger->debug("Subnet address: $subnetaddr. Subnet prefix: $subnetprefix");

	    if ( $subnetaddr ne $address ){
		if ( my $subnet = Ipblock->search(address => $subnetaddr, 
						  prefix  => $subnetprefix)->first ){
		    
		    $logger->debug(sprintf("%s: Block %s/%s already exists", 
					   $host, $subnetaddr, $subnetprefix));
		    
		    # Make sure that the status is 'Subnet'
		    $subnet->update({status=>'Subnet'}) if ( $subnet->status->name ne 'Subnet' );

		}else{
		    # Do not bother inserting loopbacks
		    if ( Ipblock->is_loopback($subnetaddr, $subnetprefix) ){
			$logger->warn("IP $subnetaddr/$subnetprefix is a loopback. Will not insert.");
			return;
		    }
		    
		    $logger->debug(sprintf("Subnet %s/%s does not exist.  Inserting.", $subnetaddr, $subnetprefix));
		    # Prepare args for insert method
		    # IP tree will be rebuilt at the end of the Device update
		    my %iargs = ( address        => $subnetaddr, 
				  prefix         => $subnetprefix, 
				  status         => "Subnet",
				  no_update_tree => 1,
				  );
		    
		    # Check if subnet should inherit device info
		    if ( $args{subs_inherit} ){
			$iargs{owner}   = $self->device->owner;
			$iargs{used_by} = $self->device->used_by;
		    }
		    # Something might go wrong here, but we want to go on anyway
		    my $newblock;
		    eval {
			$newblock = Ipblock->insert(\%iargs);
		    };
		    if ( my $e = $@ ){
			$logger->error(sprintf("%s: Could not insert Subnet %s/%s: %s", 
					       $host, $subnetaddr, $subnetprefix, $e));
		    }else{
			$logger->info(sprintf("%s: Created Subnet %s/%s", 
					      $host, $subnetaddr, $subnetprefix));
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
    }
    
    my $ipobj;
    if ( $ipobj = Ipblock->search(address=>$address)->first ){

	# update
	$logger->debug(sprintf("%s: IP %s/%s exists. Updating", 
			      $host, $address, $prefix));
	
	# Notice that this is basically to confirm that the IP belongs
	# to this interface and that the status is set to Static.  
	# Therefore, it's very unlikely that the object won't pass 
	# validation, so we skip it to speed things up.
	eval {
	    $ipobj->update({ status     => "Static",
			     interface  => $self,
			     validate   => 0,
			 });
	};
	if ( my $e = $@ ){
	    $logger->error("$host: $e");
	    return;
	}
    }else {
	# Create a new Ip

	# Do not bother inserting loopbacks
	if ( Ipblock->is_loopback($address) ){
	    $logger->warn("IP $address is a loopback. Will not insert.");
	    return;
	}
	
	# This could also go wrong, but we don't want to bail out
	eval {
	    $ipobj = Ipblock->insert({address => $address, prefix => $prefix, 
				      status  => "Static", interface  => $self});
	};
	if ( my $e = $@ ){
	    $logger->error("$host: $e");
	    return;
	}else{
	    $logger->info(sprintf("%s: Inserted IP %s", $host, $ipobj->address));
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

