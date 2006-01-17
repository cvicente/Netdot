package Netdot;

use lib "PREFIX/lib";
use Debug;
use base qw (Netdot::DBI );

#Be sure to return 1
1;


=head1 NAME

Netdot - Network Documentation Tool

=head1 SYNOPSIS

Netdot.pm contains a series of functions commonly used throughout Netdot s classes,
hence the idea of grouping them in this parent class, inheritable by every other class.

=head1 METHODS

=cut

=head2 new - Class Constructor
    
    my $netdot = Netdot->new()
    
=cut
sub new {
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    
    # Read config files
    $self->_read_defaults;
    
    # Initialize Meta data
    $self->_read_metadata;
    
    $self->{'_logfacility'} = $argv{'logfacility'} || $self->{config}->{'DEFAULT_LOGFACILITY'},
    $self->{'_loglevel'}    = $argv{'loglevel'}    || $self->{config}->{'DEFAULT_LOGLEVEL'},
    $self->{'_logident'}    = $argv{'logident'}    || $self->{config}->{'DEFAULT_SYSLOGIDENT'},
    $self->{'_foreground'}  = $argv{'foreground'}  || 0,
    
    $self->{debug} = Debug->new(logfacility => $self->{'_logfacility'},
				loglevel    => $self->{'_loglevel'},
				logident    => $self->{'_logident'},
				foreground  => $self->{'_foreground'},
				);
    
#  We override Class::DBI to speed things up in certain cases.
    
    unless ( $self->{dbh} = Netdot::DBI->db_Main() ){
	$self->error("Can't get db handle\n");
	return 0;
    }
    
    wantarray ? ( $self, '' ) : $self;
    
}


######################################################################
# STUFF for Debug.pm
######################################################################

=head2 set_loglevel - set Netdot loglevel

   $netdot->set_loglevel( "loglevel" );

Debug messages at loglevel $loglevel or above are sent to syslog; they are
otherwise dropped.  You can use this method to change the loglevel.
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


=head2 gettables

  @tables = $db->gettables();

Returns a list of table names found in the Meta table

=cut
sub gettables{
    my $self = shift;
    return map {$_->name} Meta->retrieve_all;
}

=head2 understanding get links methods

The following two methods, getlinksto and getlinksfrom, have names corresponding to the following diagram:

 +------+   ``this has linksto that'' +------+
 |      | ``that has linksfrom this'' |      |
 | this |---------------------------->| that |
 |      |                             |      |
 +------+ Many                    One +------+

Keep the arrow head (-->) in mind, otherwise the names would be ambiguous.  The actual data are specified in bin/insert-metadata, which is well commented.

=cut

=head2 getlinksto

  %linksto = $db->getlinksto($table);

When passed a table name, returns a hash containing the tables one-to-many relationships
s.t. this table is on the "many" side (has_a definitions in Class::DBI).
The hash keys are the names of the local fields, and the values are the names of the tables
that these fields reference.
This info is identical for history tables

=cut
sub getlinksto{
    my ($self, $table) = @_;
    return %{ $self->{meta}->{$table}->{linksto} };
}

=head2 getlinksfrom

  %linksfrom = $db->getlinksfrom($table);

When passed a table name, returns a hash of hashes containing the tables one-to-many relationships
s.t. this table is on the "one" side (equivalent to has_many definitions in Class::DBI).
The keys of the main hash are identifiers for the relationship.  The nested hashs keys are names of
the tables that reference this table.  The values are the names of the fields in those tables that
reference this tables primary key.
History tables are not referenced by other tables

=cut
sub getlinksfrom{
    my ($self, $table) = @_;
    return %{ $self->{meta}->{$table}->{linksfrom} };
}

=head2 getcolumnorder

  %order = $db->getcolumnorder($table);

Accepts a table name and returns its column names, ordered in the same order theyre supposed to be
displayed. It returns a hash with column names as keys and their positions and values.
History tables have two extra fields at the end

=cut
sub getcolumnorder{
    my ($self, $table) = @_;
    return %{ $self->{meta}->{$table}->{columnorder} };
}

=head2 getcolumnorderbrief

  %orderbrief = $db->getcolumnorderbrief($table);

