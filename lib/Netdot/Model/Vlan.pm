package Netdot::Model::Vlan;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::Vlan

=head1 SYNOPSIS

Netdot VLAN Class

=head1 CLASS METHODS
=cut

######################################################################################

=head2 insert - insert vlan objects
    
    We override the base method to:
    - Automatically assign Vlan to a VLAN group if it applies
    - Validate input

  Arguments:
    hash ref with field/value pairs
  Returns:
    New Vlan object
  Examples:
    $nevlan = Vlan->insert({vid=>'100', description=>'Vlan 100'});

=cut

sub insert{
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_user("Missing required arguments: vlan id")
	unless (exists $argv->{vid});
    $class->_validate_vid($argv->{vid});

    $argv->{vlangroup} = $class->_find_group($argv->{vid}) || undef;
    
    my $new = $class->SUPER::insert($argv);
    return $new;
}

######################################################################################

=head2 search
    
    We override the base method to:
    - Validate input
    
  Arguments:
    array
  Returns:
    See Class::DBI::search()
  Examples:
    my @vlans = Vlan->search(vid=>$number);

=cut

sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    # Class::DBI::search() might include an extra 'options' hash ref
    # at the end.  In that case, we want to extract the
    # field/value hash first.
    my @nargs = @args;
    my $opts = @nargs % 2 ? pop @nargs : {};
    my %args = @nargs;

    if (defined $args{vid}) {
        $class->_validate_vid($args{vid});
    }
    return $class->SUPER::search(@args);
}

=head1 INSTANCE METHODS
=cut

######################################################################################

=head2 update - update VLAN objects
    
    We override the base method to:
    - Validate VID
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
    
    $self->_validate_vid($argv->{vid}) if exists $argv->{vid};

    if ( exists $argv->{vid} && $argv->{vid} != $self->vid ){
	# reassign group
	$argv->{vlangroup} = $self->_find_group($argv->{vid});
    }
    return $self->SUPER::update($argv);
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


#########################################################################################
# Make sure VLAN ID is within valid range (configureable)
# Arguments:  vlan id
# Returns:    1 if successful
#
sub _validate_vid {
    my ($self, $vid) = @_;
    $self->throw_fatal("Missing required parameter: VLAN ID")
	unless $vid;
    my ($min, $max) = @{Netdot->config->get('VALID_VLAN_ID_RANGE')};
    $self->throw_user("VLAN id '$vid' is invalid. Valid range is $min - $max")
        unless ( ($vid =~ /^\d+$/) && ($vid >= $min) && ($vid <= $max) );
    1;
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

1;
