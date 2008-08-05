# SNMP::Info::Layer3 - SNMP Interface to Layer3 devices
# $Id: Layer3.pm,v 1.34 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2008 Max Baker -- All changes from Version 0.7 on
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

package SNMP::Info::Layer3;

use strict;
use Exporter;
use SNMP::Info;
use SNMP::Info::Bridge;
use SNMP::Info::EtherLike;
use SNMP::Info::Entity;
use SNMP::Info::PowerEthernet;

@SNMP::Info::Layer3::ISA = qw/SNMP::Info::PowerEthernet
    SNMP::Info::Entity SNMP::Info::EtherLike
    SNMP::Info::Bridge SNMP::Info Exporter/;
@SNMP::Info::Layer3::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %FUNCS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::MIBS,
    %SNMP::Info::Bridge::MIBS,
    %SNMP::Info::EtherLike::MIBS,
    %SNMP::Info::Entity::MIBS,
    %SNMP::Info::PowerEthernet::MIBS,
    'IP-MIB'   => 'ipNetToMediaIfIndex',
    'OSPF-MIB' => 'ospfRouterId',
    'BGP4-MIB' => 'bgpIdentifier',
);

%GLOBALS = (

    # Inherit the super class ones
    %SNMP::Info::GLOBALS,
    %SNMP::Info::Bridge::GLOBALS,
    %SNMP::Info::EtherLike::GLOBALS,
    %SNMP::Info::Entity::GLOBALS,
    %SNMP::Info::PowerEthernet::GLOBALS,
    'mac' => 'ifPhysAddress.1',
    'serial1' =>
        '.1.3.6.1.4.1.9.3.6.3.0',    # OLD-CISCO-CHASSIS-MIB::chassisId.0
    'router_ip'    => 'ospfRouterId.0',
    'bgp_id'       => 'bgpIdentifier.0',
    'bgp_local_as' => 'bgpLocalAs.0',
);

%FUNCS = (
    %SNMP::Info::FUNCS,
    %SNMP::Info::Bridge::FUNCS,
    %SNMP::Info::EtherLike::FUNCS,
    %SNMP::Info::Entity::FUNCS,
    %SNMP::Info::PowerEthernet::FUNCS,

    # Obsolete Address Translation Table (ARP Cache)
    'old_at_index'   => 'atIfIndex',
    'old_at_paddr'   => 'atPhysAddress',
    'old_at_netaddr' => 'atNetAddress',

    # IP-MIB IP Net to Media Table (ARP Cache)
    'at_index'   => 'ipNetToMediaIfIndex',
    'at_paddr'   => 'ipNetToMediaPhysAddress',
    'at_netaddr' => 'ipNetToMediaNetAddress',

    # OSPF-MIB::ospfIfTable
    'ospf_if_ip'    => 'ospfIfIpAddress',
    'ospf_if_area'  => 'ospfIfAreaId',
    'ospf_if_type'  => 'ospfIfType',
    'ospf_if_hello' => 'ospfIfHelloInterval',
    'ospf_if_dead'  => 'ospfIfRtrDeadInterval',
    'ospf_if_admin' => 'ospfIfAdminStat',
    'ospf_if_state' => 'ospfIfState',

    # OSPF-MIB::ospfNbrTable
    'ospf_ip'         => 'ospfHostIpAddress',
    'ospf_peers'      => 'ospfNbrIpAddr',
    'ospf_peer_id'    => 'ospfNbrRtrId',
    'ospf_peer_state' => 'ospfNbrState',

    # BGP4-MIB::bgpPeerTable
    'bgp_peers'               => 'bgpPeerLocalAddr',
    'bgp_peer_id'             => 'bgpPeerIdentifier',
    'bgp_peer_state'          => 'bgpPeerState',
    'bgp_peer_as'             => 'bgpPeerRemoteAs',
    'bgp_peer_addr'           => 'bgpPeerRemoteAddr',
    'bgp_peer_fsm_est_trans'  => 'bgpPeerFsmEstablishedTransitions',
    'bgp_peer_in_tot_msgs'    => 'bgpPeerInTotalMessages',
    'bgp_peer_in_upd_el_time' => 'bgpPeerInUpdateElapsedTime',
    'bgp_peer_in_upd'         => 'bgpPeerInUpdates',
    'bgp_peer_out_tot_msgs'   => 'bgpPeerOutTotalMessages',
    'bgp_peer_out_upd'        => 'bgpPeerOutUpdates',
);

