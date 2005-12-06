package Netdot::UI;

=head1 NAME

Netdot::UI - Group of user interface functions for the Network Documentation Tool (Netdot)

=head1 DESCRIPTION

Netdot::UI groups common methods and variables related to Netdot's user interface layer

=head1 SYNOPSIS

  use Netdot::UI

  $ui = Netdot::UI->new();  

  print $ui->text_area(object=>$o, column=>"info", edit=>1, htmlExtra=>"cols=60");

=cut

use lib "PREFIX/lib";
use Apache::Session::File;
use Apache::Session::Lock::File;

use base qw( Netdot );
use Netdot::IPManager;
use strict;

#Be sure to return 1
1;

=head1 METHODS


=head2 new

  $ui = Netot::UI->new();

Creates a new UI object (basic constructor)

=cut

sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new( %argv );

    # There's only one case where a method from 
    # IPManager is needed.  It doesn't seem justifiable
    # to complicate things by inheriting from IPManager here.
    # Just create an object
    $self->{ipm} = Netdot::IPManager->new();

    wantarray ? ( $self, '' ) : $self; 
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
	$tag = "<input type=\"text\" name=\"$col\" style=\"width:100%\" value=\"$value\">";
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

=head2 form_to_db

  %info = $ui->form_to_db(%ARGS);

Generalized code for updating columns in different tables. 
ARGS is a hash with the following format:

  Update Column1 in object with id <id> from table <Table>
    <Table>__<id>__<Column1> => <Value>

  Delete a single object with id <id> from table <Table>
    <Table>__<id>__DELETE => null

  Delete a list of objects from the same table
  (useful when using <select multiple>)
    <Table>___LIST__DELETE => [ <id1>, <id2>, <id3> ]

  Insert new object with columns 1,2,3 set to the specified values
    <Table>__NEW1__<Column1> => <Value1>
    <Table>__NEW1__<Column2> => <Value2>
    <Table>__NEW1__<Column3> => <Value3>
    
  Insert another new object with columns 1,2,3 set to the specified value
    <Table>__NEW2__<Column1> => <Value1>
    <Table>__NEW2__<Column2> => <Value2>
    <Table>__NEW2__<Column3> => <Value3>
    

Returns a hash with update details on success, false on failure and error 
should be set.

=cut

