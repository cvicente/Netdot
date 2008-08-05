# SNMP::Info::Layer3::Enterasys - SNMP Interface to Enterasys devices
# $Id: Enterasys.pm,v 1.11 2008/08/02 03:21:47 jeneric Exp $
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

package SNMP::Info::Layer3::Enterasys;

use strict;
use Exporter;
use SNMP::Info::MAU;
use SNMP::Info::LLDP;
use SNMP::Info::CDP;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::Enterasys::ISA = qw/SNMP::Info::MAU SNMP::Info::LLDP
    SNMP::Info::CDP SNMP::Info::Layer3
    Exporter/;
@SNMP::Info::Layer3::Enterasys::EXPORT_OK = qw//;

use vars qw/$VERSION $DEBUG %GLOBALS %FUNCS $INIT %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS, %SNMP::Info::CDP::MIBS,
    %SNMP::Info::LLDP::MIBS, %SNMP::Info::MAU::MIBS,
    'ENTERASYS-OIDS-MIB' => 'etsysOidDevice',
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS, %SNMP::Info::CDP::GLOBALS,
    %SNMP::Info::LLDP::GLOBALS,   %SNMP::Info::MAU::GLOBALS,
    'mac' => 'dot1dBaseBridgeAddress',
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS, %SNMP::Info::CDP::FUNCS,
    %SNMP::Info::LLDP::FUNCS,   %SNMP::Info::MAU::FUNCS,
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE, %SNMP::Info::CDP::MUNGE,
    %SNMP::Info::LLDP::MUNGE,   %SNMP::Info::MAU::MUNGE,
);

sub model {
    my $enterasys = shift;
    my $id        = $enterasys->id();

    unless ( defined $id ) {
        print
            " SNMP::Info::Layer3::Enterasys::model() - Device does not support sysObjectID\n"
            if $enterasys->debug();
        return;
    }

    my $model = &SNMP::translateObj($id);

    $model =~ s/^etsysOidDev//i;
    $model =~ s/^etsysOidPhy//i;
    return $id unless defined $model;

    return $model;
}

sub vendor {
    return 'enterasys';
}

sub os {
    return 'enterasys';
}

sub os_ver {
    my $enterasys = shift;
    my $descr     = $enterasys->description();
    return unless defined $descr;

    if ( $descr =~ m/\bRev ([\d.]*)/ ) {
        return $1;
    }

    return;
}

# Use ifName as it is used for CDP and LLDP.
sub interfaces {
    my $enterasys = shift;
    my $partial   = shift;

    #  We need the original ifName, SUPER:: would give us a method definition
    #  in a higher class, we could use orig_ but just call the MIB leaf since
    #  that's what we really want anyway.
    return $enterasys->ifName($partial)
        || $enterasys->i_description($partial);
}

sub i_ignore {
    my $enterasys = shift;
    my $partial   = shift;

    my $interfaces = $enterasys->i_type($partial) || {};

    my %i_ignore;
    foreach my $if ( keys %$interfaces ) {
        if ( $interfaces->{$if} =~ /(rs232|tunnel|loopback|\blo\b|null)/i ) {
            $i_ignore{$if}++;
        }
    }
    return \%i_ignore;
}

sub i_duplex {
    my $enterasys = shift;
    my $partial   = shift;

    return $enterasys->mau_i_duplex($partial);
}

sub i_duplex_admin {
    my $enterasys = shift;
    my $partial   = shift;

    return $enterasys->mau_i_duplex_admin($partial);
}

# Normal BRIDGE-MIB has issues on some devices, duplicates and
# non-increasing oids, Use Q-BRIDGE-MIB for macsuck
sub fw_mac {
    my $enterasys = shift;
    my $partial   = shift;

    return $enterasys->qb_fw_mac($partial);
}

sub fw_port {
    my $enterasys = shift;
    my $partial   = shift;

    return $enterasys->qb_fw_port($partial);
}

#  Use CDP and/or LLDP
#
#  LLDP table timefilter implementation continuously increments when walked
#  and we may never reach the end of the table.  This behavior can be
#  modified with the "set snmp timefilter break disable" command,
#  unfortunately it is not the default.  Query with a partial value of zero
#  which means no time filter.

sub hasCDP {
    my $enterasys = shift;

    return $enterasys->hasLLDP() || $enterasys->SUPER::hasCDP();
}

