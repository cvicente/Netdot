package Netdot::Model::RRADDR;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRADDR - DNS Adress Class

RRADDR represent either A or AAAA records.

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut


############################################################################
=head2 insert - Insert new RRADDR object

    We override the base method to:
     - Create or update the corresponding RRPTR object
    
  Arguments:
    Hashref with key/value pairs
  Returns:
    RRADDR object
  Example:
    my $arecord = RRADDR->insert(\%args)

=cut
sub insert {
    my($class, $argv) = @_;
    
    my $rraddr = $class->SUPER::insert($argv);

    my $ipb =  $rraddr->ipblock;
    
    # Create/update PTR record for this IP
    $rraddr->_update_rrptr();

    return $rraddr;
    
}
=head1 INSTANCE METHODS
=cut

############################################################################
=head2 update

    We override the base method to:
     - Create or update the corresponding RRPTR object
    
  Arguments:
    Hashref with key/value pairs
  Returns:
    Number of rows updated or -1
  Example:
    $arecord->update(\%args)

=cut
sub update {
    my($self, $argv) = @_;
    $self->isa_object_method('update');

    my @res = $self->SUPER::update($argv);

    $self->_update_rrptr();

    return @res;
}

############################################################################
=head2 delete - Delete object
    
    We override the delete method for extra functionality:
    - When removing an address record, most likely the RR (name)
    associated with it needs to be deleted too, unless it has
    more adddress records associated with it.

  Arguments:
    None
  Returns:
    True if successful. 
  Example:
    $rraddr->delete;

=cut

sub delete {
    my $self = shift;
    $self->isa_object_method('delete');
    my $rr = $self->rr;
    $self->SUPER::delete();
    $rr->delete() unless ( $rr->arecords || $rr->devices );

    return 1;
}


##################################################################
=head2 as_text

    Returns the text representation of this A/AAAA record

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

############################################################################
#
# When an RRADDR record is inserted or updated, we make sure to 
# update the corresponding PTR record
#
sub _update_rrptr {
    my ($self) = @_;
    $self->isa_object_method('_update_rrptr');

    my $rrptr;
    if ( !($rrptr = ($self->ipblock->ptr_records)[0]) ){
	# We *need* to have a SubnetZone relationship.
	# Otherwise it's hard to tell where the PTR record goes
	if ( my $rev_zone = $self->ipblock->reverse_zone() ){
	    # Notice that we don't pass the rr field because
	    # the RRPTR class can figure that out.
	    $rrptr = RRPTR->insert({ptrdname => $self->rr->get_label, 
				    ipblock  => $self->ipblock, 
				    zone     => $rev_zone,
				    ttl      => $self->ttl});
	}
    }elsif ( $rrptr->ptrdname ne $self->rr->get_label ){
	$rrptr->update({ptrdname=>$self->rr->get_label});
    }
    return 1;
}


##################################################################
sub _net_dns {
    my $self = shift;
    my $type = ($self->ipblock->version == 4)? 'A' : 'AAAA';

    my $ndo = Net::DNS::RR->new(
	name    => $self->rr->get_label,
	ttl     => $self->ttl,
	class   => 'IN',
	type    => $type,
	address => $self->ipblock->address,
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

