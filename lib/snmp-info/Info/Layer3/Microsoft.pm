# SNMP::Info::Layer3::Microsoft
# $Id: Microsoft.pm,v 1.7 2008/08/02 03:21:47 jeneric Exp $
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

package SNMP::Info::Layer3::Microsoft;

use strict;
use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::Microsoft::ISA       = qw/SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Microsoft::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( %SNMP::Info::Layer3::MIBS, );

%GLOBALS = ( %SNMP::Info::Layer3::GLOBALS, );

%FUNCS = ( %SNMP::Info::Layer3::FUNCS, );

%MUNGE = ( %SNMP::Info::Layer3::MUNGE, );

sub vendor {
    return 'microsoft';
}

sub os {
    return 'windows';
}

sub os_ver {
    return '';
}

sub model {
    return 'Windows Router';
}

sub serial {
    return '';
}

# $l3->interfaces() - Map the Interfaces to their physical names
# Add interface number to interface name because if MS Win
# have identical interface cards ("HP NC7782 Gigabit Server Adapter"
# for example), than MS Win return identical ifDescr
sub interfaces {
    my $l3      = shift;
    my $partial = shift;

    my $interfaces   = $l3->i_index($partial);
    my $descriptions = $l3->i_description($partial);

    my %interfaces = ();
    foreach my $iid ( keys %$interfaces ) {
        my $desc = $descriptions->{$iid};
        next unless defined $desc;

        $interfaces{$iid} = sprintf( "(%U) %s", $iid, $desc );
    }

    return \%interfaces;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::Microsoft - SNMP Interface to L3 Microsoft Windows router

=head1 AUTHOR

begemot

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $router = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myrouter',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $router->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Generic Microsoft Routers running Microsoft Windows OS

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=head2 Overrides

=over

=item $router->vendor()

Returns C<'microsoft'>

=item $router->os()

Returns C<'windows'>

=item $router->os_ver()

Returns ''

=item $router->model()

Returns C<'Windows Router'>

=item $router->serial()

Returns ''

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $router->interfaces()

Map the Interfaces to their physical names.  Adds interface number to
interface name because identical interface cards return identical C<ifDescr>.

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
