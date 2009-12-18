package Netdot::Model::Plugins::IPRangeDNS;

use base 'Netdot::Model';
use warnings;
use strict;


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

    It figures out the host octets and adds the given prefix and suffix strings
    For example, given the IP: 192.168.10.20
    it will create A && PTR records like "<prefix>10-20<suffix>.my-given-domain"

  Arguments:
    prefix  -  String to prepend to host part of IP address
    suffix  -  String to append to host part of IP address
    ipstart -  First IP in range
    ipend   -  Last IP in range
    fzone   -  Forward zone (for A records)
    rzone   -  Reverse zone (for PTR records)
  Returns:
    Array of RRPTR and RRADDR objects
  Examples:

    From Ipblock class:

    $range_dns_plugin->generate_records(
       name_prefix=>$argv{name_prefix}, 
       name_suffix=>$argv{name_suffix}, 
       start=>$ipstart, end=>$ipend, 
       fzone=>$fzone, rzone=>$rzone );

=cut 
sub generate_records {
    my ($self, %argv) = @_;
    my($prefix, $suffix, $ipstart, $ipend, $fzone, $rzone) 
	= @argv{'prefix', 'suffix', 'start', 'end', 'fzone', 'rzone'};

    $self->throw_fatal("Missing required arguments")
	unless ( $ipstart && $ipend && $fzone && $rzone );

    my @rrs;
    my $zname = $rzone->name;
    $zname =~ s/(.*)\.in-addr.arpa/$1/ || 
	$zname =~ s/(.*)\.ip6.arpa/$1/ ||
	$zname =~ s/(.*)\.ip6.int/$1/ ;

    my ($name, $ptrdname);
    for ( my $i=$ipstart->numeric; $i<=$ipend->numeric; $i++ ){
	my $ip = NetAddr::IP->new($i);
	if ( $ip->version eq '4' ){
	    my @octs = split(/\./, $zname);
	    my $p = join '.', reverse @octs;
	    $name = $ip->addr;
	    $name =~ s/$p\.//;
	    $name =~ s/\./-/;
	    $name = $prefix.$name if ( defined $prefix );
	    $name .= $suffix if ( defined $suffix );
	    $ptrdname = "$name.".$fzone->name;

	    my $ipb = Ipblock->search(address=>$ip->addr)->first;

	    # We'll wipe out whatever records were there
	    # We do it after we add the names to avoid the IPs
	    # being set as availble
	    my @to_delete;
	    foreach my $r ( $ipb->ptr_records ){
		push @to_delete, $r;
	    }
	    foreach my $r ( $ipb->arecords ){
		push @to_delete, $r;
	    }
	    
	    my $ptr = Netdot::Model::RRPTR->insert({ptrdname => $ptrdname, 
						    ipblock  => $ipb, 
						    zone     => $rzone});
	    push @rrs, $ptr;
	    
	    my $rraddr = Netdot::Model::RR->insert({type    => 'A',
						    name    => $name, 
						    ipblock => $ipb, 
						    zone    => $fzone});
	    push @rrs, $rraddr;

	    map { $_->delete } @to_delete;
	    
	}elsif ( $ip->version eq '6' ){
	    # Pending
	}

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
