package Netdot::Model::Vlan;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

# Make sure to return 1
1;

=head1 NAME

Netdot::Model::Vlan

=head1 SYNOPSIS

Netdot Vlan Class

=head1 CLASS METHODS
=cut

=head2 insert - insert vlan objects
    
    We override the base method to:
    - Automatically assign Vlan to a VLAN group if it applies
    
  Arguments:
    hash ref with field/value pairs
  Returns:
    New Vlan object
  Examples:
    $nevlan = Vlan->insert({vid=>'100', description=>'Vlan 100'});

=cut
######################################################################################
sub insert{
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_user("Missing required arguments: vlan id")
	unless (exists $argv->{vid});

    $argv->{vlangroup} = $class->_find_group($argv->{vid}) || 0;
    
    my $new = $class->SUPER::insert($argv);
    return $new;
}


=head1 INSTANCE METHODS
=cut

######################################################################################
=head2 update - update vlan objects
    
    We override the base method to:
    - Automatically assign Vlan to a VLAN group if needed
    
  Arguments:
    hash ref with field/value pairs
  Returns:
    Vlan object
  Examples:
    
=cut
sub update{
    my ($self, $argv) = @_;
    $self->isa_object_method('update');
    
    return $self->SUPER::update($argv);

    # We'll reassign only if vid changed and if vlangroup is not the same
    if ( exists $argv->{vid} && $argv->{vid} != $self->vid ){

	my $group = $self->_find_group($self->vid);
	$self->SUPER::update({vlangroup=>$group}) unless ( $self->vlangroup == $group->id );
    }

}
###################################################################################################
=head2 get_stp_links - Get links between devices on this vlan based on STP information

  Arguments:  
    Hashref with the following keys:
     root  - Address of Root bridge (optional)
  Returns:    
    Hashref with link info
  Example:
    my $links = $vlan->get_stp_links(root=>'DEADDEADBEEF');

=cut
sub get_stp_links {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_stp_links');
    
    my @ivs = $self->interfaces;
    # There can be multiple disconnected trees for this VLAN
    # Each set, keyed by root bridge, will include STP port
    # info for that tree
    my %sets;
    if ( $argv{root} ){
	foreach my $iv ( @ivs ){
	    if ( my $inst = $iv->stp_instance ){
		if ( $inst->root_bridge && $inst->root_bridge eq $argv{root} ){
		    push @{$sets{$argv{root}}}, $iv;
		}
	    }
	}
    }else{
	foreach my $iv ( @ivs ){
	    if ( my $inst = $iv->stp_instance ){
		if ( my $root_b = $inst->root_bridge ){
		    push @{$sets{$root_b}}, $iv;
		}
	    }
	}
    }
    
    # Run the analysis.  The designated bridge on a given segment will 
    # have its own base MAC as the designated bridge and its own STP port ID as 
    # the designated port.  The non-designated bridge will point to the 
    # designated bridge instead.
    my %links;
    foreach my $root_b ( keys %sets ){
	$logger->debug(sprintf("Vlan::get_stp_links: Determining STP topology for VLAN %s, root %s", 
			       $self->vid, $root_b));
	my (%far, %near);
	foreach my $iv ( @{$sets{$root_b}} ){
	    if ( $iv->stp_state =~ /^forwarding|blocking$/ ){
		if ( $iv->stp_des_bridge && int($iv->interface->device->physaddr) ){
		    my $des_b     = $iv->stp_des_bridge;
		    my $des_p     = $iv->stp_des_port;
		    my $int       = $iv->interface->id;
		    my $device_id = $iv->interface->device->id;
		    # Now, the trick is to determine if the MAC in the designated
		    # bridge value belongs to this same switch
		    # It can either be the base bridge MAC, or the MAC of one of the
		    # interfaces in the switch
		    my $physaddr = PhysAddr->search(address=>$des_b)->first;
		    next unless $physaddr;
		    my $des_device;
		    if ( my $dev = ($physaddr->devices)[0] ){
			$des_device = $dev->id;
		    }elsif ( (my $i = ($physaddr->interfaces)[0]) ){
			if ( my $dev = $i->device ){
			    $des_device = $dev->id ;
			}
		    }
		    # If the bridge points to itself, it is the designated bridge
		    # for the segment, which is nearest to the root
		    if ( $des_device && $device_id && $des_device == $device_id ){
			$near{$des_b}{$des_p} = $int;
		    }else{
			$far{$int}{des_p} = $des_p;
			$far{$int}{des_b} = $des_b;
		    }
		}
	    }
	}
	# Find the port in the designated bridge that is referenced by the far
	# bridge
	foreach my $int ( keys %far ){
	    my $des_b = $far{$int}{des_b};
	    my $des_p = $far{$int}{des_p};
	    if ( exists $near{$des_b} ){
		if ( exists $near{$des_b}{$des_p} ){
		    my $r_int = $near{$des_b}{$des_p};
		    $links{$int} = $r_int;
		}else{
		    # Octet representations may not match
		    foreach my $r_des_p ( keys %{$near{$des_b}} ){
			if ( $self->_cmp_des_p($r_des_p, $des_p) ){
			    my $r_int = $near{$des_b}{$r_des_p};
			    $links{$int} = $r_int;
			}
		    }
		}
	    }else{
		$logger->debug(sprintf("Vlan::get_stp_links: Designated bridge %s not found", $des_b));
	    }
	}
    }
    return \%links;
}


#########################################################################################
#
# Private methods
#
#########################################################################################
#
# Arguments:  vlan id
# Returns:    VlanGroup object if found or undef if not found
#
sub _find_group{
    my ($self, $vid) = @_;
    $self->throw_fatal("Missing required arguments: vid") 
	unless defined $vid;

    foreach my $group ( VlanGroup->retrieve_all() ){
	if ( $vid >= $group->start_vid && $vid <= $group->end_vid ){
	    return $group;
	}
    }
    return;
}

############################################################################
# Compare designated Port values
# Depending on the vendor (and the switch model within the same vendor)
# the value of dot1dStpPortDesignatedPort might be represented in different
# ways.  I ignore what the actual logic is, but some times the octets
# are swapped, and one of them may have the most significant or second to most
# significant bit turned on.  Go figure.
sub _cmp_des_p {
    my ($self, $a, $b) = @_;
    my ($aa, $ab, $ba, $bb, $x, $y);
    if ( $a =~ /(\w{2})(\w{2})/ ){
	( $aa, $ab ) = ($1, $2);
    }
    if ( $b =~ /(\w{2})(\w{2})/ ){
	( $ba, $bb ) = ($1, $2);
    }
    if ( $aa eq '00' || $aa eq '80' || $aa eq '40' ){
	$x = $ab;
    }else{
	$x = $aa;
    }
    if ( $ba eq '00' || $ba eq '80' || $ba eq '40' ){
	$y = $bb;
    }else{
	$y = $ba;
    }
    if ( $x eq $y ){
	return 1;
    }
    return 0;
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

