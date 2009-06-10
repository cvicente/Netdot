package Netdot::Model::AccessRight;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

# Make sure to return 1
1;

=head1 NAME

Netdot::Model::AccessRight

=head1 SYNOPSIS


=head1 INSTANCE METHODS
=cut

########################################################################
=head2 get_label - Get object label

  Arguments: 
    None
  Returns:   
    String
  Examples:
    print $accessright->get_label();

=cut
sub get_label{
    my ($self) = @_;
    $self->isa_object_method('get_label');
    if ( $self->access ){
	if ( $self->object_class && $self->object_id ){
	    my $oclass = $self->object_class;
	    my $oid  = $self->object_id;
	    my $obj_lbl = $oclass->retrieve($oid)->get_label;
	    return $self->object_class." ".$obj_lbl." - ".$self->access;
	}elsif ( $self->object_class ){
	    return $self->object_class." - ".$self->access;
	}
    }else{
	return "?";
    }
}


=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

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

