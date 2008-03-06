# SNMP::Info::Layer2::HP - SNMP Interface to HP ProCurve Switches
# Max Baker
#
# Copyright (c) 2004,2005 Max Baker changes from version 0.8 and beyond.
#
# Copyright (c) 2002,2003 Regents of the University of California
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the 
#       names of its contributors may be used to endorse or promote products 
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Layer2::HP;
$VERSION = '1.07';
# $Id: HP.pm,v 1.38 2007/12/02 03:02:01 jeneric Exp $

use strict;

use Exporter;
use SNMP::Info::Layer3;
use SNMP::Info::MAU;
use SNMP::Info::LLDP;
use SNMP::Info::CDP;

use vars qw/$VERSION $DEBUG %GLOBALS %MIBS %FUNCS %PORTSTAT %MODEL_MAP %MUNGE $INIT/ ;

@SNMP::Info::Layer2::HP::ISA = qw/SNMP::Info::Layer3 SNMP::Info::MAU SNMP::Info::LLDP
                                  SNMP::Info::CDP Exporter/;
@SNMP::Info::Layer2::HP::EXPORT_OK = qw//;

%MIBS = ( %SNMP::Info::Layer3::MIBS,
          %SNMP::Info::MAU::MIBS,
          %SNMP::Info::LLDP::MIBS,
          %SNMP::Info::CDP::MIBS,
          'RFC1271-MIB'    => 'logDescription',
          'HP-ICF-OID'     => 'hpSwitch4000',
          'HP-VLAN'        => 'hpVlanMemberIndex',
          'STATISTICS-MIB' => 'hpSwitchCpuStat',
          'NETSWITCH-MIB'  => 'hpMsgBufFree',
          'CONFIG-MIB'     => 'hpSwitchConfig',
          'SEMI-MIB'       => 'hpHttpMgSerialNumber',
          'HP-ICF-CHASSIS' => 'hpicfSensorObjectId',
        );

%GLOBALS = (
            %SNMP::Info::Layer3::GLOBALS,
            %SNMP::Info::MAU::GLOBALS,
            %SNMP::Info::LLDP::GLOBALS,
            %SNMP::Info::CDP::GLOBALS,
            'serial1'      => 'entPhysicalSerialNum.1',
            'serial2'      => 'hpHttpMgSerialNumber.0',
            'hp_cpu'       => 'hpSwitchCpuStat.0',
            'hp_mem_total' => 'hpGlobalMemTotalBytes.1',
            'mem_free'     => 'hpGlobalMemFreeBytes.1',
            'mem_used'     => 'hpGlobalMemAllocBytes.1',
            'os_version'   => 'hpSwitchOsVersion.0',
            'os_bin'       => 'hpSwitchRomVersion.0',
            'mac'          => 'hpSwitchBaseMACAddress.0',
            'hp_vlans'     => 'hpVlanNumber',
           );

%FUNCS   = (
            %SNMP::Info::Layer3::FUNCS,
            %SNMP::Info::MAU::FUNCS,
            %SNMP::Info::LLDP::FUNCS,
            %SNMP::Info::CDP::FUNCS,
            'bp_index2' => 'dot1dBasePortIfIndex',
            'i_type2'   => 'ifType',
            # RFC1271
            'l_descr'   => 'logDescription',
            # HP-VLAN-MIB
            'hp_v_index'   => 'hpVlanDot1QID',
            'hp_v_name'    => 'hpVlanIdentName',
            'hp_v_state'   => 'hpVlanIdentState',
            'hp_v_type'    => 'hpVlanIdentType',
            'hp_v_status'  => 'hpVlanIdentStatus',
            'hp_v_mac'     => 'hpVlanAddrPhysAddress',
            'hp_v_if_index'=> 'hpVlanMemberIndex',
            'hp_v_if_tag'  => 'hpVlanMemberTagged2',
            # CONFIG-MIB::hpSwitchPortTable
            'hp_duplex'       => 'hpSwitchPortEtherMode',
            'hp_duplex_admin' => 'hpSwitchPortFastEtherMode',
             # HP-ICF-CHASSIS
             'hp_s_oid'     => 'hpicfSensorObjectId',
             'hp_s_name'    => 'hpicfSensorDescr',
             'hp_s_status'  => 'hpicfSensorStatus',
           );

