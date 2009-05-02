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
      - Assign DhcpScopeType based on given text or id
      - Insert given attributes

 Argsuments: 
    Hashref with following keys:
      name
      type        - DhcpScopeType name, id or object
      attributes  - A hash ref with attribute key/value pairs
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

############################################################################
=head2 as_text - Generate scope definition as text

    Output will include other scopes contained within given scope.

  Argsuments: 
  Returns: 
  Examples:
    
=cut
sub as_text {
    my ($self, %argv) = @_;

    my $out;
    my $indent;

    # Open scope definition
    if ( $self->type->name ne 'global' ){
	$out .= $self->type->name." ".$self->name." {\n";
	$indent .= " " x 4;
    }

    if ( $self->type->name eq 'host' ){
	# We don't store these attributes
	if ( $self->physaddr && $self->ipblock ){
	    $out .= $indent.'hardware ethernet '.$self->physaddr->colon_address.";\n";
	    $out .= $indent.'fixed-address '.$self->ipblock->address.";\n";
	}
    }

    # Any free-form text goes verbatim first
    if ( defined $self->text ){
	$out .= $self->text."\n";
    }
    
    # Now print all my own attributes
    foreach my $attr ( $self->attributes ){
	$out .= $indent if defined $indent;
	$out .= $attr->as_text;
    }

    # Now do the same for each contained scope
    if ( my @sub_scopes = $self->contained_scopes ){
	foreach my $s ( @sub_scopes ){
	    $out .= $s->as_text();
	}
    }

    # Close scope definition
    if ( $self->type->name ne 'global' ){
	$out .= "}\n";
    }

    return $out;
}

############################################################################
=head2 print_to_file -  Print the config file as text

 Args: 
  Returns: 
    True
  Examples:
    $scope->print_to_file();

=cut
sub print_to_file{
    my ($self, %argv) = @_;
    $self->isa_object_method('print_to_file');
    
    my $dir = Netdot->config->get('DHCPD_EXPORT_DIR') 
	|| $self->throw_user('DHCPD_EXPORT_DIR not defined in config file!');
    
    my $filename = $self->export_file;
    unless ( $filename ){
	$logger->warn('Export filename not defined for this global scope: '. $self->name.' Using scope name.');
	$filename = $self->name;
    }
    my $path = "$dir/$filename";
    my $fh = Netdot::Exporter->open_and_lock($path);
    
    print $fh $self->as_text, "\n";

    close($fh);
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

