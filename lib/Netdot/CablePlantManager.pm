package Netdot::CablePlantManager;

=head1 NAME

Netdot::CablePlantManager - Series of functions used by the Cable Plant section for the Network Documentation Tool (Netdot).

=head1 DESCRIPTION

Netdot::UI groups common methods and variables related to Netdot's Cable Plant layer.

=head1 SYNOPSIS

  use Netdot::CablePlantManager

  $cable_manager = Netdot::CablePlantManager->new();

=cut

use lib "PREFIX/lib";

use base qw( Netdot );
use strict;

#Be sure to return 1
1;


=head1 METHODS


=head2 new

  $cable_manager = Netdot::CablePlantManager->new();

Creates a new CablePlantManager object (basic constructor)

=cut
sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new( %argv );

    wantarray ? ( $self, '' ) : $self; 
}


=head2 insertstrands

  $n = $cable_manager->insertstrands($o, $number_strands);

Insert N number of CableStrands for a given Backbone.
Args:
    - backbone: BackboneCable Class::DBI object.
    - number: number of strands to insert.

Returns the number of strands inserted, or 0 if there is a problem.

=cut
sub insertstrands($$$) {
    my ($self, $backbone, $number) = @_;

    if (!$backbone) {
        $self->error("Backbone is not defined.");
        return 0;
    }

    if ($number <= 0) {
        $self->error("Cannot insert $number strands.");
        return 0;
    }
    
    my $backbone_name = $backbone->name;
    my @cables = CableStrand->search_like(name=>$backbone_name . "%");
    my $strand_count = scalar(@cables);
    my %tmp_strands;
    $tmp_strands{cable} = $backbone->id;
    for (my $i = 0; $i < $number; ++$i) {
        $tmp_strands{name} = $backbone_name . "." . (++$strand_count);
        $tmp_strands{number} = $strand_count;
        if (!($self->insert(table=>"CableStrand", state=>\%tmp_strands))) {
            return 0;
        }
    }

    return $strand_count;
}

=head2 insertinterfaces

  $cable_manager->insertinterfaces($o, @interfaces);

Add interfaces to a HorizontalCable (jack).
Args:
   - jack: HorizontalCable object these interfaces will be associated with
   - interfaces: An array of Interface ids.

Returns: 1 on success, 0 on failure and error is set. 

=cut
sub insertinterfaces($$@) {
    my ($self, $jack, @interfaces) = @_;

    if (!defined($jack)) {
        $self->error("Unable to insert interfaces: HorizontalCable must be defined.");
        return 0;
    }

    foreach my $int (@interfaces) {
        my $int_obj = Interface->retrieve($int);
        if (!($self->update(object=>$int_obj, state=>{jack=>$jack->id, id=>$int}))) {
            return 0;
        }
    }

    return 1;
}

=head2 insertsplice

  $cable_manager->insertsplice($strand1, $strand2)

Splice together strand1 and strand2.
Args:
   - strand1, strand2: the CableStrand objects to create a splice for.

Returns: 1 on success, 0 on failure and error is set. 

=cut
sub insertsplice($$$) {
    my ($self, $strand1, $strand2) = @_;

    if (!defined($strand1) || !defined($strand2)) {
        $self->error("Strand 1 or 2 not defined.");
        return 0;
    }

    unless ( $self->insert(table=>"Splice", state=>{strand1=>$strand1->id, strand2=>$strand2->id})  
	||   $self->insert(table=>"Splice", state=>{strand1=>$strand2->id, strand2=>$strand1->id}) ){
	    return 0;
	}
    return 1;
}

=head2 deletesplices

  $cable_manager->deletesplices(@strands);

Delete splices for strands.

Args:
   - strands: an array of strands to delete splices for.

Returns: 1 on success, 0 on failure and error is set. 