Similar to getcolumnorder().  Accepts a table name and returns a brief list of
fields for that table (the most relevant).  The method returns a hash with column names as keys
and their positions as values.
History tables have two extra fields at the beginning

=cut
sub getcolumnorderbrief {
  my ($self, $table) = @_;
  return %{ $self->{meta}->{$table}->{columnorderbrief} };
}

=head2 getcolumntypes

  %coltypes = $db->getcolumntypes($table);

Accepts a table and returns a hash containing the SQL types for the table's columns.  The hash's
keys are the column names and the values their type.

=cut
sub getcolumntypes{
    my ($self, $table) = @_;
    return %{ $self->{meta}->{$table}->{columntypes} };
}

=head2 getcolumntags

  %tags = $db->getcolumntags($table);

Returns a hash contaning the user-friendly display names for a tables columns

=cut
sub getcolumntags{
    my ($self, $table) = @_;
    return %{ $self->{meta}->{$table}->{columntags} };
}

=head2 getlabels

  @lbls = $db->getlabels($table);

Returns a tables list of labels.  Labels are one or more columns used as hyperlinks to retrieve
the specified object.  Theyre also used as a meaningful instance identifier.

=cut
sub getlabels{
    my ($self, $table) = @_;
    return @{ $self->{meta}->{$table}->{labels} };
}

=head2 isjointable

  $flag = $db->isjointable( $table );

Check if table is a join table