sub form_to_db{
    my($self, %argv) = @_;
    my %ret;

    # Store objects, fields and values in a 3-level hash
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
        return ;
    }
    foreach my $table (keys %objs){
	#################################################################
	# Some tables require more complex validation
	# We pass the data to external functions
	if ( $table eq "Ipblock" ){
	    foreach my $id (keys %{ $objs{$table} }){
		# Actions (like delete) take precedence over value updates
		my $act = 0; 
		
		if ( $id =~ /NEW/i ) {
		    # Creating a New Ipblock object
		    my $newid;
		    unless ( $newid = $self->{ipm}->insertblock( %{ $objs{$table}{$id} } ) ){
			$self->error(sprintf("Error inserting new Ipblock: %s", $self->{ipm}->error));
			return;
		    }
		    $ret{$table}{id}{$newid}{action} = "INSERTED";
		    $act = 1;
		}else {
		    foreach my $field (keys %{ $objs{$table}{$id} }){
			if ( $field =~ /DELETE/i ){
			    # Deleting an Ipblock object
			    unless ( $self->{ipm}->removeblock( id => $id ) ){
				$self->error(sprintf("Error deleting Ipblock: %s", $self->{ipm}->error));
				return;
			    }
			    $ret{$table}{id}{$id}{action} = "DELETED";
			    $act = 1;
			    last;
			}
		    }
		    if ( ! $act ){
			# Updating an existing Ipblock object
			$objs{$table}{$id}{id} = $id;
			unless ( $self->{ipm}->updateblock( %{ $objs{$table}{$id} } ) ){
			    $self->error($self->{ipm}->error);
			    return;
			}
			$ret{$table}{id}{$id}{action} = "UPDATED";
			$act = 1;
		    }
		}
	    }
	    
	}else{
	    #################################################################
	    # All other tables
	    my %todelete; #avoid dups

	    foreach my $id (keys %{ $objs{$table} }){
		my $act = 0; 

		# If our id is 'NEW' we want to insert a new row in the DB.
		# Do a regex to allow sending many NEW groups for the same table
		if ( $id =~ /NEW/i ){
		    my $newid;
		    if (! ($newid = $self->insert(table => $table, state => \%{ $objs{$table}{$id} })) ){
			return; # error should be set.
		    }
		    $ret{$table}{id}{$newid}{action} = "INSERTED";
		    $act = 1;
		}else{
		    foreach my $field ( keys %{ $objs{$table}{$id} } ){
			my $val = $objs{$table}{$id}{$field};
			if ( $field =~ /DELETE/i ){
			    if ( $id =~ /LIST/i ){
				# This comes from a <select multiple>
				if ( ! ref($val) ){
				    $todelete{$val} = '';
				}elsif( ref($val) eq "ARRAY" ){
				    map { $todelete{$_} = '' } @$val;
				}
			    }elsif ( $id =~ /\d+/ ){
				# Single object to be deleted
				$todelete{$id} = '';
			    }
			    $act = 1;
			}
		    }
		    # Now update this object
		    if ( ! $act ) {
			my $o;
			unless ( $o = $table->retrieve($id) ){
			    $self->error("Couldn't retrieve id $id from table $table");
			    return;
			}
			unless ( $self->update(object => $o, state => \%{ $objs{$table}{$id} }) ){
			    return; # error should already be set.
			}
			$ret{$table}{id}{$id}{action} = "UPDATED";
			$ret{$table}{id}{$id}{columns} = \%{ $objs{$table}{$id} };
		    }
		}
	    }
	    
	    # Delete marked objects (do this once per table)
	    foreach my $del ( keys %todelete ){
		unless ( $self->remove( table=>$table, id => $del ) ){
		    # error should be set
		    return;
		}
		$ret{$table}{id}{$del}{action} = "DELETED";
	    }
	}
    }
    return %ret;
}


=head2 form_field

This method detects the type of form input required for the object, and then calls the appropriate
method in UI.pm. Either select_lookup, select_multiple, radio_group_boolean, text_field, or text_area.
If the interface is in "edit" mode, the user will see a form element specific to the type of data
being viewed, otherwise, the user will see the value of the object in plain text.

Arguments:
  object:       DBI object, can be null if a table object is included
  table:        Name of table in DB. (optional, but required if object is null)
  column:       Name of the field in the database
  edit:         True if editing, false otherwise
  default:      Default value to display if none defined in DB

=cut
sub form_field {
    my ($self, %args) = @_;
    my ($o, $table, $column, $edit, $default, $htmlExtra, $linkPage) = ($args{object}, $args{table}, 
									     $args{column}, $args{edit}, $args{default}, $args{htmlExtra}, $args{linkPage} );
    my $label; # return value
    my $value; # return value

    my $tableName = ($o ? $o->table : $table);
    my $id = ($o ? $o->id : "NEW");
    my $current = ($o ? $o->$column : $default);

    my %order    = $self->getcolumnorder( $tableName );
    my %linksto  = $self->getlinksto( $tableName );
    my %tags     = $self->getcolumntags( $tableName );
    my %coltypes = $self->getcolumntypes( $tableName );

    ################################################
    ## column is a local field
    if ( !exists($linksto{$column}) ) {
        if ( exists($tags{$column}) ) {
            $label = $tags{$column};
        }else{
            $label = $column;
        }

        my $type = $coltypes{$column};

        if ($edit) {
            if ($o) {
                $value = $self->getinputtag($column, $o, $current);
            } else {
                $value = $self->getinputtag($column, $table, $current);
            }

            if ($type eq "varchar" || $type eq "timestamp") {
                $value = $self->text_field(object=>$o, table=>$table, column=>$column, edit=>$edit, default=>$default, linkPage=>$linkPage, returnAsVar=>1);

            } elsif ($type eq "long varbinary") {
                $value = $self->text_area(object=>$o, table=>$table, column=>$column, edit=>$edit, returnAsVar=>1, htmlExtra=>$htmlExtra);

            } elsif ($type eq "bool") {
                $value = $self->radio_group_boolean(object=>$o, table=>$table, column=>$column, edit=>$edit, returnAsVar=>1);

            } else {
                $value = "No rule for: $type";
            }

        } else {
            if ($type eq "bool") {
                $value = ($current?"Yes":"No");
            } else {
                $value = $current;
            }
        }
    ################################################
    ## The column is a foreign key. Provide a list to select.
    } else {
        if ( exists($tags{$column}) ) {
            $label = $tags{$column};
        }else{
            $label = $column;
        }

        $value = $self->select_lookup(object=>$o, table=>$tableName, column=>$column,, htmlExtra=>$htmlExtra,
				     lookup=>$linksto{$column}, edit=>$edit, linkPage=>$linkPage, returnAsVar=>1);
    }

    ################################################
    ## Many-to-many relationships
    #  I haven't thought about how to handle the many-to-many relationships 
    #  that use select_multiple. I left any calls to select_multiple in the 
    #  html files alone.

    my %returnhash;
    $returnhash{'label'} = $label;
    $returnhash{'value'} = $value;
    return %returnhash;
}


