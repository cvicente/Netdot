package Netdot::CablePlantManager;

use lib "PREFIX/lib";

use base qw( Netdot );
use Netdot::DBI;
use Netdot::UI;
use strict;

#Be sure to return 1
1;


###############################################################################
# Constructor
###############################################################################
sub new 
{ 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    wantarray ? ( $self, '' ) : $self; 
    $self = $self->SUPER::new( %argv );
    wantarray ? ( $self, '' ) : $self; 
}

###############################################################################
# Insert N number of CableStrands for a given Backbone.
# Args:
#   - backbone: BackboneCable Class::DBI object.
#   - number: number of strands to insert.
#
# Returns: the number of strands inserted or 0 if there is a problem.
###############################################################################
sub insertstrands($$$)
{
    my ($self, $backbone, $number) = @_;

    if (!$backbone)
    {
        $self->error("Backbone is not defined.");
        return 0;
    }

    if ($number <= 0)
    {
        $self->error("Cannot insert $number strands.");
        return 0;
    }
    
    my $backbone_name = $backbone->name;
    my @cables = CableStrand->search_like(name=>$backbone_name . "%");
    my $strand_count = scalar(@cables);
    my %tmp_strands;
    $tmp_strands{cable} = $backbone->id;
    my $ui = Netdot::UI->new();
    for (my $i = 0; $i < $number; ++$i)
    {
        $tmp_strands{name} = $backbone_name . "." . (++$strand_count);
        $tmp_strands{number} = $strand_count;
        if (!($ui->insert(table=>"CableStrand", state=>\%tmp_strands)))
        {
            $self->error($ui->error());
            return 0;
        }
    }

    return $strand_count;
}

###############################################################################
# Insert interfaces. 
# Args:
#   - jack: HorizontalCable object these interfaces will be associated with
#   - interfaces: An array of Interface ids.
#
# Returns: 1 on success, 0 on failure and error is set. 
###############################################################################
sub insertinterfaces($$@)
{
    my ($self, $jack, @interfaces) = @_;

    if (!defined($jack))
    {
        $self->error("Unable to insert interfaces: HorizontalCable must be defined.");
        return 0;
    }

    my $ui = Netdot::UI->new();
    foreach my $int (@interfaces)
    {
        my $int_obj = Interface->retrieve($int);
        if (!($ui->update(object=>$int_obj, state=>{jack=>$jack->id, id=>$int})))
        {
            $self->error($ui->error());
            return 0;
        }
    }

    return 1;
}

###############################################################################
# Insert splice
# Args:
#   - strand1, strand2: the CableStrand objects to create a splice for.
#
# Returns: 1 on success, 0 on failure and error is set.
###############################################################################
sub insertsplice($$$)
{
    my ($self, $strand1, $strand2) = @_;

    if (!defined($strand1) || !defined($strand2))
    {
        $self->error("Strand 1 or 2 not defined.");
        return 0;
    }

    my $ui = Netdot::UI->new();
    $self->error($ui->error()) if (!($ui->insert(table=>"Splice", state=>{strand1=>$strand1->id, 
                                                                          strand2=>$strand2->id})));
    $self->error($ui->error()) if (!($ui->insert(table=>"Splice", state=>{strand1=>$strand2->id, 
                                                                          strand2=>$strand1->id})));

    return $self->error() ? 0 : 1;
}


###############################################################################
# Delete splices of cable strands
# Args:
#   - strands: array of strands to remove splices for.
#
# Returns: 1 on success, 0 on failure and error is set.
###############################################################################
sub deletesplices($@)
{
    my ($self, @strands) = @_;
    my $ui = Netdot::UI->new();

    foreach my $strand (@strands)
    {
        # delete all splices associated with this strand
        foreach my $splice ($strand->splices)
        {
            # ...which includes deleting its inverse.
            foreach my $obj (Splice->search(strand1=>$splice->strand2, strand2=>$splice->strand1))
            {
                eval { $obj->delete(); };
                if ($@) 
                {
                    $self->error("Unable to delete splice: $@");
                    return 0;
                }
            }
            
            if (!($ui->remove(table=>"Splice", id=>$splice->id)))
            {
                $self->error($ui->error());
                return 0;
            }
        }
    }

    return 1;
}
