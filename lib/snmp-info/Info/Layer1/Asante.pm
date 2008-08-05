# SNMP::Info::Layer1::Asante
# $Id: Asante.pm,v 1.24 2008/08/02 03:22:03 jeneric Exp $
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

package SNMP::Info::Layer1::Asante;

use strict;
use Exporter;
use SNMP::Info::Layer1;

@SNMP::Info::Layer1::Asante::ISA       = qw/SNMP::Info::Layer1 Exporter/;
@SNMP::Info::Layer1::Asante::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

# Set for No CDP
%GLOBALS = ( %SNMP::Info::Layer1::GLOBALS, );

%FUNCS = (
    %SNMP::Info::Layer1::FUNCS,
    'asante_port'  => 'ePortIndex',
    'asante_group' => 'ePortGrpIndex',
    'i_type'       => 'ePortStateType',
    'asante_up'    => 'ePortStateLinkStatus',
);

%MIBS = ( %SNMP::Info::Layer1::MIBS, 'ASANTE-HUB1012-MIB' => 'asante' );

%MUNGE = ( %SNMP::Info::Layer1::MUNGE, );

sub interfaces {
    my $asante  = shift;
    my $partial = shift;

    my $rptr_port = $asante->rptr_port($partial) || {};

    my %interfaces;

    foreach my $port ( keys %$rptr_port ) {
        $interfaces{$port} = $port;
    }

    return \%interfaces;
}

sub os {
    return 'asante';
}

sub os_ver {
    my $asante = shift;
    my $descr  = $asante->description();

    if ( $descr =~ /software v(\d+\.\d+)/ ) {
        return $1;
    }
}

sub vendor {
    return 'asante';
}

sub model {
    my $asante = shift;

    my $id    = $asante->id();
    my $model = &SNMP::translateObj($id);

    return $model;
}

sub i_up {
    my $asante  = shift;
    my $partial = shift;

    my $asante_up = $asante->asante_up($partial) || {};

    my $i_up = {};
    foreach my $port ( keys %$asante_up ) {
        my $up = $asante_up->{$port};
        $i_up->{$port} = 'down' if $up =~ /on/;
        $i_up->{$port} = 'up'   if $up =~ /off/;
    }

    return $i_up;
}

sub i_speed {
    my $asante  = shift;
    my $partial = shift;

    my $i_speed = $asante->orig_i_speed($partial) || {};

    my %i_speed;

    $i_speed{"1.2"} = $i_speed->{1};

    return \%i_speed;
}

sub i_mac {
    my $asante  = shift;
    my $partial = shift;

    my $i_mac = $asante->orig_i_mac($partial) || {};

    my %i_mac;

    $i_mac{"1.2"} = $i_mac->{1};

    return \%i_mac;
}

sub i_description {
    return;
}

sub i_name {
    my $asante  = shift;
    my $partial = shift;

    my $i_name = $asante->orig_i_descr($partial) || {};

    my %i_name;

    $i_name{"1.2"} = $i_name->{1};

    return \%i_name;
}

1;

__END__

=head1 NAME

SNMP::Info::Layer1::Asante - SNMP Interface to old Asante 1012 Hubs

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $asante = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $asante->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Asante device through SNMP.

=head2 Inherited Classes

=over

=item SNMP::Info::Layer1

=back

=head2 Required MIBs

=over

=item F<ASANTE-HUB1012-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::Layer1/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

=head2 Overrides

=over

=item $asante->os()

Returns 'asante'

=item $asante->os_ver()

Culls software version from description()

=item $asante->vendor()

Returns 'asante' :)

=item $asante->model()

Cross references $asante->id() to the F<ASANTE-HUB1012-MIB> and returns
the results.

=back

=head2 Global Methods imported from SNMP::Info::Layer1

See L<SNMP::Info::Layer1/"GLOBALS"> for details.

=head1 TABLE METHODS

=head2 Overrides

=over

=item $asante->interfaces()

Returns reference to the map between IID and physical Port.

=item $asante->i_description() 

Description of the interface.

=item $asante->i_mac()

MAC address of the interface.  Note this is just the MAC of the port, not
anything connected to it.

=item $asante->i_name()

Returns reference to map of IIDs to human-set port name.

=item $asante->i_up()

Returns reference to map of IIDs to link status.  Changes
the values of asante_up() to 'up' and 'down'.

=item $asante->i_speed()

Speed of the link, human format.

=back

=head2 Asante MIB

=over

=item $asante->ati_p_name()

(C<portName>)

=item $asante->ati_up()

(C<linkTestLED>)

=back

=head2 Table Methods imported from SNMP::Info::Layer1

See L<SNMP::Info::Layer1/"TABLE METHODS"> for details.

=cut
