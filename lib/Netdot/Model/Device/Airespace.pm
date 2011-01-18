package Netdot::Model::Device::Airespace;

use base 'Netdot::Model::Device';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');
my $AIRESPACEIF = '(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\.\d';


=head1 NAME

Netdot::Model::Device::Airespace - Cisco Wireless Controller Class

=head1 SYNOPSIS

    Overrides certain methods from the Device class.  
    Particularly, we want to create a separate Device for each 
    access point to take advantage of topology discovery and
    more documentation options.

=head1 CLASS METHODS
=cut


=head1 INSTANCE METHODS
=cut


############################################################################
=head2 info_update - Update Device in Database using SNMP info

    Updates an existing Device based on information gathered via SNMP.  
    This is exclusively an object method, and overrides the Device
    method to gather specific SNMP information, etc.

  Arguments:
    Hash with the following keys:
    session       SNMP session (optional)
    info          Hashref with Device SNMP information. 
                  If not passed, this method will try to get it.
    communities   Arrayref of SNMP Community strings
    version       SNMP Version [1|2|3]
    timeout       SNMP Timeout
    retries       SNMP Retries
    sec_name      SNMP Security Name
    sec_level     SNMP Security Level
    auth_proto    SNMP Authentication Protocol
    auth_pass     SNMP Auth Key
    priv_proto    SNMP Privacy Protocol
    priv_pass     SNMP Privacy Key
    add_subnets   Flag. When discovering routers, add subnets to database if they do not exist
    subs_inherit  Flag. When adding subnets, have them inherit information from the Device
    bgp_peers     Flag. When discovering routers, update bgp_peers
    pretend       Flag. Do not commit changes to the database
    device_is_new Flag. Specifies that device was just created.

  Returns:
    Updated Device object

  Example:
    my $device = $device->info_update();

