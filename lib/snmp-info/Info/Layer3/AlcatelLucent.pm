# SNMP::Info::Layer3::AlcatelLucent
# $Id: AlcatelLucent.pm,v 1.3 2008/08/02 03:21:47 jeneric Exp $
#
# Copyright (c) 2008 Bill Fenner
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

package SNMP::Info::Layer3::AlcatelLucent;

use strict;

use Exporter;
use SNMP::Info::Layer3;
use SNMP::Info::MAU;
use SNMP::Info::LLDP;

@SNMP::Info::Layer3::AlcatelLucent::ISA = qw/SNMP::Info::LLDP SNMP::Info::MAU
    SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::AlcatelLucent::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    %SNMP::Info::MAU::MIBS,
    %SNMP::Info::LLDP::MIBS,
    'ALCATEL-IND1-DEVICES'     => 'familyOmniSwitch7000',
    'ALCATEL-IND1-CHASSIS-MIB' => 'chasEntPhysOperStatus',
    'ALU-POWER-ETHERNET-MIB'   => 'pethPsePortDetectionStatus',
);

# Alcatel provides their own version of the POWER-ETHERNET-MIB,
# off in vendor-space, without renaming any of the objects.
# This means we have to *not* load the POWER-ETHERNET-MIB
# but can then still use the standard PowerEthernet module,
# but cannot try both so we hope Alcatel doesn't stop supporting
# their private version even if they get around to supporting the
# standard.
delete $MIBS{'POWER-ETHERNET-MIB'};

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS, %SNMP::Info::MAU::GLOBALS,
    %SNMP::Info::LLDP::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS, %SNMP::Info::MAU::FUNCS,
    %SNMP::Info::LLDP::FUNCS,
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE, %SNMP::Info::MAU::MUNGE,
    %SNMP::Info::LLDP::MUNGE,
);

# use MAU-MIB for admin. duplex and admin. speed
*SNMP::Info::Layer3::AlcatelLucent::i_duplex_admin
    = \&SNMP::Info::MAU::mau_i_duplex_admin;
*SNMP::Info::Layer3::AlcatelLucent::i_speed_admin
    = \&SNMP::Info::MAU::mau_i_speed_admin;

sub model {
    my $alu   = shift;
    my $id    = $alu->id();
    my $model = &SNMP::translateObj($id);

    return $id unless defined $model;

    $model =~ s/^device//;

    return $model;
}

sub os {
    return 'AOS';
}

sub vendor {
    return 'alcatel-lucent';
}

sub os_ver {
    my $alu = shift;

    my $descr = $alu->description();
    if ( $descr =~ m/^(\S+)/ ) {
        return $1;
    }

    # No clue what this will try but hey
    return $alu->SUPER::os_ver();
}

# ps1_type, ps1_status, ps2_type, ps2_status:
# Find the list of power supplies in the ENTITY-MIB
# e_class = powerSupply
# e_descr = ps_type
# chasEntPhysOperStatus = ps_status
sub _power_supplies {
    my $alu = shift;

    my $e_class  = $alu->e_class();
    my @supplies = ();

    foreach my $key ( sort { int($a) cmp int($b) } keys %$e_class ) {
        if ( $e_class->{$key} eq 'powerSupply' ) {
            push( @supplies, int($key) );
        }
    }
    return @supplies;
}

sub _ps_type {
    my $alu   = shift;
    my $psnum = shift;
    my @ps    = $alu->_power_supplies();

    if ( $psnum > $#ps ) {
        return "none";
    }
    my $supply = $ps[$psnum];
    my $descr  = $alu->e_descr($supply);
    return $descr->{$supply};
}

sub _ps_status {
    my $alu   = shift;
    my $psnum = shift;
    my @ps    = $alu->_power_supplies();

    if ( $psnum > $#ps ) {
        return "not present";
    }
    my $supply = $ps[$psnum];
    my $status = $alu->chasEntPhysOperStatus($supply);
    return $status->{$supply};
}

sub ps1_type {
    my $alu = shift;
    return $alu->_ps_type(0);
}

sub ps2_type {
    my $alu = shift;
    return $alu->_ps_type(1);
}

sub ps1_status {
    my $alu = shift;
    return $alu->_ps_status(0);
}

sub ps2_status {
    my $alu = shift;
    return $alu->_ps_status(1);
}

