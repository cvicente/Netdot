# SNMP::Info::CiscoQOS
# $Id: CiscoQOS.pm,v 1.13 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2005 Alexander Hartmaier
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

package SNMP::Info::CiscoQOS;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::CiscoQOS::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::CiscoQOS::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( 'CISCO-CLASS-BASED-QOS-MIB' => 'cbQosIfIndex', );

%GLOBALS = ();

%FUNCS = (

    # CISCO-CLASS-BASED-QOS-MIB::cbQosServicePolicyTable
    'qos_i_index'       => 'cbQosIfIndex',
    'qos_i_type'        => 'cbQosIfType',
    'qos_pol_direction' => 'cbQosPolicyDirection',

    # CISCO-CLASS-BASED-QOS-MIB::cbQosObjectsTable
    'qos_obj_conf_index' => 'cbQosConfigIndex',
    'qos_obj_type'       => 'cbQosObjectsType',
    'qos_obj_parent'     => 'cbQosParentObjectsIndex',

    # CISCO-CLASS-BASED-QOS-MIB::cbQosCMCfgTable
    'qos_cm_name' => 'cbQosCMName',
    'qos_cm_desc' => 'cbQosCMDesc',
    'qos_cm_info' => 'cbQosCMInfo',

    # CISCO-CLASS-BASED-QOS-MIB::cbQosCMStatsTable
    'qos_octet_pre'  => 'cbQosCMPrePolicyByte',
    'qos_octet_post' => 'cbQosCMPostPolicyByte',

    # CISCO-CLASS-BASED-QOS-MIB::cbQosQueueingCfgTable
    'qos_queueingcfg_bw'       => 'cbQosQueueingCfgBandwidth',
    'qos_queueingcfg_bw_units' => 'cbQosQueueingCfgBandwidthUnits',
);

%MUNGE = ();

1;
__END__

=head1 NAME

SNMP::Info::CiscoQOS - SNMP Interface to Cisco's Quality of Service MIBs

=head1 AUTHOR

Alexander Hartmaier

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $qos = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $qos->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::CiscoQOS is a subclass of SNMP::Info that provides 
information about a cisco device's QoS config.

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

none.

=head2 Required MIBs

=over

=item F<CISCO-CLASS-BASED-QOS-MIB>

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBALS

=over

=item none

=back

=head1 TABLE METHODS

=head2 Service Policy Table (C<cbQosServicePolicyTable>)

This table describes the interfaces/media types and the policy map that are
attached to it.

=over

=item $qos->qos_i_index()

(C<cbQosIfIndex>)

=item $qos->qos_i_type()

(C<cbQosIfType>)

=item $qos->qos_pol_direction()

(C<cbQosPolicyDirection>)

=back

=head2 Class Map Objects Table (C<cbQosObjectsTable>)

=over

=item $qos->qos_obj_index()

(C<cbQosConfigIndex>)

=item $qos->qos_obj_type()

(C<cbQosObjectsType>)

=item $qos->qos_obj_parent()

(C<cbQosParentObjectsIndex>)

=back

=head2 Class Map Configuration Table (C<cbQosCMCfgTable>)

=over

=item $qos->qos_cm_name()

(C<cbQosCMName>)

=item $qos->qos_cm_desc()

(C<cbQosCMDesc>)

=item $qos->qos_cm_info()

(C<cbQosCMInfo>)

=back

=head2 Class Map Stats Table (C<cbQosCMStatsTable>)

=over

=item $qos->qos_octet_pre()

(C<cbQosCMPrePolicyByte>)

=item $qos->qos_octet_post()

(C<cbQosCMPostPolicyByte>)

=back

=head2 Queueing Configuration Table (C<cbQosQueueingCfgTable>)

=over

=item $qos->qos_queueingcfg_bw()

(C<cbQosQueueingCfgBandwidth>)

=item $qos->qos_queueingcfg_bw_units()

(C<cbQosQueueingCfgBandwidthUnits>)

=back

=cut
