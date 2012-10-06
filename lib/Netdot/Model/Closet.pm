package Netdot::Model::Closet;

use base 'Netdot::Model';
use warnings;
use strict;
my $logger = Netdot->log->get_logger("Netdot::Model");

# Make sure to return 1
1;

=head1 NAME

Netdot::Module::Closet

=head1 CLASS METHODS

#############################################################################

=head2 insert - Inserts a closet into the DB.

  Arguments:
    Key value pairs
  Returns:
    New Closet object
  Examples:
    $newobj = Closet->insert({name=>'A', floor=>'2'});

=cut

sub insert {
    my ($self, $argv) = @_;
    
    $self->_validate($argv);
    return $self->SUPER::insert($argv);
}

=head1 INSTANCE METHODS
=cut

#############################################################################

=head2 update - Updates a closet object.

  Arguments:
    Key value pairs
  Returns:
    
  Examples:
    $closet->update({name=>'A', floor=>'2'});

=cut

sub update {
    my ($self, $argv) = @_;
    
    $self->_validate($argv);
    return $self->SUPER::update($argv);
}

###########################################################################
# PRIVATE METHODS
###########################################################################

###########################################################################
# _validate - Validate arguments before inserting/updating
#  
#    Check for required fields
#    Automatically assign site field according to floor setting

sub _validate {
    my ($self, $argv) = @_;
    if ( ref($self) ){
	$argv->{name}   = $self->name   unless ( defined $argv->{name} );
	$argv->{room} = $self->room unless ( defined $argv->{room} );
    }

    $self->throw_user("A Closet name is required")
	unless ( $argv->{name} );
    $self->throw_user("A Room/Closet number is required")
	unless ( $argv->{room} );

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

1;
