# SNMP::Info::Layer2::Airespace
# $Id: Airespace.pm,v 1.6 2008/08/02 03:21:57 jeneric Exp $
#
# Copyright (c) 2008 Eric Miller
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

package SNMP::Info::Layer2::Airespace;

use strict;
use Exporter;
use SNMP::Info::Bridge;
use SNMP::Info::CDP;
use SNMP::Info::Airespace;

@SNMP::Info::Layer2::Airespace::ISA
    = qw/SNMP::Info::Airespace SNMP::Info::CDP SNMP::Info::Bridge Exporter/;
@SNMP::Info::Layer2::Airespace::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::MIBS,      %SNMP::Info::Bridge::MIBS,
    %SNMP::Info::CDP::MIBS, %SNMP::Info::Airespace::MIBS,
);

%GLOBALS = (
    %SNMP::Info::GLOBALS,      %SNMP::Info::Bridge::GLOBALS,
    %SNMP::Info::CDP::GLOBALS, %SNMP::Info::Airespace::GLOBALS,
);

%FUNCS = (
    %SNMP::Info::FUNCS,      %SNMP::Info::Bridge::FUNCS,
    %SNMP::Info::CDP::FUNCS, %SNMP::Info::Airespace::FUNCS,
);

%MUNGE = (
    %SNMP::Info::MUNGE,      %SNMP::Info::Bridge::MUNGE,
    %SNMP::Info::CDP::MUNGE, %SNMP::Info::Airespace::MUNGE,
);

sub os {
    return 'cisco';
}

sub vendor {
    return 'cisco';
}

sub model {
    my $airespace = shift;
    my $model     = $airespace->airespace_model();
    return unless defined $model;

    return $model;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer2::Airespace - SNMP Interface to Cisco (Airespace) Wireless
Controllers

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

    #Let SNMP::Info determine the correct subclass for you.

    my $airespace = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $airespace->class();
    print " Using device sub class : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from 
Cisco (Airespace) Wireless Controllers through SNMP.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

my $airespace = new SNMP::Info::Layer2::Airespace(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Airespace

=item SNMP::Info::CDP

=item SNMP::Info::Bridge

=back

=head2 Required MIBs

=over

=item Inherited Classes' MIBs

See L<SNMP::Info::Airespace/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::CDP/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::Bridge/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $airespace->vendor()

Returns 'cisco'

=item $airespace->os()

Returns 'cisco'

=item $airespace->model()

(C<agentInventoryMachineModel>)

=back

=head2 Global Methods imported from SNMP::Info::Airespace

See documentation in L<SNMP::Info::Airespace/"GLOBALS"> for details.

=head2 Global Methods imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item None

=back

=head2 Table Methods imported from SNMP::Info::Airespace

See documentation in L<SNMP::Info::Airespace/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::CDP

See documentation in L<SNMP::Info::CDP/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"TABLE METHODS"> for details.

=cut
