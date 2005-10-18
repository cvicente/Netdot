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
        return ;
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
			return;
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
				return;
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
			    return;
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
			    return; # error should already be set.
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
			return; # error should be set.
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
			return;
		    }
		    unless ( $self->update(object => $o, state => \%{ $objs{$table}{$id} }) ){
			return; # error should already be set.
		    }
		    $form_to_db_info{$table}{action} = "update";
		    $form_to_db_info{$table}{key} = $id;
		}
	    }
        }
    }
    return %form_to_db_info;

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
    my ($o, $table, $column, $lookup, $where, $isEditing, $htmlExtra, $linkPage, $maxCount, $returnAsVar) = 
	($args{object}, $args{table}, 
	 $args{column}, $args{lookup},
	 $args{where}, $args{edit},
	 $args{htmlExtra}, $args{linkPage},
	 $args{maxCount}, $args{returnAsVar});

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
                $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $htmlExtra);
		$output .= sprintf("<option value=\"0\" selected>-- Select --</option>\n");
                if ($o->$column){
                    $output .= sprintf("<option value=\"%s\" selected>%s</option>\n", $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
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
                next if ($o && $o->$column && ($fo->id == $o->$column->id));
                $output .= sprintf("<option value=\"%s\">%s</option>\n", $fo->id, $self->getlabelvalue($fo, \@labels));
            }
            $output .= sprintf("</select>\n");
        }else{
	    # ...otherwise provide tools to narrow the selection to a managable size.
            my $srchf = "_" . $id . "_" . $column . "_srch";
            $output .= sprintf("<input type=\"text\" name=\"%s\" value=\"Keywords\" onFocus=\"if (this.value == 'Keywords') { this.value = ''; } return true;\">", $srchf);
            $output .= sprintf("<input type=\"button\" name=\"__%s\" value=\"List\" onClick=\"jsrsSendquery(%s, %s.value, \'%s\');\">\n", time(), $name, $srchf, $lookup);
            $output .= sprintf("<select name=\"%s\" id=\"%s\" %s>\n", $name, $name, $htmlExtra);
            $output .= sprintf("<option value=\"0\" selected>-- Select --</option>\n");
            if ($o && $o->$column){
                $output .= sprintf("<option value=\"%s\" selected>%s</option>\n", $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
            }
            $output .= sprintf("</select>\n");
        }

        # show link to add new item to this table
        $output .= sprintf("<a href=\"#\" onClick=\"openinsertwindow('%s', '%s');\">[new]</a>", $lookup, $name);

    }elsif ($linkPage && $o->$column ){
	if ($linkPage eq "1" || $linkPage eq "view.html"){
	    my $rtable = $o->$column->table;
	    $output .= sprintf("<a href=\"view.html?table=%s&id=%s\"> %s </a>\n", $rtable, $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
	}else{
	    $output .= sprintf("<a href=\"$linkPage?id=%s\"> %s </a>\n", $o->$column->id, $self->getlabelvalue($o->$column, \@labels));
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
        $output .= sprintf("Yes<input type=\"radio\" name=\"%s\" value=\"1\" %s>&nbsp;<br>\n", $name, ($value ? "checked" : ""));
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
