package Netdot::Model;

use base qw ( Class::DBI  Netdot );
use Netdot::Model::Nullify;
use Time::Local;
use Net::DNS;
use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(blessed);

=head1 NAME

Netdot::Model - Netdot implementation of the Model layer (of the MVC architecture)

    This base class includes logic common to all classes that need access to the stored data.
    It is not intended to be used directly.

=head1 SYNOPSIS
    
    
=cut

my %defaults; 
my $logger = Netdot->log->get_logger("Netdot::Model");

BEGIN {
    my $db_type  = __PACKAGE__->config->get('DB_TYPE');
    my $database = __PACKAGE__->config->get('DB_DATABASE');
    my $host     = __PACKAGE__->config->get('DB_HOST');
    my $port     = __PACKAGE__->config->get('DB_PORT');

    $defaults{dsn}  = "dbi:$db_type:database=$database";
    $defaults{dsn} .= ";host=$host" if defined ($host); 
    $defaults{dsn} .= ";port=$port" if defined ($port); 
    $defaults{user}        = __PACKAGE__->config->get('DB_NETDOT_USER');
    $defaults{password}    = __PACKAGE__->config->get('DB_NETDOT_PASS');
    $defaults{dbi_options} = { __PACKAGE__->_default_attributes };
    if ($db_type eq "mysql") {
        $defaults{dbi_options}->{AutoCommit} = 1;
        $defaults{dbi_options}->{mysql_enable_utf8} = 1;
    } elsif($db_type eq "Pg") {
        $defaults{dbi_options}->{AutoCommit} = 1;
        $defaults{dbi_options}->{pg_enable_utf8} = 1;
    }

    # Tell Class::DBI to connect to the DB
    __PACKAGE__->connection($defaults{dsn}, 
			    $defaults{user}, 
			    $defaults{password}, 
			    $defaults{dbi_options});

    # Verify Schema version
    my $dbh = __PACKAGE__->db_Main();
    my ($schema_version) = $dbh->selectrow_array("SELECT version FROM schemainfo");
    if ( $schema_version ne $Netdot::VERSION ){
     	Netdot::Model->_croak(sprintf("Netdot DB schema version mismatch: Netdot version '%s' != Schema version '%s'", 
				      $Netdot::VERSION, $schema_version));
    }


###########################################################
# Copy stored object in corresponding history table 
#  - After updating
#  - After creating
# This must be defined here (before loading the classes).  
###########################################################
    __PACKAGE__->add_trigger( after_update => \&_historize );
    __PACKAGE__->add_trigger( after_create => \&_historize );

    sub _historize {
	my ($self, %args) = @_;
	
	my $changed_columns = $args{discard_columns};
	if ( defined $changed_columns ){ 
	    if ( (scalar(@$changed_columns) == 1 && $changed_columns->[0] eq 'last_updated') ||
		 scalar(@$changed_columns) == 2 && $changed_columns->[0] eq 'last_updated' && 
		 ($changed_columns->[1] eq 'last_fwt' || $changed_columns->[1] eq 'last_arp') ){
		return;
	    }
	}
	my $table    = $self->table;
	my $h_table  = $self->meta_data->get_history_table_name();
	return unless $h_table;  # this object does not have a history table
	my $dbh      = $self->db_Main();
	my $col_list = join ",", $self->columns;
	my $id       = $self->id;
	my @vals = $dbh->selectrow_array("SELECT $col_list FROM $table WHERE id = $id");
	my %current_data;
	my $i = 0;
	map { $current_data{$_} = $vals[$i++] } $self->columns;
	delete $current_data{id}; # Our id is different
	my $oid = $table."_id"; # fk pointing to the real object's id
	$current_data{$oid}     = $self->id;
	$current_data{modified} = $self->timestamp;
	$current_data{modifier} = $ENV{REMOTE_USER} || "unknown";
	eval {
	    $h_table->SUPER::insert(\%current_data);
	};
	if ( my $e = $@ ){
	    $logger->error("Could not insert history record for $table id ".$self->id.": $e");
	}
	1;
    }

###########################################################
# Keep audit trail of DNS/DHCP changes.  
# Each relevant record change inserts an entry in the 
# houstaudit table.  Each time a new zonefile or dhcp config 
# is generated, pending changes are unmarked. 
# This avoids unnecessary work, and also logs record changes
###########################################################
    __PACKAGE__->add_trigger( after_update  => \&_host_audit_update );
    __PACKAGE__->add_trigger( after_create  => \&_host_audit_insert );
    __PACKAGE__->add_trigger( before_delete => \&_host_audit_delete );

    sub _host_audit_update {
	my ($self, %args) = @_;
	return unless ( $self->table =~ /^rr/ || $self->table eq 'zone' ||
			$self->table eq 'dhcpscope' || $self->table eq 'dhcpattr');
	$args{operation} = 'update';
	my $changed_columns = $args{discard_columns};
	if ( defined $changed_columns && scalar(@$changed_columns) ){
	    $args{fields} = join ',', @$changed_columns;
	    my @values;
	    foreach my $col ( @$changed_columns ){
		if ( $self->$col && blessed($self->$col) ){
		    push @values, $self->$col->get_label();
		}else{
		    push @values, $self->$col;
		}
	    }
	    $args{values} = join ',', map { "'$_'" } @values;
	    return $self->_host_audit(%args);
	}
    }
    sub _host_audit_insert {
	my ($self, %args) = @_;
	return unless ( $self->table =~ /^rr/ || $self->table eq 'zone' ||
			$self->table eq 'dhcpscope' || $self->table eq 'dhcpattr');
	$args{operation} = 'insert';
	my (@fields, @values);
	foreach my $col ( $self->columns ){
	    if ( defined $self->$col ){ 
		push @fields, $col;
		if ( $self->$col && blessed($self->$col) ){
		    push @values, $self->$col->get_label();
		}else{
		    push @values, $self->$col;
		}
	    } 
	}
	$args{fields} = join ',', @fields;
	$args{values} = join ',', map { "'$_'" } @values if @values;
	return $self->_host_audit(%args);
    }
    sub _host_audit_delete {
	my ($self, %args) = @_;
	return unless ( $self->table =~ /^rr/ || $self->table eq 'zone' ||
			$self->table eq 'dhcpscope' || $self->table eq 'dhcpattr');
	$args{operation} = 'delete';
	$args{fields} = 'all';
	$args{values} = $self->get_label;
	return $self->_host_audit(%args);
    }
    sub _host_audit {
	my ($self, %args) = @_;
	my $table = $self->table;
	my ($zone, $scope);
	my $user = $ENV{REMOTE_USER} || "unknown";
	my $rr; 
	if ( $table eq 'zone' ){
	    $zone = $self;   
	}elsif ( $table eq 'rr' ){
	    $rr = $self;
	    return if ( $args{fields} eq 'modified' );
	    $zone = $self->zone;
	}elsif ( $table =~ /^rr/ ){
	    if ( defined $self->rr && $self->rr ){
		if ( blessed($self->rr) ){
		    $rr = $self->rr;
		    $zone = $rr->zone;
		}else{
		    if ( $rr = RR->retrieve($self->rr) ){
			$zone = $rr->zone;
		    }else{
			$logger->error("Netdot::Model::_host_audit: $table id ".$self->id." has invalid rr: ".$self->rr);
			return;
		    }
		}
	    }else{
		$logger->error("Netdot::Model::_host_audit: $table id ".$self->id." has no rr");
		return;
	    }
	}elsif ( $table eq 'dhcpscope' ){
	    $scope = $self->get_global();   
	}elsif ( $table eq 'dhcpattr' ){
	    $scope = $self->scope->get_global();
	}elsif ( $table eq 'ipblock' ){
	    $scope = $self->parent->dhcp_scopes->first->get_global();
	}else{
	    $self->throw_fatal("Netdot::Model::_host_audit: Invalid table: $table");
	}
	my $label = $self->get_label;
	my %data = (tstamp      => $self->timestamp,
		    record_type => $table,
		    username    => $user,
		    operation   => $args{operation},
		    pending     => 1,
		    );
	$data{fields} = $args{fields} if $args{fields};
	$data{vals}   = $args{values} if $args{values};
	my $name; # Name of the zone or global scope
	if ( $zone ){
	    unless ( blessed($zone) ){
		$zone = Zone->retrieve($zone);
	    }
	    $name       = $zone->name;
	    $data{zone} = $name;
	}elsif ( $scope ){
	    $name        = $scope->name;
	    $data{scope} = $name;
	}else{
	    $self->throw_fatal("Netdot::Model::_host_audit: Could not determine audit object for table: $table");
	}
	
	eval {
	    HostAudit->insert(\%data);
	};
	if ( my $e = $@ ){
	    $logger->error("Netdot::Model::_host_audit: Could not insert HostAudit record about $table id ".$self->id.": $e");
	    return;
	}else{
	    my $msg = "Netdot::Model::_host_audit: table: $table, record: $label, within: $name, user: $user, operation: $args{operation}";
	    $msg .= " fields: ($args{fields}), values: ($args{values})" if (defined $args{fields} && defined $args{values});
	    $logger->info($msg);
	}
	1;
    }

    #############################################################################
    # Update RR 'modified' timestamp if any of its sub-records are touched
    #############################################################################
    __PACKAGE__->add_trigger( before_create  => \&_update_rr_tstamp );
    __PACKAGE__->add_trigger( before_update  => \&_update_rr_tstamp );
    __PACKAGE__->add_trigger( before_delete  => \&_update_rr_tstamp );

    sub _update_rr_tstamp {
	my $self = shift;
	my $table = $self->table;
	my $rr;
	if ( $table eq 'rr' ){
	    $rr = $self;
	    $rr->_attribute_set({modified=>$self->timestamp});
	}elsif ( $table =~ /^rr/ ){
	    if ( defined $self->rr && $self->rr ){
		if ( blessed($self->rr) ){
		    $rr = $self->rr;
		}else{
		    unless ( $rr = RR->retrieve($self->rr) ){
			return;
		    }
		}
	    }else{
		return;
	    }
	    $rr->SUPER::update({modified=>$self->timestamp});
	}
	1;
    }

    ###########################################################
    # This sub avoids errors like:
    # "Deep recursion on subroutine "Class::DBI::_flesh""
    # when executing under mod_perl
    # Someone suggested using it here:
    # http://lists.digitalcraftsmen.net/pipermail/classdbi/2006-January/000750.html
    # I haven't had time to understand what is really happenning
    ###########################################################
    sub _flesh {
	my $this = shift;
	if(ref($this) && $this->_undefined_primary) {
	    $this->call_trigger("select");
	    return $this;
	}
	return $this->SUPER::_flesh(@_);
    }

    # Get CDBI subclasses
    # Notice that some tables have special parent classes, so we pass a different 'base'
    my (%subclasses, %tables, $evalcode);
    my $namespace = 'Netdot::Model';
    foreach my $table ( __PACKAGE__->meta->get_tables(with_history => 1) ){
	my ($base, $subclass);
	if ( $table->name =~ /Picture/ ){
	    $base = 'Netdot::Model::Picture';
	}else{
	    $base = 'Netdot::Model';
	}
	($package, $code) = __PACKAGE__->meta->cdbi_class(table     => $table,
							  base      => $base,
							  usepkg    => ['Class::DBI::AbstractSearch'],
							  namespace => $namespace,
							  );
	$subclasses{$package} = $code;
	$tables{$package}     = $table->name;
	$evalcode .= "\n".$code;
    }

    # Load all Class::DBI subclasses
    eval $evalcode;
    if ( my $e = $@ ){
	die $e; 
    }

    # This section will attempt to load a Perl module with the same name
    # as each class that was just autogenerated, so we can extend the 
    # functionality of our classes.  The modules must be located
    # in a directory that can be found by the 'use' call.
    foreach my $package ( keys %subclasses ){
	eval "use $package";
	if( my $e = $@ ) { if($e !~ /^Can.t locate /) { die $e } }
    }

    # This section will allow us to continue to say 
    # Table->method instead of Netdot::Model::Table->method.
    # This could go away if we decide to change all our
    # existing code to use the full class names
    foreach my $package ( keys %tables ){
	my $table = $tables{$package};
	eval "package $table; use base '$package';";
	if ( my $e = $@ ){
	    die $e; 
	}
    }
    # Do the same as above for these special derived classes
    my %dc = __PACKAGE__->meta->get_derived_classes();
    while ( my($key,$val) = each %dc ){
	my $short = $key;
	my $pack  = $val->[0];
	my $base  = $val->[1];
	eval "use $pack";
	my $cmd = "package $short; use base '$pack';";
	eval $cmd;
	if ( my $e = $@ ){
	    die $e; 
	}	
    }
}

