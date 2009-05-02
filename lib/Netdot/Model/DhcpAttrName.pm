package Netdot::Model::DhcpAttrName;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::DhcpAttrName - DHCP Attribute Name Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut


=head1 INSTANCE METHODS
=cut

############################################################################
=head2 as_text - Generate attribute name text

  Argsuments: 
  Returns: 
  Examples:
    
=cut
sub as_text {
    my ($self, %argv) = @_;
    
    my $out = $self->name;
    
    if ( defined $self->code && defined $self->format ){
	$out .= 'code '.$self->code.' ='.$self->format;
    }
    return $out;
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