=head2 select_lookup

This method deals with fields that are foreign keys.  When the interface is in "edit" mode, the user
is presented with a drop-down list of possible values in the foreign table.  If the number of elements
in the list surpasses maxCount or DEFAULT_SELECTMAX, the user gets a text box where keywords can be
entered to refine the list.  Also, a [new] button is added at the end to allow the user to create
a new instance of the foreign table, which will be automatically selected in the drop-down list.
If not editing, this function only returns the label of the foreign key object.

  $ui->select_lookup(object=>$o, column=>"physaddr", lookup=>"PhysAddr", edit=>"$editgen", linkPage=>1);

Arguments:
  object:       CDBI object, can be null if a table object is included
  table:        Name of table in DB. (required if object is null)
  lookup:       Name of foreign table to look up
  column:       Name of field in DB.
  edit:         True if editing, false otherwise.
  where:        (optional) Key/value pairs to pass to search function in CDBI
  defaults:     (optional) array of objects to be shown in the drop-down list by default
  htmlExtra:    (optional) extra html you want included in the output. Common
                use would be to include style="width: 150px;" and the like.
  linkPage:     (optional) Make the printed value a link
                to itself via some page (i.e. view.html) 
                (requires that column value is defined)
  returnAsVar:  (optional) If true, output is returned as a variable.
                Otherwise, output is printed to STDOUT
  maxCount:     (optional) maximum number of results to display before giving 
                the user the option of refining their results. Defaults to
                DEFAULT_SELECTMAX in configuration files.


=cut

