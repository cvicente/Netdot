# SNMP::Info::Layer2::NAP222x
# $Id: NAP222x.pm,v 1.15 2008/08/02 03:21:57 jeneric Exp $
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

package SNMP::Info::Layer2::NAP222x;

use strict;
use Exporter;
use SNMP::Info::SONMP;
use SNMP::Info::IEEE802dot11;
use SNMP::Info::Layer2;

@SNMP::Info::Layer2::NAP222x::ISA
    = qw/SNMP::Info::SONMP SNMP::Info::IEEE802dot11 SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::NAP222x::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer2::MIBS, %SNMP::Info::IEEE802dot11::MIBS,
    %SNMP::Info::SONMP::MIBS, 'NORTEL-WLAN-AP-MIB' => 'ntWlanSwHardwareVer',
);

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,
    %SNMP::Info::IEEE802dot11::GLOBALS,
    %SNMP::Info::SONMP::GLOBALS,
    'nt_hw_ver'     => 'ntWlanSwHardwareVer',
    'nt_fw_ver'     => 'ntWlanSwBootRomVer',
    'nt_sw_ver'     => 'ntWlanSwOpCodeVer',
    'nt_cc'         => 'ntWlanSwCountryCode',
    'tftp_action'   => 'ntWlanTransferStart',
    'tftp_host'     => 'ntWlanFileServer',
    'tftp_file'     => 'ntWlanDestFile',
    'tftp_type'     => 'ntWlanFileType',
    'tftp_result'   => 'ntWlanFileTransferStatus',
    'tftp_xtype'    => 'ntWlanTransferType',
    'tftp_src_file' => 'ntWlanSrcFile',
    'ftp_user'      => 'ntWlanUserName',
    'ftp_pass'      => 'ntWlanPassword',
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,
    %SNMP::Info::IEEE802dot11::FUNCS,
    %SNMP::Info::SONMP::FUNCS,

    # From ntWlanPortTable
    'nt_prt_name'  => 'ntWlanPortName',
    'nt_dpx_admin' => 'ntWlanPortCapabilities',
    'nt_auto'      => 'ntWlanPortAutonegotiation',
    'nt_dpx'       => 'ntWlanPortSpeedDpxStatus',

    # From ntWlanDot11PhyOperationTable
    'nt_i_broadcast' => 'ntWlanDot11ClosedSystem',

    # From ntWlanApVlanTable
    'nt_i_vlan' => 'ntWlanApVlanDefaultVid',
);

%MUNGE = (
    %SNMP::Info::Layer2::MUNGE, %SNMP::Info::IEEE802dot11::MUNGE,
    %SNMP::Info::SONMP::MUNGE,
);

sub os {
    return 'nortel';
}

sub os_bin {
    my $nap222x = shift;
    my $bin     = $nap222x->nt_fw_ver();
    return unless defined $bin;

    if ( $bin =~ m/(\d+\.\d+\.\d+)/ ) {
        return $1;
    }
    return;
}

sub model {
    my $nap222x = shift;
    my $descr   = $nap222x->description();
    return unless defined $descr;

    return 'AP-2220' if ( $descr =~ /2220/ );
    return 'AP-2221' if ( $descr =~ /2221/ );
    return;
}

sub mac {
    my $nap222x = shift;
    my $i_mac   = $nap222x->i_mac();

    # Return Interface MAC
    foreach my $entry ( keys %$i_mac ) {
        my $sn = $i_mac->{$entry};
        next unless $sn;
        return $sn;
    }
    return;
}

sub serial {
    my $nap222x = shift;
    my $i_mac   = $nap222x->i_mac();

    # Return Interface MAC
    foreach my $entry ( keys %$i_mac ) {
        my $sn = $i_mac->{$entry};
        next unless $sn;
        return $sn;
    }
    return;
}

sub interfaces {
    my $nap222x = shift;
    my $partial = shift;

    my $interfaces  = $nap222x->i_index($partial)       || {};
    my $description = $nap222x->i_description($partial) || {};

    my %interfaces = ();
    foreach my $iid ( keys %$interfaces ) {
        my $desc = $description->{$iid};
        next unless defined $desc;
        next if $desc =~ /lo/i;

        $interfaces{$iid} = $desc;
    }
    return \%interfaces;
}

