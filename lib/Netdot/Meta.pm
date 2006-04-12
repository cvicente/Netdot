package Netdot::Meta;

use strict;
use Data::Dumper;
use Carp;

my $meta;

# Suffix for history table names
my $HIST = '_history';  

# Default location of the file that contains Meta Information
my $META_FILE = "<<Make:ETC>>/netdot.meta";

#Be sure to return 1
1;

=head1 NAME

Netdot::Meta - Meta Information Class for Netdot

=head1 SYNOPSIS

Netdot::Meta groups all the methods related to Netdot's metadata.
Metadata is key in writing minimalist/reusable user interface code.

=head1 PUBLIC METHODS

=head2 new - Class Constructor
    
    my $meta = Netdot::Meta->new(meta_file => "path/to/meta_file");
    
=cut
sub new {
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    my $file = $argv{'meta_file'} || $META_FILE;
    $meta = $self->_read_metadata($file);
    unless (ref($meta) eq "HASH"){
	croak "Error in metadata: file is not a valid hash: $file";
    }
    wantarray ? ( $self, '' ) : $self;
    
}

=head2 get_tables

    Returns an array of table names (including history tables)
    
  Arguments:
    None
  Returns:
    Array containing table names
  Example: 

    @tables = $meta->get_tables();

=cut
sub get_tables{
    my $self = shift;
    my @ret;
    my @tables = keys %{$self->_get_tables()};
    foreach my $tab ( @tables ) {
	push @ret, $tab;
	# Add history tables if any 
	if ( $self->_get_table_attr($tab, 'has_history') ){
	    push @ret, $tab . $HIST;
	}
    }
    return @ret;
}

=head2 understanding get links methods

The following two methods, get_links_to and get_links_from, have names corresponding to the following diagram:

 +------+   ``this has links_to that'' +------+
 |      | ``that has links_from this'' |      |
 | this |----------------------------->| that |
 |      |                              |      |
 +------+ Many                     One +------+

Keep the arrow head (-->) in mind, otherwise the names would be ambiguous. 

=cut

=head2 get_links_to

    Get one-to-many relationships for a given table, this table being on the "many" side 
    (has_a definitions in Class::DBI).
    This info is identical for history tables

  Arguments:
    Table name
  Returns:
    Hash.  The hash keys are the names of the local fields, and the values are the names of the tables
    that these fields reference.
  Example: 

    %linksto = $meta->get_links_to($table);

=cut
sub get_links_to{
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    $table =~ s/$HIST//;
    my %ret;
    my $lt = $self->_get_column_attrs($table, 'linksto');
    foreach my $col ( keys %$lt ){
	$ret{$col} = $lt->{$col}->{table};
    }
    return %ret;
}

=head2 get_links_from

    Get one-to-many relationships for a given table, this table being on the "one" side 
    (equivalent to has_many definitions in Class::DBI).
    History tables are not referenced by other tables
    
  Arguments:
    Table name
  Returns:
    Hash.  The keys of the main hash are identifiers for the relationship.  The nested hashs keys are names of
    the tables that reference this table.  The values are the names of the fields in those tables that
    reference this tables primary key.
  Example: 

    %linksfrom = $meta->get_links_from($table);

=cut
sub get_links_from{
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    my %ret;
    return if ( $table =~ /$HIST/ );
    foreach my $t ( $self->get_tables() ){
	next if ( $t =~ /$HIST/ );
	my $lt = $self->_get_column_attrs($t, 'linksto');
	foreach my $col ( keys %$lt ){
	    if ($lt->{$col}->{table} eq $table){
		my $method = $lt->{$col}->{method};
		$ret{$method}{$t} = $col;
		
	    }
	}
    }
    return %ret;
}

=head2 get_column_order
    
    Provide the position of all columns in a given table, in the order they are 
    supposed to be displayed
    
  Arguments:
    Table name
  Returns:
    Hash containing column positions, indexed by column name
  Example: 
    
   %order = $meta->get_column_order($table);
   foreach my $col { sort $order{$a} <=> $order{$b} } keys %order
     ...

=cut
sub get_column_order{
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    my %ret;
    my $hist;
    if ( $table =~ s/$HIST// ){
	$hist = 1;
    }
    my $views = $self->_get_table_attr($table, 'views');
    if ( ! exists $views->{all} ){
	return;
    }
    my @tmp = @{$views->{all}};
    if ( $hist ){
	push @tmp, ('modified', 'modifier');
    }
    my $i = 1;
    map { $ret{$_} = $i++ } @tmp;
    return %ret;
}

