# SNMP::Info::Layer3::Passport
# $Id: Passport.pm,v 1.34 2008/08/02 03:21:47 jeneric Exp $
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

package SNMP::Info::Layer3::Passport;

use strict;
use Exporter;
use SNMP::Info::SONMP;
use SNMP::Info::RapidCity;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::Passport::ISA
    = qw/SNMP::Info::SONMP SNMP::Info::RapidCity
    SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Passport::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %FUNCS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS, %SNMP::Info::RapidCity::MIBS,
    %SNMP::Info::SONMP::MIBS,
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS, %SNMP::Info::RapidCity::GLOBALS,
    %SNMP::Info::SONMP::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS, %SNMP::Info::RapidCity::FUNCS,
    %SNMP::Info::SONMP::FUNCS,
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE, %SNMP::Info::RapidCity::MUNGE,
    %SNMP::Info::SONMP::MUNGE,
);

sub model {
    my $passport = shift;
    my $id       = $passport->id();

    unless ( defined $id ) {
        print
            " SNMP::Info::Layer3::Passport::model() - Device does not support sysObjectID\n"
            if $passport->debug();
        return;
    }

    my $model = &SNMP::translateObj($id);

    return $id unless defined $model;

    $model =~ s/^rcA//i;
    return $model;
}

sub vendor {
    return 'nortel';
}

sub os {
    return 'passport';
}

sub os_ver {
    my $passport = shift;
    my $descr    = $passport->description();
    return unless defined $descr;

    #ERS / Passport
    if ( $descr =~ m/(\d+\.\d+\.\d+\.\d+)/ ) {
        return $1;
    }

    #Accelar
    if ( $descr =~ m/(\d+\.\d+\.\d+)/ ) {
        return $1;
    }
    return;
}

sub i_index {
    my $passport = shift;
    my $partial  = shift;

    my $i_index = $passport->orig_i_index($partial);
    my $model   = $passport->model();

    my %if_index;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        $if_index{$iid} = $index;
    }

    # Get VLAN Virtual Router Interfaces
    if (!defined $partial
        or (defined $model
            and (  ( $partial > 2000 and $model =~ /(86|83|81|16)/ )
                or ( $partial > 256 and $model =~ /(105|11[05]0|12[05])/ ) )
        )
        )
    {

        my $vlan_index = $passport->rc_vlan_if() || {};

        foreach my $vid ( keys %$vlan_index ) {
            my $v_index = $vlan_index->{$vid};
            next unless defined $v_index;
            next if $v_index == 0;
            next if ( defined $partial and $v_index !~ /^$partial$/ );

            $if_index{$v_index} = $v_index;
        }
    }

    if ( defined $model and $model =~ /(86)/ ) {

        my $cpu_index = $passport->rc_cpu_ifindex($partial) || {};
        my $virt_ip = $passport->rc_virt_ip();

        # Get CPU Ethernet Interfaces
        foreach my $cid ( keys %$cpu_index ) {
            my $c_index = $cpu_index->{$cid};
            next unless defined $c_index;
            next if $c_index == 0;

            $if_index{$c_index} = $c_index;
        }

        # Check for Virtual Mgmt Interface
        unless ( $virt_ip eq '0.0.0.0' ) {

            # Make up an index number, 1 is not reserved AFAIK
            $if_index{1} = 1;
        }
    }
    return \%if_index;
}

sub interfaces {
    my $passport = shift;
    my $partial  = shift;

    my $i_index      = $passport->i_index($partial);
    my $model        = $passport->model();
    my $index_factor = $passport->index_factor();
    my $port_offset  = $passport->port_offset();
    my $vlan_index   = {};
    my %reverse_vlan;
    my $vlan_id = {};

    if (!defined $partial
        or (defined $model
            and (  ( $partial > 2000 and $model =~ /(86|83|81|16)/ )
                or ( $partial > 256 and $model =~ /(105|11[05]0|12[05])/ ) )
        )
        )
    {
        $vlan_index   = $passport->rc_vlan_if() || {};
        %reverse_vlan = reverse %$vlan_index;
        $vlan_id      = $passport->rc_vlan_id();
    }

    my %if;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( ( $index == 1 ) and ( $model =~ /(86)/ ) ) {
            $if{$index} = 'Cpu.Virtual';
        }

        elsif ( ( $index == 192 ) and ( $model eq '8603' ) ) {
            $if{$index} = 'Cpu.3';
        }

        elsif ( ( $index == 320 ) and ( $model =~ /(8606|8610|8610co)/ ) ) {
            $if{$index} = 'Cpu.5';
        }

        elsif ( ( $index == 384 ) and ( $model =~ /(8606|8610|8610co)/ ) ) {
            $if{$index} = 'Cpu.6';
        }

        elsif (( $index > 2000 and $model =~ /(86|83|81|16)/ )
            or ( $index > 256 and $model =~ /(105|11[05]0|12[05])/ ) )
        {

            my $v_index = $reverse_vlan{$iid};
            my $v_id    = $vlan_id->{$v_index};
            next unless defined $v_id;
            my $v_port = 'Vlan' . "$v_id";
            $if{$index} = $v_port;
        }

        else {
            my $port = ( $index % $index_factor ) + $port_offset;
            my $slot = int( $index / $index_factor );

            my $slotport = "$slot.$port";
            $if{$iid} = $slotport;
        }

    }

    return \%if;
}