=cut
sub info_update {
    my ($self, %argv) = @_;
    $self->isa_object_method('info_update');
    
    my $class = ref $self;
    my $start = time;

    # Show full name in output
    my $host = $self->fqdn;
    
    my $sinfo = $argv{session};

    if ( !$sinfo ){
	my $version     = $argv{snmp_version} || $self->snmp_version || $self->config->get('DEFAULT_SNMPVERSION');
	my $communities = $argv{communities}  || [$self->community]  || $self->config->get('DEFAULT_SNMPCOMMUNITIES');
	my $timeout     = $argv{timeout}      || $self->config->get('DEFAULT_SNMPTIMEOUT');
	my $retries     = $argv{retries}      || $self->config->get('DEFAULT_SNMPRETRIES');
	my $sec_name    = $argv{sec_name}     || $self->snmp_securityname;
	my $sec_level   = $argv{sec_level}    || $self->snmp_securitylevel;
	my $auth_proto  = $argv{auth_proto}   || $self->snmp_authprotocol;
	my $auth_pass   = $argv{auth_pass}    || $self->snmp_authkey;
	my $priv_proto  = $argv{priv_proto}   || $self->snmp_privprotocol;
	my $priv_pass   = $argv{priv_pass}    || $self->snmp_privkey;
	
	$sinfo = $self->_get_snmp_session(communities => $communities,
					  version     => $version,
					  timeout     => $timeout,
					  retries     => $retries,
					  sec_name    => $sec_name,
					  sec_level   => $sec_level,
					  auth_proto  => $auth_proto,
					  auth_pass   => $auth_pass,
					  priv_proto  => $priv_proto,
					  priv_pass   => $priv_pass,
	    );
    }

    my $info = $argv{info} || Netdot::Model::Device->_exec_timeout($host, 
								   sub{ return $self->get_snmp_info(bgp_peers => 0,
												    session   => $sinfo,
									    ) });
    unless ( $info ){
	$logger->error("$host: No SNMP info received");
	return;	
    }
    unless ( ref($info) eq 'HASH' ){
	$self->throw_fatal("Model::Device::Airespace::info_update: Invalid SNMP data structure");
    }
    
    ##############################################################
    # Fetch Airespace-specific SNMP info
    
    # We want to do our own 'munging' for certain things
    my $munge = $sinfo->munge();
    foreach my $m ('airespace_ap_mac', 'airespace_bl_mac', 'airespace_if_mac'){
	$munge->{$m} = sub{ return $self->_oct2hex(@_) };
    }
    
    my @METHODS = ('airespace_apif_slot', 'airespace_ap_model', 'airespace_ap_mac', 'bsnAPEthernetMacAddress',
		   'airespace_ap_ip', 'bsnAPNetmask', 'airespace_apif_type', 'bsnAPIOSVersion',
		   'airespace_apif', 'airespace_apif_admin', 'airespace_ap_serial', 'airespace_ap_name',
		   'airespace_ap_loc', 'i_index', 'i_name'
	);
    
    my %hashes;
    foreach my $method ( @METHODS ){
	$hashes{$method} = $sinfo->$method;
    }
   
    ##############################################################
    # Data that will be passed to the update method
    my %dev;
    $info->{type} = 'Wireless Controller';
 
    # Pretend works by turning off autocommit in the DB handle and rolling back
    # all changes at the end
    if ( $argv{pretend} ){
        $logger->info("$host: Performing a dry-run");
        unless ( Netdot::Model->db_auto_commit(0) == 0 ){
            $self->throw_fatal("Model::Device::Airespace::info_update: Unable to set AutoCommit off");
        }
    }

    ##############################################################
    $dev{physaddr} = $self->_assign_base_mac($info);

    ##############################################################
    # Serial Number
    unless ( $dev{serialnumber} = $info->{serialnumber} ){
    	$logger->debug(sub{"$host did not return serial number" });
    }
    
    ##############################################################
    # Fill in some basic device info
    foreach my $field ( qw( community snmp_version layers ipforwarding sysname 
                            sysdescription syslocation os collect_arp collect_fwt ) ){
	$dev{$field} = $info->{$field} if exists $info->{$field};
    }
    
    ##############################################################
    if ( my $ipb = $self->_assign_snmp_target($info) ){
	$dev{snmp_target} = $ipb;
    }

    ##############################################################
    $dev{product} = $self->_assign_product($info);
    
    ##############################################################
    if ( $dev{product} && $argv{device_is_new} ){
	$dev{monitored} = $self->_assign_device_monitored($dev{product});
    }

    ##############################################################
    if ( $argv{device_is_new} && (my $g = $self->_assign_monitor_config_group($info)) ){
	$dev{monitor_config_group} = $g;
    }

    ##############################################################
    # Spanning Tree
    $self->_update_stp_info($info, \%dev);
    
    ##############################################################
    # Update Device object
    $self->update( \%dev );
    
    ##############################################################
    # Airespace APs
    #
    # Airespace Interfaces that represent thin APs
    
    foreach my $iid ( keys %{ $info->{interface} } ){
	
	# i_index value is different from iid in this case
	my $ifindex = $hashes{'i_index'}->{$iid};
	
	if ( $ifindex =~ /$AIRESPACEIF/ ){
	    my $ifname = $hashes{'i_name'}->{$iid};         # this has the name of the AP
	    $info->{interface}{$iid}{name}        = $ifindex;  
	    $info->{interface}{$iid}{description} = $ifname;
	    
	    # Notice that we pass a hashref to get the results appended.
	    # This is somewhat confusing but necessary, since each AP might have
	    # more than one interface, which would rewrite the local hash
	    # if we were to just assign the result
	    $self->_get_ap_info(hashes => \%hashes, 
				iid    => $iid , 
				info   => \%{$dev{airespace}{$ifname}} );
	}
    }

    ##############################################
    # Make sure we can write to the description field when
    # device is airespace - we store the AP name as the int description
    $self->_update_interfaces(info            => $info, 
			      add_subnets     => $argv{add_subnets}, 
			      subs_inherit    => $argv{subs_inherit},
			      overwrite_descr => 1,
	);

    # Get all the APs we already had
    my %oldaps;
    
    foreach my $int ( $self->interfaces ){
	if ( $int->name =~ /$AIRESPACEIF/ ){
	    my $apmac = $int->number;
	    $apmac =~ s/^(.*)\.\d$/$1/;
	    $oldaps{$apmac}++;
	}
    }

    # Insert or update the APs returned
    # When creating, we turn off snmp_managed because
    # the APs don't actually do SNMP
    # We also inherit some values from the Controller
    $logger->debug("Creating any new Access Points");
    foreach my $ap ( keys %{ $dev{airespace} } ){
	Netdot::Model::Device->discover(name          => $ap,
					main_ip       => $dev{airespace}{$ap}{main_ip},
					snmp_managed  => 0,
					canautoupdate => 0,
					owner         => $self->owner,
					used_by       => $self->used_by,
					info          => \%{$dev{airespace}{$ap}},
	    );
	my $apmac = $dev{airespace}{$ap}{physaddr};
	delete $oldaps{$apmac};
    }
    
    # Notify about the APs no longer associated with this controller
    # Note: If the AP was removed from the network, it will have
    # to be removed from Netdot manually.  This avoids the unwanted case of
    # removing APs that change controllers, thus losing their manually-entered information
    # (location, links, etc)
    foreach my $mac ( keys %oldaps ){
	if ( my $ap = Device->search(physaddr=>$mac)->first ){
	    $logger->warn(sprintf("AP %s (%s) no longer associated with controller: %s", 
				  $mac, $ap->short_name, $host));
	}
    }
    

    ##############################################################
    
    my $end = time;
    $logger->debug(sub{ sprintf("%s: SNMP update completed in %s", 
				$host, $self->sec2dhms($end-$start))});
    
    if ( $argv{pretend} ){
	$logger->debug(sub{"$host: Rolling back changes"});
	eval {
	    $self->dbi_rollback;
	};
	if ( my $e = $@ ){
	    $self->throw_fatal("Model::Device::Airespace::info_update: Rollback Failed!: $e");
	}
	$logger->debug(sub{"Model::Device::info_update: Turning AutoCommit back on"});
	unless ( Netdot::Model->db_auto_commit(1) == 1 ){
	    $self->throw_fatal("Model::Device::Airespace::info_update: Unable to set AutoCommit on");
	}
    }

    return $self;
}



