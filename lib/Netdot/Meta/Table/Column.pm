package Netdot::Meta::Table::Column;

use strict;
use Carp;

1;

=head1 NAME

Netdot::Meta::Table::Column

=head1 SYNOPSIS


=head1 PUBLIC METHODS

=cut

##################################################
=head2 new - Class Constructor
    
    my $mcol = Netdot::Meta::Table::Column->new($info);

=cut
sub new {
    my ($class, $info) = @_;
    croak "Incorrect call to new as an object method" 
	if ref($class);
    my $self = $info;
    bless $self, $class;
}

##################################################
=head2 name - Returns the name of this column

  Arguments:
    None
  Returns:
    name (scalar)
  Example: 
    my $column_name = $mcol->name;

=cut
sub name {
    my $self = shift;
    return $self->_get_attr('name');
}

##################################################
=head2 sql_type - Returns the SQL type as defined in the schema

  Arguments:
    None
  Returns:
    Scalar containing the SQL type of the column
  Example: 
    $type = $mcol->sql_type();

=cut
sub sql_type {
    my $self = shift;
    return $self->_get_attr('type');
}

##################################################
=head2 descr -  Get column description

  Arguments:
    None
  Returns:
    Scalar containing description for this column
  Example: 
    $descr = $mcol->descr();

=cut
sub descr {
    my $self = shift;
    return $self->_get_attr('description');
}

##################################################
=head2 length - Get the DB length for this column

  Arguments:
    None
  Returns:
    Scalar containing the length for this column
  Example: 
    $len = $mcol->length();

=cut
sub length {
    my $self = shift;
    return $self->_get_attr('length');
}

##################################################
=head2 default - Get the default value for this column

  Arguments:
    None
  Returns:
    Scalar containing the default value for this column
  Example: 
    $len = $mcol->default();

=cut
sub default {
    my $self = shift;
    return $self->_get_attr('default');
}

##################################################
=head2 nullable - Get 'nullable' nature for this column as defined in the DB

  Arguments:
    None
  Returns:
    True or false.  True meaning that the column can be set to NULL.
  Example: 
    $null = $mcol->nullable;

=cut
sub nullable {
    my $self = shift;
    return $self->_get_attr('nullable');
}

##################################################
=head2 tag - Get the tag for this column

    A column tag is the user-friendly name for the column displayed in the 
    user interface.

  Arguments:
    None
  Returns:
    Scalar containing the tag string
  Example: 
    $tag = $mcol->tag();

=cut
sub tag {
    my $self = shift;
    return $self->_get_attr('tag');
}

##################################################
=head2 is_unique -  Get a flag with the 'uniqueness' nature of this column.

    This is basically used to determine if the column is required when showing a form.
    Note: We do not use the NULLABLE attribute to determine this because in our case, 
    columns defined as 'NOT NULL' happen to be set to '0', even if the assigned Perl value 
    is undef.

  Arguments:
    None
  Returns:
    True or False
  Example: 
    $unique = $mcol->is_unique();

=cut
sub is_unique {
    my $self = shift;
    my $unique = $self->{table}->get_unique_columns();
    # The unique attribute is an arrayref containing either column names 
    # or other arrayrefs with column names
    # If the column is contained in any of these, it is 
    # unique
    my %unique;
    foreach my $elem ( @$unique ){
	if ( ref($elem) eq "ARRAY" ){
	    foreach my $col ( @$elem ){
		$unique{$col}++;
	    }
	}else{
	    $unique{$elem}++;
	} 
    }
    return 1 if exists $unique{$self->name};
    return 0;
}

##################################################
=head2 links_to_attrs - Get the attributes for this column\'s foreign key relationship

  Arguments:
    None
  Returns:
    hashref
  Example: 

    my $attrs = $col->links_to_attrs

=cut
sub links_to_attrs{
    my $self = shift;
    return $self->{'linksto'} if exists $self->{'linksto'};
}

##################################################
=head2 links_to

    Get foreign table that this column points to

  Arguments:
    None
  Returns:
    Foreign table name
  Example: 

    my $foreign_table = $mcol->links_to();

=cut
sub links_to{
    my $self = shift;
    my $lt = $self->links_to_attrs();
    return unless $lt;
    return $lt->{table} if exists $lt->{table};
}



##################################################################
#
# Private Methods
#
##################################################################

##################################################
# _get_attr
#
# Returns a hashref of a given column attribute

sub _get_attr{
    my ($self, $attr) = @_;
    croak "Need to pass attribute" unless $attr;
    croak "$attr not found" 
	unless exists $self->{$attr};
    return $self->{$attr};
}

