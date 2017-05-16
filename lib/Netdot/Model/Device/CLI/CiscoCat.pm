package Netdot::Model::Device::CLI::CiscoCat;

use base 'Netdot::Model::Device::CLI';
use warnings;
use strict;
use Net::Appliance::Session;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

# Some regular expressions
my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();
my $CISCO_MAC = '\w{4}\.\w{4}\.\w{4}';

=head1 NAME

Netdot::Model::Device::CLI::CiscoCat - Cisco IOS (Catalyst) Class

=head1 SYNOPSIS

 Overrides certain methods from the Device class. More Specifically, methods in 
 this class try to obtain forwarding tables via CLI instead of via SNMP.

=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut

############################################################################

=head2 get_arp - Fetch ARP tables

  Arguments:
    session - SNMP session (optional)
  Returns:
    Hashref
  Examples:
    my $cache = $self->get_arp(%args)
=cut

sub get_arp {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_arp');
    my $host = $self->fqdn;

    unless ( $self->collect_arp ){
	$logger->debug(sub{"Device::CiscoCat::_get_arp: $host excluded from ARP collection. Skipping"});
	return;
    }
    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::CiscoCat::_get_arp: $host in downtime. Skipping"});
	return;
    }

    # This will hold both ARP and v6 ND caches
    my %cache;

    ### v4 ARP
    my $start = time;
    my $arp_count = 0;
    my $arp_cache = $self->_get_arp_from_cli(host=>$host) ||
	$self->_get_arp_from_snmp(session=>$argv{session});
    foreach ( keys %$arp_cache ){
	$cache{'4'}{$_} = $arp_cache->{$_};
	$arp_count+= scalar(keys %{$arp_cache->{$_}})
    }
    my $end = time;
    $logger->info(sub{ sprintf("$host: ARP cache fetched. %s entries in %s", 
			       $arp_count, $self->sec2dhms($end-$start) ) });
    

    if ( $self->config->get('GET_IPV6_ND') ){
	### v6 ND
	$start = time;
	my $nd_count = 0;
	my $nd_cache  = $self->_get_v6_nd_from_cli(host=>$host) ||
	    $self->_get_v6_nd_from_snmp($argv{session});
	# Here we have to go one level deeper in order to
	# avoid losing the previous entries
	foreach ( keys %$nd_cache ){
	    foreach my $ip ( keys %{$nd_cache->{$_}} ){
		$cache{'6'}{$_}{$ip} = $nd_cache->{$_}->{$ip};
		$nd_count++;
	    }
	}
	$end = time;
	$logger->info(sub{ sprintf("$host: IPv6 ND cache fetched. %s entries in %s", 
				   $nd_count, $self->sec2dhms($end-$start) ) });
    }

    return \%cache;

}

############################################################################

=head2 get_fwt - Fetch forwarding tables

  Arguments:
    session - SNMP session (optional)    
  Returns:
    Hashref
  Examples:
    my $fwt = $self->get_fwt(%args)
=cut

sub get_fwt {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_fwt');
    my $host = $self->fqdn;
    my $fwt = {};

    unless ( $self->collect_fwt ){
	$logger->debug(sub{"Device::CiscoCat::get_fwt: $host excluded from FWT collection. Skipping"});
	return;
    }
    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::CiscoCat::get_fwt: $host in downtime. Skipping"});
	return;
    }

    my $start     = time;
    my $fwt_count = 0;
    
    # Try CLI, and then SNMP 
    $fwt = $self->_get_fwt_from_cli(host=>$host) ||
	$self->_get_fwt_from_snmp(session=>$argv{session});

    map { $fwt_count+= scalar(keys %{$fwt->{$_}}) } keys %$fwt;
    my $end = time;
    $logger->debug(sub{ sprintf("$host: FWT fetched. %s entries in %s", 
				$fwt_count, $self->sec2dhms($end-$start) ) });
   return $fwt;

}