#####################################################################
#
# Private methods
#
#####################################################################


#####################################################################
# Given Airespace interfaces info, create a hash with the necessary
# info to create a Device for each AP
#
sub _get_ap_info {
    my ($self, %argv) = @_;

    my ($hashes, $iid, $info) = @argv{"hashes", "iid", "info"};
    
    my $idx = $iid;
    $idx =~ s/\.\d+$//;
    
    if ( defined(my $model = $hashes->{'airespace_ap_model'}->{$idx}) ){
	$info->{model} = $model;
    }
    if ( defined(my $os = $hashes->{'bsnAPIOSVersion'}->{$idx}) ){
	$info->{os} = $os;
    }
    if ( defined(my $serial = $hashes->{'airespace_ap_serial'}->{$idx}) ){
	$info->{serialnumber} = $serial;
    }
    if ( defined(my $sysname = $hashes->{'airespace_ap_name'}->{$idx}) ){
	$info->{sysname} = $sysname;
    }
    if ( defined(my $syslocation = $hashes->{'airespace_ap_loc'}->{$idx}) ){
	$info->{syslocation} = $syslocation;
    }

    $info->{type}         = "Access Point";
    $info->{manufacturer} = "Cisco";

    # AP Ethernet MAC
    if ( my $basemac = $hashes->{'airespace_ap_mac'}->{$idx} ){
	my $validmac = PhysAddr->validate($basemac);
	if ( $validmac ){
	    $info->{physaddr} = $validmac;
	}else{
	    $logger->debug(sub{"Device::get_airespace_if_info: iid $iid: Invalid MAC: $basemac" });
	}
    } 

    # Interfaces in this AP
    if ( defined( my $slot = $hashes->{'airespace_apif_slot'}->{$iid} ) ){

	my $radio = $hashes->{'airespace_apif_type'}->{$iid};
	if ( $radio eq "dot11b" ){
	    $radio = "802.11b/g";
	}elsif ( $radio eq "dot11a" ){
	    $radio = "802.11a";
	}elsif ( $radio eq "uwb" ){
	    $radio = "uwb";
	}
	my $name      = $radio;
	my $apifindex = $slot + 1;
	$info->{interface}{$apifindex}{name}   = $name;
	$info->{interface}{$apifindex}{number} = $apifindex;
	if ( defined(my $oper = $hashes->{'airespace_apif'}->{$iid}) ){
	    $info->{interface}{$apifindex}{oper_status} = $oper;
	}
	if ( defined(my $admin = $hashes->{'airespace_apif_admin'}->{$iid}) ){
	    $info->{interface}{$apifindex}{admin_status} = $admin;
	}
    }

    # Add an Ethernet interface
    # This is important because the name is advertised using CDP
    my $ethidx = 3;

    # As far as I can tell, the Airespace MIB does not include the Ethernet interface name
    # Assign either GigabitEthernet0 or FastEthernet0 based on what we know about current products
    # This will most likely be out of date soon. There has to be a better way to do this!
    if ( $info->{model} =~ /(-LAP114\d)|(-LAP152\d)|(-CAP350\d)|(-SAP35)|(AP801)/ ){
	$info->{interface}{$ethidx}{name}   = 'GigabitEthernet0';
    }else{
	$info->{interface}{$ethidx}{name}   = 'FastEthernet0';
    }
    $info->{interface}{$ethidx}{number} = $ethidx;
    
    if ( my $mac = $hashes->{'bsnAPEthernetMacAddress'}->{$idx}){
	$mac = $self->_oct2hex($mac);
	$info->{interface}{$ethidx}{physaddr} = $mac;
    }

    # Add the Null0 interface
    my $nullidx = 4;
    $info->{interface}{$nullidx}{name}   = 'Null0';
    $info->{interface}{$nullidx}{number} = 4;

    # Add the BVI interface
    my $bviidx = 5;
    $info->{interface}{$bviidx}{name}   = 'BVI1';
    $info->{interface}{$bviidx}{number} = $bviidx;

    # Assign the IP and Netmask to the BVI1 interface
    if ( my $ip = $hashes->{'airespace_ap_ip'}->{$idx}  ){
	$info->{interface}{$bviidx}{ips}{$ip}{address} = $ip;
	if ( my $mask = $hashes->{'bsnAPNetmask'}->{$idx}  ){
	    $info->{interface}{$bviidx}{ips}{$ip}{mask} = $mask;
	}
	$info->{main_ip} = $ip;
    }
    
    return 1;
}

