# SNMP::Info::CiscoRTT
# $Id: CiscoRTT.pm,v 1.10 2008/08/02 03:21:25 jeneric Exp $
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

package SNMP::Info::CiscoRTT;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::CiscoRTT::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::CiscoRTT::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( 'CISCO-RTTMON-MIB' => 'rttMonCtrlAdminOwner', );

%GLOBALS = ();

%FUNCS = (

    # CISCO-RTTMON-MIB
    'rtt_desc' => 'rttMonCtrlAdminOwner',
    'rtt_last' => 'rttMonLatestRttOperCompletionTime',
);

%MUNGE = ();

1;
__END__

=head1 NAME

SNMP::Info::CiscoRTT - SNMP Interface to Cisco's Round Trip Time MIBs

=head1 AUTHOR

Alexander Hartmaier

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $rtt = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $rtt->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::CiscoRTT is a subclass of SNMP::Info that provides 
information about a cisco device's RTT values.

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

none.

=head2 Required MIBs

=over

=item F<CISCO-RTTMON-MIB>

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBALS

=over

None

=back

=head1 TABLE METHODS

=head2 Overall Control Group Table

This table is from C<CISCO-RTTMAN-MIB::rttMonCtrlAdminTable>

=over

=item $rtt->rtt_desc()

(C<rttMonCtrlAdminOwner>)

=back

=head2 Overall Control Group Table

This table is from C<CISCO-RTTMON-MIB::rttMonCtrl>

=over

=item $rtt->rtt_last()

(C<rttMonLatestRttOperCompletionTime>)

=back

=cut
