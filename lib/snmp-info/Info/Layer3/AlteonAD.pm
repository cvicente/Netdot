# SNMP::Info::Layer3::AlteonAD
# $Id: AlteonAD.pm,v 1.19 2008/08/02 03:21:47 jeneric Exp $
#
# Copyright (c) 2008 Eric Miller
# All Rights Reserved
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

package SNMP::Info::Layer3::AlteonAD;

use strict;
use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::AlteonAD::ISA       = qw/SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::AlteonAD::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %FUNCS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    'ALTEON-ROOT-MIB'            => 'aceswitch184',
    'ALTEON-TIGON-SWITCH-MIB'    => 'hwPowerSupplyStatus',
    'ALTEON-CHEETAH-SWITCH-MIB'  => 'hwFanStatus',
    'ALTEON-TS-PHYSICAL-MIB'     => 'agPortTableMaxEnt',
    'ALTEON-CS-PHYSICAL-MIB'     => 'vlanCurCfgLearn',
    'ALTEON-TS-NETWORK-MIB'      => 'ripCurCfgSupply',
    'ALTEON-CHEETAH-NETWORK-MIB' => 'ripCurCfgIntfSupply',
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    'old_sw_ver'      => 'ALTEON_TIGON_SWITCH_MIB__agSoftwareVersion',
    'new_sw_ver'      => 'ALTEON_CHEETAH_SWITCH_MIB__agSoftwareVersion',
    'old_tftp_action' => 'ALTEON_TIGON_SWITCH_MIB__agTftpAction',
    'new_tftp_action' => 'ALTEON_CHEETAH_SWITCH_MIB__agTftpAction',
    'old_tftp_host'   => 'ALTEON_TIGON_SWITCH_MIB__agTftpServer',
    'new_tftp_host'   => 'ALTEON_CHEETAH_SWITCH_MIB__agTftpServer',
    'old_tftp_file'   => 'ALTEON_TIGON_SWITCH_MIB__agTftpCfgFileName',
    'new_tftp_file'   => 'ALTEON_CHEETAH_SWITCH_MIB__agTftpCfgFileName',
    'old_tftp_result' => 'ALTEON_TIGON_SWITCH_MIB__agTftpLastActionStatus',
    'new_tftp_result' => 'ALTEON_CHEETAH_SWITCH_MIB__agTftpLastActionStatus',
    'old_ip_max'      => 'ALTEON_TS_NETWORK_MIB__ipInterfaceTableMax',
    'new_ip_max'      => 'ALTEON_CHEETAH_NETWORK_MIB__ipInterfaceTableMax',
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS,

    # From agPortCurCfgTable
    'old_ag_p_cfg_idx'  => 'ALTEON_TS_PHYSICAL_MIB__agPortCurCfgIndx',
    'new_ag_p_cfg_idx'  => 'ALTEON_CHEETAH_SWITCH_MIB__agPortCurCfgIndx',
    'old_ag_p_cfg_pref' => 'agPortCurCfgPrefLink',
    'new_ag_p_cfg_pref' => 'agPortCurCfgPreferred',
    'old_ag_p_cfg_pvid' => 'ALTEON_TS_PHYSICAL_MIB__agPortCurCfgPVID',
    'new_ag_p_cfg_pvid' => 'ALTEON_CHEETAH_SWITCH_MIB__agPortCurCfgPVID',
    'old_ag_p_cfg_fe_auto' =>
        'ALTEON_TS_PHYSICAL_MIB__agPortCurCfgFastEthAutoNeg',
    'new_ag_p_cfg_fe_auto' =>
        'ALTEON_CHEETAH_SWITCH_MIB__agPortCurCfgFastEthAutoNeg',
    'old_ag_p_cfg_fe_mode' =>
        'ALTEON_TS_PHYSICAL_MIB__agPortCurCfgFastEthMode',
    'new_ag_p_cfg_fe_mode' =>
        'ALTEON_CHEETAH_SWITCH_MIB__agPortCurCfgFastEthMode',
    'old_ag_p_cfg_ge_auto' =>
        'ALTEON_TS_PHYSICAL_MIB__agPortCurCfgGigEthAutoNeg',
    'new_ag_p_cfg_ge_auto' =>
        'ALTEON_CHEETAH_SWITCH_MIB__agPortCurCfgGigEthAutoNeg',
    'old_ag_p_cfg_name' => 'ALTEON_TS_PHYSICAL_MIB__agPortCurCfgPortName',
    'new_ag_p_cfg_name' => 'ALTEON_CHEETAH_SWITCH_MIB__agPortCurCfgPortName',

    # From portInfoTable
    'old_p_info_idx'  => 'ALTEON_TS_PHYSICAL_MIB__portInfoIndx',
    'new_p_info_idx'  => 'ALTEON_CHEETAH_SWITCH_MIB__portInfoIndx',
    'old_p_info_mode' => 'ALTEON_TS_PHYSICAL_MIB__portInfoMode',
    'new_p_info_mode' => 'ALTEON_CHEETAH_SWITCH_MIB__portInfoMode',

    # From ipCurCfgIntfTable
    'old_ip_cfg_vlan' => 'ALTEON_TS_NETWORK_MIB__ipCurCfgIntfVlan',
    'new_ip_cfg_vlan' => 'ALTEON_CHEETAH_NETWORK_MIB__ipCurCfgIntfVlan',

    # From vlanCurCfgTable
    'old_vlan_id'    => 'ALTEON_TS_PHYSICAL_MIB__vlanCurCfgVlanId',
    'new_vlan_id'    => 'ALTEON_CS_PHYSICAL_MIB__vlanCurCfgVlanId',
    'old_vlan_state' => 'ALTEON_TS_PHYSICAL_MIB__vlanCurCfgState',
    'new_vlan_state' => 'ALTEON_CS_PHYSICAL_MIB__vlanCurCfgState',
    'old_vlan_name'  => 'ALTEON_TS_PHYSICAL_MIB__vlanCurCfgVlanName',
    'new_vlan_name'  => 'ALTEON_CS_PHYSICAL_MIB__vlanCurCfgVlanName',
    'old_vlan_ports' => 'ALTEON_TS_PHYSICAL_MIB__vlanCurCfgPorts',
    'new_vlan_ports' => 'ALTEON_CS_PHYSICAL_MIB__vlanCurCfgPorts',
);

