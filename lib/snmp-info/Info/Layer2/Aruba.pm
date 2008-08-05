# SNMP::Info::Layer2::Aruba
# $Id: Aruba.pm,v 1.15 2008/08/02 03:21:57 jeneric Exp $
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

package SNMP::Info::Layer2::Aruba;

use strict;
use Exporter;
use SNMP::Info::Layer2;

@SNMP::Info::Layer2::Aruba::ISA       = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::Aruba::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer2::MIBS,
    'WLSX-SWITCH-MIB'         => 'wlsxHostname',
    'WLSX-WLAN-MIB'           => 'wlanAPFQLN',
    'WLSR-AP-MIB'             => 'wlsrHideSSID',
    #'ALCATEL-IND1-TP-DEVICES' => 'familyOmniAccessWireless',
);

%GLOBALS = ( %SNMP::Info::Layer2::GLOBALS, );

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,

    # WLSX-SWITCH-MIB::wlsxSwitchAccessPointTable
    # Table index leafs do not return information
    # therefore unable to use apBSSID.  We extract
    # the information from the IID instead.
    'aruba_ap_name'      => 'apLocation',
    'aruba_ap_ip'        => 'apIpAddress',
    'aruba_ap_essid'     => 'apESSID',
    'aruba_ap_ssidbcast' => 'wlsrHideSSID',

    # WLSX-WLAN-MIB::wlsxWlanAPTable
    'aruba_perap_fqln'   => 'wlanAPFQLN',

    # WLSR-AP-MIB::wlsrConfigTable
    'aruba_ap_channel' => 'apCurrentChannel',

    # WLSX-SWITCH-MIB::wlsxSwitchStationMgmtTable
    # Table index leafs do not return information
    # therefore unable to use staAccessPointBSSID
    # or staPhyAddress.  We extract the information from
    # the IID instead.
    #'fw_port'             => 'staAccessPointBSSID',
    #'fw_mac'              => 'staPhyAddress',
    'fw_user' => 'staUserName',
);

%MUNGE = ( %SNMP::Info::Layer2::MUNGE, );

sub layers {
    return '00000011';
}

sub os {
    my $aruba = shift;
    my %osmap = (
        'alcatel-lucent' => 'aos-w',
                );
    return $osmap{$aruba->vendor()} || 'airos';
}

sub vendor {
    my $aruba = shift;
    my $id     = $aruba->id() || 'undef';
    my %oidmap = (
                  6486 => 'alcatel-lucent',
                );
    $id = $1 if (defined($id) && $id =~ /^\.1\.3\.6\.1\.4\.1\.(\d+)/);

    if (defined($id) and exists($oidmap{$id})) {
        return $oidmap{$id};
    }
    else {
        return 'aruba';
    }
}

sub os_ver {
    my $aruba = shift;
    my $descr = $aruba->description();
    return unless defined $descr;

    if ( $descr =~ m/Version\s+(\d+\.\d+\.\d+\.\d+)/ ) {
        return $1;
    }

    return;
}

sub model {
    my $aruba = shift;
    my $id    = $aruba->id();
    return unless defined $id;
    my $model = &SNMP::translateObj($id);
    return $id unless defined $model;

    return $model;
}

# Thin APs do not support ifMIB requirement
#
# We return all BSSIDs as pseudo-ports on the controller.

sub i_index {
    my $aruba   = shift;
    my $partial = shift;

    my $i_index  = $aruba->orig_i_index($partial)  || {};
    my $ap_index = $aruba->aruba_ap_name($partial) || {};

    my %if_index;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        $if_index{$iid} = $index;
    }

    # Get Attached APs as Interfaces
    foreach my $ap_id ( keys %$ap_index ) {

        # Convert the 0.254.123.456 index entry to a MAC address.
        my $mac = join( ':',
            map { sprintf( "%02x", $_ ) } split( /\./, $ap_id ) );

        $if_index{$ap_id} = $mac;
    }
    return \%if_index;
}

sub interfaces {
    my $aruba   = shift;
    my $partial = shift;

    my $i_index = $aruba->i_index($partial)       || {};
    my $i_descr = $aruba->i_description($partial) || {};

    my %if;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {

            # Replace the Index with the ifDescr field.
            my $port = $i_descr->{$iid};
            next unless defined $port;
            $if{$iid} = $port;
        }

        elsif ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            $if{$index} = $index;
        }

        else {
            next;
        }
    }
    return \%if;
}