sub i_mac {
    my $passport = shift;
    my $partial  = shift;

    my $i_mac = $passport->orig_i_mac($partial) || {};
    my $model = $passport->model();

    my %if_mac;
    foreach my $iid ( keys %$i_mac ) {
        my $mac = $i_mac->{$iid};
        next unless defined $mac;

        $if_mac{$iid} = $mac;
    }

    # Get VLAN Virtual Router Interfaces
    if (!defined $partial
        or (defined $model
            and (  ( $partial > 2000 and $model =~ /(86|83|81|16)/ )
                or ( $partial > 256 and $model =~ /(105|11[05]0|12[05])/ ) )
        )
        )
    {

        my $vlan_index = $passport->rc_vlan_if()  || {};
        my $vlan_mac   = $passport->rc_vlan_mac() || {};

        foreach my $iid ( keys %$vlan_mac ) {
            my $v_mac = $vlan_mac->{$iid};
            next unless defined $v_mac;
            my $v_id = $vlan_index->{$iid};
            next unless defined $v_id;
            next if ( defined $partial and $v_id !~ /^$partial$/ );

            $if_mac{$v_id} = $v_mac;
        }
    }

    if ( defined $model and $model =~ /(86)/ ) {

        my $cpu_mac = $passport->rc_cpu_mac($partial) || {};
        my $virt_ip = $passport->rc_virt_ip()         || '0.0.0.0';

        # Get CPU Ethernet Interfaces
        foreach my $iid ( keys %$cpu_mac ) {
            my $mac = $cpu_mac->{$iid};
            next unless defined $mac;

            $if_mac{$iid} = $mac;
        }

        # Check for Virtual Mgmt Interface
        unless ( ( $virt_ip eq '0.0.0.0' )
            or ( defined $partial and $partial ne "1" ) )
        {
            my $chassis_base_mac = $passport->rc_base_mac();
            if ( defined $chassis_base_mac ) {
                my @virt_mac = split /:/, $chassis_base_mac;
                $virt_mac[0] = hex( $virt_mac[0] );
                $virt_mac[1] = hex( $virt_mac[1] );
                $virt_mac[2] = hex( $virt_mac[2] );
                $virt_mac[3] = hex( $virt_mac[3] );
                $virt_mac[4] = hex( $virt_mac[4] ) + 0x03;
                $virt_mac[5] = hex( $virt_mac[5] ) + 0xF8;

                my $mac = join( ':', map { sprintf "%02x", $_ } @virt_mac );

                $if_mac{1} = $mac;
            }
        }
    }
    return \%if_mac;
}

sub i_description {
    my $passport = shift;
    my $partial  = shift;

    my $i_descr = $passport->orig_i_description($partial) || {};
    my $model = $passport->model();

    my %descr;
    foreach my $iid ( keys %$i_descr ) {
        my $if_descr = $i_descr->{$iid};
        next unless defined $if_descr;

        $descr{$iid} = $if_descr;
    }

    # Get VLAN Virtual Router Interfaces
    if (!defined $partial
        or (defined $model
            and (  ( $partial > 2000 and $model =~ /(86|83|81|16)/ )
                or ( $partial > 256 and $model =~ /(105|11[05]0|12[05])/ ) )
        )
        )
    {

        my $v_descr    = $passport->v_name();
        my $vlan_index = $passport->rc_vlan_if();

        foreach my $vid ( keys %$v_descr ) {
            my $vl_descr = $v_descr->{$vid};
            next unless defined $vl_descr;
            my $v_id = $vlan_index->{$vid};
            next unless defined $v_id;
            next if ( defined $partial and $v_id !~ /^$partial$/ );

            $descr{$v_id} = $vl_descr;
        }
    }
    return \%descr;
}

