# SNMP::Info::LLDP
# $Id: LLDP.pm,v 1.8 2008/08/02 03:21:25 jeneric Exp $
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

package SNMP::Info::LLDP;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::LLDP::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::LLDP::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    'LLDP-MIB'          => 'lldpLocSysCapEnabled',
    'LLDP-EXT-DOT1-MIB' => 'lldpXdot1MIB',
    'LLDP-EXT-DOT3-MIB' => 'lldpXdot3MIB',
);

%GLOBALS = (
    'lldp_sysname' => 'lldpLocSysName',
    'lldp_sysdesc' => 'lldpLocSysDesc',
    'lldp_sys_cap' => 'lldpLocSysCapEnabled',
);

%FUNCS = (

    # LLDP-MIB::lldpLocManAddrTable
    'lldp_lman_addr' => 'lldpLocManAddrIfId',

    # LLDP-MIB::lldpRemTable
    'lldp_rem_id_type'  => 'lldpRemChassisIdSubtype',
    'lldp_rem_id'       => 'lldpRemChassisId',
    'lldp_rem_pid_type' => 'lldpRemPortIdSubtype',
    'lldp_rem_pid'      => 'lldpRemPortId',
    'lldp_rem_desc'     => 'lldpRemPortDesc',
    'lldp_rem_sysname'  => 'lldpRemSysName',
    'lldp_rem_sysdesc'  => 'lldpRemSysDesc',
    'lldp_rem_sys_cap'  => 'lldpRemSysCapEnabled',

    # LLDP-MIB::lldpRemManAddrTable
    'lldp_rman_addr' => 'lldpRemManAddrIfSubtype',
);

%MUNGE = (
    'lldp_sysdesc'       => \&SNMP::Info::munge_null,
    'lldp_sysname'       => \&SNMP::Info::munge_null,
    'lldp_rem_sysname'   => \&SNMP::Info::munge_null,
    'lldp_rem_sysdesc'   => \&SNMP::Info::munge_null,
    'lldp_rem_port_desc' => \&SNMP::Info::munge_null,
    'lldp_sys_cap'       => \&SNMP::Info::munge_bits,
    'lldp_rem_sys_cap'   => \&SNMP::Info::munge_bits,
);

sub hasLLDP {
    my $lldp = shift;

    # We may be have LLDP, but nothing in lldpRemoteSystemsData Tables
    # so we could be running LLDP but not return any useful information
    my $lldp_cap = $lldp->lldp_sys_cap();

    return 1 if defined $lldp_cap;
    return;
}

sub lldp_if {
    my $lldp    = shift;
    my $partial = shift;

    my $addr = $lldp->lldp_rem_pid($partial) || {};

    my %lldp_if;
    foreach my $key ( keys %$addr ) {
        my @aOID = split( '\.', $key );
        my $port = $aOID[1];
        $lldp_if{$key} = $port;
    }
    return \%lldp_if;
}

sub lldp_ip {
    my $lldp    = shift;
    my $partial = shift;

    my $rman_addr = $lldp->lldp_rman_addr($partial) || {};

    my %lldp_ip;
    foreach my $key ( keys %$rman_addr ) {
        my ( $index, $proto, $addr ) = _lldp_addr_index($key);
        next unless defined $index;
        next unless $proto == 1;
        $lldp_ip{$index} = $addr;
    }
    return \%lldp_ip;
}

sub lldp_addr {
    my $lldp    = shift;
    my $partial = shift;

    my $rman_addr = $lldp->lldp_rman_addr($partial) || {};

    my %lldp_ip;
    foreach my $key ( keys %$rman_addr ) {
        my ( $index, $proto, $addr ) = _lldp_addr_index($key);
        next unless defined $index;
        $lldp_ip{$index} = $addr;
    }
    return \%lldp_ip;
}

sub lldp_port {
    my $lldp    = shift;
    my $partial = shift;

    my $pdesc = $lldp->lldp_rem_desc($partial)     || {};
    my $pid   = $lldp->lldp_rem_pid($partial)      || {};
    my $ptype = $lldp->lldp_rem_pid_type($partial) || {};

    my %lldp_port;
    foreach my $key ( sort keys %$pid ) {
        my $port = $pdesc->{$key};
        unless ($port) {
            $port = $pid->{$key};
            next unless $port;
            my $type = $ptype->{$key};
            next unless $type;

          # May need to format other types in the future, i.e. Network address
            if ( $type =~ /mac/ ) {
                $port = join( ':',
                    map { sprintf "%02x", $_ } unpack( 'C*', $port ) );
            }
        }

        # Nortel lldpRemPortDesc doesn't match ifDescr, but we can still
        # figure out slot.port based upon lldpRemPortDesc
        if ( $port =~ /^(Unit\s+(\d+)\s+)?Port\s+(\d+)$/ ) {
            $port = defined $1 ? "$2.$3" : "$3";
        }

        $lldp_port{$key} = $port;
    }
    return \%lldp_port;
}

