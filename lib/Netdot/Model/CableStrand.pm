package Netdot::Model::CableStrand;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

# Store the graph as class data to avoid recalculating
# within the same process
my $graph;

=head1 NAME

Netdot::Model::CableStrand

=head1 CLASS METHODS
=cut

##################################################################

=head2 get_graph - Returns a graph of CableStrands

    Maps cablestrands to cablestrands and sites

  Arguments:
    None
  Returns:
    Hash of hashes
  Examples:
    CableStrand->get_graph();

=cut

sub get_graph {
    my ($class) = @_;
    
    # Don't compute again if we already did in this process
    return $graph if $graph;

    my $dbh = $class->db_Main;
    my %g;
    my $q1 = "SELECT DISTINCT cs.id, s.id
              FROM   cablestrand cs, backbonecable bc, closet cl, 
                     room rm, floor fl, site s
              WHERE  cs.cable=bc.id 
                 AND (bc.start_closet=cl.id OR bc.end_closet=cl.id)
                 AND cl.room=rm.id AND rm.floor=fl.id AND fl.site=s.id";
    
    my $rows = $dbh->selectall_arrayref($q1);
    foreach my $row ( @$rows ){
	my ($csid, $sid) = @$row;
	$g{STRAND}{$csid}{$sid} = 1;
	$g{SITE}{$sid}{$csid} = 1;
    }
    
    my $q2 = "SELECT strand1, strand2 FROM splice WHERE strand1 < strand2";
    $rows = $dbh->selectall_arrayref($q2);
    foreach my $row ( @$rows ){
	my ($cs1, $cs2) = @$row;
	$g{SPLICE}{$cs1}{$cs2} = 1;
	$g{SPLICE}{$cs2}{$cs1} = 1;
    }

    $graph = \%g;
    return $graph;
}

##################################################################

=head2 find_sequences - Fetch available sequences of strands between sites

  Arguments:
    - start: id of starting Site.
    - end:   id of ending Site.
  Returns:
      Arrayref containing an arrayref for each group of strands which
      are spliced together, or which belong to a single backbone connecting
      the given sites. Each third-level arrayref contains a cable strand id
      and its name.
  Examples:
    $sequences = CableStrand->find_sequences($start, $end);

=cut

sub find_sequences {
    my ($class, $site_a, $site_b) = @_;

    return if $site_a == $site_b;
    
    # Depth-first search (recursive) subroutine 
    # returns an arrayref of cablestrand IDs
    # for each sequence of strands that goes from A to B
    sub _dfs {
	my ($g, $csid, $end, $seen, $path) = @_;
	push @$path, $csid;
	# check if this strand ends in $end
	if ( exists $g->{SITE}{$end}{$csid} ){
	    return $path;
	}else{
	    # Check if this strand is spliced
	    foreach my $cs ( sort { $a <=> $b } keys %{$g->{SPLICE}{$csid}} ){
		next if ($seen->{$csid}{$cs} || $seen->{$cs}{$csid});
		$seen->{$csid}{$cs} = 1;
		$seen->{$cs}{$csid} = 1;
		return &_dfs($g, $cs, $end, $seen, $path);
	    }
	}
	# Return undef because we did not reach $end
    }

    # Get graph structure
    my $g = $class->get_graph();

    my @seq; # Stores sequences

    # For each strand connected to A
    foreach my $csid ( sort { $a <=> $b } keys %{$g->{SITE}{$site_a}} ){
	# depth first search
	my $seen = {};
	my $path = [];
	if ( my $p = &_dfs($g, $csid, $site_b, $seen, $path) ){
	    # We have a valid path vector
	    push @seq, $class->_get_sequence_names($p);
	}
    }
    return \@seq;
}

=head1 INSTANCE METHODS
=cut

##################################################################

=head2 delete_splices
    
  Arguments:
    None
  Returns: 
    1 on success
  Examples:
    $strand->delete_splices();
    
=cut

