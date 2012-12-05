package Netdot::Model::Device::CLI::CiscoFW;

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

Netdot::Model::Device::CLI::CiscoFW - Cisco Firewall Class

=head1 SYNOPSIS

 Overrides certain methods from the Device class. Specifically, methods in 
 this class try to obtain forwarding tables and ARP/ND caches via CLI
 instead of via SNMP.

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
	$logger->debug(sub{"Device::CiscoFW::_get_arp: $host excluded from ARP collection. Skipping"});
	return;
    }
    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::CiscoFW::_get_arp: $host in downtime. Skipping"});
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
    
    my %cache;
    my ($iname, $ip, $mac, $intid);
    # Lines look like this:
    # outside 10.10.47.146 0026.9809.f642 251
    foreach my $line ( @output ) {
	if ( $line =~ /^\s*(\S+)\s($IPV4)\s($CISCO_MAC).*$/ ) {
	    $iname = $1;
	    $ip    = $2;
	    $mac   = $3;
	}elsif ( $line =~ /^\s*(\S+)\s([\w\._-]+)\s($CISCO_MAC).*$/ ){
	    # The 'dns domain-lookup outside' option causes outside-facing entries 
	    # to be reported as hostnames
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
	    $logger->debug(sub{"Device::CLI::CiscoFW::_get_arp_from_cli: line did not match criteria: ".
				   "$line" });
	    next;
	}

	# The failover interface appears in the arp output but it's not in the IF-MIB output
	next if ($iname eq 'failover');

	unless ( $ip && $mac && $iname ){
	    $logger->debug(sub{"Device::CiscoFW::_get_arp_from_cli: Missing information: $line" });
	    next;
	}

	# Store in hash
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

    my @output = $self->_cli_cmd(%$args, host=>$host, cmd=>'show ipv6 neighbor', personality=>'pixos');
    shift @output; # Ignore header line
    my %cache;
    foreach my $line ( @output ) {
	my ($ip, $mac, $iname);
	chomp($line);
	# Lines look like this:
	# fe80::224:e8ff:fe51:6abe                    0 0024.e851.6abe  REACH dmz
	if ( $line =~ /^($IPV6)\s+\d+\s+($CISCO_MAC)\s+\S+\s+(\S+)/o ) {
	    $ip    = $1;
	    $mac   = $2;
	    $iname = $3;
	}else{
	    $logger->debug(sub{"Device::CLI::CiscoFW::_get_v6_nd_from_cli: ".
				   "line did not match criteria: $line" });
	    next;
	}
	unless ( $iname && $ip && $mac ){
	    $logger->debug(sub{"Device::CiscoFW::_get_v6_nd_from_cli: Missing information: $line"});
	    next;
	}
	$cache{$iname}{$ip} = $mac;
    }
    return $self->_validate_arp(\%cache, 6);
}


############################################################################
# _reduce_iname
#
# Interface names from SNMP are stupidly long and don't match the short name 
# in the ARP output so we have to do some pattern matching. Of course, this 
# will break when they decide to change the string.
#
# Arguments: 
#   string
# Returns:
#   string
#
sub _reduce_iname{
    my ($self, $name) = @_;
    return unless $name;
    if ( $name =~ /Appliance \'(\S+)\' interface/ ){
	return $1;
    }elsif ( $name =~ /Firewall Services Module \'(\S+)\' interface/ ){
	return $1;
    }
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

