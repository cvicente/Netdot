package Netdot::GUI;

use lib "/home/netdot/public_html/lib";
use Apache::Session::File;
use Apache::Session::Lock::File;
use Netdot::DBI;
use strict;

use vars qw ( @ISA @EXPORT @EXPORT_OK ) ;
@ISA = qw( Exporter ) ;

sub BEGIN { }
sub END { }
sub DESTROY { }

use Exporter;


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
# Get a Meta object for a table
######################################################################
sub gettables{
    my $self = shift;
    return map {$_->name} Meta->retrieve_all;
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
	map { my($i, $j, $k, $args) = split( /:/, $_ ); 
	      $linksfrom{$i}{$j} = $k; 
	  }  split( /,/, $mi->linksfrom );
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
# Get a table's columns in the desired brief display order
######################################################################
sub getcolumnorderbrief {
  my ($self, $table) = @_;
  my (%order, $i, $mi);
  if ( defined($mi = $self->getmeta($table)) ){
    $i = 1;
    if( defined( $mi->columnorder ) ) {
      map { $order{$_} = $i++; } split( /,/, $mi->columnorderbrief );
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
	    push @ret, $self->getobjlabel($obj->$c, $delim);
	}
    }
    return join "$delim", @ret ;
}

######################################################################
# Get the defined SQL type for a field
######################################################################
sub getsqltype {
    my ($self, $table, $col) = @_;
    my %coltypes = $self->getcolumntypes($table);
    return $coltypes{$col};   
}

######################################################################
# Build input tag based on SQL type and other options
######################################################################
sub getinputtag {
    my ($self, $col, $proto) = @_;
    my ($class, $value);
    my $tag = "";
    if ( $class = ref $proto ){  # $proto is an object
	$value = $proto->$col;
    }else{                       # $proto is a class
	$class = $proto;
	$value = "";
    }
    
    if ($col eq "info"){
	return "<textarea name=\"$col\" rows=\"10\" cols=\"38\">$value</textarea>\n";
    }
    my $sqltype = $self->getsqltype($class,$col);
    if ($sqltype =~ /bool/){
	if ($value == 1){
	    $tag = "<input type=\"radio\" name=\"$col\" value=\"1\" checked> yes<br>";
	    $tag .= "<input type=\"radio\" name=\"$col\" value=\"0\"> no";
	}else{
	    $tag = "<input type=\"radio\" name=\"$col\" value=\"1\"> yes<br>";
	    $tag .= "<input type=\"radio\" name=\"$col\" value=\"0\" checked> no";
	}
    }elsif ($sqltype eq "date"){
	$tag = "<input type=\"text\" name=\"$col\" size=\"27\" value=\"$value\"> (YYYY-MM-DD)";
    }else{
	$tag = "<input type=\"text\" name=\"$col\" size=\"40\" value=\"$value\">";
    }
    return $tag;
}

######################################################################
# create state for a session across web pages
######################################################################
sub mksession {
  my( $self, $dir ) = @_;
  my( $sid, %session );
  tie %session, 'Apache::Session::File', 
    $sid, { Directory => $dir, LockDirectory => $dir };
  return \%session ;
}

######################################################################
# fetch state for a session across web pages
######################################################################
sub getsession {
  my( $self, $dir, $sid ) = @_;
  my %session;
  tie %session, 'Apache::Session::File', 
    $sid, { Directory => $dir, LockDirectory => $dir };
  return \%session;
}

######################################################################
# remove specific session
######################################################################
sub rmsession {
  my( $self, $session ) = @_;
  if( tied(%{ $session })->delete() ) {
    return 1;
  } else {
    return 0;
  }
}

######################################################################
# clean out old state
######################################################################
sub rmsessions {
  my( $self, $dir, $age ) = @_;
  my $locker = new Apache::Session::Lock::File ;
  if( $locker->clean( $dir, $age ) ) {
    return 1;
  } else {
    return 0;
  }
}

#Be sure to return 1
1;

######################################################################
#  $Log: GUI.pm,v $
#  Revision 1.13  2003/07/11 00:48:28  netdot
#  Added gettables method
#
#  Revision 1.12  2003/07/09 23:37:11  netdot
#  Changed getinputtag so it accepts either an object or a class
#
#  Revision 1.11  2003/07/02 23:23:44  netdot
#  more changes to state code.  should work now.
#
#  Revision 1.10  2003/07/01 17:17:53  netdot
#  more tweaking of state code
#
#  Revision 1.9  2003/07/01 17:04:54  netdot
#  added documentation
#
#  Revision 1.8  2003/07/01 05:09:48  netdot
#  renaming state functions
#
#  Revision 1.7  2003/07/01 04:53:20  netdot
#  *** empty log message ***
#
#  Revision 1.6  2003/07/01 04:48:42  netdot
#  initial merge of functions for state across web pages
#
#  Revision 1.5  2003/06/21 01:27:42  netdot
#  Fixed a bug in getobjlabel (too many parameters in the recursive call)
#
#  Revision 1.4  2003/06/13 18:23:49  netdot
#  added getcolumnorderbrief -sf
#
#  Revision 1.3  2003/06/13 18:15:34  netdot
#  added log section
#

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

=head2 gettables

Returns a list of table names

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

=head2 getcolumnorderbrief

Similar to getcolumnorder().  Accepts a table name and returns the brief 
listing for that table.  The method returns a hash with column names as keys
and their positions as values.

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

=head2 getsqltype

Given a table and a column name, returns the SQL type as defined in the schema

=head2 getinputtag
 
Given column name and object, builds an HTML <input> tag based on the sql type of the 
field and other parameters

=head2 mksession - create state for a session across multiple pages

  $dir = "/tmp";  # location for locks & state files
  $session = $gui->mksession( $dir );

Creates a state session that can be used to store data across multiple 
web pages for a given session.  Returns a hash reference to store said data
in.  Requires an argument specifying what directory to use when storing 
data (and the relevant lock files).  The session-id is 
$session{_session_id}.  Be aware that you do not want to de-ref the 
hash reference (otherwise, changes made to the subsequent hash are lost).

=head2 getsession - fetch state for a session across multiple pages

  $dir = "/tmp";  # location for locks & state files
  $sessionid = $args{sid};  # session-id must be handed off to new pages
  %session = $gui->getsession( $dir, $sessionid );

Fetches a state session and its accompanying data.  Returns a hash ref.  
Requires two arguments:  the working directory and the session-id (as 
described above).  The same warning for mksession() regarding 
de-referencing the returned object applies.

=head2 rmsession - remove state for specific session

  $gui->rmsession( \%session );

Removes specific session associated with the hash %session.

=head2 rmsessions - clear out old state

  $dir = "/tmp";
  $age = 3600;   # age is in seconds
  $gui->rmsessions( $dir, $age );

Removes state older than $age (the supplied argument) from the 
directory $dir.  Returns 1 for success and 0 for failure.  Remember, age 
is in seconds.
