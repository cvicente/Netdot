package Netdot;

use lib "PREFIX/lib";
use Debug;
use Netdot::DBI;

#Be sure to return 1
1;

########################################

=head1 NAME

Netdot - Network Documentation Tool

=head1 SYNOPSIS

Netdot.pm contains a series of functions commonly used throughout Netdot's classes, 
hence the idea of grouping them in this parent class, inheritable by every other class.

=head1 METHODS
=cut
    
######################################################################
# We have two config files.  First one contains defaults
# and second one is site-specific (and optional)
# Values are stored in this base class under the 'config' key
######################################################################
    
sub _read_defaults {
    my $self = shift;
    my @files = qw( PREFIX/etc/Default.conf);
    push @files, "PREFIX/etc/Site.conf", if ( -e "PREFIX/etc/Site.conf" );
    foreach my $file (@files){
	my $config_href = do $file or die $@ || $!;
	foreach my $key ( %$config_href ) {
	    $self->{config}->{$key} = $config_href->{$key};
	}
    }
}

=head2 new

=cut

######################################################################
# Constructor
######################################################################

sub new {
   my ($proto, %argv) = @_;
   my $class = ref( $proto ) || $proto;
   my $self = {};
   bless $self, $class;

   $self->_read_defaults;

   $self->{'_logfacility'} = $argv{'logfacility'} || $self->{config}->{'DEFAULT_LOGFACILITY'},
   $self->{'_loglevel'}    = $argv{'loglevel'}    || $self->{config}->{'DEFAULT_LOGLEVEL'},
   $self->{'_logident'}    = $argv{'logident'}    || $self->{config}->{'DEFAULT_SYSLOGIDENT'},   
   $self->{'_foreground'}  = $argv{'foreground'}  || 0,   
   
   $self->{debug} = Debug->new(logfacility => $self->{'_logfacility'}, 
			       loglevel    => $self->{'_loglevel'},	  
			       logident    => $self->{'_logident'},
			       foreground  => $self->{'_foreground'},
			       );

   wantarray ? ( $self, '' ) : $self;

}


######################################################################
# STUFF for Debug.pm
######################################################################

=head2 set_loglevel - set Netdot's loglevel

   $netdot->set_loglevel( "loglevel" );

Debug messages at loglevel $loglevel or above are sent to syslog; they are
otherwise dropped.  You can use this method to change NetViewer's loglevel.
The argument is expected in the form "LOG_INFO" or "LOG_EMERG" and so on.  See
the man page for syslog for further examples.

=cut

sub set_loglevel {
  my $self = shift;
  return $self->{debug}->set_loglevel( @_ );
}

=head2 debug - send a debug message

 $netdot->debug( message => "trouble at the old mill" );

This is a frontend to the debug method in Debug.pm.

=cut

sub debug {
  my $self = shift;
  return $self->{debug}->debug( @_ );
}



######################################################################
# stuff for error messages/strings
######################################################################


=head2 error - set/return an error message.
    
    $netdot->error("Run for your lives!");

or
    
    print $netdot->error . "\n";

=cut


sub error {
    my $self = shift;
    if (@_) { $self->{'_error'} = shift }
    return $self->{'_error'};
}


######################################################################
# DB-specific stuff
######################################################################


=head2 getmeta

  $mi = $db->getmeta( $table );

When passed a table name, it searches the "Meta" table and returns the object associated
with such table.  This object then gives access to the tables metadata. 
Ideally meant to be called from other methods in this class.

=cut

sub getmeta{
    my ($self, $table) = @_;
    return (Meta->search( name => $table ))[0];
}

=head2 gettables

  @tables = $db->gettables();

Returns a list of table names found in the Meta table

=cut

sub gettables{
    my $self = shift;
    return map {$_->name} Meta->retrieve_all;
}

=head2 getlinksto

  %linksto = $db->getlinksto($table);

When passed a table name, returns a hash containing the tables one-to-many relationships, 
being this talble the "one" side (has_a definitions in Class::DBI).  
The hashs keys are the names of the local fields, and the values are the names of the tables 
that these fields reference.

=cut

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

=head2 getlinksfrom

  %linksfrom = $db->getlinksfrom($table);

When passwd a table name, returns a hash of hashes containing the tables one-to-many relationships,
being this table the "many" side (equivalent to has_many definitions in Class::DBI).
The keys of the main hash are identifiers for the relationship.  The next hashs keys are names of 
the tables that reference this table.  The values are the names of the fields in those tables that
reference this tables primary key.

=cut

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

=head2 getcolumnorder

  %order = $db->getcolumnorder($table);

Accepts a table name and returns its column names, ordered in the same order theyre supposed to be 
displayed. It returns a hash with column names as keys and their positions and values.

=cut

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