=head2 get_column_order_brief

    Provide the position of most relevant columns in a given table, in the order they are 
    supposed to be displayed

  Arguments:
    Table name
  Returns:
    Hash containing column positions, indexed by column name
  Example: 
     %orderbrief = $meta->get_column_order_brief($table);
     foreach my $col { sort $orderbrief{$a} <=> $orderbrief{$b} } keys %orderbrief
       ...


=cut
sub get_column_order_brief {
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    my %ret;
    my @tmp;
    if ( $table =~ s/$HIST// ){
	push @tmp, ('modified', 'modifier');
    }
    my $views = $self->_get_table_attr($table, 'views');
    if ( ! exists $views->{brief} ){
	return;
    }
    push @tmp, @{$views->{brief}};
    my $i = 1;
    map { $ret{$_} = $i++ } @tmp;
    return %ret;
}

=head2 get_labels

    Get labels for a given table. Labels are one or more columns used as hyperlinks to retrieve
    the specified object.  They are also used as a meaningful instance identifier.

  Arguments:
    Table name
  Returns:
    Array containing columns included in the label
  Example: 
    @lbls = $meta->get_labels($table);


=cut
sub get_labels{
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    $table =~ s/$HIST// ;
    my @labels = @{$self->_get_table_attr($table, 'label')};
    return ( @labels ) ? @labels : undef;
}

=head2 is_join

    Check if table is a join table

  Arguments:
    Table name
  Returns:
    True or false (1 or 0)
  Example: 
  $flag = $meta->is_join( $table );

=cut
sub is_join {
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    return $self->_get_table_attr($table, 'isjoin');
}

=head2 get_column_type

    Given a table and a column name, returns the SQL type as defined in the schema

  Arguments:
    Table name, Column name
  Returns:
    Scalar containing the SQL type of the column
  Example: 
    $type = $meta->get_column_type( $table, $col );


=cut
sub get_column_type {
    my ($self, $table, $col) = @_;
    croak "Need to pass table and column " unless $table && $col;
    my $attrs = $self->_get_column_attrs($table, 'type');
    return ( exists $attrs->{$col} ) ?  $attrs->{$col} :  undef;
}

=head2 get_column_descr

    Get the description for a given column.

  Arguments:
    Table name, Column name
  Returns:
    Scalar containing description for that column
  Example: 
    $descr = $meta->get_column_descr( $table, $col );


=cut
sub get_column_descr {
    my ($self, $table, $col) = @_;
    croak "Need to pass table and column " unless $table && $col;
    my $attrs = $self->_get_column_attrs($table, 'description');
    return ( exists $attrs->{$col} ) ?  $attrs->{$col} :  undef;
}

=head2 get_column_length

    Get the DB length for a given column

  Arguments:
    Table name, Column name
  Returns:
    Scalar containing the length for that column
  Example: 
    $len = $meta->get_column_length( $table, $col );


=cut
sub get_column_length {
    my ($self, $table, $col) = @_;
    croak "Need to pass table and column " unless $table && $col;
    my $attrs = $self->_get_column_attrs($table, 'length');
    return ( exists $attrs->{$col} ) ?  $attrs->{$col} :  undef;
}

=head2 get_column_null

    Get 'nullable' nature for a given column as defined in the DB.

  Arguments:
    Table name, Column name
  Returns:
    True or false.  True meaning that the column can be set to NULL.
  Example: 
    $null = $meta->get_column_null( $table, $col );

=cut
sub get_column_null {
    my ($self, $table, $col) = @_;
    croak "Need to pass table and column " unless $table && $col;
    my $attrs = $self->_get_column_attrs($table, 'nullable');
    return ( exists $attrs->{$col} ) ?  $attrs->{$col} :  undef;
}

=head2 get_column_tag

    Get the tag for a given column.
    A column tag is the user-friendly name for the column displayed in the 
    user interface.

  Arguments:
    Table name, Column name
  Returns:
    Scalar containing the tag string
  Example: 
    $tag = $meta->get_column_tag( $table, $column );

=cut
sub get_column_tag {
    my ($self, $table, $col) = @_;
    croak "Need to pass table and column " unless $table && $col;
    my $attrs = $self->_get_column_attrs($table, 'tag');
    return ( exists $attrs->{$col} ) ?  $attrs->{$col} :  undef;
}

