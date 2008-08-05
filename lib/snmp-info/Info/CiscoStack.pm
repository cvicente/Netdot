# SNMP::Info::CiscoStack
# $Id: CiscoStack.pm,v 1.21 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2008 Max Baker
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

package SNMP::Info::CiscoStack;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::CiscoStack::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::CiscoStack::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE %PORTSTAT/;

$VERSION = '2.00';

%MIBS = ( 'CISCO-STACK-MIB' => 'ciscoStackMIB', );

%GLOBALS = (
    'sysip'      => 'sysIpAddr',
    'netmask'    => 'sysNetMask',
    'broadcast'  => 'sysBroadcast',
    'serial1'    => 'chassisSerialNumber',
    'serial2'    => 'chassisSerialNumberString',
    'model1'     => 'chassisModel',
    'ps1_type'   => 'chassisPs1Type',
    'ps1_status' => 'chassisPs1Status',
    'ps2_type'   => 'chassisPs2Type',
    'ps2_status' => 'chassisPs2Status',
    'slots'      => 'chassisNumSlots',
    'fan'        => 'chassisFanStatus',
);

%FUNCS = (

    # CISCO-STACK-MIB::moduleEntry
    #   These are blades in a catalyst device
    'm_type'         => 'moduleType',
    'm_model'        => 'moduleModel',
    'm_serial'       => 'moduleSerialNumber',
    'm_status'       => 'moduleStatus',
    'm_name'         => 'moduleName',
    'm_ports'        => 'moduleNumPorts',
    'm_ports_status' => 'modulePortStatus',
    'm_hwver'        => 'moduleHwVersion',
    'm_fwver'        => 'moduleFwVersion',
    'm_swver'        => 'moduleSwVersion',

    # Router Blades :
    'm_ip'   => 'moduleIPAddress',
    'm_sub1' => 'moduleSubType',
    'm_sub2' => 'moduleSubType2',

    # CISCO-STACK-MIB::portEntry
    'p_name'                  => 'portName',
    'p_type'                  => 'portType',
    'p_status'                => 'portOperStatus',
    'p_status2'               => 'portAdditionalStatus',
    'p_speed'                 => 'portAdminSpeed',
    'p_duplex'                => 'portDuplex',
    'p_port'                  => 'portIfIndex',
    'p_rx_flow_control'       => 'portOperRxFlowControl',
    'p_tx_flow_control'       => 'portOperTxFlowControl',
    'p_rx_flow_control_admin' => 'portAdminRxFlowControl',
    'p_tx_flow_control_admin' => 'portAdminTxFlowControl',
    'p_oidx'                  => 'portCrossIndex',

    # CISCO-STACK-MIB::PortCpbEntry
    'p_speed_admin'  => 'portCpbSpeed',
    'p_duplex_admin' => 'portCpbDuplex',
);

%MUNGE = (
    'm_ports_status' => \&munge_port_status,
    'p_duplex_admin' => \&SNMP::Info::munge_bits,
);

%PORTSTAT = (
    1 => 'other',
    2 => 'ok',
    3 => 'minorFault',
    4 => 'majorFault'
);

# Changes binary byte describing each port into ascii, and returns
# an ascii list separated by spaces.
sub munge_port_status {
    my $status = shift;
    my @vals = map( $PORTSTAT{$_}, unpack( 'C*', $status ) );
    return join( ' ', @vals );
}

sub serial {
    my $stack   = shift;
    my $serial1 = $stack->serial1();
    my $serial2 = $stack->serial2();

    return $serial1 if defined $serial1;
    return $serial2 if defined $serial2;
    return;
}

# Rules for older CatOS devices using CiscoStack
#
# You can configure Ethernet and Fast Ethernet interfaces to either full
# duplex or half duplex.
#
# You cannot configure the duplex mode on Gigabit Ethernet ports (they are
# always in full-duplex mode).
#
# If you set the port speed to auto, duplex mode is automatically set to auto.
#
# For operational duplex if portCpbDuplex is all zeros the port is a gigabit
# port and duplex is always full.  If the port is not operational and auto
# return value will be undef since we don't know the operational status.
#
# Newer devices use ETHERLIKE-MIB to report operational duplex, this will be
# checked in the device class.

sub i_duplex {
    my $stack   = shift;
    my $partial = shift;

    my $p_port       = $stack->p_port()         || {};
    my $p_duplex     = $stack->p_duplex()       || {};
    my $p_duplex_cap = $stack->p_duplex_admin() || {};

    my $i_duplex = {};
    foreach my $port ( keys %$p_duplex ) {
        my $iid = $p_port->{$port};
        next unless defined $iid;
        next if ( defined $partial and $iid !~ /^$partial$/ );

        # Test for gigabit
        if ( $p_duplex_cap->{$port} == 0 ) {
            $i_duplex->{$iid} = 'full';
        }

        # Auto is not a valid operational state
        elsif ( $p_duplex->{$port} eq 'auto' ) {
            next;
        }
        else {
            $i_duplex->{$iid} = $p_duplex->{$port};
        }
    }
    return $i_duplex;
}

