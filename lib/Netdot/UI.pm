package Netdot::UI;

=head1 NAME

Netdot::UI - Group of user interface functions for the Network Documentation Tool (Netdot)

=head1 DESCRIPTION

Netdot::UI groups common methods and variables related to Netdot's user interface layer

=head1 SYNOPSIS

  use Netdot::UI

  $ui = Netdot::UI->new();  

  $mi = $ui->getmeta($table);
  %linksto = $ui->getlinksto($table);
  %linksfrom = $ui->getlinksfrom($table);
  %order = $ui->getcolumnorder($table);

=cut

use lib "PREFIX/lib";
use Apache::Session::File;
use Apache::Session::Lock::File;

use base qw( Netdot );
use strict;
use Data::Dumper;

#Be sure to return 1
1;

=head1 METHODS


=head2 new

  $ui = Netdot::UI->new();

Creates a new UI object (basic constructor)

=cut

sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new( %argv );

    $self->{ipm} = Netdot::IPManager->new();

    wantarray ? ( $self, '' ) : $self; 
}
 

=head2 getmeta

  $mi = $ui->getmeta( $table );

When passed a table name, it searches the "Meta" table and returns the object associated
with such table.  This object then gives access to the tables metadata. 
Ideally meant to be called from other methods in this class.

=cut

sub getmeta{
    my ($self, $table) = @_;
    return (Meta->search( name => $table ))[0];
}

=head2 gettables

  @tables = $ui->gettables();

Returns a list of table names found in the Meta table

=cut

sub gettables{
    my $self = shift;
    return map {$_->name} Meta->retrieve_all;
}

=head2 getlinksto

  %linksto = $ui->getlinksto($table);

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

  %linksfrom = $ui->getlinksfrom($table);

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

  %order = $ui->getcolumnorder($table);

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

  %orderbrief = $ui->getcolumnorderbrief($table);

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

  %coltypes = $ui->getcolumntypes($table);

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

  %tags = $ui->getcolumntags($table);

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

  @lbls = $ui->getlabels($table);

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

  $lbl = $ui->getobjlabel( $obj );
  $lbl = $ui->getobjlabel( $obj, ", " );

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

  @lbls = $ui->getlabelarr( $table );

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

  $lbl = $ui->getlabelvalue( $obj, $lbls, $delim );

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

  $type = $ui->getsqltype( $table, $col );

Given a table and a column name, returns the SQL type as defined in the schema

=cut

sub getsqltype {
    my ($self, $table, $col) = @_;
    my %coltypes = $self->getcolumntypes($table);
    return $coltypes{$col};   
}

=head2 isjointable

  $flag = $ui->isjointable( $table );

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

=head2 getinputtag

  $inputtag = $ui->getinputtag( $col, $obj );
  $inputtag = $ui->getinputtag( $col, $table );
  $inputtag = $ui->getinputtag( $col, $table, $arg );

Accepts column name and object (or table name) and builds an HTML <input> tag based on the SQL type of the 
field and other parameters.  When specifying a table name, the caller has the option to pass
a value to be displayed in the tag.

=cut

sub getinputtag {
    my ($self, $col, $proto, $value) = @_;
    my $class;
    my $tag = "";
    if ( $class = ref $proto ){  # $proto is an object
	if ( defined($value) ){
	    $self->error("getinputtag: Can't supply a value for an existing object\n");
	}else{
	    $value = $proto->$col;
	}
    }else{                       # $proto is a class
	$class = $proto;
	$value ||=  "";
    }
    
    if ($col eq "info"){
	return "<textarea name=\"$col\" rows=\"10\" cols=\"38\">$value</textarea>\n";
    }
    my $sqltype = $self->getsqltype($class, $col);
    if ($sqltype =~ /bool/){
	if ($value == 1){
	    $tag = "<input type=\"radio\" name=\"$col\" value=\"1\" checked> yes";
	    $tag .= " <input type=\"radio\" name=\"$col\" value=\"0\"> no";
	}elsif ($value eq ""){
	    $tag = "<input type=\"radio\" name=\"$col\" value=\"1\"> yes";
	    $tag .= " <input type=\"radio\" name=\"$col\" value=\"0\"> no";
	    $tag .= " <input type=\"radio\" name=\"$col\" value=\"\" checked> n/a";
	}elsif ($value == 0){
	    $tag = "<input type=\"radio\" name=\"$col\" value=\"1\"> yes";
	    $tag .= " <input type=\"radio\" name=\"$col\" value=\"0\" checked> no";
	}
    }elsif ($sqltype eq "date"){
	$tag = "<input type=\"text\" name=\"$col\" size=\"15\" value=\"$value\"> (yyyy-mm-dd)";
    }else{
	$tag = "<input type=\"text\" name=\"$col\" size=\"40\" value=\"$value\">";
    }
    return $tag;
}