%MUNGE = (
            # Inherit all the built in munging
            %SNMP::Info::Layer3::MUNGE,
            %SNMP::Info::MAU::MUNGE,
            %SNMP::Info::LLDP::MUNGE,
            %SNMP::Info::CDP::MUNGE,
            'c_port' => \&munge_hp_c_port,
            'c_id'   => \&munge_hp_c_id,
         );

%MODEL_MAP = ( 
                'J4093A' => '2424M',
                'J4110A' => '8000M',
                'J4120A' => '1600M',
                'J4121A' => '4000M',
                'J4122A' => '2400M',
                'J4122B' => '2424M',
                'J4138A' => '9308M',
                'J4139A' => '9304M',
                'J4812A' => '2512',
                'J4813A' => '2524',
                'J4815A' => '3324XL',
                'J4819A' => '5308XL',
                'J4840A' => '6308M-SX',
                'J4841A' => '6208M-SX',
                'J4850A' => '5304XL',
                'J4851A' => '3124',
                'J4865A' => '4108GL',
                'J4874A' => '9315M',
                'J4887A' => '4104GL',
                'J4899A' => '2650',
                'J4899B' => '2650-CR',
                'J4900A' => '2626',
                'J4900B' => '2626-CR',
                'J4902A' => '6108',
                'J4903A' => '2824',
                'J4904A' => '2848',
                'J4905A' => '3400cl-24G',
                'J4906A' => '3400cl-48G',
                'J8130A' => 'WAP-420-NA',
                'J8131A' => 'WAP-420-WW',
                'J8133A' => 'AP520WL',
                'J8164A' => '2626-PWR',
                'J8165A' => '2650-PWR',
                'J8433A' => 'CX4-6400cl-6XG',
                'J8474A' => 'MF-6400cl-6XG',
                'J8680A' => '9608sl',
                'J8692A' => '3500yl-24G-PWR',
                'J8693A' => '3500yl-48G-PWR',
                'J8697A' => '5406zl',
                'J8698A' => '5412zl',
                'J8718A' => '5404yl',
                'J8719A' => '5408yl',
                'J8770A' => '4204vl',
                'J8771A' => '4202vl-48G',
                'J8772A' => '4202vl-72',
                'J8773A' => '4208vl',
                'J8762A' => '2600-8-PWR',
                'J8992A' => '6200yl-24G',
                'J9019A' => '2510-24A',
                'J9020A' => '2510-48A',
                'J9021A' => '2810-24G',
                'J9022A' => '2810-48G',
                'J9028A' => '1800-24G',
                'J9029A' => '1800-8G',
                'J9050A' => '2900-48G',
                'J9049A' => '2900-24G',
                'J9032A' => '4202vl-68G',
                'J9091A' => '8212zl',
           );

# Method Overrides

sub cpu {
    my $hp = shift;
    return $hp->hp_cpu();
}

sub mem_total {
    my $hp = shift;
    return $hp->hp_mem_total();
}

sub os {
    return 'hp';
}
sub os_ver {
    my $hp = shift;
    my $os_version = $hp->os_version();
    return $os_version if defined $os_version;
    # Some older ones don't have this value,so we cull it from the description
    my $descr = $hp->description();
    if ($descr =~ m/revision ([A-Z]{1}\.\d{2}\.\d{2})/) {
        return $1;
    }
    return undef;
}

# Lookup model number, and translate the part number to the common number
sub model {
    my $hp = shift;
    my $id = $hp->id();
    return undef unless defined $id;
    my $model = &SNMP::translateObj($id);
    return $id unless defined $model;
    
    $model =~ s/^hpswitch//i;

    return defined $MODEL_MAP{$model} ? $MODEL_MAP{$model} : $model;
}

# Some have the serial in entity mib, some have it in SEMI-MIB::hphttpmanageable
sub serial {
    my $hp = shift;

    my $serial = $hp->serial1() || $hp->serial2() || undef;

    return $serial; 
}

sub interfaces {
    my $hp = shift;
    my $interfaces = $hp->i_index();
    my $i_descr    = $hp->i_description(); 

    my %if;
    foreach my $iid (keys %$interfaces){
        my $descr = $i_descr->{$iid};
        next unless defined $descr;
        $if{$iid} = $descr if (defined $descr and length $descr);
    }

    return \%if

}

