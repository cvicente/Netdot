package Netdot::Model::ASN;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::ASN - Autonomous System Number class

=head1 CLASS METHODS
=cut

##################################################################

=head2 insert - Insert a new ASN

    Override parent method to:
    - Validate arguments

  Arguments:
    Hash ref of key/value pairs
  Returns: 
    New ASN object
  Examples:
    ASN->insert(\%data);
    
=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal("Missing required arguments: number")
	unless ( exists $argv->{number} );

    $class->_validate($argv);

    my $new;
    if ( $new = $class->search(number=>$argv->{number})->first ){
	$class->throw_user("ASN number ".$argv->{number}." already exists!");
    }else{
	$new = $class->SUPER::insert($argv);
    }

    return $new;
}

=head1 INSTANCE METHODS
=cut

############################################################################

=head2 update 
    
    Override parent method to:
    - Validate arguments

  Args: 
    Hashref
  Returns: 
    See Class::DBI
  Examples:
    $asn->update(\%args);
=cut

sub update{
    my ($self, $argv) = @_;
    $self->isa_object_method('update');

    $self->_validate($argv);

    my @res = $self->SUPER::update($argv);
    return @res;
}

##################################################################
# Private Methods
##################################################################

##################################################################
# _validate - Validate block when creating and updating
#
#   Arguments:
#     Hash ref of arguments passed to insert/set
#   Returns:
#     True if object is valid.  Throws exception if not.
#   Examples:
#     $asn->_validate($args);


sub _validate {
    my ($self, $args) = @_;
    
    my $num = $args->{number};
    if ( $num < 1 || $num > 4294967295 ){
	$self->throw_user("Invalid AS number: $num");	
    }

    if ( my $rir = $args->{rir} ){
	my $re = $self->config->get('VALID_RIR_REGEX');
	unless ( $rir =~ /$re/ ){
	    $self->throw_user("Invalid RIR: $rir");
	}
    }

    return 1;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2013 University of Oregon, all rights reserved.

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
