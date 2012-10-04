package Netdot::Model::BackboneCable;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

# Store the graphs as class data to avoid recalculating
# within the same process
my $site_graph;
my $bb_graph;

=head1 NAME

Netdot::Model::BackboneCable

=head1 SYNOPSIS

=head1 CLASS METHODS
=cut

##################################################################

=head2 get_graph - Backbone cable to site graph

  Arguments:
    None
  Returns:
    Hash of hashes
  Examples:
    BackboneCable->get_graph();
=cut

sub get_graph {
    my ($class) = @_;

    # Don't compute again if we already did in this process
    return $bb_graph if $bb_graph;

    my $dbh = $class->db_Main;
    my %g;
    my $q = "SELECT DISTINCT bc.id, s.id
              FROM   backbonecable bc, closet cl, 
                     room rm, floor fl, site s
              WHERE  (bc.start_closet=cl.id OR bc.end_closet=cl.id)
                 AND cl.room=rm.id AND rm.floor=fl.id AND fl.site=s.id";
    
    my $rows = $dbh->selectall_arrayref($q);
    foreach my $row ( @$rows ){
	my ($bcid, $sid) = @$row;
	$g{SITE}{$sid}{$bcid} = 1;
	$g{BB}{$bcid}{$sid} = 1;
    }
    
    $bb_graph = \%g;
    return $bb_graph;
}

##################################################################

=head2 search_by_site - Search backbone cables by start and/or end sites

  Arguments:
    Hash with the following keys:
      site1 -  Site id
      site2 -  Site id 
    (at least 1 site required)
  Returns:
    Array of BackboneCable objects
  Examples:
    BackboneCable->search_by_site(site1=>$a,site2=>$b);
=cut

sub search_by_site {
    my ($class, %argv) = @_;

    my $s1 = $argv{site1};
    my $s2 = $argv{site2};
    
    $class->throw_user("At least one site is required for this search")
	unless $s1 or $s2;

    my $graph = $class->get_graph();
    my (@set1,@set2);
    @set1 = keys %{$graph->{SITE}->{$s1}} if defined $s1;
    @set2 = keys %{$graph->{SITE}->{$s2}} if defined $s2;
    
    my @res;
    if ( $s1 && $s2 ){
	if ( $s1 != $s2 ){
	    # Get intersection of sets 1 and 2
	    my %tmp; 
	    map { $tmp{$_} = 1 } @set1;
	    @res =  grep { $tmp{$_} } @set2;
	}else{
	    # backbone starts and ends in same site
	    # Get the backbone connected to this site
	    # which has only one site
	    foreach my $bb ( keys %{$graph->{SITE}->{$s1}} ){
		my @n = keys %{$graph->{BB}->{$bb}};
		if ( scalar(@n) == 1 ){
		    push @res, $bb;
		    last;
		}
	    }
	}
    }elsif ( $s1 ){
	@res = @set1;
    }elsif ( $s2 ){
	@res = @set2;
    }

    @res = map { BackboneCable->retrieve($_) } @res;
    return @res;
}

##################################################################

=head2 get_site_graph - Graph of sites connected by backbone cables

  Arguments:
    None
  Returns:
    Hash of hashes
  Examples:
    BackboneCable->get_site_graph();
=cut

sub get_site_graph {
    my ($class) = @_;

    # Don't compute again if we already did in this process
    return $site_graph if $site_graph;

    my $dbh = $class->db_Main;
    my %g;
    my $q1 = "SELECT DISTINCT s1.id, s2.id
              FROM   backbonecable bc, 
                     closet cl1, closet cl2, 
                     room rm1, room rm2, floor fl1, floor fl2, 
                     site s1, site s2
              WHERE  s1.id <= s2.id 
                 AND cl1.room=rm1.id AND rm1.floor=fl1.id AND fl1.site=s1.id
                 AND cl2.room=rm2.id AND rm2.floor=fl2.id AND fl2.site=s2.id
                 AND ((bc.start_closet=cl1.id AND bc.end_closet=cl2.id) 
                  OR (bc.end_closet=cl1.id AND bc.start_closet=cl2.id))";
    
    my $rows = $dbh->selectall_arrayref($q1);
    foreach my $row ( @$rows ){
	my ($s1, $s2) = @$row;
	$g{$s1}{$s2} = 1;
	$g{$s2}{$s1} = 1;
    }
    
    $site_graph = \%g;
    return $site_graph;
}


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

