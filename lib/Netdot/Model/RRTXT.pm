package Netdot::Model::RRTXT;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRTXT - DNS TXT record Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

############################################################################
=head2 insert - Insert new RRTXT object

    We override the base method to:
    - Check if owner is an alias

  Arguments:
    See schema
  Returns:
    RRTXT object
  Example:
    my $record = RRTXT->insert(\%args)

=cut
sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal('Missing required arguments: rr')
	unless ( $argv->{rr} );

    $class->throw_user("Missing required argument: txtdata")
	unless ( $argv->{txtdata} );

    # Avoid the "CNAME and other records" error condition
    my $rr = (ref $argv->{name})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;
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

    # If TTL is not set, use Zone's default
    my $ttl = (defined $self->ttl && $self->ttl =~ /\d+/)? $self->ttl : $self->name->zone->default_ttl;

    my $ndo = Net::DNS::RR->new(
	name    => $self->rr->get_label,
	ttl     => $ttl,
	class   => 'IN',
	type    => 'TXT',
	txtdata => $self->txtdata,
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

