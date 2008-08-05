# SNMP::Info::Bridge
# $Id: Bridge.pm,v 1.38 2008/08/02 03:21:25 jeneric Exp $
#
# Changes since Version 0.7 Copyright (c) 2004 Max Baker
# All rights reserved.
#
# Copyright (c) 2002,2003 Regents of the University of California
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

package SNMP::Info::Bridge;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::Bridge::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::Bridge::EXPORT_OK = qw//;

use vars qw/$VERSION $DEBUG %MIBS %FUNCS %GLOBALS %MUNGE $INIT/;

$VERSION = '2.00';

%MIBS = (
    'BRIDGE-MIB'   => 'dot1dBaseBridgeAddress',
    'Q-BRIDGE-MIB' => 'dot1qPvid',
);

%GLOBALS = (
    'b_mac'   => 'dot1dBaseBridgeAddress',
    'b_ports' => 'dot1dBaseNumPorts',
    'b_type'  => 'dot1dBaseType',

    # Spanning Tree Protocol
    'stp_ver'       => 'dot1dStpProtocolSpecification',
    'stp_time'      => 'dot1dStpTimeSinceTopologyChange',
    'stp_root'      => 'dot1dStpDesignatedRoot',
    'stp_root_port' => 'dot1dStpRootPort',
    'stp_priority'  => 'dot1dStpPriority',

    # Q-BRIDGE-MIB
    'qb_vlans_max'       => 'dot1qMaxSupportedVlans',
    'qb_vlans'           => 'dot1qNumVlans',
    'qb_next_vlan_index' => 'dot1qNextFreeLocalVlanIndex',
);

%FUNCS = (

    # Forwarding Table: Dot1dTpFdbEntry
    'fw_mac'    => 'dot1dTpFdbAddress',
    'fw_port'   => 'dot1dTpFdbPort',
    'fw_status' => 'dot1dTpFdbStatus',

    # Bridge Port Table: Dot1dBasePortEntry
    'bp_index' => 'dot1dBasePortIfIndex',
    'bp_port'  => 'dot1dBasePortCircuit',

    # Bridge Static (Destination-Address Filtering) Database
    'bs_mac'    => 'dot1dStaticAddress',
    'bs_port'   => 'dot1dStaticReceivePort',
    'bs_to'     => 'dot1dStaticAllowedToGoTo',
    'bs_status' => 'dot1dStaticStatus',

    # Spanning Tree Protocol Table : dot1dStpPortTable
    'stp_p_id'       => 'dot1dStpPort',
    'stp_p_priority' => 'dot1dStpPortPriority',
    'stp_p_state'    => 'dot1dStpPortState',
    'stp_p_cost'     => 'dot1dStpPortPathCost',
    'stp_p_root'     => 'dot1dStpPortDesignatedRoot',
    'stp_p_bridge'   => 'dot1dStpPortDesignatedBridge',
    'stp_p_port'     => 'dot1dStpPortDesignatedPort',

    # Q-BRIDGE-MIB : dot1qPortVlanTable
    'qb_i_vlan'        => 'dot1qPvid',
    'qb_i_vlan_type'   => 'dot1qPortAcceptableFrameTypes',
    'qb_i_vlan_in_flt' => 'dot1qPortIngressFiltering',

    # Q-BRIDGE-MIB : dot1qVlanCurrentTable
    'qb_cv_egress'   => 'dot1qVlanCurrentEgressPorts',
    'qb_cv_untagged' => 'dot1qVlanCurrentUntaggedPorts',
    'qb_cv_stat'     => 'dot1qVlanStatus',

    # Q-BRIDGE-MIB : dot1qVlanStaticTable
    'v_name'           => 'dot1qVlanStaticName',
    'qb_v_egress'      => 'dot1qVlanStaticEgressPorts',
    'qb_v_fbdn_egress' => 'dot1qVlanForbiddenEgressPorts',
    'qb_v_untagged'    => 'dot1qVlanStaticUntaggedPorts',
    'qb_v_stat'        => 'dot1qVlanStaticRowStatus',

    # VLAN Forwarding Table: Dot1qTpFdbEntry
    'qb_fw_port'   => 'dot1qTpFdbPort',
    'qb_fw_status' => 'dot1qTpFdbStatus',
);

