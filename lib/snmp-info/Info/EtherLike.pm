# SNMP::Info::EtherLike
# $Id: EtherLike.pm,v 1.21 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2008 Max Baker changes from version 0.8 and beyond.
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

package SNMP::Info::EtherLike;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::EtherLike::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::EtherLike::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( 'ETHERLIKE-MIB' => 'etherMIB' );

%GLOBALS = ();

%FUNCS = (

    # EtherLike StatsTable
    'el_chipset'         => 'dot3StatsEtherChipSet',
    'el_coll_excess'     => 'dot3StatsExcessiveCollisions',
    'el_coll_late'       => 'dot3StatsLateCollisions',
    'el_coll_mult'       => 'dot3StatsMultipleCollisionFrames',
    'el_coll_single'     => 'dot3StatsSingleCollisionFrames',
    'el_duplex'          => 'dot3StatsDuplexStatus',
    'el_error_alignment' => 'dot3StatsAlignmentErrors',
    'el_error_fcs'       => 'dot3StatsFCSErrors',
    'el_error_cs'        => 'dot3StatsCarrierSenseErrors',
    'el_error_frame'     => 'dot3StatsFrameTooLongs',
    'el_error_mac_rec'   => 'dot3StatsInternalMacReceiveErrors',
    'el_error_mac_xmit'  => 'dot3StatsInternalMacTransmitErrors',
    'el_error_sqe'       => 'dot3StatsSQETestErrors',
    'el_error_symbol'    => 'dot3StatsSymbolErrors',
    'el_index'           => 'dot3StatsIndex',
    'el_xmit_defer'      => 'dot3StatsDeferredTransmissions',

    # Ethernet-like Collision Statistics Group
    'el_coll_count' => 'dot3CollCount',
    'el_coll_freq'  => 'dot3CollFrequencies'
);

%MUNGE = ( %SNMP::Info::MUNGE, 'el_duplex' => \&munge_el_duplex, );

sub munge_el_duplex {
    my $duplex = shift;
    return unless defined $duplex;

    $duplex =~ s/Duplex$//;
    return $duplex;
}

1;
__END__


=head1 NAME

SNMP::Info::EtherLike - SNMP Interface to SNMP F<ETHERLIKE-MIB> RFC 1398

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 my $el = new SNMP::Info ( 
                             AutoSpecify => 1,
                             Debug       => 1,
                             DestHost    => 'router', 
                             Community   => 'public',
                             Version     => 2
                           );
 
 my $class = $cdp->class();
 print " Using device sub class : $class\n";

 # Find the duplex setting for a port on a device that implements
 # ETHERLIKE-MIB
 my $interfaces = $el->interfaces();
 my $el_index   = $el->el_index();
 my $el_duplex  = $el->el_duplex(); 

 foreach my $el_port (keys %$el_duplex){
    my $duplex = $el_duplex->{$el_port};
    my $iid    = $el_index->{$el_port};
    my $port   = $interfaces->{$iid};

    print "PORT:$port set to duplex:$duplex\n";
 }

=head1 DESCRIPTION

SNMP::Info::EtherLike is a subclass of SNMP::Info that supplies 
access to the F<ETHERLIKE-MIB> used by some Layer 3 Devices such as
Cisco routers.

See RFC 1398 for more details.

Use or create a subclass of SNMP::Info that inherits this one.  Do not use
directly.

=head2 Inherited Classes

None.  

=head2 Required MIBs

=over

=item F<ETHERLIKE-MIB>

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBALS

These are methods that return scalar values from SNMP

=over

=item None

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 ETHERLIKE STATS TABLE (C<dot3StatsTable>)

=over

=item $el->el_index()

Returns reference to hash. Indexes Stats Table to the interface index (iid).

(C<dot3StatsIndex>)

=item $el->el_duplex()

Returns reference to hash.  Indexes Stats Table to Duplex Status of port.

(C<dot3StatsDuplexStatus>)

=item $el->el_chipset()

(C<dot3StatsEtherChipSet>)

=item $el->el_coll_excess()

(C<dot3StatsExcessiveCollisions>)

=item $el->el_coll_late()

(C<dot3StatsLateCollisions>)

=item $el->el_coll_mult()

(C<dot3StatsMultipleCollisionFrames>)

=item $el->el_coll_single()

(C<dot3StatsSingleCollisionFrames>)

=item $el->el_error_alignment()

(C<dot3StatsAlignmentErrors>)

=item $el->el_error_fcs()

(C<dot3StatsFCSErrors>)

=item $el->el_error_cs()

(C<dot3StatsCarrierSenseErrors>)

=item $el->el_error_frame()

(C<dot3StatsFrameTooLongs>)

=item $el->el_error_mac_rec()

(C<dot3StatsInternalMacReceiveErrors>)

=item $el->el_error_mac_xmit()

(C<dot3StatsInternalMacTransmitErrors>)

=item $el->el_error_sqe()

(C<dot3StatsSQETestErrors>)

=item $el->el_error_symbol()

(C<dot3StatsSymbolErrors>)

=item $el->el_xmit_defer()

(C<dot3StatsDeferredTransmissions>)

=item $el->el_coll_count()

(C<dot3CollCount>)

=item $el->el_coll_freq()

(C<dot3CollFrequencies>)

=back

=head1 Data Munging Callback Subroutines

=over

=item $el->munge_el_duplex()

Removes 'Duplex' from the end of a string.

=back

=cut
