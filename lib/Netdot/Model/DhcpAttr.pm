package Netdot::Model::DhcpAttr;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DHCP');

=head1 NAME

Netdot::Model::DhcpAttr - DHCP Attribute Class

=head1 CLASS METHODS
=cut

############################################################################

=head2 search

    We override the base method to:
    - Accept name as string

  Arguments: 
    Hash of key/value pairs
  Returns: 
    Array of objects or iterator
  Examples:
    DhcpAttr->search(%args);
=cut

sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    my $opts = @args % 2 ? pop @args : {}; 
    my %args = @args;

    if ( defined $args{name} ){
	if ( $args{name} =~ /\w+/ ){
	    if ( my $name = DhcpAttrName->search(name=>$args{name})->first ){
		$args{name} = $name->id;
	    }
	}
    }
    return $class->SUPER::search(%args, $opts);
}

############################################################################

=head2 insert - Insert new Scope

    We override the base method to:
    - Accept name as string

  Arguments: 
    Hashref of key/value pairs
  Returns: 
    New DhcpAttr object
  Examples:
    DhcpAttr->insert(\%args)
=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('DhcpAttr::insert: Missing required parameters: name')
	unless ( $argv->{name}  );
 
    $class->_objectify_args($argv);

    return $class->SUPER::insert($argv);
}

=head1 INSTANCE METHODS
=cut

############################################################################

=head2 update

    We override the base method to:
    - Accept name as string

  Arguments: 
    Hashref of key/value pairs
  Returns: 
    Same as Class::DBI
  Examples:
    $attr->update(\%args)
=cut

sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');

    $self->_objectify_args($argv);

    return $self->SUPER::update($argv);
}


############################################################################
# Private methods
############################################################################

############################################################################
# objectify_args
#
#     Convert following arguments into objects:
#     - name
#   
#   Args: 
#     hashref
#   Returns: 
#     True
#   Examples:
#     $class->_objectify_args($argv);
#
# 
sub _objectify_args {
    my ($self, $argv) = @_;

    my $name;
    if ( $argv->{name} && !ref($argv->{name}) ){
	# Argument exists and it's not an object
	if ( $argv->{name} =~ /\D+/ ){
	    # Argument is a non-digit
	    $name = DhcpAttrName->search(name=>$argv->{name})->first;
	    $self->throw_user("DhcpAttr::objectify_args: Unknown Attribute Name: ".$argv->{name})
		unless $name;
	    $argv->{name} = $name;
	}elsif ( $name = DhcpAttrName->retrieve($argv->{name}) ){
	    # Argument was an integer and we found an object 
	    $argv->{name} = $name;
	}else{
	    $self->throw_user("Invalid name argument ".$argv->{name});
	}
    }
}    
=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

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

