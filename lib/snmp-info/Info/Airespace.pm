# SNMP::Info::Airespace
# $Id: Airespace.pm,v 1.15 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2008 Eric Miller
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR # ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Airespace;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::Airespace::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::Airespace::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::MIBS,
    'AIRESPACE-WIRELESS-MIB'  => 'bsnAPName',
    'AIRESPACE-SWITCHING-MIB' => 'agentInventorySerialNumber',
);

%GLOBALS = (
    %SNMP::Info::GLOBALS,
    'airespace_type'       => 'agentInventoryMachineType',
    'airespace_model'      => 'agentInventoryMachineModel',
    'airespace_serial'     => 'agentInventorySerialNumber',
    'airespace_maint_ver'  => 'agentInventoryMaintenanceLevel',
    'airespace_mac'        => 'agentInventoryBurnedInMacAddress',
    'airespace_os'         => 'agentInventoryOperatingSystem',
    'airespace_vendor'     => 'agentInventoryManufacturerName',
    'airespace_prod_name'  => 'agentInventoryProductName',
    'os_ver'               => 'agentInventoryProductVersion',
    'airespace_bssid_mode' => 'agentNetworkBroadcastSsidMode',
    'airespace_mc_mode'    => 'agentNetworkMulticastMode',
    'airespace_lwapp_mode' => 'agentSwitchLwappTransportMode',
    'airespace_ul_mode'    => 'agentTransferUploadMode',
    'airespace_ul_ip'      => 'agentTransferUploadServerIP',
    'airespace_ul_path'    => 'agentTransferUploadPath',
    'airespace_ul_file'    => 'agentTransferUploadFilename',
    'airespace_ul_type'    => 'agentTransferUploadDataType',
    'airespace_ul_start'   => 'agentTransferUploadStart',
    'airespace_ul_status'  => 'agentTransferUploadStatus',
);

%FUNCS = (
    %SNMP::Info::FUNCS,

    # AIRESPACE-WIRELESS-MIB::bsnDot11EssTable
    'airespace_ess_idx'       => 'bsnDot11EssIndex',
    'airespace_ess_ssid'      => 'bsnDot11EssSsid',
    'airespace_ess_macflt'    => 'bsnDot11EssMacFiltering',
    'airespace_ess_status'    => 'bsnDot11EssAdminStatus',
    'airespace_ess_sec_auth'  => 'bsnDot11EssSecurityAuthType',
    'airespace_ess_radio_pol' => 'bsnDot11EssRadioPolicy',
    'airespace_ess_qos'       => 'bsnDot11EssQualityOfService',
    'airespace_ess_ifname'    => 'bsnDot11EssInterfaceName',
    'airespace_ess_aclname'   => 'bsnDot11EssAclName',

    # AIRESPACE-WIRELESS-MIB::bsnAPTable
    'airespace_ap_mac'    => 'bsnAPDot3MacAddress',
    'airespace_ap_name'   => 'bsnAPName',
    'airespace_ap_ip'     => 'bsnApIpAddress',
    'airespace_ap_loc'    => 'bsnAPLocation',
    'airespace_ap_sw'     => 'bsnAPSoftwareVersion',
    'airespace_ap_fw'     => 'bsnAPBootVersion',
    'airespace_ap_model'  => 'bsnAPModel',
    'airespace_ap_serial' => 'bsnAPSerialNumber',
    'airespace_ap_type'   => 'bsnAPType',
    'airespace_ap_status' => 'bsnAPAdminStatus',

    # AIRESPACE-WIRELESS-MIB::bsnAPIfTable
    'airespace_apif_slot'   => 'bsnAPIfSlotId',
    'airespace_apif_type'   => 'bsnAPIfType',
    'airespace_apif_ch_num' => 'bsnAPIfPhyChannelNumber',
    'airespace_apif_power'  => 'bsnAPIfPhyTxPowerLevel',
    'airespace_apif'        => 'bsnAPIfOperStatus',
    'airespace_apif_oride'  => 'bsnAPIfWlanOverride',
    'airespace_apif_admin'  => 'bsnAPIfAdminStatus',

    # AIRESPACE-WIRELESS-MIB::bsnMobileStationTable
    'airespace_sta_mac'     => 'bsnMobileStationAPMacAddr',
    'fw_mac'                => 'bsnMobileStationMacAddress',
    'airespace_sta_slot'    => 'bsnMobileStationAPIfSlotId',
    'airespace_sta_ess_idx' => 'bsnMobileStationEssIndex',
    'airespace_sta_ssid'    => 'bsnMobileStationSsid',
    'airespace_sta_delete'  => 'bsnMobileStationDeleteAction',

    # AIRESPACE-WIRELESS-MIB::bsnUsersTable
    'airespace_user_name'    => 'bsnUserName',
    'airespace_user_pw'      => 'bsnUserPassword',
    'airespace_user_ess_idx' => 'bsnUserEssIndex',
    'airespace_user_access'  => 'bsnUserAccessMode',
    'airespace_user_type'    => 'bsnUserType',
    'airespace_user_ifname'  => 'bsnUserInterfaceName',
    'airespace_user_rstat'   => 'bsnUserRowStatus',

    # AIRESPACE-WIRELESS-MIB::bsnBlackListClientTable
    'airespace_bl_mac'   => 'bsnBlackListClientMacAddress',
    'airespace_bl_descr' => 'bsnBlackListClientDescription',
    'airespace_bl_rstat' => 'bsnBlackListClientRowStatus',

    # AIRESPACE-WIRELESS-MIB::bsnAPIfWlanOverrideTable
    'airespace_oride_id'   => 'bsnAPIfWlanOverrideId',
    'airespace_oride_ssid' => 'bsnAPIfWlanOverrideSsid',

    # AIRESPACE-SWITCHING-MIB::agentInterfaceConfigTable
    'airespace_if_name'  => 'agentInterfaceName',
    'airespace_if_vlan'  => 'agentInterfaceVlanId',
    'airespace_if_type'  => 'agentInterfaceType',
    'airespace_if_mac'   => 'agentInterfaceMacAddress',
    'airespace_if_ip'    => 'agentInterfaceIPAddress',
    'airespace_if_mask'  => 'agentInterfaceIPNetmask',
    'airespace_if_acl'   => 'agentInterfaceAclName',
    'airespace_if_rstat' => 'agentInterfaceRowStatus',

    # AIRESPACE-SWITCHING-MIB::agentPortConfigTable
    'airespace_duplex_admin' => 'agentPortPhysicalMode',
    'airespace_duplex'       => 'agentPortPhysicalStatus',
);

