# SNMP::Info::Layer3::Arista
# $Id: Arista.pm,v 1.2 2009/03/23 19:30:30 fenner Exp $
#
# Copyright (c) 2008 Arista Networks, Inc.
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
#     * Neither the name of Arista Networks, Inc. nor the
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

package SNMP::Info::Layer3::Arista;

use strict;
use Exporter;

use SNMP::Info::Layer3;
use SNMP::Info::MAU;
use SNMP::Info::LLDP;

@SNMP::Info::Layer3::Arista::ISA = qw/SNMP::Info::LLDP SNMP::Info::MAU
    SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Arista::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer3::MIBS,
    %SNMP::Info::MAU::MIBS,
    %SNMP::Info::LLDP::MIBS,
    'ARISTA-PRODUCTS-MIB' => 'aristaProducts',
);

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    %SNMP::Info::MAU::GLOBALS,
    %SNMP::Info::LLDP::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS,
    %SNMP::Info::MAU::FUNCS,
    %SNMP::Info::LLDP::FUNCS,
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE,
    %SNMP::Info::MAU::MUNGE,
    %SNMP::Info::LLDP::MUNGE,
);

# use MAU-MIB for admin. duplex and admin. speed
*SNMP::Info::Layer3::Arista::i_duplex_admin
    = \&SNMP::Info::MAU::mau_i_duplex_admin;
*SNMP::Info::Layer3::Arista::i_speed_admin
    = \&SNMP::Info::MAU::mau_i_speed_admin;

sub vendor {
    return 'arista';
}

sub os {
    return 'EOS';
}

sub os_ver {
    my $arista = shift;
    my $descr   = $arista->description();
    my $os_ver  = undef;

    $os_ver = $1 if ( $descr =~ /\s+EOS\s+version\s+(\S+)\s+/ );
    return $os_ver;
}

sub model {
    my $arista = shift;
    my $id     = $arista->id();

    my $model = &SNMP::translateObj($id);
    return $id unless defined $model;

    $model =~ s/^arista//;
    return $model;
}

# Use Q-BRIDGE-MIB

sub fw_mac {
    my $arista  = shift;
    my $partial = shift;

    return $arista->qb_fw_mac($partial);
}

sub fw_port {
    my $arista  = shift;
    my $partial = shift;

    return $arista->qb_fw_port($partial);
}

# Use LLDP

sub hasCDP {
    my $arista = shift;

    return $arista->hasLLDP();
}

sub c_ip {
    my $arista  = shift;
    my $partial = shift;

    return $arista->lldp_ip($partial);
}

sub c_if {
    my $arista  = shift;
    my $partial = shift;

    return $arista->lldp_if($partial);
}

sub c_port {
    my $arista  = shift;
    my $partial = shift;

    return $arista->lldp_port($partial);
}

sub c_id {
    my $arista  = shift;
    my $partial = shift;

    return $arista->lldp_id($partial);
}

sub c_platform {
    my $arista  = shift;
    my $partial = shift;

    return $arista->lldp_rem_sysdesc($partial);
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::Arista - SNMP Interface to Arista Networks EOS

=head1 AUTHOR

Bill Fenner

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $arista = new SNMP::Info(
                        AutoSpecify => 1,
                        Debug       => 1,
                        # These arguments are passed directly to SNMP::Session
                        DestHost    => 'myswitch',
                        Community   => 'public',
                        Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $arista->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Arista Networks EOS-based devices

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=item SNMP::Info::MAU

=item SNMP::Info::LLDP

=back

=head2 Required MIBs

=over

=item F<ARISTA-PRODUCTS-MIB>

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::MAU/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::LLDP/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar values from SNMP

=over

=item $arista->vendor()

    Returns 'Arista Networks, Inc.'

=item $arista->hasCDP()

    Returns whether LLDP is enabled.

=item $arista->model()

Tries to reference $arista->id() to one of the product MIBs listed above

Removes 'arista' from the name for readability.

=item $arista->os()

Returns 'EOS'

=item $arista->os_ver()

Grabs the os version from C<sysDescr>

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

=item $arista->fw_mac()

Use the F<Q-BRIDGE-MIB> instead of F<BRIDGE-MIB>

=item $arista->fw_port()

Use the F<Q-BRIDGE-MIB> instead of F<BRIDGE-MIB>

=item $arista->c_id()

Returns LLDP information.

=item $arista->c_if()

Returns LLDP information.

=item $arista->c_ip()

Returns LLDP information.

=item $arista->c_platform()

Returns LLDP information.

=item $arista->c_port()

Returns LLDP information.

=item $arista->i_duplex_admin()

Returns info from F<MAU-MIB>

=item $arista->i_speed_admin()

Returns info from F<MAU-MIB>

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::MAU

See documentation in L<SNMP::Info::MAU/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::LLDP

See documentation in L<SNMP::Info::LLDP/"TABLE METHODS"> for details.

=cut
