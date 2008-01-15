# SNMP::Info::CiscoPortSecurity
# Eric Miller
#
# Copyright (c) 2006 Eric Miller 
#
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
#     * Neither the name of the author nor the 
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

package SNMP::Info::CiscoPortSecurity;
$VERSION = '1.07';
# $Id: CiscoPortSecurity.pm,v 1.4 2007/12/07 23:13:01 jeneric Exp $

use strict;

use Exporter;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE %PAECAPABILITIES/;
@SNMP::Info::CiscoPortSecurity::ISA = qw/Exporter/;
@SNMP::Info::CiscoPortSecurity::EXPORT_OK = qw//;

%MIBS    = (
            'CISCO-PORT-SECURITY-MIB' => 'ciscoPortSecurityMIB',
 	    'CISCO-PAE-MIB'           => 'ciscoPaeMIB',
            'IEEE8021-PAE-MIB'        => 'dot1xAuthLastEapolFrameSource',
           );

%GLOBALS = (
            # CISCO-PORT-SECURITY-MIB
            'cps_clear'     => 'cpsGlobalClearSecureMacAddresses',
            'cps_notify'    => 'cpsGlobalSNMPNotifControl',
            'cps_rate'      => 'cpsGlobalSNMPNotifRate',
            'cps_enable'    => 'cpsGlobalPortSecurityEnable',
            'cps_mac_count' => 'cpsGlobalTotalSecureAddress',
            'cps_mac_max'   => 'cpsGlobalMaxSecureAddress',
           );

%FUNCS   = (
            # CISCO-PORT-SECURITY-MIB::cpsIfConfigTable
            'cps_i_limit_val'  => 'cpsIfInvalidSrcRateLimitValue',
            'cps_i_limit'      => 'cpsIfInvalidSrcRateLimitEnable',
            'cps_i_sticky'     => 'cpsIfStickyEnable',
            'cps_i_clear_type' => 'cpsIfClearSecureMacAddresses',
            'cps_i_shutdown'   => 'cpsIfShutdownTimeout',
            'cps_i_flood'      => 'cpsIfUnicastFloodingEnable',
            'cps_i_clear'      => 'cpsIfClearSecureAddresses',
            'cps_i_mac'        => 'cpsIfSecureLastMacAddress',
            'cps_i_count'      => 'cpsIfViolationCount',
            'cps_i_action'     => 'cpsIfViolationAction',
            'cps_i_mac_static' => 'cpsIfStaticMacAddrAgingEnable',
            'cps_i_mac_type'   => 'cpsIfSecureMacAddrAgingType',
            'cps_i_mac_age'    => 'cpsIfSecureMacAddrAgingTime',
            'cps_i_mac_count'  => 'cpsIfCurrentSecureMacAddrCount',
            'cps_i_mac_max'    => 'cpsIfMaxSecureMacAddr',
            'cps_i_status'     => 'cpsIfPortSecurityStatus',
            'cps_i_enable'     => 'cpsIfPortSecurityEnable',
            # CISCO-PORT-SECURITY-MIB::cpsIfVlanTable
            'cps_i_v_mac_count' => 'cpsIfVlanCurSecureMacAddrCount',
            'cps_i_v_mac_max'   => 'cpsIfVlanMaxSecureMacAddr',
            'cps_i_v'           => 'cpsIfVlanIndex',
            # CISCO-PORT-SECURITY-MIB::cpsIfVlanSecureMacAddrTable
            'cps_i_v_mac_status' => 'cpsIfVlanSecureMacAddrRowStatus',
            'cps_i_v_mac_age'    => 'cpsIfVlanSecureMacAddrRemainAge',
            'cps_i_v_mac_type'   => 'cpsIfVlanSecureMacAddrType',
            'cps_i_v_vlan'       => 'cpsIfVlanSecureVlanIndex',
            'cps_i_v_mac'        => 'cpsIfVlanSecureMacAddress',
            # CISCO-PORT-SECURITY-MIB::cpsSecureMacAddressTable
            'cps_m_status' => 'cpsSecureMacAddrRowStatus',
            'cps_m_age'    => 'cpsSecureMacAddrRemainingAge',
            'cps_m_type'   => 'cpsSecureMacAddrType',
            'cps_m_mac'    => 'cpsSecureMacAddress',
 	    # CISCO-PAE-MIB::dot1xPaePortEntry
            'pae_i_capabilities'             => 'dot1xPaePortCapabilities',
            'pae_i_last_eapol_frame_source'  => 'dot1xAuthLastEapolFrameSource',
           );

%MUNGE   = (
            'cps_i_mac'                      => \&SNMP::Info::munge_mac, 
            'cps_m_mac'                      => \&SNMP::Info::munge_mac,
            'cps_i_v_mac'                    => \&SNMP::Info::munge_mac,
            'pae_i_last_eapol_frame_source'  => \&SNMP::Info::munge_mac,
            'pae_i_capabilities'             => \&munge_pae_capabilities,
           );

%PAECAPABILITIES = (0 => 'dot1xPaePortAuthCapable',
 		    1 => 'dot1xPaePortSuppCapable');

