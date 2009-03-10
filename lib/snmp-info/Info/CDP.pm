# SNMP::Info::CDP
# $Id: CDP.pm,v 1.27 2008/08/02 03:21:25 jeneric Exp $
#
# Changes since Version 0.7 Copyright (c) 2004 Max Baker
# All rights reserved.
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

package SNMP::Info::CDP;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::CDP::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::CDP::EXPORT_OK = qw//;

use vars qw/$VERSION $DEBUG %FUNCS %GLOBALS %MIBS %MUNGE $INIT/;

$VERSION = '2.00';

# Five data structures required by SNMP::Info
%MIBS = ( 'CISCO-CDP-MIB' => 'cdpGlobalRun' );

# Notice we dont inherit the default GLOBALS and FUNCS
# only the default MUNGE.
%GLOBALS = (
    'cdp_run'      => 'cdpGlobalRun',
    'cdp_interval' => 'cdpGlobalMessageInterval',
    'cdp_holdtime' => 'cdpGlobalHoldTime',
    'cdp_id'       => 'cdpGlobalDeviceId',
);

%FUNCS = (
    'c_index'        => 'cdpCacheIfIndex',
    'c_proto'        => 'cdpCacheAddressType',
    'c_addr'         => 'cdpCacheAddress',
    'c_ver'          => 'cdpCacheVersion',
    'c_id'           => 'cdpCacheDeviceId',
    'c_port'         => 'cdpCacheDevicePort',
    'c_platform'     => 'cdpCachePlatform',
    'c_capabilities' => 'cdpCacheCapabilities',
    'c_domain'       => 'cdpCacheVTPMgmtDomain',
    'c_vlan'         => 'cdpCacheNativeVLAN',
    'c_duplex'       => 'cdpCacheDuplex',
    'c_power'        => 'cdpCachePowerConsumption',
);

%MUNGE = (
    'c_capabilities' => \&SNMP::Info::munge_caps,
    'c_platform'     => \&SNMP::Info::munge_null,
    'c_domain'       => \&SNMP::Info::munge_null,
    'c_port'         => \&SNMP::Info::munge_null,
    'c_id'           => \&SNMP::Info::munge_null,
    'c_ver'          => \&SNMP::Info::munge_null,
    'c_ip'           => \&SNMP::Info::munge_ip,
    'c_power'        => \&munge_power,

);

sub munge_power {
    my $power = shift;
    my $decimal = substr( $power, -3 );
    $power =~ s/$decimal$/\.$decimal/;
    return $power;
}

sub hasCDP {
    my $cdp = shift;

    my $ver = $cdp->{_version};

    # SNMP v1 clients dont have the globals
    if ( defined $ver and $ver == 1 ) {
        my $c_ip = $cdp->c_ip();

        # See if anything in cdp cache, if so we have cdp
        return 1 if ( defined $c_ip and scalar( keys %$c_ip ) );
        return;
    }

    return $cdp->cdp_run();
}

sub c_if {
    my $cdp = shift;

    # See if by some miracle Cisco implemented the cdpCacheIfIndex entry
    my $c_index = $cdp->c_index();
    return $c_index if defined $c_index;

    # Nope, didn't think so. Now we fake it.
    my $c_ip = $cdp->c_ip();
    unless ( defined $c_ip ) {
        $cdp->error_throw(
            "SNMP::Info::CDP:c_if() - Device doesn't have cdp_ip() data.  Can't fake cdp_index()"
        );
        return;
    }

    my %c_if;
    foreach my $key ( keys %$c_ip ) {
        next unless defined $key;
        my $iid = $key;

        # Truncate .1 from cdp cache entry
        $iid =~ s/\.\d+$//;
        $c_if{$key} = $iid;
    }

    return \%c_if;
}

sub c_ip {
    my $cdp     = shift;
    my $partial = shift;

    my $c_addr  = $cdp->c_addr($partial)  || {};
    my $c_proto = $cdp->c_proto($partial) || {};

    my %c_ip;
    foreach my $key ( keys %$c_addr ) {
        my $addr  = $c_addr->{$key};
        my $proto = $c_proto->{$key};
        next unless defined $addr;
        next if ( defined $proto and $proto ne 'ip' );

        my $ip = join( '.', unpack( 'C4', $addr ) );
        $c_ip{$key} = $ip;
    }
    return \%c_ip;
}

1;
__END__

=head1 NAME

SNMP::Info::CDP - SNMP Interface to Cisco Discovery Protocol (CDP) using SNMP

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 my $cdp = new SNMP::Info ( 
                             AutoSpecify => 1,
                             Debug       => 1,
                             DestHost    => 'router', 
                             Community   => 'public',
                             Version     => 2
                           );

 my $class = $cdp->class();
 print " Using device sub class : $class\n";

 $hascdp   = $cdp->hasCDP() ? 'yes' : 'no';

 # Print out a map of device ports with CDP neighbors:
 my $interfaces = $cdp->interfaces();
 my $c_if       = $cdp->c_if();
 my $c_ip       = $cdp->c_ip();
 my $c_port     = $cdp->c_port();

 foreach my $cdp_key (keys %$c_ip){
    my $iid           = $c_if->{$cdp_key};
    my $port          = $interfaces->{$iid};
    my $neighbor      = $c_ip->{$cdp_key};
    my $neighbor_port = $c_port->{$cdp_key};
    print "Port : $port connected to $neighbor / $neighbor_port\n";
 }

=head1 DESCRIPTION

SNMP::Info::CDP is a subclass of SNMP::Info that provides an object oriented 
interface to CDP information through SNMP.

CDP is a Layer 2 protocol that supplies topology information of devices that
also speak CDP, mostly switches and routers.  CDP is implemented in Cisco and
some HP devices.

Create or use a device subclass that inherits this class.  Do not use
directly.

Each device implements a subset of the global and cache entries. 
Check the return value to see if that data is held by the device.

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item F<CISCO-CDP-MIB>

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBAL METHODS

These are methods that return scalar values from SNMP

=over

=item  $cdp->hasCDP()

Is CDP is active in this device?  

Accounts for SNMP version 1 devices which may have CDP but not cdp_run()

=item $cdp->cdp_run()

Is CDP enabled on this device?  Note that a lot of Cisco devices that
implement CDP don't implement this value. @#%$!

(C<cdpGlobalRun>)

=item $cdp->cdp_interval()

Interval in seconds at which CDP messages are generated.

(C<cdpGlobalMessageInterval>)

=item $cdp->cdp_holdtime()

Time in seconds that CDP messages are kept. 

(C<cdpGlobalHoldTime>)

=item  $cdp->cdp_id() 

Returns CDP device ID.  

This is the device id broadcast via CDP to other devices, and is what is
retrieved from remote devices with $cdp->id().

(C<cdpGlobalDeviceId>)

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 CDP CACHE ENTRIES

=over

=item $cdp->c_capabilities()

Returns Device Functional Capabilities.  Results are munged into an ascii
binary string, 7 digits long, MSB.  Each digit represents a bit from the
table below.

From L<http://www.cisco.com/univercd/cc/td/doc/product/lan/trsrb/frames.htm#18843>:

(Bit) - Description

=over

=item (0x40) - Provides level 1 functionality.

=item (0x20) - The bridge or switch does not forward IGMP Report packets on
non router ports.

=item (0x10) - Sends and receives packets for at least one network layer
protocol. If the device is routing the protocol, this bit should not be set.

=item (0x08) - Performs level 2 switching. The difference between this bit
and bit 0x02 is that a switch does not run the Spanning-Tree Protocol. This
device is assumed to be deployed in a physical loop-free topology.

=item (0x04) - Performs level 2 source-route bridging. A source-route bridge
would set both this bit and bit 0x02.

=item (0x02) - Performs level 2 transparent bridging.

=item (0x01) - Performs level 3 routing for at least one network layer
protocol.

=back

Thanks to Martin Lorensen C<martin -at- lorensen.dk> for a pointer to this
information.

(C<cdpCacheCapabilities>)

=item $cdp->c_domain()

Returns remote VTP Management Domain as defined in
C<CISCO-VTP-MIB::managementDomainName>

(C<cdpCacheVTPMgmtDomain>)

=item $cdp->c_duplex() 

Returns the port duplex status from remote devices.

(C<cdpCacheDuplex>)

=item $cdp->c_id()

Returns remote device id string

(C<cdpCacheDeviceId>)

=item $cdp->c_if()

Returns the mapping to the SNMP Interface Table.

Note that a lot devices don't implement $cdp->c_index(),  So if it isn't
around, we fake it. 

In order to map the cdp table entry back to the interfaces() entry, we
truncate the last number off of it :

  # it exists, yay.
  my $c_index     = $device->c_index();
  return $c_index if defined $c_index;

  # if not, let's fake it
  my $c_ip       = $device->c_ip();
    
  my %c_if
  foreach my $key (keys %$c_ip){
      $iid = $key;
      ## Truncate off .1 from cdp response
      $iid =~ s/\.\d+$//;
      $c_if{$key} = $iid;
  }
 
  return \%c_if;


=item $cdp->c_index()

Returns the mapping to the SNMP2 Interface table for CDP Cache Entries. 

Most devices don't implement this, so you probably want to use $cdp->c_if()
instead.

See c_if() entry.

(C<cdpCacheIfIndex>)

=item  $cdp->c_ip()

If $cdp->c_proto() is supported, returns remote IPV4 address only.  Otherwise
it will return all addresses.

(C<cdpCacheAddress>)

=item  $cdp->c_addr()

Returns remote address

(C<cdpCacheAddress>)

=item $cdp->c_platform() 

Returns remote platform id 

(C<cdpCachePlatform>)

=item $cdp->c_port()

Returns remote port ID

(C<cdpDevicePort>)

=item  $cdp->c_proto()

Returns remote address type received.  Usually IP.

(C<cdpCacheAddressType>)

=item $cdp->c_ver() 

Returns remote hardware version

(C<cdpCacheVersion>)

=item $cdp->c_vlan()

Returns the remote interface native VLAN.

(C<cdpCacheNativeVLAN>)

=item $cdp->c_power()

Returns the amount of power consumed by remote device in milliwatts munged
for decimal placement.

(C<cdpCachePowerConsumption>)

=back

=head1 Data Munging Callback Subroutines

=over

=item $cdp->munge_power()

Inserts a decimal at the proper location.

=back

=cut
