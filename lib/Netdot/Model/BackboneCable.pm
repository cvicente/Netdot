package Netdot::Model::BackboneCable;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::BackboneCable

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut


##################################################################
=head2 insert_strands
    
    
    Insert N number of CableStrands for a given Backbone.
  Arguments:
    - number: number of strands to insert.
  Returns:
    Number of strands inserted    
  Examples:
     $n = $bbcable->insert_strands($number_strands);

=cut
sub insert_strands {
    my ($self, $number) = @_;

    if ( $number <= 0 ) {
        $self->throw_user("Cannot insert $number strands.");
    }
    
    my $backbone_name = $self->name;
    my @cables = CableStrand->search_like(name=>$backbone_name . "%");
    my $strand_count = scalar(@cables);
    my %tmp_strands;
    $tmp_strands{cable} = $self->id;
    for (my $i = 0; $i < $number; ++$i) {
        $tmp_strands{name} = $backbone_name . "." . (++$strand_count);
        $tmp_strands{number} = $strand_count;
        CableStrand->insert(\%tmp_strands);
    }
    return $strand_count;
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