sub delete_splices{
    my ($self) = @_;
    $self->isa_object_method('delete_splices');
    # delete all splices associated with this strand
    foreach my $splice ( $self->splices ) {
	# ...which includes deleting its inverse.
	foreach my $inv ( Splice->search(strand1=>$splice->strand2, strand2=>$splice->strand1) ) {
	    $inv->delete;
	}
	$splice->delete;
    }
    return 1;
}

##################################################################

=head2 find_endpoint

  Finds the endpoint splice for the specified strand (anything but the middle)

  Arguments:
    None
  Returns:
    CableStrand id marking the endpoint of a Splice sequence.
  Examples:
    $endpoint = $strand->find_endpoint();

=cut

sub find_endpoint {
    my ($self) = @_;
    
    # Get graph structure
    my $g = $self->get_graph();
    
    sub _fe_dfs {
	my ($g, $csid, $seen) = @_;
	foreach my $cs ( keys %{$g->{SPLICE}{$csid}} ){
	    next if ($seen->{$csid}{$cs} || $seen->{$cs}{$csid});
	    $seen->{$csid}{$cs} = 1;
	    $seen->{$cs}{$csid} = 1;
	    return $cs unless &_fe_dfs($g, $cs, $seen);
	}
    }

    my $path = [];
    my $seen = {};
    return &_fe_dfs($g, $self->id, $seen) || $self->id;
}

##################################################################

=head2 get_sequence_path

  Arguments:
    None
  Returns:
    Array of CableStrand ids in the Splice sequence (in order).
  Examples:
    my @seq_path = $strand->get_sequence_path();

=cut

sub get_sequence_path {
    my ($self) = @_;
    
    sub _gsp_dfs {
	my ($g, $csid, $seen, $path) = @_;
	foreach my $cs ( keys %{$g->{SPLICE}{$csid}} ){
	    next if ($seen->{$csid}{$cs} || $seen->{$cs}{$csid});
	    $seen->{$csid}{$cs} = 1;
	    $seen->{$cs}{$csid} = 1;
	    push @$path, $cs;
	    &_gsp_dfs($g, $cs, $seen, $path);
	}
	return $path;
    }

    # Get graph structure
    my $g = $self->get_graph();
    # Get nearest endpoint
    my $endpoint = $self->find_endpoint($self->id);
    my $path = [$endpoint]; # The path starts with this endpoint
    my $seen = {};
    my $r = &_gsp_dfs($g, $endpoint, $seen, $path);
    my @res = @$r;
    # Make the order predictable by always starting from the
    # endpoint with the lowest id value
    if ( $res[0] > $res[$#res] ){
	@res = reverse @res;
    }
    return @res;
}

##################################################################

=head2 get_sequence - Return the sequence for a given strand

  Arguments:
    None
  Returns:
    Array ref of array refs containing strand id and name
  Examples:
  my $seq = $strand->get_sequence();
=cut

sub get_sequence {
    my ($self) = @_;
    my $class = ref($self);
    $self->isa_object_method('get_sequence');
    if ( my @seq_path = $self->get_sequence_path() ){
	return $class->_get_sequence_names(\@seq_path);
    }
}


#################################################################
# Private methods
#################################################################

##################################################################
# _get_sequence_names 
#
#  Arguments:
#    Array ref containing strand ids
#  Returns:
#    Array ref of array refs containing strand id and name
#  Examples:
#  my $result = CableStrand->_get_sequence_names($seq);

sub _get_sequence_names {
    my ($class, $path) = @_;
    $class->isa_class_method('_get_sequence_names');
    return unless ( defined $path && ref($path) eq 'ARRAY' 
		    && scalar(@$path) );
    my $str = join ',', @$path;
    return unless $str;
    my $dbh = $class->db_Main;
    return $dbh->selectall_arrayref("SELECT cablestrand.id, cablestrand.name
                                     FROM   cablestrand 
                                     WHERE  cablestrand.id IN ($str)");
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

#Be sure to return 1
1;

