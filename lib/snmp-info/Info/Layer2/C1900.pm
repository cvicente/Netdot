# SNMP::Info::Layer2::C1900
# $Id: C1900.pm,v 1.31 2008/08/02 03:21:57 jeneric Exp $
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

package SNMP::Info::Layer2::C1900;

use strict;
use Exporter;
use SNMP::Info::CDP;
use SNMP::Info::CiscoStats;
use SNMP::Info::CiscoConfig;
use SNMP::Info::Layer2;

@SNMP::Info::Layer2::C1900::ISA = qw/SNMP::Info::CDP SNMP::Info::CiscoStats
    SNMP::Info::CiscoConfig SNMP::Info::Layer2
    Exporter/;
@SNMP::Info::Layer2::C1900::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,
    %SNMP::Info::CiscoConfig::GLOBALS,
    %SNMP::Info::CiscoStats::GLOBALS,
    %SNMP::Info::CDP::GLOBALS,
    'c1900_flash_status' => 'upgradeFlashBankStatus',
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,
    %SNMP::Info::CiscoConfig::FUNCS,
    %SNMP::Info::CiscoStats::FUNCS,
    %SNMP::Info::CDP::FUNCS,

    # ESSWITCH-MIB
    'c1900_p_index'        => 'swPortIndex',
    'c1900_p_ifindex'      => 'swPortIfIndex',
    'c1900_p_duplex'       => 'swPortDuplexStatus',
    'c1900_p_duplex_admin' => 'swPortFullDuplex',
    'c1900_p_name'         => 'swPortName',
    'c1900_p_up_admin'     => 'swPortAdminStatus',
    'c1900_p_type'         => 'swPortMediaCapability',
    'c1900_p_media'        => 'swPortConnectorType',
);

%MIBS = (
    %SNMP::Info::Layer2::MIBS,
    %SNMP::Info::CiscoConfig::MIBS,
    %SNMP::Info::CiscoStats::MIBS,
    %SNMP::Info::CDP::MIBS,

    # Also known as the ESSWITCH-MIB
    'STAND-ALONE-ETHERNET-SWITCH-MIB' => 'series2000'
);

%MUNGE = (
    %SNMP::Info::Layer2::MUNGE,     %SNMP::Info::CiscoConfig::MUNGE,
    %SNMP::Info::CiscoStats::MUNGE, %SNMP::Info::CDP::MUNGE,
);

sub bulkwalk_no         { return 1; }
sub cisco_comm_indexing { return 1; }

sub vendor {
    return 'cisco';
}

sub os {
    return 'catalyst';
}

sub os_ver {
    my $c1900 = shift;

    # Check for superclass one
    my $os_ver = $c1900->SUPER::os_ver();
    return $os_ver if defined $os_ver;

    my $c1900_flash_status = $c1900->c1900_flash_status();
    return unless defined $c1900_flash_status;

    if ( $c1900_flash_status =~ m/V(\d+\.\d+(\.\d+)?)/ ) {
        return $1;
    }
    return;
}

sub interfaces {
    my $c1900   = shift;
    my $partial = shift;

    my $i_descr = $c1900->i_description($partial) || {};

    foreach my $iid ( keys %$i_descr ) {
        $i_descr->{$iid} =~ s/\s*$//;
    }
    return $i_descr;
}

