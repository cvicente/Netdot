# SNMP::Info::PowerEthernet
# $Id: PowerEthernet.pm,v 1.6 2008/08/02 03:21:25 jeneric Exp $
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

package SNMP::Info::PowerEthernet;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::PowerEthernet::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::PowerEthernet::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( 'POWER-ETHERNET-MIB' => 'pethPsePortDetectionStatus' );

%GLOBALS = ();

%FUNCS = (

    # parts of pethPsePortTable
    'peth_port_admin'  => 'pethPsePortAdminEnable',
    'peth_port_status' => 'pethPsePortDetectionStatus',
    'peth_port_class'  => 'pethPsePortPowerClassifications',

    # pethMainPseTable
    'peth_power_watts'       => 'pethMainPsePower',
    'peth_power_status'      => 'pethMainPseOperStatus',
    'peth_power_consumption' => 'pethMainPseConsumptionPower',
    'peth_power_threshold'   => 'pethMainPseUsageThreshold',
);

%MUNGE = ();

# POWER-ETHERNET-MIB doesn't define a mapping of its
# "module"/"port" index to ifIndex.  Different vendors
# do this in different ways.  This is a poor fallback:
# if all of the module values = 1, return the port number
# on the assumption that port number = ifindex.
# If there is a module != 1, this heuristic doesn't work
# so returns undef.
sub peth_port_ifindex {
    my $peth    = shift;
    my $partial = shift;

    my $peth_port_status = $peth->peth_port_status($partial);
    my $peth_port_ifindex;

    foreach my $i ( keys %$peth_port_status ) {
        my ( $module, $port ) = split( /\./, $i );
        if ( $module != 1 ) {

            # This heuristic won't work, so say that we got nothing.
            # If you have this case, you have to write a device-specific
            # version of this function.
            return;
        }
        $peth_port_ifindex->{$i} = $port;
    }
    return $peth_port_ifindex;
}

1;

__END__

=head1 NAME

SNMP::Info::PowerEthernet - SNMP Interface to data stored in
F<POWER-ETHERNET-MIB>.

=head1 AUTHOR

Bill Fenner

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $poe = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $poe->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

F<POWER-ETHERNET-MIB> is used to describe PoE (IEEE 802.3af)

Create or use a device subclass that inherit this class.  Do not use directly.

For debugging purposes you can call this class directly as you would
SNMP::Info

 my $poe = new SNMP::Info::PowerEthernet (...);

=head2 Inherited Classes

none.

=head2 Required MIBs

=over

=item F<POWER-ETHERNET-MIB>

=back

=head1 GLOBALS

none.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Power Port Table

Selected values from the C<pethPsePortTable>

=over

=item $poe->peth_port_admin()

Administrative status: is this port permitted to deliver power?

C<pethPsePortAdminEnable>

=item $poe->peth_port_status()

Current status: is this port delivering power, searching, disabled, etc?

C<pethPsePortDetectionStatus>

=item $poe->peth_port_class()

Device class: if status is delivering power, this represents the 802.3af
class of the device being powered.

C<pethPsePortPowerClassifications>

=item $poe->peth_port_ifindex()

A mapping function from the C<pethPsePortTable> INDEX of
module.port to an C<ifIndex>.  The default mapping ignores the
module (returning undef if there are any module values greater
than 1) and returns the port number, assuming that there is a
1:1 mapping.

This mapping is more or less left up to the device vendor to
implement; the MIB gives only very weak guidance.
A given device class may implement its own version
of this function (e.g., see Info::CiscoPower).

=back

=head2 Power Supply Table

=over

=item $poe->peth_power_watts()

The power supply's capacity, in watts.

C<pethMainPsePower>

=item $poe->peth_power_status()

The power supply's operational status.

C<pethMainPseOperStatus>

=item $poe->peth_power_consumption()

How much power, in watts, this power supply has been committed to
deliver.  (Note: certain devices seem to supply this value in milliwatts,
so be cautious interpreting it.)

C<pethMainPseConsumptionPower>

=item $poe->peth_power_threshold()

The threshold (in percent) of consumption required to raise an
alarm.

C<pethMainPseUsageThreshold>

=back

=cut
