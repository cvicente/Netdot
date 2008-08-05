# SNMP::Info::IEEE802dot11
# $Id: IEEE802dot11.pm,v 1.9 2008/08/02 03:21:25 jeneric Exp $
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

package SNMP::Info::IEEE802dot11;

use strict;
use Exporter;

@SNMP::Info::IEEE802dot11::ISA       = qw/Exporter/;
@SNMP::Info::IEEE802dot11::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( 'IEEE802dot11-MIB' => 'dot11DesiredSSID', );

%GLOBALS = ();

%FUNCS = (

    # dot11PhyOFDMTable
    'dot11_cur_freq' => 'dot11CurrentFrequency',

    # dot11PhyDSSSTable
    'dot11_cur_ch' => 'dot11CurrentChannel',

    # dot11PhyOperationTable
    'dot11_phy_type' => 'dot11PHYType',
    'dot11_reg_dom'  => 'dot11CurrentRegDomain',

    # dot11ResourceInfoTable
    'dot11_prod_ver'  => 'dot11manufacturerProductVersion',
    'dot11_prod_name' => 'dot11manufacturerProductName',
    'dot11_man_name'  => 'dot11manufacturerName',

    # dot11OperationTable
    'dot11_mac' => 'dot11MACAddress',

    # dot11StationConfigTable
    'dot11_bss_type' => 'dot11DesiredBSSType',
    'i_ssidlist'     => 'dot11DesiredSSID',
    'dot11_pwr_mode' => 'dot11PowerManagementMode',
    'dot11_sta_id'   => 'dot11StationID',

    # dot11PhyTxPowerTable
    'dot11_cur_tx_pwr'     => 'dot11CurrentTxPowerLevel',
    'dot11_tx_pwr_level_1' => 'dot11TxPowerLevel1',
    'dot11_tx_pwr_level_2' => 'dot11TxPowerLevel2',
    'dot11_tx_pwr_level_3' => 'dot11TxPowerLevel3',
    'dot11_tx_pwr_level_4' => 'dot11TxPowerLevel4',
    'dot11_tx_pwr_level_5' => 'dot11TxPowerLevel5',
    'dot11_tx_pwr_level_6' => 'dot11TxPowerLevel6',
    'dot11_tx_pwr_level_7' => 'dot11TxPowerLevel7',
    'dot11_tx_pwr_level_8' => 'dot11TxPowerLevel8',
);

%MUNGE = (
    'dot11_mac'    => \&SNMP::Info::munge_mac,
    'dot11_sta_id' => \&SNMP::Info::munge_mac,
);

sub vendor {
    my $dot11 = shift;

    my $names = $dot11->dot11_man_name();

    foreach my $iid ( keys %$names ) {
        my $vendor = $names->{$iid};
        next unless defined $vendor;
        if ( $vendor =~ /^(\S+)/ ) {
            return lc($1);
        }
    }

    return;
}

sub model {
    my $dot11 = shift;

    my $names = $dot11->dot11_prod_name();

    foreach my $iid ( keys %$names ) {
        my $prod = $names->{$iid};
        next unless defined $prod;
        return lc($prod);
    }
    return;
}

sub os_ver {
    my $dot11 = shift;

    my $versions = $dot11->dot11_prod_ver();

    foreach my $iid ( keys %$versions ) {
        my $ver = $versions->{$iid};
        next unless defined $ver;
        if ( $ver =~ /([\d\.]+)/ ) {
            return $1;
        }
    }

    return;
}

sub i_80211channel {
    my $dot11 = shift;

    my $phy_type = $dot11->dot11_phy_type() || {};
    my $cur_freq = $dot11->dot11_cur_freq() || {};
    my $cur_ch   = $dot11->dot11_cur_ch()   || {};

    my %i_80211channel;
    foreach my $iid ( keys %$phy_type ) {
        my $type = $phy_type->{$iid};
        next unless defined $type;
        if ( $type =~ /dsss/ ) {
            my $ch = $cur_ch->{$iid};
            next unless defined $ch;
            $i_80211channel{$iid} = $ch;
        }
        elsif ( $type =~ /ofdm/ ) {
            my $ch = $cur_freq->{$iid};
            next unless defined $ch;
            $i_80211channel{$iid} = $ch;
        }
        else {
            next;
        }
    }

    return \%i_80211channel;
}

