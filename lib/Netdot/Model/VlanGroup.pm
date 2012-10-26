package Netdot::Model::VlanGroup;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::VlanGroup

=head1 SYNOPSIS

Netdot Vlan Group Class

=head1 CLASS METHODS
=cut

####################################################################################

=head2 insert - Insert new VlanGroup
    
    Override the base class to:
    - Validate input
    - Assign any existing vlans to the new group if applicable

  Arguments:
    Hash ref with field/value pairs
  Returns:
    New VlanGroup object
  Examples:
    my $newgroup = VlanGroup->insert({name=>$name, start_vid=>$start, end_vid=>$end});

=cut

sub insert{
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_user('Vlan::insert: Argument variable must be hash reference')
	unless ( ref($argv) eq 'HASH' );

    $class->throw_user("Missing one or more required arguments: name, start_vid, end_vid")
	unless ( exists $argv->{name} && exists $argv->{start_vid} && exists $argv->{end_vid} );
    
    $class->_validate($argv);
    
    my $newgroup = $class->SUPER::insert($argv);
    
    $newgroup->assign_vlans;

    return $newgroup;
}

####################################################################################

=head2 assign_all - Traverse the list of vlans and assign them to groups 
    
  Arguments:
    None
  Returns:
    True if successful
  Examples:
    VlanGroup->assign_all();

=cut

sub assign_all{
    my ($class) = @_;
    $class->isa_class_method('assign_all');

    my @groups = VlanGroup->retrieve_all();
    unless ( @groups ){
	$logger->warn('VlanGroup::assign_all: No groups to assign vlans to');
	return;
    }

    foreach my $group ( @groups ){
	$group->assign_vlans;
    }

    return 1;
}

=head1 INSTANCE METHODS

=cut
####################################################################################

=head2 assign_vlans - Traverse the list of vlans and assign them to this group
    
  Arguments:
    None
  Returns:
    List of member Vlans
  Examples:
    $group->assign_vlans();

=cut

sub assign_vlans{
    my $self = shift;
    $self->isa_object_method('assign_vlans');

    # Get a list of my own vlans and index them by id
    my %myvlans;
    map { $myvlans{$_->id} = $_ } $self->vlans;

    # Assing vlans to this new group
    foreach my $vlan ( Vlan->retrieve_all ){
	if ( $vlan->vid >= $self->start_vid && $vlan->vid <= $self->end_vid ){
	    if ( !defined $vlan->vlangroup || $vlan->vlangroup != $self->id ){
		$vlan->update({vlangroup=>$self->id});
		$logger->debug(sub{ sprintf("VlanGroup: %s: Vlan %s within my range. Updating.", 
					    $self->name, $vlan->vid) });
	    }
		
	}else{
	    # Remove from my members if necessary
	    if ( exists $myvlans{$vlan->id} ){
		$logger->debug(sprintf("VlanGroup %s: Vlan %s no longer within my range. Updating.", 
				      $self->name, $vlan->vid));
		$vlan->update({vlangroup=>undef});
	    }
	}
    }
    return $self->vlans;
}

######################################################################################

=head2 update - update VlanGroup objects
    
    We override the base method to:
    - Validate input
    - Automatically assign Vlans to this VLAN group if it applies
    
  Arguments:
    hash ref with field/value pairs
  Returns:
    Updated VlanGroup object
  Examples:

=cut

sub update{
    my ($self, $argv) = @_;
    $self->isa_object_method('update');
    my $class = ref($self);
    $self->_validate($argv);

    my $oldstart = $self->start_vid;
    my $oldend   = $self->end_vid;
    my $id = $self->id;

    my $res = $self->SUPER::update($argv);
    $self = $class->retrieve($id);
    
    # For some reason, we get an empty object after updating (weird)
    # so we re-read the object from the DB to get the comparisons below to work
    if ( $self->start_vid != $oldstart || $self->end_vid != $oldend ){
 	my $name = $self->name;
 	$logger->info("VlanGroup $name: Range changed.  Reassigning VLANs.");
 	$self->assign_vlans;
    }
    return $res;
}
####################################################################################
#
# Private Methods
#
####################################################################################


####################################################################################
# _validate - Validate VlanGroup input before inserting or updating
#
#     Check that group ranges are valid and do not overlap with existing ones.
#     Can be called as instance method or class method.
#
#   Arguments:
#     Hash ref with field/value pairs
#   Returns:
#     True if successful
#   Examples:
#     VlanGroup->_validate($args);
#

sub _validate {
    my ($proto, $argv) = @_;
    my ($self, $class);
    if ( $class = ref($proto) ){
	$self = $proto;
    }else{
	$class = $proto;
    }

    # Get an iterator
    my $groups = VlanGroup->retrieve_all();

    # Check range validity
    if ( $argv->{start_vid} < 1 || $argv->{end_vid} > 4096 ){
	$class->throw_user("Invalid range: It must be within 1 and 4096");
    }
	
    if ( exists $argv->{start_vid} && exists $argv->{end_vid} ){
	if ( $argv->{start_vid} > $argv->{end_vid} ){
	    $class->throw_user("Invalid range: start must be lower or equal than end");
	}
	while ( my $g = $groups->next ){
	    # Do not compare to self
	    if ( $self && ($self->id == $g->id) ){
		next;
	    }
	    # Check that ranges do not overlap
	    unless ( ($argv->{start_vid} < $g->start_vid && $argv->{end_vid} < $g->start_vid) ||
		     ($argv->{start_vid} > $g->end_vid && $argv->{end_vid} > $g->end_vid) ){
		
		$class->throw_user(sprintf("New range: %d-%d overlaps with Group: %s",
					   $argv->{start_vid}, $argv->{end_vid}, $g->name));
	    }
	}
    }
    return 1;
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

# Make sure to return 1
1;

