# SNMP::Info::Layer3::HP9300 - SNMP Interface to HP Foundry OEM devices
# $Id: HP9300.pm,v 1.6 2008/08/02 03:21:47 jeneric Exp $
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

package SNMP::Info::Layer3::HP9300;

use strict;
use Exporter;
use SNMP::Info::Layer3;
use SNMP::Info::FDP;
use SNMP::Info::LLDP;

@SNMP::Info::Layer3::HP9300::ISA = qw/SNMP::Info::FDP SNMP::Info::LLDP
    SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::HP9300::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %FUNCS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    %SNMP::Info::LLDP::MIBS,
    %SNMP::Info::FDP::MIBS,
    'HP-SN-ROOT-MIB'         => 'hp',
    'HP-SN-AGENT-MIB'        => 'snChasPwrSupplyDescription',
    'HP-SN-SWITCH-GROUP-MIB' => 'snSwGroupOperMode',
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    %SNMP::Info::LLDP::GLOBALS,
    %SNMP::Info::FDP::GLOBALS,
    'mac'        => 'ifPhysAddress.1',
    'chassis'    => 'entPhysicalDescr.1',
    'temp'       => 'snChasActualTemperature',
    'ps1_type'   => 'snChasPwrSupplyDescription.1',
    'ps1_status' => 'snChasPwrSupplyOperStatus.1',
    'fan'        => 'snChasFanOperStatus.1',

);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS,
    %SNMP::Info::LLDP::FUNCS,
    %SNMP::Info::FDP::FUNCS,

    # HP-SN-SWITCH-GROUP-MIB
    # snSwPortInfoTable - Switch Port Information Group
    # Fully qualify these since FDP class will load
    # FOUNDRY-SN-SWITCH-GROUP-MIB which contains the same leaf names
    'sw_index'  => 'HP_SN_SWITCH_GROUP_MIB__snSwPortIfIndex',
    'sw_duplex' => 'HP_SN_SWITCH_GROUP_MIB__snSwPortInfoChnMode',
    'sw_type'   => 'HP_SN_SWITCH_GROUP_MIB__snSwPortInfoMediaType',
    'sw_speed'  => 'HP_SN_SWITCH_GROUP_MIB__snSwPortInfoSpeed',
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE, %SNMP::Info::LLDP::MUNGE,
    %SNMP::Info::FDP::MUNGE,
);

sub i_ignore {
    my $hp9300  = shift;
    my $partial = shift;

    my $interfaces = $hp9300->interfaces($partial) || {};

    my %i_ignore;
    foreach my $if ( keys %$interfaces ) {
        if ( $interfaces->{$if} =~ /(tunnel|loopback|\blo\b|lb|null)/i ) {
            $i_ignore{$if}++;
        }
    }
    return \%i_ignore;
}

sub i_duplex {
    my $hp9300  = shift;
    my $partial = shift;

    my $sw_index  = $hp9300->sw_index($partial);
    my $sw_duplex = $hp9300->sw_duplex($partial);

    unless ( defined $sw_index and defined $sw_duplex ) {
        return $hp9300->SUPER::i_duplex();
    }

    my %i_duplex;
    foreach my $sw_port ( keys %$sw_duplex ) {
        my $iid    = $sw_index->{$sw_port};
        my $duplex = $sw_duplex->{$sw_port};
        next if $duplex =~ /none/i;
        $i_duplex{$iid} = 'half' if $duplex =~ /half/i;
        $i_duplex{$iid} = 'full' if $duplex =~ /full/i;
    }
    return \%i_duplex;
}

sub model {
    my $hp9300 = shift;
    my $id     = $hp9300->id();
    my $model  = &SNMP::translateObj($id);

    return $id unless defined $model;

    $model =~ s/^hpSwitch//;

    return $model;
}

sub os {
    return 'hp';
}

sub vendor {
    return 'hp';
}

sub os_ver {
    my $hp9300 = shift;

    return $hp9300->snAgImgVer() if ( defined $hp9300->snAgImgVer() );

    # Some older ones don't have this value,so we cull it from the description
    my $descr = $hp9300->description();
    if ( $descr =~ m/Version (\d\S*)/ ) {
        return $1;
    }

    # Last resort
    return $hp9300->SUPER::os_ver();

}

