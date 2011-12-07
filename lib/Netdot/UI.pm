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
use lib "<<Make:LIB>>";
use base qw( Netdot );
use Netdot::Model;
use Apache::Session::File;
use Apache::Session::Lock::File;
use GraphViz;
use Apache2::SiteControl;
use strict;

my $logger = Netdot->log->get_logger("Netdot::UI");

# Some tables have a specific view page. 
#
my %VIEWPAGE = ( BinFile     => "../generic/display_bin.html",
		 Closet      => "../cable_plant/closet.html",
		 Circuit     => "../cable_plant/circuit.html",
		 ContactList => "contactlist.html",
		 Device      => "../management/device.html",
		 DhcpScope   => "../management/scope.html",
		 Interface   => "../management/interface.html",
		 Ipblock     => "../management/ip.html",
		 PhysAddr    => "../management/mac.html",
		 RR          => "../management/host.html",
		 Zone        => "../management/zone.html",
		 );


=head1 METHODS


############################################################################
=head2 new

  $ui = Netot::UI->new();

Creates a new UI object (basic constructor)

=cut

sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    
    # Create a session wrapper object
    bless $self, $class;
    wantarray ? ( $self, '' ) : $self; 
}
 

#############################################################################
=head2 mk_session - create state for a session across multiple pages
    Creates a state session that can be used to store data across multiple 
    web pages for a given session.  Returns a hash reference to store said data
    in.  The session-id is $session->{_session_id}.  Be aware that you do not want 
    to de-ref the hash reference (otherwise, changes made to the subsequent hash are lost).
    
 Arguments:
    None
  Returns:
    Hash reference
  Examples:
    $session = $ui->mk_session();

=cut
sub mk_session {
    my($self) = @_;
    my (%session, $sid);
    my $TMP = $self->config->get('TMP');
    tie %session, 'Apache::Session::File',
    $sid, { Directory => "$TMP/sessions", LockDirectory => "$TMP/sessions/locks" };
    
    return \%session ;
}

#############################################################################
=head2 get_session - fetch state for a session across multiple pages

    Fetches a state session and its accompanying data.  Returns a hash ref.  
    Requires two arguments:  the working directory and the session-id (as described above).  
    The same warning for mksession() regarding de-referencing the returned object applies.
    
  Arguments:
    Session ID
  Returns:
    Hash reference
  Examples:
    $sid = $args{sid};  # session-id must be handed off to new pages
    $session = $ui->get_session($sid);

=cut
sub get_session {
    my($self, $sid) = @_;
    my %session;
    my $TMP = $self->config->get('TMP');
    tie %session, 'Apache::Session::File', 
    $sid, { Directory => "$TMP/sessions", LockDirectory => "$TMP/sessions/locks" };
    return \%session;
}

############################################################################
=head2 rm_session

    Removes specific session associated with the hash %session.

 Arguments:
    - $session:  Reference to a hash containing session data
  Returns:

  Examples:
    $ui->rm_session($session);

=cut
sub rm_session {
  my( $self, $session ) = @_;
  tied(%{$session})->delete();
}

############################################################################
=head2 rmsessions

    Removes state older than $age (the supplied argument) from the directory $dir.  
    
 Arguments:
    - $dir: Directory where session files are located
    - $age: Seconds
  Returns:
    True on success, False on failure
  Examples:
    $dir = "/tmp";
    $age = 3600;   # age is in seconds
    $ui->rmsessions( $dir, $age );

=cut
sub rmsessions {
    my( $self, $dir, $age ) = @_;
    my $locker = new Apache::Session::Lock::File ;
    $locker->clean( $dir, $age );
}


############################################################################
=head2 form_to_db

Generalized code for updating columns in different tables. 

  Arguments:
    Hash with the following format:
    
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

  Returns:
    Returns a hash with update details on success, false on failure and error 
    should be set.
  Examples:

    %info = $ui->form_to_db(%ARGS);

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
    $self->throw_user("Missing name/value pairs.") unless (scalar keys(%objs));
    foreach my $table (keys %objs){
	my %todelete;
	
	foreach my $id (keys %{ $objs{$table} }){

	    my $act = 0; 

	    # If our id is 'NEW' we want to insert a new row in the DB.
	    # Do a regex to allow sending many NEW groups for the same table
	    if ( $id =~ /NEW/i ){
		my $newid;
		$newid = $table->insert(\%{ $objs{$table}{$id} });
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
		    if ( my $o = $table->retrieve($id) ){
			$o->update(\%{ $objs{$table}{$id} });
			$ret{$table}{id}{$id}{action}  = "UPDATED";
			$ret{$table}{id}{$id}{columns} = \%{ $objs{$table}{$id} };
		    }
		}
	    }
	}
	
	# Delete marked objects (do this once per table)
	foreach my $id ( keys %todelete ){
	    my $o = $table->retrieve($id) || next;
	    $o->delete();
	    $ret{$table}{id}{$id}{action} = "DELETED";
	}
    }
    return %ret;
}


############################################################################
=head2 form_field - Generate a HTML form field.

    This method detects the type of form input required for the object, and then calls the appropriate
    method in UI.pm. Either select_lookup, select_multiple, radio_group_boolean/checkbox_boolean, text_field, or text_area.
    If the interface is in "edit" mode, the user will see a form element specific to the type of data
    being viewed, otherwise, the user will see the value of the object in plain text.
    
  Arguments: 
    - object:         DBI object, can be null if a table object is included
    - table:          Name of table in DB. (optional, but required if object is null)
    - column:         Name of the field in the database
    - edit:           True if editing, false otherwise
    - new_button:     Show [new] button to create new foreign objects
    - default:        Default value to display if none defined in DB (defined by object)
    - defaults:       Default values to add to select box
    - htmlExtra:      String of additional html to add to the form field
    - linkPage:       Make this text a link
    - returnValOnly:  Return only the form field and no label as a string
    - shortFieldName: Whether to set the input tag name as the column name or
                      the format used by form_to_db()
    - adv_search:     uses radio button groups for true/false/unset instead of
                      checkboxes which only have true/false
    - no_help         Do not show [?] help link
  Returns:
    if returnValOnly, the form field as a string
    else, a hash reference, with two keys, 'label', 'value'

  Examples:

    %tmp = $ui->form_field(object=>$o, column=>"info", edit=>1, htmlExtra=>'cols="60"');

=cut
sub form_field {
    my ($self, %args) = @_;
    my ($o, $column) = @args{'object', 'column'};

    $self->throw_fatal("You need to pass a valid object or a table name") 
	unless ( ref($o) || $args{table} );

    $self->throw_fatal("You need to pass a column name") 
	unless ( $column );
    
    my ($label, $value); # return values
    
    my $table   = ($o ? $o->short_class : $args{table});
    my $id      = ($o ? $o->id      : "NEW");
    my $current = ($o ? $o->$column : $args{default});
    $args{new_button} = 1 unless defined $args{new_button};

    
    my $mtable  = $table->meta_data;
    my $mcol    = $mtable->get_column($column);
    my $f_table = $mcol->links_to;
    $label      = $mcol->tag || $column;

    ################################################
    ## The column is a foreign key. Provide a list to select.
    if ( defined $f_table  ){
        $value = $self->select_lookup(object=>$o, table=>$table, column=>$column, htmlExtra=>$args{htmlExtra}, 
				      lookup=>$f_table, edit=>$args{edit}, new_button=>$args{new_button},
				      linkPage=>$args{linkPage}, default=>$args{default},
				      defaults=>$args{defaults}, returnAsVar=>1, shortFieldName=>$args{shortFieldName});
    }
    ################################################
    ## column is a local field
    else {
        my $type = $mcol->sql_type;

	if ( $type =~ /^varchar|timestamp|integer|numeric|bigint$/ ){
	    $value = $self->text_field(object=>$o, table=>$table, column=>$column, edit=>$args{edit}, 
				       default=>$args{default}, defaults=>$args{defaults}, linkPage=>$args{linkPage}, 
				       returnAsVar=>1, 
				       htmlExtra=>$args{htmlExtra}, shortFieldName=>$args{shortFieldName});
	    
	}elsif ( $type eq 'date' ){
	    $value = $self->date_field(object=>$o, table=>$table, column=>$column, edit=>$args{edit}, 
				       default=>$args{default}, returnAsVar=>1, shortFieldName=>$args{shortFieldName} );
	    
	} elsif ( $type eq 'blob' || $type eq 'text' ) {
	    $value = $self->text_area(object=>$o, table=>$table, column=>$column, edit=>$args{edit}, 
				      returnAsVar=>1, htmlExtra=>$args{htmlExtra}, shortFieldName=>$args{shortFieldName});
	    
	} elsif ( $type eq 'bool' ) {
	    if ( $args{adv_search} == 1 ) {
		$value = $self->radio_group_boolean(object=>$o, table=>$table, column=>$column, edit=>$args{edit}, 
						returnAsVar=>1, shortFieldName=>$args{shortFieldName}, adv_search=>1);
	    } else {
		$value = $self->checkbox_boolean(object=>$o, table=>$table, column=>$column, edit=>$args{edit}, 
						returnAsVar=>1, shortFieldName=>$args{shortFieldName});
	    }
	    
	} elsif ( $table =~ /Picture/ && $type eq 'longblob' ) {
	    if ( ! $args{edit} ){
		my $alt = $o->filename;
		$value = "<a href=\"display_bin.html?table=$table&id=$id\"><img width=\"150\" height=\"150\" alt=\"$alt\"src=\"display_bin.html?table=$table&id=$id\" ></a>";
	    }

	} else {
	    $self->throw_fatal("Unknown column type $type for column $column in table $table");
	}
	
    }

    ################################################
    ## Many-to-many relationships
    #  I haven't thought about how to handle the many-to-many relationships 
    #  that use select_multiple. I left any calls to select_multiple in the 
    #  html files alone.

    if( $args{returnValOnly} ) {
        return $value;
    } else {
        my %returnhash;
	unless ( $args{no_help} ){
	    $label = $self->col_descr_link($table, $column, $label);
	}
	if ( $args{edit} && 
	     ($mcol->is_unique || ($mcol->sql_type =~ /^varchar|timestamp|date|blob$/ 
				   && !$mcol->is_nullable)) ){  
	    $label .= "<font color=\"red\">*</font>" 
	}
        $returnhash{label} = $label . ':';
        $returnhash{value} = $value;
        return %returnhash;
    }
}