=head2 getcolumnorderbrief

  %orderbrief = $db->getcolumnorderbrief($table);

Similar to getcolumnorder().  Accepts a table name and returns the brief 
listing for that table.  The method returns a hash with column names as keys
and their positions as values.

=cut

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

=head2 getcolumntypes

  %coltypes = $db->getcolumntypes($table);

Accepts a table and returns a hash containing the SQL types for the table's columns.  The hash's
keys are the column names and the values their type.

=cut

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


=head2 getcolumntags

  %tags = $db->getcolumntags($table);

Returns a hash contaning the user-friendly display names for a tables columns

=cut

sub getcolumntags{
    my ($self, $table) = @_;
    my (%tags, $mi);
    if ( defined($mi = $self->getmeta($table)) ){
	my $mi = $self->getmeta($table);
	if( defined( $mi->columntags ) ) {
	    map { my($j, $k) = split( /:/, $_ ); $tags{$j} = $k }
	    split( /,/, $mi->columntags );	
	}
	return %tags;
    }
    return undef;
} 

=head2 getlabels

  @lbls = $db->getlabels($table);

Returns a tables list of labels.  Labels are one or more columns used as hyperlinks to retrieve 
the specified object.  Theyre also used as a meaningful instance identifier.

=cut

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

=head2 getobjlabel

  $lbl = $db->getobjlabel( $obj );
  $lbl = $db->getobjlabel( $obj, ", " );

Returns an objects label string, composed from the list of labels and the values of those labels
for this object, which might reside in more than one table.  
Accepts an object reference and a (optional) delimiter.  
Returns a string.

=cut

sub getobjlabel {
    my ($self, $obj, $delim) = @_;
    my (%linksto, @ret, @cols);
    my $table = $obj->table;
    %linksto = $self->getlinksto($table);
    @cols = $self->getlabels($table);
    foreach my $c (@cols){
	if (defined $obj->$c){
	    if ( !exists( $linksto{$c} ) ){
		push @ret, $obj->$c;
	    }else{
		push @ret, $self->getobjlabel($obj->$c, $delim);
	    }
	}
    }
    return join "$delim", @ret ;
}

=head2 getlabelarr

  @lbls = $db->getlabelarr( $table );

Returns array of labels for table. Each element is a comma delimited
string representing the labels from this table to its endpoint.

=cut

sub getlabelarr {

    my ($self, $table) = @_;
    my %linksto = $self->getlinksto($table);
    my @columns = $self->getlabels($table);
    my @ret = ();

    foreach my $col (@columns){
        if (!exists($linksto{$col})){
            push(@ret, $col);
        }else{
            my $lblString = $col . ",";
            foreach my $lbl ($self->getlabelarr($linksto{$col})){
                push(@ret, $lblString . $lbl);
            }
        }
    }
    return @ret;
}

=head2 getlabelvalue

  $lbl = $db->getlabelvalue( $obj, $lbls, $delim );

Returns actual label for this object based upon label array.
Args:
  - obj: object to find values for.
  - lbls: array of labels generated by getlabelarr().
  - delim: (optional) delimiter.

=cut

sub getlabelvalue {
    my ($self, $obj, $lbls, $delim) = @_;
    
    return "" if (!defined($obj) || int($obj) == 0);
    
    $delim = "," if (!$delim);
    my @val = ();
    foreach my $lblString (@{$lbls}){
        my $o = $obj;
        foreach my $lbl (split(/,/, $lblString)){
            $o = $o->$lbl if (defined($o->$lbl));
        }
        push(@val, $o);
    }
    return join("$delim", @val) || "";
}


=head2 getsqltype

  $type = $db->getsqltype( $table, $col );

Given a table and a column name, returns the SQL type as defined in the schema

=cut

sub getsqltype {
    my ($self, $table, $col) = @_;
    my %coltypes = $self->getcolumntypes($table);
    return $coltypes{$col};   
}

=head2 isjointable

  $flag = $db->isjointable( $table );

Check if table is a join table

=cut

sub isjointable {
    my ($self, $table) = @_;
    my $mi;
    if ( defined($mi = $self->getmeta($table)) ){
        return $mi->isjoin;
    }
    return undef;
}

=head2 getobjstate

  %state = $db->getstate( $object );

Get a hash with column/value pairs from a given object.
Useful if object needs to be restored to a previous
state.

=cut

sub getobjstate {
    my ($self, $obj) = @_;
    my %bak;
    eval {
	my $table = $obj->table;
	my @cols =  $table->columns();
	my @values = $obj->get(@cols);
	my $n = 0;
	foreach my $col (@cols){
	    $bak{$col} = $values[$n++];
	}
    };
    if ($@){
	$self->error("$@");
	return undef;
    }
    return %bak;
}


