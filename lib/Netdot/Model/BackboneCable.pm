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

##################################################################
=head2 insert

  Arguments:
    Hashref with key/value pairs plus:
      - numstrands: number of strands to insert.
  Returns:
    New BackboneCable object
  Examples:
     my $bc = BackboneCable->insert(\%args);

=cut
sub insert {
    my ($class, $argv) = @_;

    my $numstrands = delete $argv->{numstrands};
    
    my $bc = $class->SUPER::insert($argv);
    
    if ( $numstrands ){
	$bc->insert_strands($numstrands);
    }
    
    return $bc;
}

=head1 INSTANCE METHODS
=cut


##################################################################
=head2 insert_strands
    
    
    Insert N number of CableStrands for a given Backbone.
  Arguments:
    - number:  Number of strands to insert.
    - type:    Type of fiber (multimode/singlemode)
    - status:  Strand Status (default: 'Not Terminated')
  Returns:
    Number of strands inserted    
  Examples:
     $n = $bbcable->insert_strands($number_strands);

=cut
sub insert_strands {
    my ($self, $number, $type, $status) = @_;

    if ( $number <= 0 ) {
        $self->throw_user("Cannot insert $number strands.");
    }
    $type   ||= FiberType->search(name=>'Multimode Fiber')->first;
    $status ||= StrandStatus->search(name=>'Not Terminated')->first;
    
    my $backbone_name = $self->name;
    my @cables = CableStrand->search_like(name=>$backbone_name . "%");
    my $strand_count = scalar(@cables);
    my %tmp_strands;
   
    $tmp_strands{cable}      = $self->id;
    $tmp_strands{fiber_type} = $type;
    $tmp_strands{status}     = $status;

    for (my $i = 0; $i < $number; ++$i) {
        $tmp_strands{name} = $backbone_name . "." . (++$strand_count);
        $tmp_strands{number} = $strand_count;
        CableStrand->insert(\%tmp_strands);
    }
    return $strand_count;
}


##################################################################
=head2 update_range - Update a range of strands

  Arguments:
    Hash with fields/values plus:
    - start: id of starting strand.
    - end:   id of ending strand.
  Returns:
    True
  Examples:
     $bbcable->update_range(%argv);

=cut
sub update_range{
    my ($self, %argv) = @_;
    $self->isa_object_method('update_range');
    $self->throw_user("Missing required arguments: start/end") 
	unless ($argv{start} && $argv{end});

    my $start = delete $argv{start};
    my $end   = delete $argv{end};

    for ( my $i=$start; $i<=$end; $i++ ){
	if ( my $strand = CableStrand->search(cable=>$self, number=>$i)->first ){
	    $strand->update(\%argv);
	}else{
	    $self->throw_user("Cannot find strand $i in this backbone");
	}
    }
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

