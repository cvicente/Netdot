# SNMP::Info::Layer2::Foundry - SNMP Interface to Foundry Switches
# $Id: Foundry.pm,v 1.16 2008/08/02 03:21:57 jeneric Exp $
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

package SNMP::Info::Layer2::Foundry;

use strict;
use Exporter;
use SNMP::Info::Layer2;
use SNMP::Info::FDP;
use SNMP::Info::EtherLike;
use SNMP::Info::MAU;

@SNMP::Info::Layer2::Foundry::ISA
    = qw/SNMP::Info::Layer2 SNMP::Info::FDP SNMP::Info::EtherLike
    SNMP::Info::MAU    Exporter/;
@SNMP::Info::Layer2::Foundry::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %FUNCS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer2::MIBS,    %SNMP::Info::FDP::MIBS,
    %SNMP::Info::EtherLike::MIBS, %SNMP::Info::MAU::MIBS,
    'FOUNDRY-SN-ROOT-MIB' => 'foundry',
);

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,    %SNMP::Info::FDP::GLOBALS,
    %SNMP::Info::EtherLike::GLOBALS, %SNMP::Info::MAU::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,    %SNMP::Info::FDP::FUNCS,
    %SNMP::Info::EtherLike::FUNCS, %SNMP::Info::MAU::FUNCS,
    'test' => 'dot1dStpPortState',
);

%MUNGE = (
    %SNMP::Info::Layer2::MUNGE,    %SNMP::Info::FDP::MUNGE,
    %SNMP::Info::EtherLike::MUNGE, %SNMP::Info::MAU::MUNGE,
);

# Method OverRides

#sub bulkwalk_no { 1;}

*SNMP::Info::Layer2::Foundry::i_duplex = \&SNMP::Info::MAU::mau_i_duplex;
*SNMP::Info::Layer2::Foundry::i_duplex_admin
    = \&SNMP::Info::MAU::mau_i_duplex_admin;
*SNMP::Info::Layer2::Foundry::i_vlan = \&SNMP::Info::Bridge::qb_i_vlan_t;

# todo doc these

sub os_ver {
    my $foundry = shift;

    my $e_name = $foundry->e_name();

    # find entity table entry for "stackmanaget.1"
    my $unit_iid = undef;
    foreach my $e ( keys %$e_name ) {
        my $name = $e_name->{$e} || '';
        $unit_iid = $e if $name eq 'stackmanaget.1';
    }

    # Default to OID method if no dice.
    unless ( defined $unit_iid ) {
        return $foundry->SUPER::model();
    }

    # Find Model Name
    my $e_fwver = $foundry->e_fwver();
    if ( defined $e_fwver->{$unit_iid} ) {
        return $e_fwver->{$unit_iid};
    }

    # Not found in ENTITY-MIB, go up a level.
    return $foundry->SUPER::os_ver();
}

sub model {
    my $foundry = shift;

    my $e_name = $foundry->e_name();

    # find entity table entry for "unit.1"
    my $unit_iid = undef;
    foreach my $e ( keys %$e_name ) {
        my $name = $e_name->{$e} || '';
        $unit_iid = $e if $name eq 'unit.1';
    }

    # Default to OID method if no dice.
    unless ( defined $unit_iid ) {
        return $foundry->SUPER::model();
    }

    # Find Model Name
    my $e_model = $foundry->e_model();
    if ( defined $e_model->{$unit_iid} ) {
        return $e_model->{$unit_iid};
    }

    # Not found in ENTITY-MIB, go up a level.
    return $foundry->SUPER::model();

}

sub serial {
    my $foundry = shift;

    my $e_name = $foundry->e_name();

    # find entity table entry for "unit.1"
    my $unit_iid = undef;
    foreach my $e ( keys %$e_name ) {
        my $name = $e_name->{$e} || '';
        $unit_iid = $e if $name eq 'unit.1';
    }
    return unless defined $unit_iid;

    # Look up serial of found entry.
    my $e_serial = $foundry->e_serial();
    return $e_serial->{$unit_iid} if defined $e_serial->{$unit_iid};

    return $foundry->SUPER::serial();
}

sub interfaces {
    my $foundry = shift;
    my $i_descr = $foundry->i_description;
    my $i_name  = $foundry->i_name;

    # use ifName only if it is in portn
    #   format.  For EdgeIrons
    # else use ifDescr
    foreach my $iid ( keys %$i_name ) {
        my $name = $i_name->{$iid};
        next unless defined $name;
        $i_descr->{$iid} = $name
            if $name =~ /^port\d+/i;
    }

    return $i_descr;
}

sub i_ignore {
    my $foundry = shift;
    my $i_type  = $foundry->i_type();

    my %i_ignore = ();

    foreach my $iid ( keys %$i_type ) {
        my $type = $i_type->{$iid} || '';
        $i_ignore{$iid}++

            # 33 is the console port
            if $type =~ /(loopback|propvirtual|other|cpu|33)/i;
    }
    return \%i_ignore;
}

sub os {
    return 'foundry';
}

sub vendor {
    return 'foundry';
}

# this hangs on a edgeiron24g
# TODO: check by devicetype and deferr to SUPER if not bad device
sub stp_p_state { return; }

1;
__END__

=head1 NAME

SNMP::Info::Layer2::Foundry - SNMP Interface to Foundry FastIron Network
Devices

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

This module is Deprecated.  Please use Layer3::Foundry instead.

 # Let SNMP::Info determine the correct subclass for you. 
 my $foundry = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $foundry->class();

 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

This module is Deprecated.  Please use Layer3::Foundry instead.

This module provides support for Foundry EdgeIron Switches

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=item SNMP::Info::FDP

=back

=head2 Required MIBs

=over

=item F<FOUNDRY-SN-ROOT-MIB>

=item Inherited Classes' MIBs

See classes listed above for their required MIBs.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $foundry->model()

Returns model type.

=item $foundry->vendor()

Returns 'foundry'

=item $foundry->os()

Returns 'foundry'

=item $foundry->os_ver()

Returns the software version

=item $foundry->serial()

Returns the serial number

=back

=head2 Globals imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::FDP

See documentation in L<SNMP::Info::FDP/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $foundry->interfaces()

Returns reference to hash of interface names to iids.

=item $foundry->i_ignore()

Returns reference to hash of interfaces to be ignored.

Ignores interfaces with descriptions of  tunnel,loopback,null 

=item $foundry->i_duplex()

Returns reference to hash of interface link duplex status. 

Crosses $foundry->sw_duplex() with $foundry->sw_index()

=item $foundry->i_duplex_admin()

Returns reference to hash of interface administrative duplex status. 

=item $foundry->stp_p_state()

"The port's current state as defined by application of the Spanning Tree
Protocol.

Skipped if device is an EdgeIron 24G due to reports of hangs.

(C<dot1dStpPortState>)

=item $foundry->i_vlan()

Returns a mapping between C<ifIndex> and the PVID or default VLAN.

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::FDP

See documentation in L<SNMP::Info::FDP/"TABLE METHODS"> for details.

=cut
