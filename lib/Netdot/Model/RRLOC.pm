package Netdot::Model::RRLOC;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRLOC - DNS LOC record Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut
##################################################################
=head2 as_text

    Returns the text representation of this record

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->as_text();

=cut
sub as_text {
    my $self = shift;
    $self->isa_object_method('as_text');

    return $self->_net_dns->string();
}


##################################################################
# Private methods
##################################################################


##################################################################
sub _net_dns {
    my $self = shift;

    my $ndo = Net::DNS::RR->new(
	name      => $self->rr->get_label,
	ttl       => $self->ttl,
	class     => 'IN',
	type      => 'LOC',
	version   => 0,
	size      => $self->size,
	horiz_pre => $self->horiz_pre,
	vert_pre  => $self->vert_pre,
        latitude  => $self->latitude,
	longitude => $self->longitude,
	altitude  => $self->altitude,
	);
    
    return $ndo;
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

#Be sure to return 1
1;