=head2 mksession - create state for a session across multiple pages

  $dir = "/tmp";  # location for locks & state files
  $session = $ui->mksession( $dir );

Creates a state session that can be used to store data across multiple 
web pages for a given session.  Returns a hash reference to store said data
in.  Requires an argument specifying what directory to use when storing 
data (and the relevant lock files).  The session-id is 
$session{_session_id}.  Be aware that you do not want to de-ref the 
hash reference (otherwise, changes made to the subsequent hash are lost).

=cut

sub mksession {
  my( $self, $dir ) = @_;
  my( $sid, %session );
  eval {
      tie %session, 'Apache::Session::File', 
      $sid, { Directory => $dir, LockDirectory => $dir };
  };
  if ($@) {
      $self->error(sprintf("Could not create session: %s", $@));
      return 0;
  }
  return \%session ;
}

=head2 getsession - fetch state for a session across multiple pages

  $dir = "/tmp";  # location for locks & state files
  $sessionid = $args{sid};  # session-id must be handed off to new pages
  %session = $ui->getsession( $dir, $sessionid );

Fetches a state session and its accompanying data.  Returns a hash ref.  
Requires two arguments:  the working directory and the session-id (as 
described above).  The same warning for mksession() regarding 
de-referencing the returned object applies.

=cut

sub getsession {
  my( $self, $dir, $sid ) = @_;
  my %session;
  eval {
      tie %session, 'Apache::Session::File', 
      $sid, { Directory => $dir, LockDirectory => $dir };
  };
  if ($@) {
      $self->error(sprintf("Could not retrieve session id %s:, %s", $sid, $@));
      return 0;
  }
  return \%session;
}

=head2 pushsessionpath - push table name onto list of table names

  $result = $ui->pushsessionpath( $session, $table );

Pushes the table name $table onto a list of tables that have been visited.

=cut

sub pushsessionpath {
  my( $self, $session, $table ) = @_;
  if( defined( $session->{path} ) 
      && length( $session->{path} ) > 0 && $session->{path} ne ";" ) {
    $session->{path} .= ";$table";
  } else {
    $session->{path} = "$table";
  }
  return 1;
}

=head2 popsessionpath - pop table name from list of table names

  $table = $ui->popsessionpath( $session );

Pops the last table visited from the stack and returns the name.

=cut

sub popsessionpath {
  my( $self, $session ) = @_;
  my $tbl;
  my @tbls = split( /;/, $session->{path} );
  if( scalar( @tbls ) > 0 ) {
    $tbl = pop @tbls;
  }
  $session->{path} = join( ';', @tbls );
  return $tbl;
}

=head2 rmsession

  $ui->rmsession( \%session );

Removes specific session associated with the hash %session.

=cut

sub rmsession {
  my( $self, $session ) = @_;
  if( tied(%{ $session })->delete() ) {
    return 1;
  } else {
    return 0;
  }
}

=head2 rmsessions

  $dir = "/tmp";
  $age = 3600;   # age is in seconds
  $ui->rmsessions( $dir, $age );

Removes state older than $age (the supplied argument) from the 
directory $dir.  Returns 1 for success and 0 for failure.  Remember, age 
is in seconds.