%MUNGE = (
    %SNMP::Info::MUNGE,
    'airespace_ap_mac'  => \&SNMP::Info::munge_mac,
    'fw_port'           => \&SNMP::Info::munge_mac,
    'airespace_bl_mac'  => \&SNMP::Info::munge_mac,
    'airespace_if_mac'  => \&SNMP::Info::munge_mac,
    'airespace_sta_mac' => \&SNMP::Info::munge_mac,
);

sub layers {
    return '00000011';
}

sub serial {
    my $airespace = shift;
    my $sn        = $airespace->airespace_serial();
    return unless defined $sn;

    return $sn;
}

# Wirless switches do not support ifMIB requirements to get MAC
# and port status

sub i_index {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index  = $airespace->orig_i_index($partial)        || {};
    my $ap_index = $airespace->airespace_apif_slot($partial) || {};
    my $if_index = $airespace->airespace_if_name($partial)   || {};

    my %if_index;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        $if_index{$iid} = $index;
    }

    # Get Attached APs as Interfaces
    foreach my $ap_id ( keys %$ap_index ) {

        if ( $ap_id =~ /(\d+\.\d+\.\d+\.\d+\.\d+\.\d+)\.(\d+)/ ) {
            my $mac = join( ':',
                map { sprintf( "%02x", $_ ) } split( /\./, $1 ) );
            my $slot = $2;
            next unless ( ( defined $mac ) and ( defined $slot ) );

            $if_index{$ap_id} = "$mac.$slot";
        }
    }

    # Get Switch Interfaces from Interface Config Table
    foreach my $if_id ( keys %$if_index ) {
        my $name = $if_index->{$if_id};
        next unless defined $name;

        $if_index{$if_id} = $name;
    }

    return \%if_index;
}

sub interfaces {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index = $airespace->i_index($partial) || {};

    my %if;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            $if{$iid} = "1.$index";
        }

        else {
            $if{$iid} = $index;
        }
    }
    return \%if;
}

sub i_name {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index = $airespace->i_index($partial)           || {};
    my $i_name  = $airespace->orig_i_name($partial)       || {};
    my $ap_name = $airespace->airespace_ap_name($partial) || {};

    my %i_name;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            my $name = $i_name->{$iid};
            next unless defined $name;
            $i_name{$iid} = $name;
        }

        elsif ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $idx = $iid;
            $idx =~ s/\.\d+$//;
            my $name = $ap_name->{$idx};
            next unless defined $name;
            $i_name{$iid} = $name;
        }

        else {
            $i_name{$iid} = $index;
        }
    }
    return \%i_name;
}

sub i_description {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index = $airespace->i_index($partial)            || {};
    my $i_descr = $airespace->orig_i_description($partial) || {};
    my $ap_loc  = $airespace->airespace_ap_loc($partial)   || {};

    my %descr;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            my $descr = $i_descr->{$iid};
            next unless defined $descr;
            $descr{$iid} = $descr;
        }

        elsif ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $idx = $iid;
            $idx =~ s/\.\d+$//;
            my $name = $ap_loc->{$idx};
            next unless defined $name;
            $descr{$iid} = $name;
        }

        else {
            $descr{$iid} = $index;
        }
    }
    return \%descr;
}

sub i_type {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index   = $airespace->i_index($partial)             || {};
    my $i_descr   = $airespace->orig_i_type($partial)         || {};
    my $apif_type = $airespace->airespace_apif_type($partial) || {};
    my $if_type   = $airespace->airespace_if_type($partial)   || {};

    my %i_type;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            my $descr = $i_descr->{$iid};
            next unless defined $descr;
            $i_type{$iid} = $descr;
        }

        elsif ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $type = $apif_type->{$iid};
            next unless defined $type;
            $i_type{$iid} = $type;
        }

        else {
            my $type = $if_type->{$iid};
            $i_type{$iid} = $type;
        }
    }
    return \%i_type;
}