%MUNGE = (

    # Inherit all the built in munging
    %SNMP::Info::MUNGE,

    # Add ones for our class
    'b_mac'            => \&SNMP::Info::munge_mac,
    'fw_mac'           => \&SNMP::Info::munge_mac,
    'bs_mac'           => \&SNMP::Info::munge_mac,
    'stp_root'         => \&SNMP::Info::munge_mac,
    'stp_p_root'       => \&SNMP::Info::munge_prio_mac,
    'stp_p_bridge'     => \&SNMP::Info::munge_prio_mac,
    'stp_p_port'       => \&SNMP::Info::munge_prio_mac,
    'qb_cv_egress'     => \&SNMP::Info::munge_port_list,
    'qb_cv_untagged'   => \&SNMP::Info::munge_port_list,
    'qb_v_egress'      => \&SNMP::Info::munge_port_list,
    'qb_v_fbdn_egress' => \&SNMP::Info::munge_port_list,
    'qb_v_untagged'    => \&SNMP::Info::munge_port_list,

);

# break up the Dot1qTpFdbEntry INDEX into FDB ID and MAC Address.
sub _qb_fdbtable_index {
    my $idx    = shift;
    my @values = split( /\./, $idx );
    my $fdb_id = shift(@values);
    return ( $fdb_id, join( ':', map { sprintf "%02x", $_ } @values ) );
}

sub qb_fw_mac {
    my $bridge  = shift;
    my $partial = shift;

    my $qb_fw_port = $bridge->qb_fw_port($partial);
    my $qb_fw_mac  = {};
    foreach my $idx ( keys %$qb_fw_port ) {
        my ( $fdb_id, $mac ) = _qb_fdbtable_index($idx);
        $qb_fw_mac->{$idx} = $mac;
    }
    return $qb_fw_mac;
}

sub qb_i_vlan_t {
    my $bridge  = shift;
    my $partial = shift;

    my $qb_i_vlan      = $bridge->qb_i_vlan($partial);
    my $qb_i_vlan_type = $bridge->qb_i_vlan_type($partial);

    my $i_vlan = {};

    foreach my $if ( keys %$qb_i_vlan ) {
        my $vlan = $qb_i_vlan->{$if};
        my $tagged = $qb_i_vlan_type->{$if} || '';
        next unless defined $vlan;
        $i_vlan->{$if} = $tagged eq 'admitOnlyVlanTagged' ? 'trunk' : $vlan;
    }
    return $i_vlan;
}

sub i_stp_state {
    my $bridge  = shift;
    my $partial = shift;

    my $bp_index    = $bridge->bp_index($partial);
    my $stp_p_state = $bridge->stp_p_state($partial);

    my %i_stp_state;

    foreach my $index ( keys %$stp_p_state ) {
        my $state = $stp_p_state->{$index};
        my $iid   = $bp_index->{$index};
        next unless defined $iid;
        next unless defined $state;
        $i_stp_state{$iid} = $state;
    }

    return \%i_stp_state;
}

sub i_stp_port {
    my $bridge  = shift;
    my $partial = shift;

    my $bp_index   = $bridge->bp_index($partial);
    my $stp_p_port = $bridge->stp_p_port($partial);

    my %i_stp_port;

    foreach my $index ( keys %$stp_p_port ) {
        my $bridge = $stp_p_port->{$index};
        my $iid    = $bp_index->{$index};
        next unless defined $iid;
        next unless defined $bridge;
        $i_stp_port{$iid} = $bridge;
    }
    return \%i_stp_port;
}

sub i_stp_id {
    my $bridge  = shift;
    my $partial = shift;

    my $bp_index = $bridge->bp_index($partial);
    my $stp_p_id = $bridge->stp_p_id($partial);

    my %i_stp_id;

    foreach my $index ( keys %$stp_p_id ) {
        my $bridge = $stp_p_id->{$index};
        my $iid    = $bp_index->{$index};
        next unless defined $iid;
        next unless defined $bridge;
        $i_stp_id{$iid} = $bridge;
    }
    return \%i_stp_id;
}

