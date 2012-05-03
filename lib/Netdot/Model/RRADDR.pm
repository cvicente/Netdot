package Netdot::Model::RRADDR;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRADDR - DNS Address Class

RRADDR represent either A or AAAA records.

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut


############################################################################
=head2 insert - Insert new RRADDR object

    We override the base method to:
    - Validate TTL
    - Check for conflicting record types
    - Create or update the corresponding RRPTR object
    - Sanitize ipblock argument

  Arguments:
    Hashref with key/value pairs, plus:
      update_ptr - Update corresponding RRPTR object (default: ON)
  Returns:
    RRADDR object
  Example:
    my $arecord = RRADDR->insert(\%args)

=cut
sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');
    
    $class->throw_fatal('Missing required arguments')
	unless ( $argv->{ipblock} && $argv->{rr} );

    my $rr = (ref $argv->{rr})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;

    # TTL needs to be set and converted into integer
    $argv->{ttl} = (defined($argv->{ttl}) && length($argv->{ttl}))? $argv->{ttl} : $rr->zone->default_ttl;
    $argv->{ttl} = $class->ttl_from_text($argv->{ttl});
    
    # Avoid the "CNAME and other records" error condition
    if ( $rr->cnames ){
	$class->throw_user($rr->name.": Cannot add any other record to an alias");
    }
    if ( $rr->ptr_records ){
	$class->throw_user($rr->name.": Cannot add A/AAAA records when PTR records exist");
    }
    if ( $rr->naptr_records ){
	$class->throw_user($rr->name.": Cannot add A/AAAA records when NAPTR records exist");
    }
    if ( $rr->srv_records ){
	$class->throw_user($rr->name.": Cannot add A/AAAA records when SRV records exist");
    }
    
    $argv->{ipblock} = $class->_convert_ipblock($argv->{ipblock});
    
    my $update_ptr = 1; # On by default
    if ( defined $argv->{update_ptr} ){
	$update_ptr = delete $argv->{update_ptr};
    }
    
    my $rraddr = $class->SUPER::insert($argv);

    # Make sure that the IP is not left as "Available" or "Discovered" 
    my $current_status = $rraddr->ipblock->status->name;
    $rraddr->ipblock->update({status=>'Static'}) 
	if ( $current_status eq 'Available' || $current_status eq 'Discovered' );
    
    # Create/update PTR record for this IP
    $rraddr->update_rrptr() if $update_ptr;
    
    return $rraddr;
    
}

=head1 INSTANCE METHODS
=cut

############################################################################
=head2 update

    We override the base method to:
     - Validate TTL
     - Create or update the corresponding RRPTR object
    
  Arguments:
    Hashref with RRADDR key/value pairs, plus:
      update_ptr - Update corresponding RRPTR object (default: ON)
  Returns:
    Number of rows updated or -1
  Example:
    $arecord->update(\%args)

=cut
sub update {
    my($self, $argv) = @_;
    $self->isa_object_method('update');
    $argv->{ipblock} = $self->_convert_ipblock($argv->{ipblock})
	if defined $argv->{ipblock};
    
    if ( defined $argv->{ttl} && length($argv->{ttl}) ){
	$argv->{ttl} = $self->ttl_from_text($argv->{ttl});
    }else{
	delete $argv->{ttl};
    }
    
    my $update_ptr = 1; # On by default
    if ( defined $argv->{update_ptr} && $argv->{update_ptr} == 0 ){
	$update_ptr = 0;
	delete $argv->{update_ptr};
    }

    my @res = $self->SUPER::update($argv);

    $self->update_rrptr() if $update_ptr;

    return @res;
}

############################################################################
=head2 delete - Delete object
    
    We override the delete method for extra functionality:
    - When removing an address record, most likely the RR (name)
    associated with it needs to be deleted too, unless it has
    more adddress records associated with it.
    - Delete any RRPTR(s) with corresponding ptrdname
    - Set ipblock status to 'Available' if needed
    - Remove any DHCP host scopes related to the IP if needed

  Arguments:
    no_change_status - Do not change IP status to available
  Returns:
    True if successful. 
  Example:
    $rraddr->delete;

=cut

sub delete {
    my ($self, $argv) = @_;
    $self->isa_object_method('delete');

    my $ipblock = $self->ipblock;
    my $rr = $self->rr;
    my $rr_name = $rr->get_label;
    $self->SUPER::delete();
    foreach my $ptr ( RRPTR->search(ipblock=>$ipblock, ptrdname=>$rr_name) ){
	$ptr->rr->delete();
    }
    
    if ( !$ipblock->a_records ){
	# This IP has no more A records

	# Remove any dhcp host scopes
	foreach my $host ( $ipblock->dhcp_scopes ){
	    $host->delete();
	}
	if ( !$ipblock->interface && !$argv->{no_change_status} ){
	    # Not an interface IP, so it should be available
	    # unless we're told not to touch it
	    $ipblock->update({status=>"Available"});
	}
    }

    # If RR has no more associated records or devices
    # it should be deleted
    # However, if it has MX records, check if they point
    # to something else, or just to itself. In the latter case
    # it must be deleted too.

    if ( !$rr->a_records && !$rr->ns_records && !$rr->devices ){
	my $deleteme = 1;
	if ( $rr->mx_records ) {
	    foreach my $mx ( $rr->mx_records ) {
		if ( $mx->exchange ne $rr->get_label ){
		    $deleteme = 0;
		    last;
		}
	    }
	}
	$rr->delete if $deleteme;
    }

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


############################################################################
=head2 update_rrptr - Update PTR record corresponding to a A/AAAA record

 When an RRADDR record is inserted or updated, we can automatically
 update the corresponding PTR record if told to do so

  Arguments:
    None
  Returns:
    True
  Examples:
    $rraddr->update_rrptr();

=cut
sub update_rrptr {
    my ($self) = @_;
    $self->isa_object_method('update_rrptr');

    my $rrptr;
    if ( !($rrptr = ($self->ipblock->ptr_records)[0]) ){
	if ( my $rev_zone = $self->ipblock->reverse_zone() ){
	    # Notice that we don't pass the rr field because
	    # the RRPTR class can figure that out.
	    $rrptr = RRPTR->insert({ptrdname => $self->rr->get_label, 
				    ipblock  => $self->ipblock, 
				    zone     => $rev_zone,
				    ttl      => $self->ttl});
	}else{
	    $logger->warn("Netdot::Model::RRADDR::update_rrptr: Ipblock: "
			  .$self->ipblock->get_label." reverse zone not found");
	}
    }
    return 1;
}



##################################################################
# Private methods
##################################################################


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


##################################################################
# check if IP is an address string
sub _convert_ipblock {
    my ($self, $ip) = @_;
    if (!(ref $ip) && ($ip =~ /\D/)) {
	$ip = $self->rem_lt_sp($ip);
	my $ipblock;
	unless ( $ipblock = Ipblock->search(address=>$ip)->first){
	    $ipblock = Ipblock->insert({address=>$ip, status=>'Static'});
	}
	# Make sure it's set to static
	$ipblock->update({status=>'Static'})
	    if ( $ipblock->status->name ne 'Static' );
	return $ipblock;
    } else {
	return $ip;
    }
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