sub i_up {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index = $airespace->i_index($partial)        || {};
    my $i_up    = $airespace->orig_i_up($partial)      || {};
    my $apif_up = $airespace->airespace_apif($partial) || {};

    my %i_up;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            my $stat = $i_up->{$iid};
            next unless defined $stat;
            $i_up{$iid} = $stat;
        }

        elsif ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $stat = $apif_up->{$iid};
            next unless defined $stat;
            $i_up{$iid} = $stat;
        }

        else {
            next;
        }
    }
    return \%i_up;
}

sub i_up_admin {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index = $airespace->i_index($partial)              || {};
    my $i_up    = $airespace->orig_i_up($partial)            || {};
    my $apif_up = $airespace->airespace_apif_admin($partial) || {};

    my %i_up_admin;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            my $stat = $i_up->{$iid};
            next unless defined $stat;
            $i_up_admin{$iid} = $stat;
        }

        elsif ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $stat = $apif_up->{$iid};
            next unless defined $stat;
            $i_up_admin{$iid} = $stat;
        }

        else {
            next;
        }
    }
    return \%i_up_admin;
}

sub i_mac {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index = $airespace->i_index($partial)          || {};
    my $i_mac   = $airespace->orig_i_mac($partial)       || {};
    my $if_mac  = $airespace->airespace_if_mac($partial) || {};

    my %i_mac;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            my $mac = $i_mac->{$iid};
            next unless defined $mac;
            $i_mac{$iid} = $mac;
        }

        # Don't grab AP MACs - we want the AP to show up on edge switch
        # ports
        # Some switch interfaces have MACs, virtuals report 00:00:00:00:00:00

        else {
            my $mac = $if_mac->{$iid};
            next unless defined $mac;
            next if $mac =~ /00:00:00:00:00:00/;
            $i_mac{$iid} = $mac;
        }
    }
    return \%i_mac;
}

sub i_vlan {
    my $airespace = shift;
    my $partial   = shift;

    my $if_vlan = $airespace->airespace_if_vlan($partial) || {};

    my %i_vlan;
    foreach my $iid ( keys %$if_vlan ) {
        my $vlan = $if_vlan->{$iid};
        next unless defined $vlan;

        $i_vlan{$iid} = $vlan;
    }

    return \%i_vlan;
}

sub i_duplex {
    my $airespace = shift;
    my $partial   = shift;

    my $ap_duplex = $airespace->airespace_duplex($partial) || {};

    my %i_duplex;
    foreach my $if ( keys %$ap_duplex ) {
        my $duplex = $ap_duplex->{$if};
        next unless defined $duplex;

        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;
        $duplex = 'auto' if $duplex =~ /auto/i;
        $i_duplex{$if} = $duplex;
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $airespace = shift;
    my $partial   = shift;

    my $ap_duplex_admin = $airespace->airespace_duplex_admin($partial) || {};

    my %i_duplex_admin;
    foreach my $if ( keys %$ap_duplex_admin ) {
        my $duplex = $ap_duplex_admin->{$if};
        next unless defined $duplex;

        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;
        $duplex = 'auto' if $duplex =~ /auto/i;
        $i_duplex_admin{$if} = $duplex;
    }
    return \%i_duplex_admin;
}

sub ip_index {
    my $airespace = shift;
    my $partial   = shift;

    my $ip_index = $airespace->orig_ip_index($partial) || {};
    my $if_ip    = $airespace->airespace_if_ip()       || {};

    my %ip_index;
    foreach my $ip ( keys %$ip_index ) {
        my $iid = $ip_index->{$ip};
        next unless defined $iid;

        $ip_index{$ip} = $iid;
    }

    foreach my $iid ( keys %$if_ip ) {
        my $ip = $if_ip->{$iid};
        next unless defined $ip;
        next if ( defined $partial and $partial !~ /$ip/ );

        $ip_index{$ip} = $iid;
    }

    return \%ip_index;
}

sub ip_netmask {
    my $airespace = shift;
    my $partial   = shift;

    my $ip_mask = $airespace->orig_ip_netmask($partial) || {};
    my $if_ip   = $airespace->airespace_if_ip()         || {};
    my $if_mask = $airespace->airespace_if_mask()       || {};

    my %ip_netmask;
    foreach my $ip ( keys %$ip_mask ) {
        my $mask = $ip_mask->{$ip};
        next unless defined $mask;

        $ip_netmask{$ip} = $mask;
    }

    foreach my $iid ( keys %$if_mask ) {
        my $ip = $if_ip->{$iid};
        next unless defined $ip;
        next if ( defined $partial and $partial !~ /$ip/ );
        my $mask = $if_mask->{$iid};
        next unless defined $mask;

        $ip_netmask{$ip} = $mask;
    }

    return \%ip_netmask;
}

# Wireless switches do not support the standard Bridge MIB
sub bp_index {
    my $airespace = shift;
    my $partial   = shift;

    my $i_index = $airespace->i_index($partial) || {};

    my %bp_index;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        $bp_index{$index} = $iid;
    }

    return \%bp_index;
}