=head1 CLASS METHODS
=cut
############################################################################
=head2 insert - Insert (create) a new object

  Arguments:
    Hash with field/value pairs
  Returns:
    Newly inserted object
  Examples:
    my $newobj = SomeClass->insert({field1=>val1, field2=>val2});

=cut
sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal("insert needs field/value parameters") 
	unless ( keys %{$argv} );

    $class->_adjust_vals(args=>$argv, action=>'insert');

    my $obj;
    eval {
	$obj = $class->SUPER::insert($argv);
    };
    if ( my $e = $@ ){
	my $msg = "Error while inserting $class: ";
	# Class::DBI shows a full stack trace
	# Try to make it less frightening for the user
	if ( $e =~ /Duplicate entry/i ){
	    $msg .= "Some values are duplicated. Full error: $e";
	}elsif ( $e =~ /cannot be null|not-null constraint/i ){
	    $msg .= "Some fields cannot be null. Full error: $e";
	}elsif ( $e =~ /invalid input syntax/i ){
	    $msg .= "Some fields have invalid input syntax.";
	}elsif ( $e =~ /out of range/i ){
	    $msg .= "Some values are out of valid range.";
	}else{
	    $msg .= $e;
	}
	$class->throw_user("$msg");
    }

    $logger->debug( sub { sprintf("Model::insert: Inserted new record %i in table: %s", 
				  $obj->id, $obj->table) } );
    
    return $obj;
}

