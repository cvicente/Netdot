package Netdot::Model::Plugins::IPRangeDNS;

use base 'Netdot::Model';
use warnings;
use strict;
use Math::BigInt;


############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Plugin object
  Examples:
    
=cut
sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{logger} = Netdot->log->get_logger('Netdot::Model::Ipblock');
    bless $self, $class;
}

############################################################################
=head2 generate_records - Generates A/AAAA & PTR records

    Generates label based on IP address and adds the given prefix and suffix strings
    For example, given the IP: 192.168.10.20
    it will create A/AAAA && PTR records like "<prefix>192-168-10-20<suffix>.my-given-domain"

  Arguments:
    prefix  -  String to prepend to host part of IP address
    suffix  -  String to append to host part of IP address
    ip_list -  Arrayref of Ipblock objects
    fzone   -  Forward zone (for A records)
  Returns:
    Array of RRADDR objects
  Examples:

    From Ipblock class:

    $range_dns_plugin->generate_records(
       name_prefix=>$argv{name_prefix}, 
       name_suffix=>$argv{name_suffix}, 
       start=>$ipstart, end=>$ipend, 
       fzone=>$fzone );

=cut 
sub generate_records {
    my ($self, %argv) = @_;
    my($prefix, $suffix, $ip_list, $fzone) 
	= @argv{'prefix', 'suffix', 'ip_list', 'fzone'};

    $self->throw_fatal("Missing required argument: ip_list")
	unless ( $ip_list );

    $self->throw_fatal("ip_list must be an arrayref")
	unless ( ref($ip_list) eq 'ARRAY' );

    $self->throw_user("Missing required argument: forward zone")
	unless ( $fzone );

    my @rrs;

    my ($name, $ptrdname);
    my $version = $ip_list->[0]->version;
   
    foreach my $ipb ( @$ip_list ){
	if ( $version == 4 ){
	    $name = $ipb->address;
	    $name =~ s/\./-/g;

	}elsif ( $version == 6 ){
	    $name = $ipb->full_address;
	    $name =~ s/:/-/g;
	    $name =~ s/0{4}/0/g;
	}
	$name = $prefix.$name if ( defined $prefix );
	$name .= $suffix if ( defined $suffix );
	$ptrdname = "$name.".$fzone->name;
	
	foreach my $r ( $ipb->arecords ){
	    $r->delete({no_change_status=>1});
	}

	if ( my $arpa_zone = $ipb->reverse_zone() ){
	    my $ptr = Netdot::Model::RRPTR->insert({ptrdname => $ptrdname, 
						    ipblock  => $ipb, 
						    zone     => $arpa_zone});
	    push @rrs, $ptr;
	}
	
	my $rraddr = Netdot::Model::RR->insert({type    => 'A',
						name    => $name, 
						ipblock => $ipb, 
						zone    => $fzone});
	push @rrs, $rraddr;
    }
    return \@rrs;
}

=head1 AUTHORS

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

# Make sure to return 1
1;