############################################################################
=head2 table_descr_link - Generate link to display a table\'s description

  Arguments:
    table name
    text string for link
  Returns:
    HTML link string
  Examples:
    print $ui->table_descr_link($table, $text);
    
=cut
sub table_descr_link{
    my ($self, $table, $text) = @_;
    return $self->help_link("descr.html?table=$table&showheader=0", 'Help', 'width=600,height=200', $text);
}

############################################################################
=head2 col_descr_link - Generate link to display a column\'s description

  Arguments:
    table name
    column name
    text string for link
  Returns:
    HTML link string
  Examples:
    print $ui->col_descr_link($table, $col, $text);
    
=cut
sub col_descr_link{
    my ($self, $table, $column, $text) = @_;
    return $self->help_link("descr.html?table=$table&col=$column&showheader=0", 'Help', 'width=600,height=200', $text);
}

############################################################################
=head2 help_link - Generate link for help popop page

  Arguments:
    url
    window title
    window size
    text string for link
  Returns:
    HTML link string
    
=cut
sub help_link {
    my ($self, $url, $title, $size, $text) = @_;
    $title ||= 'Netdot Help Window';
    $size  ||= 'width=600,height=400';
    $text  ||= '[?]';
    $self->throw_fatal("Missing required arguments: URL")
	unless ($url);

    return "<a class=\"hand\" onClick=\"window.open('$url', '$title', '$size');\">$text</a>";
  
}

############################################################################
=head2 select_lookup

    This method deals with fields that are foreign keys.  When the interface is in "edit" mode, the user
    is presented with a drop-down list of possible values in the foreign table.  If the number of elements
    in the list surpasses maxCount or DEFAULT_SELECTMAX, the user gets a text box where keywords can be
    entered to refine the list.  Also, a [new] button is added at the end to allow the user to create
    a new instance of the foreign table, which will be automatically selected in the drop-down list.
    If not editing, this function only returns the label of the foreign key object.

 Arguments:
    Hash of key/value pairs.  Keys are:
    - object:        CDBI object, can be null if a table object is included
    - table:          Name of table in DB. (required if object is null)
    - lookup:         Name of foreign table to look up
    - column:         Name of field in DB.
    - edit:           True if editing, false otherwise.
    - new_button:     Show [new] button to create new foreign objects
    - where:         (optional) Key/value pairs to pass to search function in CDBI
    - defaults:      (optional) array of objects to be shown in the drop-down list by default, 
    - default:       (optional) id of the object in defaults that should be selected by default
    - htmlExtra:     (optional) extra html you want included in the output. Common
                      use would be to include style="width: 150px;" and the like.
    - linkPage:      (optional) Make the printed value a link
                     to itself via some page (i.e. view.html) 
                     (requires that column value be defined)
    - returnAsVar:   (optional) If true, output is returned as a variable.
                     Otherwise, output is printed to STDOUT
    - maxCount:      (optional) maximum number of results to display before giving 
                     the user the option of refining their results. Defaults to
                     DEFAULT_SELECTMAX in configuration files.
   - shortFieldName: Whether to set the input tag name as the column name or
                     the format used by form_to_db()
  Returns:
    If returnAsVar, returns variable containing HTML code.  Otherwise, prints HTML code to STDOUT
    or False if failure
  Examples:

    $ui->select_lookup(object=>$o, column=>"physaddr", lookup=>"PhysAddr", edit=>"$editgen", linkPage=>1);

=cut

sub select_lookup{
    my ($self, %args) = @_;
    my ($o, $column) = @args{'object', 'column'};
    $self->throw_fatal("Need to pass object or table name") unless ( $o || $args{table} );
    my $table  = ($o ? $o->short_class : $args{table});
    $self->throw_fatal("Need to specify table and field to look up") unless ( $args{lookup} && $column );

    my @defaults = @{$args{defaults}} if $args{defaults};

    my $output;
    
    $args{htmlExtra} = "" if ( !defined $args{htmlExtra} );
    $args{maxCount} ||= $self->config->get('DEFAULT_SELECTMAX');
    $args{new_button} = 1 unless defined $args{new_button};

    my $name;
    my $id = ($o ? $o->id : "NEW");
    if( $args{shortFieldName} ) {
	$name = $column;
    } else {
	$name = $table . "__" . $id . "__" . $column;
    }
    if( $args{edit} && $args{default} ) { 
	# If there is a default element specified, then we don't actually want a list of choices.
	# So, don't show a select box, but instead, make a hidden form element with the id,
	# and print out the name of the default element. 
	
	# should be only 1 element in @defaults
	$output .= '<input type="hidden" name="'.$name.'" value="'.$args{default}.'">';
	$output .= $defaults[0]->get_label;
    } elsif( $args{edit} ){
        my ($count, @fo);
        if ( @defaults ){
            @fo = @defaults;
            $count = scalar(@fo);
        }elsif ( $args{where} ){
            @fo = $args{lookup}->search($args{where});
            $count = scalar(@fo);
        }else {
            $count = $args{lookup}->count_all;
        }
        
        # if the selected objects are within our limits,
	# or if we've been passed a specific default list, 
	# show the select box.
        if ( $count <= $args{maxCount} || @defaults ){
            if ( !$args{where} && !@defaults ){
		@fo = $args{lookup}->retrieve_all();
	    }
	    unless ( @defaults ){
		# Assume the list is ordered when passed to us
		@fo = sort { $a->get_label cmp $b->get_label } @fo;
	    }
            # if an object was passed we use it to obtain table name, id, etc
            # as well as add an initial element to the selection list.
            if ( $o ){
                $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $args{htmlExtra});
		$output .= sprintf("<option value=\"\" selected>-- Select --</option>\n");
                if ( $o->$column ){
                    $output .= sprintf("<option value=\"%s\" selected>%s</option>\n", 
				       $o->$column->id, $o->$column->get_label);
                }
            }
            # otherwise a couple of things my have happened:
            #   1) this is a new row in some table, thus we lack an object
            #      reference and need to create a new one. We rely on the supplied 
            #      "table" argument to create the fieldname, and do so with the
            #      id of "NEW" in order to force insertion when the user hits submit.
            elsif ( $table ){
                $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $args{htmlExtra});
                $output .= "<option value=\"\" ".($args{default} ? "" :"selected").">-- Select --</option>\n";
            }else{
                $self->throw_fatal("Unable to determine table name. Please pass valid object and/or table name.\n");
            }

            foreach my $fo ( @fo ){
		next unless ( ref($fo) && $fo );
                next if ( $o && $o->$column && ($fo->id == $o->$column->id) );
		my $selected = ($fo->id == $args{default} ? "selected" : "");
                $output .= sprintf("<option value=\"%s\" %s>%s</option>\n", $fo->id, $selected, $fo->get_label);
            }
	    $output .= sprintf("<option value=\"\">[null]</option>\n");
            $output .= sprintf("</select>\n");
        }else{
	    # ...otherwise provide tools to narrow the selection to a managable size.
            my $srchf = "_" . $id . "_" . $column . "_srch";
            $output .= "<nobr>";   # forces the text field and button to be on the same line
            $output .= sprintf("<input type=\"text\" name=\"%s\" id=\"%s\" value=\"Keywords\" %s onFocus=\"if (this.value == 'Keywords') { this.value = ''; } return true;\">", $srchf, $srchf);
	    $output .= sprintf("<input type=\"button\" name=\"__%s\" value=\"List\" onClick=\"jsrsSendquery(\'%s\', \'%s\', %s.value);\">\n", time(), $args{lookup}, $name, $srchf );
            $output .= "</nobr>";
            $output .= "<nobr>";   # forces the select box and "new" link to be on the same line
            $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $args{htmlExtra});
            $output .= sprintf("<option value=\"\" selected>-- Select --</option>\n");
            if ( $o && $o->$column ){
                $output .= sprintf("<option value=\"%s\" selected>%s</option>\n", 
				   $o->$column->id, $o->$column->get_label);
            }
    	    $output .= sprintf("<option value=\"\">[null]</option>\n");
            $output .= sprintf("</select>\n");
        }

	if ( $args{new_button} ){
	    # show link to add new item to this table
	    $output .= sprintf("<a class=\"hand\" onClick=\"openinsertwindow('table=%s&select_id=%s&selected=1&dowindow=1');\">[new]</a>", 
			       $args{lookup}, $name);
	    $output .= "</nobr>";
	}
	
    }elsif ( $args{linkPage} && $o->$column ){
	if ( $args{linkPage} eq "1" || $args{linkPage} eq "view.html" ){
	    my $rtable = $o->$column->short_class;
	    $output .= sprintf("<a href=\"view.html?table=%s&id=%s\"> %s </a>\n", 
			       $rtable, $o->$column->id, $o->$column->get_label);
	}else{
	    $output .= sprintf("<a href=\"$args{linkPage}?id=%s\"> %s </a>\n", 
			       $o->$column->id, $o->$column->get_label);
	}
    }else{
        $output .= sprintf("%s\n", ($o->$column ? $o->$column->get_label : ""));
    }

    if ( $args{returnAsVar} == 1 ) {
        return $output;
    }else{
        print $output;
    }
}