sub i_name {
    my $passport = shift;
    my $partial  = shift;

    my $model      = $passport->model();
    my $i_index    = $passport->i_index($partial) || {};
    my $rc_alias   = $passport->rc_alias($partial) || {};
    my $i_name2    = $passport->orig_i_name($partial) || {};
    my $v_name     = {};
    my $vlan_index = {};
    my %reverse_vlan;

    if (!defined $partial
        or (defined $model
            and (  ( $partial > 2000 and $model =~ /(86|83|81|16)/ )
                or ( $partial > 256 and $model =~ /(105|11[05]0|12[05])/ ) )
        )
        )
    {
        $v_name     = $passport->v_name()     || {};
        $vlan_index = $passport->rc_vlan_if() || {};
        %reverse_vlan = reverse %$vlan_index;
    }

    my %i_name;
    foreach my $iid ( keys %$i_index ) {

        if ( ( $iid == 1 ) and ( $model =~ /(86)/ ) ) {
            $i_name{$iid} = 'CPU Virtual Management IP';
        }

        elsif ( ( $iid == 192 ) and ( $model eq '8603' ) ) {
            $i_name{$iid} = 'CPU 3 Ethernet Port';
        }

        elsif ( ( $iid == 320 ) and ( $model =~ /(8606|8610|8610co)/ ) ) {
            $i_name{$iid} = 'CPU 5 Ethernet Port';
        }

        elsif ( ( $iid == 384 ) and ( $model =~ /(8606|8610|8610co)/ ) ) {
            $i_name{$iid} = 'CPU 6 Ethernet Port';
        }

        elsif (
            ( $iid > 2000 and defined $model and $model =~ /(86|83|81|16)/ )
            or (    $iid > 256
                and defined $model
                and $model =~ /(105|11[05]0|12[05])/ )
            )
        {
            my $vlan_index = $reverse_vlan{$iid};
            my $vlan_name  = $v_name->{$vlan_index};
            next unless defined $vlan_name;

            $i_name{$iid} = $vlan_name;
        }

        else {
            my $name  = $i_name2->{$iid};
            my $alias = $rc_alias->{$iid};
            $i_name{$iid}
                = ( defined $alias and $alias !~ /^\s*$/ )
                ? $alias
                : $name;
        }
    }

    return \%i_name;
}

sub ip_index {
    my $passport = shift;
    my $partial  = shift;

    my $model = $passport->model();
    my $ip_index = $passport->orig_ip_index($partial) || {};

    my %ip_index;
    foreach my $ip ( keys %$ip_index ) {
        my $iid = $ip_index->{$ip};
        next unless defined $iid;

        $ip_index{$ip} = $iid;
    }

    # Only 8600 has CPU and Virtual Management IP
    if ( defined $model and $model =~ /(86)/ ) {

        my $cpu_ip = $passport->rc_cpu_ip($partial) || {};
        my $virt_ip = $passport->rc_virt_ip($partial);

        # Get CPU Ethernet IP
        foreach my $cid ( keys %$cpu_ip ) {
            my $c_ip = $cpu_ip->{$cid};
            next unless defined $c_ip;

            $ip_index{$c_ip} = $cid;
        }

        # Get Virtual Mgmt IP
        $ip_index{$virt_ip} = 1 if ( defined $virt_ip );
    }

    return \%ip_index;
}

sub ip_netmask {
    my $passport = shift;
    my $partial  = shift;

    my $model = $passport->model();
    my $ip_mask = $passport->orig_ip_netmask($partial) || {};

    my %ip_index;
    foreach my $iid ( keys %$ip_mask ) {
        my $mask = $ip_mask->{$iid};
        next unless defined $mask;

        $ip_index{$iid} = $mask;
    }

    # Only 8600 has CPU and Virtual Management IP
    if ( defined $model and $model =~ /(86)/ ) {

        my $cpu_ip    = $passport->rc_cpu_ip($partial)    || {};
        my $cpu_mask  = $passport->rc_cpu_mask($partial)  || {};
        my $virt_ip   = $passport->rc_virt_ip($partial);
        my $virt_mask = $passport->rc_virt_mask($partial) || {};

        # Get CPU Ethernet IP
        foreach my $iid ( keys %$cpu_mask ) {
            my $c_ip = $cpu_ip->{$iid};
            next unless defined $c_ip;
            my $c_mask = $cpu_mask->{$iid};
            next unless defined $c_mask;

            $ip_index{$c_ip} = $c_mask;
        }

        # Get Virtual Mgmt IP
        $ip_index{$virt_ip} = $virt_mask
            if ( defined $virt_mask and defined $virt_ip );
    }

    return \%ip_index;
}