sub lldp_id {
    my $lldp    = shift;
    my $partial = shift;

    my $ch_type = $lldp->lldp_rem_id_type($partial) || {};
    my $ch      = $lldp->lldp_rem_id($partial)      || {};

    my %lldp_id;
    foreach my $key ( keys %$ch ) {
        my $id = $ch->{$key};
        next unless $id;
        my $type = $ch_type->{$key};
        next unless $type;

        # May need to format other types in the future
        if ( $type =~ /mac/ ) {
            $id = join( ':', map { sprintf "%02x", $_ } unpack( 'C*', $id ) );
        }elsif ($type eq 'networkAddress'){
 	    if ( length(unpack('H*', $id)) == 10 ){
 		# IP address (first octet is sign, I guess)
 		my @octets = (map { sprintf "%02x",$_ } unpack('C*', $id))[1..4];
 		$id = join '.', map { hex($_) } @octets;
 	    }
	}
        $lldp_id{$key} = $id;
    }
    return \%lldp_id;
}

#sub root_ip {
#    my $lldp = shift;
#
#    my $man_addr = $lldp->lldp_lman_addr() || {};
#
#    foreach my $key (keys %$man_addr) {
#        my @oids   = split(/\./, $key);
#        my $proto  = shift(@oids);
#        my $length = shift(@oids);
#        # IPv4
#        if ($proto == 1) {
#            my $addr = join('.',@oids);
#            return $addr if (defined $addr and $lldp->snmp_connect_ip($addr));
#        }
#    }
#    return;
#}

# Break up the lldpRemManAddrTable INDEX into common index, protocol,
# and address.
sub _lldp_addr_index {
    my $idx    = shift;
    my @oids   = split( /\./, $idx );
    my $index  = join( '.', splice( @oids, 0, 3 ) );
    my $proto  = shift(@oids);
    my $length = shift(@oids);

    # IPv4
    if ( $proto == 1 ) {
        return ( $index, $proto, join( '.', @oids ) );
    }

    # MAC
    elsif ( $proto == 6 ) {
        return ( $index, $proto,
            join( ':', map { sprintf "%02x", $_ } @oids ) );
    }

    # TODO - Need to handle other protocols, i.e. IPv6
    else {
        return;
    }
}

1;
__END__

=head1 NAME

SNMP::Info::LLDP - SNMP Interface to the Link Layer Discovery Protocol (LLDP)

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 my $lldp = new SNMP::Info ( 
                             AutoSpecify => 1,
                             Debug       => 1,
                             DestHost    => 'router', 
                             Community   => 'public',
                             Version     => 2
                           );

 my $class = $lldp->class();
 print " Using device sub class : $class\n";

 $haslldp   = $lldp->hasLLDP() ? 'yes' : 'no';

 # Print out a map of device ports with LLDP neighbors:
 my $interfaces    = $lldp->interfaces();
 my $lldp_if       = $lldp->lldp_if();
 my $lldp_ip       = $lldp->lldp_ip();
 my $lldp_port     = $lldp->lldp_port();

 foreach my $lldp_key (keys %$lldp_ip){
    my $iid           = $lldp_if->{$lldp_key};
    my $port          = $interfaces->{$iid};
    my $neighbor      = $lldp_ip->{$lldp_key};
    my $neighbor_port = $lldp_port->{$lldp_key};
    print "Port : $port connected to $neighbor / $neighbor_port\n";
 }

=head1 DESCRIPTION

SNMP::Info::LLDP is a subclass of SNMP::Info that provides an object oriented 
interface to LLDP information through SNMP.

LLDP is a Layer 2 protocol that allows a network device to advertise its
identity and capabilities on the local network providing topology information.
The protocol is defined in the IEEE standard 802.1AB.

Create or use a device subclass that inherits this class.  Do not use
directly.

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item F<LLDP-MIB>

=item F<LLDP-EXT-DOT1-MIB>

=item F<LLDP-EXT-DOT3-MIB>

=back

=head1 GLOBAL METHODS

These are methods that return scalar values from SNMP

