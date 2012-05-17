package Netdot::Model::Device::CLI::CiscoFW;

use base 'Netdot::Model::Device::CLI';
use warnings;
use strict;
use Net::Appliance::Session;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::Device::CLI::CiscoFW - Cisco Firewall Class

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

    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show arp', personality=>'pixos');
    
    # MAP interface names to IDs
    # Get all interface IPs for subnet validation
    my %int_names;
    my %devsubnets;
    foreach my $int ( $self->interfaces ){
	$int_names{$int->name} = $int->id;
	foreach my $ip ( $int->ips ){
	    push @{$devsubnets{$int->id}}, $ip->parent->netaddr 
		if $ip->parent;
	}
    }

    my %cache;
    my ($iname, $ip, $mac, $intid);
    foreach my $line ( @output ) {
	if ( $line =~ /^\s+(\S+)\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s(\w{4}\.\w{4}\.\w{4}).*$/ ) {
	    $iname = $1;
	    $ip    = $2;
	    $mac   = $3;
	}elsif ( $line =~ /^\s+(\S+)\s([\w\._-]+)\s(\w{4}\.\w{4}\.\w{4}).*$/ ){
	    # The 'dns domain-lookup outside' option causes outside-facing entries to be reported as hostnames
	    $iname       = $1;
	    my $hostname = $2;
	    $mac         = $3;
	    # Notice we only care about v4 here
	    if ( my @ips = Netdot->dns->resolve_name($hostname, {v4_only=>1}) ){
		$ip = $ips[0];
	    }else{
		$logger->debug(sub{"Device::CLI::CiscoFW::_get_arp_from_cli: Cannot resolve $hostname" });
		next;
	    }
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoFW::_get_arp_from_cli: line did not match criteria: $line" });
	    next;
	}

	# The failover interface appears in the arp output but it's not in the IF-MIB output
	next if ($iname eq 'failover');

	# Interface names from SNMP are stupidly long and don't match the short name in the ARP output
	# so we have to do some pattern matching. Of course, this will break when they
	# decide to change the string.
	foreach my $name ( keys %int_names ){
	    if ( $name =~ /Appliance \'$iname\' interface/ ){
		$intid = $int_names{$name};
		last;
	    }
	}
	unless ( $intid ) {
	    $logger->warn("Device::CLI::CiscoFW::_get_arp_from_cli: $host: Could not match $iname to any interface name");
	    next;
	}
	
	my $validmac = PhysAddr->validate($mac); 
	if ( $validmac ){
	    $mac = $validmac;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoFW::_get_arp_from_cli: $host: Invalid MAC: $mac" });
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
		    $logger->debug(sub{sprintf("Device::CLI::CiscoFW::_get_arp_from_cli: $host: IP $ip not within %s", 
					       $nsub->cidr)});
		}
	    }
	    if ( $invalid_subnet ){
		$logger->debug(sub{"Device::CLI::CiscoFW::_get_arp_from_cli: $host: IP $ip not within interface $iname subnets"});
		next;
	    }
	}

	# Store in hash
	$cache{$intid}{$ip} = $mac;
	$logger->debug(sub{"Device::CLI::CiscoFW::_get_arp_from_cli: $host: $iname -> $ip -> $mac" });
    }
    
    return \%cache;
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