sub root_ip {
    my $passport        = shift;
    my $model           = $passport->model();
    my $rc_ip_addr      = $passport->rc_ip_addr();
    my $rc_ip_type      = $passport->rc_ip_type();
    my $virt_ip         = $passport->rc_virt_ip();
    my $router_ip       = $passport->router_ip();
    my $sonmp_topo_port = $passport->sonmp_topo_port();
    my $sonmp_topo_ip   = $passport->sonmp_topo_ip();

    # Only 8600 and 1600 have CLIP or Management Virtual IP
    if ( defined $model and $model =~ /(86|16)/ ) {

        # Return CLIP (CircuitLess IP)
        foreach my $iid ( keys %$rc_ip_type ) {
            my $ip_type = $rc_ip_type->{$iid};
            next
                unless ( ( defined $ip_type )
                and ( $ip_type =~ /circuitLess/i ) );
            my $ip = $rc_ip_addr->{$iid};
            next unless defined $ip;

            return $ip if $passport->snmp_connect_ip($ip);
        }

        # Return Management Virtual IP address
        if ( ( defined $virt_ip ) and ( $virt_ip ne '0.0.0.0' ) ) {
            return $virt_ip if $passport->snmp_connect_ip($virt_ip);
        }
    }

    # Return OSPF Router ID
    if ( ( defined $router_ip ) and ( $router_ip ne '0.0.0.0' ) ) {
        foreach my $iid ( keys %$rc_ip_addr ) {
            my $ip = $rc_ip_addr->{$iid};
            next unless $router_ip eq $ip;
            return $router_ip if $passport->snmp_connect_ip($router_ip);
        }
    }

    # Otherwise Return SONMP Advertised IP Address
    foreach my $entry ( keys %$sonmp_topo_port ) {
        my $port = $sonmp_topo_port->{$entry};
        next unless $port == 0;
        my $ip = $sonmp_topo_ip->{$entry};
        return $ip
            if (( defined $ip )
            and ( $ip ne '0.0.0.0' )
            and ( $passport->snmp_connect_ip($ip) ) );
    }
    return;
}

# Required for SNMP::Info::SONMP
sub index_factor {
    my $passport     = shift;
    my $model        = $passport->model();
    my $index_factor = 64;

    # Older Accelar models use base 16 instead of 64
    $index_factor = 16
        if ( defined $model and $model =~ /(105|11[05]0|12[05])/ );
    return $index_factor;
}

sub slot_offset {
    return 0;
}

sub port_offset {
    return 1;
}

# Bridge MIB does not map Bridge Port to ifIndex correctly
sub bp_index {
    my $passport = shift;
    my $partial  = shift;

    my $if_index = $passport->i_index($partial) || {};

    my %bp_index;
    foreach my $iid ( keys %$if_index ) {
        $bp_index{$iid} = $iid;
    }
    return \%bp_index;
}

# Pseudo ENTITY-MIB methods

sub e_index {
    my $passport = shift;

    my $model = $passport->model();
    my $rc_ps_t = $passport->rc_ps_type() || {};

    # We're going to hack an index: Slot/Mda/Postion
    # We're going to put chassis and power supplies in a slot
    # which doesn't exist
    my %rc_e_index;

    # Make up a chassis index
    $rc_e_index{1} = 1;

    # Power supplies are common, handle them first
    foreach my $idx ( keys %$rc_ps_t ) {
        next unless $idx;

        # We should never have 90 slots, they will also
        # sort numerically at the bottom
        my $index = $idx + 90 . "0000";
        $rc_e_index{$index} = $index;
    }

    # Older Accelars use RAPID-CITY::rcCardTable
    if ( defined $model and $model =~ /(105|11[05]0|12[05])/ ) {
        my $rc_c_t = $passport->rc_c_type() || {};
        foreach my $idx ( keys %$rc_c_t ) {
            next unless $idx;

            my $index = "$idx" . "0000";
            $rc_e_index{$index} = $index;
            $index++;
            $rc_e_index{$index} = $index;
        }
    }

    # All newer models use RAPID-CITY::rc2kCardTable
    else {
        my $rc2_c_t = $passport->rc2k_c_ftype()  || {};
        my $rc2_m_t = $passport->rc2k_mda_type() || {};

        foreach my $idx ( keys %$rc2_c_t ) {
            next unless $idx;

            my $index = "$idx" . "0000";
            for ( 0 .. 2 ) {
                $rc_e_index{$index} = $index;
                $index++;
            }
        }
        foreach my $idx ( keys %$rc2_m_t ) {
            next unless $idx;
            next if $idx == 0;

            my ( $slot, $mda ) = split /\./, $idx;
            $mda = sprintf( "%02d", $mda );

            my $index = "$idx" . "$mda" . "00";
            $rc_e_index{$index} = $index;
            $index++;
            $rc_e_index{$index} = $index;
        }
    }
    return \%rc_e_index;
}