sub fw_port {
    my $airespace = shift;
    my $partial   = shift;

    my $sta_mac  = $airespace->airespace_sta_mac($partial)  || {};
    my $sta_slot = $airespace->airespace_sta_slot($partial) || {};

    my %fw_port;
    foreach my $iid ( keys %$sta_mac ) {
        my $mac = $sta_mac->{$iid};
        next unless defined $mac;
        my $slot = $sta_slot->{$iid};
        next unless defined $slot;

        $fw_port{$iid} = "$mac.$slot";
    }

    return \%fw_port;
}

sub i_ssidlist {
    my $airespace = shift;
    my $partial   = shift;

    my $apif_override = $airespace->airespace_apif_oride($partial) || {};
    my $apif_type     = $airespace->airespace_apif_type($partial)  || {};
    my $ssids         = $airespace->airespace_ess_ssid()           || {};
    my $ssid_policy   = $airespace->airespace_ess_radio_pol()      || {};
    my $ssid_status   = $airespace->airespace_ess_status()         || {};
    my $ovride_ssids  = $airespace->airespace_oride_ssid($partial) || {};

    my %i_ssidlist;
    foreach my $iid ( keys %$apif_override ) {
        my $override = $apif_override->{$iid};
        next unless defined $override;

        next unless $override =~ /disable/i;
        my $ap_type = $apif_type->{$iid};
        next unless defined $ap_type;
        $ap_type =~ s/dot11//;

        foreach my $idx ( keys %$ssids ) {
            my $ssid = $ssids->{$idx};
            next unless defined $ssid;
            my $status = $ssid_status->{$idx};
            next unless defined $status;
            next if ( $status =~ /disable/ );
            my $policy = $ssid_policy->{$idx};
            next unless $policy =~ /$ap_type/ or $policy =~ /all/;

            $i_ssidlist{"$iid.$idx"} = $ssid;
        }
        next;
    }

    foreach my $iid ( keys %$ovride_ssids ) {
        my $ssid = $ovride_ssids->{$iid};
        next unless $ssid;

        $i_ssidlist{$iid} = $ssid;
    }

    return \%i_ssidlist;
}

sub i_ssidbcast {
    my $airespace = shift;
    my $partial   = shift;

    my $ssidlist = $airespace->i_ssidlist($partial)   || {};
    my $bc_mode  = $airespace->airespace_bssid_mode() || 'enable';

    my %bcmap     = qw/enable 1 disable 0/;
    my $broadcast = $bcmap{$bc_mode};

    my %i_ssidbcast;
    foreach my $iid ( keys %$ssidlist ) {
        $i_ssidbcast{$iid} = $broadcast;
    }

    return \%i_ssidbcast;
}

sub i_80211channel {
    my $airespace = shift;
    my $partial   = shift;

    my $ch_list = $airespace->airespace_apif_ch_num($partial) || {};

    my %i_80211channel;
    foreach my $iid ( keys %$ch_list ) {
        my $ch = $ch_list->{$iid};
        $ch =~ s/ch//;
        $i_80211channel{$iid} = $ch;
    }

    return \%i_80211channel;
}

# Pseudo ENTITY-MIB methods

sub e_index {
    my $airespace = shift;

    my $ap_model = $airespace->airespace_ap_model() || {};

    my %e_index;

    # Chassis
    $e_index{1} = 1;

    # We're going to hack an index to capture APs
    foreach my $idx ( keys %$ap_model ) {

       # Create the integer index by joining the last three octets of the MAC.
       # Hopefully, this will be unique since the manufacturer should be
       # limited to Airespace and Cisco.  We can't use the entire MAC since
       # we would exceed the intger size limit.
        if ( $idx =~ /(\d+\.\d+\.\d+)$/ ) {
            my $index = int(
                join( '', map { sprintf "%03d", $_ } split /\./, $1 ) );
            $e_index{$idx} = $index;
        }
    }
    return \%e_index;
}

sub e_class {
    my $airespace = shift;

    my $e_idx = $airespace->e_index() || {};

    my %e_class;
    foreach my $iid ( keys %$e_idx ) {
        if ( $iid eq 1 ) {
            $e_class{$iid} = 'chassis';
        }

        # This isn't a valid PhysicalClass, but we're hacking this anyway
        else {
            $e_class{$iid} = 'ap';
        }
    }
    return \%e_class;
}

sub e_name {
    my $airespace = shift;

    my $ap_name = $airespace->airespace_ap_name() || {};

    my %e_name;

    # Chassis
    $e_name{1} = 'WLAN Controller';

    # APs
    foreach my $iid ( keys %$ap_name ) {
        $e_name{$iid} = 'AP';
    }
    return \%e_name;
}

sub e_descr {
    my $airespace = shift;

    my $ap_model = $airespace->airespace_ap_model() || {};
    my $ap_name  = $airespace->airespace_ap_name()  || {};
    my $ap_loc   = $airespace->airespace_ap_loc()   || {};

    my %e_descr;

    # Chassis
    $e_descr{1} = $airespace->airespace_prod_name();

    # APs
    foreach my $iid ( keys %$ap_name ) {
        my $name = $ap_name->{$iid};
        next unless defined $name;
        my $model = $ap_model->{$iid} || 'AP';
        my $loc   = $ap_loc->{$iid}   || 'unknown';

        $e_descr{$iid} = "$model: $name ($loc)";
    }
    return \%e_descr;
}

