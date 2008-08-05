# SNMP::Info::Layer2 - SNMP Interface to Layer2 Devices
# $Id: Layer2.pm,v 1.33 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2008 Max Baker -- All changes from Version 0.7 on
#
# Copyright (c) 2002,2003 Regents of the University of California
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

package SNMP::Info::Layer2;

use strict;
use Exporter;
use SNMP::Info;
use SNMP::Info::Bridge;
use SNMP::Info::Entity;
use SNMP::Info::PowerEthernet;

@SNMP::Info::Layer2::ISA
    = qw/SNMP::Info SNMP::Info::Bridge SNMP::Info::Entity SNMP::Info::PowerEthernet Exporter/;
@SNMP::Info::Layer2::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %PORTSTAT %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::MIBS,         %SNMP::Info::Bridge::MIBS,
    %SNMP::Info::Entity::MIBS, %SNMP::Info::PowerEthernet::MIBS,
);

%GLOBALS = (
    %SNMP::Info::GLOBALS,
    %SNMP::Info::Bridge::GLOBALS,
    %SNMP::Info::Entity::GLOBALS,
    %SNMP::Info::PowerEthernet::GLOBALS,
    'serial1' =>
        '.1.3.6.1.4.1.9.3.6.3.0',    # OLD-CISCO-CHASSIS-MIB::chassisId.0
);

%FUNCS = (
    %SNMP::Info::FUNCS,         %SNMP::Info::Bridge::FUNCS,
    %SNMP::Info::Entity::FUNCS, %SNMP::Info::PowerEthernet::FUNCS,
);

%MUNGE = (

    # Inherit all the built in munging
    %SNMP::Info::MUNGE,
    %SNMP::Info::Bridge::MUNGE,
    %SNMP::Info::Entity::MUNGE,
    %SNMP::Info::PowerEthernet::MUNGE,
);

# Method OverRides

# $l2->model() - Looks at sysObjectID which gives the oid of the system
#       name, contained in a propriatry MIB.
sub model {
    my $l2    = shift;
    my $id    = $l2->id();
    my $model = &SNMP::translateObj($id) || $id || '';

    # HP
    $model =~ s/^hpswitch//i;

    # Cisco
    $model =~ s/sysid$//i;
    $model =~ s/^(cisco|catalyst)//i;
    $model =~ s/^cat//i;

    return $model;
}

sub vendor {
    my $l2    = shift;
    my $model = $l2->model();
    my $descr = $l2->description();

    if ( $model =~ /hp/i or $descr =~ /\bhp\b/i ) {
        return 'hp';
    }

    if ( $model =~ /catalyst/i or $descr =~ /(catalyst|cisco)/i ) {
        return 'cisco';
    }

}

sub serial {
    my $l2 = shift;

    my $serial1  = $l2->serial1();
    my $e_descr  = $l2->e_descr() || {};
    my $e_serial = $l2->e_serial() || {};

    my $serial2 = $e_serial->{1} || undef;
    my $chassis = $e_descr->{1}  || undef;

    # precedence
    #   serial2,chassis parse,serial1
    return $serial2 if ( defined $serial2 and $serial2 !~ /^\s*$/ );
    return $1
        if ( defined $chassis and $chassis =~ /serial#?:\s*([a-z0-9]+)/i );
    return $serial1 if ( defined $serial1 and $serial1 !~ /^\s*$/ );

    return;
}

sub i_ignore {
    my $l2      = shift;
    my $partial = shift;

    my $i_type = $l2->i_type($partial) || {};

    my %i_ignore = ();

    foreach my $if ( keys %$i_type ) {
        my $type = $i_type->{$if};
        $i_ignore{$if}++
            if $type =~ /(loopback|other|cpu)/i;
    }

    return \%i_ignore;
}

sub interfaces {
    my $l2      = shift;
    my $partial = shift;

    my $interfaces = $l2->i_index($partial)       || {};
    my $i_descr    = $l2->i_description($partial) || {};

    # Replace the Index with the ifDescr field.
    foreach my $iid ( keys %$i_descr ) {
        my $port = $i_descr->{$iid};
        next unless defined $port;
        $interfaces->{$iid} = $port;
    }
    return $interfaces;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer2 - SNMP Interface to network devices serving Layer2 only.

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $l2 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $l2->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

 # Let's get some basic Port information
 my $interfaces = $l2->interfaces();
 my $i_up       = $l2->i_up();
 my $i_speed    = $l2->i_speed();
 foreach my $iid (keys %$interfaces) {
    my $port  = $interfaces->{$iid};
    my $up    = $i_up->{$iid};
    my $speed = $i_speed->{$iid}
    print "Port $port is $up. Port runs at $speed.\n";
 }

=head1 DESCRIPTION

This class is usually used as a superclass for more specific device classes
listed under SNMP::Info::Layer2::*   Please read all docs under SNMP::Info
first.

Provides abstraction to the configuration information obtainable from a 
Layer2 device through SNMP.  Information is stored in a number of MIBs.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $l2 = new SNMP::Info::Layer2(...);

=head2 Inherited Classes

=over

=item SNMP::Info

=item SNMP::Info::Bridge

=item SNMP::Info::Entity

=back

=head2 Required MIBs

=over

=item Inherited Classes

MIBs required by the inherited classes listed above.

=back

MIBs can be found in netdisco-mibs package.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=head2 Overrides

=over

=item $l2->model()

Cross references $l2->id() with product IDs in the 
Cisco MIBs.

For HP devices, removes C<'hpswitch'> from the name

For Cisco devices, removes c<'sysid'> from the name

=item $l2->vendor()

Tries to discover the vendor from $l2->model() and $l2->description()

=item $l2->serial()

Returns serial number if available through SNMP

=back

=head2 Globals imported from SNMP::Info

See documentation in L<SNMP::Info/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Entity

See documentation in L<SNMP::Info::Entity/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $l2->interfaces()

Creates a map between the interface identifier (iid) and the physical port
name.

Defaults to C<ifDescr> but checks and overrides with C<ifName>

=item $l2->i_ignore()

Returns reference to hash.  Increments value of IID if port is to be ignored.

Ignores ports with C<ifType> of loopback, propvirtual, other, and cpu

=back

=head2 Table Methods imported from SNMP::Info

See documentation in L<SNMP::Info/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Entity

See documentation in L<SNMP::Info::Entity/"TABLE METHODS"> for details.

=cut