=head2 get_column_tags

    Get tags for all columns in a given table.
    A column tag is the user-friendly name of the column displayed in the 
    user interface.

  Arguments:
    Table name
  Returns:
    Hash of column tags indexed by column name.
  Example: 
    %tags = $meta->get_column_tags( $table );

=cut
sub get_column_tags {
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    my $attrs = $self->_get_column_attrs($table, 'tag');
    return %{$attrs};
}

=head2 is_unique

    Get a flag with the 'uniqueness' nature of a column.
    This is basically used to determine if the column is required when showing a form.
    Note: We do not use the NULLABLE attribute to determine this because in our case, 
    columns defined as 'NOT NULL' happen to be set to '0', even if the assigned Perl value 
    is undef.

  Arguments:
    Table name, Column name
  Returns:
    True or False
  Example: 
    $unique = $meta->is_unique( $table, $col );

=cut
sub is_unique {
    my ($self, $table, $col) = @_;
    croak "Need to pass table and column" unless $table && $col;
    my $unique = $self->get_table_attr($table, 'unique');
    # The unique attribute is an arrayref of arrayrefs
    # If the column is contained in any of these, it is 
    # unique
    map { return scalar(grep /^$col$/, @$_) } @$unique;
}

=head2 cdbi_defs

    Use metadata to generate Class::DBI table definitions 
    (See Class::DBI documentation on CPAN)
    A few assumptions are made.  For example, the 'essential' list of columns
    will be the 'brief' list view, which is the set of columns shown when
    listing multiple objects.

  Arguments:
    None
  Returns:
    Scalar (text) containing CDBI class definitions
  Example: 
    my $defs = $meta->cdbi_defs();

=cut

sub cdbi_defs {
    my $self = shift;
    my @tables = $self->get_tables();
    my $ret;

    foreach my $table ( sort @tables ){
	$ret .= "\n######################################################################\n";
	$ret .= "package $table;\n";
	$ret .= "######################################################################\n";
	$ret .= "use base 'Netdot::DBI';\n";
	$ret .= "__PACKAGE__->table( '$table' );\n";

	# Set up primary columns
	$ret .=  "__PACKAGE__->columns( Primary => qw / id /);\n";
	
	# Define 'Essential' and 'Others' 
	my %cols;
	map { $cols{$_} = 1 } keys %{$self->_get_columns($table)};
	my %brief = $self->get_column_order_brief($table);
	my @essential = keys %brief;
	delete $cols{$_} foreach (@essential);
	my $essential = join ' ', @essential;
	$ret .= "__PACKAGE__->columns( Essential => qw / $essential /);\n" if scalar(@essential);
	my $others = join ' ', keys %cols;
	$ret .= "__PACKAGE__->columns( Others => qw / $others /);\n" if scalar (keys %cols);

	# Set up has_a relationships
	my %ha = $self->get_links_to($table);
	foreach my $col ( keys %ha ){
	    $ret .= "__PACKAGE__->has_a( $col => '$ha{$col}' );\n";
	}

	# Set up has_many relationships
	my %hm = $self->get_links_from($table);
	foreach my $rel ( keys %hm ){
	    my $method = $rel;
	    my $tab    = ( keys %{$hm{$rel}} )[0];
	    my $col    = $hm{$rel}{$tab};
	    my $casc;
	    if ( my $l = $self->_get_column_attrs($tab, 'linksto') ){
		if ( ! exists $l->{$col}->{cascade} ){
		    return;
		}
		    $casc = $l->{$col}->{cascade};
	    }
	    my $arg;
	    if ( $casc ){
		if ( $casc eq 'Nullify' ){
		    $arg = "{cascade=>'Class::DBI::Cascade::Nullify'}";
		}else{
		    $arg = "{cascade=>'$casc'}";
		}
	    }else{
		    $arg = "{cascade=>'Delete'}";
	    }
	    $ret .= "__PACKAGE__->has_many( '$method', '$tab' => '$col', $arg );\n";
	}
    }
    return $ret;
}

=head2 schema_hash

    Use metadata to generate a hash ref containing the DB schema as it is
    used by DBIx::DBSchema.  This will, in turn, generate the appropriate
    SQL to create the database in either MySQL, Postgres, etc.
    
  Arguments:
    None
  Returns:
    Hash containing schema information to be passed to DBIx::DBSchema
  Example: 
    my $schema = $meta->schema_hash();

=cut

