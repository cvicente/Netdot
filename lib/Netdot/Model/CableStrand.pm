package Netdot::Model::CableStrand;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::CableStrand

=head1 CLASS METHODS
=cut

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
    foreach my $seq ( @$sequences ){
       foreach my $strand ( @$ ){
           printf ("ID: %d, Name: %s", $strand->id, $strand->name);
       }
    }

=cut
sub find_sequences{
    my ($class, $start, $end) = @_;
    $class->isa_class_method('find_sequences');
    $class->throw_user("Missing required arguments: start/end") 
	unless (defined $start && defined $end);
    
    my @sequences;
    my $dbh = $class->db_Main;
    eval{
	
	# Get strands from backbones connecting given sites
	my $strandsq1 = "SELECT DISTINCT cs.id, cs.name
                         FROM   cablestrand cs, backbonecable bc, 
                                closet c1, closet c2, room r1, room r2,
                                floor f1, floor f2, site a, site b
                         WHERE  cs.circuit_id IS NULL AND cs.cable=bc.id  
                           AND  a.id = $start AND b.id = $end
                           AND  c1.room=r1.id
                           AND  r1.floor=f1.id
                           AND  f1.site=a.id
                           AND  c2.room=r2.id
                           AND  r2.floor=f2.id
                           AND  f2.site=b.id
                           AND  ( (bc.start_closet=c1.id AND bc.end_closet=c2.id)
                            OR    (bc.end_closet=c1.id AND bc.start_closet=c2.id) )";

	my $rows = $dbh->selectall_arrayref($strandsq1);
	foreach my $row ( @$rows ){
	    push @sequences, [$row];
	}

	# Get strands that either start or end in given sites
	my $strands_st = $dbh->prepare_cached("SELECT DISTINCT cs.id
                                                        FROM   cablestrand cs, backbonecable bc, closet c,
                                                               room r, floor f, site s
                                                        WHERE  cs.circuit_id IS NULL AND cs.cable=bc.id  
                                                          AND  site IN (?,?)
                                                          AND  c.room=r.id
                                                          AND  r.floor=f.id
                                                          AND  f.site=s.id
                                                          AND (bc.start_closet=c.id OR bc.end_closet=c.id)");
	
	my $site_st1 = $dbh->prepare_cached("SELECT COUNT(*) 
                                             FROM   cablestrand, backbonecable, closet, room, floor
                                             WHERE  cablestrand.id = ?   
                                                AND cablestrand.cable = backbonecable.id 
                                                AND backbonecable.end_closet = closet.id 
                                                AND closet.room = room.id 
                                                AND room.floor = floor.id
                                                AND floor.site = ?");

	my $site_st2 = $dbh->prepare_cached("SELECT COUNT(*) 
                                             FROM   cablestrand, backbonecable, closet, room, floor
                                             WHERE  cablestrand.id = ? 
                                                AND cablestrand.cable = backbonecable.id 
                                                AND backbonecable.start_closet = closet.id 
                                                AND closet.room = room.id
                                                AND room.floor = floor.id
                                                AND floor.site = ?");
	
	$strands_st->execute($start, $end);
	my $i = 0;
	while ( my ($strand_id) = $strands_st->fetchrow_array() ){
	    my $strand = CableStrand->retrieve($strand_id);
	    my @seq = $strand->get_sequence_path();
	    my $end_strand;
	    if ($seq[0] == $strand_id) {
		$end_strand = $seq[scalar(@seq) - 1];
	    } elsif ($seq[scalar(@seq) - 1] == $strand_id) {
		$end_strand = $seq[0];
	    } else {
		next;
	    }
	    
	    if (($site_st1->execute($end_strand, $end) && ($site_st1->fetchrow_array())[0] != 0) ||
		($site_st2->execute($end_strand, $end) && ($site_st2->fetchrow_array())[0] != 0)) {
		my $end_strand_obj = CableStrand->retrieve($end_strand);
		push @sequences, $end_strand_obj->get_sequence();
	    }
	}
    };
    if ( my $e = $@ ){
	$class->throw_fatal("$e");
    }

    return \@sequences;
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
    $self->isa_object_method('get_sequence_path');
    my @ret;
    my $dbh = $self->db_Main;
    my $id  = $self->id;
    my $strand = $id;
    eval{
	my $st = $dbh->prepare_cached("SELECT strand2 FROM splice WHERE strand1 = ?");
	$st->execute($id);
	
	if ( $st->rows() == 0 ) {
	    push @ret, $id;
	}else{
	    $strand = $self->find_endpoint() if ( $st->rows() > 1 );
	    $st->execute($strand);
	    my $tmp_strand = ($st->fetchrow_array())[0];
	    push(@ret, $strand);
	    $st->finish();
	    $st = $dbh->prepare_cached("SELECT strand2 
                                        FROM   splice 
                                        WHERE  strand1 = ? 
                                           AND strand2 != ?");
	    while ( $st->execute($tmp_strand, $strand) && $st->rows() ){
		push(@ret, $tmp_strand);
		$strand = $tmp_strand;
		$tmp_strand = ($st->fetchrow_array())[0];
	    }
	    push(@ret, $tmp_strand) if (defined $tmp_strand);
	}
	$st->finish();
    };
    $self->throw_user("$@") if $@;
    return @ret if @ret;
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
sub find_endpoint{
    my ($self) = @_;
    $self->isa_object_method('find_endpoint');
    my ($st, $tmp_strand);
    my $dbh = $self->db_Main;
    eval{
	$st = $dbh->prepare_cached("SELECT strand2 
                                    FROM   splice 
                                    WHERE  strand1 = ?");

	return $self->id if ( $st->execute($self->id) && $st->rows() == 1 );
	
	$tmp_strand = ($st->fetchrow_array())[0];
	$st->finish();
	$st = $dbh->prepare_cached("SELECT strand2 
                                    FROM   splice 
                                    WHERE  strand1 = ? 
                                       AND strand2 <> ?");
	my $strand = $self->id;
	while ( $st->execute($tmp_strand, $strand) && $st->rows() > 1 ){
	    $strand = $tmp_strand;
	    $tmp_strand = ($st->fetchrow_array())[0];
	}
    };
    $self->throw_user("$@") if $@;
    return ($st->fetchrow_array())[0] || $tmp_strand;
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
    $self->isa_object_method('get_sequence');
    my $dbh = $self->db_Main;
    my $st;
    if ( my @seq_path = $self->get_sequence_path() ){
	my $str = join ',', @seq_path;
	return unless $str;
	eval{
	    $st = $dbh->prepare_cached("SELECT cablestrand.id, cablestrand.name
                                        FROM   cablestrand 
                                        WHERE  cablestrand.id IN ($str)");
	    $st->execute();
	};
	$self->throw_user("$@") if $@;
	return $st->fetchall_arrayref();
    }
}


=head1 AUTHOR

Kai Waldron
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

