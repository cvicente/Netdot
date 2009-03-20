package Netdot::Model::Device::CiscoFW;

use base 'Netdot::Model::Device';
use warnings;
use strict;
use Net::Appliance::Session;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');


=head1 NAME

Netdot::Model::Device::CiscoFW - Cisco Firewall Class

=head1 SYNOPSIS

 Overrides certain methods from the Device class

=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut


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
    $self->isa_object_method('_get_arp');
    my $host = $self->fqdn;
    my $cache;
    
    my $cli_cred_conf = Netdot->config->get('DEVICE_CLI_CREDENTIALS');
    unless ( @$cli_cred_conf ){
	$self->throw_user("Device::CiscoFW::get_arp: No credentials found in config file.");
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
	    
	    $cache = $self->_get_arp_from_cli(%args);
	    last;
	}
    }   
    if ( !$match ){
	$self->throw_user("Device::CiscoFW::get_arp: $host did not match any patterns in configured credentials.")
    }

    return $cache;
}


############################################################################
#_get_arp_from_cli - Fetch ARP tables via CLI
#
#    
#   Arguments:
#     login      -  first level login
#     password   -  first level password
#     privileged -  privileged password (optional)
#     transport  -  'SSH' or 'Telnet'
#   Returns:
#     Hash ref.
#    
#   Examples:
#     $self->_get_arp_from_cli();
#
#
sub _get_arp_from_cli {
    my ($self, %argv) = @_;
    my ($login, $password, $privileged, $transport) = 
	@argv{'login', 'password', 'privileged', 'transport'};
    
    $self->isa_object_method('_get_arp_from_cli');

    my $host = $self->fqdn;

    $self->throw_user("Device::CiscoFW::_get_arp_from_cli: $host: Missing required parameters: login/password")
	unless ( $login && $password );
    
    my %cache;
    
    # Temporarily until a bug is fixed in Net::Appliance::Session

    my ($s, @output);
    eval {
	$logger->debug(sub{"$host: Fetching ARP cache via CLI"});
	$s = Net::Appliance::Session->new(
	    Host      => $host,
	    Transport => $transport,
	    );
	
	$s->do_paging(0);

	$s->connect(Name     => $login, 
		    Password  => $password,
		    SHKC      => 0,
	    );
	
	if ( $privileged ){
	    $s->begin_privileged($privileged);
	}
	$s->cmd('termi pager 0');
	@output = $s->cmd('show arp');
	
	if ( $privileged ){
	    $s->end_privileged;
	}
	$s->close;
	
    };
    if ( my $e = $@ ){
	$self->throw_user("Device::CiscoFW::_get_arp_from_cli: $host: $e");
    }

    # MAP interface names to IDs
    my %iface_names;
    foreach my $iface ( $self->interfaces ){
	$iface_names{$iface->name} = $iface->id;
    }

    foreach my $line ( @output ) {
	if ( $line =~ /^\s+(\w+)\s(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s(\w{4}\.\w{4}\.\w{4}).*$/ ) {
	    my $iname = $1;
	    my $ip    = $2;
	    my $mac   = $3;
	    my $intid;
	    foreach my $name ( keys %iface_names ){
		if ( $name =~ /$iname/ ){
		    $intid = $iface_names{$name};
		}
	    }
	    unless ( $intid ) {
		$logger->warning("Device::CiscoFW::_get_arp_from_cli: $host: Could not match $iname to any interface name");
		next;
	    }
	    my $validmac = PhysAddr->validate($mac); 
	    if ( $validmac ){
		$mac = $validmac;
	    }else{
		$logger->debug(sub{"Device::CiscoFW::_get_arp_from_cli: $host: Invalid MAC: $mac" });
		next;
	    }	
	    # Store in hash
	    $cache{$intid}{$ip} = $mac;
	    $logger->debug(sub{"Device::get_arp_from_cli: $host: $iname -> $ip -> $mac" });
	}
    }

    return \%cache;
}