# Most items are indexed by BSSID.
# aruba_perap_fqln is indexed by AP, so we use the
# [haven't decided yet] index to figure out all of the
# BSSIDs served by a given radio.
sub aruba_ap_fqln {
    my $aruba  = shift;
    # I don't think $partial is meaningful in this context

    my $perap_fqln = $aruba->aruba_perap_fqln();
    my $channel = $aruba->wlanAPBssidChannel();
    my $aruba_ap_fqln = {};

    # Channel index is: AP, radio, BSSID
    foreach my $idx (keys %$channel) {
	my @oid = split(/\./, $idx );
	my $ap = join(".", @oid[0..5]);
        my $bssid = join(".", @oid[7..12]);
	$aruba_ap_fqln->{$bssid} = $perap_fqln->{$ap};
    }

    return $aruba_ap_fqln;
}

sub i_name {
    my $aruba   = shift;
    my $partial = shift;

    my $i_index = $aruba->i_index($partial)       || {};
    my $i_name2 = $aruba->orig_i_name($partial)   || {};
    my $ap_name = $aruba->aruba_ap_name($partial) || {};
    my $ap_fqln = $aruba->aruba_ap_fqln($partial) || {};

    my %i_name;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /^\d+$/ ) {
            my $name = $i_name2->{$iid};
            next unless defined $name;
            $i_name{$index} = $name;
        }

        elsif ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $name = $ap_fqln->{$iid} || $ap_name->{$iid};
            next unless defined $name;
            $i_name{$index} = $name;
        }
        else {
            next;
        }
    }
    return \%i_name;
}

sub i_ssidlist {
    my $aruba   = shift;
    my $partial = shift;

    my $i_index = $aruba->i_index($partial)        || {};
    my $ap_ssid = $aruba->aruba_ap_essid($partial) || {};

    my %i_ssid;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $ssid = $ap_ssid->{$iid};
            next unless defined $ssid;
            $i_ssid{$index} = $ssid;
        }
        else {
            next;
        }
    }
    return \%i_ssid;
}

sub i_80211channel {
    my $aruba   = shift;
    my $partial = shift;

    my $i_index = $aruba->i_index($partial)          || {};
    my $ap_ch   = $aruba->aruba_ap_channel($partial) || {};

    my %i_ch;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $ch = $ap_ch->{$iid};
            next unless defined $ch;
            $i_ch{$index} = $ch;
        }
        else {
            next;
        }
    }
    return \%i_ch;
}

sub i_ssidbcast {
    my $aruba   = shift;
    my $partial = shift;

    my $i_index = $aruba->i_index($partial)            || {};
    my $ap_bc   = $aruba->aruba_ap_ssidbcast($partial) || {};

    my %i_bc;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        if ( $index =~ /(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ ) {
            my $bc = $ap_bc->{$iid};
            next unless defined $bc;
            $bc = ( $bc ? 0 : 1 );
            $i_bc{$index} = $bc;
        }
        else {
            next;
        }
    }
    return \%i_bc;
}

# Wireless switches do not support the standard Bridge MIB
sub bp_index {
    my $aruba   = shift;
    my $partial = shift;

    my $i_index  = $aruba->orig_i_index($partial)  || {};
    my $ap_index = $aruba->aruba_ap_name($partial) || {};

    my %bp_index;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;

        $bp_index{$iid} = $index;
    }

    # Get Attached APs as Interfaces
    foreach my $ap_id ( keys %$ap_index ) {

        # Convert the 0.254.123.456 index entry to a MAC address.
        my $mac = join( ':',
            map { sprintf( "%02x", $_ ) } split( /\./, $ap_id ) );

        $bp_index{$mac} = $mac;
    }
    return \%bp_index;
}

sub fw_port {
    my $aruba   = shift;
    my $partial = shift;

    my $fw_idx = $aruba->fw_user($partial) || {};

    my %fw_port;
    foreach my $iid ( keys %$fw_idx ) {
        if ( $iid
            =~ /(\d+\.\d+\.\d+\.\d+\.\d+\.\d+).(\d+\.\d+\.\d+\.\d+\.\d+\.\d+)/
            )
        {
            my $port = join( ':',
                map { sprintf( "%02x", $_ ) } split( /\./, $2 ) );
            $fw_port{$iid} = $port;
        }
        else {
            next;
        }
    }
    return \%fw_port;
}

sub fw_mac {
    my $aruba   = shift;
    my $partial = shift;

    my $fw_idx = $aruba->fw_user($partial) || {};

    my %fw_mac;
    foreach my $iid ( keys %$fw_idx ) {
        if ( $iid
            =~ /(\d+\.\d+\.\d+\.\d+\.\d+\.\d+).(\d+\.\d+\.\d+\.\d+\.\d+\.\d+)/
            )
        {
            my $mac = join( ':',
                map { sprintf( "%02x", $_ ) } split( /\./, $1 ) );
            $fw_mac{$iid} = $mac;
        }
        else {
            next;
        }
    }
    return \%fw_mac;
}