############################################################################
=head2 search_like - Search with wildcards

    We override the base method to add wildcard characters at the beginning
    and end of the search string by default.  
    User can also specify exact search by enclosing search terms within 
    quotation marks (''), or use their own shell-style wildcards (*,?),
    which will be translated into SQL-style (%,_)

  Arguments:
    hash with key/value pairs
  Returns:
    See Class::DBI search_like()
  Examples:
    my @objs = SomeClass->search_like(field1=>val1, field2=>val2);

=cut
sub search_like {
    my ($class, @args) = @_;
    $class->isa_class_method('search_like');

    @args = %{ $args[0] } if ref $args[0] eq "HASH";
    my $opts = @args % 2 ? pop @args : {};
    my %argv = @args;

    foreach my $key ( keys %argv ){
	# Don't do it for foreign key fields
	unless ( $class->meta_data->get_column($key)->links_to() ){
	    $argv{$key} = $class->_convert_search_keyword($argv{$key});
	}
    }
    return $class->SUPER::search_like(%argv, $opts);
}

############################################################################
=head2 timestamp - Get timestamp in DB 'datetime' format

  Arguments:
    None
  Returns:
    String
  Examples:
    $lastseen = $obj->timestamp();

=cut
sub timestamp {
    my $class  = shift;
    my ($seconds, $minutes, $hours, $day_of_month, 
	$month, $year,$wday, $yday, $isdst) = localtime;
    my $datetime = sprintf("%04d\/%02d\/%02d %02d:%02d:%02d",
			   $year+1900, $month+1, $day_of_month, $hours, $minutes, $seconds);
    return $datetime;
}

