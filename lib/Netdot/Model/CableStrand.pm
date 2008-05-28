package Netdot::Model::CableStrand;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::CableStrand

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

##################################################################
=head2 findsequences - Fetch available sequences between sites

  Arguments:
    - start: id of starting Site.
    - end:   id of ending Site.
  Returns:
      Hash
  Examples:
    %sequences = CableStrand->find_sequences($start, $end);

=cut
sub find_sequences{
    my ($class, $start, $end) = @_;
    $class->isa_class_method('find_sequences');
    $class->throw_user("Missing required arguments: start/end") 
	unless (defined $start && defined $end);
    
    my %sequences = ();
    my $dbh = $class->db_Main;
    eval{
	my $st = $dbh->prepare_cached("SELECT id 
                                       FROM   closet 
                                       WHERE  site = ?");
	$st->execute($start);
	my $closet_ids = join(",", $st->fetchrow_array());
	
	my $bb_st = $dbh->prepare_cached("SELECT backbonecable.id 
                                          FROM   backbonecable 
                                          WHERE  start_closet IN ($closet_ids) 
                                              OR end_closet IN ($closet_ids)");
	
	my $splice_st = $dbh->prepare_cached("SELECT cablestrand.id 
                                              FROM   cablestrand 
                                              WHERE  circuit_id = 0 
                                                 AND cable = ?");
	
	my $site_st1 = $dbh->prepare_cached("SELECT COUNT(*) 
                                             FROM   cablestrand, backbonecable, closet
                                             WHERE  cablestrand.id = ?   
                                                AND cablestrand.cable = backbonecable.id 
                                                AND backbonecable.end_closet = closet.id 
                                                AND closet.site = ?");

	my $site_st2 = $dbh->prepare_cached("SELECT COUNT(*) 
                                             FROM   cablestrand, backbonecable, closet
                                             WHERE  cablestrand.id = ? 
                                                AND cablestrand.cable = backbonecable.id 
                                                AND backbonecable.start_closet = closet.id 
                                                AND closet.site = ?");
	
	my $i = 0;
	$bb_st->execute();
	while ( my ($id) = $bb_st->fetchrow_array() ) {
	    $splice_st->execute($id);
	    while ( my ($strand_id) = $splice_st->fetchrow_array() ){
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
		    $sequences{++$i} = $end_strand_obj->get_sequence();
		}
	    }
	}
	
	$st->finish();
	$bb_st->finish();
	$splice_st->finish();
	$site_st1->finish();
	$site_st2->finish();
    };
    $class->throw_user("$@") if ($@);

    return %sequences;
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
    eval{
	my $st = $dbh->prepare_cached("SELECT strand2 FROM splice WHERE strand1 = ?");
	$st->execute($id);
	
	if ( $st->rows() == 0 ) {
	    return;
	}else{
	    my $strand = $self->find_endpoint() if ( $st->rows() > 1 );
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
    Array ref
  Examples:
  $strand->get_sequence();
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

