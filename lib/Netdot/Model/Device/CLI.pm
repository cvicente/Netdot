package Netdot::Model::Device::CLI;

use base 'Netdot::Model::Device';
use warnings;
use strict;
use Net::Appliance::Session;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::Device::CLI - Base class to deal with Device CLI interaction

=head1 SYNOPSIS

Provides common functions for CLI access

=head1 CLASS METHODS
=cut

############################################################################
# Get CLI login credentials from config file
#
# Arguments: 
#   host
# Returns:
#   hashref
#
sub _get_credentials {
    my ($self, %argv) = @_;

    my $config_item = 'DEVICE_CLI_CREDENTIALS';
    my $host = $argv{host};
    my $cli_cred_conf = Netdot->config->get($config_item);
    unless ( ref($cli_cred_conf) eq 'ARRAY' ){
	$self->throw_user("Device::CLI::_get_credentials: config $config_item must be an array reference.");
    }
    unless ( @$cli_cred_conf ){
	$self->throw_user("Device::CLI::_get_credentials: config $config_item is empty");
    }

    my $match = 0;
    foreach my $cred ( @$cli_cred_conf ){
	my $pattern = $cred->{pattern};
	if ( $host =~ /$pattern/ ){
	    $match = 1;
	    my %args;
	    $args{login}      = $cred->{login};
	    $args{password}   = $cred->{password};
	    $args{privileged} = $cred->{privileged};
	    $args{transport}  = $cred->{transport} || 'SSH';
	    $args{timeout}    = $cred->{timeout}   || '30';
	    return \%args;
	}
    }   
    if ( !$match ){
	$self->throw_user("Device::CLI::_get_credentials: $host did not match any patterns in configured credentials.")
    }
}

############################################################################
# Issue CLI command
#
# Arguments:
#   Hash with the following keys:
#   login
#   password
#   privileged
#   transport
#   timeout
#   host 
#   personality
#   cmd
# Returns:
#   array
#
sub _cli_cmd {
    my ($self, %argv) = @_;
    my ($login, $password, $privileged, $transport, $timeout, $host, $personality, $cmd) = 
	@argv{'login', 'password', 'privileged', 'transport', 'timeout', 'host', 'personality', 'cmd'};
    
    $self->throw_user("Device::CLI::_cli_cmd: $host: Missing required parameters: login, password, cmd")
	unless ( $login && $password && $cmd );
    
    $personality ||= 'ios';

    my %sess_args = (
	host              => $host,
	transport         => $transport,
	personality       => $personality,
	connect_options   => {
	    shkc => 0,
	    opts => [
		'-o', "ConnectTimeout=$timeout",
		'-o', 'CheckHostIP=no',
		],
	},
	);

    # this is broken for some reason. Need to debug
    # $sess_args{privileged_paging} = 1 if ($personality eq 'pixos');
    # when fixed, remove terminal pager commands below

    my @output;
    eval {
	$logger->debug(sub{"$host: issuing CLI command: '$cmd' over $transport"});
	my $s = Net::Appliance::Session->new(\%sess_args);

	$s->nci->transport->ors("\r\n") if ($personality eq 'foundry');                                        

#       Uncomment this to debug session exchanges	
#	$s->set_global_log_at('debug');
	
	$s->connect({username  => $login, 
		     password  => $password,
		    });
	
	$s->begin_privileged({password=>$privileged}) if ( $privileged );
	$s->cmd('terminal pager 0') if ( $personality eq 'pixos' );
	@output = $s->cmd($cmd, {timeout=>$timeout});
	$s->cmd('terminal pager 36') if ( $personality eq 'pixos' );
	$s->end_privileged if ( $privileged );
	$s->close;
    };
    if ( my $e = $@ ){
	$self->throw_user("Device::CLI::_get_arp_from_cli: $host: $e");
    }
    return @output;
}

############################################################################
# _validate_arp - Validate contents of ARP and v6 ND structures
#    
#   Arguments:
#       hashref of hashrefs containing ifIndex, IP address and Mac
#       IP version
#   Returns:
#     Hash ref
#   Examples:
#     $self->_validate_arp(\%cache, 4);
#
#
sub _validate_arp {
    my($self, $cache, $version) = @_;
    $self->isa_object_method('_validate_arp');

    $self->throw_fatal("Device::CLI::_validate_arp: Missing required arguments")
	unless ($cache && $version);

    my $host = $self->fqdn();

    my $ign_non_subnet = Netdot->config->get('IGNORE_IPS_FROM_ARP_NOT_WITHIN_SUBNET');
    
    # Cisco Firewalls do not return subnet prefix information via SNMP
    # as of 27/07/2012. But we can get ARP info from them, so if we are
    # configured to ignore IPs which are not within known subnets, then
    # we'll have to disable that if we want to get ND neighbors.
    # This block must be removed later if the SNMP values are supported
    if ( $version == 6 && ref($self) =~ /CiscoFW$/o ){
	$ign_non_subnet = 0;
    }

    # MAP interface names to IDs
    # Get all interface IPs for subnet validation
    my %int_names;
    my %devsubnets;
    foreach my $int ( $self->interfaces ){
	my $name = $self->_reduce_iname($int->name);
	$int_names{$name} = $int->id;
	if ( $ign_non_subnet ){
	    foreach my $ip ( $int->ips ){
		next unless ($ip->version == $version);
		push @{$devsubnets{$int->id}}, $ip->parent->netaddr 
		    if $ip->parent;
	    }
	}
    }
    if ( $ign_non_subnet ){
	$logger->warn("Device::CLI::_validate_arp: We have no subnet information. ".
		      "ARP validation will fail except for link-local addresses")
	    unless %devsubnets;
    }

    my %valid;
    foreach my $key ( keys %{$cache} ){
	my $iname = $self->_reduce_iname($key);
	my $intid = $int_names{$iname};
	unless ( $intid ) {
	    $logger->warn("Device::CLI::_validate_arp: $host: Could not match $iname ".
			  "to any interface name");
	    next;
	}
	foreach my $ip ( keys %{$cache->{$key}} ){
	    if ( $version == 6 && Ipblock->is_link_local($ip) &&
		 Netdot->config->get('IGNORE_IPV6_LINK_LOCAL') ){
		next;
	    }
	    my $mac = $cache->{$key}->{$ip};
	    eval {
		$mac = PhysAddr->validate($mac);
	    };
	    if ( my $e = $@ ){
		$logger->debug(sub{"Device::CLI::_validate_arp: $host: Invalid MAC: $e" });
		next;
	    }
	    if ( $ign_non_subnet ){
		# This check does not work with link-local, so if user wants those
		# just validate them
		if ( $version == 6 && Ipblock->is_link_local($ip) ){
		    $valid{$intid}{$ip} = $mac;
		    next;
		}
		my $nip;
		unless ( $nip = NetAddr::IP->new($ip) ){
		    $logger->error("Device::CLI::_validate_arp: Cannot create NetAddr::IP object from $ip");
		    next;
		}
		foreach my $nsub ( @{$devsubnets{$intid}} ){
		    if ( $nip->within($nsub) ){
			$valid{$intid}{$ip} = $mac;
			last;
		    }else{
			$logger->debug(sub{"Device::CLI::_validate_arp: $host: $ip not within $nsub" });
		    }
		}
	    }else{
		$valid{$intid}{$ip} = $mac;
	    }
	    $logger->debug(sub{"Device::CLI::_validate_arp: $host: valid: $iname -> $ip -> $mac" });
	}
    }
    return \%valid;
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