sub serial {
    my $hp9300 = shift;

    # Return chassis serial number if available
    return $hp9300->snChasSerNum() if ( $hp9300->snChasSerNum() );

    # If no chassis serial use first module serial
    my $mod_serials = $hp9300->snAgentConfigModuleSerialNumber();

    foreach my $mod ( sort keys %$mod_serials ) {
        my $serial = $mod_serials->{$mod} || '';
        next unless defined $serial;
        return $serial;
    }

    # Last resort
    return $hp9300->SUPER::serial();
}

sub interfaces {
    my $hp9300  = shift;
    my $partial = shift;

    my $i_descr = $hp9300->i_description($partial) || {};
    my $i_name  = $hp9300->i_name($partial)        || {};

    # Use ifName for EdgeIrons else use ifDescr
    foreach my $iid ( keys %$i_name ) {
        my $name = $i_name->{$iid};
        next unless defined $name;
        $i_descr->{$iid} = $name
            if $name =~ /^port\d+/i;
    }

    return $i_descr;
}

#  Use FDP and/or LLDP

sub hasCDP {
    my $hp9300 = shift;

    return $hp9300->hasLLDP() || $hp9300->SUPER::hasCDP();
}

sub c_ip {
    my $hp9300  = shift;
    my $partial = shift;

    my $cdp  = $hp9300->SUPER::c_ip($partial) || {};
    my $lldp = $hp9300->lldp_ip($partial)     || {};

    my %c_ip;
    foreach my $iid ( keys %$cdp ) {
        my $ip = $cdp->{$iid};
        next unless defined $ip;

        $c_ip{$iid} = $ip;
    }

    foreach my $iid ( keys %$lldp ) {
        my $ip = $lldp->{$iid};
        next unless defined $ip;

        $c_ip{$iid} = $ip;
    }
    return \%c_ip;
}

sub c_if {
    my $hp9300  = shift;
    my $partial = shift;

    my $lldp = $hp9300->lldp_if($partial)     || {};
    my $cdp  = $hp9300->SUPER::c_if($partial) || {};

    my %c_if;
    foreach my $iid ( keys %$cdp ) {
        my $if = $cdp->{$iid};
        next unless defined $if;

        $c_if{$iid} = $if;
    }

    foreach my $iid ( keys %$lldp ) {
        my $if = $lldp->{$iid};
        next unless defined $if;

        $c_if{$iid} = $if;
    }
    return \%c_if;
}

sub c_port {
    my $hp9300  = shift;
    my $partial = shift;

    my $lldp = $hp9300->lldp_port($partial)     || {};
    my $cdp  = $hp9300->SUPER::c_port($partial) || {};

    my %c_port;
    foreach my $iid ( keys %$cdp ) {
        my $port = $cdp->{$iid};
        next unless defined $port;

        $c_port{$iid} = $port;
    }

    foreach my $iid ( keys %$lldp ) {
        my $port = $lldp->{$iid};
        next unless defined $port;

        $c_port{$iid} = $port;
    }
    return \%c_port;
}

sub c_id {
    my $hp9300  = shift;
    my $partial = shift;

    my $lldp = $hp9300->lldp_id($partial)     || {};
    my $cdp  = $hp9300->SUPER::c_id($partial) || {};

    my %c_id;
    foreach my $iid ( keys %$cdp ) {
        my $id = $cdp->{$iid};
        next unless defined $id;

        $c_id{$iid} = $id;
    }

    foreach my $iid ( keys %$lldp ) {
        my $id = $lldp->{$iid};
        next unless defined $id;

        $c_id{$iid} = $id;
    }
    return \%c_id;
}