# The interface description contains the software version, so
# to avoid losing historical information through a software upgrade
# we use interface name instead.
sub interfaces {
    my $alu     = shift;
    my $partial = shift;

    return $alu->orig_i_name($partial);
}

# Use Q-BRIDGE-MIB
sub fw_mac {
    my $alu     = shift;
    my $partial = shift;

    return $alu->qb_fw_mac($partial);
}

sub fw_port {
    my $alu     = shift;
    my $partial = shift;

    return $alu->qb_fw_port($partial);
}

# Work around buggy bp_index in 6.3.1.871.R01 and 6.3.1.975.R01
sub bp_index {
    my $alu     = shift;
    my $partial = shift;

    my $bp_index = $alu->SUPER::bp_index($partial);

    #
    # This device sometimes reports an ifIndex and sometimes reports
    # dot1dBasePort for the dot1d port values - e.g.,
    # in 6.3.1.871.R01 both dot1dTpFdbPort and dot1qTpFdbPort report
    # the ifIndex; in 6.3.1.975.R01 dot1dTpFdbPort has been updated
    # to report the dot1dBasePort but dot1qTpFdbPort still returns an
    # ifIndex.  For this reason, we augment the dot1dBasePort
    # mapping with ifIndex->ifIndex mappings -- we can do this because
    # the ifIndex and dot1dBasePort spaces don't overlap, at least for
    # the ports we care about.
    my @keys = keys %$bp_index;
    foreach my $idx (@keys) {
        my $ifIndex = $bp_index->{$idx};
        $bp_index->{$ifIndex} = $ifIndex;
    }

    #
    # In addition, aggregates aren't reported at all in bp_index.
    # We grab them from i_index.
    my $i_index = $alu->i_index();
    foreach my $idx ( keys %$i_index ) {
        my $ifIndex = $i_index->{$idx};
        if ( int($ifIndex) > 40000001 ) {
            $bp_index->{$ifIndex} = $ifIndex;

            # dot1dTpFdbPort seems to use 4098, 4099, 4100 for
            # 40000001, 40000002, 40000003.  I guess this is
            # 4096 + 1 + aggregate number.
            my $tmp = sprintf( "%d", int($ifIndex) - 39995903 );
            $bp_index->{$tmp} = $ifIndex;
        }
    }
    return $bp_index;
}

# Workaround for unimplemented Q-BRIDGE-MIB::dot1qPvid
# If there is only one VLAN on which a given port is output
# untagged, then call that one the PVID.  This is a guess that
# works in obvious configurations but may be wrong in
# subtle cases (like there's one output VLAN but a different
# input one - the only way to know that is via the dot1qPvid
# object)
#
# Newer versions have implemented dot1qPvid (but wrong, but
# that's just life)
#sub i_vlan {
#    my $alu = shift;
#
#    my $qb_v_untagged = $alu->qb_v_untagged();
#    my $bp_index = $alu->bp_index();
#    my $vlan_list = {};
#    foreach my $vlan (keys %$qb_v_untagged) {
#	my $portlist = $qb_v_untagged->{$vlan};
#	my $port;
#	for ($port = 0; $port <= $#$portlist; $port++) {
#	    if ($portlist->[$port]) {
#		my $ifindex = $bp_index->{$port + 1};
#		if ($ifindex) {
#		    push(@{$vlan_list->{$ifindex}}, int($vlan));
#		}
#	    }
#	}
#    }
#
#    my $i_vlan = {};
#    foreach my $ifindex (keys %$vlan_list) {
#	if ($#{$vlan_list->{$ifindex}} == 0) {
#	    $i_vlan->{$ifindex} = ${$vlan_list->{$ifindex}}[0];
#	}
#    }
#    return $i_vlan;
#}

# Use LLDP
# (or at least try.  The versions I've seen have two problems:
# 1. they report ifIndex values as 'local'; we don't support ifIndex
#    but *could*
# 2. They report 0.0.0.0 as the management address
# )
sub hasCDP {
    my $alu = shift;

    return $alu->hasLLDP();
}

sub c_ip {
    my $alu     = shift;
    my $partial = shift;

    return $alu->lldp_ip($partial);
}

sub c_if {
    my $alu     = shift;
    my $partial = shift;

    return $alu->lldp_if($partial);
}

