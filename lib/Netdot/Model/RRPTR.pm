package Netdot::Model::RRPTR;

use base 'Netdot::Model';
use warnings;
use strict;
use Scalar::Util qw(blessed);

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRPTR - DNS PTR record Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

##################################################################
=head2 insert

    Override the base method to:
      - Validate TTL
      - If not given, figure out the name of the record, using the 
        zone and the IP address
      - Check for conflicting record types
    
  Arguments:
    None
  Returns:
    RRPTR object
  Examples:

=cut
sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal("Missing required arguments")
	unless ( $argv->{ptrdname} && $argv->{ipblock} );
    
    # Convert ipblock into object
    $argv->{ipblock} = $class->_convert_ipblock($argv->{ipblock});
    my $ipb = $argv->{ipblock};

    my $rr;
    if ( !defined $argv->{rr} ){
	$class->throw_fatal("Figuring out the rr field requires passing zone")
	    unless ( $argv->{zone} );

	$logger->debug("Netdot::Model::RRPTR: Figuring out owner for ".$ipb->get_label);

	my $zone = blessed($argv->{zone}) ? $argv->{zone} : Zone->retrieve($argv->{zone});
	unless ( $zone->name =~ /(?:\.in-addr)|(?:\.ip6)\.arpa$/ ){
	    $class->throw_user(sprintf("Zone %s is not a reverse zone", $zone->name));
	}
	my $name = $class->get_name(ipblock=>$ipb);
	$rr = RR->find_or_create({zone=>$zone, name=>$name});
	$logger->debug("Netdot::Model::RRPTR: Created owner RR for IP: ".
		       $ipb->get_label." as: ".$rr->get_label);
	$argv->{rr} = $rr;
    }

    $rr = blessed($argv->{rr})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;
    
    my %linksfrom = RR->meta_data->get_links_from;
    foreach my $i ( keys %linksfrom ){
	if ( $rr->$i ){
	    next if ( $i eq 'ptr_records' || $i eq 'txt_records' || $i eq 'loc_records' );
	    $class->throw_user($rr->name.": Cannot add PTR records when other conflicting types exist.");
	}
    }

    # Sanitize TTL
    if ( defined $argv->{ttl} && length($argv->{ttl}) ){
	$argv->{ttl} = $class->ttl_from_text($argv->{ttl});
    }else{
	$argv->{ttl} = $argv->{rr}->zone->default_ttl;
    }

    $class->_sanitize_ptrdname($argv);

    delete $argv->{zone};
    return $class->SUPER::insert($argv);
    
}

##################################################################
=head2 get_name - Figure out record name given IP

  Arguments:
    Hash containing:
    ipblock - ipblock object
  Returns:
    String
  Examples:
    my $name = RRPTR->get_name(ipblock=>$ipb);
=cut
sub get_name {
    my ($class, %argv) = @_;

    my $ipblock = $argv{ipblock};
    unless ( $ipblock ){
	$class->throw_fatal("RRPTR::get_name: Missing required arguments");
    }

      my $name;
      if ( $ipblock->version eq '4' ){
          $name = join('.', reverse(split(/\./, $ipblock->address)), 'in-addr.arpa');
      }elsif ( $ipblock->version eq '6' ){
          $name = $ipblock->full_address;
          $name =~ s/://g;
          $name = join('.', reverse(split(//, $name)), 'ip6.arpa');
      }else {
          $class->throw_fatal("RRPTR::get_name: Unknown IP version");
      }
      return $name;
}

=head1 INSTANCE METHODS
=cut

############################################################################
=head2 update

    We override the base method to:
     - Validate TTL
    
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

    if ( exists $argv->{ipblock} ){
	unless ( $argv->{ipblock} ){
	    # Make sure it is not null or 0 if passed
	    $self->throw_user("IP cannot be null");
	}
	# Convert ipblock into object
	$argv->{ipblock} = $self->_convert_ipblock($argv->{ipblock});
    }

    if ( defined $argv->{ttl} && length($argv->{ttl}) ){
	$argv->{ttl} = $self->ttl_from_text($argv->{ttl});
    }else{
	# keep what we have
	delete $argv->{ttl};
    }    

    $self->_sanitize_ptrdname($argv);
    
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


############################################################################
# PRIVATE METHODS
############################################################################

############################################################################
# _sanitize_ptrdname
#
#  Args: 
#    hashref
#  Returns: 
#    True, or throws exception if validation fails
#  Examples:
#    $class->_sanitize_ptrdname($argv);
#
sub _sanitize_ptrdname {
    my ($self, $argv) = @_;
    
    # Sanitize ptrdname
    if ( exists $argv->{ptrdname} ){
	if ( length($argv->{ptrdname}) < 1 || length($argv->{ptrdname}) > 255 ){
	    $self->throw_user("Invalid domain name size");
	}
	$argv->{ptrdname} =~ s/\s+//g;  # remove spaces
	$argv->{ptrdname} = lc($argv->{ptrdname}); # lowercase
    }
    1;
}

##################################################################
# check if IP is an address string, if so then convert into object
sub _convert_ipblock {
    my ($self, $ip) = @_;

    if ( blessed($ip) ){
	return $ip;
    }elsif ( $ip =~ /\D/ ){
	# value has non-digits
	if ( my $ipblock = Ipblock->search(address=>$ip)->first ){
	    return $ipblock;
	}else {
	    return Ipblock->insert({address=>$ip, status=>'Static'});
	}
    }else{
	# Value must be an integer, so it might be an id
	if ( my $ipblock = Ipblock->retrieve($ip) ) {
	    return $ipblock;
	}else{
	    $self->throw_user("Invalid ipblock value: $ip");
	}
    }
}

##################################################################
sub _net_dns {
    my $self = shift;

    my $ndo = Net::DNS::RR->new(
	name     => $self->rr->get_label,
	ttl      => $self->ttl,
	class    => 'IN',
	type     => 'PTR',
	ptrdname => $self->ptrdname,
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

