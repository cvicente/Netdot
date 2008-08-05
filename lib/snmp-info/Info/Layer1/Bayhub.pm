# SNMP::Info::Layer1::Bayhub
# $Id: Bayhub.pm,v 1.20 2008/08/02 03:22:03 jeneric Exp $
#
# Copyright (c) 2008 Eric Miller, Max Baker
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

package SNMP::Info::Layer1::Bayhub;

use strict;
use Exporter;
use SNMP::Info::SONMP;
use SNMP::Info::NortelStack;
use SNMP::Info::Layer2;

@SNMP::Info::Layer1::Bayhub::ISA
    = qw/SNMP::Info::SONMP SNMP::Info::NortelStack  SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer1::Bayhub::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::Layer2::MIBS,
    %SNMP::Info::NortelStack::MIBS,
    %SNMP::Info::SONMP::MIBS,
    'S5-ETHERNET-COMMON-MIB' => 's5EnPortTable',
    'S5-COMMON-STATS-MIB'    => 's5CmStat',
);

%GLOBALS = (
    %SNMP::Info::Layer2::GLOBALS, %SNMP::Info::NortelStack::GLOBALS,
    %SNMP::Info::SONMP::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,
    %SNMP::Info::NortelStack::FUNCS,
    %SNMP::Info::SONMP::FUNCS,

    # S5-ETHERNET-COMMON-MIB::s5EnPortTable
    'bayhub_pb_index' => 's5EnPortBrdIndx',
    'bayhub_pp_index' => 's5EnPortIndx',
    'bayhub_up_admin' => 's5EnPortPartStatus',
    'bayhub_up'       => 's5EnPortLinkStatus',

    # S5-ETHERNET-COMMON-MIB::s5EnPortExtTable
    'bayhub_p_speed' => 's5EnPortExtActiveSpeed',
    'bayhub_p_cap'   => 's5EnPortExtHwCapability',
    'bayhub_p_adv'   => 's5EnPortExtAutoNegAdv',

    # S5-COMMON-STATS-MIB::s5CmSNodeTable
    'bayhub_nb_index' => 's5CmSNodeBrdIndx',
    'bayhub_np_index' => 's5CmSNodePortIndx',
    'fw_mac'          => 's5CmSNodeMacAddr',
);

%MUNGE = (
    %SNMP::Info::Layer2::MUNGE, %SNMP::Info::NortelStack::MUNGE,
    %SNMP::Info::SONMP::MUNGE,
);

sub layers {
    return '00000011';
}

sub os {
    return 'bay_hub';
}

sub vendor {
    return 'nortel';
}

sub model {
    my $bayhub = shift;
    my $id     = $bayhub->id();
    return unless defined $id;
    my $model = &SNMP::translateObj($id);
    return $id unless defined $model;
    $model =~ s/^sreg-//i;

    return 'Baystack Hub' if ( $model =~ /BayStack/ );
    return '5000'         if ( $model =~ /5000/ );
    return '5005'         if ( $model =~ /5005/ );
    return $model;
}

# Hubs do not support ifMIB requirements for get MAC
# and port status

sub i_index {
    my $bayhub  = shift;
    my $partial = shift;

    my $b_index = $bayhub->bayhub_pb_index($partial) || {};
    my $p_index = $bayhub->bayhub_pp_index($partial) || {};
    my $model   = $bayhub->model()                   || 'Baystack Hub';

    my %i_index;
    foreach my $iid ( keys %$b_index ) {
        my $board = $b_index->{$iid};
        next unless defined $board;
        my $port = $p_index->{$iid} || 0;

        if ( $model eq 'Baystack Hub' ) {
            my $comidx = $board;
            if ( !( $comidx % 5 ) ) {
                $board = ( $board / 5 );
            }
            elsif ( $comidx =~ /[16]$/ ) {
                $board = int( $board / 5 );
                $port  = 25;
            }
            elsif ( $comidx =~ /[27]$/ ) {
                $board = int( $board / 5 );
                $port  = 26;
            }
        }

        my $index = ( $board * 256 ) + $port;

        $i_index{$iid} = $index;
    }
    return \%i_index;
}

# Partials don't really help in this class, but implemented
# for consistency

sub interfaces {
    my $bayhub  = shift;
    my $partial = shift;

    my $i_index = $bayhub->i_index() || {};

    my %if;
    foreach my $iid ( keys %$i_index ) {
        my $index = $i_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        # Index numbers are deterministic slot * 256 + port
        my $port = $index % 256;
        my $slot = int( $index / 256 );

        my $slotport = "$slot.$port";

        $if{$index} = $slotport;
    }

    return \%if;
}