############################################################################
=head2 date - Get date in DB 'date' format

  Arguments:
    None
  Returns:
    String
  Examples:
    $lastupdated = $obj->date();

=cut
sub date {
    my $class  = shift;
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
	$wday, $yday, $isdst) = localtime;
    my $date = sprintf("%04d\/%02d\/%02d",
			   $year+1900, $month+1, $day_of_month);
    return $date;
}


############################################################################
=head2 meta_data - Return Meta::Table object associated with this object or class

  Arguments:
    None
  Returns:
    Meta::Table object
  Examples:
    my @device_columns = $dev->meta_data->get_column_names();

=cut
sub meta_data {
    my $self = shift;
    my $table;
    $table = $self->short_class();
    return $self->meta->get_table($table);
}

############################################################################
=head2 short_class - Return the short version of a class name.  It can also be called as a Class method.
    
  Arguments:
    None
  Returns:
    Short class name
  Examples:
    # This returns 'Device' instead of Netdot::Model::Device
    $class = $dev->short_class();
=cut
sub short_class {
    my $self = shift;

    my $class = ref($self) || $self;
    if ( $class =~ /::(\w+)$/ ){
	$class = $1;
    }
    return $class;
}

############################################################################
=head2 raw_sql - Issue SQL queries directly

    Returns results from an SQL query

 Arguments: 
    SQL query (string)
 Returns:  
    Reference to a hash of arrays. 
    When using SELECT statements, the keys are:
     - headers:  array containing column names
     - rows:     array containing column values

    When using NON-SELECT statements, the keys are:
     - rows:     array containing one string, which states the number
                 of rows affected
  Example:
    $result = Netdot::Model->raw_sql($sql)

    my @headers = $result->{headers};
    my @rows    = $result->{rows};

    # In a Mason component:
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
    	    $self->throw_user("SQL Error: $errormsg");
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
    	    $self->throw_fatal("raw_sql Error: $@");
    	    return;
    	}
    	$rows = 0 if ( $rows eq "0E0" );  # See DBI's documentation for 'do'

        my @info = ('Rows Affected: '.$rows);
        my @rows;
        push( @rows, \@info );
        $result{rows} = \@rows;
    }else{
    	$self->throw_user("raw_sql Error: Only select, delete, update and insert statements accepted");
    	return;
    }
    return \%result;
}