sub select_lookup($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $lookup, $where, $defaults, $isEditing, $htmlExtra, $linkPage, $maxCount, $returnAsVar) = 
	($args{object}, $args{table}, 
	 $args{column}, $args{lookup},
	 $args{where}, $args{defaults}, $args{edit},
	 $args{htmlExtra}, $args{linkPage},
	 $args{maxCount}, $args{returnAsVar});

    my @defaults = @$defaults if $defaults;
    unless ( $o || $table ){
	$self->error("Need to pass object or table name");
	return 0;
    }
    unless ( $lookup && $column ){
	$self->error("Need to specify table and field to look up");
	return 0;
    }

    my $output;
    
    $htmlExtra = "" if (!$htmlExtra);
    $maxCount = $args{maxCount} || $self->{config}->{"DEFAULT_SELECTMAX"};
    my @labels = $self->getlabelarr($lookup);

    if ($isEditing){
        my ($count, @fo);
        my $tableName = ($o ? $o->table : $table);
        my $id = ($o ? $o->id : "NEW");
        my $name = $tableName . "__" . $id . "__" . $column;
        
        if (@defaults){
            @fo = @defaults;
            $count = scalar(@fo);
        }elsif ($where){
            @fo = $lookup->search($where);
            $count = scalar(@fo);
        }else {
            $count = $lookup->count_all;
        }
        
        # if the selected objects are within our limits,
	# or if we've been passed a specific default list, 
	# show the select box.
        if ($count <= $maxCount || @defaults){
            @fo = $lookup->retrieve_all() if (!$where && !@defaults);
	    @fo = map  { $_->[0] }
	    sort { $a->[1] cmp $b->[1] }
	    map { [$_ , $self->getlabelvalue($_, \@labels)] } @fo;

            # if an object was passed we use it to obtain table name, id, etc
            # as well as add an initial element to the selection list.
            if ($o){
                $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $htmlExtra);
		$output .= sprintf("<option value=\"0\" selected>-- Select --</option>\n");
                if ( int($o->$column) ){
                    $output .= sprintf("<option value=\"%s\" selected>%s</option>\n", 
				       $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
                }
            }
            # otherwise a couple of things my have happened:
            #   1) this is a new row in some table, thus we lack an object
            #      reference and need to create a new one. We rely on the supplied 
            #      "table" argument to create the fieldname, and do so with the
            #      id of "NEW" in order to force insertion when the user hits submit.
            elsif ($table){
                $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $htmlExtra);
                $output .= sprintf("<option value=\"0\" selected>-- Select --</option>\n");
            }else{
            #   2) The apocalypse has dawned. No table argument _or_ valid DB object..lets bomb out.
                $self->error("Unable to determine table name. Please pass valid object and/or table name.\n");
                return 0;
            }

            foreach my $fo (@fo){
		next unless (ref($fo) && int($fo) != 0 );
                next if ($o && $o->$column && ($fo->id == $o->$column->id));
                $output .= sprintf("<option value=\"%s\">%s</option>\n", $fo->id, $self->getlabelvalue($fo, \@labels));
            }
	    $output .= sprintf("<option value=\"0\">[null]</option>\n");
            $output .= sprintf("</select>\n");
        }else{
	    # ...otherwise provide tools to narrow the selection to a managable size.
            my $srchf = "_" . $id . "_" . $column . "_srch";
            $output .= "<nobr>";   # forces the text field and button to be on the same line
            $output .= sprintf("<input type=\"text\" name=\"%s\" value=\"Keywords\" onFocus=\"if (this.value == 'Keywords') { this.value = ''; } return true;\">", $srchf);
            $output .= sprintf("<input type=\"button\" name=\"__%s\" value=\"List\" onClick=\"jsrsSendquery(%s, %s.value, \'%s\');\">\n", time(), $name, $srchf, $lookup);
            $output .= "</nobr>";
            $output .= "<nobr>";   # forces the select box and "new" link to be on the same line
            $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $htmlExtra);
            $output .= sprintf("<option value=\"0\" selected>-- Select --</option>\n");
            if ($o && $o->$column){
                $output .= sprintf("<option value=\"%s\" selected>%s</option>\n", 
				   $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
            }
    	    $output .= sprintf("<option value=\"0\">[null]</option>\n");
            $output .= sprintf("</select>\n");
        }

        # show link to add new item to this table
        $output .= sprintf("<a href=\"#\" onClick=\"openinsertwindow('table=%s&select_id=%s&selected=1');\">[new]</a>", 
			   $lookup, $name);
        $output .= "</nobr>";

    }elsif ($linkPage && $o->$column ){
	if ($linkPage eq "1" || $linkPage eq "view.html"){
	    my $rtable = $o->$column->table;
	    $output .= sprintf("<a href=\"view.html?table=%s&id=%s\"> %s </a>\n", 
			       $rtable, $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
	}else{
	    $output .= sprintf("<a href=\"$linkPage?id=%s\"> %s </a>\n", 
			       $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
	}
    }else{
        $output .= sprintf("%s\n", ($o->$column ? $self->getlabelvalue($o->$column, \@labels) : ""));
    }

    if ($returnAsVar==1) {
        return $output;
    }else{
        print $output;
    }
}

=head2 select_multiple

Meant to be used with Many-to-Many relationships.
When editing, creates a <select> form input with the MULTIPLE flag to allow user to select more than one object.
It also presents a [add] button to allow user to insert another join.
The idea is to present the objects form the 'other' table but act on the join table objects.

The following diagram might help in understanding the method

  this                 join                other
 +------+             +------+            +------+  
 |      |             |      |            |      |
 |      |<------------|t    o|----------->|      |
 |      |             |      |            |      |
 +------+ Many    One +------+One    Many +------+



Arguments:

object:       Object from which the relationships are viewed (from this table)
joins:        Array ref of join table objects
join_table:   Name of the join table
this_field:   Field in the join table that points to this table
other_table:  Name of the other table (required)
other_field:  Field in the join table that points to the other table
isEditing:    Whether to create the form input tags or just present the object
action:       What selecting the objects will eventually do.  
              Valid actions are: "delete"
makeLink:     If true, will show the object as a link via "linkPage"
linkPage:     Page to pass the object to for viewing
returnAsVar:  Whether to print to STDOUT or return a scalar.

=cut

sub select_multiple {
    my ($self, %args) = @_;
    my ($o, $joins, $join_table, $this_field, $other_table, 
	$other_field, $isEditing, $action, $makeLink, $linkPage, $returnAsVar ) = 
	    ($args{object}, $args{joins}, $args{join_table}, $args{this_field}, $args{other_table}, 
	     $args{other_field}, $args{isEditing}, $args{action}, $args{makeLink}, $args{linkPage}, $args{returnAsVar});

    $linkPage ||= "view.html";
    $action   ||= "delete";

    my @joins;
    if ( $joins ){
	unless ( ref($joins) eq "ARRAY" ){
	    $self->error("joins parameter must be an arrayref");
	    return 0;
	}
	@joins = @{$joins};
    }
    unless ( $join_table ) {
	$self->error("Must provide join table name");
	return 0;
    }
 
    # See UI::form_to_db()
    my $select_name;
    if ( $action eq "delete" ){
	$select_name  =  $join_table . "__LIST__DELETE";
    } else{ # Have yet to think of other actions
	$self->error("action $action not valid");
	return 0;
    }
    my $output;

    if ( $isEditing  ){
	$output .= "<select name=\"$select_name\" id=\"$select_name\" MULTIPLE>\n";
	foreach my $join ( @joins ){
	    my $other  = $join->$other_field;
	    my $lbl = $self->getobjlabel($other);
	    $output .= "<option value=" . $join->id . ">$lbl</option>\n";
	}
	$output .= "</select>";
	$output .= "<a href=\"#\" onClick=\"openinsertwindow('table=$join_table&$this_field=";
	$output .= $o->id;
	$output .= "&select_id=$select_name&selected=0')\">[add]</a>";
	if ( @joins ){
	    $output .= '<br>(*) Selecting will delete';
	}

    }else{ 
	foreach my $join ( @joins ){
	    my $other  = $join->$other_field;
	    my $lbl = $self->getobjlabel($other);
	    if ( $makeLink ){
		$output .= "<a href=\"$linkPage?table=$other_table&id=" . $other->id . "\">$lbl</a><br>";
	    }else{
		$output .= "$lbl<br>";
	    }
	}
    }
    if ($returnAsVar==1) {
        return $output;
    }else{
        print $output;
    }
}


=head2 radio_group_boolean

   $ui->radio_group_boolean(object=>$o, column=>"monitored", edit=>$editmgmt);

 Simple yes/no radio button group. 

 Arguments:
   - object: DBI object, can be null if a table object is included
   - table: Name of table in DB. (required if object is null)
   - column: name of field in DB.
   - edit: true if editing, false otherwise.

=cut

sub radio_group_boolean($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $returnAsVar) = ($args{object}, $args{table}, 
                                            $args{column}, $args{edit}, $args{returnAsVar} );
    my $output;

    my $tableName = ($o ? $o->table : $table);
    my $id = ($o ? $o->id : "NEW");
    my $value = ($o ? $o->$column : "");
    my $name = $tableName . "__" . $id . "__" . $column;
    
    
     unless ($o || $table){
	 $self->error("Unable to determine table name. Please pass valid object and/or table name.\n");
	 return 0;
     }

    if ($isEditing){
        $output .= sprintf("Yes<input type=\"radio\" name=\"%s\" value=\"1\" %s>&nbsp;\n", $name, ($value ? "checked" : ""));
        $output .= sprintf("No<input type=\"radio\" name=\"%s\" value=\"0\" %s>\n", $name, (!$value ? "checked" : ""));
    }else{
        $output .= sprintf("%s\n", ($value ? "Yes" : "No"));
    }

    if ($returnAsVar==1) {
        return $output;
    }else{
        print $output;
    }
}