sub i_stp_bridge {
    my $bridge  = shift;
    my $partial = shift;

    my $bp_index     = $bridge->bp_index($partial);
    my $stp_p_bridge = $bridge->stp_p_bridge($partial);

    my %i_stp_bridge;

    foreach my $index ( keys %$stp_p_bridge ) {
        my $bridge = $stp_p_bridge->{$index};
        my $iid    = $bp_index->{$index};
        next unless defined $iid;
        next unless defined $bridge;
        $i_stp_bridge{$iid} = $bridge;
    }
    return \%i_stp_bridge;
}

# Non-accessible, but needed for consistency with other classes
sub v_index {
    my $bridge  = shift;
    my $partial = shift;

    my $v_name = $bridge->v_name($partial);
    my %v_index;
    foreach my $idx ( keys %$v_name ) {
        $v_index{$idx} = $idx;
    }
    return \%v_index;
}

sub i_vlan {
    my $bridge  = shift;
    my $partial = shift;

    my $index = $bridge->bp_index();

    # If given a partial it will be an ifIndex, we need to use dot1dBasePort
    if ($partial) {
        my %r_index = reverse %$index;
        $partial = $r_index{$partial};
    }

    my $i_pvid = $bridge->qb_i_vlan($partial) || {};
    my $i_vlan = {};

    foreach my $bport ( keys %$i_pvid ) {
        my $vlan    = $i_pvid->{$bport};
        my $ifindex = $index->{$bport};
        unless ( defined $ifindex ) {
            print "  Port $bport has no bp_index mapping. Skipping.\n"
                if $DEBUG;
            next;
        }
        $i_vlan->{$ifindex} = $vlan;
    }

    return $i_vlan;
}

sub i_vlan_membership {
    my $bridge  = shift;
    my $partial = shift;

    my $index = $bridge->bp_index();

    # Use VlanCurrentTable if available since it will include dynamic
    # VLANs.  However, some devices do not populate the table.

    # 11/07 - Todo: Issue with some devices trying to query VlanCurrentTable
    # as table may grow very large with frequent VLAN changes.
    # 06/08 - VlanCurrentTable may be due to timefilter, should query with
    # zero partial for no time filter.
    # my $v_ports = $bridge->qb_cv_egress() || $bridge->qb_v_egress();

    my $v_ports = $bridge->qb_v_egress() || {};

    my $i_vlan_membership = {};
    foreach my $idx ( keys %$v_ports ) {
        next unless ( defined $v_ports->{$idx} );
        my $portlist = $v_ports->{$idx};
        my $ret      = [];
        my $vlan;

        # Strip TimeFilter if we're using VlanCurrentTable
        ( $vlan = $idx ) =~ s/^\d+\.//;

        # Convert portlist bit array to bp_index array
        for ( my $i = 0; $i <= $#$portlist; $i++ ) {
            push( @{$ret}, $i + 1 ) if ( @$portlist[$i] );
        }

        #Create HoA ifIndex -> VLAN array
        foreach my $port ( @{$ret} ) {
            my $ifindex = $index->{$port};
            next unless ( defined($ifindex) );    # shouldn't happen
            next if ( defined $partial and $ifindex !~ /^$partial$/ );
            push( @{ $i_vlan_membership->{$ifindex} }, $vlan );
        }
    }
    return $i_vlan_membership;
}

sub set_i_pvid {
    my $bridge = shift;

    $bridge->error_throw("VLAN set not supported.");
    return;
}

sub set_i_vlan {
    my $bridge = shift;

    $bridge->error_throw("VLAN set not supported.");
    return;
}

sub set_add_i_vlan_tagged {
    my $bridge = shift;

    $bridge->error_throw("VLAN set not supported.");
    return;
}

sub set_remove_i_vlan_tagged {
    my $bridge = shift;

    $bridge->error_throw("VLAN set not supported.");
    return;
}

#
# These are internal methods and are not documented.  Do not use directly.
#
sub _check_forbidden_ports {
    my $bridge = shift;
    my ( $vlan_id, $index ) = @_;
    return unless ( $vlan_id =~ /\d+/ and $index =~ /\d+/ );

    my $iv_forbidden = $bridge->qb_v_fbdn_egress($vlan_id);

    my $forbidden_ports = $iv_forbidden->{$vlan_id};
    print "Forbidden ports: @$forbidden_ports\n" if $bridge->debug();
    if ( defined( @$forbidden_ports[ $index - 1 ] )
        and ( @$forbidden_ports[ $index - 1 ] eq "1" ) )
    {
        print
            "Error: Index: $index in forbidden list for VLAN: $vlan_id unable to add.\n"
            if $bridge->debug();
        return;
    }
    return 1;
}

