# SNMP::Info::Layer3::C3550
# $Id: C3550.pm,v 1.33 2009/06/11 21:49:37 maxbaker Exp $
#
# Copyright (c) 2008-2009 Max Baker changes from version 0.8 and beyond.
# Copyright (c) 2004 Regents of the University of California
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

package SNMP::Info::Layer3::C3550;

use strict;
use Exporter;
use SNMP::Info::CiscoVTP;
use SNMP::Info::CiscoStack;
use SNMP::Info::CDP;
use SNMP::Info::CiscoConfig;
use SNMP::Info::CiscoStats;
use SNMP::Info::CiscoImage;
use SNMP::Info::CiscoPortSecurity;
use SNMP::Info::CiscoPower;
use SNMP::Info::Layer3;
use SNMP::Info::CiscoStpExtensions;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

# NOTE : Top-most items gets precedence for @ISA
@SNMP::Info::Layer3::C3550::ISA = qw/
    SNMP::Info::CiscoVTP
    SNMP::Info::CiscoStpExtensions
    SNMP::Info::CiscoStack
    SNMP::Info::CDP
    SNMP::Info::CiscoStats
    SNMP::Info::CiscoImage
    SNMP::Info::CiscoPortSecurity
    SNMP::Info::CiscoConfig
    SNMP::Info::CiscoPower
    SNMP::Info::Layer3
    Exporter/;

@SNMP::Info::Layer3::C3550::EXPORT_OK = qw//;

$VERSION = '2.01';

# NOTE: Order creates precedence
#       Example: v_name exists in Bridge.pm and CiscoVTP.pm
#       Bridge is called from Layer3 and CiscoStpExtensions
#       So we want CiscoVTP to come last to get the right one.
# The @ISA order should match these orders.

%MIBS = (
    %SNMP::Info::Layer3::MIBS,             %SNMP::Info::CiscoPower::MIBS,
    %SNMP::Info::CiscoConfig::MIBS,        %SNMP::Info::CiscoPortSecurity::MIBS,
    %SNMP::Info::CiscoImage::MIBS,         %SNMP::Info::CiscoStats::MIBS,
    %SNMP::Info::CDP::MIBS,                %SNMP::Info::CiscoStack::MIBS,
    %SNMP::Info::CiscoStpExtensions::MIBS, %SNMP::Info::CiscoVTP::MIBS,
);


%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    %SNMP::Info::CiscoPower::GLOBALS,
    %SNMP::Info::CiscoConfig::GLOBALS,
    %SNMP::Info::CiscoPortSecurity::GLOBALS,
    %SNMP::Info::CiscoImage::GLOBALS,
    %SNMP::Info::CiscoStats::GLOBALS,
    %SNMP::Info::CDP::GLOBALS,
    %SNMP::Info::CiscoStack::GLOBALS,
    %SNMP::Info::CiscoStpExtensions::GLOBALS,
    %SNMP::Info::CiscoVTP::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::Layer3::FUNCS,             %SNMP::Info::CiscoPower::FUNCS,
    %SNMP::Info::CiscoConfig::FUNCS,        %SNMP::Info::CiscoPortSecurity::FUNCS,
    %SNMP::Info::CiscoImage::FUNCS,         %SNMP::Info::CiscoStats::FUNCS,
    %SNMP::Info::CDP::FUNCS,                %SNMP::Info::CiscoStack::FUNCS,
    %SNMP::Info::CiscoStpExtensions::FUNCS, %SNMP::Info::CiscoVTP::FUNCS,    
);

%MUNGE = (
    %SNMP::Info::Layer3::MUNGE,             %SNMP::Info::CiscoPower::MUNGE,
    %SNMP::Info::CiscoConfig::MUNGE,        %SNMP::Info::CiscoPortSecurity::MUNGE,
    %SNMP::Info::CiscoImage::MUNGE,         %SNMP::Info::CiscoStats::MUNGE,
    %SNMP::Info::CDP::MUNGE,                %SNMP::Info::CiscoStack::MUNGE,
    %SNMP::Info::CiscoStpExtensions::MUNGE, %SNMP::Info::CiscoVTP::MUNGE,    
);