############################################################################
#_get_arp_from_cli - Fetch ARP tables via CLI
#    
#   Arguments:
#     host
#   Returns:
#     Hash ref.
#   Examples:
#     $self->_get_arp_from_cli(host=>'foo');
#
sub _get_arp_from_cli {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_arp_from_cli');

    my $host = $argv{host};
    my $args = $self->_get_credentials(host=>$host);
    return unless ref($args) eq 'HASH';

    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show ip arp');

    my %cache;
    shift @output; # Ignore header line
    # Lines look like this:
    # Internet  10.82.250.129           -   0000.0c9f.f002  ARPA   GigabitEthernet0/3.2335
    foreach my $line ( @output ) {
	my ($iname, $ip, $mac, $intid);
	chomp($line);
	if ( $line =~ /^Internet\s+($IPV4)\s+[-\d]+\s+($CISCO_MAC)\s+ARPA\s+(\S+)/o ) {
	    $ip    = $1;
	    $mac   = $2;
	    $iname = $3;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoCat::_get_arp_from_cli: line did not match criteria: $line" });
	    next;
	}
	unless ( $ip && $mac && $iname ){
	    $logger->debug(sub{"Device::CiscoCat::_get_arp_from_cli: Missing information: $line" });
	    next;
	}
	$cache{$iname}{$ip} = $mac;
    }
    return $self->_validate_arp(\%cache, 4);
}

############################################################################
#_get_v6_nd_from_cli - Fetch ARP tables via CLI
#    
#   Arguments:
#     host
#   Returns:
#     Hash ref.
#   Examples:
#     $self->_get_v6_nd_from_cli(host=>'foo');
#
sub _get_v6_nd_from_cli {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_v6_nd_from_cli');

    my $host = $argv{host};
    my $args = $self->_get_credentials(host=>$host);
    return unless ref($args) eq 'HASH';

    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show ipv6 neighbors');
    shift @output; # Ignore header line
    my %cache;
    foreach my $line ( @output ) {
	my ($ip, $mac, $iname);
	chomp($line);
	# Lines look like this:
	# FE80::219:E200:3B7:1920                     0 0019.e2b7.1920  REACH Gi0/2.3
	if ( $line =~ /^($IPV6)\s+\d+\s+($CISCO_MAC)\s+\S+\s+(\S+)/o ) {
	    $ip    = $1;
	    $mac   = $2;
	    $iname = $3;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoCat::_get_v6_nd_from_cli: line did not match criteria: $line" });
	    next;
	}
	unless ( $iname && $ip && $mac ){
	    $logger->debug(sub{"Device::CiscoCat::_get_v6_nd_from_cli: Missing information: $line"});
	    next;
	}
	$cache{$iname}{$ip} = $mac;
    }
    return $self->_validate_arp(\%cache, 6);
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
    return unless ref($args) eq 'HASH';

    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show mac address-table dynamic');

    # MAP interface names to IDs
    my %int_names;
    foreach my $int ( $self->interfaces ){
	my $name = $self->_reduce_iname($int->name);
	$int_names{$name} = $int->id;
    }

    my ($iname, $mac, $intid);
    my %fwt;
    
    # Output look like this:
    # Vlan    Mac Address       Type        Ports
    # ----    -----------       --------    -----
    #	88    0000.487d.c465    DYNAMIC     Gi0/2
    #	88    0000.5a72.59b4    DYNAMIC     Gi0/2

    foreach my $line ( @output ) {
	chomp($line);
	if ( $line =~ /^.*($CISCO_MAC)\s+DYNAMIC\s+(\S+)\s*$/o ) {
	    $mac   = $1;
	    $iname = $2;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoCat::_get_fwt_from_cli: ".
				   "line did not match criteria: '$line'" });
	    next;
	}
	$iname = $self->_reduce_iname($iname);
	my $intid = $int_names{$iname};

	unless ( $intid ) {
	    $logger->warn("Device::CLI::CiscoCat::_get_fwt_from_cli: ".
			  "$host: Could not match $iname to any interface names");
	    next;
	}
	eval {
	    $mac = PhysAddr->validate($mac);
	};
	if ( my $e = $@ ){
	    $logger->debug(sub{"Device::CLI::CiscoCat::_get_fwt_from_cli: ".
				   "$host: Invalid MAC: $e" });
	    next;
	}	
	# Store in hash
	$fwt{$intid}{$mac} = 1;
	$logger->debug(sub{"Device::CLI::CiscoCat::_get_fwt_from_cli: ".
			       "$host: $iname -> $mac" });
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

