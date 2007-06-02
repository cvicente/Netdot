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