sub schema_hash {
    my $self = shift;
    my %ret;
    my @tables = $self->get_tables();

    foreach my $table ( sort @tables ){
	my $types    = $self->_get_column_attrs($table, 'type');
	my $nulls    = $self->_get_column_attrs($table, 'nullable');
	my $lengths  = $self->_get_column_attrs($table, 'length');
	my $defaults = $self->_get_column_attrs($table, 'default');
	# Convert nullable flag into NULL or empty string
	foreach my $c ( keys %$nulls ){
	    $nulls->{$c} = ( $nulls->{$c} )? "NULL" : "";
	}
	# Build the hash
	if ( $table =~ /$HIST/ ){
	    my $orig = $table;
	    $orig =~ s/$HIST//;
	    $ret{$table}{primary_key} = $self->_get_table_attr($orig, 'primary_key');
	    $ret{$table}{unique}      = [ [ ] ];
	    $ret{$table}{index}       = [ [ lc($orig) . "_id" ] ];
	}else{
	    $ret{$table}{primary_key} = $self->_get_table_attr($table, 'primary_key');
	    $ret{$table}{unique}      = $self->_get_table_attr($table, 'unique');
	    $ret{$table}{index}       = $self->_get_table_attr($table, 'index');
	}
	my $cols = $self->_get_columns($table);
	foreach my $col ( keys %$cols ){
	    push @{$ret{$table}{columns}}, 
	    ($col, $types->{$col}, $nulls->{$col}, $lengths->{$col}, $defaults->{$col}, '');
	}
    }
    return  ( keys %ret ) ? \%ret : undef;
}

##################################################################
#
# Private Methods
#
##################################################################

# _read_metadata - Reads Metadata from disk
#
# Metadata is stored as a Perl hash in a text file.  This method
# reads that file and adds the hash as an attribute of an instance
# of this class.
#

sub _read_metadata {
    my ($self, $file) = @_;
    my $info = {};
    $info = do "$file" or croak "Can't read $file: $@ || $!";
    return $info;
}

# _get_tables
#
# Returns an hashref of table hashrefs containing metadata
#

sub _get_tables{
    my $self = shift;
    if ( ! exists $meta->{tables} ){
	croak "Error getting meta tables";
    }
    my %ret = %{$meta->{tables}};
    return \%ret;
}

# _get_table_attr
#
# Given table name and attribute name, returns a scalar containing the value of 
# (or reference to) the given attribute for the given table.
#

sub _get_table_attr{
    my ($self, $table, $attr) = @_;
    croak "Need to pass table and attribute" unless $table && $attr;
    my $t = $self->_get_tables();
    my $ret;
    if ( ! exists $t->{$table}->{$attr} ){
	croak "Table '$table' does not have attribute '$attr'";
    }
    $ret = $t->{$table}->{$attr};
    return $ret;
}

# _get_columns
#
# Returns a hashref of column hashrefs for the given table
#

sub _get_columns{
    my ($self, $table) = @_;
    croak "Need to pass table name" unless $table;
    my $hist; 
    if ( $table =~ s/$HIST// ){
	$hist = 1;
    }
    my %ret = %{$self->_get_table_attr($table, 'columns')};
    
    # If it is a history table, we have to add these fields
    if ( $hist  ){
	# The field that points to the original object id
	my $hid    = lc($table) . "_id"; 
	$ret{$hid} = {default     => '',
		      description => '',
		      length      => '',
		      nullable    => 0,
		      tag         => '',
		      type        => 'integer'};
	
	$ret{modified} = {default     => '',
			  description => 'Time this record was last modified',
			  length      => '',
			  nullable    => 0,
			  tag         => 'Modified',
			  type        => 'timestamp'};
	
	$ret{modifier} = {default     => '',
			  description => 'Netdot user who last modified this record',
			  length      => '32',
			  nullable    => 1,
			  tag         => 'Modifier',
			  type        => 'varchar'};
	
	
    }
    return \%ret;
}

# _get_column_attrs
#
# Returns a hashref of a given column attribute for a table, indexed by column name

sub _get_column_attrs{
    my ($self, $table, $attr) = @_;
    croak "Need to pass table and attribute" unless $table && $attr;
    my %ret;
    my $cols = $self->_get_columns($table);
    foreach my $col ( keys %$cols ){
	if ( exists $cols->{$col}->{$attr} ){
	    $ret{$col} = $cols->{$col}->{$attr};
	}
    }
    return ( keys %ret ) ? \%ret : undef;
}