############################################################################
=head2 do_transaction - Perform an operation "atomically".
    
    A reference to a subroutine is passed, together with its arguments.
    If anything fails within the operation, any DB changes made since the 
    start are rolled back.  
    
  Arguments:
    code - code reference
    args - array of arguments to pass to subroutine
    
  Returns:
    results from code ref
    
  Example: (*)
    
    $r = Netdot::Model->do_transaction( sub{ return $dev->snmp_update(@_) }, %argv);

    (*) Notice the correct way to get a reference to an object\'s method
        (See section 4.3.6 - Closures, from "Programming Perl")

=cut

# This method has been adapted from an example offered here:
# http://wiki.class-dbi.com/wiki/Using_transactions

sub do_transaction {
    my ($self, $code, @args) = @_;
    $self->isa_class_method('do_transaction');

    my @result;
    my $dbh = $self->db_Main();

    # Parallel processes might cause deadlocks so we try 
    # up to three times if that happens
    for ( 1..3 ){

	# Localize AutoCommit database handle attribute
	# and turn off for this block.
	local $dbh->{AutoCommit};
	
	eval {
	    @result = $code->(@args);
	    $self->dbi_commit;
	};
	if ( my $e = $@ ) {
	    if ( $e =~ /deadlock/i ){
		$logger->debug("Deadlock found.  Restarting transaction.");
		next;
	    }
	    $self->clear_object_index;
	    eval { $self->dbi_rollback; };
	    my $rollback_error = $@;
	    if ( $rollback_error ){
		$self->throw_fatal("Transaction aborted: $e; "
				   . "(Rollback failed): $rollback_error\n");
	    }else{
		# Rethrow
		if ( ref($e) =~ /Netdot::Util::Exception/  &&
		     $e->isa_netdot_exception('User') ){
		    $self->throw_user("Transaction aborted: $e\n");
		}else{
		    $self->throw_fatal("Transaction aborted: $e\n");
		}
	    }
	    return;
	}else{
	    last;
	}
    }
    wantarray ? @result : $result[0];
} 

############################################################################
=head2 db_auto_commit - Set the AutoCommit flag in DBI for the current db handle

 Arguments: Flag value to be set (1 or 0)
 Returns:   Current value of the flag (1 or 0)

=cut
sub db_auto_commit {
    my $self = shift;
    $self->isa_class_method('db_auto_commit');

    my $dbh = $self->db_Main;
    if ( @_ ) { $dbh->{AutoCommit} = shift };
    return $dbh->{AutoCommit};
}

=head1 INSTANCE METHODS
=cut

############################################################################
=head2 update - Update object in DB

  We combine Class::DBI\'s set() and update() into one method.  
  If called with no arguments, assumes values have been set() and calls update() only.

  Arguments:
    hashref  containing key/value pairs (optional)
  Returns: 
    See Class::DBI update()
  Examples:
    $obj->update({field1=>value1, field2=>value2});

=cut
sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');
    my $class = ref($self);
    my @changed_keys;
    if ( $argv ){

	$class->_adjust_vals(args=>$argv, action=>'update');
	
	while ( my ($col, $val) = each %$argv ){
	    my $a = blessed($self->$col) ? $self->$col->id : $self->$col;
	    my $b = blessed($val)        ? $val->id        : $val;
	    if ( (!defined $a || !defined $b) || (defined $a && defined $b && $a ne $b) ){
		$self->set($col=>$b);
		push @changed_keys, $col;
	    }
	}
    }
    my $id = $self->id;
    my $res;
    eval {
	$res = $self->SUPER::update();
    };
    if ( my $e = $@ ){
	my $msg = "Error while updating $class: ";
	# Class::DBI shows a full stack trace
	# Try to make it less frightening for the user
	if ( $e =~ /Duplicate/i ){
	    $msg .= "Some values are duplicated. Full error: $e";
	}elsif ( $e =~ /invalid input syntax/i ){
	    $msg .= "Some fields have invalid input syntax";
	}elsif ( $e =~ /out of range/i ){
	    $msg .= "Some values are out of valid range.";
	}else{ 
	    $msg .= $e;
	}
	$self->throw_user("$msg");
    }
    if ( @changed_keys ){
	# For some reason, we (with some classes) get an empty object after updating (weird)
	# so we re-read the object from the DB
	$self = $class->retrieve($id);
	my @values = map { $self->$_ } @changed_keys;
	$logger->debug( sub { sprintf("Model::update: Updated table: %s, id: %s, fields: (%s), values: (%s)", 
				      $self->table, $self->id, (join ", ", @changed_keys), (join ", ", @values) ) } );
    }
    return $res;
}

