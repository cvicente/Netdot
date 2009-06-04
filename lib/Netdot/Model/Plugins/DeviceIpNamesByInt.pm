package Netdot::Model::Plugins::DeviceIpNamesByInt;

use base 'Netdot::Model';
use warnings;
use strict;

# Interface name to DNS abbreviation mapping

my %ABBR = ('Ethernet'           => 'e-',
	    'FastEthernet'       => 'fe-',
	    'GigabitEthernet'    => 'ge-',
	    'TenGigabitEthernet' => 'tge-',
	    'Serial'             => 'ser-',
	    'Tunnel'             => 'tun-',
	    'POS'                => 'pos-',
	    'Loopback'           => 'lo-',
	    'Vlan'               => 'vl-',
	    "Adaptive Security Appliance '(.*)' interface"   => '$1',
	    "Cisco Pix Security Aappliance '(.*)' interface" => '$1',
	    );
    
my $logger = Netdot->log->get_logger('Netdot::Model::Device');

#Be sure to return 1
1;


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

    if ( int($ip->parent) && $ip->address_numeric == $ip->parent->address_numeric + 1 ){
	$logger->debug("Plugins::DeviceIpNamesByInt::get_name: $ipaddr is first in its subnet");
	if ( int($ip->parent->vlan) ){
	    # Make the name reflect the vlan number
	    my $vlan = $ip->parent->vlan;
	    $name = 'vl-'.$vlan->vid."-gw";
	}else{
	    # No vlan, so use the subnet address
	    $name = "net-".$ip->parent->address."-gw";
	    $name =~ s/\./-/g;
	}
    }else{
	# Use interface name
	$logger->debug("Plugins::DeviceIpNamesByInt::get_name: $ipaddr: Using Interface name");
	$name = $ip->interface->name;
    
	foreach my $pat ( sort keys %ABBR ){
	    my $conv = $ABBR{$pat};
	    if ( $name =~ /^$pat/ ){
		$logger->debug("Plugins::DeviceIpNamesByInt::get_name: $ipaddr: $name matches: $pat");
		if ( $conv eq '$1' ){
		    $conv = $1;
		}
		$name =~ s/$pat/$conv/i;
		last;
	    }else{
		$logger->debug("Plugins::DeviceIpNamesByInt::get_name: $ipaddr: '$name' does not match '$pat'");
	    }
	}
	$name =~ s/\/|\.|:|_|\s+/-/g;
	$name =~ s/\'//g;
	$name = lc( $name );

	# Append device name
	# Remove any possible prefixes added
	# e.g. loopback0.devicename -> devicename
	my $devname = $ip->interface->device->short_name;
	$devname =~ s/^.*\.(.*)/$1/;
	
	if ( (my @ips = $ip->interface->ips) > 1  ){
	    foreach my $i ( @ips ){
		next if $i->id == $ip->id;
		foreach my $a ( $i->arecords ){
		    if ( $a->rr->name eq "$name.$devname" ){
			$name .= "-".$ip->address;
			$name =~ s/\./-/g;
			last;
		    }
		}
	    }
	}
	$name .= ".".$devname ;
    }
    
    $logger->debug("Plugins::DeviceIpNamesByInt::get_name: $ipaddr: Generated name: $name");
    return $name;
}

