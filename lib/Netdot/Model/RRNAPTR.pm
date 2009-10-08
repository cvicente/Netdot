package Netdot::Model::RRNAPTR;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

my $MAX_ORDER      = 2**16 - 1;
my $MAX_PREFERENCE = $MAX_ORDER;

=head1 Netdot::Model::RRNAPTR - DNS NAPTR record Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

############################################################################
=head2 insert - Insert new RRNAPTR object

    We override the base method to:
    - Validate fields
    - Check for conflicts with other record types

  Arguments:
    See schema
  Returns:
    RRNAPTR object
  Example:
    my $record = RRNAPTR->insert(\%args)

=cut
sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal('Missing required arguments: rr')
	unless ( $argv->{rr} );

    foreach my $field ( qw/order_field preference flags services regexpr replacement/ ){
	$class->throw_user("Missing required argument: $field")
	    unless (defined $argv->{$field});
    }

    $class->throw_user("Invalid order value: ".$argv->{order_field})
	if ( $argv->{order_field} < 0 || $argv->{order_field} > $MAX_ORDER );

    $class->throw_user("Invalid preference value: ".$argv->{preference})
	if ( $argv->{preference} < 0 || $argv->{preference} > $MAX_PREFERENCE );

    $class->throw_user("Invalid services string: ".$argv->{services})
	if ( !($argv->{services} =~ /^e2u\+/i) );
    
    my $rr = (ref $argv->{rr})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;

    # TTL needs to be set and converted into integer
    $argv->{ttl} = (defined($argv->{ttl}) && length($argv->{ttl}))? $argv->{ttl} : $rr->zone->default_ttl;
    $argv->{ttl} = $class->ttl_from_text($argv->{ttl});

    # Avoid the "CNAME and other records" error condition
    if ( $rr->cnames ){
	$class->throw_user("Cannot add any other record to an alias");
    }
    if ( $rr->ptr_records ){
	$class->throw_user("Cannot add any other record when PTR records exist");
    }

    return $class->SUPER::insert($argv);
    
}

=head1 INSTANCE METHODS
=cut
############################################################################
=head2 update

    We override the base method to:
     - Validate TTL and other values
    
  Arguments:
    Hash with field/value pairs
  Returns:
    Number of rows updated or -1
  Example:
    $record->update(\%args)

=cut
sub update {
    my($self, $argv) = @_;
    $self->isa_object_method('update');

    if ( defined $argv->{ttl} ){
	$argv->{ttl} = $self->ttl_from_text($argv->{ttl});
    }
    if ( defined $argv->{order_field} ){
	$self->throw_user("Invalid order value: ".$argv->{order_field})
	    if ( $argv->{order_field} < 0 || $argv->{order_field} > $MAX_ORDER );
    }
    if ( defined $argv->{preference} ){
	$self->throw_user("Invalid preference value: ".$argv->{preference})
	    if ( $argv->{preference} < 0 || $argv->{preference} > $MAX_PREFERENCE );
    }
    if ( defined $argv->{service} ){
	$self->throw_user("Invalid service string: ".$argv->{service})
	    if ( !($argv->{service} =~ /^e2u\+/i) );
    }

    return $self->SUPER::update($argv);
}

##################################################################
=head2 as_text

    Returns the text representation of this record

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->as_text();

=cut
sub as_text {
    my $self = shift;
    $self->isa_object_method('as_text');

    return $self->_net_dns->string();
}


##################################################################
# Private methods
##################################################################


##################################################################
sub _net_dns {
    my $self = shift;

    my $ndo = Net::DNS::RR->new(
	name        => $self->rr->get_label,
	ttl         => $self->ttl,
	class       => 'IN',
	type        => 'NAPTR',
	order       => $self->order_field,
	preference  => $self->preference,
	flags       => $self->flags,
	service     => $self->services,
	regexp      => $self->regexpr,
	replacement => $self->replacement,
	);
    
    return $ndo;
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

