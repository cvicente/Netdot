# SNMP::Info::Layer3::Sun
# $Id: Sun.pm,v 1.10 2008/08/02 03:21:47 jeneric Exp $
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

package SNMP::Info::Layer3::Sun;

use strict;
use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::Sun::ISA       = qw/SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Sun::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( %SNMP::Info::Layer3::MIBS, );

%GLOBALS = (
    %SNMP::Info::Layer3::GLOBALS,
    'sun_hostid' => '.1.3.6.1.4.1.42.3.1.2.0',
    'motd'       => '.1.3.6.1.4.1.42.3.1.3.0',
);

%FUNCS = ( %SNMP::Info::Layer3::FUNCS, );

%MUNGE = ( %SNMP::Info::Layer3::MUNGE, );

sub vendor {
    return 'sun';
}

sub os {
    return 'sun';
}

sub os_ver {
    my $sun   = shift;
    my $descr = $sun->motd();
    return unless defined $descr;

    if ( $descr =~ m/SunOS (\S+)/ ) {
        return $1;
    }
    return;
}

sub model {
    return 'Solaris Router';
}

sub serial {
    my $sun = shift;
    my $serial = unpack( "H*", $sun->sun_hostid() );
    return $serial;
}

sub i_ignore {
    my $l3      = shift;
    my $partial = shift;

    my $interfaces = $l3->interfaces($partial) || {};

    my %i_ignore;
    foreach my $if ( keys %$interfaces ) {

        # lo0
        if ( $interfaces->{$if} =~ /\blo0\b/i ) {
            $i_ignore{$if}++;
        }
    }
    return \%i_ignore;
}

1;

__END__

=head1 NAME

SNMP::Info::Layer3::Sun - SNMP Interface to L3 Sun Solaris

=head1 AUTHOR

begemot

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $sun = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'mysunrouter',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $sun->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Generic Sun Routers running SunOS

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

=over

=item $sun->vendor()

Returns 'sun'

=item $sun->os()

Returns 'sun'

=item $sun->os_ver()

Returns the software version extracted from message of the day.

=item $sun->model()

Returns 'Solaris Router'

=item $sun->serial()

Returns serial number

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $sun->i_ignore()

Returns reference to hash.  Increments value of IID if port is to be ignored.

Ignores loopback

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