sub _validate_vlan_param {
    my $bridge = shift;
    my ( $vlan_id, $ifindex ) = @_;

    # VID and ifIndex should both be numeric
    unless (defined $vlan_id
        and defined $ifindex
        and $vlan_id =~ /^\d+$/
        and $ifindex =~ /^\d+$/ )
    {
        $bridge->error_throw("Invalid parameter.");
        return;
    }

    # Check that ifIndex exists on device
    my $index = $bridge->interfaces($ifindex);

    unless ( exists $index->{$ifindex} ) {
        $bridge->error_throw("ifIndex $ifindex does not exist.");
        return;
    }

    #Check that VLAN exists on device
    my $vtp_vlans = $bridge->load_qb_cv_stat() || $bridge->load_qb_v_stat();
    my $vlan_exists = 0;

    foreach my $iid ( keys %$vtp_vlans ) {
        my $vlan  = 0;
        my $state = $vtp_vlans->{$iid};
        next unless defined $state;
        if ( $iid =~ /(\d+)$/ ) {
            $vlan = $1;
        }

        $vlan_exists = 1 if ( $vlan_id eq $vlan );
    }
    unless ($vlan_exists) {
        $bridge->error_throw(
            "VLAN $vlan_id does not exist or is not operational.");
        return;
    }

    return 1;
}

1;

__END__


=head1 NAME

SNMP::Info::Bridge - SNMP Interface to SNMP data available through the
F<BRIDGE-MIB> (RFC1493)

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 my $bridge = new SNMP::Info ( 
                             AutoSpecify => 1,
                             Debug       => 1,
                             DestHost    => 'switch', 
                             Community   => 'public',
                             Version     => 2
                             );

 my $class = $bridge->class();
 print " Using device sub class : $class\n";

 # Grab Forwarding Tables
 my $interfaces = $bridge->interfaces();
 my $fw_mac     = $bridge->fw_mac();
 my $fw_port    = $bridge->fw_port();
 my $bp_index   = $bridge->bp_index();

 foreach my $fw_index (keys %$fw_mac){
    my $mac   = $fw_mac->{$fw_index};
    my $bp_id = $fw_port->{$fw_index};
    my $iid   = $bp_index->{$bp_id};
    my $port  = $interfaces->{$iid};

    print "Port:$port forwarding to $mac\n";
 } 

=head1 DESCRIPTION

F<BRIDGE-MIB> is used by most Layer 2 devices, and holds information like the
MAC Forwarding Table and Spanning Tree Protocol info.

F<Q-BRIDGE-MIB> holds 802.1q information -- VLANs and Trunking.  Cisco tends
not to use this MIB, but some proprietary ones.  HP and some nicer vendors use
this.  This is from C<RFC2674_q>.  

Create or use a subclass of SNMP::Info that inherits this class.  Do not use
directly.

For debugging you can call new() directly as you would in SNMP::Info 

 my $bridge = new SNMP::Info::Bridge(...);

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item F<BRIDGE-MIB>

=item F<Q-BRIDGE-MIB>

=back

F<BRIDGE-MIB> needs to be extracted from
ftp://ftp.cisco.com/pub/mibs/v1/v1.tar.gz

=head1 GLOBAL METHODS

These are methods that return scalar values from SNMP

=over

=item $bridge->b_mac()

Returns the MAC Address of the root bridge port

(C<dot1dBaseBridgeAddress>)

=item $bridge->b_ports()

Returns the number of ports in device

(C<dot1dBaseNumPorts>)

=item $bridge->b_type()

Returns the type of bridging this bridge can perform, transparent and/or
source route.

(C<dot1dBaseType>)

=item $bridge->stp_ver()

Returns what version of STP the device is running.

(C<dot1dStpProtocolSpecification>)

=item $bridge->stp_time()

Returns time since last topology change detected. (100ths/second)

(C<dot1dStpTimeSinceTopologyChange>)