%MUNGE = (

    # Inherit all the built in munging
    %SNMP::Info::MUNGE,
    %SNMP::Info::Bridge::MUNGE,
    %SNMP::Info::EtherLike::MUNGE,
    %SNMP::Info::Entity::MUNGE,
    %SNMP::Info::PowerEthernet::MUNGE,
    'old_at_paddr' => \&SNMP::Info::munge_mac,
    'at_paddr'     => \&SNMP::Info::munge_mac,
);

# Method OverRides

sub root_ip {
    my $l3 = shift;

    my $router_ip = $l3->router_ip();
    my $ospf_ip   = $l3->ospf_ip();

    # return the first one found here (should be only one)
    if ( defined $ospf_ip and scalar( keys %$ospf_ip ) ) {
        foreach my $key ( keys %$ospf_ip ) {
            my $ip = $ospf_ip->{$key};
            next if $ip eq '0.0.0.0';
            next unless $l3->snmp_connect_ip($ip);
            print " SNMP::Layer3::root_ip() using $ip\n" if $l3->debug();
            return $ip;
        }
    }

    return $router_ip
        if (( defined $router_ip )
        and ( $router_ip ne '0.0.0.0' )
        and ( $l3->snmp_connect_ip($router_ip) ) );
    return;
}

sub i_ignore {
    my $l3      = shift;
    my $partial = shift;

    my $interfaces = $l3->interfaces($partial) || {};

    my %i_ignore;
    foreach my $if ( keys %$interfaces ) {

        # lo -> cisco aironet 350 loopback
        if ( $interfaces->{$if} =~ /(tunnel|loopback|\blo\b|null)/i ) {
            $i_ignore{$if}++;
        }
    }
    return \%i_ignore;
}