sub i_name {
    my $hp = shift;
    my $i_alias    = $hp->i_alias();
    my $e_name     = $hp->e_name();
    my $e_port     = $hp->e_port();

    my %i_name;

    foreach my $port (keys %$e_name){
        my $iid = $e_port->{$port};
        next unless defined $iid;
        my $alias = $i_alias->{$iid};
        next unless defined $iid;
        $i_name{$iid} = $e_name->{$port};

        # Check for alias
        $i_name{$iid} = $alias if (defined $alias and length($alias));
    }
    
    return \%i_name;
}

sub i_duplex {
    my $hp = shift;

    return $hp->mau_i_duplex();
}

sub i_duplex_admin {
    my $hp = shift;
    my $partial = shift;

    # Try HP MIB first
    my $hp_duplex = $hp->hp_duplex_admin($partial);
    if (defined $hp_duplex and scalar(keys %$hp_duplex)){

        my %i_duplex;
        foreach my $if (keys %$hp_duplex){
            my $duplex = $hp_duplex->{$if};
            next unless defined $duplex; 
    
            $duplex = 'half' if $duplex =~ /half/i;
            $duplex = 'full' if $duplex =~ /full/i;
            $duplex = 'auto' if $duplex =~ /auto/i;
            $i_duplex{$if}=$duplex; 
        }
        return \%i_duplex;
    }
    else {
        return $hp->mau_i_duplex_admin();
    }
}

sub vendor {
    return 'hp';
}

sub log {
    my $hp=shift;

    my $log = $hp->l_descr();

    my $logstring = undef;

    foreach my $val (values %$log){
        next if $val =~ /^Link\s+(Up|Down)/;
        $logstring .= "$val\n"; 
    }

    return $logstring; 
}

sub slots {
    my $hp=shift;
    
    my $e_name = $hp->e_name();

    return undef unless defined $e_name;

    my $slots;
    foreach my $slot (keys %$e_name) {
        $slots++ if $e_name->{$slot} =~ /slot/i;
    }

    return $slots;
}

sub fan {
    my $hp = shift;
    return &sensor($hp, 'fan');
}

sub ps1_status {
    my $hp = shift;
    return &sensor($hp, 'power', '^power supply 1') || &sensor($hp, 'power', '^power supply sensor');
}

sub ps2_status {
    my $hp = shift;
    return &sensor($hp, 'power', '^power supply 2') || &sensor($hp, 'power', '^redundant');
}

sub sensor {
    my $hp = shift;
    my $search_type = shift || 'fan';
    my $search_name = shift || '';
    my $hp_s_oid = $hp->hp_s_oid();
    my $result;
    foreach my $sensor (keys %$hp_s_oid) {
        my $sensortype = &SNMP::translateObj($hp_s_oid->{$sensor});
        if ($sensortype =~ /$search_type/i) {
            my $sensorname = $hp->hp_s_name()->{$sensor};
            my $sensorstatus = $hp->hp_s_status()->{$sensor};
            if ($sensorname =~ /$search_name/i) {
                $result = $sensorstatus;
            }
        }
    }
    return $result;
}

# Bridge MIB does not map Bridge Port to ifIndex correctly on all models
sub bp_index {
    my $hp = shift;
    my $partial = shift;

    my $if_index = $hp->i_index($partial);
    my $model = $hp->model();
    my $bp_index = $hp->bp_index2($partial);
    
    unless (defined $model and $model =~ /(1600|2424|4000|8000)/) {
        return $bp_index;
    }

    my %mod_bp_index;
    foreach my $iid (keys %$if_index){
        $mod_bp_index{$iid} = $iid;
    }
    return \%mod_bp_index;
}

# VLAN methods.  Newer HPs use Q-BRIDGE, older use proprietary MIB.  Use
# Q-BRIDGE if available.

sub v_index {
    my $hp = shift;
    my $partial = shift;

    # Newer devices
    my $q_index = $hp->SUPER::v_index($partial);
    if (defined $q_index and scalar(keys %$q_index)){
        return $q_index;
    }

    # Older devices
    return $hp->hp_v_index($partial);
}

sub v_name {
    my $hp = shift;
    my $partial = shift;

    # Newer devices
    my $q_name = $hp->SUPER::v_name($partial);
    if (defined $q_name and scalar(keys %$q_name)){
        return $q_name;
    }

    # Older devices
    return $hp->hp_v_name($partial);
}

