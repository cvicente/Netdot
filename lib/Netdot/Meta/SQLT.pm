package Netdot::Meta::SQLT;

use base 'Netdot::Meta';
use SQL::Translator;
use Data::Dumper;
use Carp;

my $t = SQL::Translator->new(no_comments         => 1,
			     add_drop_table      => 0,
			     validate            => 1,
			     );

1;

=head1 NAME

Netdot::Meta::SQLT - Netdot interface to SQL::Translator functions

=head1 SYNOPSIS

=head1 DESCRIPTION

  Netdot::Meta::SQLT provides relevant functionality from the SQL::Translator Class
  for use within Netdot

=head1 PUBLIC METHODS

=head2 new - Class Constructor
    
    my $sqlt = Netdot::Meta::SQLT->new();
    
=cut
#####################################################################
sub new{
    my ($class, %argv) = @_;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new(%argv);
}


#####################################################################
=head2 sql_schema - Generate SQL code to create schema

 Arguments:
    type - DBMS [MySQL|Pg]
  Returns:
    scalar containing SQL code
  Examples:
    my $schame_code = $sqlt->sql_schema('MySQL');

=cut
sub sql_schema {
    my ($self, $type) = @_;
    $t->parser( sub{ return $self->_parser(@_) } ) or croak $t->error;
    $t->producer($type) or croak $t->error;
    $t->filters( [sub{ return $self->_drop_fkeys(@_) }] ) or croak $t->error;
    my $output = $t->translate() or croak $t->error;
    return $output;
}

#####################################################################
=head2 html_schema - Generate HTML schema documentation 

 Arguments:
    None
  Returns:
    scalar containing HTML code
  Examples:
    print $sqlt->html_schema;

=cut
sub html_schema {
    my ($self) = @_;
    $t->parser( sub{ return $self->_parser(@_) } ) or croak $t->error;
    $t->producer('HTML') or croak $t->error;
    my $output = $t->translate() or croak $t->error;
    return $output;
}

#####################################################################
=head2 graphviz_schema - Generate GraphViz schema graph

 Arguments:
    out_file         => '/path/to/schema.png',
    layout           => 'dot',
    add_color        => 1,
    show_constraints => 1,
    show_datatypes   => 0,
    show_fields      => 0,
    show_col_sizes   => 0,
    width            => 17,
    length           => 22,
		    
  Returns:
    Saves the graph in the file specified
  Examples:
    $sqlt->graphviz_schema;

=cut
sub graphviz_schema {
    my ($self, %argv) = @_;
    croak "Missing required parameter: out_file" unless $argv{out_file};

    my %defaults = (output_type      => 'png',
		    layout           => 'dot',
		    add_color        => 1,
		    show_constraints => 1,
		    show_datatypes   => 0,
		    show_fields      => 0,
		    show_col_sizes   => 0,
		    width            => 20,
		    hight            => 15,
		    );
    my %args = %defaults;
    foreach my $key ( keys %argv ) { $args{$key} = $argv{$key} };

    $t->parser( sub{ return $self->_parser(@_) } ) or croak $t->error;
    $t->producer_args(\%args);
    $t->producer('GraphViz') or croak $t->error;
    $t->translate() or croak $t->error;
}

######################################################################
#
# Private Methods
#
######################################################################


#####################################################################
# Our parser creates the SQL::Translator::Schema object using 
# information from Netdot metadata
#
sub _parser{
    my ( $self, $tr ) = @_;
    my $schema = $tr->schema;
    my @tables = $self->get_tables(with_history => 1);
    foreach my $mtable ( @tables ) {
	my $table = $schema->add_table( name => $mtable->name )
	    or croak $schema->error;

	# Add Primary key constraint
	$table->add_constraint(name   => "pk_".$table->name,
			       type   => 'PRIMARY_KEY',
			       fields => 'id',
			       );

	# Add columns
	foreach my $mcol ( $mtable->get_columns ) {
	    my %field_args = (name              => $mcol->name,
			      data_type         => $mcol->sql_type,
			      size              => $mcol->length,
			      is_nullable       => $mcol->nullable
			      );
	    
	    $field_args{default_value} = $mcol->default 
		if ( (defined $mcol->default) && ($mcol->default ne '') );

	    $field_args{is_auto_increment} = 1 
		if ($mcol->name eq "id");
	    
	    $table->add_field(%field_args) or croak $table->error;
	    
	    # Add Foreign key constraints
	    if ( my $ft = $mcol->links_to() ){
		$table->add_constraint(name             => "fk_".$mcol->name,
				       type             => 'FOREIGN_KEY',
				       fields           => $mcol->name,
				       reference_table  => $ft,
				       reference_fields => 'id',
				       );
	    }
	}

	my $icount;

	# Add Unique indexes. Skip history tables

	my $hs = $self->get_history_suffix();
	if ( $mtable->name !~ /$hs/ ) {
	    foreach my $unique ( @{$mtable->get_unique_columns} ){
		$icount++;
		$table->add_index(name   => $table->name.$icount,
				  fields => $unique,
				  type   => 'UNIQUE',
				  );
	    }
	}
	# Add normal indexes

	foreach my $index ( @{$mtable->get_indexed_columns} ){
	    $icount++;
	    $table->add_index(name   => $mtable->name.$icount,
			      fields => $index,
			      type   => 'NORMAL',
			      );
	}
    }
    return 1;
}

#####################################################################
# Ignore FOREIGN KEY constraints when generating the actual schema
#
# This might change in the future, but for now, FK constraints at the 
# DB level are a royal pain.
sub _drop_fkeys {
    my ($self, $schema) = @_;
    foreach my $table ( $schema->get_tables ){
	foreach my $constraint ( $table->get_constraints ){
	    if ($constraint->type eq "FOREIGN KEY"){
		$table->drop_constraint($constraint);
	    }
	}
    }
}