sub c_port {
    my $alu     = shift;
    my $partial = shift;

    return $alu->lldp_port($partial);
}

sub c_id {
    my $alu     = shift;
    my $partial = shift;

    return $alu->lldp_id($partial);
}

sub c_platform {
    my $alu     = shift;
    my $partial = shift;

    return $alu->lldp_rem_sysdesc($partial);
}

# Power-Ethernet ifIndex mapping.  I've only seen this from a
# fixed-config single-module system, so this is only a plausible
# guess as to the mapping on a stack or modular system.
sub peth_port_ifindex {
    my $alu     = shift;
    my $partial = shift;

    my $peth_port_status  = $alu->peth_port_status($partial);
    my $peth_port_ifindex = {};

    foreach my $key ( keys %$peth_port_status ) {
        my @oid = split( m/\./, $key );
        $peth_port_ifindex->{$key} = int( $oid[0] ) * 1000 + int( $oid[1] );
    }
    return $peth_port_ifindex;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::AlcatelLucent - SNMP Interface to Alcatel-Lucent OmniSwitch

=head1 AUTHOR

Bill Fenner

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $alu = new SNMP::Info(
                        AutoSpecify => 1,
                        Debug       => 1,
                        # These arguments are passed directly to SNMP::Session
                        DestHost    => 'myswitch',
                        Community   => 'public',
                        Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $alu->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Alcatel-Lucent OmniSwitch devices

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=item SNMP::Info::MAU

=item SNMP::Info::LLDP

=back

=head2 Required MIBs

=over

=item F<ALCATEL-IND1-DEVICES>

=item F<ALCATEL-IND1-CHASSIS-MIB>

=item F<ALU-POWER-ETHERNET-MIB>

Note that Alcatel-Lucent distributes their own proprietary version of the
F<POWER-ETHERNET-MIB>, but the MIB module name that they distribute is
simply F<POWER-ETHERNET-MIB>.  This module must be hand-edited to change the
module name to F<ALU-POWER-ETHERNET-MIB> so that it can be used simultaneously
with the standard F<POWER-ETHERNET-MIB>.

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::MAU/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::LLDP/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $alu->vendor()

    Returns 'alcatel-lucent'

=item $alu->hasCDP()

    Returns whether LLDP is enabled.

=item $alu->model()

Tries to reference $alu->id() to one of the product MIBs listed above

Removes 'device' from the name for readability.

=item $alu->os()

Returns 'AOS'

=item $alu->os_ver()

Grabs the os version from C<sysDescr>

=item $alu->ps1_type()

Return the type of the first power supply from the F<ENTITY-MIB>

=item $alu->ps2_type()

Return the type of the second power supply from the F<ENTITY-MIB>

=item $alu->ps1_status()

Return the status of the first power supply from the F<ALCATEL-IND1-CHASSIS-MIB>

=item $alu->ps2_status()

Return the status of the second power supply from the F<ALCATEL-IND1-CHASSIS-MIB>

=back

=head2 Global Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::MAU

See documentation in L<SNMP::Info::MAU/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $alu->interfaces()

Returns interface name from C<ifName>, since the default return value
of C<ifDescr> includes the OS version.

=item $alu->fw_mac()

Use the F<Q-BRIDGE-MIB> instead of F<BRIDGE-MIB>

=item $alu->fw_port()

Use the F<Q-BRIDGE-MIB> instead of F<BRIDGE-MIB>

=item $alu->bp_index()

Work around various bugs in the F<BRIDGE-MIB> and
F<Q-BRIDGE-MIB> implementations, by returning both
C<ifIndex> and C<dot1dBasePort> mappings to C<ifIndex> values.

=item $alu->c_id()

Returns LLDP information.

=item $alu->c_if()

Returns LLDP information.

=item $alu->c_ip()

Returns LLDP information.

=item $alu->c_platform()

Returns LLDP information.

=item $alu->c_port()

Returns LLDP information.

=item $alu->i_duplex_admin()

Returns info from F<MAU-MIB>

=item $alu->i_speed_admin()

Returns info from F<MAU-MIB>

=item $alu->peth_port_ifindex()

Returns the C<ifIndex> value for power-ethernet ports
using the OmniSwitch algorithm.

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::MAU

See documentation in L<SNMP::Info::MAU/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"TABLE METHODS"> for details.

=cut