sub i_vlan {
    my $hp = shift;

    # Newer devices use Q-BRIDGE-MIB
    my $qb_i_vlan = $hp->SUPER::i_vlan();
    if (defined $qb_i_vlan and scalar(keys %$qb_i_vlan)){
        return $qb_i_vlan;
    }

    # HP4000 ... get it from HP-VLAN
    # the hpvlanmembertagged2 table has an entry in the form of 
    #   vlan.interface = /untagged/no/tagged/auto
    my $i_vlan      = {};
    my $hp_v_index  = $hp->hp_v_index();
    my $hp_v_if_tag = $hp->hp_v_if_tag();
    foreach my $row (keys %$hp_v_if_tag){
        my ($index,$if) = split(/\./,$row);

        my $tag = $hp_v_if_tag->{$row};
        my $vlan = $hp_v_index->{$index};
        
        next unless (defined $tag and $tag =~ /untagged/);

        $i_vlan->{$if} = $vlan if defined $vlan;
    }

    return $i_vlan;
}

sub i_vlan_membership {
    my $hp = shift;

    # Newer devices use Q-BRIDGE-MIB
    my $qb_i_vlan = $hp->SUPER::i_vlan_membership();
    if (defined $qb_i_vlan and scalar(keys %$qb_i_vlan)){
        return $qb_i_vlan;
    }

    # Older get it from HP-VLAN
    my $i_vlan_membership = {};
    my $hp_v_index  = $hp->hp_v_index();
    my $hp_v_if_tag = $hp->hp_v_if_tag();
    foreach my $row (keys %$hp_v_if_tag){
        my ($index,$if) = split(/\./,$row);

        my $tag = $hp_v_if_tag->{$row};
        my $vlan = $hp_v_index->{$index};
        
        next unless (defined $tag);
        next if ($tag eq 'no');

        push(@{$i_vlan_membership->{$if}}, $vlan);
    }

    return $i_vlan_membership;
}

sub set_i_vlan {
    my $hp = shift;
    my ($vlan, $ifindex) = @_;

    unless ( defined $vlan and defined $ifindex and
            $vlan =~ /^\d+$/ and $ifindex =~ /^\d+$/ ) {
        $hp->error_throw("Invalid parameter");
        return undef;
    }

    # Newer devices use Q-BRIDGE-MIB
    my $qb_i_vlan = $hp->qb_i_vlan_t();
    if (defined $qb_i_vlan and scalar(keys %$qb_i_vlan)){
        return $hp->SUPER::set_i_vlan($vlan, $ifindex);
    } # We're done here if the device supports the Q-BRIDGE-MIB

    # Older HP switches use the HP-VLAN MIB
    # Thanks to Jeroen van Ingen
    my $hp_v_index  = $hp->hp_v_index();
    my $hp_v_if_tag = $hp->hp_v_if_tag();
    if (defined $hp_v_index and scalar(keys %$hp_v_index)){
        my $old_untagged;
        # Hash to lookup VLAN index of the VID (dot1q tag)
        my %vl_trans = reverse %$hp_v_index;

        foreach my $row (keys %$hp_v_if_tag){
            # Loop through table to determine current untagged vlan for the port we're about to change
            my ($index,$if) = split(/\./,$row);
            if ($if == $ifindex and $hp_v_if_tag->{$row} =~ /untagged/) {
                # Store the row information of the current untagged VLAN and temporarily set it to tagged
                $old_untagged = $row;
                my $rv = $hp->set_hp_v_if_tag(1, $row);
                warn "Unexpected error changing native/untagged VLAN into tagged.\n" unless $rv;
                last;
            }
        }

        # Translate the VLAN identifier (tag) value to the index used by the HP-VLAN MIB
        my $vlan_index = $vl_trans{$vlan};
        if (defined $vlan_index) {
            # Set our port untagged in the desired VLAN
            my $rv = $hp->set_hp_v_if_tag(2, "$vlan_index.$ifindex");
            if ($rv) {
                # If port change is successful, remove VLAN that used to be untagged from the port
                $hp->set_hp_v_if_tag(3, $old_untagged) if defined $old_untagged;
                return $rv;
            } else {
                # If not, try to revert to the old situation.
                $hp->set_hp_v_if_tag(2, $old_untagged) if defined $old_untagged;
            }
        }
        else {
            warn "Requested VLAN (VLAN ID: $vlan) not found!\n";
        }
    }
    print "Error: Unable to change VLAN: $vlan on IfIndex: $ifindex list\n" if $hp->debug();
    return undef;
}