=over

=item $lldp->hasLLDP()

Is LLDP is active in this device?  

Note:  LLDP may be active, but nothing in C<lldpRemoteSystemsData> Tables so
the device would not return any useful topology information.

=item $lldp->lldp_sysname()

The string value used to identify the system name of the local system.  If the
local agent supports IETF RFC 3418, C<lldpLocSysName> object should have the
same value of C<sysName> object.

Nulls are removed before the value is returned. 

(C<lldpLocSysName>)

=item $lldp->lldp_sysdesc()

The string value used to identify the system description of the local system.
If the local agent supports IETF RFC 3418, C<lldpLocSysDesc> object should
have the same value of C<sysDesc> object.
 
Nulls are removed before the value is returned.

(C<lldpLocSysDesc>)

=item  $lldp->lldp_sys_cap() 

Returns which system capabilities are enabled on the local system.  Results
are munged into an ascii binary string, LSB.  Each digit represents a bit
from the table below:

=over

=item Bit 'other(0)' indicates that the system has capabilities other than
those listed below.

=item Bit 'repeater(1)' indicates that the system has repeater capability.

=item Bit 'bridge(2)' indicates that the system has bridge capability.

=item Bit 'wlanAccessPoint(3)' indicates that the system has WLAN access
point capability.

=item Bit 'router(4)' indicates that the system has router capability.

=item Bit 'telephone(5)' indicates that the system has telephone capability.

=item Bit 'docsisCableDevice(6)' indicates that the system has DOCSIS Cable
Device capability (IETF RFC 2669 & 2670).

=item Bit 'stationOnly(7)' indicates that the system has only station
capability and nothing else."

=back

(C<lldpLocSysCapEnabled>)

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $lldp->lldp_id()

Returns the string value used to identify the chassis component	associated
with the remote system.

(C<lldpRemChassisId>)

=item $lldp->lldp_if()

Returns the mapping to the SNMP Interface Table.

=item  $lldp->lldp_ip()

Returns remote IPv4 address.  Returns for all other address types, use
lldp_addr if you want any return address type.

=item  $lldp->lldp_addr()

Returns remote address.  Type may be any IANA Address Family Number.
Currently only returns IPv4 or MAC addresses.

=item $lldp->lldp_port()

Returns remote port ID

=back

=head2 LLDP Remote Table (C<lldpRemTable>)

=over

=item $lldp->lldp_rem_id_type()

Returns the type of encoding used to identify the chassis associated with
the remote system.

(C<lldpRemChassisIdSubtype>)

=item $lldp->lldp_rem_id()

Returns the string value used to identify the chassis component	associated
with the remote system.

(C<lldpRemChassisId>)

=item $lldp->lldp_rem_pid_type()

Returns the type of port identifier encoding used in the associated
C<lldpRemPortId> object.

(C<lldpRemPortIdSubtype>)

=item $lldp->lldp_rem_pid()

Returns the string value used to identify the port component associated with
the remote system.

(C<lldpRemPortId>)

=item $lldp->lldp_rem_desc()

Returns the string value used to identify the description of the given port
associated with the remote system.

Nulls are removed before the value is returned. 

(C<lldpRemPortDesc>)

=item $lldp->lldp_rem_sysname()

Returns the string value used to identify the system name of the remote
system.

Nulls are removed before the value is returned. 

(C<lldpRemSysName>)

=item $lldp->lldp_rem_sysdesc()

Returns the string value used to identify the system description of the
remote system.

Nulls are removed before the value is returned. 

(C<lldpRemSysDesc>)

=item  $lldp->lldp_rem_sys_cap() 

Returns which system capabilities are enabled on the local system.  Results
are munged into an ascii binary string, LSB.  Each digit
represents a bit from the table below:

=over

=item Bit 'other(0)' indicates that the system has capabilities other than
those listed below.

=item Bit 'repeater(1)' indicates that the system has repeater capability.

=item Bit 'bridge(2)' indicates that the system has bridge capability.

=item Bit 'wlanAccessPoint(3)' indicates that the system has WLAN access
point capability.

=item Bit 'router(4)' indicates that the system has router capability.

=item Bit 'telephone(5)' indicates that the system has telephone capability.

=item Bit 'docsisCableDevice(6)' indicates that the system has DOCSIS Cable
Device capability (IETF RFC 2669 & 2670).

=item Bit 'stationOnly(7)' indicates that the system has only station
capability and nothing else."

=back

(C<lldpRemSysCapEnabled>)

=back

=cut