sub munge_pae_capabilities {
    my $bits = shift;

    return undef unless defined $bits;
    my @vals = map($PAECAPABILITIES{$_},sprintf("%x",unpack('b*',$bits)));
    return join(' ',@vals);
}

1;
__END__

=head1 NAME

SNMP::Info::CiscoPortSecurity - SNMP Interface to data from
CISCO-PORT-SECURITY-MIB and CISCO-PAE-MIB

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $cps = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $cps->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::CiscoPortSecurity is a subclass of SNMP::Info that provides
an interface to the C<CISCO-PORT-SECURITY-MIB> and C<CISCO-PAE-MIB>.  These
MIBs are used across the Catalyst family under CatOS and IOS.

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item CISCO-PORT-SECURITY-MIB

=item CISCO-PAE-MIB

=item IEEE8021-PAE-MIB

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz or from
Netdisco-mib package at netdisco.org. 

=head1 GLOBALS

These are methods that return scalar values from SNMP

=over

=back

=head2 CISCO-PORT-SECURITY-MIB globals

=over

=item $stack->cps_clear()

(B<cpsGlobalClearSecureMacAddresses>)

=item $stack->cps_notify()

(B<cpsGlobalSNMPNotifControl>)

=item $stack->cps_rate()

(B<cpsGlobalSNMPNotifRate>)

=item $stack->cps_enable()

(B<cpsGlobalPortSecurityEnable>)

=item $stack->cps_mac_count()

(B<cpsGlobalTotalSecureAddress>)

=item $stack->cps_mac_max()

(B<cpsGlobalMaxSecureAddress>)

=back

=head1 TABLE METHODS

=head2 CISCO-PORT-SECURITY-MIB - Interface Config Table

=over

=item $stack->cps_i_limit_val()

(B<cpsIfInvalidSrcRateLimitValue>)

=item $stack->cps_i_limit()

(B<cpsIfInvalidSrcRateLimitEnable>)

=item $stack->cps_i_sticky()

(B<cpsIfStickyEnable>)

=item $stack->cps_i_clear_type()

(B<cpsIfClearSecureMacAddresses>)

=item $stack->cps_i_shutdown()

(B<cpsIfShutdownTimeout>)

=item $stack->cps_i_flood()

(B<cpsIfUnicastFloodingEnable>)

=item $stack->cps_i_clear()

(B<cpsIfClearSecureAddresses>)

=item $stack->cps_i_mac()

(B<cpsIfSecureLastMacAddress>)

=item $stack->cps_i_count()

(B<cpsIfViolationCount>)

=item $stack->cps_i_action()

(B<cpsIfViolationAction>)

=item $stack->cps_i_mac_static()

(B<cpsIfStaticMacAddrAgingEnable>)

=item $stack->cps_i_mac_type()

(B<cpsIfSecureMacAddrAgingType>)

=item $stack->cps_i_mac_age()

(B<cpsIfSecureMacAddrAgingTime>)

=item $stack->cps_i_mac_count()

(B<cpsIfCurrentSecureMacAddrCount>)

=item $stack->cps_i_mac_max()

(B<cpsIfMaxSecureMacAddr>)

=item $stack->cps_i_status()

(B<cpsIfPortSecurityStatus>)

=item $stack->cps_i_enable()

(B<cpsIfPortSecurityEnable>)

=back

=head2 CISCO-PORT-SECURITY-MIB::cpsIfVlanTable

=over

=item $stack->cps_i_v_mac_count()

(B<cpsIfVlanCurSecureMacAddrCount>)

=item $stack->cps_i_v_mac_max()

(B<cpsIfVlanMaxSecureMacAddr>)

=item $stack->cps_i_v()

(B<cpsIfVlanIndex>)

=back

=head2 CISCO-PORT-SECURITY-MIB::cpsIfVlanSecureMacAddrTable

=over

=item $stack->cps_i_v_mac_status()

(B<cpsIfVlanSecureMacAddrRowStatus>)

=item $stack->cps_i_v_mac_age()

(B<cpsIfVlanSecureMacAddrRemainAge>)

=item $stack->cps_i_v_mac_type()

(B<cpsIfVlanSecureMacAddrType>)

=item $stack->cps_i_v_vlan()

(B<cpsIfVlanSecureVlanIndex>)

=item $stack->cps_i_v_mac()

(B<cpsIfVlanSecureMacAddress>)

=back

=head2 CISCO-PORT-SECURITY-MIB::cpsSecureMacAddressTable

=over

=item $stack->cps_m_status()

(B<cpsSecureMacAddrRowStatus>)

=item $stack->cps_m_age()

(B<cpsSecureMacAddrRemainingAge>)

=item $stack->cps_m_type()

(B<cpsSecureMacAddrType>)

=item $stack->cps_m_mac()

(B<cpsSecureMacAddress>)

=back

=head2 CISCO-PAE-MIB::dot1xPaePortEntry

=over

=item $stack->pae_i_capabilities()

B<dot1xPaePortCapabilities>

Indicates the PAE functionality that this Port supports
and that may be managed through this MIB.

=back

=cut
