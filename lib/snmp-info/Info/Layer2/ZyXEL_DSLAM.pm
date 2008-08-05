# SNMP::Info::Layer2::ZyXEL_DSLAM
# $Id: ZyXEL_DSLAM.pm,v 1.16 2008/08/02 03:21:57 jeneric Exp $
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

package SNMP::Info::Layer2::ZyXEL_DSLAM;

use strict;
use Exporter;
use SNMP::Info::Layer2;

@SNMP::Info::Layer2::ZyXEL_DSLAM::ISA       = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::ZyXEL_DSLAM::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

# Set for No CDP
%GLOBALS = ( %SNMP::Info::Layer2::GLOBALS );

%FUNCS = (
    %SNMP::Info::Layer2::FUNCS,
    'ip_adresses'   => 'ipAdEntAddr',
    'i_name'        => 'ifDescr',
    'i_description' => 'adslLineConfProfile',
);

%MIBS
    = ( %SNMP::Info::Layer2::MIBS, 'ADSL-LINE-MIB' => 'adslLineConfProfile' );

%MUNGE = ( %SNMP::Info::Layer2::MUNGE );

sub layers {
    my $zyxel  = shift;
    my $layers = $zyxel->layers();
    return $layers if defined $layers;

    # If these don't claim to have any layers, so we'll give them 1+2
    return '00000011';
}

sub vendor {
    return 'zyxel';
}

sub os {
    return 'zyxel';
}

sub os_ver {
    my $zyxel = shift;
    my $descr = $zyxel->description();

    if ( $descr =~ m/version (\S+) / ) {
        return $1;
    }
    return;
}

sub model {
    my $zyxel = shift;

    my $desc = $zyxel->description();

    if ( $desc =~ /8-port ADSL Module\(Annex A\)/ ) {
        return "AAM1008-61";
    }
    elsif ( $desc =~ /8-port ADSL Module\(Annex B\)/ ) {
        return "AAM1008-63";
    }
    return;
}

sub ip {
    my $zyxel   = shift;
    my $ip_hash = $zyxel->ip_addresses();
    my $found_ip;

    foreach my $ip ( keys %{$ip_hash} ) {
        $found_ip = $ip
            if ( defined $ip
            and $ip =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ );
    }
    return $found_ip;
}
1;
__END__

=head1 NAME

SNMP::Info::Layer2::ZyXEL_DSLAM - SNMP Interface to ZyXEL DSLAM

=head1 AUTHOR

Dmitry Sergienko (C<dmitry@trifle.net>)

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $zyxel = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myhub',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $l2->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
ZyXEL device through SNMP. See inherited classes' documentation for 
inherited methods.

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item F<ADSL-LINE-MIB>

=item Inherited Classes

MIBs listed in L<SNMP::Info::Layer2/"Required MIBs"> and their inherited
classes.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=head2 Overrides

=over

=item $zyxel->vendor()

Returns 'ZyXEL' :)

=item $zyxel->os()

Returns 'ZyXEL' 

=item $zyxel->os_ver()

Culls Version from description()

=item $zyxel->ip()

Returns IP Address of DSLAM.

(C<ipAdEntAddr>)

=item $zyxel->model()

Tries to cull out model out of the description field.

=item $zyxel->layers()

Returns 00000011.

=back

=head2 Global Methods imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

=head2 Overrides

=over

=item $zyxel->i_name()

Returns reference to map of IIDs to port name (C<ifDescr>).

=item $zyxel->i_description()

Returns reference to map of IIDs to human-set port description (profile name).

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
