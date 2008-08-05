# SNMP::Info::Layer3::Aironet
# $Id: Aironet.pm,v 1.24 2008/08/02 03:21:47 jeneric Exp $
#
# Copyright (c) 2008 Max Baker changes from version 0.8 and beyond.
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

package SNMP::Info::Layer3::Aironet;

use strict;
use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::Aironet::ISA       = qw/SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Aironet::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    'AWCVX-MIB'        => 'awcIfTable',
    'IEEE802dot11-MIB' => 'dot11StationID',
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    'mac' => 'dot11StationID.2',

    # AWC Ethernet Table
    'awc_duplex' => 'awcEtherDuplex.0',
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS,
    'i_mac2' => 'ifPhysAddress',
    'i_mtu2' => 'ifMtu',
    'i_ssid' => 'dot11DesiredSSID',

    # Bridge-mib overrides
    'fw_mac2'   => 'dot1dTpFdbAddress',
    'fw_port2'  => 'dot1dTpFdbPort',
    'bp_index2' => 'dot1dBasePortIfIndex',

    # AWC Interface Table (awcIfTable)
    'awc_default_mac' => 'awcIfDefaultPhyAddress',
    'awc_mac'         => 'awcIfPhyAddress',
    'awc_ip'          => 'awcIfIpAddress',
    'awc_netmask'     => 'awcIfIpNetMask',
    'awc_msdu'        => 'awcIfMSDUMaxLength',
);

%MUNGE = (

    # Inherit all the built in munging
    %SNMP::Info::Layer3::MUNGE,
    'i_mac2'  => \&SNMP::Info::munge_mac,
    'awc_mac' => \&SNMP::Info::munge_mac,
    'fw_mac2' => \&SNMP::Info::munge_mac,
);

sub os {
    return 'aironet';
}

sub os_ver {
    my $aironet = shift;
    my $descr = $aironet->description() || '';

    # CAP340 11.21, AP4800-E 11.21
    if ( $descr =~ /AP\d{3,4}(-\D+)?\s+(\d{2}\.\d{2})/ ) {
        return $2;
    }

    if ( $descr =~ /Series\s*AP\s+(\d{2}\.\d{2})/ ) {
        return $1;
    }

    return;
}

# Override wireless port with static info
sub bp_index {
    my $aironet    = shift;
    my $interfaces = $aironet->interfaces();
    my $bp_index   = $aironet->bp_index2();

    foreach my $iid ( keys %$interfaces ) {
        my $port = $interfaces->{$iid};

        # Hardwire the wireless port to the transparent bridge port
        if ( $port =~ /awc/ ) {
            $bp_index->{0} = $iid;
        }
    }

    return $bp_index;
}

# Add the static table to the forwarding table
sub fw_mac {
    my $aironet = shift;
    my $fw_mac  = $aironet->fw_mac2();
    my $fw_port = $aironet->fw_port2();
    my $bs_mac  = $aironet->bs_mac();

    # remove port 0 forwarding table entries, only port 0 static entries
    foreach my $fw ( keys %$fw_mac ) {
        my $port = $fw_port->{$fw};
        next unless defined $port;
        delete $fw_mac->{$fw} if $port == 0;
    }

    foreach my $bs ( keys %$bs_mac ) {
        my $entry = $bs;
        $entry =~ s/\.0$//;
        $fw_mac->{$entry} = $bs_mac->{$bs};
    }

    return $fw_mac;
}

# Add the static table to the forwarding table
sub fw_port {
    my $aironet = shift;
    my $fw_port = $aironet->fw_port2();
    my $bs_port = $aironet->bs_port();

    foreach my $bs ( keys %$bs_port ) {
        my $entry = $bs;
        $entry =~ s/\.0$//;
        $fw_port->{$entry} = $bs_port->{$bs};
    }

    return $fw_port;
}

sub i_duplex {
    my $aironet    = shift;
    my $interfaces = $aironet->interfaces();
    my $awc_duplex = $aironet->awc_duplex();

    my %i_duplex;

    foreach my $iid ( keys %$interfaces ) {
        my $name = $interfaces->{$iid};

        if ( $name =~ /fec/ ) {
            $i_duplex{$iid} = $awc_duplex;
        }
    }

    return \%i_duplex;
}

sub i_mac {
    my $aironet = shift;

    my $i_mac   = $aironet->i_mac2();
    my $awc_mac = $aironet->awc_mac();

    foreach my $iid ( keys %$awc_mac ) {
        next unless defined $i_mac->{$iid};
        $i_mac->{$iid} = $awc_mac->{$iid};
    }

    return $i_mac;
}

sub i_ignore {
    my $aironet    = shift;
    my $interfaces = $aironet->interfaces();

    my %i_ignore;
    foreach my $if ( keys %$interfaces ) {
        $i_ignore{$if}++ if ( $interfaces->{$if} =~ /(rptr|lo)/ );
    }

    return \%i_ignore;
}

sub vendor {
    return 'cisco';
}

1;
__END__


=head1 NAME

SNMP::Info::Layer3::Aironet - Perl5 Interface to Cisco Aironet Wireless
Devices running Aironet software, not IOS

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $aironet = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $aironet->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info subclass to provide access to SNMP data for an Aironet device
running Aironet software, not cisco IOS.

Note there are two classes for Aironet devices :

=over

=item SNMP::Info::Layer3::Aironet

This class is for devices running Aironet software (older)

=item SNMP::Info::Layer2::Aironet

This class is for devices running Cisco IOS software (newer)

=back

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $aironet = new SNMP::Info::Layer3::Aironet(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<AWCVX-MIB>

=item F<IEEE802dot11-MIB>

=back

These MIBs are now included in the v2.tar.gz archive available from
ftp.cisco.com.  Make sure you have a current version. 

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $aironet->awc_duplex()

Gives the admin duplex setting for the Ethernet Port.

C<awcEtherDuplex.0>

=item $aironet->mac()

Gives the MAC Address of the wireless side 

C<dot11StationID.2>

=item $aironet->os()

'aironet'

=item $aironet->os_ver

Tries to cull the version from the description field.

=item $aironet->vendor()

Returns 'cisco'.

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $aironet->bp_index()

Takes the bp_index() value from SNMP::Info::Bridge and overrides the wireless
port to be assigned to the transparent bridge port (port 0)

=item $aironet->fw_mac()

Adds static table entries from bs_mac() to port 0 so that wireless MAC
addresses will be reported.  Forwarding table entries for port 0 are removed.

=item $aironet->fw_port()

Adds the static table port mappings to the forwarding table port mappings by
adding bs_port() to fw_port()

=item $aironet->i_duplex()

Adds the value of awc_duplex() to each Ethernet port seen.

=item $aironet->i_mac()

Overrides the values for i_mac with the value from awc_mac() if they are set.

=item $aironet->i_ignore()

Ignores ports that are of type ``rptr'' and ``lo''.

=back

=head2 Aironet specific items

=over

=item $aironet->awc_default_mac()

Gives the default MAC address of each interface.

C<awcIfDefaultPhyAddress>

=item $aironet->awc_mac()

Gives the actual MAC address of each interface.

C<awcIfPhyAddress>

=item $aironet->awc_ip()

Gives the IP Address assigned to each interface.

C<awcIfIpAddress>

=item $aironet->awc_netmask()

Gives the NetMask for each interface.

C<awcIfIpNetMask>

=item $aironet->awc_msdu()

C<awcIfMSDUMaxLength>

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