=cut

sub rmsessions {
  my( $self, $dir, $age ) = @_;
  my $locker = new Apache::Session::Lock::File ;
  if( $locker->clean( $dir, $age ) ) {
    return 1;
  } else {
    return 0;
  }
}

=head2 update - update a DB table row

  $result = $ui->update( object => $obj, state => \%state );

Updates values for a particular row in a DB table.  Takes two arguments. 
The first argument 'object' is a Netdot::DBI (and consequently Class::DBI
) object that represents the table row you wish to update.  The second 
argument 'state' is a hash reference which is a simple composition 
of column => value pairs.  Returns positive integer representing the 
modified rows id column for success and 0 for failure.

=cut 

sub update {
    my( $self, %argv ) = @_;
    my($obj) = $argv{object};
    my(%state) = %{ $argv{state} };
    my $change = 0;
    my $table = $obj->table;
    
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
    if( $change ) {
	eval { $obj->update(); };
	if( $@ ) {
	    $self->error("Unable to update $table $obj: $@");
	    return 0;
	}
    }
    return $obj->id;
}

=head2 insert - insert row into DB table

  $result = $ui->insert( table => $tbl, state => \%state );

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

  $result = $ui->remove( table => $tbl, id => $id );

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

  $ret = $ui->insertbinfile(file, filetype);

  inserts binary object into the BinFile table. If filetype is not
  specified it will be (hopefully) determined automatically.

  Returns the id of the newly inserted row, or 0 for failure and error
  should be set.

=cut