sub e_model {
    my $airespace = shift;

    my $ap_model = $airespace->airespace_ap_model() || {};

    my %e_model;

    # Chassis
    $e_model{1} = $airespace->airespace_model();

    # APs
    foreach my $iid ( keys %$ap_model ) {
        my $model = $ap_model->{$iid};
        next unless defined $model;

        $e_model{$iid} = $model;
    }
    return \%e_model;
}

sub e_type {
    my $airespace = shift;

    my $ap_type = $airespace->airespace_ap_type() || {};

    my %e_type;

    # Chassis
    $e_type{1} = $airespace->airespace_type();

    # APs
    foreach my $iid ( keys %$ap_type ) {
        my $type = $ap_type->{$iid};
        next unless defined $type;

        $e_type{$iid} = $type;
    }
    return \%e_type;
}

sub e_fwver {
    my $airespace = shift;

    my $ap_fw = $airespace->airespace_ap_fw() || {};

    my %e_fwver;

    # Chassis
    $e_fwver{1} = $airespace->airespace_maint_ver();

    # APs
    foreach my $iid ( keys %$ap_fw ) {
        my $fw = $ap_fw->{$iid};
        next unless defined $fw;

        $e_fwver{$iid} = $fw;
    }
    return \%e_fwver;
}

sub e_vendor {
    my $airespace = shift;

    my $e_idx = $airespace->e_index() || {};

    my %e_vendor;
    foreach my $iid ( keys %$e_idx ) {
        $e_vendor{$iid} = 'cisco';
    }
    return \%e_vendor;
}

sub e_serial {
    my $airespace = shift;

    my $ap_serial = $airespace->airespace_ap_serial() || {};

    my %e_serial;

    # Chassis
    $e_serial{1} = $airespace->airespace_serial();

    # APs
    foreach my $iid ( keys %$ap_serial ) {
        my $serial = $ap_serial->{$iid};
        next unless defined $serial;

        $e_serial{$iid} = $serial;
    }
    return \%e_serial;
}

sub e_pos {
    my $airespace = shift;

    my $e_idx = $airespace->e_index() || {};

    my %e_pos;
    my $pos = 0;
    foreach my $iid ( sort keys %$e_idx ) {
        if ( $iid eq 1 ) {
            $e_pos{$iid} = -1;
            next;
        }
        else {
            $pos++;
            $e_pos{$iid} = $pos;
        }
    }
    return \%e_pos;
}

sub e_swver {
    my $airespace = shift;

    my $ap_sw = $airespace->airespace_ap_sw() || {};

    my %e_swver;

    # Chassis
    $e_swver{1} = $airespace->airespace_os();

    # APs
    foreach my $iid ( keys %$ap_sw ) {
        my $sw = $ap_sw->{$iid};
        next unless defined $sw;

        $e_swver{$iid} = $sw;
    }
    return \%e_swver;
}

sub e_parent {
    my $airespace = shift;

    my $e_idx = $airespace->e_index() || {};

    my %e_parent;
    foreach my $iid ( sort keys %$e_idx ) {
        if ( $iid eq 1 ) {
            $e_parent{$iid} = 0;
            next;
        }
        else {
            $e_parent{$iid} = 1;
        }
    }
    return \%e_parent;
}

1;
__END__

=head1 NAME

SNMP::Info::Airespace - SNMP Interface to data from F<AIRESPACE-WIRELESS-MIB>
and F<AIRESPACE-SWITCHING-MIB>

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    my $airespace = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $airespace->class();
    print " Using device sub class : $class\n";

=head1 DESCRIPTION

SNMP::Info::Airespace is a subclass of SNMP::Info that provides an interface
to F<AIRESPACE-WIRELESS-MIB> and F<AIRESPACE-SWITCHING-MIB>.  These MIBs are
used in Airespace wireless switches, as well as, products from Cisco, Nortel,
and Alcatel which are based upon the Airespace platform.

The Airespace platform utilizes intelligent wireless switches which control
thin access points.  The thin access points themselves are unable to be polled
for end station information.

This class emulates bridge functionality for the wireless switch. This enables
end station MAC addresses collection and correlation to the thin access point
the end station is using for communication.

Use or create a subclass of SNMP::Info that inherits this one.
Do not use directly.

=head2 Inherited Classes

=over

None.

=back

=head2 Required MIBs

=over

=item F<AIRESPACE-WIRELESS-MIB>

=item F<AIRESPACE-SWITCHING-MIB>

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $airespace->airespace_type()

(C<agentInventoryMachineType>)

=item $airespace->airespace_model()

(C<agentInventoryMachineModel>)

=item $airespace->airespace_serial()

(C<agentInventorySerialNumber>)

=item $airespace->airespace_maint_ver()

(C<agentInventoryMaintenanceLevel>)

=item $airespace->airespace_mac()

(C<agentInventoryBurnedInMacAddress>)

=item $airespace->airespace_os()

(C<agentInventoryOperatingSystem>)

=item $airespace->airespace_vendor()

(C<agentInventoryManufacturerName>)

=item $airespace->airespace_prod_name()