=cut
sub deletesplices($@) {
    my ($self, @strands) = @_;

    foreach my $strand (@strands) {
        # delete all splices associated with this strand
        foreach my $splice ($strand->splices) {
            # ...which includes deleting its inverse.
            foreach my $inv (Splice->search(strand1=>$splice->strand2, strand2=>$splice->strand1)) {
		unless ( $self->remove(table=>"Splice", id=>$inv->id) ){
		    return 0;
		}
            }
            unless ( $self->remove(table=>"Splice", id=>$splice->id) ){
                return 0;
            }
        }
    }

    return 1;
}

=head2 assigncircuit

  $cable_manager->assigncircuit($circuit_id, @strands);

Assign a circuit to a list of strands.

Args:
   - circuit_id: the id of the Circuit these strands should be associated w/.
   - strands: an array of CableStrand ids.

=cut
sub assigncircuit($$@) {
    my ($self, $circuit_id, @strands) = @_;
    eval{
	my $st = $self->{dbh}->prepare("UPDATE CableStrand SET circuit_id = $circuit_id WHERE id = ?;");
	foreach my $strand (@strands) {
	    $st->execute($strand);
	}
	$st->finish();
    };
    if ($@){
	$self->error("$@");
	return 0;
    }
    return 1;
}

=head2 removecircuit

  $cable_manager->removecircuit(@strands);

Remove the circuit from a list of strands.

Args:
   - strands: an array of CableStrand ids.

=cut
sub removecircuit($@) {
    my ($self, @strands) = @_;
    eval{
	my $st = $self->{dbh}->prepare("UPDATE CableStrand SET circuit_id = 0 WHERE id = ?;");
	foreach my $strand (@strands) {
	    $st->execute($strand);
	}
	$st->finish();
    };
    if ($@){
	$self->error("$@");
	return 0;	
    }
    return 1;
}

=head2 findsequences

  %sequences = $cable_manager->findsequences($start, $end);

Fetch available sequences from starting to ending site.

Args:
   - start: id of starting Site.
   - end: id of ending Site.