sub dot11_cur_tx_pwr_mw {
    my $dot11               = shift;
    my $partial             = shift;
    my $cur                 = $dot11->dot11_cur_tx_pwr($partial);
    my $dot11_cur_tx_pwr_mw = {};
    foreach my $idx ( keys %$cur ) {
        my $pwr = $cur->{$idx};
        if ( $pwr >= 1 && $pwr <= 8 ) {

            # ToDo - Look at string eval
            my $mw
                = eval "\$dot11->dot11_tx_pwr_level_$pwr(\$idx)"; ## no critic
            $dot11_cur_tx_pwr_mw->{$idx} = $mw->{$idx};
        }
        else {
            next;
        }
    }
    return $dot11_cur_tx_pwr_mw;
}

1;

__END__

=head1 NAME

SNMP::Info::IEEE802dot11 - SNMP Interface to data from F<IEEE802dot11-MIB>

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    my $dot11 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $dot11->class();
    print " Using device sub class : $class\n";

=head1 DESCRIPTION

SNMP::Info::IEEE802dot11 is a subclass of SNMP::Info that provides an
interface to F<IEEE802dot11-MIB>.  This MIB is used in standards based
802.11 wireless devices.

Use or create a subclass of SNMP::Info that inherits this one.
Do not use directly.

=head2 Inherited Classes

=over

None.

=back

=head2 Required MIBs

=over

=item F<IEEE802dot11-MIB>

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $dot11->vendor()

Tries to discover the vendor from dot11_man_name() - returns lower case
of the first word in the first instance found.

=item $dot11->model()

Tries to discover the model from dot11_prod_name() - returns lower case
of the first instance found.

=item $dot11->os_ver()

Tries to discover the operating system version from dot11_prod_ver() - returns
string of numeric and decimals in the first instance found.

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $dot11->i_ssidlist()

Returns reference to hash.  SSID's recognized by the radio interface.

(C<dot11DesiredSSID>)

=item $dot11->i_80211channel()

Returns reference to hash.  Current operating frequency channel of the radio
interface.

=item $dot11->dot11_cur_tx_pwr_mw()

Returns reference to hash.  Current transmit power, in milliwatts, of the
radio interface.

=back

=head2 Dot11 Phy OFDM Table  (C<dot11PhyOFDMTable>)

=over

=item $dot11->dot11_cur_freq()

(C<dot11CurrentFrequency>)

=back

=head2 Dot11 Phy DSSS Table  (C<dot11PhyDSSSTable>)

=over

=item $dot11->dot11_cur_ch()

(C<dot11CurrentChannel>)

=back

=head2 Dot11 Phy Operation Table  (C<dot11PhyOperationTable>)

=over

=item $dot11->dot11_phy_type()

(C<dot11PHYType>)

=item $dot11->dot11_reg_dom()

(C<dot11CurrentRegDomain>)

=back

=head2 Dot11 Resource Information Table  (C<dot11ResourceInfoTable>)

=over

=item $dot11->dot11_prod_ver()

(C<dot11manufacturerProductVersion>)

=item $dot11->dot11_prod_name()

(C<dot11manufacturerProductName>)

=item $dot11->dot11_man_name()

(C<dot11manufacturerName>)

=back

=head2 Dot11 Operation Table  (C<dot11OperationTable>)

=over

=item $dot11->dot11_mac()

(C<dot11MACAddress>)

=back

=head2 Dot11 Station Configuration Table  (C<dot11StationConfigTable>)

=over

=item $dot11->dot11_bss_type()

(C<dot11DesiredBSSType>)

=item $dot11->dot11_pwr_mode()

(C<dot11PowerManagementMode>)

=item $dot11->dot11_sta_id()

(C<dot11StationID>)

=back

=head2 Dot11 Transmission Power Table  (C<dot11PhyTxPowerTable>)

=over

=item $dot11->dot11_cur_tx_pwr()

(C<dot11CurrentTxPowerLevel>)

=item $dot11->dot11_tx_pwr_level_1()

(C<dot11TxPowerLevel1>)

=item $dot11->dot11_tx_pwr_level_2()

(C<dot11TxPowerLevel2>)

=item $dot11->dot11_tx_pwr_level_3()

(C<dot11TxPowerLevel3>)

=item $dot11->dot11_tx_pwr_level_4()

(C<dot11TxPowerLevel4>)

=item $dot11->dot11_tx_pwr_level_5()

(C<dot11TxPowerLevel5>)

=item $dot11->dot11_tx_pwr_level_6()

(C<dot11TxPowerLevel6>)

=item $dot11->dot11_tx_pwr_level_7()

(C<dot11TxPowerLevel7>)

=item $dot11->dot11_tx_pwr_level_8()

(C<dot11TxPowerLevel8>)

=back

=cut