############################################################################
=head2 select_multiple - Create <select> form tag with MULTIPLE flag

    Meant to be used with Many-to-Many relationships.
    When editing, creates a <select> form input with the MULTIPLE flag to allow user to select more than one object.
    It also presents a [add] button to allow user to insert another join.
    The idea is to present the objects from the 'other' table but act on the join table objects.
    
    The following diagram might help in understanding the method

    this                 join                other
    +------+             +------+            +------+  
    |      |             |      |            |      |
    |      |<------------|t    o|----------->|      |
    |      |             |      |            |      |
    +------+ Many    One +------+One    Many +------+
    

  Arguments:
    Hash of key/value pairs.  Keys are:
    - object:       Object from which the relationships are viewed (from this table)
    - joins:        Array ref of join table objects
    - join_table:   Name of the join table
    - this_field:   Field in the join table that points to this table
    - other_table:  Name of the other table (required)
    - other_field:  Field in the join table that points to the other table
    - isEditing:    Whether to create the form input tags or just present the object
    - action:       What selecting the objects will eventually do.  
                    Valid actions are: "delete"
    - makeLink:     If true, will show the object as a link via "linkPage"
    - linkPage:     Page to pass the object to for viewing
    - returnAsVar:  Whether to print to STDOUT or return a scalar.
  Returns:
    If returnAsVar, returns variable containing HTML code.  Otherwise, prints HTML code to STDOUT
    or False if failure
  Examples:

    $ui->select_multiple(object=>$o, joins=>\@devcontacts, join_table=>"DeviceContacts", 
			 this_field=>"device", other_table=>"ContactList", 
			 other_field=>"contactlist", isEditing=>$editloc, action=>"delete", 
			 makeLink=>1, returnAsVar=>1 ) 
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
	    $self->throw_fatal("joins parameter must be an arrayref");
	}
	@joins = @{$joins};
    }
    unless ( $join_table ) {
	$self->throw_fatal("Must provide join table name");
    }
 
    # See UI::form_to_db()
    my $select_name;
    if ( $action eq "delete" ){
	$select_name  =  $join_table . "__LIST__DELETE";
    } else{ # Have yet to think of other actions
	$self->throw_fatal("action $action not valid");
    }
    my $output;

    if ( $isEditing  ){
	$output .= "<select name=\"$select_name\" id=\"$select_name\" MULTIPLE>\n";
	foreach my $join ( @joins ){
	    my $other  = $join->$other_field;
	    my $lbl = $other->get_label;
	    $output .= "<option value=" . $join->id . ">$lbl</option>\n";
	}
	$output .= "</select>";
	$output .= "<a onClick=\"openinsertwindow('table=$join_table&$this_field=";
	$output .= $o->id;
	$output .= "&select_id=$select_name&selected=0&dowindow=1')\" class=\"hand\">[add]</a>";
	if ( @joins ){
	    $output .= '<br>(*) Selecting will delete';
	}

    }else{ 
	foreach my $join ( @joins ){
	    my $other  = $join->$other_field;
	    my $lbl = $other->get_label;
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


############################################################################
=head2 radio_group_boolean - Create simple yes/no radio button group. 

 Arguments:
   Hash containing key/value pairs.  Keys are:
   - object:         DBI object, can be null if a table object is included
   - table:          Name of table in DB. (required if object is null)
   - column:         Name of field in DB.
   - edit:           True if editing, false otherwise.
   - returnAsVar:    Whether to return output as a variable or STDOUT
   - shortFieldName: Whether to set the input tag name as the column name or
                     the format used by form_to_db()
   - adv_search:     If this is 1 then we provide a third, default radio button
                     with value unset
  Returns:
    String
  Examples:

    $ui->radio_group_boolean(object=>$o, column=>"monitored", edit=>$editmgmt);
   
=cut

sub radio_group_boolean{
    my ($self, %args) = @_;
    my ($o, $table, $column) = @args{'object', 'table', 'column'};
    my $output;

    $table = ($o ? $o->short_class : $table);
    my $id    = ($o ? $o->id : "NEW");
    my $value = ($o ? $o->$column : "");
    my $name  = ( $args{shortFieldName} ? $column : $table . "__" . $id . "__" . $column );
    my $adv_search = ( $args{adv_search} ? 1 : 0 );

    $self->throw_fatal("Unable to determine table name. Please pass valid object and/or table name.\n")
	unless ( $o || $table );

    if ( $args{edit} ){
        if ( $adv_search == 1 ){
            $output .= sprintf("<nobr>Yes<input type=\"radio\" name=\"%s\" value=\"radio_yes\" %s></nobr>&nbsp;\n", $name, "");
            $output .= sprintf("<nobr>No<input type=\"radio\" name=\"%s\" value=\"radio_no\" %s></nobr>\n", $name, "");
            $output .= sprintf("&nbsp;<nobr>Unset<input type=\"radio\" name=\"%s\" value=\"radio_unset\" %s></nobr>\n", $name, "checked");
	}else{
            $output .= sprintf("<nobr>Yes<input type=\"radio\" name=\"%s\" value=\"1\" %s></nobr>&nbsp;\n", $name, ($value ? "checked" : ""));
            $output .= sprintf("<nobr>No<input type=\"radio\" name=\"%s\" value=\"0\" %s></nobr>\n", $name, (!$value ? "checked" : ""));
	}
    }else{
        $output .= sprintf("%s\n", ($value ? "Yes" : "No"));
    }

    if ( $args{returnAsVar} == 1 ) {
        return $output;
    }else{
        print $output;
    }
}

############################################################################
=head2 checkbox_boolean

    A yes/no checkbox, which gets around the problem of an unchecked box sending nothing instead of "no".
    A hidden form field is created, which is where the receiving code actually reads the value. When the
    checkbox is checked, it sets the value of the hidden field to 1, and when it is unchecked, it sets the
    value to 0. This way, the actual value of the checkbox is irrelevant.

 Arguments:
   - object:         DBI object, can be null if a table object is included
   - table:          Name of table in DB. (required if object is null)
   - column:         Name of field in DB.
   - edit:           True if editing, false otherwise.
   - returnAsVar:    Whether to return output as a variable or STDOUT
   - shortFieldName: Whether to set the input tag name as the column name or
                     the format used by form_to_db()

  Examples:
    
   $ui->checkbox_boolean(object=>$o, column=>"monitored", edit=>$editmgmt);


=cut

sub checkbox_boolean{
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $returnAsVar, $shortFieldName) = ($args{object}, $args{table}, 
                                            $args{column}, $args{edit}, $args{returnAsVar}, $args{shortFieldName} );
    my $output;

    $table   = ($o ? $o->short_class : $table);
    my $id      = ($o ? $o->id : "NEW");
    my $value   = ($o ? $o->$column : "");
    my $name    = ( $shortFieldName ? $column : $table . "__" . $id . "__" . $column );
    my $chkname = "____".$name."____";  # name to use for the checkbox, which should be ignored when reading the data

    $self->throw_fatal("Unable to determine table name. Please pass valid object and/or table name.\n")
	unless ($o || $table);
    
    if ($isEditing){
	$output .= '<input type="checkbox" onclick="if (this.checked) { this.form[\''.$name.'\'].value=\'1\'; }else{this.form[\''.$name.'\'].value=\'0\'; }" '.($value?"checked=\"checked\"":"").'>';
	$output .= '<input type="hidden" name="'.$name.'" value="'.$value.'">';
    }else{
        $output .= sprintf("%s\n", ($value ? "Yes" : "No"));
    }
    
    if ($returnAsVar==1) {
        return $output;
    }else{
        print $output;
    }
}


############################################################################
=head2 text_field

Text field widget. If "edit" is true then a text field is displayed with
the value from the DB (if any).

 Arguments:
   Hash containing key/value pairs.  Keys are:
   - object:         DBI object, can be null if a table object is included
   - table:          Name of table in DB. (required if object is null)
   - column:         Name of field in DB.
   - default:        Default value to display if no value is defined in DB.
   - defaults:       Hashref with default values to show in a select box
                     where key=option value, value=option text
   - edit:           True if editing, false otherwise.
   - htmlExtra:      Extra html you want included in the output. Common use
                     would be to include style="width: 150px;" and the like.
   - linkPage:       (optional) Make the printed value a link
                     to itself via some component (i.e. view.html) 
                     (requires that column value be defined)
   - returnAsVar:    default false, true if the sub should return the string instead of outputting
   - shortFieldName: Whether to set the input tag name as the column name or
                     the format used by form_to_db()
  Returns:
    If returnAsVar, returns variable containing HTML code.  Otherwise, prints HTML code to STDOUT
    or False if failure    
  Examples:

    $ui->text_field(object=>$pic->binfile, table=>"BinFile", column=>"filename", edit=>$editPictures);

=cut

sub text_field($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $htmlExtra, $linkPage, $defaults, $default, $returnAsVar, $shortFieldName) = 
	($args{object}, $args{table}, $args{column}, $args{edit}, $args{htmlExtra}, 
	 $args{linkPage}, $args{defaults}, $args{default}, $args{returnAsVar}, $args{shortFieldName} );
    my $output;

    $table     = ($o ? $o->short_class : $table);
    my $id     = ($o ? $o->id : "NEW");
    my $value  = ($o ? $o->$column : $default);
    my $name   = ( $shortFieldName ? $column : $table . "__" . $id . "__" . $column );
    $htmlExtra = "" if (!$htmlExtra);

    $self->throw_fatal("Unable to determine table name. Please pass valid object and/or table name.\n")
	unless ($o || $table) ;

    my $input_type = ($column =~ /^password|snmp_authkey|snmp_privkey$/)? 'password' : 'text';

    if ( $isEditing ){
	if ( $defaults && ref($defaults) eq "HASH" ){
	    # Show a select tag instead
	    $output .= "<select name=\"$name\">";
	    my $value_found = 0;
	    foreach my $key ( sort { $defaults->{$a} cmp $defaults->{$b} } 
			      keys %$defaults ){
		my $v = $defaults->{$key};
		if ( $value eq $key ){
 		    $output .= "<option value=\"$key\" SELECTED>$v</option>";
		    $value_found = 1;
		}else{
		    $output .= "<option value=\"$key\">$v</option>";
		}
	    }
	    unless ( $value_found ){
		$output .= "<option value=\"$value\" SELECTED>$value</option>";
	    }
	    $output .= '</select>';
	}else{
	    $value =~ s/"/&quot;/g;
	    $output .= sprintf("<input type=\"%s\" name=\"%s\" value=\"%s\" %s>\n", $input_type, $name, $value, $htmlExtra);
	}
    }elsif ( $linkPage && $value ){
	$value =~ s/</&lt;/g;
	$value =~ s/>/&gt;/g;
	if ( $linkPage eq "1" || $linkPage eq "view.html" ){
	    $output .= sprintf("<a href=\"view.html?table=%s&id=%s\"> %s </a>\n", $table, $o->id, $value);
	}else{
    	    $output .= sprintf("<a href=\"$linkPage?id=%s\"> %s </a>\n", $o->id, $value);
	}
    }else{
	if ( $input_type ne 'password' ){
	    $value =~ s/</&lt;/g;
	    $value =~ s/>/&gt;/g;
	    $output .= sprintf("%s", $value);
	}
    }

    if ($returnAsVar==1) {
        return $output;
    }else{
        print $output;
    }
}

