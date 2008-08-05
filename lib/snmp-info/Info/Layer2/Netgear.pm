# SNMP::Info::Layer2::Netgear
# $Id: Netgear.pm,v 1.7 2008/08/02 03:21:57 jeneric Exp $
#
# Copyright (c) 2008 Bill Fenner
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

package SNMP::Info::Layer2::Netgear;

use strict;
use Exporter;
use SNMP::Info::Layer2;

@SNMP::Info::Layer2::Netgear::ISA       = qw/SNMP::Info::Layer2 Exporter/;
@SNMP::Info::Layer2::Netgear::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( %SNMP::Info::Layer2::MIBS, );

%GLOBALS = ( %SNMP::Info::Layer2::GLOBALS, );

%FUNCS = ( %SNMP::Info::Layer2::FUNCS, );

%MUNGE = ( %SNMP::Info::Layer2::MUNGE, );

sub vendor {
    return 'netgear';
}

sub os {
    return 'netgear';
}

# Wish the OID-based method worked, but netgear scatters
# the sysObjectID values across all the device MIBs, and
# makes the device MIBs state secrets.
# They seem to set sysDescr to the model number, though,
# so we'll use that.
sub model {
    my $netgear = shift;
    return $netgear->description();
}

#
# This is model-dependent.  Some netgear brand devices don't implement
# the bridge MIB forwarding table, so we use the Q-BRIDGE-MIB forwarding
# table.  Fall back to the orig functions if the qb versions don't
# return anything.
sub fw_mac {
    my $netgear = shift;
    my $ret     = $netgear->qb_fw_mac();
    $ret = $netgear->orig_fw_mac() if ( !defined($ret) );
    return $ret;
}

sub fw_port {
    my $netgear = shift;
    my $ret     = $netgear->qb_fw_port();
    $ret = $netgear->orig_fw_port() if ( !defined($ret) );
    return $ret;
}

1;

__END__

=head1 NAME

SNMP::Info::Layer2::Netgear - SNMP Interface to Netgear switches

=head1 AUTHOR

Bill Fenner and Zoltan Erszenyi

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $netgear = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $netgear->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a 
Netgear device through SNMP. See inherited classes' documentation for 
inherited methods.

=head2 Inherited Classes

=over

=item SNMP::Info::Layer2

=back

=head2 Required MIBs

=over

=item Inherited Classes' MIBs

MIBs listed in L<SNMP::Info::Layer2/"Required MIBs"> and its inherited
classes.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=head2 Overrides

=over

=item $netgear->vendor()

Returns 'netgear'

=item $netgear->os()

Returns 'netgear' 

=item $netgear->model()

Returns description()

=back

=head2 Global Methods imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of
a reference to a hash.

=head2 Overrides

=over

=item $netgear->fw_mac()

Returns reference to hash of forwarding table MAC Addresses.

Some devices don't implement the C<BRIDGE-MIB> forwarding table, so we use
the C<Q-BRIDGE-MIB> forwarding table.  Fall back to the C<BRIDGE-MIB> if
C<Q-BRIDGE-MIB> doesn't return anything.

=item $netgear->fw_port()

Returns reference to hash of forwarding table entries port interface
identifier (iid)

Some devices don't implement the C<BRIDGE-MIB> forwarding table, so we use
the C<Q-BRIDGE-MIB> forwarding table.  Fall back to the C<BRIDGE-MIB> if
C<Q-BRIDGE-MIB> doesn't return anything.

=back

=head2 Table Methods imported from SNMP::Info::Layer2

See documentation in L<SNMP::Info::Layer2/"TABLE METHODS"> for details.

=cut
