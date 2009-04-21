package Netdot::Model::DhcpScope;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::DhcpScope - DHCP scope Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

############################################################################
=head2 search


 Argsuments: 

  Returns: 

  Examples:

=cut

sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    # Class::DBI::search() might include an extra 'options' hash ref
    # at the end.  In that case, we want to extract the 
    # field/value hash first.
    my $opts = @args % 2 ? pop @args : {}; 
    my %args = @args;

    if ( defined $args{type} ){
	if ( $args{type} =~ /\w+/ ){
	    if ( my $type = DhcpScopeType->search(name=>$args{type})->first ){
		$args{type} = $type->id;
	    }
	}
    }
    return $class->SUPER::search(%args, $opts);
}

############################################################################
=head2 insert - Insert new Scope

    Override base method to:
      - Assign DhcpScopeType based on give text or id
      - Insert given attributes

 Argsuments: 
    name
    type
    attributes
  Returns: 
    DhcpScope object
  Examples:
    
=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('DhcpScope::insert: Missing required parameters')
	unless ( defined $argv->{name} && defined $argv->{type} );

    if ( $argv->{type} =~ /\D+/ ){
	my $type = DhcpScopeType->search(name=>$argv->{type})->first;
	$class->throw_user("DhcpScope::insert: Unknown type: $argv->{type}")
	    unless $type;
	$argv->{type} = $type;
    }
    my $attributes = delete $argv->{attributes} if defined $argv->{attributes};

    my $scope = $class->SUPER::insert($argv);
    
    if ( $attributes ){
	while ( my($key, $val) = each %$attributes ){
	    my $attr;
	    if ( !($attr = DhcpAttr->search(name=>$key, value=>$val, scope=>$scope->id)->first) ){
		$logger->debug("DhcpScope::insert: ".$scope->get_label.": Inserting DhcpAttr $key: $val");
		DhcpAttr->find_or_create({name=>$key, value=>$val, scope=>$scope->id});
	    }
	}
    }

    return $scope;
}

=head1 INSTANCE METHODS
=cut



=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

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

#Be sure to return 1
1;

