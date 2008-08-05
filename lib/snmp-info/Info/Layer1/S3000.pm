# SNMP::Info::Layer1::S3000
# $Id: S3000.pm,v 1.12 2008/08/02 03:22:04 jeneric Exp $
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

package SNMP::Info::Layer1::S3000;

use strict;
use Exporter;
use SNMP::Info::Layer2;

@SNMP::Info::Layer1::S3000::ISA       = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer1::S3000::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer2::MIBS,
    'SYNOPTICS-ETHERNET-MIB' => 's3EnetPortTable',
    'SYNOPTICS-COMMON-MIB'   => 's3AgentType',
);

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS,

    # From SYNOPTICS-COMMON-MIB
    'os_bin'          => 's3AgentFwVer',
    's3000_major_ver' => 's3AgentSwMajorVer',
    's3000_minor_ver' => 's3AgentSwMinorVer',
    's3000_maint_ver' => 's3AgentSwMaintVer',
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,

    # SYNOPTICS-ETHERNET-MIB::s3EnetPortTable
    's3000_pb_index' => 's3EnetPortBoardIndex',
    's3000_pp_index' => 's3EnetPortIndex',
    's3000_up_admin' => 's3EnetPortPartStatus',
    's3000_up'       => 's3EnetPortLinkStatus',

    # SYNOPTICS-ETHERNET-MIB::s3EnetShowNodesTable
    's3000_nb_index' => 's3EnetShowNodesSlotIndex',
    's3000_np_index' => 's3EnetShowNodesPortIndex',
    'fw_mac'         => 's3EnetShowNodesMacAddress',

    # SYNOPTICS-ETHERNET-MIB::s3EnetTopNmmTable
    's3000_topo_port' => 's3EnetTopNmmPort',
    's3000_topo_mac'  => 's3EnetTopNmmMacAddr',
);

%MUNGE = (
    %SNMP::Info::Layer2::MUNGE, 's3000_topo_mac' => \&SNMP::Info::munge_mac
);

sub layers {
    return '00000011';
}

sub os {
    return 'synoptics';
}

sub vendor {
    return 'nortel';
}

sub model {
    my $s3000 = shift;
    my $id    = $s3000->id();
    return unless defined $id;
    my $model = &SNMP::translateObj($id);
    return $id unless defined $model;
    $model =~ s/^s3reg-//i;

    return $1 if ( $model =~ /((\d+){3}[\dX])/ );
    return $model;
}

sub os_ver {
    my $s3000     = shift;
    my $major_ver = $s3000->s3000_major_ver() || 0;
    my $minor_ver = $s3000->s3000_minor_ver() || 0;
    my $maint_ver = $s3000->s3000_maint_ver() || 0;

    my $ver = "$major_ver.$minor_ver.$maint_ver";
    return $ver;
}

sub mac {
    my $s3000     = shift;
    my $topo_port = $s3000->s3000_topo_port();
    my $topo_mac  = $s3000->s3000_topo_mac();

    foreach my $entry ( keys %$topo_port ) {
        my $port = $topo_port->{$entry};
        next unless $port == 0;
        my $mac = $topo_mac->{$entry};
        return $mac;
    }

    # Topology turned off, not supported.
    return;
}

# Hubs do not support ifMIB requirements for get MAC
# and port status

sub i_index {
    my $s3000   = shift;
    my $partial = shift;

    my $b_index = $s3000->s3000_pb_index($partial) || {};
    my $p_index = $s3000->s3000_pp_index($partial) || {};

    my %i_index;
    foreach my $iid ( keys %$b_index ) {
        my $board = $b_index->{$iid};
        next unless defined $board;
        my $port = $p_index->{$iid} || 0;

        # We need to make up an index for multiple board instances.
        my $index = ( $board * 256 ) + $port;

        $i_index{$iid} = $index;
    }
    return \%i_index;
}

# Partials don't really help in this class, but implemented
# for consistency

sub interfaces {
    my $s3000   = shift;
    my $partial = shift;

    my $i_index = $s3000->i_index() || {};

    my %if;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        # Index numbers are deterministic slot * 256 + port - see i_index()
        my $port = $index % 256;
        my $slot = int( $index / 256 );

        my $slotport = "$slot.$port";

        $if{$index} = $slotport;
    }

    return \%if;
}

sub i_duplex {
    my $s3000   = shift;
    my $partial = shift;

    my $port_index = $s3000->i_index() || {};

    my %i_duplex;
    foreach my $iid ( keys %$port_index ) {
        my $index = $port_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        # Hubs only function half duplex
        my $duplex = 'half';
        $i_duplex{$index} = $duplex;
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $s3000   = shift;
    my $partial = shift;

    my $port_index = $s3000->i_index() || {};

    my %i_duplex_admin;
    foreach my $iid ( keys %$port_index ) {
        my $index = $port_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        # Hubs only function half duplex
        my $duplex = 'half';
        $i_duplex_admin{$index} = $duplex;
    }
    return \%i_duplex_admin;
}

sub i_speed {
    my $s3000   = shift;
    my $partial = shift;

    my $port_index = $s3000->i_index() || {};

    my %i_speed;
    foreach my $iid ( keys %$port_index ) {
        my $index = $port_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        # These hubs only support 10 Mbs
        my $speed = '10000000';
        $i_speed{$index} = $speed;
    }
    return \%i_speed;
}

sub i_up {
    my $s3000   = shift;
    my $partial = shift;

    my $port_index = $s3000->i_index()  || {};
    my $link_stat  = $s3000->s3000_up() || {};

    my %i_up;
    foreach my $iid ( keys %$port_index ) {
        my $index = $port_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $link_stat = $link_stat->{$iid};
        next unless defined $link_stat;

        $link_stat = 'up'   if $link_stat =~ /on/i;
        $link_stat = 'down' if $link_stat =~ /off/i;

        $i_up{$index} = $link_stat;
    }
    return \%i_up;
}

sub i_up_admin {
    my $s3000   = shift;
    my $partial = shift;

    my $i_index   = $s3000->i_index()        || {};
    my $link_stat = $s3000->s3000_up_admin() || {};

    my %i_up_admin;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $link_stat = $link_stat->{$iid};
        next unless defined $link_stat;

        $i_up_admin{$index} = $link_stat;
    }
    return \%i_up_admin;
}