############################################################################
=head2 delete - Delete an existing object

  Arguments:
    None
  Returns:
    True if successful
  Examples:
    $obj->delete();

=cut
sub delete {
    my $self = shift;
    $self->isa_object_method('delete');
    $self->throw_fatal("delete does not take any parameters") if shift;

    my ($id, $table) = ($self->id, $self->table);

    # Remove any access rights for this object
    $logger->debug( sub { sprintf("Model::delete: Searching Access Rights for table %s id %s", 
				  $table, $id) } );
    if ( my @access_rights = AccessRight->search(object_class=>$table, object_id=>$id) ){
	foreach my $ar ( @access_rights ){
	    $logger->debug( sub { sprintf("Model::delete: Deleting AccessRight: %s for table %s id %s", 
					  $ar->access, $table, $id) } );
	    $ar->SUPER::delete();
	}
    }

    eval {
	$self->SUPER::delete();
    };
    if ( my $e = $@ ){
	if ( $e =~ /objects still refer to/i ){
	    $e = "Other objects refer to this object.  Delete failed.";
	}
	$self->throw_user($e);
    }
    $logger->debug( sub { sprintf("Model::delete: Deleted record %i, from table: %s", 
				  $id, $table) } );

    return 1;
}

############################################################################
=head2 get_state - Get current state of an object

    Get a hash with column/value pairs from this object.
    Useful if object needs to be restored to a previous
    state after changes have been committed.

  Arguments:
    None
  Returns:
    Hash with column/value pairs
  Examples:

    my %state = $obj->get_state;

=cut
sub get_state {
    my ($self) = @_;
    $self->isa_object_method('get_state');

    # Make sure we're working with an fresh object
    my $id    = $self->id;
    my $class = ref($self);
    $self     = $class->retrieve($id);
    
    my %state;
    my @cols   = $class->columns();
    my @values = $self->get(@cols);
    my $n = 0;
    foreach my $col ( @cols ){
	$state{$col} = $values[$n++];
    }
    return %state;
}

############################################################################
=head2 get_digest - Calculate MD5 digest of object's current data

  Arguments:
    None
  Returns:
    MD5 digest of object's data
  Examples:
    my %digest = $obj->get_state_digest;

=cut
sub get_digest {
    my ($self) = @_;
    
    my %state = $self->get_state();
    my @data;
    foreach my $col ( sort keys %state ){
	my $val = $state{$col};
	push @data, "$col:$val";
    }
    use Data::Dumper;
    return md5_hex(Dumper(@data));
}

##################################################################
=head2 get_label - Get label string

    Returns an object\'s label string, composed of the values 
    of a list of label fields, defined in metadata,
    which might reside in more than one table.
    Specific classes might override this method.

Arguments:
    (Optional) field delimiter (default: ', ')
Returns:
    String
Examples:
    print $obj->get_label();

=cut
sub get_label {
    my ($self, $delim) = @_;
    $self->isa_object_method('get_label');

    $delim ||= ', ';  # default delimiter

    my @lbls = $self->meta_data->get_labels();

    my @ret;
    foreach my $c ( @lbls ){
	my $mcol;
	if ( defined($self->$c) && ($mcol = $self->meta_data->get_column($c)) ){
	    if ( ! $mcol->links_to() ){
		push @ret, $self->$c;
	    }else{
		# The field is a foreign key
		if ( $self->$c && blessed($self->$c) ){
		    push @ret, $self->$c->get_label($delim);
		}else{
		    push @ret, $self->$c;
		}
	    }
	}
    }
    # Only want non empty fields
    return join "$delim", grep {$_ ne ""} @ret ;
}

