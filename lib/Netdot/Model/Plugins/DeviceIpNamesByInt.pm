package Netdot::Model::Plugins::DeviceIpNamesByInt;

use base 'Netdot::Model';
use warnings;
use strict;


# Interface name to DNS abbreviation mapping

my %ABBR = ('Ethernet'        => 'e-',
	    'FastEthernet'    => 'fe-',
	    'GigabitEthernet' => 'ge-',
	    'Serial'          => 'ser-',
	    'Tunnel'          => 'tun-',
	    'POS'             => 'pos-',
	    'Loopback'        => 'lo-',
	    'Vlan'            => 'vl-',
	    );
    
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
sub get_name {
    my ($self, $ip) = @_;
    my $name = $ip->interface->name;
    
    foreach my $ab ( keys %ABBR ){
	$name =~ s/^$ab/$ABBR{$ab}/i;
    }
    $name =~ s/\/|\.|\s+/-/g;
    $name = lc( $name );
    
    if ( $ip->interface->ips > 1  ||  RR->search( name=>$name ) ){
	# Interface has more than one ip
	# or somehow this name is already used.
	# Append the ip address to the name to make it unique
	$name .= "-" . $ip->address;
    }
    # Append device name
    # Remove any possible prefixes added
    # e.g. loopback0.devicename -> devicename
    my $suffix = $ip->interface->device->short_name;
    $suffix =~ s/^.*\.(.*)/$1/;
    $name .= "." . $suffix ;
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
