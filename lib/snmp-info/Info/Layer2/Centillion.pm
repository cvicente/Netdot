# SNMP::Info::Layer2::Centillion
# Eric Miller
# $Id: Centillion.pm,v 1.11 2007/11/26 04:24:51 jeneric Exp $
#
# Copyright (c) 2004 Eric Miller
#
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the 
#       names of its contributors may be used to endorse or promote products 
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Layer2::Centillion;
$VERSION = '1.07';

use strict;

use Exporter;
use SNMP::Info;
use SNMP::Info::Bridge;
use SNMP::Info::NortelStack;
use SNMP::Info::SONMP;

@SNMP::Info::Layer2::Centillion::ISA = qw/SNMP::Info SNMP::Info::Bridge SNMP::Info::NortelStack SNMP::Info::SONMP Exporter/;
@SNMP::Info::Layer2::Centillion::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE $AUTOLOAD $INIT $DEBUG/;

%MIBS    = (
            %SNMP::Info::MIBS,
            %SNMP::Info::Bridge::MIBS,
            %SNMP::Info::NortelStack::MIBS,
            %SNMP::Info::SONMP::MIBS,
            'CENTILLION-DOT3-EXTENSIONS-MIB' => 'cnDot3ExtnTable',
            'S5-COMMON-STATS-MIB'            => 's5CmStat',
            'CENTILLION-VLAN-MIB'            => 'cnVlanENETMgt',
            'CENTILLION-CONFIG-MIB'          => 'sysTFTPStart',
            );

%GLOBALS = (
            %SNMP::Info::GLOBALS,
            %SNMP::Info::Bridge::GLOBALS,
            %SNMP::Info::NortelStack::GLOBALS,
            %SNMP::Info::SONMP::GLOBALS,
            'tftp_action'  => 'sysTFTPStart',
            'tftp_host'    => 'sysTFTPIpAddress',
            'tftp_file'    => 'sysTFTPFileName',
            'tftp_type'    => 'sysTFTPFileType',
            'tftp_result'  => 'sysTFTPResult',
            );

%FUNCS   = (
            %SNMP::Info::FUNCS,
            %SNMP::Info::Bridge::FUNCS,
            %SNMP::Info::NortelStack::FUNCS,
            %SNMP::Info::SONMP::FUNCS,
        # CENTILLION-DOT3-EXTENSIONS-MIB::cnDot3ExtnTable
            'centillion_p_index'        => 'cnDot3ExtnIfIndex',
            'centillion_p_duplex'       => 'cnDot3ExtnIfOperConnectionType',
            'centillion_p_duplex_admin' => 'cnDot3ExtnIfAdminConnectionType',
        # S5-COMMON-STATS-MIB::s5CmSNodeTable
            'fw_mac'     => 's5CmSNodeMacAddr',
            'fw_port'    => 's5CmSNodeIfIndx',
        # CENTILLION-VLAN-MIB::cnVlanPortMemberTable
            'centillion_i_vlan_index'    => 'cnVlanPortMemberIfIndex',
            'centillion_i_vlan'        => 'cnVlanPortMemberVID',
            'centillion_i_vlan_type'    => 'cnVlanPortMemberIngressType',        
            );

%MUNGE   = (
            # Inherit all the built in munging
            %SNMP::Info::MUNGE,
            %SNMP::Info::Bridge::MUNGE,
            %SNMP::Info::NortelStack::MUNGE,
            %SNMP::Info::SONMP::MUNGE,
            );

sub os {
    return 'centillion';
}

sub vendor {
    return 'nortel';
}

sub i_ignore {
    my $centillion = shift;
    my $descr = $centillion->i_description();

    my %i_ignore;
    foreach my $if (keys %$descr){
        my $type = $descr->{$if};
      # Skip virtual interfaces  
        $i_ignore{$if}++ if $type =~ /(VE|VID|vc|lp)/i;
    }
    return \%i_ignore;
}