############################################################################
=head2 ge_history - Get a list of history objects for a given object

  Arguments:
    None
  Returns:
    Array of history records associated with this object, ordered
    by modified time, newest first.
  Example:
    my @h = $obj->get_history();

=cut
sub get_history {
    my ($self, $o) = @_;
    $self->isa_object_method('get_history');

    my $table  = $self->table;
    my $htable = $self->meta_data->get_history_table_name();
    return unless $htable;

    # History objects have two indexes, one is the necessary
    # unique index, the other one refers to which real object
    # this is the history of.
    # The latter has the table's name plus the "_id" suffix

    my $id_f = lc("$table" . "_id");
    my @ho;
    return $htable->search($id_f=>$self->id, {order_by => 'modified DESC'});
}

############################################################################
=head2 search_all_tables - Search for a string in all text fields from all tables
    
    If query has the format <table:keyword>, then only fields of that table
    will be searched

  Arguments:  
    query string
  Returns:    
    reference to hash of hashes

=cut
sub search_all_tables {
    my ($self, $q) = @_;
    my %results;
   
    # Check if a table was specified
    my $table;
    if ( $q =~ /(\S+):(.+)$/ ){
	$table = $1;
	$q     = $2;
    }
    
    if ( Ipblock->matches_ip($q) ){
	# Convert IP addresses before searching
	my @res = Ipblock->search(address=>Ipblock->ip2int($q));
	map { $results{'Ipblock'}{$_->id} = $_ } @res;
    }elsif ( my ($addr,$pref) = Ipblock->matches_cidr($q) ){
	my @res = Ipblock->search(address=>$addr, prefix=>$pref);
	map { $results{'Ipblock'}{$_->id} = $_ } @res;	
    }else{
	foreach my $tbl ( $self->meta->get_table_names() ) {
	    next if ( $table && $tbl !~ /^$table$/i );
	    $lctbl = lc($tbl);
	    my @cols;
	    foreach my $c ( $tbl->columns ){
		my $mcol = $tbl->meta_data->get_column($c);
		# Ignore id field
		next if ( $mcol->name eq 'id' );
		# Ignore foreign key fields
		next if ( $mcol->links_to() );
		# Only include these types
		push @cols, $c
		    if ( $mcol->sql_type =~ /^blob|text|varchar|integer$/ ); 
	    }
	    foreach my $col ( @cols ){
		my @res = $tbl->search_like($col=>$q);
		map { $results{$tbl}{$_->id} = $_ } @res;
	    }
	    last if $table;
	}
    }
    return \%results;
}


############################################################################
=head2 sqldate2time - Convert SQL date or timestamp into epoch value

  Arguments:  
    SQL date or timestamp string ('YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS')
  Returns:    
    Seconds since epoch (compatible with Perls time function)

=cut
sub sqldate2time {
    my ($self, $date) = @_;
    if ( $date =~ /^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}):(\d{2}))?$/ ){
	my ($y, $m, $d)  = ($1, $2, $3);
	my ($h, $mn, $s) = ($4, $5, $6);
	$self->throw_fatal("Netdot::Model::sqldate2time: Invalid date string: $date.")
	    unless ($y >= 0 && $m >= 0 && $m <= 12 && $d > 0 && $d <= 31 && 
		    $h >= 0 && $h < 24 && $mn >= 0 && $m < 60 && $s >= 0 && $s < 60);
	return timelocal($s,$mn,$h,$d,$m-1,$y);
    }else{
	$self->throw_fatal("Netdot::Model::sqldate2time: Invalid SQL date format: $date. ".
			   "Should be 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS'.");
    }
}

############################################################################
=head2 sqldate_days_ago - N days ago in SQL date format

  Arguments:  
    number of days (integer)
  Returns:    
    SQL date num_days ago

=cut
sub sqldate_days_ago {
    my ($self, $num_days) = @_;
    my $epochdate = time-($num_days*24*60*60);
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $epochdate;
    $year += 1900; $mon += 1;
    return sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec);
}

############################################################################
=head2 sqldate_today - Today's date in SQL date format

  Arguments:  
    None
  Returns:    
    Today's date in SQL format

=cut
sub sqldate_today {
    my ($self) = @_;
    my $epochdate = time;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $epochdate;
    $year += 1900; $mon += 1;
    return sprintf("%4d-%02d-%02d",$year,$mon,$mday);
}

############################################################################
=head2 time2sqldate

  Arguments:  
    time (epoch)
  Returns:    
    Date string in SQL format (YYYY-MM-DD)

