# SNMP::Info::Layer3::Timetra
# $Id: Timetra.pm,v 1.3 2008/08/02 03:21:47 jeneric Exp $
#
# Copyright (c) 2008 Bill Fenner
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

package SNMP::Info::Layer3::Timetra;

use strict;

use Exporter;
use SNMP::Info::Layer3;

@SNMP::Info::Layer3::Timetra::ISA = qw/SNMP::Info::Layer3
    Exporter/;
@SNMP::Info::Layer3::Timetra::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( %SNMP::Info::Layer3::MIBS, 'TIMETRA-GLOBAL-MIB' => 'timetraReg', );

%GLOBALS = ( %SNMP::Info::Layer3::GLOBALS, );

%FUNCS = ( %SNMP::Info::Layer3::FUNCS, );

%MUNGE = ( %SNMP::Info::Layer3::MUNGE, );

sub model {
    my $timetra = shift;
    my $id      = $timetra->id();
    my $model   = &SNMP::translateObj($id);

    return $id unless defined $model;

    $model =~ s/^tmnxModel//;

    return $model;
}

sub os {
    return 'TiMOS';
}

sub vendor {
    return 'alcatel-lucent';
}

sub os_ver {
    my $timetra = shift;

    my $descr = $timetra->description();
    if ( $descr =~ m/^TiMOS-(\S+)/ ) {
        return $1;
    }

    # No clue what this will try but hey
    return $timetra->SUPER::os_ver();
}

# The interface description contains the SFP type, so
# to avoid losing historical information through a configuration change
# we use interface name instead.
sub interfaces {
    my $alu     = shift;
    my $partial = shift;

    return $alu->orig_i_name($partial);
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::Timetra - SNMP Interface to Alcatel-Lucent SR

=head1 AUTHOR

Bill Fenner

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $alu = new SNMP::Info(
                        AutoSpecify => 1,
                        Debug       => 1,
                        # These arguments are passed directly to SNMP::Session
                        DestHost    => 'myswitch',
                        Community   => 'public',
                        Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $alu->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Subclass for Alcatel-Lucent Service Routers

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<TIMETRA-GLOBAL-MIB>

=item Inherited Classes' MIBs

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $alu->vendor()

Returns 'alcatel-lucent'

=item $alu->os()

Returns 'TiMOS'

=item $alu->os_ver()

Grabs the version string from C<sysDescr>.

=item $alu->model()

Tries to reference $alu->id() to one of the product MIBs listed above

Removes 'tmnxModel' from the name for readability.

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $alu->interfaces()

Returns C<ifName>, since the default Layer3 C<ifDescr> varies based
upon the transceiver inserted.

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