sub set_i_pvid {
    my $hp = shift;
    my ($vlan, $ifindex) = @_;

    unless ( defined $vlan and defined $ifindex and
            $vlan =~ /^\d+$/ and $ifindex =~ /^\d+$/ ) {
        $hp->error_throw("Invalid parameter");
        return undef;
    }

    # Newer devices use Q-BRIDGE-MIB
    my $qb_i_vlan = $hp->qb_i_vlan_t();
    if (defined $qb_i_vlan and scalar(keys %$qb_i_vlan)){
        return $hp->SUPER::set_i_pvid($vlan, $ifindex);
    }
    
    # HP method same as set_i_vlan()
    return $hp->set_i_vlan($vlan, $ifindex);
}

sub set_add_i_vlan_tagged {
    my $hp = shift;
    my ($vlan, $ifindex) = @_;

    unless ( defined $vlan and defined $ifindex and
            $vlan =~ /^\d+$/ and $ifindex =~ /^\d+$/ ) {
        $hp->error_throw("Invalid parameter");
        return undef;
    }

    # Newer devices use Q-BRIDGE-MIB
    my $qb_i_vlan = $hp->qb_i_vlan();
    if (defined $qb_i_vlan and scalar(keys %$qb_i_vlan)){
        return $hp->SUPER::set_add_i_vlan_tagged($vlan, $ifindex);
    } # We're done here if the device supports the Q-BRIDGE-MIB

    # Older HP switches use the HP-VLAN MIB
    my $hp_v_index  = $hp->hp_v_index();
    my $hp_v_if_tag = $hp->hp_v_if_tag();
    if (defined $hp_v_index and scalar(keys %$hp_v_index)){
        # Hash to lookup VLAN index of the VID (dot1q tag)
        my %vl_trans = reverse %$hp_v_index;

        # Translate the VLAN identifier (tag) value to the index used by the HP-VLAN MIB
        my $vlan_index = $vl_trans{$vlan};
        if (defined $vlan_index) {
            # Add port to egress list for VLAN
            my $rv = ($hp->set_hp_v_if_tag(1, "$vlan_index.$ifindex"));
            if ($rv) {
                print "Successfully added IfIndex: $ifindex to VLAN: $vlan list\n" if $hp->debug();
                return 1;
            }
        }
        else {
            $hp->error_throw("Requested VLAN (VLAN ID: $vlan) not found!\n");
        }
    }
    print "Error: Unable to add VLAN: $vlan to IfIndex: $ifindex list\n" if $hp->debug();
    return undef;
}

sub set_remove_i_vlan_tagged {
    my $hp = shift;
    my ($vlan, $ifindex) = @_;

    unless ( defined $vlan and defined $ifindex and
            $vlan =~ /^\d+$/ and $ifindex =~ /^\d+$/ ) {
        $hp->error_throw("Invalid parameter");
        return undef;
    }

    # Newer devices use Q-BRIDGE-MIB
    my $qb_i_vlan = $hp->qb_i_vlan();
    if (defined $qb_i_vlan and scalar(keys %$qb_i_vlan)){
        return $hp->SUPER::set_remove_i_vlan_tagged($vlan, $ifindex);
    } # We're done here if the device supports the Q-BRIDGE-MIB

    # Older HP switches use the HP-VLAN MIB
    my $hp_v_index  = $hp->hp_v_index();
    my $hp_v_if_tag = $hp->hp_v_if_tag();
    if (defined $hp_v_index and scalar(keys %$hp_v_index)){
        # Hash to lookup VLAN index of the VID (dot1q tag)
        my %vl_trans = reverse %$hp_v_index;

        # Translate the VLAN identifier (tag) value to the index used by the HP-VLAN MIB
        my $vlan_index = $vl_trans{$vlan};
        if (defined $vlan_index) {
            # Add port to egress list for VLAN
            my $rv = ($hp->set_hp_v_if_tag(3, "$vlan_index.$ifindex"));
            if ($rv) {
                print "Successfully added IfIndex: $ifindex to VLAN: $vlan list\n" if $hp->debug();
                return 1;
            }
        }
        else {
            $hp->error_throw("Requested VLAN (VLAN ID: $vlan) not found!\n");
        }
    }
    print "Error: Unable to remove VLAN: $vlan to IfIndex: $ifindex list\n" if $hp->debug();
    return undef;
}

#  Use CDP and/or LLDP

sub hasCDP {
    my $hp = shift;

    return $hp->hasLLDP() || $hp->SUPER::hasCDP();
}