=cut
sub time2sqldate {
    my ($self, $time) = @_;
    $time ||= time;
    my (@arr) = localtime($time);
    my ($d, $m, $y) = ($arr[3], $arr[4], $arr[5]);
    $m++; $y += 1900;
    return "$y-$m-$d";
}

##################################################################
#
# Private Methods
#
##################################################################

############################################################################
# _adjust_vals - Adjust field values before inserting/updating
# 
#    - Make sure to set integer and bool fields to 0 instead of the empty string.
#    - Make sure non-nullable fields are inserted as 0 if not passed
#    - Ignore the empty string when inserting/updating date fields.
#    - Check the length of the varchar fields.
#
# Arguments:
#   hash with following keys:
#      - args   - field/value pairs
#      - action - <update|insert>
# Returns:
#   True
# Examples:
#
sub _adjust_vals{
    my ($class, %argv) = @_;
    $class->isa_class_method('_adjust_vals');
    my ($action, $args) = @argv{'action', 'args'};
    my %meta_columns;
    map { $meta_columns{$_->name} = $_ } $class->meta_data->get_columns;
    foreach my $field ( keys %$args ){
	my $mcol = $meta_columns{$field} || $class->throw_fatal("Cannot find $field in metadata");
	if ( !blessed($args->{$field}) && $mcol->sql_type eq 'varchar' && defined($mcol->length) && $mcol->length =~ /^\d+$/ ) {
            if (length($args->{$field}) > $mcol->length) {
                $class->throw_user("Value for field '$field' (max " . $mcol->length . ") is too long: '$args->{$field}'");
            }
        }
	if ( !blessed($args->{$field}) && 
	     (!defined($args->{$field}) || $args->{$field} eq '' || 
	      $args->{$field} eq 'null' || $args->{$field} eq 'NULL' ) ){

	    if ( $mcol->links_to ){
		# It's a foreign key. Set to null
		$args->{$field} = undef;
	    }else{
		if ( !defined($mcol->sql_type) ){
		    $class->throw_fatal("Netdot::Model::_adjust_vals: sql_type not defined for $field");
		}
		if ( $mcol->sql_type =~ /^integer|bigint|bool$/o ) {
		    $logger->debug(sub{sprintf("Model::_adjust_vals: Setting empty field '%s' type '%s' to 0.", 
					       $field, $mcol->sql_type) });
		    $args->{$field} = 0;
		}else{
		    # Insert NULL instead of ""
		    $args->{$field} = undef;
		}
	    }
	}
	delete $meta_columns{$field};
    }
    # Go over remaining (not given) columns to make sure non-nullables are 
    # explicitly set to 0
    if ( $action eq 'insert' ){
	foreach my $field ( keys %meta_columns ){
	    next if ( $field eq 'id' );
	    my $mcol = $meta_columns{$field};
	    if ( !$mcol->is_nullable && 
		 $mcol->sql_type =~ /^integer|bigint|bool$/o ) {
		$logger->debug(sub{sprintf("Netdot::Model::_adjust_vals: Setting missing non-nullable ". 
					   "field '%s' type '%s' to 0.", 
					   $field, $mcol->sql_type) } );
		$args->{$field} = 0;
	    }
	}
    }
    return 1;
}

##################################################################
#_convert_search_keyword - Transform a search keyword into exact or wildcarded
#
#    Search keywords between quotation marks ('') are interpreted
#    as exact matches.  Otherwise, SQL wildcards are prepended and appended.
#
#  Arguments:
#   keyword
#  Returns:
#    Scalar containing transformed keyword string
#  Examples:
#

sub _convert_search_keyword {
    my ($self, $keyword) = @_;
    $self->isa_class_method("_convert_search_keyword");

    my ($old, $new);
    $old = $keyword;

    # Remove leading and trailing spaces
    $keyword = Netdot->rem_lt_sp($keyword);

    if ( $keyword =~ /^['"](.*)['"]$/ ){
	# User wants exact match
	$new = $1;
    }elsif( $keyword =~ /[\*\?]/ ){
	# Translate wildcards into SQL form
	$keyword =~ s/\*/%/g;
	$keyword =~ s/\?/_/g;	
	$new = $keyword;
    }else{
	# Add wildcards at beginning and end
	$new =  "%" . $keyword . "%";
    }
    $logger->debug(sub{"Model::_convert_search_keyword: Converted '$old' into '$new'"});
    return $new;
}


=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut

# Make sure to return 1
1;