%MUNGE = ( %SNMP::Info::Layer3::MUNGE, );

sub model {
    my $alteon = shift;

    my $id = $alteon->id();

    unless ( defined $id ) {
        print
            " SNMP::Info::Layer3::AlteonAD::model() - Device does not support sysObjectID\n"
            if $alteon->debug();
        return;
    }

    my $model = &SNMP::translateObj($id);

    return $id unless defined $model;

    $model =~ s/^aceswitch//;
    $model =~ s/^acedirector/AD/;
    $model =~ s/^(copper|fiber)Module/BladeCenter GbESM/;

    return $model;
}

sub vendor {
    return 'nortel';
}

sub os {
    return 'alteon';
}

sub os_ver {
    my $alteon = shift;
    my $version = $alteon->new_sw_ver() || $alteon->old_sw_ver();
    return unless defined $version;

    return $version;
}

sub interfaces {
    my $alteon       = shift;
    my $interfaces   = $alteon->i_index();
    my $descriptions = $alteon->i_description();
    my $ip_max       = $alteon->new_ip_max() || $alteon->old_ip_max();

    my %interfaces = ();
    foreach my $iid ( keys %$interfaces ) {
        my $desc = $descriptions->{$iid};
        next unless defined $desc;

        if ( $desc =~ /(^net\d+)/ ) {
            $desc = $1;
        }

        # IP interfaces are first followed by physical, number possible
        # varies by switch model
        elsif ( defined $ip_max and $iid > $ip_max ) {
            $desc = ( $iid % $ip_max );
        }
        $interfaces{$iid} = $desc;
    }
    return \%interfaces;
}