sub c_ip {
    my $hp = shift;
    my $partial = shift;

    my $cdp  = $hp->SUPER::c_ip($partial) || {};
    my $lldp = $hp->lldp_ip($partial) || {};

    my %c_ip;
    foreach my $iid (keys %$cdp){
        my $ip = $cdp->{$iid};
        next unless defined $ip;

        $c_ip{$iid} = $ip;
    }

    foreach my $iid (keys %$lldp){
        my $ip = $lldp->{$iid};
        next unless defined $ip;

        $c_ip{$iid} = $ip;
    }
    return \%c_ip;
}

sub c_if {
    my $hp = shift;
    my $partial = shift;

    my $lldp = $hp->lldp_if($partial) || {};;
    my $cdp  = $hp->SUPER::c_if($partial) || {};
    
    my %c_if;
    foreach my $iid (keys %$cdp){
        my $if = $cdp->{$iid};
        next unless defined $if;

        $c_if{$iid} = $if;
    }

    foreach my $iid (keys %$lldp){
        my $if = $lldp->{$iid};
        next unless defined $if;

        $c_if{$iid} = $if;
    }
    return \%c_if;
}

sub c_port {
    my $hp = shift;
    my $partial = shift;

    my $lldp = $hp->lldp_port($partial) || {};
    my $cdp  = $hp->SUPER::c_port($partial) || {};
    
    my %c_port;
     foreach my $iid (keys %$cdp){
         my $port = $cdp->{$iid};
         next unless defined $port;
         $c_port{$iid} = $port;
     }

    foreach my $iid (keys %$lldp){
        my $port = $lldp->{$iid};
        next unless defined $port;
        $c_port{$iid} = $port;
    }
    return \%c_port;
}

sub munge_hp_c_port {
    my ($v) = @_;
    if ( length(unpack('H*', $v)) == 12 ){
	return join(':',map { sprintf "%02x", $_ } unpack('C*', $v));
    }else{
	return $v;
    }
}

sub c_id {
    my $hp = shift;
    my $partial = shift;

    my $lldp = $hp->lldp_id($partial) || {};
    my $cdp  = $hp->SUPER::c_id($partial) || {};

    my %c_id;
    foreach my $iid (keys %$cdp){
	my $id = $cdp->{$iid};
	next unless defined $id;
	$c_id{$iid} = $id;
    }
    
   foreach my $iid (keys %$lldp){
       my $id = $lldp->{$iid};
       next unless defined $id;
       $c_id{$iid} = $id;
   }
    return \%c_id;
}

sub munge_hp_c_id {
    my ($v) = @_;
    if ( length(unpack('H*', $v)) == 12 ){
	return join(':',map { sprintf "%02x", $_ } unpack('C*', $v));
    }if ( length(unpack('H*', $v)) == 10 ){
	# IP address (first octet is sign, I guess)
	my @octets = (map { sprintf "%02x",$_ } unpack('C*', $v))[1..4];
	return join '.', map { hex($_) } @octets;
    }else{
	return $v;
    }
}