sub vendor {
    return 'cisco';
}

sub model {
    my $c3550 = shift;
    my $id    = $c3550->id();
    my $model = &SNMP::translateObj($id) || $id;
    $model =~ s/^catalyst//;

    # turn 355048 into 3550-48
    if ( $model =~ /^(35\d\d)(\d\d(T|G)?)$/ ) {
        $model = "$1-$2";
    }
    return $model;
}

# Ports is encoded into the model number
sub ports {
    my $c3550 = shift;

    my $id    = $c3550->id();
    my $model = &SNMP::translateObj($id);
    if ( $model =~ /(12|24|48)(C|T|TS|G|TS-E|TS-S|T-E)?$/ ) {
        return $1;
    }

    my $ports = $c3550->orig_ports();
    return $ports;
}

#  Verions prior to 12.1(22)EA1a use the older CiscoStack method
#  Newer versions use the ETHERLIKE-MIB to report operational duplex.
#  See http://www.ciscosystems.com/en/US/products/hw/switches/ps646/prod_release_note09186a00802a08ee.html

sub i_duplex {
    my $c3550   = shift;
    my $partial = shift;

    my $el_duplex = $c3550->el_duplex($partial);

    # Newer software
    if ( defined $el_duplex and scalar( keys %$el_duplex ) ) {
        my %i_duplex;
        foreach my $el_port ( keys %$el_duplex ) {
            my $duplex = $el_duplex->{$el_port};
            next unless defined $duplex;

            $i_duplex{$el_port} = 'half' if $duplex =~ /half/i;
            $i_duplex{$el_port} = 'full' if $duplex =~ /full/i;
        }
        return \%i_duplex;
    }

    # Fall back to CiscoStack method
    else {
        return $c3550->SUPER::i_duplex($partial);
    }
}

# Software >= 12.1(22)EA1a uses portDuplex as admin setting

sub i_duplex_admin {
    my $c3550   = shift;
    my $partial = shift;

    my $el_duplex = $c3550->el_duplex($partial);

    # Newer software
    if ( defined $el_duplex and scalar( keys %$el_duplex ) ) {
        my $p_port   = $c3550->p_port()   || {};
        my $p_duplex = $c3550->p_duplex() || {};

        my $i_duplex_admin = {};
        foreach my $port ( keys %$p_duplex ) {
            my $iid = $p_port->{$port};
            next unless defined $iid;
            next if ( defined $partial and $iid !~ /^$partial$/ );

            $i_duplex_admin->{$iid} = $p_duplex->{$port};
        }
        return $i_duplex_admin;
    }

    # Fall back to CiscoStack method
    else {
        return $c3550->SUPER::i_duplex_admin($partial);
    }
}

sub set_i_duplex_admin {

    # map a textual duplex to an integer one the switch understands
    my %duplexes = qw/half 1 full 2 auto 4/;

    my $c3550 = shift;
    my ( $duplex, $iid ) = @_;

    my $el_duplex = $c3550->el_duplex($iid);

    # Auto duplex only supported on newer software
    if ( defined $el_duplex and scalar( keys %$el_duplex ) ) {
        my $p_port = $c3550->p_port() || {};
        my %reverse_p_port = reverse %$p_port;

        $duplex = lc($duplex);

        return 0 unless defined $duplexes{$duplex};

        $iid = $reverse_p_port{$iid};

        return $c3550->set_p_duplex( $duplexes{$duplex}, $iid );
    }
    else {
        return $c3550->SUPER::set_i_duplex_admin;
    }
}

