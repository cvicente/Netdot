package Netdot::Model::VlanGroup;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

# Make sure to return 1
1;

=head1 NAME

Netdot::Model::Vlan::Group

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
    my $newgroup = VlanGroup->insert({name=>$name, start=>$start, end=>$end});

=cut
sub insert{
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_user('Vlan::insert: Argument variable must be hash reference')
	unless ( ref($argv) eq 'HASH' );

    $class->throw_user("Missing one or more required arguments: name, start, end")
	unless ( exists $argv->{name} && exists $argv->{start} && exists $argv->{end} );
    
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

    my @vlans = Vlan->retrieve_all();
    unless ( @vlans ){
	$logger->warn('VlanGroup::assign_all: No vlans to assign to groups');
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
    List of assigned Vlans

  Examples:
    $group->assign_vlans();

=cut
sub assign_vlans{
    my ($self) = @_;
    $self->isa_object_method('assign_vlans');

    my $vlans = Vlan->retrieve_all();
    
    # Assing vlans to this new group
    while ( my $vlan = $vlans->next ){
	if ( $vlan->vid >= $self->start && $vlan->vid <= $self->end ){
	    $vlan->update({vlangroup=>$self->id})
		unless ( $vlan->vlangroup == $self->id );
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
    
    $self->throw_user('VlanGroup::update: Argument variable must be hash reference')
	unless ref($argv) eq 'HASH';
    
    $self->_validate($argv);
    my $oldstart = $self->start;
    my $oldend   = $self->oldend;

    $self->SUPER::update($argv);

    if ( exists $argv->{start} && $argv->{start} != $oldstart || 
	 exists $argv->{end} && $argv->{end} != $oldstart ){
	$self->assign_vlans;
    }
    return $self;
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
    if ( exists $argv->{start} && exists $argv->{end} ){
	if ( $argv->{start} >= $argv->{end} ){
	    $class->throw_user("VlanGroup::_validate: start must be lower than end");
	}
	
	while ( my $g = $groups->next ){
	    # Do not compare to self
	    if ( $self && ($self->id == $g->id) ){
		next;
	    }
	    
	    # Check that ranges do not overlap
	    unless ( ($argv->{start} < $g->start && $argv->{end} < $g->start) ||
		     ($argv->{start} > $g->end && $argv->{end} > $g->end) ){
		
		$class->throw_user(sprintf("VlanGroup::_validate: New range %d - %d overlaps with Group %s",
					   $argv->{start}, $argv->{end}, $g->name));
	    }
	}
    }
    # No negative values
    if ( (exists $argv->{start} && $argv->{start} < 0) 
	 || (exists $argv->{end} && $argv->{end} < 0)  ){
	$class->throw_user("VlanGroup::_validate: Neither start nor end can be negative");
    }

    return 1;
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