sub e_class {
    my $passport = shift;

    my $rc_e_idx = $passport->e_index() || {};

    my %rc_e_class;
    foreach my $iid ( keys %$rc_e_idx ) {
        if ( $iid == 1 ) {
            $rc_e_class{$iid} = 'chassis';
        }
        elsif ( $iid =~ /^9(\d)/ and length $iid > 5 ) {
            $rc_e_class{$iid} = 'powerSupply';
        }
        elsif ( $iid =~ /0000$/ ) {
            $rc_e_class{$iid} = 'container';
        }
        else {
            $rc_e_class{$iid} = 'module';
        }
    }
    return \%rc_e_class;
}

sub e_descr {
    my $passport = shift;

    my $model = $passport->model();
    my $rc_ps = $passport->rc_ps_detail() || {};
    my $rc_ch = $passport->rcChasType();
    $rc_ch =~ s/a//;

    my %rc_e_descr;

    # Chassis
    $rc_e_descr{1} = $rc_ch;

    # Power supplies are common, handle them first
    foreach my $idx ( keys %$rc_ps ) {
        next unless $idx;
        my $ps = $rc_ps->{$idx};
        next unless $ps;
        my $index = $idx + 90 . "0000";
        $rc_e_descr{$index} = $ps;
    }

    # Older Accelars use RAPID-CITY::rcCardTable
    if ( defined $model and $model =~ /(105|11[05]0|12[05])/ ) {
        my $rc_c_t = $passport->rc_c_type() || {};
        foreach my $idx ( keys %$rc_c_t ) {
            next unless $idx;
            my $type = $rc_c_t->{$idx};
            next unless $type;
            my $index = "$idx" . "0000";
            $rc_e_descr{$index} = "Slot " . "$idx";
            $index++;
            $rc_e_descr{$index} = $type;
        }
    }

    # All newer models use RAPID-CITY::rc2kCardTable
    else {
        my $rc2_cf = $passport->rc2k_c_fdesc()  || {};
        my $rc2_cb = $passport->rc2k_c_bdesc()  || {};
        my $rc2_m  = $passport->rc2k_mda_desc() || {};

        foreach my $idx ( keys %$rc2_cf ) {
            next unless $idx;
            my $cf = $rc2_cf->{$idx};
            next unless $idx;
            my $cb = $rc2_cb->{$idx};

            my $index = "$idx" . "0000";
            $rc_e_descr{$index} = "Slot " . "$idx";
            $index++;
            $rc_e_descr{$index} = $cf;
            $index++;
            $rc_e_descr{$index} = $cb;
        }
        foreach my $idx ( keys %$rc2_m ) {
            next unless $idx;
            my $cm = $rc2_m->{$idx};
            next unless $cm;
            my ( $slot, $mda ) = split /\./, $idx;
            $mda = sprintf( "%02d", $mda );

            my $index = "$idx" . "$mda" . "00";
            $rc_e_descr{$index} = $cm;
        }
    }
    return \%rc_e_descr;
}