sub c_platform {
    my $hp = shift;
    my $partial = shift;

    my $lldp = $hp->lldp_rem_sysdesc($partial) || {};
    my $cdp  = $hp->SUPER::c_platform($partial) || {};

    my %c_platform;
    foreach my $iid (keys %$cdp){
        my $platform = $cdp->{$iid};
        next unless defined $platform;

        $c_platform{$iid} = $platform;
    }

    foreach my $iid (keys %$lldp){
        my $platform = $lldp->{$iid};
        next unless defined $platform;

        $c_platform{$iid} = $platform;
    }
    return \%c_platform;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer2::HP - SNMP Interface to HP Procurve Switches

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $hp = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $hp->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
HP ProCurve Switch via SNMP. 

Note:  Some HP Switches will connect via SNMP version 1, but a lot of config data will 
not be available.  Make sure you try and connect with Version 2 first, and then fail back
to version 1.

For speed or debugging purposes you can call the subclass directly, but not after determining
a more specific class using the method above. 

 my $hp = new SNMP::Info::Layer2::HP(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=item SNMP::Info::LLDP

=item SNMP::Info::MAU

=back

=head2 Required MIBs

=over

=item RFC1271-MIB

Included in V2 mibs from Cisco

=item HP-ICF-OID

=item HP-VLAN

(this MIB new with SNMP::Info 0.8)

=item STATISTICS-MIB

=item NETSWITCH-MIB

=item CONFIG-MIB

=back

The last five MIBs listed are from HP and can be found at L<http://www.hp.com/rnd/software>
or L<http://www.hp.com/rnd/software/MIBs.htm>

=head1 ChangeLog

Version 0.4 - Removed ENTITY-MIB e_*() methods to separate sub-class - SNMP::Info::Entity

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $hp->cpu()

Returns CPU Utilization in percentage.

=item $hp->log()

Returns all the log entries from the switch's log that are not Link up or down messages.

=item $hp->mem_free()

Returns bytes of free memory

=item $hp->mem_total()

Return bytes of total memory

=item $hp->mem_used()

Returns bytes of used memory

=item $hp->model()

Returns the model number of the HP Switch.  Will translate between the HP Part number and 
the common model number with this map :

 %MODEL_MAP = ( 
                'J4093A' => '2424M',
                'J4110A' => '8000M',
                'J4120A' => '1600M',
                'J4121A' => '4000M',
                'J4122A' => '2400M',
                'J4122B' => '2424M',
                'J4138A' => '9308M',
                'J4139A' => '9304M',
                'J4812A' => '2512',
                'J4813A' => '2524',
                'J4815A' => '3324XL',
                'J4819A' => '5308XL',
                'J4840A' => '6308M-SX',
                'J4841A' => '6208M-SX',
                'J4850A' => '5304XL',
                'J4851A' => '3124',
                'J4865A' => '4108GL',
                'J4874A' => '9315M',
                'J4887A' => '4104GL',
                'J4899A' => '2650',
                'J4899B' => '2650-CR',
                'J4900A' => '2626',
                'J4900B' => '2626-CR',
                'J4902A' => '6108',
                'J4903A' => '2824',
                'J4904A' => '2848',
                'J4905A' => '3400cl-24G',
                'J4906A' => '3400cl-48G',
                'J8130A' => 'WAP-420-NA',
                'J8131A' => 'WAP-420-WW',
                'J8133A' => 'AP520WL',
                'J8164A' => '2626-PWR',
                'J8165A' => '2650-PWR',
                'J8433A' => 'CX4-6400cl-6XG',
                'J8474A' => 'MF-6400cl-6XG',
                'J8680A' => '9608sl',
                'J8692A' => '3500yl-24G-PWR',
                'J8693A' => '3500yl-48G-PWR',
                'J8697A' => '5406zl',
                'J8698A' => '5412zl',
                'J8718A' => '5404yl',
                'J8719A' => '5408yl',
                'J8770A' => '4204vl',
                'J8771A' => '4202vl-48G',
                'J8772A' => '4202vl-72',
                'J8773A' => '4208vl',
                'J8762A' => '2600-8-PWR',
                'J8992A' => '6200yl-24G',
                'J9019A' => '2510-24A',
                'J9020A' => '2510-48A',
                'J9021A' => '2810-24G',
                'J9022A' => '2810-48G',
                'J9028A' => '1800-24G',
                'J9029A' => '1800-8G',
                'J9050A' => '2900-48G',
                'J9049A' => '2900-24G',
                'J9032A' => '4202vl-68G',
                'J9091A' => '8212zl',
                );

=item $hp->os()

Returns hp

=item $hp->os_bin()

B<hpSwitchRomVersion.0>

=item $hp->os_ver()

Tries to use os_version() and if that fails will try and cull the version from
the description field.

=item $hp->os_version()

B<hpSwitchOsVersion.0>

=item $hp->serial()

Returns serial number if available through SNMP

=item $hp->slots()

Returns number of entries in $hp->e_name that have 'slot' in them.

=item $hp->vendor()

hp

=back

=head2 Globals imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::MAU

See documentation in L<SNMP::Info::MAU/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $hp->interfaces() 

Uses $hp->i_description()

=item $hp->i_duplex()

Returns reference to map of IIDs to current link duplex.

=item $hp->i_duplex_admin()

Returns reference to hash of IIDs to admin duplex setting.

=item $hp->i_name()

Crosses i_name() with $hp->e_name() using $hp->e_port() and i_alias()

=item $hp->i_vlan()

Returns a mapping between ifIndex and the PVID (default VLAN) or untagged
port when using HP-VLAN.

Looks in Q-BRIDGE-MIB first (L<SNMP::Info::Bridge/"TABLE METHODS">) and for
older devices looks in HP-VLAN.

=item $hp->i_vlan_membership()

Returns reference to hash of arrays: key = ifIndex, value = array of VLAN IDs.
These are the VLANs which are members of the egress list for the port.  It
is the union of tagged, untagged, and auto ports when using HP-VLAN.

Looks in Q-BRIDGE-MIB first (L<SNMP::Info::Bridge/"TABLE METHODS">) and for
older devices looks in HP-VLAN.

  Example:
  my $interfaces = $hp->interfaces();
  my $vlans      = $hp->i_vlan_membership();
  
  foreach my $iid (sort keys %$interfaces) {
    my $port = $interfaces->{$iid};
    my $vlan = join(',', sort(@{$vlans->{$iid}}));
    print "Port: $port VLAN: $vlan\n";
  }

=item $hp->bp_index()

Returns reference to hash of bridge port table entries map back to interface identifier (iid)

Returns (B<ifIndex>) for both key and value for 1600, 2424, 4000, and 8000 models
since they seem to have problems with BRIDGE-MIB

=back

=head2 Topology information

Based upon the firmware version HP devices may support Cisco Discovery
Protocol (CDP), Link Layer Discovery Protocol (LLDP), or both.  These methods
will query both and return the combination of all information.  As a result,
there may be identical topology information returned from the two protocols
causing duplicate entries.  It is the calling program's responsibility to
identify any duplicate entries and de-duplicate if necessary.

=over

=item $hp->hasCDP()

Returns true if the device is running either CDP or LLDP.

=item $hp->c_if()

Returns reference to hash.  Key: iid Value: local device port (interfaces)

=item $hp->c_ip()

Returns reference to hash.  Key: iid Value: remote IPv4 address

If multiple entries exist with the same local port, c_if(), with the same IPv4
address, c_ip(), it may be a duplicate entry.

If multiple entries exist with the same local port, c_if(), with different IPv4
addresses, c_ip(), there is either a non-CDP/LLDP device in between two or
more devices or multiple devices which are not directly connected.  

Use the data from the Layer2 Topology Table below to dig deeper.

=item $hp->c_port()

Returns reference to hash. Key: iid Value: remote port (interfaces)

=item $hp->c_id()

Returns reference to hash. Key: iid Value: string value used to identify the
chassis component associated with the remote system.

=item $hp->c_platform()

Returns reference to hash.  Key: iid Value: Remote Device Type

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::MAU

See documentation in L<SNMP::Info::MAU/"TABLE METHODS"> for details.

=head1 SET METHODS

These are methods that provide SNMP set functionality for overridden methods or
provide a simpler interface to complex set operations.  See
L<SNMP::Info/"SETTING DATA VIA SNMP"> for general information on set operations. 

=over

=item $hp->set_i_vlan(vlan, ifIndex)

Changes an untagged port VLAN, must be supplied with the numeric VLAN
ID and port ifIndex.  This method will modify the port's VLAN membership.
This method should only be used on end station (non-trunk) ports.

  Example:
  my %if_map = reverse %{$hp->interfaces()};
  $hp->set_i_vlan('2', $if_map{'1.1'}) 
    or die "Couldn't change port VLAN. ",$hp->error(1);

=item $hp->set_i_pvid(pvid, ifIndex)

Sets port PVID or default VLAN, must be supplied with the numeric VLAN ID and
port ifIndex.  This method only changes the PVID, to modify an access (untagged)
port use set_i_vlan() instead.

  Example:
  my %if_map = reverse %{$hp->interfaces()};
  $hp->set_i_pvid('2', $if_map{'1.1'}) 
    or die "Couldn't change port PVID. ",$hp->error(1);

=item $hp->set_add_i_vlan_tagged(vlan, ifIndex)

Adds the port to the egress list of the VLAN, must be supplied with the numeric
VLAN ID and port ifIndex.

  Example:
  my %if_map = reverse %{$hp->interfaces()};
  $hp->set_add_i_vlan_tagged('2', $if_map{'1.1'}) 
    or die "Couldn't add port to egress list. ",$hp->error(1);

=item $hp->set_remove_i_vlan_tagged(vlan, ifIndex)

Removes the port from the egress list of the VLAN, must be supplied with the
numeric VLAN ID and port ifIndex.

  Example:
  my %if_map = reverse %{$hp->interfaces()};
  $hp->set_remove_i_vlan_tagged('2', $if_map{'1.1'}) 
    or die "Couldn't add port to egress list. ",$hp->error(1);

=cut