sub i_duplex {
    my $bayhub  = shift;
    my $partial = shift;

    my $port_index = $bayhub->i_index() || {};

    my %i_duplex;
    foreach my $iid ( keys %$port_index ) {
        my $index = $port_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        my $duplex = 'half';
        $i_duplex{$index} = $duplex;
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $bayhub  = shift;
    my $partial = shift;

    my $port_index = $bayhub->i_index() || {};

    my %i_duplex_admin;
    foreach my $iid ( keys %$port_index ) {
        my $index = $port_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );

        my $duplex = 'half';
        $i_duplex_admin{$index} = $duplex;
    }
    return \%i_duplex_admin;
}

sub i_speed {
    my $bayhub  = shift;
    my $partial = shift;

    my $port_index = $bayhub->i_index()        || {};
    my $port_speed = $bayhub->bayhub_p_speed() || {};

    my %i_speed;
    foreach my $iid ( keys %$port_index ) {
        my $index = $port_index->{$iid};
        next unless defined $index;
        next if ( defined $partial and $index !~ /^$partial$/ );
        my $speed = $port_speed->{$iid} || '10 Mbps';

        $speed = '10 Mbps'  if $speed =~ /bps10M/i;
        $speed = '100 Mbps' if $speed =~ /bps100M/i;
        $i_speed{$index} = $speed;
    }
    return \%i_speed;
}

sub i_up {
    my $bayhub  = shift;
    my $partial = shift;

    my $port_index = $bayhub->i_index()   || {};
    my $link_stat  = $bayhub->bayhub_up() || {};

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
    my $bayhub  = shift;
    my $partial = shift;

    my $i_index   = $bayhub->i_index()         || {};
    my $link_stat = $bayhub->bayhub_up_admin() || {};

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

    my $bayhub = shift;
    my ( $setting, $iid ) = @_;

    my $i_index = $bayhub->i_index() || {};
    my %reverse_i_index = reverse %$i_index;

    $setting = lc($setting);

    return 0 unless defined $setting{$setting};

    $iid = $reverse_i_index{$iid};

    return $bayhub->set_bayhub_up_admin( $setting{$setting}, $iid );
}

# Hubs do not support the standard Bridge MIB
sub bp_index {
    my $bayhub  = shift;
    my $partial = shift;

    my $b_index = $bayhub->bayhub_nb_index() || {};
    my $p_index = $bayhub->bayhub_np_index() || {};
    my $model   = $bayhub->model()           || 'Baystack Hub';

    my %bp_index;
    foreach my $iid ( keys %$b_index ) {
        my $board = $b_index->{$iid};
        next unless defined $board;
        my $port = $p_index->{$iid} || 0;

        if ( $model eq 'Baystack Hub' ) {
            my $comidx = $board;
            if ( !( $comidx % 5 ) ) {
                $board = ( $board / 5 );
            }
            elsif ( $comidx =~ /[16]$/ ) {
                $board = int( $board / 5 );
                $port  = 25;
            }
            elsif ( $comidx =~ /[27]$/ ) {
                $board = int( $board / 5 );
                $port  = 26;
            }
        }

        my $index = ( $board * 256 ) + $port;
        next if ( defined $partial and $index !~ /^$partial$/ );

        $bp_index{$index} = $index;
    }
    return \%bp_index;
}

sub fw_port {
    my $bayhub  = shift;
    my $partial = shift;

    my $b_index = $bayhub->bayhub_nb_index($partial) || {};
    my $p_index = $bayhub->bayhub_np_index($partial) || {};
    my $model   = $bayhub->model()                   || 'Baystack Hub';

    my %fw_port;
    foreach my $iid ( keys %$b_index ) {
        my $board = $b_index->{$iid};
        next unless defined $board;
        my $port = $p_index->{$iid} || 0;

        if ( $model eq 'Baystack Hub' ) {
            my $comidx = $board;
            if ( !( $comidx % 5 ) ) {
                $board = ( $board / 5 );
            }
            elsif ( $comidx =~ /[16]$/ ) {
                $board = int( $board / 5 );
                $port  = 25;
            }
            elsif ( $comidx =~ /[27]$/ ) {
                $board = int( $board / 5 );
                $port  = 26;
            }
        }

        my $index = ( $board * 256 ) + $port;

        $fw_port{$iid} = $index;
    }
    return \%fw_port;
}

sub index_factor {
    return 256;
}

sub slot_offset {
    return 0;
}

# Devices do not support ENTITY-MIB use proprietary methods.

sub e_index {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_index($partial);
}

sub e_class {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_class($partial);
}

sub e_descr {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_descr($partial);
}

sub e_name {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_name($partial);
}

sub e_fwver {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_fwver($partial);
}

sub e_hwver {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_hwver($partial);
}

sub e_parent {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_parent($partial);
}

sub e_pos {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_pos($partial);
}

