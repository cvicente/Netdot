package Netdot::Model::DhcpAttr;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::DhcpAttr - DHCP Attribute Class

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


 Argsuments: 

  Returns: 

  Examples:

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('DhcpAttr::insert: Missing required parameters')
	unless ( defined $argv->{name} && defined $argv->{value} );
 
    my $name;
    if (!($name = DhcpAttrName->search(name=>$argv->{name})->first)){
	$name = DhcpAttrName->insert({name=>$argv->{name}});
    }
    $argv->{name} = $name->id;
    return $class->SUPER::insert($argv);
}

=head1 INSTANCE METHODS
=cut

############################################################################
=head2 as_text - Generate definition as text

  Argsuments: 
  Returns: 
  Examples:
    
=cut
sub as_text {
    my ($self, %argv) = @_;
    
    my $out = $self->name->as_text;
    $out .=  " " . $self->value if ( defined $self->value );
    $out .= ";\n";

    return $out;
}
    
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