sub c_ip {
    my $enterasys = shift;
    my $partial   = shift;

    my $cdp  = $enterasys->SUPER::c_ip($partial) || {};
    my $lldp = $enterasys->lldp_ip(0)            || {};

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
    my $enterasys = shift;
    my $partial   = shift;

    my $lldp = $enterasys->lldp_if(0)            || {};
    my $cdp  = $enterasys->SUPER::c_if($partial) || {};

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
    my $enterasys = shift;
    my $partial   = shift;

    my $lldp = $enterasys->lldp_port(0)            || {};
    my $cdp  = $enterasys->SUPER::c_port($partial) || {};

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
    my $enterasys = shift;
    my $partial   = shift;

    my $lldp = $enterasys->lldp_id(0)            || {};
    my $cdp  = $enterasys->SUPER::c_id($partial) || {};

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
    my $enterasys = shift;
    my $partial   = shift;

    my $lldp = $enterasys->lldp_rem_sysdesc(0)         || {};
    my $cdp  = $enterasys->SUPER::c_platform($partial) || {};

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

SNMP::Info::Layer3::Enterasys - SNMP Interface to Enterasys Network Devices

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $enterasys = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $enterasys->class();

 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from an 
Enterasys device through SNMP. 

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

my $enterasys = new SNMP::Info::Layer3::Enterasys(...);

=head2 Inherited Classes

=over

=item SNMP::Info::MAU

=item SNMP::Info::LLDP

=item SNMP::Info::CDP

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<ENTERASYS-OIDS-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::MAU/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::LLDP/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::CDP/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::Layer3/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $enterasys->model()

Returns model type.  Checks $enterasys->id() against the
F<ENTERASYS-OIDS-MIB>.

=item $enterasys->vendor()

Returns enterasys

=item $enterasys->os()

Returns enterasys

=item $enterasys->os_ver()

Returns os version extracted from C<sysDescr>

=item $enterasys->mac()

Returns base mac

(C<dot1dBaseBridgeAddress>)

=back

=head2 Overrides

=over

=back

=head2 Globals imported from SNMP::Info::MAU

See documentation in L<SNMP::Info::MAU/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $enterasys->interfaces()

Mapping between the Interface Table Index (iid) and the physical port name.

=item $enterasys->i_ignore()

Returns reference to hash.  Creates a key for each IID that should be ignored.

Currently looks for rs232, tunnel,loopback,lo,null from
$enterasys->interfaces()

=item $enterasys->i_duplex()

See documentation for mau_i_duplex() in L<SNMP::Info::MAU/"TABLE METHODS">.

=item $enterasys->i_duplex_admin()

See documentation for mau_i_duplex_admin() in
L<SNMP::Info::MAU/"TABLE METHODS">.

=item $enterasys->fw_mac()

Returns reference to hash of forwarding table MAC Addresses.

=item $enterasys->fw_port()

Returns reference to hash of forwarding table entries port interface
identifier (iid).

(C<dot1qTpFdbPort>)

=back

=head2 Topology information

Based upon the firmware version Enterasys devices may support Cabletron
Discovery Protocol (CTRON CDP), Cisco Discovery Protocol (CDP), Link Layer
Discovery Protocol (LLDP), or all.  This module currently supports CDP and
LLDP, but not CTRON CDP.  These methods will query both CDP and LLDP and
return the combination of all information.  As a result, there may be
identical topology information returned from the two protocols
causing duplicate entries.  It is the calling program's responsibility to
identify any duplicate entries and remove duplicates if necessary.

=over

=item $enterasys->hasCDP()

Returns true if the device is running either CDP or LLDP.

=item $enterasys->c_if()

Returns reference to hash.  Key: iid Value: local device port (interfaces)

=item $enterasys->c_ip()

Returns reference to hash.  Key: iid Value: remote IPv4 address

If multiple entries exist with the same local port, c_if(), with the same IPv4
address, c_ip(), it may be a duplicate entry.

If multiple entries exist with the same local port, c_if(), with different
IPv4 addresses, c_ip(), there is either a non-CDP/LLDP device in between two
or more devices or multiple devices which are not directly connected.  

Use the data from the Layer2 Topology Table below to dig deeper.

=item $enterasys->c_port()

Returns reference to hash. Key: iid Value: remote port (interfaces)

=item $enterasys->c_id()

Returns reference to hash. Key: iid Value: string value used to identify the
chassis component associated with the remote system.

=item $enterasys->c_platform()

Returns reference to hash.  Key: iid Value: Remote Device Type

=back

=head2 Table Methods imported from SNMP::Info::MAU

See documentation in L<SNMP::Info::MAU/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