sub i_duplex {
    my $alteon = shift;

    my $p_mode = $alteon->new_p_info_mode()
        || $alteon->old_p_info_mode()
        || {};
    my $ip_max = $alteon->new_ip_max() || $alteon->old_ip_max();

    my %i_duplex;
    foreach my $if ( keys %$p_mode ) {
        my $duplex = $p_mode->{$if};
        next unless defined $duplex;

        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;

        my $idx;
        $idx = $if + $ip_max if ( defined $ip_max );

        $i_duplex{$idx} = $duplex;
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $alteon = shift;

    my $ag_pref = $alteon->new_ag_p_cfg_pref()
        || $alteon->old_ag_p_cfg_pref()
        || {};
    my $ag_fe_auto = $alteon->new_ag_p_cfg_fe_auto()
        || $alteon->old_ag_p_cfg_fe_auto()
        || {};
    my $ag_fe_mode = $alteon->new_ag_p_cfg_fe_mode()
        || $alteon->old_ag_p_cfg_fe_mode()
        || {};
    my $ag_ge_auto = $alteon->new_ag_p_cfg_ge_auto()
        || $alteon->old_ag_p_cfg_ge_auto()
        || {};
    my $ip_max = $alteon->new_ip_max() || $alteon->old_ip_max();

    my %i_duplex_admin;
    foreach my $if ( keys %$ag_pref ) {
        my $pref = $ag_pref->{$if};
        next unless defined $pref;

        my $string = 'other';
        if ( $pref =~ /gigabit/i ) {
            my $ge_auto = $ag_ge_auto->{$if};
            $string = 'full' if ( $ge_auto =~ /off/i );
            $string = 'auto' if ( $ge_auto =~ /on/i );
        }
        elsif ( $pref =~ /fast/i ) {
            my $fe_auto = $ag_fe_auto->{$if};
            my $fe_mode = $ag_fe_mode->{$if};
            $string = 'half'
                if ( $fe_mode =~ /half/i and $fe_auto =~ /off/i );
            $string = 'full'
                if ( $fe_mode =~ /full/i and $fe_auto =~ /off/i );
            $string = 'auto' if $fe_auto =~ /on/i;
        }

        my $idx;
        $idx = $if + $ip_max if ( defined $ip_max );

        $i_duplex_admin{$idx} = $string;
    }
    return \%i_duplex_admin;
}

sub i_name {
    my $alteon = shift;

    my $p_name = $alteon->new_ag_p_cfg_name()
        || $alteon->old_ag_p_cfg_name()
        || {};
    my $ip_max = $alteon->new_ip_max() || $alteon->old_ip_max();

    my %i_name;
    foreach my $iid ( keys %$p_name ) {
        my $name = $p_name->{$iid};
        next unless defined $name;
        my $idx;
        $idx = $iid + $ip_max if ( defined $ip_max );
        $i_name{$idx} = $name;
    }
    return \%i_name;
}

sub v_index {
    my $alteon  = shift;
    my $partial = shift;

    return $alteon->new_vlan_id($partial) || $alteon->old_vlan_id($partial);
}

sub v_name {
    my $alteon  = shift;
    my $partial = shift;

    return $alteon->new_vlan_name($partial)
        || $alteon->old_vlan_name($partial);
}

sub i_vlan {
    my $alteon = shift;

    my $ag_vlans = $alteon->new_ag_p_cfg_pvid()
        || $alteon->old_ag_p_cfg_pvid()
        || {};
    my $ip_vlans = $alteon->new_ip_cfg_vlan()
        || $alteon->old_ip_cfg_vlan()
        || {};
    my $ip_max = $alteon->new_ip_max() || $alteon->old_ip_max();

    my %i_vlan;
    foreach my $if ( keys %$ip_vlans ) {
        my $ip_vlanid = $ip_vlans->{$if};
        next unless defined $ip_vlanid;

        $i_vlan{$if} = $ip_vlanid;
    }
    foreach my $if ( keys %$ag_vlans ) {
        my $ag_vlanid = $ag_vlans->{$if};
        next unless defined $ag_vlanid;

        my $idx;
        $idx = $if + $ip_max if ( defined $ip_max );
        $i_vlan{$idx} = $ag_vlanid;
    }
    return \%i_vlan;
}

sub i_vlan_membership {
    my $alteon = shift;

    my $v_ports = $alteon->old_vlan_ports()
        || $alteon->new_vlan_ports()
        || {};
    my $ip_max = $alteon->new_ip_max() || $alteon->old_ip_max();

    my $i_vlan_membership = {};
    foreach my $vlan ( keys %$v_ports ) {
        my $portlist = [ split( //, unpack( "B*", $v_ports->{$vlan} ) ) ];
        my $ret = [];

        # Convert portlist bit array to ifIndex array
        for ( my $i = 0; $i <= scalar(@$portlist); $i++ ) {
            my $idx;
            $idx = $i + $ip_max if ( defined $ip_max );
            push( @{$ret}, $idx ) if ( @$portlist[$i] );
        }

        #Create HoA ifIndex -> VLAN array
        foreach my $port ( @{$ret} ) {
            push( @{ $i_vlan_membership->{$port} }, $vlan );
        }
    }
    return $i_vlan_membership;
}

# Bridge MIB does not map Bridge Port to ifIndex correctly on some code
# versions
sub bp_index {
    my $alteon = shift;

    my $b_index = $alteon->orig_bp_index();
    my $ip_max = $alteon->new_ip_max() || $alteon->old_ip_max();

    my %bp_index;
    foreach my $iid ( keys %$b_index ) {
        my $port = $b_index->{$iid};
        next unless defined $port;
        $port = $port + $ip_max if ( defined $ip_max and $iid == $ip_max );

        $bp_index{$iid} = $port;
    }
    return \%bp_index;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::AlteonAD - SNMP Interface to Nortel Alteon Layer 2-7
Switches.

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $alteon = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $alteon->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Abstraction subclass for Nortel Alteon Series Layer 2-7 load balancing
switches and Nortel BladeCenter Layer2-3 GbE Switch Modules.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $alteon = new SNMP::Info::Layer3::AlteonAD(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<ALTEON-ROOT-MIB>

=item F<ALTEON-TIGON-SWITCH-MIB>

=item F<ALTEON-TS-PHYSICAL-MIB>

=item F<ALTEON-TS-NETWORK-MIB>

=item F<ALTEON-CS-PHYSICAL-MIB>

=item F<ALTEON-CHEETAH-SWITCH-MIB>

=item F<ALTEON-CHEETAH-NETWORK-MIB>

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $alteon->model()

Returns model type.  Checks $alteon->id() against the F<ALTEON-ROOT-MIB> and
then parses out C<aceswitch>, replaces C<acedirector> with AD, and replaces
copperModule/fiberModule with BladeCenter GbESM.

=item $alteon->vendor()

Returns 'nortel'

=item $alteon->os()

Returns 'alteon'

=item $alteon->os_ver()

Returns the software version reported by C<agSoftwareVersion>

=item $alteon->tftp_action()

(C<agTftpAction>)

=item $alteon->tftp_host()

(C<agTftpServer>)

=item $alteon->tftp_file()

(C<agTftpCfgFileName>)

=item $alteon->tftp_result()

(C<agTftpLastActionStatus>)

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $alteon->interfaces()

Returns reference to the map between IID and physical port.

Utilizes description for network interfaces.  Ports are determined by
formula (C<ifIndex mod 256>).

=item $alteon->i_duplex()

Returns reference to hash.  Maps port operational duplexes to IIDs.

=item $alteon->i_duplex_admin()

Returns reference to hash.  Maps port admin duplexes to IIDs.

=item $alteon->i_vlan()

Returns a mapping between C<ifIndex> and the PVID or default VLAN.

=item $alteon->i_vlan_membership()

Returns reference to hash of arrays: key = C<ifIndex>, value = array of VLAN
IDs.  These are the VLANs which are members of the egress list for the port.

  Example:
  my $interfaces = $alteon->interfaces();
  my $vlans      = $alteon->i_vlan_membership();
  
  foreach my $iid (sort keys %$interfaces) {
    my $port = $interfaces->{$iid};
    my $vlan = join(',', sort(@{$vlans->{$iid}}));
    print "Port: $port VLAN: $vlan\n";
  }

=item $alteon->v_index()

Returns VLAN IDs

=item $alteon->v_name()

Human-entered name for vlans.

=item $alteon->i_name()

Maps (C<agPortCurCfgPortName>) to port and returns the human set port name if
exists.

=item $alteon->bp_index()

Returns a mapping between C<ifIndex> and the Bridge Table.

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
