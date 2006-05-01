package Netdot;

use lib "<<Make:LIB>>";
use Debug;
use base qw ( Netdot::DBI );

#Be sure to return 1
1;


=head1 NAME

Netdot - Network Documentation Tool

=head1 SYNOPSIS

Netdot.pm contains a series of functions commonly used throughout Netdot s classes,
hence the idea of grouping them in this parent class, inheritable by every other class.

=head1 METHODS


=head2 new - Class Constructor
    
    my $netdot = Netdot->new();
    
=cut
sub new {
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;

    # Read config files
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
  eval { $ret = $tbl->insert( \%state ); };
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
    $self->error("Unable to remove table $tbl id $id: $@");
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

=head2 convert_search_keyword - Transform a search keyword into exact or wildcarded

    Search keywords between quotation marks ('') are interpreted
    as exact matches.  Otherwise, SQL wildcards are prepended and appended.
    This is used in various search functions throughout Netdot and gives the
    user more flexibility when searching objects

  Arguments:
    keyword
  Returns:
    Scalar containing transformed keyword string

=cut

sub convert_search_keyword {
    my ($self, $keyword) = @_;
    if ( $keyword =~ /^'(.*)'$/ ){
	# User wants exact match
	# Translate wildcards into SQL form
	$keyword = $1;
	$keyword =~ s/\*/%/g;
	return $keyword;
    }else{
	# Remove leading and trailing spaces
	$keyword =~ s/^\s*(.*)\s*$/$1/;
	# Add wildcards
	return "%" . $keyword . "%";
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


=head2 raw_sql - Issue SQL queries directly

    Prints out results from an SQL query

 Arguments: 
    sql    - SQL query (text)
 Returns:  
    Reference to a hash of arrays. When using SELECT statements, the 
    keys are:
     - headers:  array containing column names
     - rows:     array containing column values

    When using NON-SELECT statements, the keys are:
     - rows:     array containing one string, which states the number
                 of rows affected
  Example:
    if ( ! ($result = $ui->raw_sql($sql) ) ){
	$sql_err = $ui->error;
    }

    my @headers = $result->{headers};
    my @rows    = $result->{rows};

    <& /generic/data_table.mhtml, field_headers=>@headers, data=>@rows &>

=cut
sub raw_sql {
    my ($self, $sql) = @_;
    my $dbh = $self->db_Main;
    my $st;
    my %result;
    if ( $sql =~ /select/i ){
    	eval {
    	    $st = $dbh->prepare_cached( $sql );
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
    	    $rows = $dbh->do( $sql );
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


=head2 do_transaction - Perform an operation 'atomically'.
    
    A reference to a subroutine is passed, together with its arguments.
    If anything fails within the operation, any changes made since the 
    start are rolled back.  
    This method has been adapted from an example offered here:
    http://wiki.class-dbi.com/wiki/Using_transactions

    Note: Since our calls to Class::DBI operations like insert, update and
          delete are already wrapped in 'eval' blocks, and hence will not die, 
          this method needs to check for the status of the error buffer.
          For this same reason, the call to 'commit' is not done within
          the same eval block as the main code ref (we would get an 
          undesired commit).

    Arguments:
    code - reference to a subroutine
    args - array of arguments to pass to subroutine

    Returns:
    results from code ref

    Example(*):
    
    $r = $dm->do_transaction( sub{ return $dm->update_device(@_) }, %argv) )

    * Notice the correct way to get a reference to an objects method
      (See section 4.3.6 - Closures, from "Programming Perl")

=cut
sub do_transaction {
    my ($self, $code, @args) = @_;

    # Make sure we start with  an empty error buffer because
    # we use it to test if the db operations have failed
    $self->error("");

    my @result = ();
    my $dbh = $self->{dbh};

    # Localize AutoCommit database handle attribute
    # and turn off for this block.
    local $dbh->{AutoCommit};

    eval {
        @result = $code->(@args);
    };
    if ($@ || $self->error) {
        my $error = $@ || $self->error;
	if ( $self->db_rollback ) {
            $self->error("Transaction aborted (rollback "
			 . "successful): $error");
        }else {
	    # Now error is set by db_rollback
            my $rollback_error = $self->error;
            $self->error("Transaction aborted: $error; "
			 . "Rollback failed: $rollback_error");
        }
        $self->clear_object_index;
        return;
    }else{ # No errors.  Commit
	# Error is set by db_commit
	$self->db_commit || return;
    }
    wantarray ? @result : $result[0];
    
} 

=head2 db_auto_commit - Set the AutoCommit flag in DBI for the current db handle

 Arguments: Flag value to be set (1 or 0)
 Returns:   Current value of the flag (1 or 0)

=cut
sub db_auto_commit {
    my $self = shift;
    my $dbh = $self->{dbh};
    if (@_) { $dbh->{AutoCommit} = shift };
    return $dbh->{AutoCommit};
}

=head2 db_begin_work - Temporarily set AutoCommit to 0

    This will set DBIs AutoCommit flag to 0 temporarily,
    until either a commit or a rollback occur.

  Note: This does not actually work as expected (though it would be useful)
        Probably something to investigate in the mailing lists

  Arguments: None
  Returns:   True on success, false on error

=cut
sub db_begin_work {
    my $self = shift;
    my $dbh = $self->{dbh};
    eval {
	$dbh->begin_work;
    };
    if ( $@ ){
	$self->error("$@");
	return;	
    }
    return 1;
}

=head2 db_commit - Tell database to commit changes
    
  Arguments: None
  Returns:   True on success, false on error

=cut
sub db_commit {
    my $self = shift;
    eval { $self->dbi_commit; };
    if ( $@ ) {
	$self->error("Commit failed!: $@");
	return;
    }
    return 1;
}

=head2 db_rollback - Tell database to roll back changes

  Arguments: None
  Returns:   True on success, false on error

=cut
sub db_rollback {
    my $self = shift;
    eval { $self->dbi_rollback; };
    if ( $@ ) {
	$self->error("$@");
	return;
    }
    return 1;
}



######################################################################
# Miscellaneous
######################################################################

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
    note: hard-coded to work for 32-bit integers,
    	so this won't work with ipv6 addresses.
    Arguments:
        - x: an integer
    Returns a power of 2

=cut
sub powerof2lo {
    my ($self, $x) = @_;
    $x |= $x >> 1;
    $x |= $x >> 2;
    $x |= $x >> 4;
    $x |= $x >> 8;  # the above sets all bits to the right of the
    $x |= $x >> 16; # left-most "1" bit of x to 1. (ex 10011 -> 11111)
	$x  = $x >> 1;  # divide by 2  (ex 1111)
    $x++;           # add one      (ex 10000)
    return $x;
}

=head2 ceil

	There is no ceiling function built in to perl. 

	Arguments:
		- x: a floating point number
	Returns the smallest integer greater than or equal to x.	
	(Also works for negative numbers, although we don't 
	really need that here.)

=cut
sub ceil {
    my ($self, $x) = @_;
	return int($x-(int($x)+1)) + int($x) + 1;
}

=head2 floor

	There is no floor function built in to perl.
	int(x) is equivalent to floor(x) for positive numbers,
	which is really all we need floor for here,	so this
	method will not work for negative numbers.

	Arguments:
		- x: a floating point number
	Return the largest integer less than or equal to x.	
=cut
sub floor {
    my ($self, $x) = @_;
	return int($x);
}

=head2 empty_space
	
	Returns empty space
	
	Arguments:
		none
=cut
sub empty_space {
	my ($self, $x) = @_;
	return " ";
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
    my @files = qw( <<Make:PREFIX>>/etc/Default.conf);
    push @files, "<<Make:PREFIX>>/etc/Site.conf", if ( -e "<<Make:PREFIX>>/etc/Site.conf" );
    foreach my $file (@files){
	my $config_href = do $file or die $@ || $!;
	foreach my $key ( %$config_href ) {
	    $self->{config}->{$key} = $config_href->{$key};
	}
    }
}