sub insertbinfile($$$) {
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

  $ret = $ui->updatebinfile(file, binfile_id);

  updates the the binary object with the specified id.

  Returns positive int on success, or 0 for failure and error
  should be set.

=cut

sub updatebinfile($$$) {
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

  $lastseen = $ui->timestamp();

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

  $lastupdated = $ui->date();

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

  $serial = $ui->dateserial();

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

=head2 form_to_db

  %info = $ui->form_to_db(%ARGS);

Generalized code for updating columns in different tables. 
Expected format for passed in form data is:

   TableName__<primary key>__ColumnName => Value

If primary key =~ "NEW", a new row will be inserted.

Returns a hash with update details on success, false on failure and error 
should be set.

=cut

sub form_to_db{
    my($self, %argv) = @_;
    my %form_to_db_info;

    # Store objects, fields and values in a hash
    my %objs;
    foreach ( keys %argv ){
	my $item = $_;	
	# Some table names are preceded with "_" 
	# to avoid problems in javascript
	$item =~ s/^_//;
	if ( $item =~ /^(\w+)__(\w+)__(\w+)$/ ){
	    $objs{$1}{$2}{$3} = $argv{$_};
	}
    }
# Check that we have at least one parameter
    unless (scalar keys(%objs)){
        $self->error("Missing name/value pairs.");
        return 0;
    }
    
    foreach my $table (keys %objs){
	
        foreach my $id (keys %{ $objs{$table} }){
	    # Actions (like delete) take precedence over value updates
	    # 
	    my $act = 0; 
	    #################################################################
	    # Some tables require more complex validation
	    # We pass the data to external functions
	    
	    if ( $table eq "Ipblock" ){
		if ( $id =~ /NEW/i ) {
		    # Creaating a New Ipblock object
		    my $newid;
		    unless ( $newid = $self->{ipm}->insertblock( %{ $objs{$table}{$id} } ) ){
			$self->error(sprintf("Error inserting new Ipblock: %s", $self->{ipm}->error));
			return 0;
		    }
		    $form_to_db_info{$table}{action} = "insert";
		    $form_to_db_info{$table}{key} = $newid;
		    $act = 1;
		}else {
		    foreach my $field (keys %{ $objs{$table}{$id} }){
			if ( $field eq "delete" ){
			    # Deleting an Ipblock object
			    unless ( $self->{ipm}->removeblock( id => $id ) ){
				$self->error(sprintf("Error deleting Ipblock: %s", $self->{ipm}->error));
				return 0;
			    }
			    $form_to_db_info{$table}{action} = "delete";
			    $form_to_db_info{$table}{key} = $id;
			    $act = 1;
			    last;
			}
		    }
		    if ( ! $act ){
			# Updating an existing Ipblock object
			$objs{$table}{$id}{id} = $id;
			unless ( $self->{ipm}->updateblock( %{ $objs{$table}{$id} } ) ){
			    $self->error($self->{ipm}->error);
			    return 0;
			}
			$form_to_db_info{$table}{action} = "update";
			$form_to_db_info{$table}{key} = $id;
			$act = 1;
		    }
		}
		
	    }else{
		foreach my $field (keys %{ $objs{$table}{$id} }){
		    if ($field eq "delete" && $objs{$table}{$id}{$field} eq "on"){
			# Remove object from DB
			if ( ! $self->remove(table => "$table", id => "$id") ){
			    return 0; # error should already be set.
			}
			$form_to_db_info{$table}{action} = "delete";
			$form_to_db_info{$table}{key} = $id;
			# Set the 'action' flag
			$act = 1;
			last;
		    }
		}
		
		# If our id is new we want to insert a new row in the DB.
		# Do a regex to allow sending many NEW groups for the same
		if ( $id =~ /NEW/i ){
		    my $newid;
		    if (! ($newid = $self->insert(table => $table, state => \%{ $objs{$table}{$id} })) ){
			return 0; # error should be set.
		    }
		    
		    $form_to_db_info{$table}{action} = "insert";
		    $form_to_db_info{$table}{key} = $newid;
		    $act = 1;
		}
		# Now update the thing
		if ( ! $act ) {
		    # only if no other actions were performed
		    my $o;
		    unless ( $o = $table->retrieve($id) ){
			$self->error("Couldn't retrieve id $id from table $table");
			return 0;
		    }
		    unless ( $self->update(object => $o, state => \%{ $objs{$table}{$id} }) ){
			return 0; # error should already be set.
		    }
		    $form_to_db_info{$table}{action} = "update";
		    $form_to_db_info{$table}{key} = $id;
		}
	    }
        }
    }
    return %form_to_db_info;

}

=head2 selectLookup

  $ui->selectLookup(object=>$o, column=>"physaddr", lookup=>"PhysAddr", edit=>"$editgen", linkPage=>1);

Arguments:
  - object: DBI object, can be null if a table object is included
  - table: Name of table in DB. (required if object is null)
  - column: name of field in DB.
  - edit: true if editing, false otherwise.
  - htmlExtra: (optional) extra html you want included in the output. Common
               use would be to include style="width: 150px;" and the like.
  - linkPage:  (optional) Make the printed value a link
               to itself via some page (i.e. view.html) 
               (requires that column value is defined)
  - maxCount: (optional) maximum number of results to display before giving 
              the user the option of refining their results. Defaults to
              DEFAULT_SELECTMAX in configuration files.


=cut

sub selectLookup($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $lookup, $where, $isEditing, $htmlExtra, $linkPage, $maxCount) = 
	($args{object}, $args{table}, 
	 $args{column}, $args{lookup},
	 $args{where}, $args{edit},
	 $args{htmlExtra}, $args{linkPage},
	 $args{maxCount});
    
    $htmlExtra = "" if (!$htmlExtra);
    $maxCount = $args{maxCount} || $self->{config}->{"DEFAULT_SELECTMAX"};
    my @labels = $self->getlabelarr($lookup);

    if ($isEditing){
        my ($count, @fo);
        my $tableName = ($o ? $o->table : $table);
        my $id = ($o ? $o->id : "NEW");
        my $name = $tableName . "__" . $id . "__" . $column;
        
        if ($where){
            @fo = $lookup->search($where);
            $count = scalar(@fo);
        }else {
            $count = $lookup->count_all;
        }
        
        # if the selected objects are within our limits, show the select box.
        if ($count <= $maxCount){
            @fo = $lookup->retrieve_all() if (!$where);
	    @fo = map  { $_->[0] }
	    sort { $a->[1] cmp $b->[1] }
	    map { [$_ , $self->getlabelvalue($_, \@labels)] } @fo;

            # if an object was passed we use it to obtain table name, id, etc
            # as well as add an initial element to the selection list.
            if ($o){
                printf("<SELECT NAME=\"%s\" %s>\n", $name, $htmlExtra);
                if ($o->$column){
                    printf("<OPTION VALUE=\"%s\" SELECTED>%s</OPTION>\n", $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
                }else{
                    printf("<OPTION VALUE=\"\" SELECTED>-- Select --</OPTION>\n");
                }
            }
            # otherwise a couple of things my have happened:
            #   1) this is a new row in some table, thus we lack an object
            #      reference and need to create a new one. We rely on the supplied 
            #      "table" argument to create the fieldname, and do so with the
            #      id of "NEW" in order to force insertion when the user hits submit.
            elsif ($table){
                printf("<SELECT NAME=\"%s\" %s>\n", $name, $htmlExtra);
                printf("<OPTION VALUE=\"\" SELECTED>-- Make your selection --</OPTION>\n");
            }else{
            #   2) The apocalypse has dawned. No table argument _or_ valid DB object..lets bomb out.
                $self->error("Unable to determine table name. Please pass valid object and/or table name.\n");
                return 0;
            }

            foreach my $fo (@fo){
                next if ($o && $o->$column && ($fo->id == $o->$column->id));
                printf("<OPTION VALUE=\"%s\">%s</OPTION>\n", $fo->id, $self->getlabelvalue($fo, \@labels));
            }
            printf("<OPTION VALUE=\"0\">[null]</OPTION>\n");
            printf("</SELECT>\n");
        }else{
	    # ...otherwise provide tools to narrow the selection to a managable size.
            my $srchf = "_" . $id . "_" . $column . "_srch";
            printf("<INPUT TYPE=\"text\" name=\"%s\" VALUE=\"Keywords\" onFocus=\"if (this.value == 'Keywords') { this.value = ''; } return true;\">&nbsp;\n", $srchf);
            printf("<INPUT TYPE=\"button\" name=\"__%s\" value=\"List\" onClick=\"sendquery(%s, %s.value, \'%s\');\"><br>\n", time(), 
                                                                                                                              $name, 
                                                                                                                              $srchf, 
                                                                                                                              $lookup);
            printf("<SELECT NAME=\"%s\" %s>\n", $name, $htmlExtra);
            printf("<OPTION VALUE=\"\" SELECTED>-- Make your selection --</OPTION>\n");
            if ($o && $o->$column){
                printf("<OPTION VALUE=\"%s\" SELECTED>%s</OPTION>\n", $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
            }
            printf("<OPTION VALUE=\"0\">[null]</OPTION>\n");
            printf("</SELECT>\n");
        }

    }elsif ($linkPage && $o->$column){
	if ($linkPage eq "1" || $linkPage eq "view.html"){
	    my $rtable = $o->$column->table;
	    printf("<a href=\"view.html?table=%s&id=%s\"> %s </a>\n", $rtable, $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
	}else{
	    printf("<a href=\"$linkPage?id=%s\"> %s </a>\n", $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
	}
    }else{
        printf("%s\n", ($o->$column ? $self->getlabelvalue($o->$column, \@labels) : ""));
    }
}

=head2 selectQuery

  $r = $ui->selectQuery(table => $table, terms => \@terms, max => $max);

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

sub selectQuery {
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
	    if (my $fobjs = $self->selectQuery( table => $rtable, terms => $terms )){
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

=head2 radioGroupBoolean

   $ui->radioGroupBoolean(object=>$o, column=>"monitored", edit=>$editmgmt);

 Simple yes/no radio button group. 

 Arguments:
   - object: DBI object, can be null if a table object is included
   - table: Name of table in DB. (required if object is null)
   - column: name of field in DB.
   - edit: true if editing, false otherwise.

=cut

sub radioGroupBoolean($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing) = ($args{object}, $args{table}, 
                                            $args{column}, $args{edit});
    my $tableName = ($o ? $o->table : $table);
    my $id = ($o ? $o->id : "NEW");
    my $value = ($o ? $o->$column : "");
    my $name = $tableName . "__" . $id . "__" . $column;
    
    
     unless ($o || $table){
	 $self->error("Unable to determine table name. Please pass valid object and/or table name.\n");
	 return 0;
     }

    if ($isEditing){
        printf("Y<INPUT TYPE=\"RADIO\" NAME=\"%s\" VALUE=\"1\" %s>&nbsp;<br>\n", $name, ($value ? "CHECKED" : ""));
        printf("N<INPUT TYPE=\"RADIO\" NAME=\"%s\" VALUE=\"0\" %s>\n", $name, (!$value ? "CHECKED" : ""));
    }else{
        printf("%s\n", ($value ? "Y" : "N"));
    }
}

=head2 textField

 Text field widget. If "edit" is true then a text field is displayed with
 the value from the DB (if any).

 Arguments:
   - object: DBI object, can be null if a table object is included
   - table: Name of table in DB. (required if object is null)
   - column: name of field in DB.
   - default: default value to display if no value is defined in DB.
   - edit: true if editing, false otherwise.
   - htmlExtra: extra html you want included in the output. Common use
                would be to include style="width: 150px;" and the like.
   - linkPage: (optional) Make the printed value a link
                to itself via some component (i.e. view.html) 
                (requires that column value is defined)

=cut

sub textField($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $htmlExtra, $linkPage, $default) = ($args{object}, $args{table}, 
									     $args{column}, $args{edit}, 
									     $args{htmlExtra}, $args{linkPage},
									     $args{default});
    
    my $tableName = ($o ? $o->table : $table);
    my $id = ($o ? $o->id : "NEW");
    my $value = ($o ? $o->$column : $default);
    my $name = $tableName . "__" . $id . "__" . $column;

    $htmlExtra = "" if (!$htmlExtra);

    unless ($o || $table){
	$self->error("Unable to determine table name. Please pass valid object and/or table name.\n") ;
	return 0;
    }
    if ($isEditing){
        printf("<INPUT TYPE=\"TEXT\" NAME=\"%s\" VALUE=\"%s\" %s>\n", $name, $value, $htmlExtra);
    }elsif ( $linkPage && $value){
	if ( $linkPage eq "1" || $linkPage eq "view.html" ){
	    printf("<a href=\"view.html?table=%s&id=%s\"> %s </a>\n", $tableName, $o->id, $value);
	}else{
    	    printf("<a href=\"$linkPage.html?id=%s\"> %s </a>\n", $o->id, $value);
	}
    }else{
        printf("%s\n", $value);
    }
}

=head2 textArea

 Text area widget. If "edit" is true then a textarea is displayed with
 the value from the DB (if any).

 Arguments:
   - object: DBI object, can be null if a table object is included
   - table: Name of table in DB. (required if object is null)
   - column: name of field in DB. 
   - edit: true if editing, false otherwise.
   - htmlExtra: extra html you want included in the output. Common use
     would be to include style="width: 150px;" and the like.

=cut

sub textArea($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $htmlExtra) = ($args{object}, $args{table}, 
                                                        $args{column}, $args{edit}, 
                                                        $args{htmlExtra});
    my $tableName = ($o ? $o->table : $table);
    my $id = ($o ? $o->id : "NEW");
    my $value = ($o ? $o->$column : "");
    my $name = $tableName . "__" . $id . "__" . $column;

    $htmlExtra = "" if (!$htmlExtra);

    unless ($o || $table){
	$self->error("Unable to determine table name. Please pass valid object and/or table name.\n");
	return 0;
    }
    if ($isEditing){
        printf("<TEXTAREA NAME=\"%s\" %s>%s</TEXTAREA>\n", $name, $htmlExtra, $value);
    }else{
        printf("%s\n", $value);
    }
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