(C<agentInventoryProductName>)

=item $airespace->os_ver()

(C<agentInventoryProductVersion>)

=item $airespace->airespace_bssid_mode()

(C<agentNetworkBroadcastSsidMode>)

=item $airespace->airespace_mc_mode()

(C<agentNetworkMulticastMode>)

=item $airespace->airespace_lwapp_mode()

The LWAPP transport mode decides if the switch is operating in the Layer2 or
Layer3 mode.

(C<agentSwitchLwappTransportMode>)

=item $airespace->airespace_ul_mode()

Transfer upload mode configures the mode to use when uploading from the
switch.  Normal usage tftp.

(C<agentTransferUploadMode>)

=item $airespace->airespace_ul_ip()

Transfer upload tftp server ip configures the IP address of the server. It is
valid only when the Transfer Mode is tftp.

(C<agentTransferUploadServerIP>)

=item $airespace->airespace_ul_path()

Transfer upload tftp path configures the directory path where the file is to
be uploaded to. The switch remembers the last file path used. 

(C<agentTransferUploadPath>)

=item $airespace->airespace_ul_file()

(C<agentTransferUploadFilename>)

=item $airespace->airespace_ul_type()

Transfer upload datatype configures the type of file to upload from the
switch.

    The types for upload are:
    config(2)
    errorlog(3)
    systemtrace(4)
    traplog(5)
    crashfile(6)

(C<agentTransferUploadDataType>)

=item $airespace->airespace_ul_start()

(C<agentTransferUploadStart>)

=item $airespace->airespace_ul_status()

(C<agentTransferUploadStatus>)

=back

=head2 Overrides

=over

=item $airespace->layers()

Returns 00000011.  Class emulates Layer 2 functionality for Thin APs through
proprietary MIBs.

=item $airespace->serial()

(C<agentInventorySerialNumber>)

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $airespace->i_ssidlist()

Returns reference to hash.  SSID's recognized by the radio interface.

=item $airespace->i_ssidbcast()

Returns reference to hash.  Indicates whether the SSID is broadcast.

=item $airespace->i_80211channel()

Returns reference to hash.  Current operating frequency channel of the radio
interface.

=back

=head2 Dot11 Ess Table  (C<bsnDot11EssTable>)

Ess(WLAN) Configuration Table. Maximum of 17 WLANs can be created on
Airespace Switch. Index of 17 is reserved for WLAN for Third Party
APs(non-Airespace APs).

=over

=item $airespace->airespace_ess_idx()

(C<bsnDot11EssIndex>)

=item $airespace->airespace_ess_ssid()

SSID assigned to ESS(WLAN)

(C<bsnDot11EssSsid>)

=item $airespace->airespace_ess_macflt()

Select to filter clients by MAC address.  By selecting this Security, you need
to create MAC Filters in C<bsnUsersTable> or have MAC Filters configured on
Radius Servers specified in C<bsnRadiusAuthenticationTable>

(C<bsnDot11EssMacFiltering>)

=item $airespace->airespace_ess_status()

Administrative Status of ESS(WLAN).

(C<bsnDot11EssAdminStatus>)

=item $airespace->airespace_ess_sec_auth()

Type of 802.11 Authentication.

(C<bsnDot11EssSecurityAuthType>)

=item $airespace->airespace_ess_radio_pol()

Radio Policy for a WLAN. It can either be All where it will be applicable
to ALL types of protocols or it can be set to apply to combinations of
802.11a, 802.11b, 802.11g.

(C<bsnDot11EssRadioPolicy>)

=item $airespace->airespace_ess_qos()

Quality of Service for a WLAN.

(C<bsnDot11EssQualityOfService>)

=item $airespace->airespace_ess_ifname()

Name of the interface used by this WLAN.

(C<bsnDot11EssInterfaceName>)

=item $airespace->airespace_ess_aclname()

Name of ACL for the WLAN. This is applicable only when Web Authentication is
enabled.

(C<bsnDot11EssAclName>)           

=back

=head2 AP Table (C<bsnAPTable>)

Table of Airespace APs managed by this Airespace Switch.

=over

=item $airespace->airespace_ap_mac()

The MAC address of the 802.3 interface of the AP.

(C<bsnAPDot3MacAddress>)

=item $airespace->airespace_ap_name()

Name assigned to this AP. If an AP is not configured its factory default name
will be ap:<last three byte of MAC Address>.  e.g. ap:af:12:be

(C<bsnAPName>)

=item $airespace->airespace_ap_ip()

Ip address of the AP. This will not be available when the switch is operating
in the Layer2 mode. In this case, the attribute will return 0 as value.

(C<bsnApIpAddress>)

=item $airespace->airespace_ap_loc()

User specified location of this AP.

(C<bsnAPLocation>)

=item $airespace->airespace_ap_sw()

(C<bsnAPSoftwareVersion>)

=item $airespace->airespace_ap_fw()

(C<bsnAPBootVersion>)

=item $airespace->airespace_ap_model()

(C<bsnAPModel>)

=item $airespace->airespace_ap_serial()

(C<bsnAPSerialNumber>)

=item $airespace->airespace_ap_type()

(C<bsnAPType>)

=item $airespace->airespace_ap_status()

(C<bsnAPAdminStatus>)

