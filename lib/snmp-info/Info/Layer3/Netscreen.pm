# SNMP::Info::Layer3::Netscreen
# $Id: Netscreen.pm,v 1.8 2008/08/02 03:21:47 jeneric Exp $
#
# Copyright (c) 2008 Eric Miller
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

package SNMP::Info::Layer3::Netscreen;

use strict;
use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::Netscreen::ISA       = qw/SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Netscreen::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    'NETSCREEN-SMI'           => 'netscreenSetting',
    'NETSCREEN-PRODUCTS-MIB'  => 'netscreenGeneric',
    'NETSCREEN-INTERFACE-MIB' => 'nsIfIndex',
    'NETSCREEN-SET-GEN-MIB'   => 'nsSetGenSwVer',
);

%GLOBALS = ( %SNMP::Info::Layer3::GLOBALS, 'os_version' => 'nsSetGenSwVer', );

%FUNCS = ( %SNMP::Info::Layer3::FUNCS, );

%MUNGE = ( %SNMP::Info::Layer3::MUNGE, );

sub layers {
    return '01001100';
}

sub vendor {
    return 'netscreen';
}

sub os {
    return 'screenos';
}

sub os_ver {
    my $netscreen = shift;

    my $descr = $netscreen->description();
    if ( $descr =~ m/version (\d\S*) \(SN: / ) {
        return $1;
    }
    return;
}

sub serial {
    my $netscreen = shift;

    my $e_serial = $netscreen->e_serial() || {};

    my $serial = $e_serial->{1} || undef;

    return $1 if ( defined $serial and $serial =~ /(\d+)/ );
    my $descr = $netscreen->description();
    if ( $descr =~ m/version .*\(SN: (\d\S*),/ ) {
        return $1;
    }
    return;
}

1;

__END__

=head1 NAME

SNMP::Info::Layer3::Netscreen - SNMP Interface to Juniper Netscreen Devices

=head1 AUTHOR

Kent Hamilton

=head1 SYNOPSIS

    #Let SNMP::Info determine the correct subclass for you.

    my $netscreen = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $netscreen->class();
    print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Netscreen device through SNMP. See inherited classes' documentation for 
inherited methods.

my $netscreen = new SNMP::Info::Layer3::Netscreen(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<NETSCREEN-SMI>

=item F<NETSCREEN-PRODUCTS-MIB>

=item F<NETSCREEN-INTERFACE-MIB>

=item F<NETSCREEN-SET-GEN-MIB>

=item Inherited Classes

See L<SNMP::Info::Layer3/"Required MIBs"> and its inherited classes.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $netscreen->vendor()

Returns 'netscreen'

=item $netscreen->os()

Returns C<'screenos'>

=item $netscreen->os_ver()

Extracts the OS version from the description string.

=item $netscreen->serial()

Returns serial number..

=back

=head2 Overrides

=over

=item $netscreen->layers()

Returns 01001100.  Device doesn't report layers properly, modified to reflect 
Layer3 functionality.

=back

=head2 Globals imported from SNMP::Info::Layer3

See L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Table Methods imported from SNMP::Info::Layer3

See L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut

