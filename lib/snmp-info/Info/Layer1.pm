# SNMP::Info::Layer1 - SNMP Interface to Layer1 Devices 
# Max Baker
#
# Copyright (c) 2004 Max Baker changes from version 0.8 and beyond.
#
# Copyright (c) 2002,2003 Regents of the University of California
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the 
#       names of its contributors may be used to endorse or promote products 
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Layer1;
$VERSION = '1.05';
# $Id: Layer1.pm,v 1.17 2007/06/13 02:48:23 jeneric Exp $

use strict;

use Exporter;
use SNMP::Info;

use vars qw/$VERSION %GLOBALS %MIBS %FUNCS %PORTSTAT %MUNGE/;

@SNMP::Info::Layer1::ISA = qw/SNMP::Info Exporter/;
@SNMP::Info::Layer1::EXPORT_OK = qw//;

%MIBS = ( %SNMP::Info::MIBS, 
          'SNMP-REPEATER-MIB' => 'rptrPortGroupIndex'
        );

%GLOBALS = (
            %SNMP::Info::GLOBALS,
            'ports_managed'  => 'ifNumber',
            'rptr_slots'     => 'rptrGroupCapacity',
            'slots'          => 'rptrGroupCapacity'
            );

%FUNCS   = (
            %SNMP::Info::FUNCS,
            'rptr_ports'    => 'rptrGroupPortCapacity',
            'rptr_port'     => 'rptrPortIndex',
            'rptr_slot'     => 'rptrPortGroupIndex',
            'rptr_up_admin' => 'rptrPortAdminStatus',
            'rptr_up'       => 'rptrPortOperStatus',
            'rptr_last_src' => 'rptrAddrTrackNewLastSrcAddress',
           );

%MUNGE = (
            # Inherit all the built in munging
            %SNMP::Info::MUNGE,
            'rptr_last_src'=> \&SNMP::Info::munge_mac,
         );

# Method OverRides

# assuming managed ports aren't in repeater ports?
sub ports {
    my $l1 = shift;

    my $ports         = $l1->ports_managed();
    my $rptr_ports    = $l1->rptr_ports();

    foreach my $group (keys %$rptr_ports){
        $ports += $rptr_ports->{$group}; 
    }

    return $ports;
}

# $l1->model() - Looks at sysObjectID which gives the oid of the system
#       name, contained in a propriatry MIB. 
sub model {
    my $l1 = shift;
    my $id = $l1->id();
    my $model = &SNMP::translateObj($id);
    
    # HP
    $model =~ s/^hpswitch//i;

    # Cisco
    $model =~ s/sysid$//i;

    return $model;
}

sub vendor {
    my $l1 = shift;
    my $descr = $l1->description();

    return 'hp' if ($descr =~ /hp/i);
    return 'cisco' if ($descr =~ /(catalyst|cisco|ios)/i);
    return 'allied' if ($descr =~ /allied/i);
    return 'asante' if ($descr =~ /asante/i);

}

# By Default we'll use the description field
sub interfaces {
    my $l1 = shift;
    my $partial = shift;

    my $interfaces = $l1->i_index($partial) || {};
    my $rptr_port  = $l1->rptr_port($partial) || {};

    foreach my $port (keys %$rptr_port){
        $interfaces->{$port} = $port;
    }
    return $interfaces;
}

sub i_up_admin {
    my $l1 = shift;
    my $partial = shift;

    my $i_up_admin = $l1->SUPER::i_up_admin($partial) || {};
    my $rptr_up_admin = $l1->rptr_up_admin($partial) || {};

    foreach my $key (keys %$rptr_up_admin){
        my $up = $rptr_up_admin->{$key};
        $i_up_admin->{$key} = 'up' if $up =~ /enabled/; 
        $i_up_admin->{$key} = 'down' if $up =~ /disabled/; 
    }

    return $i_up_admin;
}

sub i_up {
    my $l1 = shift;
    my $partial = shift;

    my $i_up = $l1->SUPER::i_up($partial) || {};
    my $rptr_up = $l1->rptr_up($partial) || {};

    foreach my $key (keys %$rptr_up){
        my $up = $rptr_up->{$key};
        $i_up->{$key} = 'up' if $up =~ /operational/; 
    }

    return $i_up;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer1 - SNMP Interface to network devices serving Layer1 only.

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $l1 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $l1->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

 # Let's get some basic Port information
 my $interfaces = $l1->interfaces();
 my $i_up       = $l1->i_up();
 my $i_speed    = $l1->i_speed();

 foreach my $iid (keys %$interfaces) {
    my $port  = $interfaces->{$iid};
    my $up    = $i_up->{$iid};
    my $speed = $i_speed->{$iid}
    print "Port $port is $up. Port runs at $speed.\n";
 }

=head1 DESCRIPTION

This class is usually used as a superclass for more specific device classes
listed under SNMP::Info::Layer1::*   Please read all docs under SNMP::Info
first.

Provides abstraction to the configuration information obtainable from a 
Layer1 device through SNMP.  Information is stored in a number of MIBs.

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $l1 = new SNMP::Info::Layer1(...);

=head2 Inherited Classes 

=over

=item SNMP::Info

=back

=head2 Required MIBs 

=over

=item SNMP-REPEATER-MIB

=back

MIBs required for L<SNMP::Info/"Required MIBs">

See L<SNMP::Info/"Required MIBs"> for its MIB requirements.

SNMP-REPEATER-MIB needs to be extracted from
ftp://ftp.cisco.com/pub/mibs/v1/v1.tar.gz

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $l1->ports_managed()

Gets the number of ports under the interface mib 

(B<ifNumber>)

=back

=head2 Overrides

=over

=item $l1->vendor()

Trys to discover the vendor from $l1->model() and $l1->vendor()

=item $l1->ports()

Adds the values from rptr_ports() and ports_managed()

=item $l1->slots()

Number of 'groups' in the Repeater MIB

(B<rptrGroupCapacity>)

=back

=head2 Global Methods imported from SNMP::Info

See documentation in L<SNMP::Info/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $l1->interfaces()

=item $l1->i_up()

=item $l1->i_up_admin()

=back

=head2 Repeater MIB

=over

=item $l1->rptr_ports()

Number of ports in each group.

(B<rptrGroupPortCapacity>)

=item $l1->rptr_port()

Port number in Group

(B<rptrPortIndex>)

=item $l1->rptr_slot()

Group (slot) Number for given port.

(B<rptrPortGroupIndex>)

=item $l1->rptr_up_admin()

(B<rptrPortAdminStatus>)

=item $l1->rptr_up()

(B<rptrPortOperStatus>)

=item $l1->rptr_last_src()

(B<rptrAddrTrackNewLastSrcAddress>)

=back

=head2 Table Methods imported from SNMP::Info

See documentation in L<SNMP::Info/"TABLE METHODS"> for details.

=cut