=item $bridge->stp_root()

Returns root of STP.

(C<dot1dStpDesignatedRoot>)

=item $bridge->qb_vlans_max() 

Maximum number of VLANS supported on this device.

(C<dot1qMaxSupportedVlans>)

=item $bridge->qb_vlans() 

Current number of VLANs that are configured in this device.

(C<dot1qNumVlans>)

=item $bridge->qb_next_vlan_index() 

The next available value for C<dot1qVlanIndex> of a local VLAN entry in
C<dot1qVlanStaticTable>

(C<dot1qNextFreeLocalVlanIndex>)

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $bridge->i_vlan()

Returns a mapping between C<ifIndex> and the PVID or default VLAN.

=item $bridge->i_vlan_membership()

Returns reference to hash of arrays: key = C<ifIndex>, value = array of VLAN
IDs.  These are the VLANs which are members of the egress list for the port.

  Example:
  my $interfaces = $bridge->interfaces();
  my $vlans      = $bridge->i_vlan_membership();
  
  foreach my $iid (sort keys %$interfaces) {
    my $port = $interfaces->{$iid};
    my $vlan = join(',', sort(@{$vlans->{$iid}}));
    print "Port: $port VLAN: $vlan\n";
  }

=item $bridge->qb_i_vlan_t()

Returns reference to hash: key = C<dot1dBasePort>, value = either 'trunk' for
tagged ports or the VLAN ID.

=item $bridge->v_index()

Returns VLAN IDs

=back

=head2 Forwarding Table (C<dot1dTpFdbEntry>)

=over 

=item $bridge->fw_mac()

Returns reference to hash of forwarding table MAC Addresses

(C<dot1dTpFdbAddress>)

=item $bridge->fw_port()

Returns reference to hash of forwarding table entries port interface
identifier (iid)

(C<dot1dTpFdbPort>)

=item $bridge->fw_status()

Returns reference to hash of forwarding table entries status

(C<dot2dTpFdbStatus>)

=back

=head2 Bridge Port Table (C<dot1dBasePortEntry>)

=over

=item $bridge->bp_index()

Returns reference to hash of bridge port table entries map back to interface
identifier (iid)

(C<dot1dBasePortIfIndex>)

=item $bridge->bp_port()

Returns reference to hash of bridge port table entries for a port which
(potentially) has the same value of C<dot1dBasePortIfIndex> as another port
on the same bridge, this object contains the name of an	object instance unique
to this port.

(C<dot1dBasePortCircuit>)

=back

=head2 Spanning Tree Protocol Table (C<dot1dStpPortTable>)

Descriptions are straight from F<BRIDGE-MIB.my>

=over

=item $bridge->stp_p_id()

"The port number of the port for which this entry contains Spanning Tree
Protocol management information."

(C<dot1dStpPort>)

=item $bridge->stp_p_priority()

"The value of the priority field which is contained in the first
(in network byte order) octet of the (2 octet long) Port ID.  The other octet
of the Port ID is given by the value of C<dot1dStpPort>."

(C<dot1dStpPortPriority>)

=item $bridge->stp_p_state()

"The port's current state as defined by application of the Spanning Tree
Protocol.  This state controls what action a port takes on reception of a
frame.  If the bridge has detected a port that is malfunctioning it will place
that port into the broken(6) state.  For ports which are disabled
(see C<dot1dStpPortEnable>), this object will have a value of disabled(1)."

 disabled(1)
 blocking(2)
 listening(3)
 learning(4)
 forwarding(5)
 broken(6)

(C<dot1dStpPortState>)

=item $bridge->stp_p_cost()

"The contribution of this port to the path cost of paths towards the spanning
tree root which include this port.  802.1D-1990 recommends that the default
value of this parameter be in inverse proportion to the speed of the attached
LAN."

(C<dot1dStpPortPathCost>)

=item $bridge->stp_p_root()

"The unique Bridge Identifier of the Bridge recorded as the Root in the
Configuration BPDUs transmitted by the Designated Bridge for the segment to
which the port is attached."

(C<dot1dStpPortDesignatedRoot>)

=item $bridge->stp_p_bridge()

"The Bridge Identifier of the bridge which this port considers to be the
Designated Bridge for this port's segment."

