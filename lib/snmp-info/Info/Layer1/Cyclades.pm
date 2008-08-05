# SNMP::Info::Layer1::Cyclades
# $Id: Cyclades.pm,v 1.7 2008/08/02 03:22:04 jeneric Exp $
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

package SNMP::Info::Layer1::Cyclades;

use strict;
use Exporter;
use SNMP::Info::Layer1;

@SNMP::Info::Layer1::Cyclades::ISA       = qw/SNMP::Info::Layer1 Exporter/;
@SNMP::Info::Layer1::Cyclades::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE $AUTOLOAD/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer1::MIBS,
    'CYCLADES-ACS-SYS-MIB'  => 'cyACSversion',
    'CYCLADES-ACS-CONF-MIB' => 'cyEthIPaddr',
    'CYCLADES-ACS-INFO-MIB' => 'cyISPortTty',
);

%GLOBALS = (

    # CYCLADES-ACS-SYS-MIB
    %SNMP::Info::Layer1::GLOBALS,
    'os_ver'     => 'cyACSversion',
    'cy_model'   => 'cyACSpname',
    'serial'     => 'cyACSDevId',
    'root_ip'    => 'cyEthIPaddr',
    'ps1_status' => 'cyACSPw1',
    'ps2_status' => 'cyACSPw2',
);

%FUNCS = (
    %SNMP::Info::Layer1::FUNCS,

    # CYCLADES-ACS-INFO-MIB::cyInfoSerialTable
    'cy_port_tty'   => 'cyISPortTty',
    'cy_port_name'  => 'cyISPortName',
    'cy_port_speed' => 'cyISPortSpeed',
    'cy_port_cd'    => 'cyISPortSigCD',

    # CYCLADES-ACS-CONF-MIB::cySerialPortTable
    'cy_port_socket' => 'cySPortSocketPort',
);

%MUNGE = ( %SNMP::Info::Layer1::MUNGE, );

# These devices don't have a FDB and we probably don't want to poll for ARP
# cache so turn off reported L2/L3.
sub layers {
    return '01000001';
}

sub os {
    return 'cyclades';
}

sub vendor {
    return 'cyclades';
}

sub model {
    my $cyclades = shift;

    my $model = $cyclades->cy_model();

    return unless defined $model;

    return lc($model);
}

# Extend interface methods to include serial ports
#
# Partials don't really help in this class, but implemented
# for consistency

sub i_index {
    my $cyclades = shift;
    my $partial  = shift;

    my $orig_index = $cyclades->orig_i_index($partial) || {};
    my $cy_index   = $cyclades->cy_port_socket()       || {};

    my %i_index;
    foreach my $iid ( keys %$orig_index ) {
        my $index = $orig_index->{$iid};
        next unless defined $index;

        $i_index{$iid} = $index;
    }

    # Use alternative labeling system for the serial port, listening socket
    # to avoid conflicts with ifIndex.
    foreach my $iid ( keys %$cy_index ) {
        my $index = $cy_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        $i_index{$index} = $index;
    }

    return \%i_index;
}

sub interfaces {
    my $cyclades = shift;
    my $partial  = shift;

    my $i_descr  = $cyclades->orig_i_description($partial) || {};
    my $cy_index = $cyclades->cy_port_socket()             || {};
    my $cy_p_tty = $cyclades->cy_port_tty()                || {};

    my %if;
    foreach my $iid ( keys %$i_descr ) {
        my $descr = $i_descr->{$iid};
        next unless defined $descr;

        $if{$iid} = $descr;
    }

    foreach my $iid ( keys %$cy_p_tty ) {
        my $index = $cy_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $name = $cy_p_tty->{$iid};
        next unless defined $name;

        $if{$index} = $name;
    }

    return \%if;
}

sub i_speed {
    my $cyclades = shift;
    my $partial  = shift;

    my $i_speed    = $cyclades->orig_i_speed($partial) || {};
    my $cy_index   = $cyclades->cy_port_socket()       || {};
    my $cy_p_speed = $cyclades->cy_port_speed()        || {};

    my %i_speed;
    foreach my $iid ( keys %$i_speed ) {
        my $speed = $i_speed->{$iid};
        next unless defined $speed;

        $i_speed{$iid} = $speed;
    }

    foreach my $iid ( keys %$cy_p_speed ) {
        my $index = $cy_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $speed = $cy_p_speed->{$iid};
        next unless defined $speed;

        $i_speed{$index} = $speed;
    }

    return \%i_speed;
}