sub e_type {
    my $passport = shift;

    my $model = $passport->model();
    my $rc_ps = $passport->rc_ps_type() || {};
    my $rc_ch = $passport->rcChasType();

    my %rc_e_type;

    # Chassis
    $rc_e_type{1} = $rc_ch;

    # Power supplies are common, handle them first
    foreach my $idx ( keys %$rc_ps ) {
        next unless $idx;
        my $ps = $rc_ps->{$idx};
        next unless $ps;
        my $index = $idx + 90 . "0000";
        $rc_e_type{$index} = $ps;
    }

    # Older Accelars use RAPID-CITY::rcCardTable
    if ( defined $model and $model =~ /(105|11[05]0|12[05])/ ) {
        my $rc_c_t = $passport->rc_c_type() || {};
        foreach my $idx ( keys %$rc_c_t ) {
            next unless $idx;
            my $type = $rc_c_t->{$idx};
            next unless $type;
            my $index = "$idx" . "0000";
            $rc_e_type{$index} = "zeroDotZero";
            $index++;
            $rc_e_type{$index} = $type;
        }
    }

    # All newer models use RAPID-CITY::rc2kCardTable
    else {
        my $rc2_cf = $passport->rc2k_c_ftype()  || {};
        my $rc2_cb = $passport->rc2k_c_btype()  || {};
        my $rc2_m  = $passport->rc2k_mda_type() || {};

        foreach my $idx ( keys %$rc2_cf ) {
            next unless $idx;
            my $cf = $rc2_cf->{$idx};
            next unless $idx;
            my $cb = $rc2_cb->{$idx};

            my $index = "$idx" . "0000";
            $rc_e_type{$index} = "zeroDotZero";
            $index++;
            $rc_e_type{$index} = $cf;
            $index++;
            $rc_e_type{$index} = $cb;
        }
        foreach my $idx ( keys %$rc2_m ) {
            next unless $idx;
            my $cm = $rc2_m->{$idx};
            next unless $cm;
            my ( $slot, $mda ) = split /\./, $idx;
            $mda = sprintf( "%02d", $mda );

            my $index = "$idx" . "$mda" . "00";
            $rc_e_type{$index} = $cm;
        }
    }
    return \%rc_e_type;
}

sub e_name {
    my $passport = shift;

    my $model = $passport->model();
    my $rc_e_idx = $passport->e_index() || {};

    my %rc_e_name;
    foreach my $iid ( keys %$rc_e_idx ) {

        if ( $iid == 1 ) {
            $rc_e_name{$iid} = 'Chassis';
            next;
        }

        my $mod = int( substr( $iid, -4, 2 ) );
        my $slot = substr( $iid, -6, 2 );

        if ( $iid =~ /^9(\d)/ and length $iid > 5 ) {
            $rc_e_name{$iid} = "Power Supply $1";
        }
        elsif ( $iid =~ /(00){2}$/ ) {
            $rc_e_name{$iid} = "Slot $slot";
        }
        elsif ( $iid =~ /(00){1}$/ ) {
            $rc_e_name{$iid} = "Card $slot, MDA $mod";
        }
        elsif ( defined $model
            and $model =~ /(105|11[05]0|12[05])/
            and $iid   =~ /1$/ )
        {
            $rc_e_name{$iid} = "Card $slot";
        }
        elsif ( $iid =~ /1$/ ) {
            $rc_e_name{$iid} = "Card $slot (front)";
        }
        elsif ( $iid =~ /2$/ ) {
            $rc_e_name{$iid} = "Card $slot (back)";
        }
    }
    return \%rc_e_name;
}

sub e_hwver {
    my $passport = shift;

    my $model = $passport->model();
    my $rc_ps = $passport->rc_ps_rev() || {};

    my %rc_e_hwver;

    # Chassis
    $rc_e_hwver{1} = $passport->rc_ch_rev();

    # Power supplies are common, handle them first
    foreach my $idx ( keys %$rc_ps ) {
        next unless $idx;
        my $ps = $rc_ps->{$idx};
        next unless $ps;
        my $index = $idx + 90 . "0000";
        $rc_e_hwver{$index} = $ps;
    }

    # Older Accelars use RAPID-CITY::rcCardTable
    if ( defined $model and $model =~ /(105|11[05]0|12[05])/ ) {
        my $rc_c_t = $passport->rc_c_rev() || {};
        foreach my $idx ( keys %$rc_c_t ) {
            next unless $idx;
            my $type = $rc_c_t->{$idx};
            next unless $type;
            my $index = "$idx" . "0001";
            $rc_e_hwver{$index} = $type;
        }
    }

    # All newer models use RAPID-CITY::rc2kCardTable
    else {
        my $rc2_cf = $passport->rc2k_c_frev()  || {};
        my $rc2_cb = $passport->rc2k_c_brev()  || {};
        my $rc2_m  = $passport->rc2k_mda_rev() || {};

        foreach my $idx ( keys %$rc2_cf ) {
            next unless $idx;
            my $cf = $rc2_cf->{$idx};
            next unless $idx;
            my $cb = $rc2_cb->{$idx};

            my $index = "$idx" . "0001";
            $rc_e_hwver{$index} = $cf;
            $index++;
            $rc_e_hwver{$index} = $cb;
        }
        foreach my $idx ( keys %$rc2_m ) {
            next unless $idx;
            my $cm = $rc2_m->{$idx};
            next unless $cm;
            my ( $slot, $mda ) = split /\./, $idx;
            $mda = sprintf( "%02d", $mda );

            my $index = "$idx" . "$mda" . "00";
            $rc_e_hwver{$index} = $cm;
        }
    }
    return \%rc_e_hwver;
}