(C<dot1dStpPortDesignatedBridge>)

=item $bridge->stp_p_port()

(C<dot1dStpPortDesignatedPort>)

"The Port Identifier of the port on the Designated Bridge for this port's
segment."

=item $bridge->i_stp_port()

Returns the mapping of (C<dot1dStpPortDesignatedPort>) to the interface
index (iid).

=item $bridge->i_stp_state()

Returns the mapping of (C<dot1dStpPortState>) to the interface
index (iid).

=item $bridge->i_stp_id()

Returns the mapping of (C<dot1dStpPort>) to the interface index (iid).

=item $bridge->i_stp_bridge()

Returns the mapping of (C<dot1dStpPortDesignatedBridge>) to the interface
index (iid).

=back

=head2 Q-BRIDGE Port VLAN Table (C<dot1qPortVlanTable>)

=over

=item $bridge->qb_i_vlan()

The PVID, the VLAN ID assigned to untagged frames or Priority-Tagged frames
received on this port.

(C<dot1qPvid>)

=item $bridge->qb_i_vlan_type()

Either C<admitAll> or C<admitOnlyVlanTagged>.  This is a good spot to find
trunk ports.

(C<dot1qPortAcceptableFrameTypes>)

=item $bridge->qb_i_vlan_in_flt()

When this is C<true> the device will discard incoming frames for VLANs which
do not include this Port in its Member set.  When C<false>, the port will
accept all incoming frames.

(C<dot1qPortIngressFiltering>)

=back

=head2 Q-BRIDGE VLAN Current Table (C<dot1qVlanCurrentTable>)

=over

=item $bridge->qb_cv_egress()

The set of ports which are assigned to the egress list for this VLAN.

(C<dot1qVlanCurrentEgressPorts>)

=item $bridge->qb_cv_untagged()

The set of ports which should transmit egress packets for this VLAN as
untagged. 

(C<dot1qVlanCurrentUntaggedPorts>)

=item $bridge->qb_cv_stat()

Status of the VLAN, other, permanent, or dynamicGvrp.

(C<dot1qVlanStatus>)

=back

=head2 Q-BRIDGE VLAN Static Table (C<dot1qVlanStaticTable>)

=over

=item $bridge->qb_v_name()

Human-entered name for vlans.

(C<dot1qVlanStaticName>)

=item $bridge->qb_v_egress()

The set of ports which are assigned to the egress list for this VLAN.

(C<dot1qVlanStaticEgressPorts>)

=item $bridge->qb_v_fbdn_egress()

The set of ports which are prohibited from being included in the egress list
for this VLAN.

(C<dot1qVlanForbiddenEgressPorts>)

=item $bridge->qb_v_untagged()

The set of ports which should transmit egress packets for this VLAN as
untagged. 

(C<dot1qVlanStaticUntaggedPorts>)

=item $bridge->qb_v_stat()

C<active> !

(C<dot1qVlanStaticRowStatus>)

=back

=head2 Q-BRIDGE Filtering Database Table (C<dot1qFdbTable>)

=over

=item $bridge->qb_fw_mac()

Returns reference to hash of forwarding table MAC Addresses

(C<dot1qTpFdbAddress>)

=item $bridge->qb_fw_port()

Returns reference to hash of forwarding table entries port interface
identifier (iid)

(C<dot1qTpFdbPort>)

=item $bridge->qb_fw_status()

Returns reference to hash of forwarding table entries status

(C<dot1qTpFdbStatus>)

=back
 
=head1 SET METHODS

These are methods that provide SNMP set functionality for overridden methods
or provide a simpler interface to complex set operations.  See
L<SNMP::Info/"SETTING DATA VIA SNMP"> for general information on set
operations. 

=over

=item $bridge->set_i_vlan(vlan, ifIndex)

Currently unsupported.  Throws an error and returns.

=item $bridge->set_i_pvid(pvid, ifIndex)

Currently unsupported.  Throws an error and returns.

=item $bridge->set_add_i_vlan_tagged(vlan, ifIndex)

Currently unsupported.  Throws an error and returns.

=item $bridge->set_remove_i_vlan_tagged(vlan, ifIndex)

Currently unsupported.  Throws an error and returns.

=cut