sub i_duplex {
    my $nap222x = shift;
    my $partial = shift;

    my $mode       = $nap222x->nt_dpx($partial)      || {};
    my $port_name  = $nap222x->nt_prt_name($partial) || {};
    my $interfaces = $nap222x->interfaces($partial)  || {};

    my %i_duplex;
    foreach my $if ( keys %$interfaces ) {
        my $port = $interfaces->{$if};
        next unless $port =~ /dp/i;
        foreach my $idx ( keys %$mode ) {
            my $name = $port_name->{$idx} || 'unknown';
            next unless $name eq $port;
            my $duplex = $mode->{$idx};

            $duplex = 'other' unless defined $duplex;
            $duplex = 'half' if $duplex =~ /half/i;
            $duplex = 'full' if $duplex =~ /full/i;

            $i_duplex{$if} = $duplex;
        }
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $nap222x = shift;
    my $partial = shift;

    my $dpx_admin  = $nap222x->nt_dpx_admin($partial) || {};
    my $nt_auto    = $nap222x->nt_auto($partial)      || {};
    my $interfaces = $nap222x->interfaces($partial)   || {};
    my $port_name  = $nap222x->nt_prt_name($partial)  || {};

    my %i_duplex_admin;
    foreach my $if ( keys %$interfaces ) {
        my $port = $interfaces->{$if};
        next unless $port =~ /dp/i;
        foreach my $idx ( keys %$dpx_admin ) {
            my $name = $port_name->{$idx} || 'unknown';
            next unless $name eq $port;
            my $duplex = $dpx_admin->{$idx};
            my $auto   = $nt_auto->{$idx};

            $duplex = 'other' unless defined $duplex;
            $duplex = 'half'
                if ( $duplex =~ /half/i and $auto =~ /disabled/i );
            $duplex = 'full'
                if ( $duplex =~ /full/i and $auto =~ /disabled/i );
            $duplex = 'auto' if $auto =~ /enabled/i;

            $i_duplex_admin{$if} = $duplex;
        }
    }
    return \%i_duplex_admin;
}

sub i_name {
    my $nap222x = shift;
    my $partial = shift;

    my $interfaces = $nap222x->interfaces($partial) || {};

    my %i_name;
    foreach my $if ( keys %$interfaces ) {
        my $desc = $interfaces->{$if};
        next unless defined $desc;

        my $name = 'unknown';
        $name = 'Ethernet Interface'   if $desc =~ /dp/i;
        $name = 'Wireless Interface B' if $desc =~ /ndc/i;
        $name = 'Wireless Interface A' if $desc =~ /ar/i;

        $i_name{$if} = $name;
    }
    return \%i_name;
}

# dot1dBasePortTable does not exist and dot1dTpFdbPort does not map to ifIndex
sub bp_index {
    my $nap222x = shift;
    my $partial = shift;

    my $interfaces = $nap222x->interfaces($partial) || {};

    my %bp_index;
    foreach my $iid ( keys %$interfaces ) {
        my $desc = $interfaces->{$iid};
        next unless defined $desc;
        next unless $desc =~ /(ndc|ar)/i;

        my $port = 1;
        $port = 2 if $desc =~ /ndc/i;

        $bp_index{$port} = $iid;
    }
    return \%bp_index;
}

# Indicies don't match anywhere in these devices! Need to override to match
# IfIndex.
sub i_ssidlist {
    my $nap222x = shift;
    my $partial = shift;

    # modify partial to match index
    if ( defined $partial ) {
        $partial = $partial - 2;
    }
    my $ssids = $nap222x->orig_i_ssidlist($partial) || {};

    my %i_ssidlist;
    foreach my $iid ( keys %$ssids ) {
        my $port = $iid + 2;
        my $ssid = $ssids->{$iid};
        next unless defined $ssid;

        $i_ssidlist{$port} = $ssid;
    }
    return \%i_ssidlist;
}

sub i_ssidbcast {
    my $nap222x = shift;
    my $partial = shift;

    # modify partial to match index
    if ( defined $partial ) {
        $partial = $partial - 2;
    }
    my $bcast = $nap222x->nt_i_broadcast($partial) || {};

    my %i_ssidbcast;
    foreach my $iid ( keys %$bcast ) {
        my $port = $iid + 2;
        my $bc   = $bcast->{$iid};
        next unless defined $bc;

        $i_ssidbcast{$port} = $bc;
    }
    return \%i_ssidbcast;
}

sub i_80211channel {
    my $nap222x = shift;
    my $partial = shift;

    # modify partial to match index
    if ( defined $partial ) {
        $partial = $partial - 2;
    }
    my $phy_type = $nap222x->dot11_phy_type($partial) || {};
    my $cur_freq = $nap222x->dot11_cur_freq()         || {};
    my $cur_ch   = $nap222x->dot11_cur_ch()           || {};

    my %i_80211channel;
    foreach my $iid ( keys %$phy_type ) {
        my $port = $iid + 2;
        my $type = $phy_type->{$iid};
        next unless defined $type;
        if ( $type =~ /dsss/ ) {
            my $ch = $cur_ch->{1};
            next unless defined $ch;
            $i_80211channel{$port} = $ch;
        }
        elsif ( $type =~ /ofdm/ ) {
            my $ch = $cur_freq->{0};
            next unless defined $ch;
            $i_80211channel{$port} = $ch;
        }
        else {
            next;
        }
    }

    return \%i_80211channel;
}

sub i_vlan {
    my $nap222x = shift;
    my $partial = shift;

    # modify partial to match index
    if ( defined $partial ) {
        $partial = $partial - 2;
    }
    my $vlans = $nap222x->nt_i_vlan($partial) || {};

    my %i_vlan;
    foreach my $iid ( keys %$vlans ) {
        my $port = $iid + 2;
        my $vlan = $vlans->{$iid};
        next unless defined $vlan;

        $i_vlan{$port} = $vlan;
    }
    return \%i_vlan;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer2::NAP222x - SNMP Interface to Nortel 2220 Series Access
Points

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $nap222x = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $nap222x->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a Nortel
2220 series wireless Access Points through SNMP. 

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $nap222x = new SNMP::Info::Layer2::NAP222x(...);

=head2 Inherited Classes

=over

=item SNMP::Info::SONMP

=item SNMP::Info::IEEE802dot11

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item F<NORTEL-WLAN-AP-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::SONMP/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::IEEE802dot11/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::Layer2/"Required MIBs"> for its MIB requirements.


=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $nap222x->model()

Returns the model extracted from C<sysDescr>.

=item $nap222x->os()

Returns 'nortel'

=item $nap222x->os_bin()

Returns the firmware version extracted from C<ntWlanSwBootRomVer>.

=item $nap222x->mac()

Returns the MAC address of the first Ethernet Interface.

=item $nap222x->serial()

Returns the MAC address of the first Ethernet Interface.

=item $nap222x->nt_hw_ver()

Returns the hardware version.

(C<ntWlanSwHardwareVer>)

=item $nap222x->nt_cc()

Returns the country code of the AP.

(C<ntWlanSwHardwareVer>)

=item $nap222x->tftp_action()

(C<ntWlanTransferStart>)

=item $nap222x->tftp_host()

(C<ntWlanFileServer>)

=item $nap222x->tftp_file()

(C<ntWlanDestFile>)

=item $nap222x->tftp_type()

(C<ntWlanFileType>)

=item $nap222x->tftp_result()

(C<ntWlanFileTransferStatus>)

=item $nap222x->tftp_xtype()

(C<ntWlanTransferType>)

=item $nap222x->tftp_src_file()

(C<ntWlanSrcFile>)

=item $nap222x->ftp_user()

(C<ntWlanUserName>)

=item $nap222x->ftp_pass()

(C<ntWlanPassword>)

=back

=head2 Globals imported from SNMP::Info::SONMP

See L<SNMP::Info::SONMP/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::IEEE802dot11

See L<SNMP::Info::IEEE802dot11/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $nap222x->interfaces()

Returns reference to map of IIDs to physical ports. 

=item $nap222x->i_duplex()

Returns reference to hash.  Maps port operational duplexes to IIDs.

(C<ntWlanPortSpeedDpxStatus>)

=item $nap222x->i_duplex_admin()

Returns reference to hash.  Maps port admin duplexes to IIDs.

(C<ntWlanPortCapabilities>)

=item $nap222x->i_name()

Returns a human name based upon port description.

=item $nap222x->bp_index()

Returns a mapping between C<ifIndex> and the Bridge Table.  This does not
exist in the MIB and bridge port index is not the same as C<ifIndex> so it is
created. 

=item $nap222x->i_ssidlist()

Returns reference to hash.  SSID's recognized by the radio interface.

=item $nap222x->i_ssidbcast()

Returns reference to hash.  Indicates whether the SSID is broadcast.

=item $nap222x->i_80211channel()

Returns reference to hash.  Current operating frequency channel of the radio
interface.

=item $nap222x->i_vlan()

The default Vlan ID of the radio interfaces.

(C<ntWlanApVlanDefaultVid>)

=back

=head2 Table Methods imported from SNMP::Info::SONMP

See L<SNMP::Info::SONMP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::IEEE802dot11

See L<SNMP::Info::IEEE802dot11/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