sub e_serial {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_serial($partial);
}

sub e_swver {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_swver($partial);
}

sub e_type {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_type($partial);
}

sub e_vendor {
    my $stack   = shift;
    my $partial = shift;

    return $stack->ns_e_vendor($partial);
}

1;
__END__

=head1 NAME

SNMP::Info::Layer1::Bayhub - SNMP Interface to Bay / Nortel Hubs

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    #Let SNMP::Info determine the correct subclass for you.

    my $bayhub = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $bayhub->class();
    print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Bay hub device through SNMP.  Also provides device MAC to port mapping through
the proprietary MIB. 

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

my $bayhub = new SNMP::Info::Layer1::Bayhub(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=item SNMP::Info::NortelStack

=item SNMP::Info::SONMP

=back

=head2 Required MIBs

=over

=item F<S5-ETHERNET-COMMON-MIB>

=item F<S5-COMMON-STATS-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info::Layer2/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::NortelStack/"Required MIBs"> for its MIB requirements.

See L<SNMP::Info::SONMP/"Required MIBs"> for its MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $bayhub->vendor()

Returns 'nortel'

=item $bayhub->os()

Returns 'bay_hub'

=item $bayhub->model()

Cross references $bayhub->id() to the F<SYNOPTICS-MIB> and returns
the results.

Removes either Baystack Hub, 5000, or 5005 depending on the model.

=back

=head2 Overrides

=over

=item $bayhub->layers()

Returns 00000011.  Class emulates Layer 2 functionality through proprietary
MIBs.

=item  $bayhub->index_factor()

Required by SNMP::Info::SONMP.  Number representing the number of ports
reserved per slot within the device MIB.  Returns 256.

=item $bayhub->slot_offset()

Required by SNMP::Info::SONMP.  Offset if slot numbering does not
start at 0.  Returns 0.

=back

=head2 Globals imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::NortelStack

See L<SNMP::Info::NortelStack/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::SONMP

See L<SNMP::Info::SONMP/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $bayhub->i_index()

Returns reference to map of IIDs to Interface index. 

Since hubs do not support C<ifIndex>, the interface index is created using the
formula (board * 256 + port).

=item $bayhub->interfaces()

Returns reference to map of IIDs to physical ports. 

=item $bayhub->i_duplex()

Returns half, hubs do not support full duplex. 

=item $bayhub->i_duplex_admin()

Returns half, hubs do not support full duplex.

=item $bayhub->i_speed()

Returns interface speed.

=item $bayhub->i_up()

Returns (C<s5EnPortLinkStatus>) for each port.  Translates on/off to up/down.

=item $bayhub->i_up_admin()

Returns (C<s5EnPortPartStatus>) for each port.

=item $bayhub->set_i_up_admin(state, ifIndex)

Sets port state, must be supplied with state and port C<ifIndex>

State choices are 'up' or 'down'

Example:
  my %if_map = reverse %{$bayhub->interfaces()};
  $bayhub->set_i_up_admin('down', $if_map{'1.1'}) 
      or die "Couldn't change port state. ",$bayhub->error(1);

=item $bayhub->bp_index()

Simulates bridge MIB by returning reference to a hash containing the index for
both the keys and values.

=item $bayhub->fw_port()

Returns reference to map of IIDs of the C<S5-COMMON-STATS-MIB::s5CmSNodeTable>
to the Interface index.

=item $bayhub->fw_mac()

(C<s5CmSNodeMacAddr>)

=back

=head2 Pseudo F<ENTITY-MIB> Information

These devices do not support F<ENTITY-MIB>.  These methods emulate Physical
Table methods using F<S5-CHASSIS-MIB>.  See
L<SNMP::Info::NortelStack/"TABLE METHODS"> for details.

=over

=item $bayhub->e_index() 

Returns ns_e_index().

=item $bayhub->e_class() 

Returns ns_e_class().

=item $bayhub->e_descr() 

Returns ns_e_descr().

=item $bayhub->e_name() 

Returns ns_e_name().

=item $bayhub->e_fwver() 

Returns ns_e_fwver().

=item $bayhub->e_hwver() 

Returns ns_e_hwver().

=item $bayhub->e_parent() 

Returns ns_e_parent().

=item $bayhub->e_pos() 

Returns ns_e_pos().

=item $bayhub->e_serial() 

Returns ns_e_serial().

=item $bayhub->e_swver() 

Returns ns_e_swver().

=item $bayhub->e_type() 

Returns ns_e_type().

=item $bayhub->e_vendor() 

Returns ns_e_vendor().

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::NortelStack

See L<SNMP::Info::NortelStack/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::SONMP

See L<SNMP::Info::SONMP/"TABLE METHODS"> for details.

=cut
