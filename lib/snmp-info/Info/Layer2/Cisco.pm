# SNMP::Info::Layer2::Cisco
# $Id: Cisco.pm,v 1.9 2008/08/02 03:21:57 jeneric Exp $
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

package SNMP::Info::Layer2::Cisco;

use strict;
use Exporter;
use SNMP::Info::CiscoVTP;
use SNMP::Info::CDP;
use SNMP::Info::CiscoStats;
use SNMP::Info::CiscoImage;
use SNMP::Info::CiscoRTT;
use SNMP::Info::CiscoQOS;
use SNMP::Info::CiscoConfig;
use SNMP::Info::Layer2;

@SNMP::Info::Layer2::Cisco::ISA = qw/SNMP::Info::CiscoVTP SNMP::Info::CDP
    SNMP::Info::CiscoStats SNMP::Info::CiscoImage
    SNMP::Info::CiscoRTT SNMP::Info::CiscoQOS
    SNMP::Info::CiscoConfig SNMP::Info::Layer2
    Exporter/;
@SNMP::Info::Layer2::Cisco::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer2::MIBS,     %SNMP::Info::CiscoConfig::MIBS,
    %SNMP::Info::CiscoQOS::MIBS,   %SNMP::Info::CiscoRTT::MIBS,
    %SNMP::Info::CiscoImage::MIBS, %SNMP::Info::CiscoStats::MIBS,
    %SNMP::Info::CDP::MIBS,        %SNMP::Info::CiscoVTP::MIBS,
);

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,     %SNMP::Info::CiscoConfig::GLOBALS,
    %SNMP::Info::CiscoQOS::GLOBALS,   %SNMP::Info::CiscoRTT::GLOBALS,
    %SNMP::Info::CiscoImage::GLOBALS, %SNMP::Info::CiscoStats::GLOBALS,
    %SNMP::Info::CDP::GLOBALS,        %SNMP::Info::CiscoVTP::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,     %SNMP::Info::CiscoConfig::FUNCS,
    %SNMP::Info::CiscoQOS::FUNCS,   %SNMP::Info::CiscoRTT::FUNCS,
    %SNMP::Info::CiscoImage::FUNCS, %SNMP::Info::CiscoStats::FUNCS,
    %SNMP::Info::CDP::FUNCS,        %SNMP::Info::CiscoVTP::FUNCS,
);

%MUNGE = (
    %SNMP::Info::Layer2::MUNGE,     %SNMP::Info::CiscoConfig::MUNGE,
    %SNMP::Info::CiscoQOS::MUNGE,   %SNMP::Info::CiscoRTT::MUNGE,
    %SNMP::Info::CiscoImage::MUNGE, %SNMP::Info::CiscoStats::MUNGE,
    %SNMP::Info::CDP::MUNGE,        %SNMP::Info::CiscoVTP::MUNGE,
);

1;
__END__

=head1 NAME

SNMP::Info::Layer2::Cisco - SNMP Interface to L3 and L2+L3 IOS Cisco Device
that are not covered in other classes.

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $cisco = new SNMP::Info(
                        AutoSpecify => 1,
                        Debug       => 1,
                        # These arguments are passed directly to SNMP::Session
                        DestHost    => 'myswitch',
                        Community   => 'public',
                        Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $cisco->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Generic Cisco Routers running IOS

=head2 Inherited Classes

=over

=item SNMP::Info::CiscoVTP

=item SNMP::Info::CDP

=item SNMP::Info::CiscoStats

=item SNMP::Info::CiscoImage

=item SNMP::Info::CiscoRTT

=item SNMP::Info::CiscoQOS

=item SNMP::Info::CiscoConfig

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item Inherited Classes' MIBs

See L<SNMP::Info::CiscoVTP/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoStats/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CDP/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoImage/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoRTT/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoQOS/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoConfig/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::Layer2/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $cisco->vendor()

    Returns 'cisco'

=back

=head2 Global Methods imported from SNMP::Info::CiscoVTP

See documentation in L<SNMP::Info::CiscoVTP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoStats

See documentation in L<SNMP::Info::CiscoStats/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoImage

See documentation in L<SNMP::Info::CiscoImage/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoRTT

See documentation in L<SNMP::Info::CiscoRTT/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoQOS

See documentation in L<SNMP::Info::CiscoQOS/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoConfig

See documentation in L<SNMP::Info::CiscoConfig/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Table Methods imported from SNMP::Info::CiscoVTP

See documentation in L<SNMP::Info::CiscoVTP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoStats

See documentation in L<SNMP::Info::CiscoStats/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoImage

See documentation in L<SNMP::Info::CiscoImage/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoRTT

See documentation in L<SNMP::Info::CiscoRTT/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoQOS

See documentation in L<SNMP::Info::CiscoQOS/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoConfig

See documentation in L<SNMP::Info::CiscoConfig/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