sub interfaces {
    my $centillion = shift;
    my $i_index = $centillion->i_index();
    my $i_descr = $centillion->i_description();

    my %if;
    foreach my $iid (keys %$i_index){
        my $index = $i_index->{$iid};
        next unless defined $index;
      my $descr = $i_descr->{$iid};
      # Skip ATM and virtual interfaces
      next if $descr =~ /(VE|VID|vc|lp)/i;

      # Index numbers are deterministic slot * 256 + port
    my $port = $index % 256;
        my $slot = int($index / 256);
        my $slotport = "$slot.$port";

    $slotport = "$descr" if $descr =~ /(mcp)/i;
    
        $if{$index} = $slotport;
    }

    return \%if;
}

sub i_duplex {
    my $centillion = shift;
    
    my $port_index  = $centillion->centillion_p_index();
    my $port_duplex = $centillion->centillion_p_duplex();

    my %i_duplex;
    foreach my $iid (keys %$port_index){
        my $index = $port_index->{$iid};
        next unless defined $index;
        my $duplex = $port_duplex->{$iid};
        next unless defined $duplex; 
    
        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;
        $i_duplex{$index}=$duplex; 
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $centillion = shift;
    
    my $port_index = $centillion->centillion_p_index();
    my $port_admin = $centillion->centillion_p_duplex_admin();

    my %i_duplex_admin;
    foreach my $iid (keys %$port_index){
        my $index = $port_index->{$iid};
        next unless defined $index;
        my $duplex = $port_admin->{$iid};
        next unless defined $duplex; 
    
        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;
        $duplex = 'auto' if $duplex =~ /auto/i;
        $i_duplex_admin{$index}=$duplex; 
    }
    return \%i_duplex_admin;
}

sub i_vlan {
    my $centillion = shift;
    
    my $cn_vlan_index = $centillion->centillion_i_vlan_index();
    my $cn_vlan = $centillion->centillion_i_vlan();

    my %i_vlan;
    foreach my $iid (keys %$cn_vlan_index){
        my $index = $cn_vlan_index->{$iid};
        next unless defined $index;
        my $vlan = $cn_vlan->{$iid};
        next unless defined $vlan; 
    
        $i_vlan{$index}=$vlan; 
    }
    return \%i_vlan;
}

sub model {
    my $centillion = shift;
    my $id = $centillion->id();
    return undef unless defined $id;
    my $model = &SNMP::translateObj($id);
    return $id unless defined $model;
    $model =~ s/^sreg-//i;

    return '5000BH' if ($model =~ /5000BH/);
    return '5005BH' if ($model =~ /5005BH/);
    return 'C100' if ($model =~ /Centillion100/);
    return 'C50N' if ($model =~ /Centillion50N/);
    return 'C50T' if ($model =~ /Centillion50T/);
    return $model;
}

sub bp_index {
    my $centillion = shift;
    my $index = $centillion->fw_port();

    my %bp_index;
    foreach my $iid (keys %$index){
        my $b_index = $index->{$iid};
        next unless defined $b_index;

    #Index value is the same as ifIndex    
        $bp_index{$b_index} = $b_index;
    }

    return \%bp_index;
}

sub index_factor {
    return 256;
}

sub slot_offset {
    return 0;
}


1;
__END__

=head1 NAME

SNMP::Info::Layer2::Centillion - SNMP Interface to Nortel Centillion based ATM Switches

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $centillion = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $centillion->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Centillion device through SNMP. 

For speed or debugging purposes you can call the subclass directly, but not after determining
a more specific class using the method above. 

 my $centillion = new SNMP::Info::Layer2::centillion(...);
 
Note:  This class supports version 4.X and 5.X which are VLAN based rather
than bridge group based.

=head2 Inherited Classes

=over

=item SNMP::Info

=item SNMP::Info::Bridge

=item SNMP::Info::NortelStack

=item SNMP::Info::SONMP

=back

=head2 Required MIBs

=over

=item CENTILLION-DOT3-EXTENSIONS-MIB

=item S5-COMMON-STATS-MIB

=item CENTILLION-VLAN-MIB

=item CENTILLION-CONFIG-MIB

=item Inherited Classes' MIBs

See L<SNMP::Info/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::Bridge/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::NortelStack/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::SONMP/"Required MIBs"> for its own MIB requirements.

=back

MIBs can be found on the CD that came with your product.

Or, they can be downloaded directly from Nortel Networks regardless of support
contract status.

Go to http://www.nortelnetworks.com Techninal Support, Browse Technical Support,
Select by Product Families, Centillion, Centillion C100-C50 ATM Speed Modules,
Software.  Filter on mibs and download the latest version's archive.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $centillion->vendor()

Returns 'Nortel'

=item $centillion->model()

Cross references $centillion->id() to the SYNOPTICS-MIB and returns
the results.

Removes sreg- from the model name

=item $centillion->os()

Returns 'Centillion'

=item $centillion->tftp_action()

(B<sysTFTPStart>)

=item $centillion->tftp_host()

(B<sysTFTPIpAddress>)

=item $centillion->tftp_file()

(B<sysTFTPFileName>)

=item $centillion->tftp_type()

(B<sysTFTPFileType>)

=item $centillion->tftp_result()

(B<sysTFTPResult>)

=back

=head2 Overrides

=over

=item $centillion->layers()

Returns 00000011.  Class emulates Layer 2 functionality through proprietary MIBs.

=item  $centillion->index_factor()

Required by SNMP::Info::SONMP.  Number representing the number of ports
reserved per slot within the device MIB.  Returns 256.

=item $centillion->slot_offset()

Required by SNMP::Info::SONMP.  Offset if slot numbering does not
start at 0.  Returns 0.

=back

=head2 Globals imported from SNMP::Info

See documentation in L<SNMP::Info/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::NortelStack

See documentation in L<SNMP::Info::NortelStack/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::SONMP

See documentation in L<SNMP::Info::SONMP/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $centillion->interfaces()

    Returns reference to the map between IID and physical Port.

    Slot and port numbers on the Passport switches are determined by the formula:
      port = index % 256
      slot = int(index / 256)
 
    The physical port name is returned as slot.port.

=item $centillion->i_duplex()

Returns reference to map of IIDs to current link duplex

=item $centillion->i_duplex_admin()

Returns reference to hash of IIDs to admin duplex setting

=item $centillion->i_ignore()

Returns reference to hash of IIDs to ignore.

=item $centillion->fw_mac()

(B<s5CmSNodeMacAddr>)

=item $centillion->fw_port()

(B<s5CmSNodeIfIndx>)

=item $centillion->bp_index()

Returns a mapping between ifIndex and the Bridge Table.

=item $centillion->i_vlan()

Returns a mapping between ifIndex and the VLAN.

=back

=head2 Centillion 802.3 Extension Table (B<cnDot3ExtnTable>)

=over

=item $centillion->centillion_p_index()

Returns reference to hash.  Maps table IIDs to Interface IIDs 

(B<cnDot3ExtnIfIndex>)

=item $centillion->centillion_p_duplex()

Returns reference to hash.  Maps port operational duplexes to IIDs 

(B<cnDot3ExtnIfOperConnectionType>)

=item $centillion->rc_centillion_p_duplex_admin()

Returns reference to hash.  Maps port admin duplexes to IIDs

(B<cnDot3ExtnIfAdminConnectionType>)

=back

=head2 Centillion VLAN Table (B<cnVlanPortMemberTable>)

=over

=item $centillion->centillion_i_vlan_index()

Returns reference to hash.  Key: Table entry, Value: Index 

(B<cnVlanPortMemberIfIndex>)

=item $centillion->centillion_i_vlan()

Returns reference to hash.  Key: Table entry, Value: VLAN ID 

(B<cnVlanPortMemberVID>)

=item $centillion->centillion_i_vlan_type()

Returns reference to hash.  Key: Table entry, Value: VLAN Type 

(B<cnVlanPortMemberIngressType>)

=back

=head2 Table Methods imported from SNMP::Info

See documentation in L<SNMP::Info/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::NortelStack

See documentation in L<SNMP::Info::NortelStack/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::SONMP

See documentation in L<SNMP::Info::SONMP/"TABLE METHODS"> for details.

=cut