############################################################################
=head2 date_field

 Arguments:
   Hash containing key/value pairs.  Keys are:
   - object:         DBI object, can be null if a table object is included
   - table:          Name of table in DB. (required if object is null)
   - column:         Name of field in DB.
   - default:        Default value to display if no value is defined in DB.
   - edit:           True if editing, false otherwise.
   - htmlExtra:      Extra html you want included in the output. Common use
                     would be to include style="width: 150px;" and the like.
   - linkPage:       (optional) Make the printed value a link
                     to itself via some component (i.e. view.html) 
                     (requires that column value be defined)
   - returnAsVar:    default false, true if the sub should return the string instead of outputting
   - shortFieldName: Whether to set the input tag name as the column name or
                     the format used by form_to_db()
  Returns:
    If returnAsVar, returns variable containing HTML code.  Otherwise, prints HTML code to STDOUT
    or False if failure    
  Examples:

    $ui->date_field(object=>$rr, table=>"RR", column=>"expiration", edit=>$edit);

=cut

sub date_field($@){
    my ($self, %args) = @_;
    my $output;

    my ($o, $column) = @args{'object', 'column'};
    my $table  = ($o ? $o->short_class : $args{table});
    my $id     = ($o ? $o->id : "NEW");
    my $value  = ($o ? $o->$column : $args{default});
    my $name   = ( $args{shortFieldName} ? $column : $table . "__" . $id . "__" . $column );
    my $htmlExtra = $args{htmlExtra} || "";
    
    $self->throw_fatal("Unable to determine table name. Please pass valid object and/or table name.\n")
	unless ($o || $table) ;
    
    if ( $args{edit} ){
	$value =~ s/"/&quot;/g;
        $output .= sprintf("<input id=\"%s\" type=\"text\" size=\"10\" name=\"%s\" value=\"%s\">", $name, $name, $value);
	$output .= "<img src=\"../img/calendar.gif\" onclick=\"showChooser(this, '$name', 'chooserSpan', 1990, 2050, 'Y-m-d', false);\"/>
<div id=\"chooserSpan\" class=\"dateChooser select-free\" style=\"display: none; visibility: hidden; width: 160px;\"></div>";

    }else{
	$value =~ s/</&lt;/g;
	$value =~ s/>/&gt;/g;
        $output .= sprintf("%s", $value);
    }

    if ( $args{returnAsVar} == 1 ){
        return $output;
    }else{
        print $output;
    }
}


############################################################################
=head2 text_area
    
    Text area widget. If "edit" is true then a textarea is displayed with
    the value from the DB (if any).

 Arguments:
   Hash containing key/value pairs.  Keys are:
    - object:          DBI object, can be null if a table object is included
    - table:           Name of table in DB. (required if object is null)
    - column:          Name of field in DB. 
    - edit:            True if editing, false otherwise.
    - htmlExtra:       Extra html you want included in the output. Common use
                       would be to include style="width: 150px;" and the like.
    - returnAsVar:     Default false, true if the sub should return the string instead of outputting
    - shortFieldName:  Whether to set the input tag name as the column name or
                       the format used by form_to_db()
  Returns:
    If returnAsVar, returns variable containing HTML code.  Otherwise, prints HTML code to STDOUT
    or False if failure    
  Examples:
    $ui->text_area(object=>$o, table=>"HorizontalCable", column=>"info",
		   edit=>$editCable, htmlExtra=>"rows='3' cols='80'");

=cut

