package Netdot::Meta::Table;

use Netdot::Meta::Table::Column;

use strict;
use Carp;

# Some private class data and related methods
{
    # Cache Meta::Table::Column objects
    my %_column_cache;

    sub cache_column {
	my ($self, $table, $obj) = @_;
	$_column_cache{$table}{$obj->name} = $obj;
	return 1;
    }
    sub get_cached_column{
	my ($self, $table, $name) = @_;
	return $_column_cache{$table}{$name} 
	if exists $_column_cache{$table}{$name};
    }
}

1;

=head1 NAME

Netdot::Meta::Table

=head1 SYNOPSIS


=head1 PUBLIC METHODS

=cut

##################################################
sub new {
    my ($class, $info) = @_;
    croak "Incorrect call to new as an object method" 
	if ref($class);
    my $self = $info;
    bless $self, $class;
}

##################################################
=head2 name - Returns the name of this table

  Arguments:
    None
  Returns:
    name (scalar)
  Example: 
    my $table_name = $mtable->name;

=cut
sub name {
    my $self = shift;
    return $self->_get_attr('name');
}

##################################################
=head2 db_name - Returns the actual name of this table in the database

  Arguments:
    None
  Returns:
    name (scalar)
  Example: 
    my $db_name = $mtable->db_name;

=cut
sub db_name {
    my $self = shift;
    return $self->_get_attr('table_db_name');
}

##################################################
=head2 descr -  Get Table description

  Arguments:
    None
  Returns:
    Scalar containing description for this table
  Example: 
    $descr = $mtable->descr();

=cut
sub descr {
    my $self = shift;
    return $self->_get_attr('description');
}

##################################################
=head2 get_column_names

  Arguments:
    None
  Returns:
    Array with table names
  Example: 
    my @tables = Netdot::Meta::Table->get_table_names();

=cut
sub get_column_names{
    my $self = shift;
    my @names = sort keys %{$self->_get_columns_hash()};
    return @names;
}

##################################################
=head2 get_column - Get new Column object

  Arguments:
    column name
  Returns:
    Netdot::Meta::Column object
  Example: 
    my $mc = Device->meta_data->get_column('sysdescription');
=cut
sub get_column {
    my ($self, $name) = @_;
    my $newcolumn;
    if ( $newcolumn = $self->get_cached_column($self->name, $name) ){
	return $newcolumn;
    }else{
	my $info = $self->_get_column_info($name);
	$info->{name}  = $name;
	$info->{table} = $self;
	$newcolumn = Netdot::Meta::Table::Column->new($info);
	$self->cache_column($self->name, $newcolumn);
    }
    return $newcolumn;
}

##################################################
=head2 get_columns - Get a list of all Column objects for this table

  Arguments:    None
  Returns:
    Array
  Example: 
    my @meta_columns = $mtable->get_columns;

=cut
sub get_columns {
    my $self = shift;
    my @ret;
    push @ret, $self->get_column($_) foreach $self->get_column_names();
    return @ret;
}

=head2 understanding get links methods


 +------+   ``this links_to that''     +------+
 |      | ``that has links_from this'' |      |
 | this |----------------------------->| that |
 |      |                              |      |
 +------+ Many                     One +------+

Keep the arrow head (-->) in mind, otherwise the names would be ambiguous. 

=cut

##################################################
=head2 get_links_to

    Get foreign key relationships for a given table,
    (equivalent to has_a definitions in Class::DBI).
    
  Arguments:
    None
  Returns:
    Hash keyed by column name, values are foreign tables.
  Example: 

    %linksto = $mtable->get_links_to();

=cut
sub get_links_to{
    my $self = shift;
    my %ret;
    foreach my $c ( $self->get_columns() ){
	if ( my $l = $c->links_to ){
	    $ret{$c->name} = $l;
	}
    }
    return %ret;
}