# For administrative duplex if portCpbDuplex is all zeros the port is a gigabit
# port and duplex is always full.  If portAdminSpeed is set to auto then the
# duplex will be auto, otherwise use portDuplex.

sub i_duplex_admin {
    my $stack   = shift;
    my $partial = shift;

    my $p_port       = $stack->p_port()         || {};
    my $p_duplex     = $stack->p_duplex()       || {};
    my $p_duplex_cap = $stack->p_duplex_admin() || {};
    my $p_speed      = $stack->p_speed()        || {};

    my $i_duplex_admin = {};
    foreach my $port ( keys %$p_duplex ) {
        my $iid = $p_port->{$port};
        next unless defined $iid;
        next if ( defined $partial and $iid !~ /^$partial$/ );

        # Test for gigabit
        if ( $p_duplex_cap->{$port} == 0 ) {
            $i_duplex_admin->{$iid} = 'full';
        }

        # Check admin speed for auto
        elsif ( $p_speed->{$port} =~ /auto/ ) {
            $i_duplex_admin->{$iid} = 'auto';
        }
        else {
            $i_duplex_admin->{$iid} = $p_duplex->{$port};
        }
    }
    return $i_duplex_admin;
}

sub i_speed_admin {
    my $stack   = shift;
    my $partial = shift;

    my %i_speed_admin;
    my $p_port  = $stack->p_port() || {};
    my %mapping = reverse %$p_port;
    my $p_speed = $stack->p_speed( $mapping{$partial} );

    my %speeds = (
        'autoDetect'      => 'auto',
        'autoDetect10100' => 'auto',
        's10000000'       => '10 Mbps',
        's100000000'      => '100 Mbps',
        's1000000000'     => '1.0 Gbps',
        's10G'            => '10 Gbps',
    );

    %i_speed_admin
        = map { $p_port->{$_} => $speeds{ $p_speed->{$_} } } keys %$p_port;

    return \%i_speed_admin;
}

sub set_i_speed_admin {

    # map speeds to those the switch will understand
    my %speeds = qw/auto 1 10 10000000 100 100000000 1000 1000000000/;

    my $stack = shift;
    my ( $speed, $iid ) = @_;
    my $p_port = $stack->p_port() || {};
    my %reverse_p_port = reverse %$p_port;

    $speed = lc($speed);

    return 0 unless defined $speeds{$speed};

    $iid = $reverse_p_port{$iid};

    return $stack->set_p_speed( $speeds{$speed}, $iid );
}

sub set_i_duplex_admin {

    # map a textual duplex to an integer one the switch understands
    my %duplexes = qw/half 1 full 2 auto 4/;

    my $stack = shift;
    my ( $duplex, $iid ) = @_;
    if ( $duplex eq 'auto' ) {
        $stack->error_throw(
            "Software doesn't support setting auto duplex with
                            set_i_duplex_admin() you must use
                            set_i_speed_admin() and set both speed and duplex
                            to auto"
        );
        return 0;
    }

    my $p_port = $stack->p_port() || {};
    my %reverse_p_port = reverse %$p_port;

    $duplex = lc($duplex);

    return 0 unless defined $duplexes{$duplex};

    $iid = $reverse_p_port{$iid};

    return $stack->set_p_duplex( $duplexes{$duplex}, $iid );
}

1;

__END__

=head1 NAME

SNMP::Info::CiscoStack - SNMP Interface to data from F<CISCO-STACK-MIB> and
F<CISCO-PORT-SECURITY-MIB>

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $ciscostats = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $ciscostats->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::CiscoStack is a subclass of SNMP::Info that provides
an interface to the C<CISCO-STACK-MIB>.  This MIB is used across
the Catalyst family under CatOS and IOS.

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

none.

=head2 Required MIBs

=over

=item F<CISCO-STACK-MIB>

=back

=head1 GLOBALS

=over

=item $stack->broadcast()

(C<sysBroadcast>)

=item $stack->fan()

(C<chassisFanStatus>)

=item $stack->model()

(C<chassisModel>)

=item $stack->netmask()

(C<sysNetMask>)

=item $stack->ps1_type()

(C<chassisPs1Type>)

=item $stack->ps2_type()

(C<chassisPs2Type>)

=item $stack->ps1_status()

(C<chassisPs1Status>)

=item $stack->ps2_status()

(C<chassisPs2Status>)

=item $stack->serial()

(C<chassisSerialNumberString>) or (C<chassisSerialNumber>)

=item $stack->slots()

(C<chassisNumSlots>)

=back

=head1 TABLE METHODS

=head2 Interface Tables

=over

=item $stack->i_physical()

Returns a map to IID for ports that are physical ports, not vlans, etc.

=item $stack->i_type()

Crosses p_port() with p_type() and returns the results. 

Overrides with C<ifType> if p_type() isn't available.

=item $stack->i_duplex()

Returns reference to hash of iid to current link duplex setting.

First checks for fixed gigabit ports which are always full duplex.  Next, if
the port is not operational and reported port duplex (C<portDuplex>) is auto
then the operational duplex can not be determined.  Otherwise it uses the
reported port duplex (C<portDuplex>).

