package Netdot::Model::Plugins::DeviceIpNamesFixed;

use base 'Netdot::Model';
use warnings;
use strict;

=head1 NAME

Netdot::Model::Plugins::DeviceIpNamesFixed

=head1 DESCRIPTION

    This plugin is used at Device discovery time to automate the creation
    and maintenance of DNS records for IP addresses that belong to devices.

    This particular plugin only sets the record to the device name

=head1 SYNOPSIS

    Netdot::Model::Plugins::DeviceIpNamesFromDNS->new();
    my $name = Netdot::Model::Plugins::DeviceIpNamesFromDNS->get_name($ipblock);

=cut

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
    bless $self, $class;
}

############################################################################

=head2 new - Class constructor

  Arguments:
    Ipblock object
  Returns:
    Name String 
  Examples:
    $plugin->get_name($ip);

=cut

sub get_name {
    my ($self, $ip) = @_;
    
    return $ip->interface->device->short_name;
}

1;

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