sub set_i_up_admin {

    # map setting to those the hub will understand
    my %setting = qw/up 2 down 3/;

    my $s3000 = shift;
    my ( $setting, $iid ) = @_;

    my $i_index = $s3000->i_index() || {};
    my %reverse_i_index = reverse %$i_index;

    $setting = lc($setting);

    return 0 unless defined $setting{$setting};

    $iid = $reverse_i_index{$iid};

    return $s3000->set_s3000_up_admin( $setting{$setting}, $iid );
}

# Hubs do not support the standard Bridge MIB
sub bp_index {
    my $s3000   = shift;
    my $partial = shift;

    my $b_index = $s3000->s3000_nb_index() || {};
    my $p_index = $s3000->s3000_np_index() || {};
    my $model   = $s3000->model();

    my %bp_index;
    foreach my $iid ( keys %$b_index ) {
        my $board = $b_index->{$iid};
        next unless defined $board;
        my $port = $p_index->{$iid} || 0;

        my $index = ( $board * 256 ) + $port;
        next if ( defined $partial and $index !~ /^$partial$/ );

        $bp_index{$index} = $index;
    }
    return \%bp_index;
}

sub fw_port {
    my $s3000   = shift;
    my $partial = shift;

    my $b_index = $s3000->s3000_nb_index($partial) || {};
    my $p_index = $s3000->s3000_np_index($partial) || {};
    my $model   = $s3000->model();

    my %fw_port;
    foreach my $iid ( keys %$b_index ) {
        my $board = $b_index->{$iid};
        next unless defined $board;
        my $port = $p_index->{$iid} || 0;

        my $index = ( $board * 256 ) + $port;

        $fw_port{$iid} = $index;
    }
    return \%fw_port;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer1::S3000 - SNMP Interface to Synoptics / Nortel Hubs

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    #Let SNMP::Info determine the correct subclass for you.

    my $s3000 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $s3000->class();
    print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Bay hub device through SNMP.  Also provides device MAC to port mapping through
the proprietary MIB.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

my $s3000 = new SNMP::Info::Layer1::S3000(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item F<SYNOPTICS-COMMON-MIB>

=item F<SYNOPTICS-ETHERNET-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::Layer2/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $s3000->vendor()

Returns 'nortel'

=item $s3000->os()

Returns 'synoptics'

=item $s3000->model()

Cross references $s3000->id() to the F<SYNOPTICS-MIB> and returns
the results.

Removes C<sreg-> from the model name and returns only the numeric model
identifier.

=item $stack->os_ver()

Returns the software version specified as major.minor.maint.

(C<s3AgentSwMajorVer>).(C<s3AgentSwMinorVer>).(C<s3AgentSwMaintVer>)

=item $stack->os_bin()

Returns the firmware version. (C<s3AgentFwVer>)

=item $s3000->mac()

Returns MAC of the advertised IP address of the device. 

=back

=head2 Overrides

=over

=item $s3000->layers()

Returns 00000011.  Class emulates Layer 2 functionality through proprietary
MIBs.

=back

=head2 Globals imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $s3000->i_index()

Returns reference to map of IIDs to Interface index. 

Since hubs do not support C<ifIndex>, the interface index is created using the
formula (board * 256 + port).  This is required to support devices with more
than one module.

=item $s3000->interfaces()

Returns reference to map of IIDs to physical ports. 

=item $s3000->i_duplex()

Returns half, hubs do not support full duplex. 

=item $s3000->i_duplex_admin()

Returns half, hubs do not support full duplex.

=item $s3000->i_speed()

Returns 10000000.  The hubs only support 10 Mbs Ethernet.

=item $s3000->i_up()

Returns (C<s3EnetPortLinkStatus>) for each port.  Translates on/off to
up/down.

=item $s3000->i_up_admin()

Returns (C<s3EnetPortPartStatus>) for each port.

=item $s3000->set_i_up_admin(state, ifIndex)

Sets port state, must be supplied with state and port C<ifIndex>

State choices are 'up' or 'down'

Example:
  my %if_map = reverse %{$s3000->interfaces()};
  $s3000->set_i_up_admin('down', $if_map{'1.1'}) 
      or die "Couldn't change port state. ",$s3000->error(1);

=item $s3000->bp_index()

Simulates bridge MIB by returning reference to a hash containing the index for
both the keys and values.

=item $s3000->fw_port()

Returns reference to map of IIDs of the
C<SYNOPTICS-ETHERNET-MIB::s3EnetShowNodesTable> to the Interface index.

=item $s3000->fw_mac()

(C<s3EnetShowNodesMacAddress>)

=item $s3000->s3000_topo_port()

Returns reference to hash.  Key: Table entry, Value:Port Number
(interface iid)

(C<s3EnetTopNmmPort>)

=item $s3000->s3000_topo_mac()

(C<s3EnetTopNmmMacAddr>)

Returns reference to hash.  Key: Table entry, Value:Remote MAC address

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
