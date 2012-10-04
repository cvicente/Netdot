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
    type - DBMS [MySQL|PostgreSQL]
  Returns:
    scalar containing SQL code
  Examples:
    my $schame_code = $sqlt->sql_schema('MySQL');

=cut

sub sql_schema {
    my ($self, $type) = @_;
    $t->parser( sub{ return $self->_parser(@_) } ) or croak $t->error;
    $t->producer($type) or croak $t->error;
    my $output = $t->translate() or croak $t->error;
    if ( $type eq 'PostgreSQL' ){
	# Bug in SQLT
	# https://rt.cpan.org/Public/Bug/Display.html?id=58420
	$output =~ s/serial NOT NULL/bigserial NOT NULL/smg;
    }
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
		    height           => 15,
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
	my $tname = $mtable->name;
	$tname = lc($tname);
	my $table = $schema->add_table(name=>$tname)
	    or croak $schema->error;

	$table->extra(mysql_table_type=>'InnoDB');
	
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
			      is_nullable       => $mcol->is_nullable
			      );
	    
	    $field_args{default_value} = $mcol->default 
		if ( (defined $mcol->default) && ($mcol->default ne '') );

	    if ( $mcol->name eq 'id' ){
		$field_args{is_auto_increment} = 1;
	    }
	    
	    $table->add_field(%field_args) or croak $table->error;
	   
	    
	    # Add Foreign key constraints
	    if ( my $ft = $mcol->links_to() ){
		$table->add_constraint(name             => "fk_".$mcol->name,
				       type             => 'FOREIGN_KEY',
				       fields           => $mcol->name,
				       reference_table  => lc($ft),
				       reference_fields => 'id',
				       );
	    }
	}

	my $icount;

	# Add Unique indexes. Skip history tables
	unless ( $mtable->is_history ) {
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


=head1 AUTHORS

Carlos Vicente

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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

#Be sure to return 1
1;