# Return the BSSID in i_mac.
sub i_mac {
    my $aruba = shift;
    my $partial = shift;

    # Start with the i_mac entries for the physical ports.
    my $i_mac = $aruba->orig_i_mac($partial) || {};

    # Add in all the BSSID entries.
    my $i_index  = $aruba->i_index($partial) || {};
    foreach my $iid (keys %$i_index) {
        my $index = $i_index->{$iid};
	if ($index =~ /:/) {
	    $i_mac->{$index} = $index;
	}
    }

    return $i_mac;
}

1;

__END__

=head1 NAME

SNMP::Info::Layer2::Aruba - SNMP Interface to Aruba wireless switches

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    my $aruba = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $aruba->class();
    print " Using device sub class : $class\n";

=head1 DESCRIPTION

SNMP::Info::Layer2::Aruba is a subclass of SNMP::Info that provides an
interface to Aruba wireless switches.  The Aruba platform utilizes
intelligent wireless switches which control thin access points.  The thin
access points themselves are unable to be polled for end station information.

This class emulates bridge functionality for the wireless switch. This enables
end station MAC addresses collection and correlation to the thin access point
the end station is using for communication.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $aruba = new SNMP::Info::Layer2::Aruba(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item F<WLSX-SWITCH-MIB>

=item F<WLSR-AP-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::Layer2/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $aruba->model()

Returns model type.  Cross references $aruba->id() with product IDs in the 
Aruba MIB.

=item $aruba->vendor()

Returns 'aruba'

=item $aruba->os()

Returns 'airos'

=item $aruba->os_ver()

Returns the software version extracted from C<sysDescr>

=back

=head2 Overrides

=over

=item $aruba->layers()

Returns 00000011.  Class emulates Layer 2 functionality for Thin APs through
proprietary MIBs.

=back

=head2 Globals imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $aruba->i_index()

Returns reference to map of IIDs to Interface index. 

Extends C<ifIndex> to support thin APs as device interfaces.

=item $aruba->interfaces()

Returns reference to map of IIDs to ports.  Thin APs are implemented as device 
interfaces.  The thin AP BSSID is used as the port identifier.

=item $aruba->i_name()

Interface name.  Returns (C<ifName>) for Ethernet interfaces and
(C<wlanAPFQLN> or C<apLocation>) for thin AP interfaces.

=item $aruba->i_mac()

Interface MAC address.  Returns interface MAC address for Ethernet
interfaces and BSSID for thin AP interfaces.

=item $aruba->bp_index()

Simulates bridge MIB by returning reference to a hash containing the index for
both the keys and values.

=item $aruba->fw_port()

(C<staAccessPointBSSID>) as extracted from the IID.

=item $aruba->fw_mac()

(C<staPhyAddress>) as extracted from the IID.

=item $aruba->i_ssidlist()

Returns reference to hash.  SSID's recognized by the radio interface.

(C<apESSID>)

=item $aruba->i_ssidbcast()

Returns reference to hash.  Indicates whether the SSID is broadcast, true or
false.

(C<wlsrHideSSID>)

=item $aruba->i_80211channel()

Returns reference to hash.  Current operating frequency channel of the radio
interface.

(C<apCurrentChannel>)

=item $aruba->aruba_ap_fqln()

Returns F<aruba_perap_fqln> indexed by BSSID instead of by AP.

=back

=head2 Aruba Switch AP Table  (C<wlsxSwitchAccessPointTable>)

=over

=item $aruba->aruba_ap_name()

(C<apLocation>)

=item $aruba->aruba_ap_ip()

(C<apIpAddress>)

=item $aruba->aruba_ap_essid()

(C<apESSID>)

=item $aruba->aruba_ap_ssidbcast()

(C<wlsrHideSSID>)

=back

=head2 Aruba AP Table (C<wlsxWlanAPTable>)

=over

=item $aruba->aruba_perap_fqln()

(C<wlanAPFQLN>)

=back

=head2 Aruba Switch Station Management Table (C<wlsxSwitchStationMgmtTable>)

=over

=item $aruba->fw_user()

(C<staUserName>)

=back

=head2 Aruba Wireless AP Configuration Table (C<wlsrConfigTable>)

=over

=item $aruba->aruba_ap_channel()

(C<apCurrentChannel>)

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