##################################################
=head2 get_links_from

    Get one-to-many relationships for a given table, this table being on the "one" side 
    (equivalent to has_many definitions in Class::DBI).
    History tables are not referenced by other tables
    
  Arguments:
    None
  Returns:
    Hash.  The keys of the main hash are identifiers for the relationship.  The nested hashs keys are names of
    the tables that reference this table.  The values are the names of the fields in those tables that
    reference this tables primary key.
  Example: 

    %links = $mtable->get_links_from();

=cut
sub get_links_from{
    my $self = shift;
    my %ret;
    return if ( $self->is_history );
    foreach my $t ( $self->{meta}->get_tables(with_history=>1) ){
	foreach my $c ( $t->get_columns() ){
	    my $lt = $c->links_to_attrs();
	    next unless ( $lt && exists $lt->{table} );
	    if ( $lt->{table} eq $self->name ){
		next unless exists $lt->{method};
		my $method;
		if ( $t->is_history && $lt->{method} ne 'history_records' ){
		    $method = 'history_'.$lt->{method};
		}else{
		    $method = $lt->{method};
		}
		$ret{$method}{$t->name} = $c->name;
	    }
	}
    }
    return %ret;
}

##################################################
=head2 get_column_order
    
    Provide the position of all columns in this table, in the order they are 
    supposed to be displayed.  Supports the notion of 'views', which allow
    you to show different sets of fields, depending on the context.
    
  Arguments:
    view  -  Name of view (defaults to 'all')
  Returns:
    Hash containing column positions, indexed by column name
  Example: 
    
   %order = $mtable->get_column_order(view=>'all');
   foreach my $col { sort $order{$a} <=> $order{$b} } keys %order
     ...

=cut
sub get_column_order{
    my ($self, %argv) = @_;
    my $views = $self->_get_attr('views');
    my $view = $argv{view} || 'all';

    if ( ! exists $views->{$view} ){
	return;
    }
    my @tmp = @{$views->{$view}};
    if ( $self->is_history ){
	push @tmp, ('modified', 'modifier');
    }
    my $i = 1;
    my %ret;
    map { $ret{$_} = $i++ } @tmp;
    return %ret;
}

##################################################
=head2 get_column_order_brief

    Provide the position of most relevant columns in this table, in the order they are 
    supposed to be displayed

  Arguments:
    None
  Returns:
    Hash containing column positions, indexed by column name
  Example: 
     %orderbrief = $mtable->get_column_order_brief();
     foreach my $col { sort $orderbrief{$a} <=> $orderbrief{$b} } keys %orderbrief
       ...


=cut
sub get_column_order_brief {
    my $self = shift;
    my @tmp;
    if ( $self->is_history ){
	push @tmp, ('modified', 'modifier');
    }
    my $views = $self->_get_attr('views');
    if ( ! exists $views->{brief} ){
	return;
    }
    push @tmp, @{$views->{brief}};
    my $i = 1;
    my %ret;
    map { $ret{$_} = $i++ } @tmp;
    return %ret;
}

##################################################
=head2 get_labels -  Get labels this table. 

    Labels are one or more columns used as hyperlinks to retrieve
    the specified object.  They are also used as a meaningful instance identifier.

  Arguments:
    None
  Returns:
    Array containing columns included in the label
  Example: 
    @lbls = $mtable->get_labels();


=cut
sub get_labels{
    my $self = shift;
    my @labels = @{$self->_get_attr('label')};
    return ( @labels ) ? @labels : undef;
}

##################################################
=head2 get_unique_columns - Get list of unique columns

  Arguments:
    None
  Returns:
    Arrayref containing either column names 
    or other arrayrefs containing column names
  Example: 
    $unique = $mtable->get_unique_columns();

=cut
sub get_unique_columns {
    my $self = shift;
    return $self->_get_attr('unique');
}

##################################################
=head2 get_indexed_columns - Get list of indexed columns for this table

  Arguments:
    None
  Returns:
    Arrayref containing either column names 
    or other arrayrefs containing column names
  Example: 
    $unique = $mtable->get_indexed_columns();

