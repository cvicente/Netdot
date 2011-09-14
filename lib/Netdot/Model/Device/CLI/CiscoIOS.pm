package Netdot::Model::Device::CLI::CiscoIOS;

use base 'Netdot::Model::Device::CLI';
use warnings;
use strict;
use Net::Appliance::Session;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::Device::CLI::CiscoIOS - Cisco IOS Class

=head1 SYNOPSIS

 Overrides certain methods from the Device class

=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut

############################################################################
=head2 get_arp - Fetch ARP tables

  Arguments:
    None
  Returns:
    Hashref
  Examples:
    my $cache = $self->get_arp(%args)
=cut
sub get_arp {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_arp');
    my $host = $self->fqdn;
    return $self->_get_arp_from_cli(host=>$host);
}

############################################################################
=head2 get_fwt - Fetch forwarding tables

  Arguments:
    None
  Returns:
    Hashref
  Examples:
    my $fwt = $self->get_fwt(%args)
=cut
sub get_fwt {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_fwt');
    my $host = $self->fqdn;
    return $self->_get_fwt_from_cli(host=>$host);
}


############################################################################
#_get_arp_from_cli - Fetch ARP tables via CLI
#
#    
#   Arguments:
#     host
#   Returns:
#     Hash ref.
#   Examples:
#     $self->_get_arp_from_cli();
#
#
sub _get_arp_from_cli {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_arp_from_cli');

    my $host = $argv{host};
    my $args = $self->_get_credentials(host=>$host);

    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show ip arp');

    # MAP interface names to IDs
    # Get all interface IPs for subnet validation
    my %int_names;
    my %devsubnets;
    foreach my $int ( $self->interfaces ){
	my $name = $self->_reduce_iname($int->name);
	$int_names{$name} = $int->id;
	foreach my $ip ( $int->ips ){
	    push @{$devsubnets{$int->id}}, $ip->parent->_netaddr 
		if $ip->parent;
	}
    }

    my %cache;
    my ($iname, $ip, $mac, $intid);
    shift @output; # Ignore header line
    foreach my $line ( @output ) {
	chomp($line);
	if ( $line =~ /^Internet\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+[-\d]+\s+(\w{4}\.\w{4}\.\w{4})\s+ARPA\s+(\S+)/ ) {
	    $ip    = $1;
	    $mac   = $2;
	    $iname = $3;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoIOS::_get_arp_from_cli: line did not match criteria: $line" });
	    next;
	}
	$iname = $self->_reduce_iname($iname);
	my $intid = $int_names{$iname};

	unless ( $intid ) {
	    $logger->warn("Device::CLI::CiscoIOS::_get_arp_from_cli: $host: Could not match $iname to any interface name");
	    next;
	}
	
	my $validmac = PhysAddr->validate($mac); 
	if ( $validmac ){
	    $mac = $validmac;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoIOS::_get_arp_from_cli: $host: Invalid MAC: $mac" });
	    next;
	}	

	if ( Netdot->config->get('IGNORE_IPS_FROM_ARP_NOT_WITHIN_SUBNET') ){
	    # Don't accept entry if ip is not within this interface's subnets
	    my $invalid_subnet = 1;
	    foreach my $nsub ( @{$devsubnets{$intid}} ){
		my $nip = NetAddr::IP->new($ip) 
		    || $self->throw_fatal(sprintf("Cannot create NetAddr::IP object from %s", $ip));
		if ( $nip->within($nsub) ){
		    $invalid_subnet = 0;
		    last;
		}else{
		    $logger->debug(sub{sprintf("Device::CLI::CiscoIOS::_get_arp_from_cli: $host: IP $ip not within %s", 
					       $nsub->cidr)});
		}
	    }
	    if ( $invalid_subnet ){
		$logger->debug(sub{"Device::CLI::CiscoIOS::_get_arp_from_cli: $host: IP $ip not within interface $iname subnets"});
		next;
	    }
	}

	# Store in hash
	$cache{$intid}{$ip} = $mac;
	$logger->debug(sub{"Device::CLI::CiscoIOS::_get_arp_from_cli: $host: $iname -> $ip -> $mac" });
    }
    
    return \%cache;
}



############################################################################
#_get_fwt_from_cli - Fetch forwarding tables via CLI
#
#    
#   Arguments:
#     host
#   Returns:
#     Hash ref.
#    
#   Examples:
#     $self->_get_fwt_from_cli();
#
#
sub _get_fwt_from_cli {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_fwt_from_cli');

    my $host = $argv{host};
    my $args = $self->_get_credentials(host=>$host);
    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show mac-address-table dynamic');

    # MAP interface names to IDs
    my %int_names;
    foreach my $int ( $self->interfaces ){
	my $name = $self->_reduce_iname($int->name);
	$int_names{$name} = $int->id;
    }

    my ($iname, $mac, $intid);
    my %fwt;
    
    # Output look like this:
    #  vlan   mac address     type    learn     age              ports
    # ------+----------------+--------+-----+----------+--------------------------
    #   128  0024.b20e.fe0f   dynamic  Yes        255   Gi9/22

    foreach my $line ( @output ) {
	chomp($line);
	if ( $line =~ /^\*?\s+.*\s+(\w{4}\.\w{4}\.\w{4})\s+dynamic\s+\S+\s+\S+\s+(\S+)\s+$/ ) {
	    $mac   = $1;
	    $iname = $2;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoIOS::_get_fwt_from_cli: line did not match criteria: $line" });
	    next;
	}
	$iname = $self->_reduce_iname($iname);
	my $intid = $int_names{$iname};

	unless ( $intid ) {
	    $logger->warn("Device::CLI::CiscoIOS::_get_fwt_from_cli: $host: Could not match $iname to any interface names");
	    next;
	}
	
	my $validmac = PhysAddr->validate($mac);
	if ( $validmac ){
	    $mac = $validmac;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoIOS::_get_fwt_from_cli: $host: Invalid MAC: $mac" });
	    next;
	}	

	# Store in hash
	$fwt{$intid}{$mac} = 1;
	$logger->debug(sub{"Device::CLI::CiscoIOS::_get_fwt_from_cli: $host: $iname -> $mac" });
    }
    
    return \%fwt;
}



############################################################################
# _reduce_iname
#  Convert "GigabitEthernet0/3 into "Gi0/3" to match the different formats
#
# Arguments: 
#   string
# Returns:
#   string
#
sub _reduce_iname{
    my ($self, $name) = @_;
    return unless $name;
    $name =~ s/^(\w{2})\S*?([\d\/]+).*/$1$2/;
    return $name;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 University of Oregon, all rights reserved.

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