=cut
sub isjointable {
    my ($self, $table) = @_;
    return %{ $self->{meta}->{$table}->{isjointable} };
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
    # Only want non empty fields
    return join "$delim", grep {$_ ne ""} @ret ;
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
	return;
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
	# Comparisons are very picky about overloaded arguments,
	# so we check if either the column or the value to be set
	# are actually Class::DBI objects and if they are, we
	# use the corresponding id
	my $c = ( ref($obj->$col) )   ? $obj->$col->id   : $obj->$col;
	my $v = ( ref($state{$col}) ) ? $state{$col}->id : $state{$col};
	eval {
	    if( $c ne $v ) {
		$change = 1;
		$obj->set( $col, $state{$col} );
	    }
	};
	if( $@ ) {
	    $self->error("Unable to set $col to $state{$col}: $@");
	    return 0;
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


=head2 single_table_search

  $r = $db->single_table_search(table => $table, field => $field, keyword => $keyword, max => $max);

 Search the 'field' field in 'table' for rows matching 'keyword'.

 Arguments
   table: Name of table to search in
   field: field name of the table that will be searched
   keyword: search for this value in field
   max: maximum rows to return
 Returns
   hashref of $table objects

=cut
sub single_table_search {
    my ($self, %args) = @_;
    my ($table, $field, $keyword, $max) = ($args{table}, $args{field}, $args{keyword}, $args{max});
    my %found;

	my $it;
	if ( $table eq "Ipblock" && $field eq "address" ){
	    # Special case.  We have to convert into an integer first
	    # Also, if user happened to enter a prefix, make it work
	    my ($address, $prefix);
	    if ( $keyword =~ /\/\d+$/ ){
   			($address, $prefix) = split /\//, $keyword;
   			my $int = $self->ip2int($address);
   			$it = $table->search( 'address' => $int, 'prefix'=> $prefix );
	    }else{
   			$address = $keyword;
   			my $int = $self->ip2int($address);
   			$it = $table->search( 'address' => $int );
	    }
	}else{
	    $it = $table->search( $field => $keyword );
	}

	while (my $obj = $it->next){
	    $found{$obj->id} = $obj;
	}

    # Return all matching objects for the keyword
	return \%found;
}

=head2 select_query

  $r = $db->select_query(table => $table, terms => \@terms, max => $max);

 Search keywords in a tables label fields. If label field is a foreign
 key, recursively search for same keywords in foreign table.

 Arguments
   table: Name of table to look up
   terms: array ref of search terms
 Returns
   hashref of $table objects

=cut
sub select_query {
    my ($self, %args) = @_;
    my ($table, $terms) = ($args{table}, $args{terms});
    my %found;
    my %linksto = $self->getlinksto($table);
    my @labels = $self->getlabels($table);
    foreach my $term (@$terms){
	foreach my $c (@labels){
	    if (! $linksto{$c} ){ # column is local
		my $it;
		if ( $table eq "Ipblock" && $c eq "address" ){
		    # Special case.  We have to convert into an integer first
		    # Also, if user happened to enter a prefix, make it work
		    my ($address, $prefix);
		    if ( $term =~ /\/\d+$/ ){
			($address, $prefix) = split /\//, $term;
			my $int = $self->ip2int($address);
			$it = $table->search( 'address' => $int, 'prefix'=> $prefix );
		    }else{
			$address = $term;
			my $int = $self->ip2int($address);
			$it = $table->search( 'address' => $int );
		    }
		}else{
		    $it = $table->search_like( $c => "%" . $term . "%" );
		}
		while (my $obj = $it->next){
		    $found{$term}{$obj->id} = $obj;
		}
	    }else{ # column is a foreign key.
		my $rtable = $linksto{$c};
		# go recursive
		if (my $fobjs = $self->select_query( table => $rtable, terms => [$term] )){
		    foreach my $foid (keys %$fobjs){
			my $it = $table->search( $c => $foid );
			while (my $obj = $it->next){
			    $found{$term}{$obj->id} = $obj;
			}
		    }
		}
	    }
	}
    }
    # If more than one keyword, return the intersection.
    # Otherwise, return all matching objects for the single keyword
    if ( (scalar @$terms) > 1 ){
	my (%in, %un);
	foreach my $term ( keys %found ){
	    foreach my $id ( keys %{ $found{$term} } ){
		(exists $un{$id})? $in{$id} = $found{$term}{$id} : $un{$id} = $found{$term}{$id};
	    }
	}
	return \%in;
    }else{
	return \%{$found{$terms->[0]}};
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
        return;
    }
    my $htable = $self->gethistorytable($o);

    # History objects have two indexes, one is the necessary
    # unique index, the other one refers to which normal object
    # this is the history of
    # The latter has the table's name plus the "_id" suffix

    my $id_f = lc ("$table" . "_id");
    my @ho;
    eval {
       @ho = $htable->search($id_f => $o->id, {order_by => 'modified DESC'});
    };
    if ( $@ ){
	$self->error("Can't retrieve history objects for $table id $o->id: $@");
	return;
    }
    return @ho;
}

=head2 search_all_netdot - Search for a string in all fields from all tables, excluding foreign key fields.

Arguments:  query string
Returns:    reference to hash of hashes or -1 if error

=cut
sub search_all_netdot {
    my ($self, $q) = @_;
    my %results;

    # Ignore these fields when searching
    my %ign_fields = ('id' => '');
    # Remove leading and trailing spaces
    $q =~ s/^\s*(.*)\s*$/$1/;
    # Add wildcards
    $q = "%" . $q . "%";

    foreach my $tbl ( $self->gettables() ) {
	next if $tbl eq "Meta";
	# Will also ignore foreign key fields
	my %linksto = $self->getlinksto($tbl);
	my @cols;
	map { push @cols, $_ unless( exists $ign_fields{$_} || $linksto{$_} ) } $tbl->columns();
	my @where;
	map { push @where, "$_ LIKE \"$q\"" } @cols;
	my $where = join " or ", @where;
	next unless $where;
	my $st;
	eval {
	    $st = $self->{dbh}->prepare("SELECT id FROM $tbl WHERE $where;");
	    $st->execute();
	};
	if ( $@ ){
	    $self->error("search_all_netdot: $@");
	    return -1;
	}
	while ( my ($id) = $st->fetchrow_array() ){
	    $results{$tbl}{$id} = $tbl->retrieve($id);
	}
    }
    return \%results;

}

=head2 raw_sql - Issue SQL queries directly

    Prints out results from an SQL query

 Arguments: 
    sql    - SQL query (text)
 Returns:  
    Reference to an array containing lines of output

  Example:
    if ( ! ($result = $ui->raw_sql($sql) ) ){
	$sql_err = $ui->error;
    }

    my @headers = $result->{headers};
    my @rows    = $result->{rows};

    <& data_table.mhtml, field_headers=>@headers, data=>@rows &>

=cut
sub raw_sql {
    my ($self, $sql) = @_;

    my $st;
    my %result;
    if ( $sql =~ /select/i ){
    	eval {
    	    $st = $self->{dbh}->prepare( $sql );
    	    $st->execute();
    	};
    	if ( $@ ){
            # parse out SQL error message from the entire error
            my ($errormsg) = $@ =~ m{execute[ ]failed:[ ](.*)[ ]at[ ]/};
    	    $self->error("SQL Error: $errormsg");
    	    return;
    	}

        $result{headers} = $st->{"NAME_lc"};
        $result{rows}    = $st->fetchall_arrayref;

    }elsif ( $sql =~ /delete|update|insert/i ){
    	my $rows;
    	eval {
    	    $rows = $self->{dbh}->do( $sql );
    	};
    	if ( $@ ){
    	    $self->error("raw_sql Error: $@");
    	    return;
    	}
    	$rows = 0 if ( $rows eq "0E0" );  # See DBI's documentation for 'do'

        my @info = ('Rows Affected: '.$rows);
        my @rows;
        push( @rows, \@info );
        $result{rows} = \@rows;
    }else{
    	$self->error("raw_sql Error: Only select, delete, update and insert statements accepted");
    	return;
    }
    return \%result;
}


=head2 ip2int - Convert IP(v4/v6) address string into its decimal value

 Arguments: address string
 Returns:   integer (decimal value of IP address)

=cut
sub ip2int {
    my ($self, $address) = @_;
    my $ipobj;
    unless ( $ipobj = NetAddr::IP->new($address) ){
	$self->error(sprintf("Invalid IP address: %s", $address));
	return 0;
    }
    return ($ipobj->numeric)[0];
}


=head2 within

    Checks if a value is between two other values
    Arguments:
        - val: value youre interested in
        - beg: start of range to check
        - end: end of range to check
    Returns true/false whether val is between beg and end, inclusive

=cut
sub within {
    my ($self, $val, $beg, $end) = @_;
    return( $beg <= $val && $val <= $end );
}

=head2 powerof2lo

    Returns the next lowest power of 2 from x
    note: hard-coded to work for 32-bit integers
    Arguments:
        - x: an integer
    Returns a power of 2

=cut
sub powerof2lo {
    my ($self, $x) = @_;
    $x++;
    $x |= $x >> 1;
    $x |= $x >> 2;
    $x |= $x >> 4;
    $x |= $x >> 8;
    $x |= $x >> 16;
    $x--;
    return 2**((log($x)/log(2))-1) + 1;
}

=head2 send_mail

    Sends mail to desired destination.  
    Useful to e-mail output from automatic processes

    Arguments (hash):
    - to      : destination email (defaults to NOCEMAIL from config file)
    - from    : orignin email (defaults to ADMINEMAIL from config file)
    - subject : subject of message
    - body    : body of message

    Returns true/false for success/failure

=cut
sub send_mail {
    my ($self, %args) = @_;
    my ($to, $from, $subject, $body) = 	
	($args{to}, $args{from}, $args{subject}, $args{body});
 
    my $SENDMAIL = $self->{config}->{'SENDMAIL'};

    $to    ||= $self->{config}->{'NOCEMAIL'};
    $from  ||= $self->{config}->{'ADMINEMAIL'};

    if ( !open(SENDMAIL, "|$SENDMAIL -oi -t") ){
        $self->error("send_mail: Can't fork for $SENDMAIL: $!");
        return 0;
    }

print SENDMAIL <<EOF;
From: $from
To: $to
Subject: $subject
    
$body
    
EOF

close(SENDMAIL);
    return 1;

}


######################################################################
#
# Private Methods
#
######################################################################

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

sub _getmeta{
    my ($self, $table) = @_;
    return (Meta->search( name => $table ))[0];
}


sub _read_metadata{
    my ($self) = @_;
    foreach my $table ( $self->gettables ){
	$self->{meta}->{$table}->{linksto}          = $self->_read_linksto($table);
	$self->{meta}->{$table}->{linksfrom}        = $self->_read_linksfrom($table);
	$self->{meta}->{$table}->{columnorder}      = $self->_read_columnorder($table);
	$self->{meta}->{$table}->{columnorderbrief} = $self->_read_columnorderbrief($table);
	$self->{meta}->{$table}->{columntypes}      = $self->_read_columntypes($table);
	$self->{meta}->{$table}->{columntags}       = $self->_read_columntags($table);
	$self->{meta}->{$table}->{labels}           = $self->_read_labels($table);
	$self->{meta}->{$table}->{isjointable}      = $self->_read_isjointable($table);
    }
}

sub _read_linksto{
    my ($self, $table) = @_;
    
    $table =~ s/_history//;
    my (%linksto, $mi);
    if ( defined($mi = $self->_getmeta($table)) ){
	map { my($j, $k) = split( /:/, $_ ); $linksto{$j} = $k }
	split( /,/, $mi->linksto );
	return \%linksto;
    }
    return;
}

sub _read_linksfrom{
    my ($self, $table) = @_;
    
    return if ( $table =~ /_history/ );
    my (%linksfrom, $mi);
    if ( defined($mi = $self->_getmeta($table)) ){
	map { my($i, $j, $k, $args) = split( /:/, $_ );
	      $linksfrom{$i}{$j} = $k;
	  }  split( /,/, $mi->linksfrom );
	return \%linksfrom;
    }
    return;
}

sub _read_columnorder{
    my ($self, $table) = @_;
    
    my $hist = 1 if ( $table =~ s/_history// );
    my (%order, $i, $mi);
    if ( defined($mi = $self->_getmeta($table)) ){
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
	if ( $hist ){
	    $order{'modified'} = $i++;
	    $order{'modifier'} = $i++;
	}
	return \%order;
    }
    return;
}

sub _read_columnorderbrief {
  my ($self, $table) = @_;

  my $hist = 1 if ( $table =~ s/_history// );
  my (%order, $i, $mi);
  if ( defined($mi = $self->_getmeta($table)) ){
    $i = 1;
    if ( $hist ){
	$order{'modified'} = $i++;
	$order{'modifier'} = $i++;
    }
    if( defined( $mi->columnorder ) ) {
      map { $order{$_} = $i++; } split( /,/, $mi->columnorderbrief );
    } else {
      $order{"id"} = $i++;
      foreach ( sort { $a cmp $b } $mi->name->columns() ) {
	next if( $_ eq "id" );
	$order{$_} = $i++;
      }
    }
    return \%order;
  }
  return;
}

sub _read_columntypes{
    my ($self, $table) = @_;

    my $hist = 1 if ( $table =~ s/_history// );
    my (%types, $mi);
    if ( defined($mi = $self->_getmeta($table)) ){
	my $mi = $self->_getmeta($table);
	if( defined( $mi->columntypes ) ) {
	    map { my($j, $k) = split( /:/, $_ ); $types{$j} = $k }
	    split( /,/, $mi->columntypes );
	}
	if ( $hist ){
	    $types{modified} = "varchar";
	    $types{modifier} = "timestamp";
	}
	return \%types;
    }
    return;
}

sub _read_columntags{
    my ($self, $table) = @_;

    $table =~ s/_history// ;
    my (%tags, $mi);
    if ( defined($mi = $self->_getmeta($table)) ){
	my $mi = $self->_getmeta($table);
	if( defined( $mi->columntags ) ) {
	    map { my($j, $k) = split( /:/, $_ ); $tags{$j} = $k }
	    split( /,/, $mi->columntags );
	}
	return \%tags;
    }
    return;
}

sub _read_labels{
    my ($self, $table) = @_;
    my $mi;
    if ( defined($mi = $self->_getmeta($table)) ){
	if( defined( $mi->label ) ) {
	    my @labels = split /,/, $mi->label;
	    return \@labels;
	}
    }
    return;
}

sub _read_isjointable {
    my ($self, $table) = @_;
    my $mi;
    if ( defined($mi = $self->_getmeta($table)) ){
        return $mi->isjoin;
    }
    return undef;
}