=cut
sub get_indexed_columns {
    my $self = shift;
    my $idx = []; 
    if ( $self->is_history ){
	# History tables do not need the same indexes
	# as their real counterpars.
	# We index the id that points to the  real table
	push @$idx, lc($self->original_table)."_id";
	# Also, the modified date
	push @$idx, 'modified';
    }else{
	$idx = $self->_get_attr('index');
    }
    return $idx;
}

##################################################
=head2 is_join - Check if table is a join table

  Arguments:
    None
  Returns:
    True or false (1 or 0)
  Example: 
  $flag = $mtable->is_join();

=cut
sub is_join {
    my $self = shift;
    return $self->_get_attr('isjoin');
}

##################################################
=head2 has_history - Check if this table has a corresponding history table

  Arguments:
    None
  Returns:
    True or false (1 or 0)
  Example: 
  $flag = $mtable->has_history();

=cut
sub has_history {
    my ($self) = @_;
    return $self->_get_attr('has_history');
}

##################################################
=head2 get_history_table_name - Return the name of the history table that corresponds to this table

  Arguments:
    None
  Returns:
    History table name
  Example: 

=cut
sub get_history_table_name {
    my ($self) = @_;
    if ( $self->has_history && !$self->is_history ){
	return $self->name . $self->{meta}->get_history_suffix;
    }
    return;
}

##################################################
=head2 is_history - Check if this table is a history table

  Arguments:
    None
  Returns:
    True or false (1 or 0)
  Example: 
  $flag = $mtable->is_history();

=cut
sub is_history {
    my ($self) = @_;
    return $self->_get_attr('is_history');
}

##################################################
=head2 original_table - Return name of original table if this is a history table

  Arguments:
    None
  Returns:
    Name of original table 
  Example: 
  $orig = $mtable->original_table();

=cut
sub original_table {
    my ($self) = @_;
    return $self->_get_attr('original_table')
	if ( $self->is_history );
}

##################################################################
#
# Private Methods
#
##################################################################

##################################################
# _get_attr
#
# Given an attribute name, returns a scalar containing the value of 
# (or reference to) the given attribute for this table.
#

sub _get_attr{
    my ($self, $attr) = @_;
    croak "Need to pass attribute" 
	unless $attr;
    croak "Table ", $self->name, " does not have attribute '$attr'"
	unless exists $self->{$attr};
    return $self->{$attr};
}

##################################################
# _get_columns_hash
#
# Returns a hashref of column info hashrefs for this table.
# 

sub _get_columns_hash{
    my $self = shift;
    my %ret = %{ $self->_get_attr('columns') };
    # If it is a history table, we have to add some columns
    if ( $self->is_history ){
	# The field that points to the original object id
	my $hid    = lc($self->original_table)."_id"; 
	$ret{$hid} = {default     => '',
		      description => '',
		      length      => '',
		      linksto => {
			  cascade => 'Delete',
			  method  => 'history_records',
			  table   => $self->original_table
			  },
		      nullable    => 1,
		      tag         => '',
		      type        => 'bigint'};
	
	$ret{modified} = {default     => '1970-01-02 00:00:01',
			  description => 'Time this record was last modified',
			  length      => '',
			  nullable    => 0,
			  tag         => 'Modified',
			  type        => 'timestamp'};
	
	$ret{modifier} = {default     => '',
			  description => 'Netdot user who last modified this record',
			  length      => '255',
			  nullable    => 1,
			  tag         => 'Modifier',
			  type        => 'varchar'};
	
	
    }
    return \%ret;
}

##################################################
# _get_column_info
#
# Returns an hashref containing column metadata
#

sub _get_column_info {
    my ($self, $name) = @_;
    croak "Need to pass column name"
	unless $name;
    my $columns = $self->_get_columns_hash();
    croak "column $name does not exist in table ", $self->name
	unless exists $columns->{$name};
    my %info = %{ $columns->{$name} };
    return \%info;
}

