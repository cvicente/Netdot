package Netdot::Model::Contact;

use base 'Netdot::Model';
use warnings;
use strict;

=head1 NAME

Netdot::Model::Contact

=head1 INSTANCE METHODS
=cut

##################################################################

=head2 get_label - Override get_label method

  Arguments:
    None
  Returns:
    string
  Examples:
    print $contact->get_label();

=cut

sub get_label {
    my $self = shift;
    my $lbl = $self->person->get_label;
    $lbl .= ": ". $self->contacttype->name;
    return $lbl;
}

# Make sure to return 1
1;

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