=head2 update - update a DB table row

  $result = $db->update( object => $obj, state => \%state );

Updates values for a particular row in a DB table.  Takes two arguments. 
The first argument 'object' is a Netdot::DBI (and consequently Class::DBI
) object that represents the table row you wish to update.  The second 
argument 'state' is a hash reference which is a simple composition 
of column => value pairs.  The third argument 'commit' is a flag that
will determine if the object changes are sent to the DB.  Default is Yes.
Returns positive integer representing the modified rows id column 
for success and 0 for failure.

=cut 

sub update {
    my( $self, %argv ) = @_;
    my($obj) = $argv{object};
    my(%state) = %{ $argv{state} };
    my $change = 0;
    my $table = $obj->table;
    # In some cases, user might want to discard changes later,
    # so we give the option to disable commits.
    # We will update the DB by default
    my $commit = (defined $argv{commit}) ? $argv{commit} : 1;

    foreach my $col ( keys %state ) {
	my $v = ( ref($obj->$col) ) ? $obj->$col->id : $obj->$col;
	eval { 
	    if( $state{$col} ne $v ) {
		$change = 1;
		$obj->set( $col, $state{$col} ); 
	    };
	if( $@ ) {
	    $self->error("Unable to set $col to $state{$col}: $@");
	    return 0;
	}
    }
}
    if ( $commit ){
	if( $change ) {
	    eval { $obj->update(); };
	    if( $@ ) {
		$self->error("Unable to update $table $obj: $@");
		return 0;
	    }
	}
    }
    return $obj->id;
}

=head2 insert - insert row into DB table

  $result = $db->insert( table => $tbl, state => \%state );

Inserts row into database.  Method takes two arguments.  The first 
argument 'table' is the name of the table to add a row to.  The second 
argument 'state' is a hash reference which is a simple composition 
of column => value pairs.  If the method succeeds, it returns a positive 
integer which is the value of the newly inserted rows id column. 
Otherwise, the method returns 0.

=cut

sub insert {
  my($self, %argv) = @_;
  my($tbl) = $argv{table};
  my(%state) = %{ $argv{state} };
  my $ret;
  eval { $ret = $tbl->create( \%state ); };
  if( $@ ) {
    $self->error("Unable to insert into $tbl: $@");
    return 0;
  } else {
    return $ret->id;
  }
}

=head2 remove - remove row from DB table

  $result = $db->remove( table => $tbl, id => $id );

Removes row from table $tbl with id $id.  Function takes two arguments.
The first argument is 'table', which is the name of the table a row will
be removed from.  The second argument 'id' specifies the value of the id
column.  Because id is a unique value, this will delete that specific row.
Returns 1 for success and 0 for failure.

=cut

sub remove {
  my($self, %argv) = @_;
  my($tbl) = $argv{table};
  my($id) = $argv{id};
  $self->error(undef);
  eval { 
      my($obj) = $tbl->retrieve($id);
      $obj->delete(); 
  };
  if( $@ ) {
    $self->error("Unable to delete: $@");
    return 0;
  }
  return 1;
}

=head2 insertbinfile - inserts a binary file into the DB.

  $ret = $db->insertbinfile(file, filetype);

  inserts binary object into the BinFile table. If filetype is not
  specified it will be (hopefully) determined automatically.

  Returns the id of the newly inserted row, or 0 for failure and error
  should be set.

=cut

sub insertbinfile {
    my ($self, $fh, $filetype) = @_;
    my $extension = $1 if ($fh =~ /\.(\w+)$/);
    my %mimeTypes = ("jpg"=>"image/jpeg", "jpeg"=>"image/jpeg", "gif"=>"image/gif",
                     "png"=>"image/png", "bmp"=>"image/bmp", "tiff"=>"image/tiff", 
                     "tif"=>"image/tiff", "pdf"=>"application/pdf");

    if (!exists($mimeTypes{lc($extension)})) {
        $self->error("File type could not be determined: extension \".$extension\" is unknown.");
        return 0;
    }

    my $mimetype = $mimeTypes{lc($extension)};
    my $data;
    while (<$fh>) {
        $data .= $_;
    }
    
    my %tmp;
    $tmp{bindata} = $data;
    $tmp{filename} = $fh;
    $tmp{filetype} = $mimetype;
    $tmp{filesize} = -s $fh;
    
    return $self->insert(table=>"BinFile", state=>\%tmp);
}

=head2 updatebinfile - updates a binary file in the DB.

  $ret = $db->updatebinfile(file, binfile_id);

  updates the the binary object with the specified id.

  Returns positive int on success, or 0 for failure and error
  should be set.

=cut