=head2 text_field

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
   - returnAsVar: default false, true if the sub should return the string instead of outputting

=cut

sub text_field($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $htmlExtra, $linkPage, $default, $returnAsVar) = ($args{object}, $args{table}, 
									     $args{column}, $args{edit}, 
									     $args{htmlExtra}, $args{linkPage},
									     $args{default}, $args{returnAsVar} );
    
    my $output;

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
        $output .= sprintf("<input type=\"text\" name=\"%s\" value=\"%s\" %s>\n", $name, $value, $htmlExtra);
    }elsif ( $linkPage && $value){
	if ( $linkPage eq "1" || $linkPage eq "view.html" ){
	    $output .= sprintf("<a href=\"view.html?table=%s&id=%s\"> %s </a>\n", $tableName, $o->id, $value);
	}else{
    	    $output .= sprintf("<a href=\"$linkPage?id=%s\"> %s </a>\n", $o->id, $value);
	}
    }else{
        $output .= sprintf("%s", $value);
    }

    if ($returnAsVar==1) {
        return $output;
    }else{
        print $output;
    }
}

=head2 text_area

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

sub text_area($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $htmlExtra, $returnAsVar) = ($args{object}, $args{table}, 
                                                                      $args{column}, $args{edit}, 
                                                                      $args{htmlExtra}, $args{returnAsVar} );
    my $output;

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
        $output .= sprintf("<textarea name=\"%s\" %s>%s</textarea>\n", $name, $htmlExtra, $value);
    }else{
        $output .= sprintf("<pre>%s</pre>\n", $value);
    }

    if ($returnAsVar==1) {
        return $output;
    }else{
        print $output;
    }
}


