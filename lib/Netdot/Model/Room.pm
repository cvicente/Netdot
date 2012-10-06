package Netdot::Model::Room;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::Room

=head1 SYNOPSIS

    $room->get_label()

=head1 CLASS METHODS
=cut

##################################################################

=head2 insert - Insert new object

  Arguments:
    Any of Room's fields
  Returns:
    New Room object
  Examples:
    my $room = Room->insert(\%args);

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->_validate_args($argv);
    return $class->SUPER::insert($argv);
}


=head1 INSTANCE METHODS
=cut

##################################################################

=head2 update - Update object's values

  Arguments:
    Any of Room's fields
  Returns:
    See Class::DBI's update method
  Examples:
    $room->update(\%args);

=cut

sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');
    $self->_validate_args($argv);
    return $self->SUPER::update($argv);
}

##################################################################

=head2 get_label - Override get_label method

    Combines room number and site name

  Arguments:
    None
  Returns:
    string
  Examples:
    print $room->get_label();

=cut

sub get_label {
    my $self = shift;
    $self->isa_object_method('get_label');
    if ( $self->floor && $self->floor->site ){
	return $self->name. " ". $self->floor->site->get_label;
    }else{
	return $self->name;
    }
}

##################################################################
# Private methods
##################################################################

#
# Validate args passed to insert and update 
#
sub _validate_args {
    my ($self, $argv) = @_;
    foreach my $field ( qw/floor name/ ){
	$self->throw_user("Missing required argument: $field")
	    unless ( $argv->{$field} );
    }
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