sub i_up {
    my $cyclades = shift;
    my $partial  = shift;

    my $i_up     = $cyclades->orig_i_up($partial) || {};
    my $cy_index = $cyclades->cy_port_socket()    || {};
    my $cy_p_up  = $cyclades->cy_port_cd()        || {};

    my %i_up;
    foreach my $iid ( keys %$i_up ) {
        my $up = $i_up->{$iid};
        next unless defined $up;

        $i_up{$iid} = $up;
    }

    foreach my $iid ( keys %$cy_p_up ) {
        my $index = $cy_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $up = $cy_p_up->{$iid};
        next unless defined $up;

        $i_up{$index} = $up;
    }

    return \%i_up;
}

sub i_description {
    my $cyclades = shift;
    my $partial  = shift;

    my $i_desc    = $cyclades->orig_i_description($partial) || {};
    my $cy_index  = $cyclades->cy_port_socket()             || {};
    my $cy_p_desc = $cyclades->cy_port_name()               || {};

    my %descr;
    foreach my $iid ( keys %$i_desc ) {
        my $desc = $i_desc->{$iid};
        next unless defined $desc;

        $descr{$iid} = $desc;
    }

    foreach my $iid ( keys %$cy_p_desc ) {
        my $index = $cy_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $desc = $cy_p_desc->{$iid};
        next unless defined $desc;

        $descr{$index} = $desc;
    }

    return \%descr;
}

sub i_name {
    my $cyclades = shift;
    my $partial  = shift;

    my $i_name    = $cyclades->orig_i_name($partial) || {};
    my $cy_index  = $cyclades->cy_port_socket()      || {};
    my $cy_p_desc = $cyclades->cy_port_name()        || {};

    my %i_name;
    foreach my $iid ( keys %$i_name ) {
        my $name = $i_name->{$iid};
        next unless defined $name;

        $i_name{$iid} = $name;
    }

    foreach my $iid ( keys %$cy_p_desc ) {
        my $index = $cy_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $name = $cy_p_desc->{$iid};
        next unless defined $name;

        $i_name{$index} = $name;
    }

    return \%i_name;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer1::Cyclades - SNMP Interface to Cyclades terminal servers

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    #Let SNMP::Info determine the correct subclass for you.

    my $cyclades = new SNMP::Info(
                        AutoSpecify => 1,
                        Debug       => 1,
                        # These arguments are passed directly to SNMP::Session
                        DestHost    => 'myswitch',
                        Community   => 'public',
                        Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $cyclades->class();
    print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Cyclades device through SNMP.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

my $cyclades = new SNMP::Info::Layer1::Cyclades(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer1

=back

=head2 Required MIBs

=over

=item F<CYCLADES-ACS-SYS-MIB>

=item F<CYCLADES-ACS-CONF-MIB>

=item F<CYCLADES-ACS-INFO-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::Layer1/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $cyclades->os_ver()

(C<cyACSversion>)

=item $cyclades->serial()

(C<cyACSDevId>)

=item $cyclades->root_ip()

(C<cyEthIPaddr>)

=item $cyclades->ps1_status()

(C<cyACSPw1>)

=item $cyclades->ps2_status()

(C<cyACSPw2>)

=back

=head2 Overrides

=over

=item $cyclades->layers()

Returns 01000001.  These devices don't have a FDB and we probably don't want
to poll for an ARP cache so turn off reported Layer 2 and Layer 3.

=item $cyclades->vendor()

Returns 'cyclades'

=item $cyclades->os()

Returns 'cyclades'

=item $cyclades->model()

Returns lower case (C<cyACSpname>)

=back

=head2 Globals imported from SNMP::Info::Layer1

See L<SNMP::Info::Layer1/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $cyclades->i_index()

Returns reference to map of IIDs to Interface index. 

Extended to include serial ports.  Serial ports are indexed with the
alternative labeling system for the serial port, the listening socket port
C<cySPortSocketPort> to avoid conflicts with C<ifIndex>.  

=item $cyclades->interfaces()

Returns reference to map of IIDs to physical ports.  Extended to include
serial ports, C<cyISPortTty>.

=item $cyclades->i_speed()

Returns interface speed.  Extended to include serial ports, C<cyISPortSpeed>. 

=item $cyclades->i_up()

Returns link status for each port.  Extended to include serial ports,
C<cyISPortSigCD>.

=item $cyclades->i_description()

Returns description of each port.  Extended to include serial ports,
C<cyISPortName>.

=item $cyclades->i_name()

Returns name of each port.  Extended to include serial ports, C<cyISPortName>.

=back

=head2 Table Methods imported from SNMP::Info::Layer1

See L<SNMP::Info::Layer1/"TABLE METHODS"> for details.

=cut
