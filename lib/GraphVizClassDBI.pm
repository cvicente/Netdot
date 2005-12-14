package GraphVizClassDBI;

# These libs are already loaded when run from within netdot
#use lib "PREFIX/lib";
#use Netdot;
use GraphViz;
use Data::Dumper;

use strict;

my $DEBUG = 0;

#"/usr/local/netdot/lib/Netdot/DBI.pm";
# print "Enter a dbi file (default: $dbi_file): ";
# chomp(my $response = <STDIN>);
# if ($response) {
#     $dbi_file = $response;
# }

# Remove history tables
# my $history = 0;
# unless ($history) {
#     @tables = grep { $_ !~ /_history$/ } @tables;
# }

# Determine the tables.  No idea how to introspect all classes
# inheriting from Netdot, so we'll parse the Class::DBI file.
#    my $parent_class = "'Netdot::DBI'";

=head1 SYNOPSIS

    my @tables = grep { $_ !~ /_history$/ } 
        get_tables("/usr/local/netdot/lib/Netdot/DBI.pm", "'Netdot::DBI'");
    make_graph(@tables)->as_gif("test.gif");

Would create a graph of the relationships between non history tables
in Netdot and write a gif image of the graph to a file called test.gif
in the current directory.

We assume that table classes have already been loaded when we are run.
This will always be the case if run inside Netdot.

=head1 METHODS

=head2 get_tables

    GraphVizClassDBI::get_tables("/usr/local/netdot/lib/Netdot/DBI.pm", "'Netdot::DBI'");

Given the name of a Class::DBI subclass(es) file and a parent class
(in the same form it appears in the Class::DBI, i.e. supply the single
quotes in 'Netdot::DBI') it returns a list of table classes.  Function
assumes the Class::DBI file is layed out like Netdot/DBI.pm.  If it
isn't you might have to grep the table names out on your own.

=cut

sub get_tables {
# Get file for determining tables
    my ($dbi_file, $parent_class) = @_;
    print "Using dbi file $dbi_file\n" if $DEBUG;
    open DBI_FILE, $dbi_file or die $!;
    my $lines = join '', (<DBI_FILE>);
    close DBI_FILE;
# Always seems to be package <Table Name>;\nuse base 'Netdot::DBI'
    my @tables = $lines =~ /package (.*?);.*?\n.*?use base $parent_class[ ]*;/g;
    return @tables;
}

=head2 make_graph

    GraphVizClassDBI::make_graph(@tables);

Given a list of Class::DBI table subclasses returns a GraphViz object
which represents the relationships between the tables.  See the
GraphViz documentation for more info, but all you probably need to
know is that the GraphViz object has as_<format>(<file name>) methods,
e.g. as_gif('graph.gif'), which write out an image of type <format> to
<file name>.

=cut

sub make_graph {
    my @tables = @_;
    print "Generating dependency graph for tables:\n\t", 
    join "\n\t", @tables if $DEBUG;
# Now build a graph.  One node for each table.
    my $g = GraphViz->new(
			  # Size in inches
			  #width => 10, height => 10,
			  # Maybe supposed to smoosh nodes together, but doesn't
			  # overlap => "compress", 
			  # Concentrate merges edges.  Ugly but saves space.
			  #concentrate => "true",
			  ); # layout => "fdp" is ok
    foreach (@tables) {
	$g->add_node("$_");
    }
# and an edge for each has a relationship.  Doesn't tell us what
# points where though.
    foreach my $table (@tables) {
	# Run Data::Dumper on meta_info if you want to make sense of this.
	my $meta = $table->meta_info->{has_a};
	foreach my $has_a (keys %$meta) {
	    # We can specify (hue, saturation, brightness) for edges and
	    # labels to make the graph a little easier to decipher.
	    my $hue = rand 1;
	    $g->add_edge($table => $meta->{$has_a}->foreign_class, 
			 label => "[1:" . $meta->{$has_a}->accessor . "]",
			 # decorate => "true", is really ugly
			 style => "bold",
			 fontcolor => "$hue,1,1",
			 color => "$hue,1,1",
			 );
	    print "$table has a @{[$meta->{$has_a}->foreign_class]} \n" if $DEBUG;
	}
	$meta = $table->meta_info->{has_many};
	foreach my $has_many (keys %$meta) {
	    # We can specify (hue, saturation, brightness) for edges and
	    # labels to make the graph a little easier to decipher.
	    my $hue = rand 1;
	    $g->add_edge($table => $meta->{$has_many}->foreign_class, 
			 label => "[M:" . $meta->{$has_many}->accessor . "]",
			 style => "filled",
			 fontcolor => "$hue,1,.5",
			 color => "$hue,1,.5",
			 );
	    print "$table has many @{[$meta->{$has_many}->foreign_class]} \n" if $DEBUG;
	}

    }
# Make a legend.
    $g->add_node("\lBold edges are has_a relationships"
		 . "\n\lRegular width edges are has_many relationships"
		 . "\n\lIn both cases the labels are the class dbi accessors"
		 . "\nand the nodes are the classes", 
		 cluster => "LEGEND", shape => "record", 
		 );
    return $g;
}


# Eats ram like crazy while viewing in `display'
#print "Building png...\n";
#$g->as_png("test.png");

# This is the one goldy locks would go for
#print "Building gif...\n" if $DEBUG;
#$g->as_gif("test.gif");

# Fuzzy
#print "Building jpeg...\n";
#$g->as_jpeg("test.jpeg");

# This is braindead
1;
