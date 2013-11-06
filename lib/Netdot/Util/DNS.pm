package Netdot::Util::DNS;

use base 'Netdot::Util';
use warnings;
use strict;
use Socket;
use Socket6;

=head1 NAME

Netdot::Util::DNS - DNS utilities class

=head1 SYNOPSIS

    my $dns = Netdot::Util::DNS->new();
    my $ip  = ($dns->resolve_name($host))[0];

=head1 CLASS METHODS
=cut

############################################################################

=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Util::DNS object
  Examples:
    my $dns = Netdot::Util::DNS->new();
=cut

sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{_logger} = Netdot->log->get_logger('Netdot::Util');
    $self->{_IPV4}   = Netdot->get_ipv4_regex();
    $self->{_IPV6}   = Netdot->get_ipv6_regex();
    
    bless $self, $class;
}

############################################################################

=head2 resolve_name - Resolve name to IPv4 or IPv6 address(es)

  Arguments:
    name        -  string
    opts        -  hashref with following keys:
       v4_only  -  flag (1 or 0).  Return only v4 addresses.
       v6_only  -  flag (1 or 0).  Return only v6 addresses.
  Returns:
    Array of IP addresses (strings)
  Example:
    my @addrs = Netdot::Util::DNS->resolve_name($name)
   
=cut 

sub resolve_name {
    my ($self, $name, $opts) = @_;
    return unless $name;

    my @addresses;

    my @res = getaddrinfo($name, 0, AF_UNSPEC, SOCK_STREAM);
    unless ( scalar(@res) >= 5 ){
	$self->{_logger}->warn("Could not resolve $name: ".$res[0].".\n");
	return;
    }

    while ( scalar(@res) ) {
        my ($family, $socktype, $proto, $saddr, $canonname, @res) = splice(@res, 0, 5);
	next unless ($saddr && $family);
	my ($port, $addr) = ($family == AF_INET6) ?
	    unpack_sockaddr_in6($saddr) : sockaddr_in($saddr);
	my $ip_address = inet_ntop($family, $addr);
	next if ( $opts->{v4_only} && $ip_address =~ /^$self->{_IPV6}$/ );
	next if ( $opts->{v6_only} && $ip_address =~ /^$self->{_IPV4}$/ );
        push @addresses, $ip_address;
    }
    
    return @addresses;
}


############################################################################

=head2 resolve_ip - Resolve ip (v4 or v6) adress to name

  Arguments:
    IP address string
  Returns:
    Name string or undef
  Example:
    my $name = Netdot::Util::DNS->resolve_ip($ip);

=cut 

sub resolve_ip {
    my ($self, $ip) = @_;
    return unless $ip;
    my $name;
    if ( $ip =~ /^$self->{_IPV4}$/ ){
	my $iaddr = inet_aton($ip);
	unless ( $iaddr ){
	    $self->{_logger}->error("Netdot::Util::DNS::resolve_ip: Can't convert $ip to binary");
	    return;
	}
	unless ($name = gethostbyaddr($iaddr, AF_INET)){
	    $self->{_logger}->error("Netdot::Util::DNS::resolve_ip: Can't resolve $ip");
	    return;
	}
    }elsif ( $ip =~ /^$self->{_IPV6}$/ ){
	my $saddr = pack_sockaddr_in6(0,inet_pton(AF_INET6, $ip));
	unless ( $saddr ){
	    $self->{_logger}->error("Netdot::Util::DNS::resolve_ip: Can't convert $ip to binary");
	    return;
	}
	unless ( ($name, undef) = getnameinfo($saddr) ){
	    $self->{_logger}->error("Netdot::Util::DNS::resolve_ip: Can't resolve $ip");
	    return;
	}
    }else{
	$self->{_logger}->error("Netdot::Util::DNS::resolve_ip: Unrecognized address: $ip");
	return;
    }
    return $name;
}

############################################################################

=head2 resolve_any - Resolve ip or name

  Arguments:
    IP or hostname
  Returns:
    Array with ip, name
  Example:
    my ($ip, $name) = Netdot::Util::DNS->resolve_any('blah');

=cut 

sub resolve_any {
    my ($self, $host) = @_;
    return unless $host;
    my $IPV4 = $self->{_IPV4};
    my $IPV6 = $self->{_IPV6};
    my ($ip, $name);
    if ( $host =~ /^($IPV4)|($IPV6)$/ ){
	# looks like an IP address
	$ip   = $host;
	$name = $self->resolve_ip($ip) || "";
    }else{
	# looks like a name
	$name = $host;
	$ip   = ($self->resolve_name($name))[0];
    }
    return ($ip, $name);
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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