=item $stack->i_duplex_admin()

Returns reference to hash of iid to administrative duplex setting.

First checks for fixed gigabit ports which are always full duplex. Next checks
the port administrative speed (C<portAdminSpeed>) which if set to
autonegotiate then the duplex will also autonegotiate, otherwise it uses the
reported port duplex (C<portDuplex>).

=item $stack->i_speed_admin()

Returns reference to hash of iid to administrative speed setting.

C<portAdminSpeed>

=item $stack->set_i_speed_admin(speed, ifIndex)

    Sets port speed, must be supplied with speed and port C<ifIndex>

    Speed choices are 'auto', '10', '100', '1000'

    Crosses $stack->p_port() with $stack->p_duplex() to
    utilize port C<ifIndex>.

    Example:
    my %if_map = reverse %{$stack->interfaces()};
    $stack->set_i_speed_admin('auto', $if_map{'FastEthernet0/1'}) 
        or die "Couldn't change port speed. ",$stack->error(1);

=item $stack->set_i_duplex_admin(duplex, ifIndex)

    Sets port duplex, must be supplied with duplex and port C<ifIndex>

    Speed choices are 'auto', 'half', 'full'

    Crosses $stack->p_port() with $stack->p_duplex() to
    utilize port C<ifIndex>.

    Example:
    my %if_map = reverse %{$stack->interfaces()};
    $stack->set_i_duplex_admin('auto', $if_map{'FastEthernet0/1'}) 
        or die "Couldn't change port duplex. ",$stack->error(1);

=back

=head2 Module table

This table holds configuration information for each of the blades installed in
the Catalyst device.

=over

=item $stack->m_type()

(C<moduleType>)

=item $stack->m_model()

(C<moduleModel>)

=item $stack->m_serial()

(C<moduleSerialNumber>)

=item $stack->m_status()

(C<moduleStatus>)

=item $stack->m_name()

(C<moduleName>)

=item $stack->m_ports()

(C<moduleNumPorts>)

=item $stack->m_ports_status()

Returns a list of space separated status strings for the ports.

To see the status of port 4 :

    @ports_status = split(' ', $stack->m_ports_status() );
    $port4 = $ports_status[3];

(C<modulePortStatus>)

=item $stack->m_ports_hwver()

(C<moduleHwVersion>)

=item $stack->m_ports_fwver()

(C<moduleFwVersion>)

=item $stack->m_ports_swver()

(C<moduleSwVersion>)

=item $stack->m_ports_ip()

(C<moduleIPAddress>)

=item $stack->m_ports_sub1()

(C<moduleSubType>)

=item $stack->m_ports_sub2()

(C<moduleSubType2>)

=back

=head2 Modules - Router Blades

=over

=item $stack->m_ip()

(C<moduleIPAddress>)

=item $stack->m_sub1()

(C<moduleSubType>)

=item $stack->m_sub2()

(C<moduleSubType2>)

=back

=head2 Port Entry Table (C<CISCO-STACK-MIB::portTable>)

=over

=item $stack->p_name()

(C<portName>)

=item $stack->p_type()

(C<portType>)

=item $stack->p_status()

(C<portOperStatus>)

=item $stack->p_status2()

(C<portAdditionalStatus>)

=item $stack->p_speed()

(C<portAdminSpeed>)

=item $stack->p_duplex()

(C<portDuplex>)

=item $stack->p_port()

(C<portIfIndex>)

=item $stack->p_rx_flow_control()

Can be either C<on> C<off> or C<disagree>

"Indicates the receive flow control operational status of the port. If the
port could not agree with the far end on a link protocol, its operational
status will be disagree(3)."

C<portOperRxFlowControl>

=item $stack->p_tx_flow_control()

Can be either C<on> C<off> or C<disagree>

"Indicates the transmit flow control operational status of the port. If the
port could not agree with the far end on a link protocol, its operational
status will be disagree(3)."

C<portOperTxFlowControl>

=item $stack->p_rx_flow_control_admin()

Can be either C<on> C<off> or C<desired>

"Indicates the receive flow control administrative status set on the port. If
the status is set to on(1), the port will require the far end to send flow
control. If the status is set to off(2), the port will not allow far end to
send flow control.  If the status is set to desired(3), the port will allow
the far end to send the flow control."

C<portAdminRxFlowControl>

=item $stack->p_tx_flow_control_admin()

Can be either C<on> C<off> or C<desired>

"Indicates the transmit flow control administrative status set on the port.
If the status is set to on(1), the port will send flow control to the far end.  If
the status is set to off(2), the port will not send flow control to the far
end. If the status is set to desired(3), the port will send flow control to
the far end if the far end supports it."

C<portAdminTxFlowControl>

=back

=head2 Port Capability Table (C<CISCO-STACK-MIB::portCpbTable>)

=over

=item $stack->p_speed_admin()

(C<portCpbSpeed>)

=item $stack->p_duplex_admin()

(C<portCpbDuplex>)

=back

=head1 Data Munging Callback Subroutines

=over

=item $stack->munge_port_status()

Munges binary byte describing each port into ascii, and returns an ascii
list separated by spaces.

=back

=cut