=cut
sub findsequences($$$) {
    my ($self, $start, $end) = @_;
    my %sequences = ();
    eval{
	my $st = $self->{dbh}->prepare("SELECT id FROM Closet where site = ?;");
	$st->execute($start);
	my $closet_ids = join(",", $st->fetchrow_array());
	my $bb_st = $self->{dbh}->prepare("SELECT BackboneCable.id FROM BackboneCable WHERE 
                                       start_closet IN ($closet_ids) OR end_closet IN ($closet_ids);");
	
	my $splice_st = $self->{dbh}->prepare("SELECT CableStrand.id from CableStrand WHERE circuit_id = 0 AND cable = ?;");
	
	my $site_st1 = $self->{dbh}->prepare("SELECT COUNT(*) FROM CableStrand, BackboneCable, Closet
                                         WHERE CableStrand.id = ? AND CableStrand.cable = BackboneCable.id 
                                         AND BackboneCable.end_closet = Closet.id AND Closet.site = ?;");
	my $site_st2 = $self->{dbh}->prepare("SELECT COUNT(*) FROM CableStrand, BackboneCable, Closet
                                         WHERE CableStrand.id = ? AND CableStrand.cable = BackboneCable.id 
                                         AND BackboneCable.start_closet = Closet.id AND Closet.site = ?;");
	
	my $i = 0;
	$bb_st->execute();
	while (my ($id) = $bb_st->fetchrow_array()) {
	    $splice_st->execute($id);
	    while (my ($strand_id) = $splice_st->fetchrow_array()) {
		my @seq = $self->getsequencepath($strand_id);
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
		    $sequences{++$i} = $self->getsequence($end_strand);
		}
	    }
	}
	
	$st->finish();
	$bb_st->finish();
	$splice_st->finish();
	$site_st1->finish();
	$site_st2->finish();
    };
    if ($@){
	$self->error("$@");
	return;
    }

    return %sequences;
}

=head2 getsequence

  $cable_manager->getsequence($strand_id);

Return the sequence for a given strand id as an array ref.

Args:
    - strand: the cablestrand id.

=cut
sub getsequence($$) {
    my ($self, $strand) = @_;
    my $st;
    eval{
	$st = $self->{dbh}->prepare("SELECT CableStrand.id, CableStrand.name
                                    FROM CableStrand WHERE CableStrand.id
                                    IN (" . join(",", $self->getsequencepath($strand)) . ");");
	$st->execute();
    };
    if ($@){
	$self->error("$@");
	return;
    }
    return $st->fetchall_arrayref();
}


=head2 getsequencepath

  @seq_path = $cable_manager->getsequencepath($strand_id);

Returns: an array of CableStrand ids in the Splice sequence (in order).

Args:
    - strand: the cablestrand id.

=cut
sub getsequencepath($$) {
    my ($self, $strand) = @_;
    my @ret = ();
    eval{
	my $st = $self->{dbh}->prepare("SELECT strand2 FROM Splice WHERE strand1 = ?;");
	$st->execute($strand);
	
	if ($st->rows() == 0) {
	    $self->error("0 rows returned where CableStrand.id = $strand");
	    return 0;
	} else {
	    $strand = $self->findendpoint($strand) if ($st->rows() > 1);
	    $st->execute($strand);
	    my $tmp_strand = ($st->fetchrow_array())[0];
	    push(@ret, $strand);
	    $st->finish();
	    $st = $self->{dbh}->prepare("SELECT strand2 FROM Splice WHERE strand1 = ? AND strand2 <> ?;");
	    while ($st->execute($tmp_strand, $strand) && $st->rows()) {
		push(@ret, $tmp_strand);
		$strand = $tmp_strand;
		$tmp_strand = ($st->fetchrow_array())[0];
	    }
	    
	    push(@ret, $tmp_strand);
	}
	
	$st->finish();
    };
    if ($@){
	$self->error("$@");
	return;
    }
    return @ret;
}

=head2 findendpoint

  $endpoint = $cable_manager->findendpoint($strand_id);

Finds the endpoint splice for the specified strand (anything but the middle

Returns the CableStrand id marking the endpoint of a Splice sequence.

Args:
    - strand: the cablestrand id.

=cut
sub findendpoint($$) {
    my ($self, $strand) = @_;
    my ($st, $tmp_strand);
    eval{
	$st = $self->{dbh}->prepare("SELECT strand2 FROM Splice WHERE strand1 = ?;");
	return $strand if ($st->execute($strand) && $st->rows() == 1);
	
	$tmp_strand = ($st->fetchrow_array())[0];
	$st->finish();
	$st = $self->{dbh}->prepare("SELECT strand2 FROM Splice WHERE strand1 = ? AND strand2 <> ?;");
	while ($st->execute($tmp_strand, $strand) && $st->rows() > 1) {
	    $strand = $tmp_strand;
	    $tmp_strand = ($st->fetchrow_array())[0];
	}
    };
    if ($@){
	$self->error("$@");
	return;
    }
    
    return ($st->fetchrow_array())[0] || $tmp_strand;
}

=head2 search_circuits - Search Circuits by keywords

 Relevant fields include: CID, Connection name, Connection Sites, Connection Entity

 Arguments: string or substring
 Returns: array of Circuit objects

=cut

sub search_circuits {
    my ($self, $string) = @_;
    my $crit = "%" . $string . "%";
    my (@sites, @conn, @ent);
    my %c;  # Hash to prevent dups

    map { $c{$_} = $_ } Circuit->search_like(cid => $crit);
    @sites = Site->search_like(name => $crit);
    @conn  = Connection->search_like(name => $crit);
    @ent   = Entity->search_like(name => $crit);

    map { push @conn, $_->farconnections  } @sites;
    map { push @conn, $_->nearconnections } @sites;
    map { push @conn, $_->connections     } @ent;
    map { $c{$_} = $_ } map { $_->circuits } @conn;

    my @c = map { $c{$_} } keys %c;

    wantarray ? ( @c ) : $c[0]; 

}

