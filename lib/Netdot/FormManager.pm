###############################################################################
# FormManger.pm
#
# Helper to (hopefully) reduce the monotony of populating forms with
# data from the DB. Plan on adding additional functionality as needed.
#
##############################################################################
package Netdot::FormManager;

use lib "/usr/local/netdot/lib"; 
use base qw( Netdot );
use Netdot::UI;
use strict;

#Be sure to return 1
1;

###############################################################################
# Constructor
###############################################################################
sub new 
{ 
    my $proto = shift;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self->{_ui} = Netdot::UI->new();
    wantarray ? ( $self, '' ) : $self; 
}


###############################################################################
# selectLookup
#
#
# TODO: Be smarter about handeling cases when lookup object might be foreign
#       key to some other table. Need to check for a link and use the label
#       from that table instead.
###############################################################################
sub selectLookup
{
    my ($self, %args) = @_;
    my ($object, $table, $column, $lookup, $default) = 
                                              ($args{object}, 
                                              $args{table}, 
                                              $args{column}, 
                                              $args{lookup},
                                              $args{default});

    my $lblField = ($self->{_ui}->getlabels($lookup))[0];
    
    #my %linksto = $self->{_ui}->getlinksto($lookup);
    #if ($linksto{$lblField})
    #{
    #    $lookup = $linksto{$lblField};
    #    $lblField = ($self->{_ui}->getlabels($lookup))[0];
    #}

    my @fo = $lookup->retrieve_all();
    @fo = sort { $a->$lblField cmp $b->$lblField } @fo;

    # if an object was passed we use it to obtain table name, id, etc
    # as well as add an initial element to the selection list.
    if ($object)
    {
        printf("<SELECT NAME=\"%s__%s__%s\">\n", $object->table, $object->id, $column);
        if ($object->$column)
        {
            printf("<OPTION VALUE=\"%s\" SELECTED>%s</OPTION>\n", $object->$column->id,
                                                                  $object->$column->$lblField);
        }

        else
        {
            printf("<OPTION VALUE=\"\" SELECTED>-- Make your selection --</OPTION>\n");
        }
    }
    # otherwise a couple of things my have happened:
    #   1) this is a new row in some table, thus we lack an object
    #      reference and need to create a new one. We rely on the supplied 
    #      "table" argument to create the fieldname, and do so with the
    #      id of "NEW" in order to force insertion when the user hits submit.
    elsif ($table)
    {
        printf("<SELECT NAME=\"%s__%s__%s\">\n", $table, "NEW", $column);
        printf("<OPTION VALUE=\"\" SELECTED>-- Make your selection --</OPTION>\n");
    }
    #   2) The apocalypse has dawned. No table argument _or_ valid DB object..lets bomb out.
    else
    {
        die("Error: Unable to determine table name. Please pass valid object and/or table name.\n");
    }

    foreach my $fo (@fo)
    {
        next if ($object && $object->$column && ($fo->id == $object->$column->id));
        printf("<OPTION VALUE=\"%s\">%s</OPTION>\n", $fo->id, $fo->name);
    }

    printf("<OPTION VALUE=\"0\">[null]</OPTION>\n");
    printf("</SELECT>\n");
}


###############################################################################
# radioGroupBoolean
#
# Simple yes/no button group.
#
###############################################################################
sub radioGroupBoolean
{
    my ($self, %args) = @_;
    my ($object, $table, $column) = ($args{object}, $args{table}, $args{column});
    my $tableName = ($object ? $object->table : $table);
    my $id = ($object ? $object->id : "NEW");
    my $value = ($object ? $object->$column : "");
    my $name = $tableName . "__" . $id . "__" . $column;
    
    die("Error: Unable to determine table name. Please pass valid object and/or table name/\n") unless ($object || $table);

    printf("<INPUT TYPE=\"RADIO\" NAME=\"%s\" VALUE=\"1\" %s>Yes &nbsp;&nbsp;\n", $name, ($value ? "CHECKED" : ""));
    printf("<INPUT TYPE=\"RADIO\" NAME=\"%s\" VALUE=\"0\" %s>No\n", $name, (!$value ? "CHECKED" : ""));
}
