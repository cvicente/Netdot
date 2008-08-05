# SNMP::Info::Layer3::NetSNMP
# $Id: NetSNMP.pm,v 1.9 2008/08/02 03:21:47 jeneric Exp $
#
# Copyright (c) 2008 Bill Fenner
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

package SNMP::Info::Layer3::NetSNMP;

use strict;
use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::NetSNMP::ISA       = qw/SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::NetSNMP::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    'UCD-SNMP-MIB'       => 'versionTag',
    'NET-SNMP-TC'        => 'netSnmpAgentOIDs',
    'HOST-RESOURCES-MIB' => 'hrSystem',
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    'netsnmp_vers'   => 'versionTag',
    'hrSystemUptime' => 'hrSystemUptime',
);

%FUNCS = ( %SNMP::Info::Layer3::FUNCS, );

%MUNGE = ( %SNMP::Info::Layer3::MUNGE, );

sub vendor {
    return 'Net-SNMP';
}

sub os {
    my $netsnmp = shift;
    my $descr   = $netsnmp->description();

    return $1 if ( $descr =~ /^(\S+)\s+/ );
    return;
}

sub os_ver {
    my $netsnmp = shift;
    my $descr   = $netsnmp->description();
    my $vers    = $netsnmp->netsnmp_vers();
    my $os_ver  = undef;

    $os_ver = $1 if ( $descr =~ /^\S+\s+\S+\s+(\S+)\s+/ );
    if ($vers) {
        $os_ver = "???" unless defined($os_ver);
        $os_ver .= " / Net-SNMP " . $vers;
    }

    return $os_ver;
}

sub serial {
    return '';
}

# sysUptime gives us the time since the SNMP daemon has restarted,
# so return the system uptime since that's probably what the user
# wants.  (Caution: this could cause trouble if using
# sysUptime-based discontinuity timers or other TimeStamp
# objects.
sub uptime {
    my $netsnmp = shift;
    my $uptime;

    $uptime = $netsnmp->hrSystemUptime();
    return $uptime if defined $uptime;

    return $netsnmp->SUPER::uptime();
}

sub i_ignore {
    my $l3      = shift;
    my $partial = shift;

    my $interfaces = $l3->interfaces($partial) || {};

    my %i_ignore;
    foreach my $if ( keys %$interfaces ) {

        # lo0 etc
        if ( $interfaces->{$if} =~ /\blo\d*\b/i ) {
            $i_ignore{$if}++;
        }
    }
    return \%i_ignore;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::NetSNMP - SNMP Interface to L3 Net-SNMP Devices

=head1 AUTHORS

Bradley Baetz and Bill Fenner

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $netsnmp = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myrouter',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $netsnmp->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Generic Net-SNMP devices

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<UCD-SNMP-MIB>

=item F<NET-SNMP-TC>

=item F<HOST-RESOURCES-MIB>

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $netsnmp->vendor()

Returns 'Net-SNMP'.

=item $netsnmp->os()

Returns the OS extracted from C<sysDescr>.

=item $netsnmp->os_ver()

Returns the software version extracted from C<sysDescr>, along
with the Net-SNMP version.

=item $netsnmp->uptime()

Returns the system uptime instead of the agent uptime.
NOTE: discontinuity timers and other Time Stamp based objects
are based on agent uptime, so use orig_uptime().

=item $netsnmp->serial()

Returns ''.

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3> for details.

=head1 TABLE ENTRIES

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $netsnmp->i_ignore()

Returns reference to hash.  Increments value of IID if port is to be ignored.

Ignores loopback

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3> for details.

=head1 NOTES

In order to cause SNMP::Info to classify your device into this class, it
may be necessary to put a configuration line into your F<snmpd.conf>
similar to

  sysobjectid .1.3.6.1.4.1.8072.3.2.N

where N is the object ID for your OS from the C<NET-SNMP-TC> MIB (or
255 if not listed).  Some Net-SNMP installations default to an
incorrect return value for C<system.sysObjectId>.

In order to recognize a Net-SNMP device as Layer3, it may be necessary
to put a configuration line similar to

  sysservices 76

in your F<snmpd.conf>.

=cut