sub c_platform {
    my $hp9300  = shift;
    my $partial = shift;

    my $lldp = $hp9300->lldp_rem_sysdesc($partial)  || {};
    my $cdp  = $hp9300->SUPER::c_platform($partial) || {};

    my %c_platform;
    foreach my $iid ( keys %$cdp ) {
        my $platform = $cdp->{$iid};
        next unless defined $platform;

        $c_platform{$iid} = $platform;
    }

    foreach my $iid ( keys %$lldp ) {
        my $platform = $lldp->{$iid};
        next unless defined $platform;

        $c_platform{$iid} = $platform;
    }
    return \%c_platform;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::HP9300 - SNMP Interface to HP Foundry OEM Network Devices

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $hp9300 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $hp9300->class();

 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Abstraction subclass for HP network devices which Foundry Networks was the
Original Equipment Manufacturer (OEM) such as the HP ProCurve 9300 series.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above.

 my $hp9300 = new SNMP::Info::Layer3::HP9300(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3;

=item SNMP::Info::FDP;

=item SNMP::Info::LLDP;

=back

=head2 Required MIBs

=over

=item F<HP-SN-ROOT-MIB>

=item F<HP-SN-AGENT-MIB>

=item F<HP-SN-SWITCH-GROUP-MIB>

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::FDP/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::LLDP/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $hp9300->model()

Returns model type.  Checks $hp9300->id() against the F<HP-SN-ROOT-MIB>
and removes C<hpSwitch>.

=item $hp9300->vendor()

Returns 'hp'

=item $hp9300->os()

Returns 'hp'

=item $hp9300->os_ver()

Returns the software version

=item $hp9300->mac()

Returns MAC Address of root port.

(C<ifPhysAddress.1>)

=item $hp9300->chassis()

Returns Chassis type.

(C<entPhysicalDescr.1>)

=item $hp9300->serial()

Returns serial number of device.

=item $hp9300->temp()

Returns the chassis temperature

(C<snChasActualTemperature>)

=item $hp9300->ps1_type()

Returns the Description for the power supply

(C<snChasPwrSupplyDescription.1>)

=item $hp9300->ps1_status()

Returns the status of the power supply.

(C<snChasPwrSupplyOperStatus.1>)

=item $hp9300->fan()

Returns the status of the chassis fan.

(C<snChasFanOperStatus.1>)

=back

=head2 Global Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::FDP

See documentation in L<SNMP::Info::FDP/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $hp9300->interfaces()

Returns reference to hash of interface names to iids.

=item $hp9300->i_ignore()

Returns reference to hash of interfaces to be ignored.

Ignores interfaces with descriptions of  tunnel,loopback,null 

=item $hp9300->i_duplex()

Returns reference to hash of interface link duplex status. 

Crosses $hp9300->sw_duplex() with $hp9300->sw_index()

=back

=head2 Switch Port Information Table (C<snSwPortIfTable>)

=over

=item $hp9300->sw_index()

Returns reference to hash.  Maps Table to Interface IID. 

(C<snSwPortIfIndex>)

=item $hp9300->sw_duplex()

Returns reference to hash.   Current duplex status for switch ports. 

(C<snSwPortInfoChnMode>)

=item $hp9300->sw_type()

Returns reference to hash.  Current Port Type .

(C<snSwPortInfoMediaType>)

=item $hp9300->sw_speed()

Returns reference to hash.  Current Port Speed. 

(C<snSwPortInfoSpeed>)

=back

=head2 Topology information

Based upon the software version devices may support Foundry Discovery
Protocol (FDP) and Link Layer Discovery Protocol (LLDP). These
methods will query both and return the combination of all information. As a
result, there may be identical topology information returned from the two
protocols causing duplicate entries.  It is the calling program's
responsibility to identify any duplicate entries and remove duplicates
if necessary.

=over

=item $hp9300->hasCDP()

Returns true if the device is running either FDP or LLDP.

=item $hp9300->c_if()

Returns reference to hash.  Key: iid Value: local device port (interfaces)

=item $hp9300->c_ip()

Returns reference to hash.  Key: iid Value: remote IPv4 address

If multiple entries exist with the same local port, c_if(), with the same IPv4
address, c_ip(), it may be a duplicate entry.

If multiple entries exist with the same local port, c_if(), with different
IPv4 addresses, c_ip(), there is either a non-FDP/LLDP device in between two
or more devices or multiple devices which are not directly connected.  

Use the data from the Layer2 Topology Table below to dig deeper.

=item $hp9300->c_port()

Returns reference to hash. Key: iid Value: remote port (interfaces)

=item $hp9300->c_id()

Returns reference to hash. Key: iid Value: string value used to identify the
chassis component associated with the remote system.

=item $hp9300->c_platform()

Returns reference to hash.  Key: iid Value: Remote Device Type

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::FDP

See documentation in L<SNMP::Info::FDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"TABLE METHODS"> for details.

=cut