sub i_duplex {
    my $c1900   = shift;
    my $partial = shift;

    my $c1900_p_duplex = $c1900->c1900_p_duplex($partial) || {};

    my %i_duplex;
    foreach my $if ( keys %$c1900_p_duplex ) {
        my $duplex = $c1900_p_duplex->{$if};
        next unless defined $duplex;

        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;
        $i_duplex{$if} = $duplex;
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $c1900   = shift;
    my $partial = shift;

    my $c1900_p_admin = $c1900->c1900_p_duplex_admin($partial) || {};

    my %i_duplex_admin;
    foreach my $if ( keys %$c1900_p_admin ) {
        my $duplex = $c1900_p_admin->{$if};
        next unless defined $duplex;

        $duplex = 'half' if $duplex =~ /disabled/i;
        $duplex = 'full' if $duplex =~ /flow control/i;
        $duplex = 'full' if $duplex =~ /enabled/i;
        $duplex = 'auto' if $duplex =~ /auto/i;
        $i_duplex_admin{$if} = $duplex;
    }
    return \%i_duplex_admin;
}

sub i_name {
    my $c1900   = shift;
    my $partial = shift;

    my $i_name       = $c1900->orig_i_name($partial)  || {};
    my $c1900_p_name = $c1900->c1900_p_name($partial) || {};

    foreach my $port ( keys %$c1900_p_name ) {
        my $name = $c1900_p_name->{$port};
        next unless defined $name;
        next unless $name !~ /^\s*$/;
        $i_name->{$port} = $name;
    }

    return $i_name;
}

sub set_i_duplex_admin {
    my $c1900 = shift;
    my ( $duplex, $port ) = @_;

    # map a textual duplex to an integer one the switch understands
    my %duplexes = qw/full 1 half 2 auto 3/;

    my $iid = $c1900->c1900_p_ifindex($port);

    $duplex = lc($duplex);

    return 0 unless defined $duplexes{$duplex};

    return $c1900->set_c1900_p_duplex_admin( $duplexes{$duplex}, $iid );
}

sub i_vlan {
    my $c1900   = shift;
    my $partial = shift;

    # Overlap allows more than one VLAN per port.  Unable to determine default
    my $overlap = $c1900->bridgeGroupAllowMembershipOverlap()
        || $c1900->vlanAllowMembershipOverlap()
        || 'disabled';

    if ( $overlap eq 'enabled' ) {
        return;
    }

    my $member_of = $c1900->bridgeGroupMemberPortOfBridgeGroup()
        || $c1900->vlanMemberPortOfVlan();

    my $i_pvid = {};
    foreach my $idx ( keys %$member_of ) {
        my @values = split( /\./, $idx );
        my ( $vlan, $port ) = @values;
        next unless $vlan;
        next unless $port;
        next if ( defined $partial and $port !~ /^$partial$/ );
        my $value = $member_of->{$idx};
        next if ( $value eq 'false' );

        $i_pvid->{$port} = $vlan;
    }
    return $i_pvid;
}

sub i_vlan_membership {
    my $c1900   = shift;
    my $partial = shift;

    my $member_of = $c1900->bridgeGroupMemberPortOfBridgeGroup()
        || $c1900->vlanMemberPortOfVlan();

    my $i_vlan_membership = {};
    foreach my $idx ( keys %$member_of ) {
        my @values = split( /\./, $idx );
        my ( $vlan, $port ) = @values;
        next unless $vlan;
        next unless $port;
        next if ( defined $partial and $port !~ /^$partial$/ );
        my $value = $member_of->{$idx};
        next if ( $value eq 'false' );

        push( @{ $i_vlan_membership->{$port} }, $vlan );
    }
    return $i_vlan_membership;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer2::C1900 - SNMP Interface to data from Cisco Catalyst 1900
Network Switches running CatOS

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $c1900 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $c1900->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a
Catalyst 1900 device through SNMP.  See SNMP::Info for full documentation

Note that most of these devices only talk SNMP version 1, but not all.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $c1900 = new SNMP::Info::Layer2::C1900(...);

=head2 Inherited classes

=over

=item SNMP::Info::CDP

=item SNMP::Info::CiscoStats

=item SNMP::Info::CiscoConfig

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item F<STAND-ALONE-ETHERNET-SWITCH-MIB (ESSWITCH-MIB)>

F<ESSWITCH-MIB> is included in the Version 1 MIBs from Cisco.

They can be found at ftp://ftp.cisco.com/pub/mibs/v1/v1.tar.gz

=back

=head2 Inherited MIBs

See L<SNMP::Info::CDP/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::CiscoStats/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::CiscoConfig/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::Layer2/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $c1900->c1900_flash_status()

Usually contains the version of the software loaded in flash.
Used by os_ver()

C<STAND-ALONE-ETHERNET-SWITCH-MIB::upgradeFlashBankStatus>

=item $c1900->os()

Returns 'catalyst'

=item $c1900->os_ver()

Returns CatOS version if obtainable.  First tries to use 
SNMP::Info::CiscoStats->os_ver() .  If that fails then it 
checks for the presence of $c1900->c1900_flash_status() and culls
the version from there.

=item $c1900->vendor()

Returns 'cisco' :)

=back

=head2 Overrides

=over

=item $c1900->cisco_comm_indexing()

Returns 1.  Use vlan indexing.

=item $c1900->bulkwalk_no

Return C<1>.  Bulkwalk is turned off for this class.

=back

=head2 Globals imported from SNMP::Info::CDP

See L<SNMP::Info::CDP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoStats

See L<SNMP::Info::CiscoStats/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoConfig

See L<SNMP::Info::CiscoConfig/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $c1900->interfaces()

Returns reference to the map between IID and physical Port.

=item $c1900->i_duplex()

Returns reference to map of IIDs to current link duplex

=item $c1900->i_duplex_admin()

Returns reference to hash of IIDs to admin duplex setting

=item $c1900->i_name()

Crosses C<ifName> with $c1900->c1900_p_name() and returns the human set port
name if exists.

=item $c1900->i_vlan()

Returns a mapping between the interface and the VLAN / bridge group if overlap
is not enabled.

=item $c1900->i_vlan_membership()

Returns reference to hash of arrays: key = interface, value = array of VLAN /
bridge group IDs.

  Example:
  my $interfaces = $c1900->interfaces();
  my $vlans      = $c1900->i_vlan_membership();
  
  foreach my $iid (sort keys %$interfaces) {
    my $port = $interfaces->{$iid};
    my $vlan = join(',', sort(@{$vlans->{$iid}}));
    print "Port: $port VLAN: $vlan\n";
  }

=back

=head2 F<STAND-ALONE-ETHERNET-SWITCH-MIB> Switch Port Table Entries:

=over

=item $c1900->c1900_p_index()

Maps the Switch Port Table to the IID

C<swPortIfIndex>

=item $c1900->c1900_p_duplex()

Gives Port Duplex Info

(C<swPortDuplexStatus>)

=item $c1900->c1900_p_duplex_admin()

Gives admin setting for Duplex Info

(C<swPortFullDuplex>)

=item $c1900->c1900_p_name()

Gives human set name for port 

(C<swPortName>)

=item $c1900->c1900_p_up_admin()

Gives Admin status of port enabled.

(C<swPortAdminStatus>)

=item $c1900->c1900_p_type()

Gives Type of port, i.e. C<"general-ethernet">

(C<swPortMediaCapability>)

=item $c1900->c1900_p_media()

Gives the media of the port , i.e. "C<fiber-sc>"

(C<swPortConnectorType>)

=back

=head2 Table Methods imported from SNMP::Info::CDP

See L<SNMP::Info::CDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoStats

See L<SNMP::Info::CiscoStats/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoConfig

See L<SNMP::Info::CiscoConfig/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=head1 SET METHODS

These are methods that provide SNMP set functionality for overridden methods
or provide a simpler interface to complex set operations.  See
L<SNMP::Info/"SETTING DATA VIA SNMP"> for general information on set
operations. 

=over

=item $c1900->set_i_duplex_admin(duplex, ifIndex)

Sets port duplex, must be supplied with duplex and port C<ifIndex>.  Speed
choices are 'auto', 'half', 'full'.

  Example:
  my %if_map = reverse %{$c1900->interfaces()};
  $c1900->set_i_duplex_admin('auto', $if_map{'1'}) 
    or die "Couldn't change port duplex. ",$c1900->error(1);

=back

=cut
