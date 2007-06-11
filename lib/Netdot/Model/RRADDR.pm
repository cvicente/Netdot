package Netdot::Model::RRADDR;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 Netdot::Model::RRADDR - DNS Adress Class

RRADDR represent either A or AAAA records.

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut


############################################################################
=head2 delete - Delete object
    
    We override the delete method for extra functionality:
    - When removing an address record, most likely the RR (name)
    associated with it needs to be deleted too, unless it has
    more adddress records associated with it.

  Arguments:
    None
  Returns:
    True if successful. 
  Example:
    $rraddr->delete;

=cut

sub delete {
    my $self = shift;
    $self->isa_object_method('delete');
    my $rr = $self->rr;
    $self->SUPER::delete();
    $rr->delete() unless ( $rr->arecords || $rr->devices );

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

#Be sure to return 1
1;