=back

=head2 AP Interface Table (C<bsnAPIfTable>)

Table of 802.11 interfaces in an Airespace APs.

=over

=item $airespace->airespace_apif_slot()

The slot Id of this interface. Value will be 0 for a 802.11a (5Ghz) interface
and will be 1 for 802.11b/g (2.4Ghz) interface.

(C<bsnAPIfSlotId>)

=item $airespace->airespace_apif_type()

(C<bsnAPIfType>)

=item $airespace->airespace_apif_ch_num()

(C<bsnAPIfPhyChannelNumber>)

=item $airespace->airespace_apif_power()

The transmit power level N currently being used to transmit data.

(C<bsnAPIfPhyTxPowerLevel>)

=item $airespace->airespace_apif()

(C<bsnAPIfOperStatus>)

=item $airespace->airespace_apif_oride()

This flag when disabled implies that all WLANs are available from this radio.
However, if this is enabled, then only those WLANs that appear in the
(C<bsnApIfWlanOverrideTable>) will be available from this radio.

(C<bsnAPIfWlanOverride>)

=item $airespace->airespace_apif_admin()

(C<bsnAPIfAdminStatus>)

=back

=head2 Mobile Station Table (C<bsnMobileStationTable>)

=over

=item $airespace->airespace_sta_mac()

Mac Address of the AP on which Mobile Station is associated.

(C<bsnMobileStationAPMacAddr>)

=item $airespace->airespace_sta_slot()

Slot Id of AP If on which mobile station is associated.

(C<bsnMobileStationAPIfSlotId>)

=item $airespace->airespace_sta_ess_idx()

Ess Index of the Wlan(SSID) that is being used by Mobile Station to connect
to the AP.

(C<bsnMobileStationEssIndex>)

=item $airespace->airespace_sta_ssid()

The SSID Advertised by the Mobile Station.

(C<bsnMobileStationSsid>)

=item $airespace->airespace_sta_delete()

Action to Deauthenticate the Mobile Station. Set the State to delete.

(C<bsnMobileStationDeleteAction>)

=back

=head2 Users Table (C<bsnUsersTable>)

The (conceptual) table listing Wlan Users.

=over

=item $airespace->airespace_user_name()

User name.  For MAC filters, this will be the MAC address (e.g. 000123456789).

(C<bsnUserName>)

=item $airespace->airespace_user_pw()

User Password.  For MAC filters, this will be "nopassword".

(C<bsnUserPassword>)

=item $airespace->airespace_user_ess_idx()

User WLAN ID. Value 0 implies that this applies to any WLAN ID.

(C<bsnUserEssIndex>)

=item $airespace->airespace_user_access()

For MAC filters, this will be "readOnly".

(C<bsnUserAccessMode>)

=item $airespace->airespace_user_type()

User Access Mode. For MAC filters, this will be "macFilter".

(C<bsnUserType>)

=item $airespace->airespace_user_ifname()

ACL for MAC Filters.  An interface name from C<agentInterfaceConfigTable>

(C<bsnUserInterfaceName>)

=item $airespace->airespace_user_rstat()

(C<bsnUserRowStatus>)

=back

=head2 Black List Client Table (C<bsnBlackListClientTable>)

The table listing Wlan Black Listed Clients

=over

=item $airespace->airespace_bl_mac()

(C<bsnBlackListClientMacAddress>)

=item $airespace->airespace_bl_descr()

(C<bsnBlackListClientDescription>)

=item $airespace->airespace_bl_rstat()

(C<bsnBlackListClientRowStatus>)

=back

=head2 AP Interface WLAN Override Table (C<bsnAPIfWlanOverrideTable>)

Each entry represents an SSID added to the AP when the attribute
C<bsnAPIfWlanOverride> on the radio is enabled.  This means only those WLANs
on the switch that are added to this table will be available on such a radio.

=over

=item $airespace->airespace_oride_id()

Index of the WLAN (C<bsnDot11EssIndex>) added to the radio.

(C<bsnAPIfWlanOverrideId>)

=item $airespace->airespace_oride_ssid()

SSID assigned to the override WLAN.

(C<bsnAPIfWlanOverrideSsid>)

=back

=head2 Interface Config Table (C<agentInterfaceConfigTable>)

A table of the switch's Interface Config entries. Typically, it will contain
entries	for Service Port Interface, DS Port Interface and Virtual Gateway
Interface apart from other entries.

=over

=item $airespace->airespace_if_name()

Interface Name. This values is 'management' for DS port, 'service-port' for
service port and 'virtual' for virtual gateway. For other interfaces, the
name can be anything. These interfaces are already created by default.

(C<agentInterfaceName>)

=item $airespace->airespace_if_vlan()

VLAN Id configured for the Interface.

(C<agentInterfaceVlanId>)

=item $airespace->airespace_if_type()

The interface's type. The static type is set for the interfaces that are
created by default on the switch and these cannot be deleted. Any other
interface that is created is of type dynamic which can be deleted.

(C<agentInterfaceType>)

=item $airespace->airespace_if_mac()

Interface MAC Address. This is only applicable in case of management and
service-port interfaces.

(C<agentInterfaceMacAddress>)

=item $airespace->airespace_if_ip()

