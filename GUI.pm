package Netdot::GUI;

use lib "/home/netdot/public_html/lib";
use Netdot::DBI;
use strict;

use vars qw ( @ISA @EXPORT @EXPORT_OK %inputtypes ) ;
@ISA = qw( Exporter ) ;

sub BEGIN { }
sub END { }
sub DESTROY { }

use Exporter;

@EXPORT = qw ( %inputtypes );

%inputtypes = ( varchar   => "text",
		bool      => "checkbox",
		integer   => "text",
		timestamp => "text" );

######################################################################
# Constructor
######################################################################
sub new {
    my $class = shift;
    my $self  = { };
    bless($self, $class);
    return $self;
} 

######################################################################
# Get a Meta object for a table
######################################################################
sub getmeta{
    my ($self, $table) = @_;
    return (Meta->search( name => $table ))[0];
}

######################################################################
# Get a table's has_a relationships
######################################################################
sub getlinksto{
    my ($self, $table) = @_;
    my (%linksto, $mi);
    if ( defined($mi = $self->getmeta($table)) ){
	map { my($j, $k) = split( /:/, $_ ); $linksto{$j} = $k }
	   split( /,/, $mi->linksto );
	return  %linksto;
    }
    return undef;
} 

######################################################################
# Get a table's has_many relationships
######################################################################
sub getlinksfrom{
    my ($self, $table) = @_;
    my (%linksfrom, $mi);
    if ( defined($mi = $self->getmeta($table)) ){
	map { my($i, $j, $k) = split( /:/, $_ ); $linksfrom{$i}{$j} = $k }
	   split( /,/, $mi->linksfrom );
	return %linksfrom;
    }
    return undef;
} 

######################################################################
# Get a table's columns in the desired display order
######################################################################
sub getcolumnorder{
    my ($self, $table) = @_;
    my (%order, $i, $mi);
    if ( defined($mi = $self->getmeta($table)) ){
	$i = 1;
	if( defined( $mi->columnorder ) ) {
	    map { $order{$_} = $i++; } split( /,/, $mi->columnorder );
	} else {
	    $order{"id"} = $i++;
	    foreach ( sort { $a cmp $b } $mi->name->columns() ) {
		next if( $_ eq "id" );
		$order{$_} = $i++;
	    }
	}
	return %order;
    }
    return undef;
} 

######################################################################
# Get a table's column types
######################################################################
sub getcolumntypes{
    my ($self, $table) = @_;
    my (%types, $mi);
    if ( defined($mi = $self->getmeta($table)) ){
	my $mi = $self->getmeta($table);
	if( defined( $mi->columntypes ) ) {
	    map { my($j, $k) = split( /:/, $_ ); $types{$j} = $k }
	    split( /,/, $mi->columntypes );	
	}
	return %types;
    }
    return undef;
} 

######################################################################
# Get a table's labels (columns used as instance names)
######################################################################
sub getlabels{
    my ($self, $table) = @_;
    my $mi;
    if ( defined($mi = $self->getmeta($table)) ){
	if( defined( $mi->label ) ) {
	    return split /,/, $mi->label;
	}
    }
    return undef;
} 

######################################################################
# build label string for a specific object
######################################################################
sub getobjlabel {
    my ($self, $obj, $delim) = @_;
    my (%linksto, @ret, @cols);
    my $table = ref($obj);
    %linksto = $self->getlinksto($table);
    @cols = $self->getlabels($table);
    foreach my $c (@cols){
	if ( !exists( $linksto{$c} ) ){
	    push @ret, $obj->$c;
	}else{
	    push @ret, &getobjlabel($linksto{$c}, $obj->$c, $delim);
	}
    }
    return join "$delim", @ret ;
}

#Be sure to return 1
1;

__DATA__

=head1 NAME

Netdot::GUI - Group of user interface functions for the Network Documentation Tool (Netdot)

=head1 SYNOPSIS

use Netdot::DBI

$gui = Netdot::DBI->new();  

$mi = $gui->getmeta($table);
%linksto = $gui->getlinksto($table);
%linksfrom = $gui->getlinksfrom($table);
%order = $gui->getcolumnorder($table);

=head1 DESCRIPTION

Netdot::GUI groups common methods and variables related to Netdot's user interface layer

=head1 METHODS

=head2 new

Creates a new GUI object (basic constructor)

=head2 getmeta

When passed a table name, it searches the "Meta" table and returns the object associated
with such table.  This object then gives access to the table's metadata.
Its mostly meant to be called from other methods in this class.

=head2 getlinksto

When passed a table name, returns a hash containing the table's one-to-many relationships, 
being this talble the "one" side (has_a definitions in Class::DBI).  
The hash's keys are the names of the local fields, and the values are the names of the tables 
that these fields reference.

=head2 getlinksfrom

When passwd a table name, returns a hash of hashes containing the table's one-to-many relationships,
being this table the "many" side (equivalent to has_many definitions in Class::DBI).
The keys of the main hash are identifiers for the relationship.  The next hash's keys are names of 
the tables that reference this table.  The values are the names of the fields in those tables that
reference this table's primary key.

=head2 getcolumnorder

Accepts a table name and returns its column names, ordered in the same order they're supposed to be 
displayed. It returns a hash with column names as keys and their positions and values.

=head2 getcolumntypes

Accepts a table and returns a hash containing the SQL types for the table's columns.  The hash's
keys are the column names and the values their type.

=head2 getlabels

Returns a table's list of labels.  Labels are one or more columns used as hyperlinks to retrieve 
the specified object.  They're also used as a meaningful instance identifier.

=head2 getobjlabel

Returns an object's label string, composed from the list of labels and the values of those labels
for this object, which might reside in more than one table.  Accepts an object reference and a delimiter.  
Returns a string.