sub updatebinfile {
    my ($self, $fh, $id) = @_;
    my $extension = $1 if ($fh =~ /\.(\w+)$/);
    my %mimeTypes = ("jpg"=>"image/jpeg", "jpeg"=>"image/jpeg", "gif"=>"image/gif",
                     "png"=>"image/png", "bmp"=>"image/bmp", "tiff"=>"image/tiff", 
                     "tif"=>"image/tiff", "pdf"=>"application/pdf");

    if (!exists($mimeTypes{lc($extension)})) {
        $self->error("File type could not be determined for $fh: extension \".$extension\" is unknown.");
        return 0;
    }

    my $obj = BinFile->retrieve($id);
    if (!defined($obj)) {
        $self->error("Could not locate row in BinFile with id $id.");
        return 0;
    }

    my $mimetype = $mimeTypes{lc($extension)};
    my $data;
    while (<$fh>) {
        $data .= $_;
    }
    
    my %tmp;
    $tmp{bindata} = $data;
    $tmp{filename} = $fh;
    $tmp{filetype} = $mimetype;
    $tmp{filesize} = -s $fh;

    return $self->update(object=>$obj, state=>\%tmp);
}

=head2 timestamp

  $lastseen = $db->timestamp();

Get timestamp in DB 'datetime' format

=cut

sub timestamp {
    my $self  = shift;
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
	$wday, $yday, $isdst) = localtime;
    my $datetime = sprintf("%04d\/%02d\/%02d %02d:%02d:%02d",
			   $year+1900, $month+1, $day_of_month, $hours, $minutes, $seconds);
    return $datetime;
}

=head2 date

  $lastupdated = $db->date();

Get date in DB 'date' format

=cut

sub date {
    my $self  = shift;
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
	$wday, $yday, $isdst) = localtime;
    my $date = sprintf("%04d\/%02d\/%02d",
			   $year+1900, $month+1, $day_of_month);
    return $date;
}

=head2 dateserial

  $serial = $db->dateserial();

Get date in 'DNS zone serial' format

=cut

sub dateserial {
    my $self  = shift;
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
	$wday, $yday, $isdst) = localtime;
    my $date = sprintf("%04d%02d%02d",
			   $year+1900, $month+1, $day_of_month);
    return $date;
}

=head2 select_query

  $r = $db->select_query(table => $table, terms => \@terms, max => $max);

 Search keywords in a tables label fields. If label field is a foreign
 key, recursively search for same keywords in foreign table.
 If objects exist that match both keys, return those.  Otherwise, return all
 objects that match either keyword

 Arguments
   table: Name of table to look up
   terms: array ref of search terms
 Returns
   hashref of $table objects

=cut

sub select_query {
    my ($self, %args) = @_;
    my ($table, $terms) = ($args{table}, $args{terms});
    my %in; # intersection
    my %un; # union
    my %linksto = $self->getlinksto($table);
    my @labels = $self->getlabels($table);
    foreach my $c (@labels){
	if (! $linksto{$c} ){ # column is local
	    foreach my $term (@$terms){
		my $it = $table->search_like( $c => "%" . $term . "%" );
		while (my $obj = $it->next){
		    (exists $un{$obj->id})? $in{$obj->id} = $obj : $un{$obj->id} = $obj;
		}	
	    }
	}else{ # column is a foreign key.
	    my $rtable = $linksto{$c};
	    # go recursive
	    if (my $fobjs = $self->select_query( table => $rtable, terms => $terms )){
		foreach my $foid (keys %$fobjs){
		    my $it = $table->search( $c => $foid );
		    while (my $obj = $it->next){
			(exists $un{$obj->id})? $in{$obj->id} = $obj : $un{$obj->id} = $obj;
		    }
		}
	    }
	}
    }
    return (keys %in) ? \%in : \%un;
}

=head2 gethistorytable - Get the name of the history table for a given object

Arguments:  object

=cut

sub gethistorytable {
    my ($self, $o) = @_;
    my $table;
    unless ( $table = $o->table ){
        $self->error("Can't get table from object $o");
        return 0;
    }
    # For now, the only trick is appending the "_history" suffix
    return "$table" . "_history";
}

=head2 gethistoryobjs - Get a list of history objects for a given object

Arguments:  object

=cut

sub gethistoryobjs {
    my ($self, $o) = @_;
    my $table;
    unless ( $table = $o->table ){
        $self->error("Can't get table from object $o");
        return 0;
    }
    my $htable;
    unless ( $htable = $self->gethistorytable($o) ){
        $self->error("Can't get history table from object $o");
        return 0;
    }
    # History objects have two indexes, one is the necessary
    # unique index, the other one refers to which normal object
    # this is the history of
    # The latter has the table's name plus the "_id" suffix

    my $id_f = lc ("$table" . "_id");

    if ( my @ho = $htable->search($id_f => $o->id) ){
        return @ho;
    }
    return;
}