(C<agentInterfaceIPAddress>)

=item $airespace->airespace_if_mask()

(C<agentInterfaceIPNetmask>)

=item $airespace->airespace_if_acl()

Name of the Access Control List applied to the interface. This attribute is
applicable only to the management interface and other dynamic interfaces.
If it is required to remove the ACL name for an interface, it should be set
to an empty string.

(C<agentInterfaceAclName>)

=item $airespace->airespace_if_rstat()

(C<agentInterfaceRowStatus>)

=back

=head2 Port Config Table (C<agentPortConfigTable>)

=over

=item $airespace->airespace_duplex_admin()

(C<agentPortPhysicalMode>)

=item $airespace->airespace_duplex()

(C<agentPortPhysicalStatus>)

=back

=head2 Overrides

=over

=item $airespace->i_index()

Returns reference to map of IIDs to Interface index. 

Extends C<ifIndex> to support thin APs and WLAN virtual interfaces as device
interfaces.

=item $airespace->interfaces()

Returns reference to map of IIDs to ports.  Thin APs are implemented as device 
interfaces.  The thin AP MAC address airespace_ap_mac() and Slot ID
airespace_apif_slot() are used as the port identifier.  Virtual interfaces
use airespace_if_name() as the port identifier.

=item $airespace->i_name()

Returns reference to map of IIDs to interface names.  Returns C<ifName> for
Ethernet interfaces, airespace_ap_name() for thin AP interfaces, and
airespace_if_name() for virtual interfaces.

=item $airespace->i_description()

Returns reference to map of IIDs to interface types.  Returns C<ifDescr>
for Ethernet interfaces, airespace_ap_loc() for thin AP interfaces, and
airespace_if_name() for virtual interfaces.

=item $airespace->i_type()

Returns reference to map of IIDs to interface descriptions.  Returns
C<ifType> for Ethernet interfaces, airespace_apif_type() for thin AP
interfaces, and airespace_if_type() for virtual interfaces.

=item $airespace->i_up()

Returns reference to map of IIDs to link status of the interface.  Returns
C<ifOperStatus> for Ethernet interfaces and airespace_apif() for thin AP
interfaces.

=item $airespace->i_up_admin()

Returns reference to map of IIDs to administrative status of the interface.
Returns C<ifAdminStatus> for Ethernet interfaces and airespace_apif_admin()
for thin AP interfaces.

=item $airespace->i_mac()

Returns reference to map of IIDs to MAC address of the interface.  Returns
C<ifPhysAddress> for Ethernet interfaces and airespace_if_mac() for virtual 
interfaces.

=item $airespace->i_vlan()

Returns reference to map of IIDs to VLAN ID of the interface.  Returns
airespace_if_vlan() for virtual interfaces.

=item $airespace->i_duplex()

Returns reference to map of IIDs to current link duplex.  Ethernet interfaces
only.

=item $airespace->i_duplex_admin()

Returns reference to hash of IIDs to admin duplex setting.  Ethernet
interfaces only.

=item $airespace->ip_index()

Extends table by mapping airespace_if_ip() to the interface IID.

=item $airespace->ip_netmask()

Extends IP table by mapping airespace_if_mask() to airespace_if_ip()

=item $airespace->bp_index()

Simulates bridge MIB by returning reference to a hash mapping i_index() to
the interface iid.

=item $airespace->fw_port()

Returns reference to a hash, value being airespace_sta_mac() and
airespace_sta_slot() combined to match the interface iid.  

=item $airespace->fw_mac()

(C<bsnMobileStationMacAddress>)

=back

=head2 Pseudo F<ENTITY-MIB> information

These methods emulate F<ENTITY-MIB> Physical Table methods using
F<AIRESPACE-SWITCHING-MIB> and F<AIRESPACE-WIRELESS-MIB>.  Thin APs are
included as subcomponents of the wireless controller.

=over

=item $airespace->e_index()

Returns reference to hash.  Key: IID and Value: Integer. The index for APs is
created with an integer representation of the last three octets of the
AP MAC address.

=item $airespace->e_class()

Returns reference to hash.  Key: IID, Value: General hardware type.  Return ap
for wireless access points.

=item $airespace->e_descr()

Returns reference to hash.  Key: IID, Value: Human friendly name.

=item $airespace->e_model()

Returns reference to hash.  Key: IID, Value: Model name.

=item $airespace->e_name()

More computer friendly name of entity.  Name is either 'WLAN Controller' or
'AP'.

=item $airespace->e_vendor()

Returns reference to hash.  Key: IID, Value: cisco.

=item $airespace->e_serial()

Returns reference to hash.  Key: IID, Value: Serial number.

=item $airespace->e_pos()

Returns reference to hash.  Key: IID, Value: The relative position among all
entities sharing the same parent.

=item $airespace->e_type()

Returns reference to hash.  Key: IID, Value: Type of component.

=item $airespace->e_fwver()

Returns reference to hash.  Key: IID, Value: Firmware revision.

=item $airespace->e_swver()

Returns reference to hash.  Key: IID, Value: Software revision.

=item $airespace->e_parent()

Returns reference to hash.  Key: IID, Value: The value of e_index() for the
entity which 'contains' this entity.

=back

=cut