=head2 percent_bar

 Generates a graphical representation of a percentage as a progress bar.
 Can pass arguments in as either a straight percentage, or as a fraction.

 Arguments:
    - percent: percentage (expressed as a number between 0 and 100) e.g. (100, 45, 23.33, 0)
    or
    - numerator
    - denominator (0 in the denominator means 0%)

 Returns a string with HTML, does not output to the browser.

=cut
sub percent_bar {
    my ($self, %args) = @_;
    my ($percent, $numerator, $denominator) = ($args{percent}, $args{numerator}, $args{denominator});
    my $width;
    my $output;

    if ($percent) {
        if ($percent <= 0) {
            $width = 0;
        } else {
            $width = int($percent);
            if ($width < 1 ) {
                $width = 1;
            }
        }
    } else {
        if ($numerator <= 0 || $denominator <= 0) {
            $width = 0;
            $percent = 0;
        } else {
            $width = int($numerator/$denominator*100);
            $percent = $numerator/$denominator*100;
            if ($width < 1 ) {
                $width = 1;
            }
        }
    }

    $output .= '<div class="progress_bar" title="'.(int($percent*10)/10).'%">';
    $output .= '<div class="progress_used" style="width:'.$width.'%">';
    $output .= '</div></div>';

    return $output;
}


=head2 percent_bar2

 Generates a graphical representation of two percentages as a progress bar.
 Can pass arguments in as either a straight percentage, or as a fraction.

 Arguments:
    - percent1: percentage (expressed as a number between 0 and 100) e.g. (100, 45, 23.33, 0)
    - percent2: percentage (expressed as a number between 0 and 100) e.g. (100, 45, 23.33, 0)
    or
    - numerator1
    - denominator2 (0 in the denominator means 0%)
    - numerator1
    - denominator2 (0 in the denominator means 0%)
    
 Returns a string with HTML, does not output to the browser.