sub cisco_comm_indexing {
    return 1;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::C3550 - SNMP Interface to Cisco Catalyst 3550 Layer 2/3
Switches running IOS

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $c3550 = new SNMP::Info(
                        AutoSpecify => 1,
                        Debug       => 1,
                        # These arguments are passed directly to SNMP::Session
                        DestHost    => 'myswitch',
                        Community   => 'public',
                        Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $c3550->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Abstraction subclass for Cisco Catalyst 3550 Layer 2/3 Switches.  

These devices run IOS but have some of the same characteristics as the
Catalyst WS-C family (5xxx,6xxx).  For example, forwarding tables are held in
VLANs, and extended interface information is gleaned from F<CISCO-SWITCH-MIB>.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $c3550 = new SNMP::Info::Layer3::C3550(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=item SNMP::Info::CiscoSTPExtensions

=item SNMP::Info::CiscoPower

=item SNMP::Info::CiscoPortSecurity

=item SNMP::Info::CiscoVTP

=item SNMP::Info::CiscoStack

=item SNMP::Info::CDP

=item SNMP::Info::CiscoStats

=item SNMP::Info::CiscoImage

=back

=head2 Required MIBs

=over

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoStpExtensions/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoPower/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoPortSecurity/"Required MIBs"> for its own MIB
requirements.

See L<SNMP::Info::CiscoVTP/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoStack/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoStats/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CiscoImage/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CDP/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $c3550->vendor()

Returns 'cisco'

=item $c3550->model()

Will take the translated model number and try to format it better.

 355048 -> 3550-48
 355012G -> 3550-12G

=item $c3550->ports()

Tries to cull the number of ports from the model number.

=item $c3550->cisco_comm_indexing()

Returns 1.  Use vlan indexing.

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoStpExtensions

See documentation in L<SNMP::Info::CiscoStpExtensions/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoPower

See documentation in L<SNMP::Info::CiscoPower/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoPortSecurity

See documentation in L<SNMP::Info::CiscoPortSecurity/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::CiscoVTP

See documentation in L<SNMP::Info::CiscoVTP/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::CiscoStack

See documentation in L<SNMP::Info::CiscoStack/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoStats

See documentation in L<SNMP::Info::CiscoStats/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::CiscoImage

See documentation in L<SNMP::Info::CiscoImage/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $c3550->i_duplex()

Returns reference to hash of iid to current link duplex setting.

Software version 12.1(22)EA1a or greater returns duplex based upon the
result of $c3550->el_duplex().  Otherwise it uses the result of
the call to CiscoStack::i_duplex().

See L<SNMP::Info::Etherlike> for el_duplex() method and
L<SNMP::Info::CiscoStack> for its i_duplex() method.

=item $c3550->i_duplex_admin()

Returns reference to hash of iid to administrative duplex setting.

Software version 12.1(22)EA1a or greater returns duplex based upon the
result of $c3550->p_duplex().  Otherwise it uses the result of
the call to CiscoStack::i_duplex().

See L<SNMP::Info::CiscoStack> for its i_duplex() and p_duplex() methods.

=item $c3550->set_i_duplex_admin(duplex, ifIndex)

Sets port duplex, must be supplied with duplex and port C<ifIndex>.

Speed choices are 'auto', 'half', 'full'.

Crosses $c3550->p_port() with $c3550->p_duplex() to utilize port C<ifIndex>.

    Example:
    my %if_map = reverse %{$c3550->interfaces()};
    $c3550->set_i_duplex_admin('auto', $if_map{'FastEthernet0/1'}) 
        or die "Couldn't change port duplex. ",$c3550->error(1);

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoStpExtensions

See documentation in L<SNMP::Info::CiscoStpExtensions/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoPower

See documentation in L<SNMP::Info::CiscoPower/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoPortSecurity

See documentation in L<SNMP::Info::CiscoPortSecurity/"TABLE METHODS"> for
details.

=head2 Table Methods imported from SNMP::Info::CiscoVTP

See documentation in L<SNMP::Info::CiscoVTP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoStack

See documentation in L<SNMP::Info::CiscoStack/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoStats

See documentation in L<SNMP::Info::CiscoStats/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CiscoImage

See documentation in L<SNMP::Info::CiscoImage/"TABLE METHODS"> for details.

=cut