sub e_vendor {
    my $passport = shift;

    my $rc_e_idx = $passport->e_index() || {};

    my %rc_e_vendor;
    foreach my $iid ( keys %$rc_e_idx ) {
        $rc_e_vendor{$iid} = 'nortel';
    }
    return \%rc_e_vendor;
}

sub e_serial {
    my $passport = shift;

    my $model = $passport->model();
    my $rc_ps = $passport->rc_ps_serial() || {};

    my %rc_e_serial;

    # Chassis
    $rc_e_serial{1} = $passport->rc_serial();

    # Power supplies are common, handle them first
    foreach my $idx ( keys %$rc_ps ) {
        next unless $idx;
        my $ps = $rc_ps->{$idx};
        next unless $ps;
        my $index = $idx + 90 . "0000";
        $rc_e_serial{$index} = $ps;
    }

    # Older Accelars use RAPID-CITY::rcCardTable
    if ( defined $model and $model =~ /(105|11[05]0|12[05])/ ) {
        my $rc_c_t = $passport->rc_c_serial() || {};
        foreach my $idx ( keys %$rc_c_t ) {
            next unless $idx;
            my $type = $rc_c_t->{$idx};
            next unless $type;
            my $index = "$idx" . "0001";
            $rc_e_serial{$index} = $type;
        }
    }

    # All newer models use RAPID-CITY::rc2kCardTable
    else {
        my $rc2_cf = $passport->rc2k_c_fserial()  || {};
        my $rc2_cb = $passport->rc2k_c_bserial()  || {};
        my $rc2_m  = $passport->rc2k_mda_serial() || {};

        foreach my $idx ( keys %$rc2_cf ) {
            next unless $idx;
            my $cf = $rc2_cf->{$idx};
            next unless $idx;
            my $cb = $rc2_cb->{$idx};

            my $index = "$idx" . "0001";
            $rc_e_serial{$index} = $cf;
            $index++;
            $rc_e_serial{$index} = $cb;
        }
        foreach my $idx ( keys %$rc2_m ) {
            next unless $idx;
            my $cm = $rc2_m->{$idx};
            next unless $cm;
            my ( $slot, $mda ) = split /\./, $idx;
            $mda = sprintf( "%02d", $mda );

            my $index = "$idx" . "$mda" . "00";
            $rc_e_serial{$index} = $cm;
        }
    }
    return \%rc_e_serial;
}

sub e_pos {
    my $passport = shift;

    my $rc_e_idx = $passport->e_index() || {};

    my %rc_e_pos;
    foreach my $iid ( keys %$rc_e_idx ) {
        next unless $iid;
        if ( $iid == 1 ) {
            $rc_e_pos{$iid} = -1;
            next;
        }
        my $sub = int( substr( $iid, -2, 2 ) );
        my $mod = int( substr( $iid, -4, 2 ) );
        my $slot = substr( $iid, -6, 2 );
        if ( $iid =~ /(00){2}$/ ) {
            $rc_e_pos{$iid} = $slot;
        }
        elsif ( $iid =~ /(00){1}$/ ) {
            $rc_e_pos{$iid} = $mod * 100;
        }
        else {
            $rc_e_pos{$iid} = $sub;
        }
    }
    return \%rc_e_pos;
}