sub text_area($@){
    my ($self, %args) = @_;
    my ($o, $table, $column, $isEditing, $htmlExtra, $returnAsVar, $shortFieldName) = 
	($args{object}, $args{table}, $args{column}, $args{edit}, $args{htmlExtra}, 
	 $args{returnAsVar}, $args{shortFieldName} );
    my $output;
    
    $table  = ($o ? $o->short_class : $table);
    my $id     = ($o ? $o->id : "NEW");
    my $value  = ($o ? $o->$column : "");
    my $name   = ( $shortFieldName ? $column : $table . "__" . $id . "__" . $column );
    #textareas need bigger space, so we'll specify a default htmlExtra
    $htmlExtra = "cols='80' rows='10'" if (!$htmlExtra);

    $self->throw_fatal("Unable to determine table name. Please pass valid object and/or table name.\n")
	unless ( $o || $table );
    
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    if ( $isEditing ){
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


############################################################################
=head2 percent_bar

    Generates a graphical representation of a percentage as a progress bar.
    Can pass arguments in as either a straight percentage, or as a fraction.

 Arguments:
   percent: percentage (expressed as a number between 0 and 100) e.g. (100, 45, 23.33, 0)
    or
    numerator
    denominator (0 in the denominator means 0%)
  Returns: 
    a string with HTML, does not output to the browser.
  Examples:

    $ui->percent_bar(percent=>$percent)

=cut
sub percent_bar {
    my ($self, %args) = @_;
    my ($percent, $numerator, $denominator) = ($args{percent}, $args{numerator}, $args{denominator});
    my $width;
    my $output;
    
    if ( $percent ) {
        if ($percent <= 0) {
            $width = 0;
        }else{
            $width = int($percent);
            if ( $width < 1 ) {
                $width = 1;
            }
        }
    }else{
        if ( $numerator <= 0 || $denominator <= 0 ) {
            $width   = 0;
            $percent = 0;
        }else{
            $width   = int($numerator/$denominator*100);
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


############################################################################
=head2 percent_bar2

    Generates a graphical representation of two percentages as a progress bar.
    Can pass arguments in as either a straight percentage, or as a fraction.

 Arguments:
  percent1: percentage (expressed as a number between 0 and 100) e.g. (100, 45, 23.33, 0)
  percent2: percentage (expressed as a number between 0 and 100) e.g. (100, 45, 23.33, 0)
    or
   numerator1
   denominator2 (0 in the denominator means 0%)
   numerator1
   denominator2 (0 in the denominator means 0%)
  Returns: 
    a string with HTML, does not output to the browser.
  Examples:

    $ui->percent_bar2( title1=>"Address Usage: ", title2=>"Subnet Usage: ", 
		       percent1=>$percent1, percent2=>$percent2 ) 
    
=cut
sub percent_bar2 {
    my ($self, %args) = @_;
    my ($percent1, $numerator1, $denominator1, $title1) = 
	($args{percent1}, $args{numerator1}, $args{denominator1}, $args{title1});
    my ($percent2, $numerator2, $denominator2, $title2) = 
	($args{percent2}, $args{numerator2}, $args{denominator2}, $args{title2});
    my $width1;
    my $width2;
    my $output;

    if ( $percent1 ) {
        if ( $percent1 <= 0 ) {
            $width1 = 0;
        }else{
            $width1 = int($percent1);
            if ($width1 < 1 ) {
                $width1 = 1;
            }
        }
    }else{
        if ( $numerator1 <= 0 || $denominator1 <= 0 ){
            $width1 = 0;
            $percent1 = 0;
        }else{
            $width1 = int($numerator1/$denominator1*100);
            $percent1 = $numerator1/$denominator1*100;
            if ($width1 < 1 ) {
                $width1 = 1;
            }
        }
    }
    if ( $percent2 ) {
        if ($percent2 <= 0) {
            $width2 = 0;
        }else{
            $width2 = int($percent2);
            if ($width2 < 1 ) {
                $width2 = 1;
            }
        }
    } else {
        if ( $numerator2 <= 0 || $denominator2 <= 0 ) {
            $width2 = 0;
            $percent2 = 0;
        }else{
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



############################################################################
=head2 color_mix - Mix two hex colors by the amount specified.

 Arguments:
   - $color1: should be a string like "ff00cc" 
   - $color2: same
   - $blend:  0 means all of color1, 1 means all of color2, 0.5 averages the two
  Returns:  
    hex string like "99aacc"
  Examples:
    my $cm = $ui->color_mix(color1=>'ff00cc', color2=>'cc00ff', blend=>0.5);

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


############################################################################
=head2 friendly_percent

    Returns a string representation of the integer percentage of a/b

 Arguments:
    Hash of key/value pairs where keys are:
    - value: the numerator.
    - total: the denominator.
  Returns:
    If value/total < 0.01, returns a string "<1%" instead of the "0%" which
    would otherwise show up. Similarly, with 99%.
  Examples:
    $ui->friendly_percent(value=>$avail,total=>$total)

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

############################################################################
=head2 format_size

    Turns "1048576" into "1MB". Allows user to specify maximum unit to show.

  Arguments:
    $bytes:    integer value
    $max_unit: how many divisions by 1024 to allow at most. (i.e. 3 would show $bytes in gigabytes)
  Returns:
    Formatted string (scalar)
  Examples:
    $ui->format_size($data_len)

=cut
sub format_size {
    my ($self, $bytes, $max_unit) = @_;
    my $size_index = 0;
    my @sizes = ('B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB');

    if( $max_unit == 0 ) { $max_unit = 2; }
    if( $max_unit > scalar @sizes ) { $max_unit = scalar @sizes; }

    while( $bytes >= 1024 && $size_index < $max_unit ) {
        $bytes = $bytes / 1024;
        $size_index++;
    }

    return sprintf("%.0f",$bytes).' '.($sizes[$size_index]);
}

############################################################################
=head2 add_to_fields

    Used as a shortcut for adding data to an attribute table in pages such as device.html.

  Arguments:
    Hash of key/value pairs where keys are:
    - o:              A reference to a DBI object
    - edit:           True if editing, false otherwise
    - new_button:     Show [new] button to create new foreign objects
    - fields:         Reference to an array of column names in the database
    - defaults:       Reference to an array containing default objects or values
    - linkpages:      Reference to an array of the same size as @fields, with optional pages to link to
    - with_delete:    Add a checkbox at the end to delete object when editing (requires passing object)
    - field_headers:  Reference to the array to add the names of the columns to
    - cell_data:      Reference to the array to add the form fields to
  Returns:
    True
  Examples:
    
    my (@field_headers, @cell_data);
    {
     my @fields = ('cid','connectionid','vendor','nearend','farend');
     my @linkpages = ('', 'view.html', 'view.html', 'view.html', 'view.html');
     $ui->add_to_fields(o=>$o, edit=>$editCircuit, fields=>\@fields, linkpages=>\@linkpages, 
			field_headers=>\@field_headers, cell_data=>\@cell_data);
    }
    <& attribute_table.mhtml, field_headers=>\@field_headers, data=>\@cell_data &>
    

=cut
sub add_to_fields {
    my ($self, %args) = @_;
    my ($o, $table, $edit, $fields, $linkpages, $defaults, $with_delete, $field_headers, $cell_data) = 
	@args{ 'o', 'table', 'edit', 'fields', 'linkpages', 'defaults', 'with_delete', 'field_headers', 'cell_data'};
    
    $self->throw_fatal("You need to pass either a valid object or a table name")
	unless ( ref($o) || $table );

    $args{new_button} = 1 unless defined $args{new_button};

    for( my $i=0; $i<@{$fields}; $i++ ) {
        my $field = ${$fields}[$i];
        my $linkpage = ${$linkpages}[$i];
        my %tmp;
	my %ffargs = (object=>$o, table=>$table, column=>$field, edit=>$edit, 
		      linkPage=>$linkpage, new_button=>$args{new_button});
	$ffargs{defaults} = $defaults->[$i] 
	    if ( defined $defaults && defined $defaults->[$i] );
        %tmp = $self->form_field(%ffargs);
        push( @{$field_headers}, $tmp{label} );
        push( @{$cell_data}, $tmp{value} );
    }
    if ( $edit && $o && $with_delete ){
	$table ||= $o->short_class;
        push( @{$field_headers}, 'Delete' );
        push( @{$cell_data}, '<input type="checkbox" name="'.$table.'__'.$o.'__DELETE">' );
    }
    1;
}


############################################################################
=head2 select_query - Search keywords in a tables label fields.

    If label field is a foreign key, recursively search for same keywords in foreign table.

  Arguments:
   - table   Name of table to look up
   - terms   array ref of search terms
  Returns:
    hashref of $table objects
  Examples:
    
  $r = $ui->select_query(table => $table, terms => \@terms, max => $max);

=cut
sub select_query {
    my ($self, %args) = @_;
    my ($table, $terms) = @args{'table', 'terms'};
    my %found;
    my @labels = $table->meta_data->get_labels();
    foreach my $term ( @$terms ){
	foreach my $c ( @labels ){
	    $logger->debug("Netdot::UI::select_query: Searching for $term on $table $c");
	    my $f_table = $table->meta_data->get_column($c)->links_to();
	    if ( !defined $f_table ){ # column is local
		my $it;
		my @results = $table->search_like( $c => $term );
		foreach my $obj ( @results ) {
		    $found{$term}{$obj->id} = $obj;
		}
	    }else{ # column is a foreign key.
		# go recursive
		if ( my $fobjs = $self->select_query(table=>$f_table, terms=>[$term]) ){
		    foreach my $foid ( keys %$fobjs ){
			my $it = $table->search( $c => $foid );
			while ( my $obj = $it->next ){
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

############################################################################
=head2 table_view_page - Get custom component for viewing a particular table

  Arguments:
    Table name
  Returns:
    String with component path
  Examples:
    my $page = $ui->table_view_page($table);

=cut
sub table_view_page {
    my ($self, $table) = @_;
    
    if ( exists $VIEWPAGE{$table} ){
	return $VIEWPAGE{$table};
    }else{
	return "view.html";
    }
}
############################################################################
=head2 build_backbone_graph

  Arguments:
    filename
  Returns:
    GraphViz object
  Examples:
    my $g = $ui->build_backbone_graph(%argv);

=cut
sub build_backbone_graph {
    my ($self, %argv) = @_;
    my ($filename) = @argv{'filename'};
    
    my $g = GraphViz->new(layout=>'dot', truecolor=>1, bgcolor=>"#ffffff00",ranksep=>2.0, rankdir=>"LR", 
			  node=>{shape=>"house", fillcolor=>'#ffffff88', style=>'filled', fontsize=>10},
			  edge=>{dir=>'none', fontsize=>10, labelfontsize=>8, arrowhead=>'none', arrowtail=>'none', color=>'black'});
    my %seen;
    my %site_closets;
    foreach my $bb ( BackboneCable->retrieve_all() ){
	# Get end closets and end sites
	my @eclosets     = ($bb->start_closet, $bb->end_closet);
	unless ( @eclosets &&
		 $bb->start_closet->room && $bb->start_closet->room->floor && 
		 $bb->end_closet->room && $bb->end_closet->room->floor ){
	    next;
	}
	my @esites       = ($bb->start_closet->room->floor->site, $bb->end_closet->room->floor->site);
	my @strands      = $bb->strands;
	my $num_strands  = scalar @strands;
	my $st           = StrandStatus->search(name=>'In Use')->first;
	my $used_strands = CableStrand->search(status=>$st, cable=>$bb)->count;


	# Create a node for each site
	foreach my $site ( @esites ){
	    if ( $site && !$seen{$site->id} ){

		# Create an array of closets to display per Site
		# First element is the Site name
		my @sclosets = ($site->get_label);
		map { push @sclosets, $_->name } sort { $a->name cmp $b->name } $site->closets;
                                         
		for ( my $i=0; $i < scalar(@sclosets); $i++ ){
		    $site_closets{$site->id}{$sclosets[$i]} = $i;
		}

		$g->add_node(
		    name     => $site->get_label,
		    label    => $site->get_label,
		    URL      => "view.html?table=Site&id=".$site->id,
		    );
		$seen{$site->id} = 1;
	    }
	}

	# Create an edge for each cable
	if ( defined $esites[0] && defined $esites[1] && 
	     defined $eclosets[0] && defined $eclosets[1] ){
	    
	    $g->add_edge($esites[0]->get_label => $esites[1]->get_label,
			 label     => $bb->name." (".$used_strands."/".$num_strands.")",
			 labelURL  => "cable_backbone.html?id=".$bb->id,
			 edgeURL  => "cable_backbone.html?id=".$bb->id,
                         from_port => $site_closets{$esites[0]->id}{$eclosets[0]->name},
                         to_port   => $site_closets{$esites[1]->id}{$eclosets[1]->name},
			 
		);
	}
    }
    $g->as_png($filename);
    
    return $g;
}

############################################################################
=head2 build_backbone_graph_html

  Arguments:
    web_path string
    filename (optional)
  Returns:
    html img code
  Examples:
    print $ui->build_backbone_graph_html(web_path=>$r->dir_config('NetdotPath'));

=cut
sub build_backbone_graph_html {
    my ($self, %argv) = @_;
    my ($web_path, $filename) = 
	@argv{'web_path', 'filename'};
    
    my $img_name      = $filename || "Backbone-cable-plant.png";
    my $graph_path    = "img/graphs/$img_name";
    my $img           = $web_path . $graph_path;
    my $netdot_path   = Netdot->config->get('NETDOT_PATH');
    $argv{filename}   = "$netdot_path/htdocs/" . $graph_path;
    
    my $g = $self->build_backbone_graph(%argv);

    return "<img alt=\"Backbone Graph\" width=\"100%\" src=\"$img\" usemap=\"#test\" border=\"0\">" . $g->as_cmapx;
}

############################################################################
=head2 build_ip_tree_graph

  Arguments:
    Hash with following keys:
       list       - arrayref of Ipblock descendants
       filename   - Name of file to save the graph to
  Returns:
    GraphViz object
  Examples:
    my $g = $ui->build_ip_tree_graph(%argv);

=cut
sub build_ip_tree_graph {
    my ($self, %argv) = @_;
    my ($list, $filename) = @argv{'list', 'filename'};
    
    # These should match whatever is on the stylesheet
    my %colors = (
	Subnet    => '#ff6666',
	Container => '#ffee77',
	Reserved  => '#cccccc',
        Available => '#bbddbb',
	);
    
    my $g = GraphViz->new(layout=>'dot', truecolor=>1, bgcolor=>"#ffffff00",ranksep=>2.0, rankdir=>"1", 
			  node=>{shape=>'record', fillcolor=>'#ffffff88', style=>'filled', fontsize=>10, height=>.25},
			  edge=>{dir=>'none', labelfontsize=>8} );
    
    my %seen;

    foreach my $n ( @$list ){
	my $ip = Ipblock->retrieve($n->data);
	
	# Make sure we don't have a null reference
	next unless($ip);

	# Make sure we don't include end addresses in the tree
	next if $ip->is_address;
	
	my @lbls;
	push @lbls, $ip->get_label;
	push @lbls, $ip->description if $ip->description;
	my $lbl = join '\n', @lbls;

	# Graph will not work if description contains non-ascii characters
	use Encode;
	$lbl = encode('utf8', $lbl);

	$g->add_node(
	    name      => $ip->get_label,
	    label     => $lbl,
	    shape     => "record",
	    fillcolor => $colors{$ip->status->name},
	    URL       => "ip.html?id=".$ip->id,
	    );
	
	if ( $n->parent && (my $parent = Ipblock->retrieve($n->parent->data)) ){
	    
	    my @lbls;
	    push @lbls, $parent->get_label;
	    push @lbls, $parent->description if $parent->description;
	    my $lbl = join '\n', @lbls;
           $lbl = encode('utf8', $lbl);
	    
	    if ( !$seen{$parent->id} ){
		$g->add_node(
		    name   => $parent->get_label,
		    label  => $lbl,
		    shape  => "record",
		    URL    => "ip.html?id=".$parent->id,
		    );
		$seen{$parent->id} = 1;
	    }
	    $g->add_edge($parent->get_label => $ip->get_label,
			 color              => 'black',
		);
	}
    }

    $g->as_png($filename);
    
    return $g;
}

############################################################################
=head2 build_ip_tree_graph_html

  Arguments:
    ipblock id
    Arrayref of Net::IPTrie nodes
    web_path string
    filename
  Returns:
    html img code
  Examples:
    print $ui->build_ip_tree_graph_html(list=>$list, web_path=>$r->dir_config('NetdotPath'));

=cut
sub build_ip_tree_graph_html {
    my ($self, %argv) = @_;
    my ($id, $list, $web_path, $filename) = 
	@argv{'id', 'list', 'web_path', 'filename'};
    
    my $img_name      = $filename || "Ipblock-tree-$id.png";
    my $graph_path    = "img/graphs/$img_name";
    my $img           = $web_path . $graph_path;
    my $netdot_path   = Netdot->config->get('NETDOT_PATH');
    $argv{filename}   = "$netdot_path/htdocs/" . $graph_path;
    
    my $g = $self->build_ip_tree_graph(%argv);

    return "<img src=\"$img\" usemap=\"#test\" border=\"0\">" . $g->as_cmapx;
}


############################################################################
=head2 build_device_topology_graph

  Arguments:
    device id
    depth
    view
    showvlans    Boolean
    vlans
    shownames    Boolean
    filename     
    format       (text|ps|hpgl|gd|gd2|gif|jpeg|png|svg)
    direction    (up_down|left_right)
  Returns:
    GraphViz object
  Examples:
    my $g = $ui->build_device_topology_graph(%argv);

=cut
sub build_device_topology_graph {
    my ($self, %argv) = @_;
    my ($id, $depth, $view, $showvlans, $shownames, $filename, $vlans, $format, $direction, $specific_vlan) = 
	@argv{'id', 'depth', 'view', 'show_vlans', 'show_names', 'filename', 'vlans', 'format', 'direction', 'specific_vlan'};
    
    # Guard against malicious input
    $depth = (int($depth) > 0) ? int($depth) : 0;
    $showvlans = ($showvlans == 1) ? 1 : 0;
    $shownames = ($shownames == 1) ? 1 : 0;

    $direction = ($direction eq 'up_down')? 0 : 1;

    if ( $specific_vlan == 0 || $showvlans == 0 ) {
	$specific_vlan = undef;
    }
    
    if ( defined($specific_vlan) && $specific_vlan != 0 ) {
	$showvlans = 1;
    }

    # Declare some useful functions
    sub add_topo_node {
        my (%argv) = @_;
	my ($g, $device, $view, $shownames, $showvlans, $nodeoptions) = 
	    @argv{'graph', 'device', 'view', 'show_names', 'show_vlans', 'nodeoptions'};
	
	$view ||= "view";
        $g->add_node(name  => $device->short_name, 
		     shape => "record",
		     URL   => "device.html?id=".$device->id."&view=$view&toponames=$shownames&topovlans=$showvlans",
		     %$nodeoptions
            );
    }

    # Tried to be fancy and add lots of port information.  EPIC FAIL.  There's no
    # good way to do it.  A nice tarpit for others to avoid.

    sub randomcolor {
        return sprintf("#%02X%02X%02X", rand(128), rand(128), rand(128));
    }

    sub dfs { # DEPTH FIRST SEARCH - recursive
        my ($g, $device, $hops, $seen, $vlans, $showvlans, $shownames, $view, $specific_vlan) = @_;
        return unless $hops;

        my @ifaces = $device->interfaces;
        
        foreach my $iface ( sort { int($a) cmp int($b) }  @ifaces) {
            my $neighbor = $iface->neighbor;
            next unless $neighbor;  # If there's no neighbor, skip ahead

	    my $name          = ($shownames ? $iface->name :    $iface->number)    || $iface->number;
	    my $neighbor_name = ($shownames ? $neighbor->name : $neighbor->number) || $neighbor->number;

            my $nd = $neighbor->device;
            unless (scalar($nd)) {
                $logger->debug("No device found for neighbor $neighbor");
                next;
            }

	    my $add_node = 0;

            # If we haven't seen this edge before, add it to the graph
            next if exists $seen->{'EDGE'}{$neighbor->id . " " . $iface->id};
            $seen->{'EDGE'}{$neighbor->id . " " . $iface->id} = 1;
            $seen->{'EDGE'}{$iface->id . " " . $neighbor->id} = 1;

            my $color = 'black';
	    my $cont = 0;
            if ($showvlans && $iface->vlans) {
                foreach my $vlan ($iface->vlans) {
		    if ( !defined($specific_vlan) || (defined($specific_vlan) && $specific_vlan == $vlan->vlan->vid) ) {
			my $neighbor_vlan = InterfaceVlan->search(interface=>$neighbor->id, vlan=>$vlan->vlan->id)->first;
			next if ( defined($specific_vlan) && $specific_vlan != 0 && ( ($neighbor_vlan && $neighbor_vlan->vlan->vid != $specific_vlan) || !defined($neighbor_vlan) ) );

			my $style = 'solid';
			my $vname = $vlan->vlan->name || $vlan->vlan->vid;
			if (!exists $vlans->{$vname}) {
			    $vlans->{$vname} = { color=>&randomcolor, vlan=>$vlan->vlan->id };
			}
			$color = $vlans->{$vname}{'color'};
			
			if ($vlan->stp_state eq 'blocking' 
			    || ($neighbor_vlan and $neighbor_vlan->stp_state eq 'blocking')) {
			    $style='dashed';
			}   
			
			$g->add_edge($device->short_name => $nd->short_name,
				     tailURL             => "view.html?table=Interface&id=".$iface->id,
				     taillabel           => ((defined($specific_vlan) && $specific_vlan != 0)?$name:$vname),
				     headURL             => "view.html?table=Interface&id=".$neighbor->id, 
				     headlabel           => $neighbor_name,
				     color               => $color,
				     style               => $style,
			    );
			$add_node = 1;
			$cont = 1;
		    }
                }
            } else {
		if ( !defined($specific_vlan) || defined($specific_vlan) && $specific_vlan == 0 ) {
		    $g->add_edge($device->short_name => $nd->short_name,
				 tailURL             => "view.html?table=Interface&id=".$iface->id,
				 taillabel           => $name,
				 headURL             => "view.html?table=Interface&id=".$neighbor->id, 
				 headlabel           => $neighbor_name,
				 color               => 'black',
			);
		    $add_node = 1;
		    $cont = 1;
		}
            }
	    
	    # also make sure we haven't seen this node before
	    if ( $add_node == 1 && !(exists $seen->{'NODE'}{$nd->id}) ) {
		&add_topo_node(graph      => $g, 
			       device     => $nd, 
			       view       => $view,
			       show_names => $shownames, 
			       show_vlans => $showvlans);
		$seen->{'NODE'}{$nd->id} = 1;
	    }
	    
            # If we haven't recursed across this edge before, then do so now.
	    if ( $cont == 1 ) {
		&dfs($g, $nd, $hops-1, $seen, $vlans, $showvlans, $shownames, $view, $specific_vlan);
	    }
        }
    }
    
    my %args = (layout=>'dot', truecolor=>1, bgcolor=>"#ffffff00",ranksep=>2.0,
		node=>{shape=>'record', fillcolor=>'#ffffff88', style=>'filled', 
		       fontsize=>10, height=>.25},
		edge=>{dir=>'none', labelfontsize=>8}, rankdir=>$direction );

    # Actually do the searching
    my $g = GraphViz->new(%args);
    
    my $start = Device->retrieve($id);
    &add_topo_node(graph       => $g,
		   device      => $start, 
		   show_vlans  => $showvlans,
		   show_names  => $shownames, 
		   view        => $view,
		   nodeoptions => { color=>'red'},
	);

    my $seen = { NODE=>{}, EDGE=>{} };
    $seen->{'NODE'}{$start->id} = 1;

    &dfs($g, $start, $depth, $seen, $vlans, $showvlans, $shownames, $view, $specific_vlan);

    $argv{format} ||= 'png';
    if ( $argv{format} =~ /^(text|ps|hpgl|gd|gd2|gif|jpeg|png|svg)$/){
	my $method = 'as_'.$argv{format};
	$g->$method($filename);
    }else{
	$self->throw_user("Unrecognized format: $argv{format}");
    }

    return $g;
}


############################################################################
=head2 build_device_topology_graph_html

  Arguments:

  Returns:
    A string containing an img tag, a cmap, and a bunch of vlans
  Examples:
    print $ui->build_device_topology_graph_html(id=>$id, view=>$view, depth=>$topodepth, 
                                                   web_path=>$r->dir_config('NetdotPath'), 
                                                   show_vlans=>$topovlans, show_names=>$toponames);

=cut
sub build_device_topology_graph_html {
    my ($self, %argv) = @_;
    my ($id, $view, $depth, $web_path, $showvlans, $shownames, $filename, $specificvlan) = 
	@argv{'id', 'view', 'depth', 'web_path', 'show_vlans', 'show_names', 'filename', 'specific_vlan'};
    
    if ( !defined($specificvlan) ) {
	$specificvlan = 0;
    }
    my $img_name      = $filename || "Device-$id-$depth-$showvlans-$shownames-$specificvlan.png";
    my $graph_path    = "img/graphs/$img_name";
    my $img           = $web_path . $graph_path;
    my $netdot_path   = Netdot->config->get('NETDOT_PATH');
    $argv{filename}   = "$netdot_path/htdocs/" . $graph_path;

    my $vlans    = { 1=>{color=>'#000000', vlan=>Vlan->search(id=>1)->first} };
    $argv{vlans} = $vlans;

    my $g = $self->build_device_topology_graph(%argv);

    my  $vlanlist = "";
    foreach my $vlan (keys %$vlans) {
	$vlanlist .= '<a href="view.html?table=Vlan&id=' . $vlans->{$vlan}{'vlan'} . '"><font color="' . $vlans->{$vlan}{'color'} . "\">$vlan</font></a> ";
    }
    return "<img src=\"$img\" usemap=\"#test\" border=\"0\">" 
	. $g->as_cmapx
	. ($showvlans ? '<br><b>List of vlans and their colors:</b><br>'
	   . '<b>' . $vlanlist . '</b>'
	   : "");
}


############################################################################
=head2 build_device_stp_graph

  Arguments:

  Returns:
    GraphViz object
  Examples:
    print $ui->build_device_stp_graph(%argv);

=cut
sub build_device_stp_graph {
    my ($self, %argv) = @_;
    my ($id, $number, $view, $web_path, $filename, $format, $direction) = 
	@argv{'id', 'number', 'view', 'web_path', 'filename', 'format', 'direction'};
    
    $direction = ($direction eq 'up_down')? 0 : 1;
    
    my %links;
    my %graph_args = (layout=>'dot', truecolor=>1, bgcolor=>"#ffffff00",ranksep=>2.0,
		node=>{shape=>'record', fillcolor=>'#ffffff88', style=>'filled', 
		       fontsize=>10, height=>.25},
		edge=>{dir=>'none', labelfontsize=>8}, rankdir=>$direction );
    my $g = GraphViz->new(%graph_args);
    my $start = Device->retrieve($id);
    my $stp_inst = STPInstance->search(device=>$id, number=>$number)->first;
    return $g unless defined($stp_inst);
    my $start_root = $stp_inst->root_bridge;
    return $g unless defined($start_root);
    
    my $devicemacs = Device->get_macs_from_all();

    my $links = Netdot::Topology->get_tree_stp_links(root=>$start_root, devicemacs=>$devicemacs);  # these links contain STP graphs for all numbers
    map { $links{$_} = $links->{$_} } keys %$links;
    
    
    sub add_stp_node{
	my (%argv) = @_;
	my ($g, $device_id, $view, $nodeoptions, $customlabel) =
	    @argv{'graph', 'device_id', 'view', 'nodeoptions', 'custom_label'};
	
	$view ||= "view";
	if ( !defined($customlabel) || $customlabel eq "" ) {
	    $customlabel = Device->search(id=>$device_id)->first->short_name;
	}
	my $nodename = $g->add_node(name  => $device_id,
				    label => $customlabel,
				    shape => "record",
				    URL   => "device.html?id=".$device_id."&view=$view",
				    %$nodeoptions
            );
	
	return $nodename;
    }
    
    
    my $out = "";
    my $seen = { NODE=>{}, EDGE=>{} };
    foreach my $key (keys %links) {
	# Note: I am not sure how much of the 'from' and 'to' mean directionally,
	# but they are just two ends of a connection -DY
	
	# first get relevant objects
	my $from_int   = Interface->search(id=>$links{$key})->first;
	my $from_dev   = Device->search(id=>$from_int->device)->first;
	my $from_stp_inst = STPInstance->search(device=>$from_dev->id, number=>$number)->first;
	
	my $to_int   = Interface->search(id=>$key)->first;
	my $to_dev   = Device->search(id=>$to_int->device)->first;
	my $to_stp_inst = STPInstance->search(device=>$to_dev->id, number=>$number)->first;
	
	next unless ( defined($from_stp_inst) && defined($to_stp_inst) );
	
	#add 'from' device to graph
	if ( !exists $seen->{'NODE'}{$from_dev->id} && defined($from_stp_inst) ) {
	    my $from_label = $from_dev->short_name
	 	             . "|Mac:\\ ".$from_dev->physaddr->address
	                     . "|Priority:\\ ".$from_stp_inst->bridge_priority
	                     . "|<port".$links{$key}."> Int:\\ ".$from_int->name;
	    $seen->{'NODE'}{$from_dev->id} = $from_label;
	} else {
	    $seen->{'NODE'}{$from_dev->id} .= "|<port".$links{$key}."> Int:\\ ".$from_int->name;
	}
	
	#add 'to' device to graph
	if ( !exists $seen->{'NODE'}{$to_dev->id} ) {
	    my $to_label = $to_dev->short_name
   		           . "|Mac:\\ ".$to_dev->physaddr->address
		           . "|Priority:\\ ".$to_stp_inst->bridge_priority
	                   . "|<port".$key."> Int:\\ ".$to_int->name;
	    $seen->{'NODE'}{$to_dev->id} = $to_label;
	} else {
	    $seen->{'NODE'}{$to_dev->id} .= "|<port".$key."> Int:\\ ".$to_int->name;
	}
	
	# note the connection to graph
	if ( !exists $seen->{'EDGE'}{$links{$key} . " " . $key} ) {
            $seen->{'EDGE'}{$key . " " . $links{$key}} = 1;
            $seen->{'EDGE'}{$links{$key} . " " . $key} = $from_dev->id . " " . $to_dev->id;
	}
    }
    
    # add the nodes to the graph
    foreach my $dev_id (keys %{$seen->{'NODE'}}) {
	&add_stp_node(graph        => $g,
		      device_id    => $dev_id,
		      view         => $view,
		      custom_label => $seen->{'NODE'}{$dev_id}
	    );
    }
    
    # add the edges to the graph
    my $color = 'black';
    my $style = 'solid';
    foreach my $edge (keys %{$seen->{'EDGE'}}) {
        next if $seen->{'EDGE'}{$edge} == 1;
	my ($tail_int, $head_int) = split(/ /, $edge);
	my ($tail_dev, $head_dev) = split(/ /, $seen->{'EDGE'}{$edge});
	next if ( !exists $seen->{'NODE'}{$tail_dev} );
	next if ( !exists $seen->{'NODE'}{$head_dev} );
	# tail == from == $links{$key} previously
	# head == to == $key previously
	$g->add_edge($tail_dev => $head_dev,
		     tailURL   => "view.html?table=Interface&id=".$tail_int,
		     taillabel => "",
		     headURL   => "view.html?table=Interface&id=".$head_int,
		     headlabel => "",
		     color     => $color,
		     style     => $style,
		     from_port => $tail_int,
		     to_port   => $head_int
	    );
    }
    
    #output the graph to file
    $argv{format} ||= 'png';
    if ( $argv{format} =~ /^(text|ps|hpgl|gd|gd2|gif|jpeg|png|svg)$/){
	my $method = 'as_'.$argv{format};
	$g->$method($filename);
    }else{
	$self->throw_user("Unrecognized format: $argv{format}");
    }
    
    return $g;
}


############################################################################
=head2 build_device_stp_graph_html

  Arguments:

  Returns:
    A string containing an img tag and a cmap (similar to build_device_topology_graph_html)
  Examples:
    print $ui->build_device_stp_graph_html(id=>$id, number=>$stp_number, view=>$view,
                                           web_path=>$r->dir_config('NetdotPath'),
                                           );

=cut
sub build_device_stp_graph_html {
    my ($self, %argv) = @_;
    my ($id, $number, $view, $web_path, $filename) = 
	@argv{'id', 'number', 'view', 'web_path', 'filename'};
    
    my $img_name      = $filename || "DeviceSTP-$id-$number.png";
    my $graph_path    = "img/graphs/$img_name";
    my $img           = $web_path . $graph_path;
    my $netdot_path   = Netdot->config->get('NETDOT_PATH');
    $argv{filename}   = "$netdot_path/htdocs/" . $graph_path;

    my $g = $self->build_device_stp_graph(%argv);

    return "<img src=\"$img\" usemap=\"#test\" border=\"0\">" 
	. $g->as_cmapx;
}


############################################################################
=head2 rrd_graph - Create RRD graphs

  Arguments:
    type
    title
    period
    img
    web_path
  Returns:
    <IMG> html tag containing graph img path
  Examples:
    

=cut
sub rrd_graph{
    my ($class, %argv) = @_;
    die "UI::rrd_graph: Missing required arguments" 
	unless ($argv{title} && $argv{period} && $argv{type} 
		&& $argv{img} && $argv{web_path});
    my $rrd_rel_path = Netdot->config->get('POLL_STATS_FILE_PATH');
    my $netdot_path  = Netdot->config->get('NETDOT_PATH');
    my $rrd_file     = "$netdot_path/$rrd_rel_path";
    my $graph_path   = "img/graphs/$argv{img}";
    my $out_file     = "$netdot_path/htdocs/" . $graph_path;
    my @args = ( $out_file, "--imgformat=PNG", "--interlaced",
		 "--title=$argv{title}", "--start=$argv{period}");
    
    if ( $argv{type} eq 'addr' ){
	push @args, ("--vertical-label=Addresses",
		     "DEF:ips=$rrd_file:ips:AVERAGE",
		     "DEF:macs=$rrd_file:macs:AVERAGE",
		     "VDEF:avgips=ips,AVERAGE",
		     "VDEF:maxips=ips,MAXIMUM",
		     "VDEF:minips=ips,MINIMUM",
		     "VDEF:curips=ips,LAST",
		     "VDEF:avgmacs=macs,AVERAGE",
		     "VDEF:maxmacs=macs,MAXIMUM",
		     "VDEF:minmacs=macs,MINIMUM",
		     "VDEF:curmacs=macs,LAST",
		     "COMMENT:         Average   Maximum   Minimum   Current\\l",
		     "AREA:macs#0033CC:MACs",
		     "GPRINT:avgmacs:%6lg %s",
		     "GPRINT:maxmacs:%6lg %s",
		     "GPRINT:minmacs:%6lg %s",
		     "GPRINT:curmacs:%6lg %s\\l",
		     "LINE:ips#00CC66:IPs ",
		     "GPRINT:avgips:%6lg %s",
		     "GPRINT:maxips:%6lg %s",
		     "GPRINT:minips:%6lg %s",
		     "GPRINT:curips:%6lg %s",
	);

    }elsif ( $argv{type} eq 'dev' ){
	push @args, ("--vertical-label=Devices",
		     "DEF:fwt_devs=$rrd_file:fwt_devs:AVERAGE",
		     "DEF:arp_devs=$rrd_file:arp_devs:AVERAGE",
		     "VDEF:avgfwt=fwt_devs,AVERAGE",
		     "VDEF:maxfwt=fwt_devs,MAXIMUM",
		     "VDEF:minfwt=fwt_devs,MINIMUM",
		     "VDEF:curfwt=fwt_devs,LAST",
		     "VDEF:avgarp=arp_devs,AVERAGE",
		     "VDEF:maxarp=arp_devs,MAXIMUM",
		     "VDEF:minarp=arp_devs,MINIMUM",
		     "VDEF:curarp=arp_devs,LAST",
		     "COMMENT:         Average    Maximum   Minimum   Current\\l",
		     "AREA:fwt_devs#0033CC:FWT",
		     "GPRINT:avgfwt:%6lg %s",
		     "GPRINT:maxfwt:%6lg %s",
		     "GPRINT:minfwt:%6lg %s",
		     "GPRINT:curfwt:%6lg %s\\l",
		     "LINE:arp_devs#00CC66:ARP",
		     "GPRINT:avgarp:%6lg %s",
		     "GPRINT:maxarp:%6lg %s",
		     "GPRINT:minarp:%6lg %s",
		     "GPRINT:curarp:%6lg %s",
	);
	
    }elsif ( $argv{type} eq 'time' ){
	push @args, ("--vertical-label=Time (min)",
		     "DEF:poll_time=$rrd_file:poll_time:AVERAGE",
		     "CDEF:poll_mins=poll_time,60,/",
		     "VDEF:avgtime=poll_mins,AVERAGE",
		     "VDEF:maxtime=poll_mins,MAXIMUM",
		     "VDEF:mintime=poll_mins,MINIMUM",
		     "VDEF:curtime=poll_mins,LAST",
		     "COMMENT:         Average    Maximum   Minimum   Current\\l",
		     "AREA:poll_mins#FFCC00:Time",
		     "GPRINT:avgtime:%6lg %s",
		     "GPRINT:maxtime:%6lg %s",
		     "GPRINT:mintime:%6lg %s",
		     "GPRINT:curtime:%6lg %s\\l"
	);
	
    }else{
	die("UI::rrd_graph: Unknown type: $argv{type}");
    }
    RRDs::graph(@args);
    if ( my $e = RRDs::error ){
	die("UI::rrd_graph: Could not graph RRD: $e");
    }
    my $img  = $argv{web_path} . $graph_path;
    return "<img src=\"$img\" border=\"0\">";
}

############################################################################
=head2 get_current_user - Return current user object

  Arguments:
    $r = Apache request object
  Returns:
    Apache2::SiteControl::User object
  Examples:
    $ui->get_current_user($r)

=cut
sub get_current_user{
    my ($self, $r) = @_;
    return Apache2::SiteControl->getCurrentUser($r);
}

############################################################################
=head2 get_permission_manager - Return PermissionManager object

  Arguments:
    $r = Apache request object
  Returns:
    Apache2::SiteControl::PermissionManager object
  Examples:
    $ui->get_permission_manager($r)

=cut
sub get_permission_manager{
    my ($self, $r) = @_;
    return Apache2::SiteControl->getPermissionManager($r);
}


############################################################################
=head2 get_user_person - Get Person object associated with SiteControl user


  Arguments:
    $user  = Apache2::SiteControl::User object
  Returns:
    Person object
  Examples:
    my $person = $self->get_user_person($user);

=cut
sub get_user_person {
    my ($self, $user) = @_;

    my $username = $user->getUsername() || 
	$self->throw_user("Cannot get username for given user object");

    my $person;
    if ( $person = Person->search(username=>$username)->first ){
	return $person;
    }elsif ( my $default_user_type = $self->config->get('DEFAULT_REMOTE_AUTHED_USER_TYPE') ){

	# If it's "none", do not attempt to create a Person
	$self->throw_user("Username $username not found in Person table")
	    if ( $default_user_type =~ /^none$/i );

	if ( $default_user_type =~ /^User|Operator|Admin$/i ){
	    if ( my $type = UserType->search(name=>$default_user_type)->first ){
		$person = Person->insert({lastname=>$username, username=>$username, user_type=>$type});
		return $person;
	    }
	}else{
	    $self->throw_user("Unrecognized value for DEFAULT_REMOTE_AUTHED_USER_TYPE config option");
	}
    }
    $self->throw_user("Username $username not found in Person table");
    
}

############################################################################
=head2 set_user_rights - Set user permissions 

    Store user type as an attribute of Apache2::SiteControl::User
    objects, which are then evaluated by the various SiteControl rules that
    control what users can do.  

  Arguments:
    $user = Apache2::SiteControl::User object
    $r    = Apache request object
  Returns:
    True
  Examples:
    $ui->set_user_type($user, $r)

=cut
sub set_user_type{
    my ($self, $r, $user) = @_;

    $self->throw_fatal("Missing required arguments: user object and/or Apache request object")
	unless ( $user && $r);

    my $person = $self->get_user_person($user);

    my $user_type = $person->get_user_type();
    $user->setAttribute($r, 'USER_TYPE', $user_type);

    return 1;
}

############################################################################
=head2 get_allowed_objects

    Retrieve list of objects for which user has access.

  Arguments:
    $r     = Apache request object
    $user  = Apache2::SiteControl::User object
  Returns:
    Hashref with key=Object class, 
                 value=Hashref with key=Object id, value=access right
  Examples:
    $ui->get_allowed_objects($user, 'Device')

=cut
sub get_allowed_objects{
    my ($self, $r, $user, $type) = @_;

    $self->throw_fatal("Netdot::UI::get_allowed_objects: Missing required arguments")
	unless ( $r, $user );
    
    if ( !defined $user->getAttribute('ALLOWED_OBJECTS') ){
	my $person  = $self->get_user_person($user);
	my $objects = $person->get_allowed_objects();
	# Set as user attribute to avoid querying DB again
	# This means that users will have to re-login when their
	# access rights change.
	$user->setAttribute($r, 'ALLOWED_OBJECTS', $objects);
    }
    my $aohref = $user->getAttribute('ALLOWED_OBJECTS');
    return $aohref;
}

############################################################################
=head2 url_encode

  Arguments:
  Returns:
  Examples:

=cut
sub url_encode {
    my ($self, $url) = @_;
    $url =~ s/([\W])/"%" . uc(sprintf("%2.2x",ord($1)))/eg;
    return $url;
}

############################################################################
=head2 url_decode

  Arguments:
  Returns:
  Examples:

=cut
sub url_decode {
    my ($self, $url) = @_;
    $url =~ tr/+/ /;
    $url =~ s/%([a-fA-F0-9]{2,2})/chr(hex($1))/eg;
    $url =~ s/<!--(.|\n)*-->//g;
    return $url;
}


=head1 AUTHORS

Carlos Vicente, Nathan Collins, Aaron Parecki, Peter Boothe.

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

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