sub serial {
    my $l3 = shift;

    my $serial1  = $l3->serial1();
    my $e_descr  = $l3->e_descr() || {};
    my $e_serial = $l3->e_serial() || {};

    my $serial2 = $e_serial->{1} || undef;
    my $chassis = $e_descr->{1}  || undef;

    # precedence
    #   serial2,chassis parse,serial1
    return $serial2 if ( defined $serial2 and $serial2 !~ /^\s*$/ );
    return $1
        if ( defined $chassis and $chassis =~ /serial#?:\s*([a-z0-9]+)/i );
    return $serial1 if ( defined $serial1 and $serial1 !~ /^\s*$/ );

    return;
}

# $l3->model() - the sysObjectID returns an IID to an entry in
#       the CISCO-PRODUCT-MIB.  Look it up and return it.
sub model {
    my $l3 = shift;
    my $id = $l3->id();

    unless ( defined $id ) {
        print
            " SNMP::Info::Layer3::model() - Device does not support sysObjectID\n"
            if $l3->debug();
        return;
    }

    my $model = &SNMP::translateObj($id);

    return $id unless defined $model;

    $model =~ s/^cisco//i;
    $model =~ s/^catalyst//;
    $model =~ s/^cat//;
    return $model;
}

sub i_name {
    my $l3      = shift;
    my $partial = shift;

    my $i_index = $l3->i_index($partial);
    my $i_alias = $l3->i_alias($partial);
    my $i_name2 = $l3->orig_i_name($partial);

    my %i_name;
    foreach my $iid ( keys %$i_name2 ) {
        my $name  = $i_name2->{$iid};
        my $alias = $i_alias->{$iid};
        $i_name{$iid}
            = ( defined $alias and $alias !~ /^\s*$/ )
            ? $alias
            : $name;
    }

    return \%i_name;
}

sub i_duplex {
    my $l3      = shift;
    my $partial = shift;

    my $el_index  = $l3->el_index($partial);
    my $el_duplex = $l3->el_duplex($partial);

    my %i_index;
    foreach my $el_port ( keys %$el_duplex ) {
        my $iid = $el_index->{$el_port};
        next unless defined $iid;
        my $duplex = $el_duplex->{$el_port};
        next unless defined $duplex;

        $i_index{$iid} = 'half' if $duplex =~ /half/i;
        $i_index{$iid} = 'full' if $duplex =~ /full/i;
        $i_index{$iid} = 'auto' if $duplex =~ /auto/i;
    }

    return \%i_index;
}

# $l3->interfaces() - Map the Interfaces to their physical names
sub interfaces {
    my $l3      = shift;
    my $partial = shift;

    my $interfaces   = $l3->i_index($partial);
    my $descriptions = $l3->i_description($partial);

    my %interfaces = ();
    foreach my $iid ( keys %$interfaces ) {
        my $desc = $descriptions->{$iid};
        next unless defined $desc;

        $interfaces{$iid} = $desc;
    }

    return \%interfaces;
}

sub vendor {
    my $l3 = shift;

    my $descr = $l3->description();

    return 'cisco'   if ( $descr =~ /(cisco|\bios\b)/i );
    return 'foundry' if ( $descr =~ /foundry/i );

    return 'unknown';

}

sub at_index {
    my $l3      = shift;
    my $partial = shift;

    return $l3->orig_at_index($partial) || $l3->old_at_index($partial);
}

sub at_paddr {
    my $l3      = shift;
    my $partial = shift;

    return $l3->orig_at_paddr($partial) || $l3->old_at_paddr($partial);
}

sub at_netaddr {
    my $l3      = shift;
    my $partial = shift;

    return $l3->orig_at_netaddr($partial) || $l3->old_at_netaddr($partial);
}

1;

__END__

=head1 NAME

SNMP::Info::Layer3 - SNMP Interface to network devices serving Layer3 or
Layers 2 & 3

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $l3 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $l3->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

 # Let's get some basic Port information
 my $interfaces = $l3->interfaces();
 my $i_up       = $l3->i_up();
 my $i_speed    = $l3->i_speed();
 foreach my $iid (keys %$interfaces) {
    my $port  = $interfaces->{$iid};
    my $up    = $i_up->{$iid};
    my $speed = $i_speed->{$iid}
    print "Port $port is $up. Port runs at $speed.\n";
 }

=head1 DESCRIPTION

This class is usually used as a superclass for more specific device classes
listed under SNMP::Info::Layer3::*   Please read all docs under SNMP::Info
first.

Provides generic methods for accessing SNMP data for Layer 3 network devices. 
Includes support for Layer2+3 devices. 

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $l3 = new SNMP::Info::Layer3(...);

=head2 Inherited Classes

=over

=item SNMP::Info

=item SNMP::Info::Bridge (For L2/L3 devices)

=item SNMP::Info::EtherLike

=item SNMP::Info::Entity

=back

=head2 Required MIBs

=over

=item F<IP-MIB>

=item F<OSPF-MIB>

=item F<BGP4-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::Bridge/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::EtherLike/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::Entity/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $l3->mac()

Returns root port mac address

(C<ifPhysAddress.1>)

=item $l3->router_ip()

(C<ospfRouterId.0>)

=item $l3->bgp_id()

(C<bgpIdentifier.0>)

Returns the BGP identifier of the local system

=item $l3->bgp_local_as()

Returns the local autonomous system number 

(C<bgpLocalAs.0>)

=back

=head2 Overrides

=over

=item $l3->model()

Tries to reference $l3->id() to one of the product MIBs listed above

Removes 'cisco'  from cisco devices for readability.

=item $l3->serial()

Tries to cull a serial number from F<ENTITY-MIB>, description, and
F<OLD-CISCO->... MIB.

=item $l3->vendor()

Tries to cull a Vendor name from C<sysDescr>

=item $l3->root_ip()

Returns the primary IP used to communicate with the device.  Returns the first
found:  OSPF Router ID (C<ospfRouterId>) or any OSPF Host IP Address
(C<ospfHostIpAddress>).

=back

=head2 Globals imported from SNMP::Info

See L<SNMP::Info/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::Bridge

See L<SNMP::Info::Bridge/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::EtherLike

See L<SNMP::Info::EtherLike/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::Entity

See L<SNMP::Info::Entity/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $l3->interfaces()

Returns the map between SNMP Interface Identifier (iid) and physical port
name. 

Only returns those iids that have a description listed in $l3->i_description()

=item $l3->i_ignore()

Returns reference to hash.  Creates a key for each IID that should be ignored.

Currently looks for tunnel,loopback,lo,null from $l3->interfaces()

=item $l3->i_name()

Returns reference to hash of iid to human set name. 

Defaults to C<ifName>, but checks for an C<ifAlias>

=item $l3->i_duplex()

Returns reference to hash of iid to current link duplex setting.

Maps $l3->el_index() to $l3->el_duplex, then culls out 
full,half, or auto and sets the map to that value. 

See L<SNMP::Info::Etherlike> for the el_index() and el_duplex() methods.

=back

=head2 F<IP-MIB> Arp Cache Table (C<ipNetToMediaTable>)

=over

=item $l3->at_index()

Returns reference to hash.  Maps ARP table entries to Interface IIDs 

(C<ipNetToMediaIfIndex>)

If the device doesn't support C<ipNetToMediaIfIndex>, this will try
the deprecated C<atIfIndex>.

=item $l3->at_paddr()

Returns reference to hash.  Maps ARP table entries to MAC addresses. 

(C<ipNetToMediaPhysAddress>)

If the device doesn't support C<ipNetToMediaPhysAddress>, this will try
the deprecated C<atPhysAddress>.

=item $l3->at_netaddr()

Returns reference to hash.  Maps ARP table entries to IP addresses. 

(C<ipNetToMediaNetAddress>)

If the device doesn't support C<ipNetToMediaNetAddress>, this will try
the deprecated C<atNetAddress>.

=back

=head2 ARP Cache Entries

The C<atTable> has been deprecated since 1991.  You should never need
to use these methods.  See C<ipNetToMediaTable> above.

=over

=item $l3->old_at_index()

Returns reference to map of IID to Arp Cache Entry

(C<atIfIndex>)

=item $l3->old_at_paddr()

Returns reference to hash of Arp Cache Entries to MAC address

(C<atPhysAddress>)

=item $l3->old_at_netaddr()

Returns reference to hash of Arp Cache Entries to IP Address

(C<atNetAddress>)

=back

=head2 BGP Peer Table (C<bgpPeerTable>)

=over

=item $l3->bgp_peers()

Returns reference to hash of BGP peer to local IP address

(C<bgpPeerLocalAddr>)

=item $l3->bgp_peer_id()

Returns reference to hash of BGP peer to BGP peer identifier

(C<bgpPeerIdentifier>)

=item $l3->bgp_peer_state()

Returns reference to hash of BGP peer to BGP peer state

(C<bgpPeerState>)

=item $l3->bgp_peer_as()

Returns reference to hash of BGP peer to BGP peer autonomous system number

(C<bgpPeerRemoteAs>)

=item $l3->bgp_peer_addr()

Returns reference to hash of BGP peer to BGP peer IP address

(C<bgpPeerRemoteAddr>)

=item $l3->bgp_peer_fsm_est_trans()

Returns reference to hash of BGP peer to the total number of times the BGP FSM
transitioned into the established state

(C<bgpPeerFsmEstablishedTransitions>)

=item $l3->bgp_peer_in_tot_msgs()

Returns reference to hash of BGP peer to the total number of messages received
from the remote peer on this connection

(C<bgpPeerInTotalMessages>)

=item $l3->bgp_peer_in_upd_el_time()

Returns reference to hash of BGP peer to the elapsed time in seconds since
the last BGP UPDATE message was received from the peer.

(C<bgpPeerInUpdateElapsedTime>)

=item $l3->bgp_peer_in_upd()

Returns reference to hash of BGP peer to the number of BGP UPDATE messages
received on this connection

(C<bgpPeerInUpdates>)

=item $l3->bgp_peer_out_tot_msgs()

Returns reference to hash of BGP peer to the total number of messages
transmitted to the remote peer on this connection

(C<bgpPeerOutTotalMessages>)

=item $l3->bgp_peer_out_upd()

Returns reference to hash of BGP peer to the number of BGP UPDATE messages
transmitted on this connection

(C<bgpPeerOutUpdates>)

=back

=head2 OSPF Interface Table (C<ospfIfTable>)

=over

=item $l3->ospf_if_ip()

Returns reference to hash of OSPF interface IP addresses

(C<ospfIfIpAddress>)

=item $l3->ospf_if_area()

Returns reference to hash of the OSPF area to which the interfaces connect

(C<ospfIfAreaId>)

=item $l3->ospf_if_type()

Returns reference to hash of the OSPF interfaces' type

(C<ospfIfType>)

=item $l3->ospf_if_hello()

Returns reference to hash of the OSPF interfaces' hello interval

(C<ospfIfHelloInterval>)

=item $l3->ospf_if_dead()

Returns reference to hash of the OSPF interfaces' dead interval

(C<ospfIfRtrDeadInterval>)

=item $l3->ospf_if_admin()

Returns reference to hash of the OSPF interfaces' administrative status

(C<ospfIfAdminStat>)

=item $l3->ospf_if_state()

Returns reference to hash of the OSPF interfaces' state

(C<ospfIfState>)

=back

=head2 OSPF Neighbor Table (C<ospfNbrTable>)

=over

=item $l3->ospf_peers()

Returns reference to hash of IP addresses the neighbor is using in its
IP Source Addresses

(C<ospfNbrIpAddr>)

=item $l3->ospf_peer_id()

Returns reference to hash of neighbor Router IDs

(C<ospfNbrRtrId>)

=item $l3->ospf_peer_state()

Returns reference to hash of state of the relationship with the neighbor
routers

(C<ospfNbrState>)

=back

=head2 Table Methods imported from SNMP::Info

See L<SNMP::Info/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Bridge

See L<SNMP::Info::Bridge/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::EtherLike

See L<SNMP::Info::EtherLike/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Entity

See L<SNMP::Info::Entity/"TABLE METHODS"> for details.

=cut
