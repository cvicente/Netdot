package Netdot::Model::Plugins::DeviceIpNamesByInt;

use base 'Netdot::Model';
use warnings;
use strict;

# Interface name to DNS abbreviation mapping

my %ABBR = ('Ethernet'           => 'e-',
	    'FastEthernet'       => 'fe-',
	    'GigabitEthernet'    => 'ge-',
	    'TenGigabitEthernet' => 'xe-',
	    'Serial'             => 'ser-',
	    'Tunnel'             => 'tun-',
	    'POS'                => 'pos-',
	    'Loopback'           => 'lo-',
	    'Vlan'               => 'vl-',
	    "Adaptive Security Appliance '(.*)' interface"   => '$1',
	    "Cisco Pix Security Aappliance '(.*)' interface" => '$1',
	    );
    
my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::Plugins::DeviceIpNamesByInt;

=head1 DESCRIPTION

    This plugin is used at Device discovery time to automate the creation
    and maintenance of DNS records for IP addresses that belong to devices.

    This particular plugin uses some rules to derive the DNS name from
    the VLAN, the subnet, or the Device's interface name.

=head1 SYNOPSIS

    Netdot::Model::Plugins::DeviceIpNamesByInt->new();
    my $name = Netdot::Model::Plugins::DeviceIpNamesByInt->get_name($ipblock);

=head1 METHODS

=cut
############################################################################

=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Plugin object
    
=cut

sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    bless $self, $class;
}

############################################################################

=head2 get_name - Return name for given IP

  Arguments:
    Ipblock object
  Returns:
    String
    
=cut

sub get_name {
    my ($self, $ip) = @_;
    my $name;
    my $ipaddr = $ip->address;

    if ( $ip->parent && $ip->address_numeric == $ip->parent->address_numeric + 1 ){
	$logger->debug("Plugins::DeviceIpNamesByInt::get_name: $ipaddr is first in its subnet");
	if ( $ip->parent->vlan ){
	    # Make the name reflect the vlan number
	    my $vlan = $ip->parent->vlan;
	    $name = 'vl-'.$vlan->vid."-gw";
	}else{
	    $name = $self->get_name_from_interface($ip);
	}
    }else{
	$name = $self->get_name_from_interface($ip);
    }
    $logger->debug("Plugins::DeviceIpNamesByInt::get_name: $ipaddr: Generated name: $name");
    return $name;
}

############################################################################

=head2 get_name_from_interface

  Arguments:
    Ipblock object
  Returns:
    String
    
=cut

sub get_name_from_interface {
    my ($self, $ip) = @_;
    my $ipaddr = $ip->address;
    my $name = $ip->interface->name;
    return unless $name;
    $logger->debug("Plugins::DeviceIpNamesByInt::get_name_from_interface: $ipaddr: Using Interface name");
    
    foreach my $pat ( sort keys %ABBR ){
	my $conv = $ABBR{$pat};
	if ( $name =~ /^$pat/ ){
	    $logger->debug("Plugins::DeviceIpNamesByInt::get_name_from_interface: $ipaddr: $name matches: $pat");
	    if ( $conv eq '$1' ){
		$conv = $1;
	    }
	    $name =~ s/$pat/$conv/i;
	    last;
	}
    }
    # Make sub-interface number resemble a sub-domain
    if ( $name =~ s/\.(\d+)$// ){
	$name = $1.'.'.$name;
    }elsif ( $name =~ s/:(\d+)$// ){
	$name = $1.'.'.$name;
    }
    $name = lc( $name );
    # Remove quotes
    $name =~ s/\'//g;
    # Substitute invalid DNS chars with dashes
    $name =~ s/[^a-z0-9\.]/-/og;
    # Only one dash "-" in a row
    $name =~ s/[-]+/-/og;
    # Remove dashes from start and end
    $name =~ s/^-+|-+$//og;
    # No dash before dot
    $name =~ s/-\./\./g;
    
    # Append device name
    my $devname = $ip->interface->device->short_name;
    $name .= ".".$devname ;

    return $name;
}


=head1 AUTHORS

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

# Make sure to return 1
1;
