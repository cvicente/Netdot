# SNMP::Info::Layer2::Allied
# $Id: Allied.pm,v 1.17 2008/08/02 03:21:57 jeneric Exp $
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

package SNMP::Info::Layer2::Allied;

use strict;
use Exporter;
use SNMP::Info::Layer2;
use SNMP::Info::Layer1;

@SNMP::Info::Layer2::Allied::ISA       = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::Allied::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%GLOBALS = ( %SNMP::Info::Layer2::GLOBALS );

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,
    'ip_adresses' => 'atNetAddress',
    'ip_mac'      => 'atPhysAddress',
);

%MIBS = (
    %SNMP::Info::Layer2::MIBS,
    'AtiSwitch-MIB'    => 'atiswitchProductType',
    'AtiStackInfo-MIB' => 'atiswitchEnhancedStacking',
);

%MUNGE = ( %SNMP::Info::Layer2::MUNGE, );

sub vendor {
    return 'allied';
}

sub os {
    return 'allied';
}

sub os_ver {
    my $allied = shift;
    my $descr  = $allied->description();

    if ( $descr =~ m/version (\d+\.\d+)/ ) {
        return $1;
    }
}

sub model {
    my $allied = shift;

    my $desc = $allied->description();

    if ( $desc =~ /(AT-80\d{2}\S*)/ ) {
        return $1;
    }
    return;
}

sub root_ip {
    my $allied  = shift;
    my $ip_hash = $allied->ip_addresses();
    my $found_ip;

    foreach my $ip ( values %{$ip_hash} ) {
        $found_ip = SNMP::Info::munge_ip($ip) if ( defined $ip );
        last;    # this is only one IP address
    }
    return $found_ip;
}

sub mac {
    my $allied   = shift;
    my $mac_hash = $allied->ip_mac();
    my $found_mac;

    foreach my $mac ( values %{$mac_hash} ) {
        $found_mac = SNMP::Info::munge_mac($mac);
        last;    # this is only one MAC address
    }
    return $found_mac;
}

sub i_up {
    my $allied  = shift;
    my $partial = shift;

    my $i_up = SNMP::Info::Layer1::i_up( $allied, $partial );

    foreach my $port ( keys %$i_up ) {
        my $up = $i_up->{$port};
        $i_up->{$port} = 'down' if $up eq 'linktesterror';
        $i_up->{$port} = 'up'   if $up eq 'nolinktesterror';
    }

    return $i_up;
}
1;
__END__

=head1 NAME

SNMP::Info::Layer2::Allied - SNMP Interface to Allied Telesyn switches

=head1 AUTHOR

Max Baker, Dmitry Sergienko <dmitry@trifle.net>

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $allied = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myhub',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $allied->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Allied device through SNMP. See inherited classes' documentation for 
inherited methods.

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item F<AtiSwitch-MIB>

=item F<AtiStackInfo-MIB>

Download for your device from ftp://ftp.allied-telesyn.com/pub/switches/mibs/

=back

=head2 Inherited MIBs

See L<SNMP::Info::Layer2/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=head2 Overrides

=over

=item $allied->vendor()

Returns 'allied' :)

=item $allied->os()

Returns 'allied' 

=item $allied->os_ver()

Culls Version from description()

=item $allied->root_ip()

Returns IP Address of Managed Device.

(C<actualIpAddr>)

=item $allied->model()

Tries to cull out C<AT-nnnnX> out of the description field.

=item $allied->mac()

Returns device MAC. 

=back

=head2 Globals imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

=head2 Overrides

=over

=item $allied->i_up()

Returns reference to map of IIDs to link status.  Changes
the values of ati_up() to 'up' and 'down'.

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