=cut
sub percent_bar2 {
    my ($self, %args) = @_;
    my ($percent1, $numerator1, $denominator1, $title1) = ($args{percent1}, $args{numerator1}, $args{denominator1}, $args{title1});
    my ($percent2, $numerator2, $denominator2, $title2) = ($args{percent2}, $args{numerator2}, $args{denominator2}, $args{title2});
    my $width1;
    my $width2;
    my $output;

    if ($percent1) {
        if ($percent1 <= 0) {
            $width1 = 0;
        } else {
            $width1 = int($percent1);
            if ($width1 < 1 ) {
                $width1 = 1;
            }
        }
    } else {
        if ($numerator1 <= 0 || $denominator1 <= 0) {
            $width1 = 0;
            $percent1 = 0;
        } else {
            $width1 = int($numerator1/$denominator1*100);
            $percent1 = $numerator1/$denominator1*100;
            if ($width1 < 1 ) {
                $width1 = 1;
            }
        }
    }
    if ($percent2) {
        if ($percent2 <= 0) {
            $width2 = 0;
        } else {
            $width2 = int($percent2);
            if ($width2 < 1 ) {
                $width2 = 1;
            }
        }
    } else {
        if ($numerator2 <= 0 || $denominator2 <= 0) {
            $width2 = 0;
            $percent2 = 0;
        } else {
            $width2 = int($numerator2/$denominator2*100);
            $percent2 = $numerator2/$denominator2*100;
            if ($width2 < 1 ) {
                $width2 = 1;
            }
        }
    }

    $title1 .= (int($percent1*10)/10);
    $title2 .= (int($percent2*10)/10);

    $output .= '<div class="progress_bar2">';
    $output .= '<div class="progress_used2_n" style="width:'.$width1.'%" title="'.$title1.'%"></div>';
    $output .= '<div class="progress_used2_s" style="width:'.$width2.'%" title="'.$title2.'%"></div>';
    $output .= '</div>';

    return $output;
}



=head2 color_mix

 Mixes two hex colors by the amount specified.

 Arguments:
    - color1: should be a string like "ff00cc" 
    - color2: same
    - blend:  0 means all of color1, 1 means all of color2, 0.5 averages the two

 Returns a hex string like "99aacc"

=cut

sub color_mix {
    my ($self, %args) = @_;
    my ($color1, $color2, $blend) = ($args{color1}, $args{color2}, $args{blend});

    my $r1 = hex substr($color1,0,2);
    my $g1 = hex substr($color1,2,2);
    my $b1 = hex substr($color1,4,2);
    my $r2 = hex substr($color2,0,2);
    my $g2 = hex substr($color2,2,2);
    my $b2 = hex substr($color2,4,2);

    my $r3 = $r1 + ($r2-$r1)*$blend;
    my $g3 = $g1 + ($g2-$g1)*$blend;
    my $b3 = $b1 + ($b2-$b1)*$blend;

    $r3 = unpack("H2", pack("I", $r3));
    $g3 = unpack("H2", pack("I", $g3));
    $b3 = unpack("H2", pack("I", $b3));
    
    return $r3.$g3.$b3;
}


=head2 friendly_percent

 Returns a string representation of the integer percentage of a/b

 Arguments:
    - value: the numerator.
    - total: the denominator.

 If value/total < 0.01, returns a string "<1%" instead of the "0%" which
 would otherwise show up. Similarly, with 99%.

=cut
sub friendly_percent {
    my ($self, %args) = @_;
    my ($value, $total) = ($args{value}, $args{total});
    my $string;

    if ($value == 0) {
        return "0%";
    } elsif ($value == $total) {
        return "100%";
    } else {
        my $p = int(($value*100) / $total);

        if ($p < 1) {
            return "<1%";
        } elsif ($p >= 99) {
            return ">99%";
        } else {
            return $p."%";
        }
    }   
}

=head2 format_size

  Turns "1048576" into "1mb". Allows user to specify maximum unit to show.

  Arguments:
    $bytes - integer value
    $max_unit - how many divisions by 1024 to allow at most. (i.e. 3 would show $bytes in gigabytes)

=cut
sub format_size {
    my ($self, $bytes, $max_unit) = @_;
    my $size_index = 0;
    my @sizes = ('B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB');

    if( $max_unit == 0 ) { $max_unit = 2; }
    if( $max_unit > @sizes ) { $max_unit = @sizes; }

    while( $bytes > 1024 && $size_index < $max_unit ) {
        $bytes = $bytes / 1024;
        $size_index++;
    }

    return sprintf("%.0f",$bytes).' '.($sizes[$size_index]);
}