sub e_parent {
    my $passport = shift;

    my $rc_e_idx = $passport->e_index() || {};

    my %rc_e_parent;
    foreach my $iid ( keys %$rc_e_idx ) {
        next unless $iid;
        if ( $iid == 1 ) {
            $rc_e_parent{$iid} = 0;
            next;
        }
        my $slot = substr( $iid, -6, 2 );
        if ( $iid =~ /(00){1,2}$/ ) {
            $rc_e_parent{$iid} = 1;
        }
        else {
            $rc_e_parent{$iid} = "$slot" . "0000";
        }
    }
    return \%rc_e_parent;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::Passport - SNMP Interface to modular Nortel Ethernet Routing
Switches (formerly Passport / Accelar)

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $passport = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $passport->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Abstraction subclass for modular Nortel Ethernet Routing Switches (formerly
Passport and Accelar Series Switches).

These devices have some of the same characteristics as the stackable Nortel 
Ethernet Switches (Baystack).  For example, extended interface information is 
gleaned from F<RAPID-CITY>.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $passport = new SNMP::Info::Layer3::Passport(...);

=head2 Inherited Classes

=over

=item SNMP::Info::SONMP

=item SNMP::Info::RapidCity

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item Inherited Classes' MIBs

See L<SNMP::Info::SONMP/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::RapidCity/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $passport->model()

Returns model type.  Checks $passport->id() against the 
F<RAPID-CITY-MIB> and then parses out C<rcA>.

=item $passport->vendor()

Returns 'nortel'

=item $passport->os()

Returns 'passport'

=item $passport->os_ver()

Returns the software version extracted from C<sysDescr>

=item $passport->serial()

Returns (C<rcChasSerialNumber>)

=item $passport->root_ip()

Returns the primary IP used to communicate with the device.  Returns the first
found:  CLIP (CircuitLess IP), Management Virtual IP (C<rcSysVirtualIpAddr>),
OSPF Router ID (C<ospfRouterId>), SONMP Advertised IP Address.

=back

=head2 Overrides

=over

=item $passport->index_factor()

Required by SNMP::Info::SONMP.  Returns 64 for 8600, 16 for Accelar.

=item $passport->port_offset()

Required by SNMP::Info::SONMP.  Returns 1.

=item $passport->slot_offset()

Required by SNMP::Info::SONMP.  Returns 0.

=back

=head2 Global Methods imported from SNMP::Info::SONMP

See documentation in L<SNMP::Info::SONMP/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::RapidCity

See documentation in L<SNMP::Info::RapidCity/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $passport->i_index()

Returns SNMP IID to Interface index.  Extends (C<ifIndex>) by adding the index
of the CPU virtual management IP (if present), each CPU Ethernet port, and
each VLAN to ensure the virtual router ports are captured.

=item $passport->interfaces()

Returns reference to the map between IID and physical Port.

Slot and port numbers on the Passport switches are determined by the formula:
port = (C<ifIndex % index_factor>) + port_offset,
slot = int(C<ifIndex / index_factor>).

The physical port name is returned as slot.port.  CPU Ethernet ports are
prefixed with CPU and VLAN interfaces are returned as the VLAN ID prefixed
with Vlan.

=item $passport->i_mac()

MAC address of the interface.  Note this is just the MAC of the port, not
anything connected to it.

=item $passport->i_description()

Description of the interface. Usually a little longer single word name that is both
human and machine friendly.  Not always.

=item $passport->i_name()

Crosses rc_alias() (C<rcPortName>) with ifAlias() and returns the human set
port name if exists.

=item $passport->ip_index()

Maps the IP Table to the IID.  Extends (C<ipAdEntIfIndex>) by adding the index of
the CPU virtual management IP (if present) and each CPU Ethernet port.

=item $passport->ip_netmask()

Extends (C<ipAdEntNetMask>) by adding the mask of the CPU virtual management
IP (if present) and each CPU Ethernet port.

=item $passport->bp_index()

Returns reference to hash of bridge port table entries map back to interface
identifier (iid)

Returns (C<ifIndex>) for both key and value since some devices seem to have
problems with F<BRIDGE-MIB>

=back

=head2 Pseudo F<ENTITY-MIB> information

These devices do not support F<ENTITY-MIB>.  These methods emulate Physical
Table methods using the F<RAPID-CITY MIB>.

=over

=item $passport->e_index()

Returns reference to hash.  Key and Value: Integer. The index is created by
combining the slot, module, and position into a five or six digit integer.
Slot can be either one or two digits while the module and position are each
two digits padded with leading zero if required.

=item $passport->e_class()

Returns reference to hash.  Key: IID, Value: General hardware type.  This
class only returns container, module, and power supply types.

=item $passport->e_descr()

Returns reference to hash.  Key: IID, Value: Human friendly name.

=item $passport->e_name()

Returns reference to hash.  Key: IID, Value: Human friendly name.

=item $passport->e_hwver()

Returns reference to hash.  Key: IID, Value: Hardware version.

=item $passport->e_vendor()

Returns reference to hash.  Key: IID, Value: nortel.

=item $passport->e_serial()

Returns reference to hash.  Key: IID, Value: Serial number.

=item $passport->e_pos()

Returns reference to hash.  Key: IID, Value: The relative position among all
entities sharing the same parent.

=item $passport->e_type()

Returns reference to hash.  Key: IID, Value: Type of component/sub-component.

=item $passport->e_parent()

Returns reference to hash.  Key: IID, Value: The value of e_index() for the
entity which 'contains' this entity.  A value of zero indicates	this entity
is not contained in any other entity.

=back

=head2 Table Methods imported from SNMP::Info::SONMP

See documentation in L<SNMP::Info::SONMP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::RapidCity

See documentation in L<SNMP::Info::RapidCity/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
