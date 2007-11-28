# SNMP::Info - Max Baker
#
# Copyright (c) 2003,2004 Max Baker 
# All rights reserved.  
# Portions Copyright (c) 2002-3, Regents of the University of California
# All rights reserved.  
#
# See COPYRIGHT at bottom
# $Id: Info.pm,v 1.124 2007/11/27 03:17:36 jeneric Exp $

package SNMP::Info;
$VERSION = '1.07';
use strict;

use Exporter;
use SNMP;
use Carp;
use Math::BigInt;

@SNMP::Info::ISA = qw/Exporter/;
@SNMP::Info::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE $AUTOLOAD $INIT $DEBUG %SPEED_MAP 
            $NOSUCH $BIGINT $REPEATERS/;

=head1 NAME

SNMP::Info - Object Oriented Perl5 Interface to Network devices and MIBs through SNMP. 

=head1 VERSION

SNMP::Info - Version 1.07

=head1 AUTHOR

SNMP::Info was created at UCSC for the netdisco project (www.netdisco.org)
and was orginally written by Max Baker.

Currently being maintained by team of Open Source authors headed by Eric Miller
and Bill Fenner. 

=head1 SYNOPSIS

 use SNMP::Info;

 my $info = new SNMP::Info( 
                            # Auto Discover more specific Device Class
                            AutoSpecify => 1,
                            Debug       => 1,
                            # The rest is passed to SNMP::Session
                            DestHost    => 'router',
                            Community   => 'public',
                            Version     => 2 
                          ) or die "Can't connect to device.\n";

 my $err = $info->error();
 die "SNMP Community or Version probably wrong connecting to device. $err\n" if defined $err;

 $name  = $info->name();
 $class = $info->class();
 print "SNMP::Info is using this device class : $class\n";

 # Find out the Duplex status for the ports
 my $interfaces = $info->interfaces();
 my $i_duplex   = $info->i_duplex();

 # Get CDP Neighbor info
 my $c_if       = $info->c_if();
 my $c_ip       = $info->c_ip();
 my $c_port     = $info->c_port();

 # Print out data per port
 foreach my $iid (keys %$interfaces){
    my $duplex = $i_duplex->{$iid};
    # Print out physical port name, not snmp iid
    my $port  = $interfaces->{$iid};

    print "$port: ";
    print "$duplex duplex" if defined $duplex;

    # The CDP Table has table entries different than the interface tables.
    # So we use c_if to get the map from cdp table to interface table.

    my %c_map = reverse %$c_if; 
    my $c_key = $c_map{$iid};
    unless (defined $c_key) {
         print "\n\n";
         next;
     }
    my $neighbor_ip   = $c_ip->{$c_key};
    my $neighbor_port = $c_port->{$c_key};

    print " connected to $neighbor_ip / $neighbor_port\n" if defined $neighbor_ip;
    print "\n";

 }

=head1 SUPPORT

Please direct all support, help, and bug requests to the snmp-info-users Mailing List
at <http://lists.sourceforge.net/lists/listinfo/snmp-info-users>.

=head1 DESCRIPTION 

SNMP::Info gives an object oriented interface to information obtained through SNMP.

This module lives at http://snmp-info.sourceforge.net  Check for newest version and 
documentation.

This module is geared towards network devices.  Subclasses exist for a number of 
network devices and common MIBs. 

The idea behind this module is to give a common interface to data from network devices,
leaving the device-specific hacks behind the scenes in subclasses.

In the SYNOPSIS example we fetch the name of all the ports on the device and the duplex
setting for that port with two methods -- interfaces() and i_duplex().

The information may be coming from any number of MIB files and is very vendor specific.
SNMP::Info provides you a common method for all supported devices.

Adding support for your own device is easy, and takes little SNMP knowledge.

The module is not limited to network devices. Any MIB or device can be given an objected oriented
front-end by making a module that consists of a couple hashes.  See EXTENDING SNMP::INFO.

=head1 REQUIREMENTS

=over

=item 1. Net-SNMP

To use this module, you must have Net-SNMP installed on your system.
More specifically you need the Perl modules that come with it.

DO NOT INSTALL SNMP:: or Net::SNMP from CPAN!

The SNMP module is matched to an install of net-snmp, and must be installed
from the net-snmp source tree.

The Perl module C<SNMP> is found inside the net-snmp distribution.  Go to the F<perl/> directory
of the distribution to install it, or run C<./configure --with-perl-modules> from the top directory
of the net-snmp distribution.

Net-SNMP can be found at http://net-snmp.sourceforge.net

Version 5.1.2 or greater is recommended.

Various version 4's and 5.0 and 5.1 series will work. 5.0.1 is kinda flaky
on the Perl side.

Versions 5.0301 and 5.0203 have issues with bulkwalk, turn off bulkwalk.

B<Redhat Users>: Some versions that come with certain versions of Redhat/Fedora
don't have the Perl library installed.  Uninstall the RPM and install by hand.

=item 2. MIBS

SNMP::Info operates on textual descriptors found in MIBs.

If you are using SNMP::Info separate from Netdisco, 
download the Netdisco-MIB package at

 http://sourceforge.net/project/showfiles.php?group_id=80033&package_id=135517

Make sure that your snmp.conf is updated to point to your MIB directory
and that the MIBs are world-readable.

=back

=head1 DESIGN GOALS

=over

=item 1. Use of textual MIB leaf identifier and enumerated values 

=over

=item * All values are retrieved via MIB Leaf node names

For example SNMP::Info has an entry in its %GLOBALS hash for ``sysName'' instead
of 1.3.6.1.2.1.1.5.

=item * Data returned is in the enumerated value form.

For Example instead of looking up 1.3.6.1.2.1.2.2.1.3 and getting back C<23>

SNMP::Info will ask for C<RFC1213-MIB::ifType> and will get back C<ppp>. 

=back

=item 2. SNMP::Info is easily extended to new devices

You can create a new subclass for a device by providing four hashes :
%GLOBALS, %MIBS, %FUNCS, and %MUNGE.  

Or you can override any existing methods from a parent class by making a short subroutine. 

See the section EXTENDING SNMP::INFO for more details.

When you make a new subclass for a device, please be sure to send it back to
the developers (via Source Forge or the mailing list) for inclusion in the next
version.

=back

=head1 SUBCLASSES

These are the subclasses that implement MIBs and support devices:

Required MIBs not included in the install instructions above are noted here.

=head2 MIB Subclasses

These subclasses implement method to access one or more MIBs.  These are not 
used directly, but rather inherited from device subclasses.

For more info run C<perldoc> on any of the following module names.

=over

=item SNMP::Info::Airespace

AIRESPACE-WIRELESS-MIB and AIRESPACE-SWITCHING-MIB.  Inherited by devices based
on the Airespace wireless platform.

=item SNMP::Info::Bridge

BRIDGE-MIB (RFC1286).  QBRIDGE-MIB. Inherited by devices with Layer2 support.

=item SNMP::Info::CDP

CISCO-CDP-MIB.  Cisco Discovery Protocol (CDP) Support.  Inherited by Cisco
and HP devices.

=item SNMP::Info::CiscoConfig

CISCO-CONFIG-COPY-MIB, CISCO-FLASH-MIB, and OLD-CISCO-SYS-MIB.
These OIDs facilitate the writing of configuration files.

=item SNMP::Info::CiscoImage

CISCO-IMAGE-MIB. A collection of OIDs providing IOS image characteristics.

=item SNMP::Info::CiscoPortSecurity

CISCO-PORT-SECURITY-MIB.

=item SNMP::Info::CiscoQOS

CISCO-CLASS-BASED-QOS-MIB. A collection of OIDs providing information about
a Cisco device's QOS config.

=item SNMP::Info::CiscoRTT

CISCO-RTTMON-MIB. A collection of OIDs providing information about a Cisco
device's RTT values.

=item SNMP::Info::CiscoStack

CISCO-STACK-MIB.

=item SNMP::Info::CiscoStats

OLD-CISCO-CPU-MIB, CISCO-PROCESS-MIB, and CISCO-MEMORY-POOL-MIB.  Provides
common interfaces for memory, cpu, and os statistics for Cisco devices.  

=item SNMP::Info::CiscoVTP

CISCO-VTP-MIB, CISCO-VLAN-MEMBERSHIP-MIB, CISCO-VLAN-IFTABLE-RELATIONSHIP-MIB

=item SNMP::Info::Entity

ENTITY-MIB.  Used for device info in Cisco and other vendors.

=item SNMP::Info::EtherLike

ETHERLIKE-MIB (RFC1398) - Some Layer3 devices implement this MIB, as well as
some Aironet Layer 2 devices (non Cisco).

=item SNMP::Info::FDP

Foundry Discovery Protocol.  FOUNDRY-SN-SWITCH-GROUP-MIB

=item SNMP::Info::IEEE802dot11

IEEE802dot11-MIB.  A collection of OIDs providing information about standards
based 802.11 wireless devices.  

=item SNMP::Info::LLDP

LLDP-MIB, LLDP-EXT-DOT1-MIB, and LLDP-EXT-DOT3-MIB.  Link Layer Discovery
Protocol (LLDP) Support.

=item SNMP::Info::MAU

MAU-MIB (RFC2668).  Some Layer2 devices use this for extended Ethernet
(Media Access Unit) interface information.

=item SNMP::Info::NortelStack

S5-AGENT-MIB, S5-CHASSIS-MIB.

=item SNMP::Info::RapidCity

RAPID-CITY.  Inhertited by Nortel switches for duplex and VLAN information.

=item SNMP::Info::SONMP

SYNOPTICS-ROOT-MIB, S5-ETH-MULTISEG-TOPOLOGY-MIB.  Provides translation from
Nortel Topology Table information to CDP.  Inherited by Nortel/Bay/Synoptics
switches and hubs.

=back

=head2 Device Subclasses

These subclasses inherit from one or more classes to provide a common interface
to data obtainable from network devices. 

All the required MIB files are included in the netdisco-mib package.  (See Above).

=over

=item SNMP::Info::Layer1

Generic Layer1 Device subclass.

=over 

=item SNMP::Info::Layer1::Allied

Subclass for Allied Telesys Repeaters / Hubs.  

Requires ATI-MIB

=item SNMP::Info::Layer1::Asante

Subclass for Asante 1012 Hubs. 

Requires ASANTE-HUB1012-MIB

=item SNMP::Info::Layer1::Bayhub

Subclass for Nortel/Bay hubs.  This includes System 5000, 100 series,
200 series, and probably more.

=item SNMP::Info::Layer1::Cyclades

Subclass for Cyclades terminal servers.

=item SNMP::Info::Layer1::S3000

Subclass for Bay/Synoptics hubs.  This includes System 3000, 281X, and
probably more.

=back

=item SNMP::Info::Layer2

Generic Layer2 Device subclass.

=over

=item SNMP::Info::Layer2::Airespace

Subclass for Cisco (Airespace) wireless controllers.

=item SNMP::Info::Layer2::Aironet

Class for Cisco Aironet wireless devices that run IOS.  See also
Layer3::Aironet for Aironet devices that don't run IOS.

=item SNMP::Info::Layer2::Allied

Allied Telesys switches.

=item SNMP::Info::Layer2::Aruba

Subclass for Aruba wireless switches.

=item SNMP::Info::Layer2::Bay

Depreciated.  Use BayStack.

=item SNMP::Info::Layer2::Baystack

Subclass for Nortel/Bay Ethernet Switch/Baystack switches.  This includes 303,
304, 350, 380, 410, 420, 425, 450, 460, 470, 5510, 5520, 5530, Business Policy
Switch (BPS) and probably others.

=item SNMP::Info::Layer2::C1900

Subclass for Cisco Catalyst 1900 and 1900c Devices running CatOS.

=item SNMP::Info::Layer2::C2900

Subclass for Cisco Catalyst 2900, 2950, 3500XL, and 3548 devices running IOS.

=item SNMP::Info::Layer2::Catalyst

Subclass for Cisco Catalyst switches running CatOS.  These switches usually
report a model number that starts with C<wsc>.   Note that this class
does not support everything that has the name Catalyst. 

=item SNMP::Info::Layer2::Centillion

Subclass for Nortel/Bay Centillion and 5000BH ATM switches.

=item SNMP::Info::Layer2::Cisco

Generic Cisco subclass for layer2 devices that are not yet supported
in more specific subclasses.

=item SNMP::Info::Layer2::Foundry

Depreciated.  Use SNMP::Info::Layer3::Foundry.

=item SNMP::Info::Layer2::HP

Subclass for HP Procurve Switches

Requires HP-ICF-OID and ENTITY-MIB downloaded from HP.  

See SNMP::Info::Layer2::HP for more info.

=item SNMP::Info::Layer2::N2270

Subclass for Nortel 2270 wireless switches.

=item SNMP::Info::Layer2::NAP222x

Subclass for Nortel 222x series wireless access points.

=item SNMP::Info::Layer2::Orinoco

Subclass for Orinoco/Proxim wireless access points.

=item SNMP::Info::Layer2::ZyXEL_DSLAM

Zyxel DSLAMs.  Need I say more?

=back

=item SNMP::Info::Layer3

Generic Layer3 and Layer2+3 Device subclass.

=over

=item SNMP::Info::Layer3::Aironet

Subclass for Cisco Aironet wireless access points (AP) not running IOS. These
are usually older devices.

MIBs for these devices now included in v2.tar.gz available from ftp.cisco.com.

Note Layer2::Aironet 

=item SNMP::Info::Layer3::AlteonAD

Subclass for Nortel Alteon Ace Director series L2-7 switches.

=item SNMP::Info::Layer3::BayRS

Subclass for Nortel Multiprotocol/BayRS routers.  This includes BCN, BLN, ASN,
ARN, AN, 2430, and 5430 routers.

=item SNMP::Info::Layer3::C3550

Subclass for Cisco Catalyst 3550,3540,3560 2/3 switches running IOS.

=item SNMP::Info::Layer3::C4000

This class covers Catalyst 4000s and 4500s.

=item SNMP::Info::Layer3::C6500

This class covers Catalyst 6500s in native mode, hybrid mode.  Catalyst
3750's, 2970's and probably others.

=item SNMP::Info::Layer3::Cisco

This is a simple wrapper around Layer3 for IOS devices.  It adds on CiscoVTP.

=item SNMP::Info::Layer3::Contivity

Subclass for Nortel Contivity/VPN Routers.  

=item SNMP::Info::Layer3::Dell

Subclass for Dell PowerConnect switches.  

=item SNMP::Info::Layer3::Enterasys

Subclass for Enterasys devices.

=item SNMP::Info::Layer3::Extreme

Subclass for Extreme Networks switches.

See SNMP::Info::Layer3::Extreme for more info.

=item SNMP::Info::Layer3::Foundry

Subclass for Foundry Network devices.

See SNMP::Info::Layer3::Foundry for more info.

=item SNMP::Info::Layer3::Juniper

Subclass for Juniper devices

=item SNMP::Info::Layer3::Microsoft

Subclass for Generic Microsoft Routers running Microsoft Windows OS.

=item SNMP::Info::Layer3::N1600

Subclass for Nortel Ethernet Routing Switch 1600 series.

=item SNMP::Info::Layer3::NetSNMP

Subclass for host systems running Net-SNMP.

=item SNMP::Info::Layer3::Netscreen

Subclass for Juniper NetScreen.

=item SNMP::Info::Layer3::Passport

Subclass for Nortel Ethernet Routing Switch/Passport 8000 series and Accelar
series switches.

=item SNMP::Info::Layer3::Sun

Subclass for Generic Sun Routers running SunOS.

=back

=back

=head1 Thanks

Thanks for testing and coding help (in no particular order) to :
Andy Ford, Brian Wilson, Jean-Philippe Luiggi, Dána Watanabe, Bradley Baetz,
Mike Hunter, Justin Hunter, Brian Chow and people listed on the Netdisco README!

=head1 USAGE

=head2 Constructor

=over

=item new()

Creates a new object and connects via SNMP::Session. 

 my $info = new SNMP::Info( 'Debug'         => 1,
                            'AutoSpecify'   => 1,
                            'BigInt'        => 1,
                            'BulkWalk'      => 1,
                            'BulkRepeaters' => 20,
                            'LoopDetect'    => 1,
                            'DestHost'      => 'myrouter',
                            'Community'     => 'public',
                            'Version'       => 2,
                            'MibDirs'       => ['dir1','dir2','dir3'],
                          ) or die;

SNMP::Info Specific Arguments :

=over

=item AutoSpecify

Returns an object of a more specific device class

(default on)

=item BigInt

Return Math::BigInt objects for 64 bit counters.  Sets on a global scope, not object.

(default off)

=item BulkWalk

Set to C<0> to turn off BULKWALK commands for SNMPv2 connections.

Note that BULKWALK is turned off for Net-SNMP versions 5.1.x because of a bug.

(default on)

=item BulkRepeaters

Set number of MaxRepeaters for BULKWALK operation.  See C<perldoc SNMP> -> bulkwalk() for more info.

(default 20)

=item LoopDetect

Detects looping during getnext table column walks by comparing IIDs for each
instance.  A loop is detected if the same IID is seen more than once and the
walk is aborted.  Note:  This will not detect loops during a bulkwalk
operation, Net-SNMP's internal bulkwalk function must detect the loop. 

Set to C<0> to turn off loop detection.

(default on)

=item Debug

Prints Lots of debugging messages.
Pass 2 to print even more debugging messages.

(default off)

=item DebugSNMP

Set $SNMP::debugging  level for Net-SNMP.

See L<SNMP> for more details.

=item MibDirs

Array ref to list of directories in which to look for MIBs.  Note this will
be in addition to the ones setup in snmp.conf at the system level.

(default use net-snmp settings only)

=item RetryNoSuch

When using SNMP Version 1, try reading values even if they come back as "no
such variable in this MIB".  Set to false if so desired.  This feature lets you
read SNMPv2 data from an SNMP version 1 connection, and should probably be left
on.

(default true)

=item Session

SNMP::Session object to use instead of connecting on own.

(default creates session automatically)

=item OTHER

All other arguments are passed to SNMP::Session.

See SNMP::Session for a list of other possible arguments.

=back

A Note about the wrong Community string or wrong SNMP Version:

If a connection is using the wrong community string or the wrong SNMP version,
the creation of the object will not fail.  The device still answers the call on
the SNMP port, but will not return information.  Check the error() method after
you create the device object to see if there was a problem in connecting.

A note about SNMP Versions :

Some older devices don't support SNMP version 2, and will not return anything when a
connection under Version 2 is attempted.

Some newer devices will support Version 1, but will not return all the data they might have
if you had connected under Version 1 

When trying to get info from a new device, you may have to try version 2 and then fallback to 
version 1.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %args = @_;
    my %sess_args = %args;
    my $new_obj = {};
    bless $new_obj,$class;

    $new_obj->{class} = $class;

    # load references to all the subclass data structures
    {
        no strict 'refs';
        $new_obj->{init}    = \${$class . '::INIT'};
        $new_obj->{mibs}    = \%{$class . '::MIBS'};
        $new_obj->{globals} = \%{$class . '::GLOBALS'};
        $new_obj->{funcs}   = \%{$class . '::FUNCS'};
        $new_obj->{munge}   = \%{$class . '::MUNGE'};
    }

    # SNMP::Info specific args :
    if (defined $args{Debug}){
        $new_obj->debug($args{Debug});
        delete $sess_args{Debug};
    } else {
        $new_obj->debug(defined $DEBUG ? $DEBUG : 0);
    }

    if (defined $args{DebugSNMP}){
        $SNMP::debugging = $args{DebugSNMP};
        delete $sess_args{DebugSNMP};
    }

    my $auto_specific = 0;
    if (defined $args{AutoSpecify}){
        $auto_specific = $args{AutoSpecify} || 0;
        delete $sess_args{AutoSpecify};
    }

    if (defined $args{BulkRepeaters}){
        $new_obj->{BulkRepeaters} = $args{BulkRepeaters};
        delete $sess_args{BulkRepeaters};
    }

    if (defined $args{BulkWalk}){
        $new_obj->{BulkWalk} = $args{BulkWalk};
        delete $sess_args{BulkWalk};
    }

    if (defined $args{LoopDetect}){
        $new_obj->{LoopDetect} = $args{LoopDetect};
        delete $sess_args{LoopDetect};
    }

    my $sess = undef;
    if (defined $args{Session}){
        $sess = $args{Session};
        delete $sess_args{Session};
    }
    if (defined $args{BigInt}){
        $BIGINT = $args{BigInt};
        delete $sess_args{BigInt};
    }
    if (defined $args{MibDirs}){
        $new_obj->{mibdirs} = $args{MibDirs};
        delete $sess_args{MibDirs};
    }

    $new_obj->{nosuch} = $args{RetryNoSuch} || $NOSUCH;

    # Initialize mibs if not done
    my $init_ref = $new_obj->{init};
    unless ( defined $$init_ref and $$init_ref ) {
        $new_obj->init();
        $$init_ref=1;    
    }

    # Connects to device unless open session is provided.  
    $sess = new SNMP::Session( 'UseEnums' => 1, %sess_args , 'RetryNoSuch' => $new_obj->{nosuch}) 
        unless defined $sess;

    # No session object created
    unless (defined $sess){
        $new_obj->error_throw("SNMP::Info::new() Failed to Create Session. ");
        return undef;
    }
    
    # Session object created but SNMP connection failed.
    my $sess_err = $sess->{ErrorStr} || '';
    if ($sess_err){
        $new_obj->error_throw("SNMP::Info::new() Net-SNMP session creation failed. $sess_err");
        return undef;
    }

    # Table function store
    my $store = {};

    # Save Args for later
    $new_obj->{store}     = $store;
    $new_obj->{sess}      = $sess;
    $new_obj->{args}      = \%args;
    $new_obj->{snmp_ver}  = $args{Version}   || 2;
    $new_obj->{snmp_comm} = $args{Community} || 'public';

    return $auto_specific ?
        $new_obj->specify() : $new_obj;
}

=back

=head2 Data is Cached

Methods and subroutines requesting data from a device will only load the data
once, and then return cached versions of that data. 

Run $info->load_METHOD() where method is something like 'i_name' to reload
data from a method.

Run $info->clear_cache() to clear the cache to allow reload of both globals
and table methods.

=head2 Object Scalar Methods

These are for package related data, not direcly supplied
from SNMP.

=over

=item $info->clear_cache()

Clears the cached data.  This includes GLOBALS data and TABLE METHOD data.

=cut

sub clear_cache {
    my $self = shift;

    print "SNMP::Info::clear_cache() - Cache Cleared.\n" if $self->debug();
    
    # Clear cached global values and table method flag for being cached
    foreach my $key (keys %$self){
        next unless defined $key;
        next unless $key =~ /^_/;
        delete $self->{$key};
    }

    # Clear store for tables
    $self->store({});
}

=item $info->debug(1)

Returns current debug status, and optionally toggles debugging info for this object.

=cut

sub debug {
    my $self = shift;
    my $debug = shift;

    if (defined $debug){
        $self->{debug} = $debug;
    }
    
    return $self->{debug};
}

=item $info->bulkwalk([1|0])

Returns if bulkwalk is currently turned on for this object.

Optionally sets the bulkwalk parameter.

=cut

sub bulkwalk {
    my $self = shift;
    my $bw   = shift;

    if (defined $bw){
        $self->{BulkWalk} = $bw;
    }   
    return $self->{BulkWalk};
}
    

=item $info->loopdetect([1|0])

Returns if loopdetect is currently turned on for this object.

Optionally sets the loopdetect parameter.

=cut

sub loopdetect {
    my $self = shift;
    my $ld   = shift;

    if (defined $ld){
        $self->{LoopDetect} = $ld;
    }   
    return $self->{LoopDetect};
}

=item $info->device_type()

Returns the Subclass name for this device.  C<SNMP::Info> is returned if no more
specific class is available.

First the device is checked for Layer 3 support and a specific subclass,
then Layer 2 support and subclasses are checked.

This means that Layer 2 / 3  switches and routers will fall under the
SNMP::Info::Layer3 subclasses.

If the device still can be connected to via SNMP::Info, then 
SNMP::Info is returned.  

Algorithm for Subclass Detection:

        Layer3 Support                     -> SNMP::Info::Layer3
            Aironet (BR500,AP340,350,1200) -> SNMP::Info::Layer3::Aironet
                     AP4800... All Non IOS
            Catalyst 3550,3548,3560        -> SNMP::Info::Layer3::C3550
            Catalyst 4000,4500             -> SNMP::Info::Layer3::C4000
            Catalyst 6500,3750             -> SNMP::Info::Layer3::C6500
            Cisco Generic L3 IOS device    -> SNMP::Info::Layer3::Cisco
            Cyclades terminal server       -> SNMP::Info::Layer1::Cyclades
            Dell PowerConnect              -> SNMP::Info::Layer3::Dell
            Enterasys                      -> SNMP::Info::Layer3::Enterasys
            Extreme                        -> SNMP::Info::Layer3::Extreme
            Foundry                        -> SNMP::Info::Layer3::Foundry
            Juniper                        -> SNMP::Info::Layer3::Juniper
            Microsoft                      -> SNMP::Info::Layer3::Microsoft
            Net-SNMP                       -> SNMP::Info::Layer3::NetSNMP
            Nortel Passport/Accelar LAN    -> SNMP::Info::Layer3::Passport
            Nortel/Bay Baystack            -> SNMP::Info::Layer2::Baystack
            Alteon Ace Director            -> SNMP::Info::Layer3::AlteonAD
            Nortel Contivity               -> SNMP::Info::Layer3::Contivity
            Nortel BayRS Router            -> SNMP::Info::Layer3::BayRS
            Sun Router                     -> SNMP::Info::Layer3::Sun
         Elsif Layer2 (no Layer3)          -> SNMP::Info::Layer2
            Aironet - IOS Devices          -> SNMP::Info::Layer2::Aironet
            Catalyst 1900                  -> SNMP::Info::Layer2::C1900
            Catalyst 2900XL,2940,2950,
                     3500XL                -> SNMP::Info::Layer2::C2900
            Catalyst 2960, 2970            -> SNMP::Info::Layer3::C6500
            Catalyst 3550/3548             -> SNMP::Info::Layer3::C3550
            Cisco 3400 w/ MetroBase        -> SNMP::Info::Layer3::C3550
            Catalyst WS-C 2926,5xxx        -> SNMP::Info::Layer2::Catalyst
            Cisco (Airespace) Wireless     -> SNMP::Info::Layer2::Airespace
            Cisco (not covered by above)   -> SNMP::Info::Layer2::Cisco
            Cyclades terminal server       -> SNMP::Info::Layer1::Cyclades
            Dell PowerConnect              -> SNMP::Info::Layer3::Dell
            Enterasys                      -> SNMP::Info::Layer3::Enterasys
            Extreme                        -> SNMP::Info::Layer3::Extreme
            Foundry                        -> SNMP::Info::Layer3::Foundry
            HP Procurve                    -> SNMP::Info::Layer2::HP
            Nortel/Bay Centillion ATM      -> SNMP::Info::Layer2::Centillion
            Nortel/Bay Baystack            -> SNMP::Info::Layer2::Baystack
            Nortel Business Ethernet Switch-> SNMP::Info::Layer2::Baystack
            Nortel Passport/Accelar 8100   -> SNMP::Info::Layer3::Passport
            Nortel AP 222x                 -> SNMP::Info::Layer2::NAP222x
            Orinco AP                      -> SNMP::Info::Layer2::Orinoco
            Nortel 2270 WSS                -> SNMP::Info::Layer2::N2270
        Elsif Layer1 Support               -> SNMP::Info::Layer1
            Allied                         -> SNMP::Info::Layer1::Allied
            Asante                         -> SNMP::Info::Layer1::Asante
            Nortel/Bay Hub                 -> SNMP::Info::Layer1::Bayhub
            Bay/Synoptics Hub              -> SNMP::Info::Layer1::S3000
        Else                               -> SNMP::Info
            ZyXEL_DSLAM                    -> SNMP::Info::Layer2::ZyXEL_DSLAM
            Aruba wireless                 -> SNMP::Info::Layer2::Aruba
            Juniper NetScreen              -> SNMP::Info::Layer3::Netscreen

=cut

sub device_type {
    my $info = shift;

    my $objtype = "SNMP::Info";

    my $layers = $info->layers();
    # if we dont have sysServices, we dont have anything else either probably.
    return undef unless (defined $layers and length($layers));

    my $desc   = $info->description() || 'undef';
    $desc =~ s/[\r\n\l]+/ /g;
    my $id     = $info->id() || 'undef';

    $info->debug() and print "SNMP::Info::device_type() layers:$layers id:$id sysDescr:\"$desc\"\n";

    # Hash for generic fallback to a device class if unable to determine using
    # the sysDescr regex.
    my %l3sysoidmap = (
                      9     => 'SNMP::Info::Layer3::Cisco',
                      11    => 'SNMP::Info::Layer2::HP',
                      18    => 'SNMP::Info::Layer3::BayRS',
                      42    => 'SNMP::Info::Layer3::Sun',
                      311   => 'SNMP::Info::Layer3::Microsoft',
                      674   => 'SNMP::Info::Layer3::Dell',
                      1916  => 'SNMP::Info::Layer3::Extreme',
                      1991  => 'SNMP::Info::Layer3::Foundry',
                      2021  => 'SNMP::Info::Layer3::NetSNMP',
                      2272  => 'SNMP::Info::Layer3::Passport',
                      2636  => 'SNMP::Info::Layer3::Juniper',
                      2925  => 'SNMP::Info::Layer1::Cyclades',
                      5624  => 'SNMP::Info::Layer3::Enterasys',
                      8072  => 'SNMP::Info::Layer3::NetSNMP',
                    );

    my %l2sysoidmap = (
                      9     => 'SNMP::Info::Layer2::Cisco',
                      11    => 'SNMP::Info::Layer2::HP',
                      207   => 'SNMP::Info::Layer2::Allied',
                      674   => 'SNMP::Info::Layer3::Dell',
                      1916  => 'SNMP::Info::Layer3::Extreme',
                      1991  => 'SNMP::Info::Layer3::Foundry',
                      2272  => 'SNMP::Info::Layer3::Passport',
                      2925  => 'SNMP::Info::Layer1::Cyclades',
                      4526  => 'SNMP::Info::Layer2::Netgear',
                      5624  => 'SNMP::Info::Layer3::Enterasys',
                      14179 => 'SNMP::Info::Layer2::Airespace',
                      14823 => 'SNMP::Info::Layer2::Aruba',
                    );

    # Get just the enterprise number for generic mapping
    $id = $1 if (defined($id) && $id =~ /^\.1\.3\.6\.1\.4\.1\.(\d+)/);
    
    # Layer 3 Supported 
    #   (usually has layer2 as well, so we check for 3 first)
    if ($info->has_layer(3)) {
        $objtype = 'SNMP::Info::Layer3';

        # Device Type Overrides

        return $objtype unless (defined $desc and length($desc));

        $objtype = 'SNMP::Info::Layer3::C3550'   if $desc =~ /(C3550|C3560)/ ;
        $objtype = 'SNMP::Info::Layer3::C4000'   if $desc =~ /Catalyst 4[05]00/;
        $objtype = 'SNMP::Info::Layer3::Foundry' if $desc =~ /foundry/i ;
        # Aironet - older non-IOS
        $objtype = 'SNMP::Info::Layer3::Aironet' if ($desc =~ /Cisco/ and $desc =~ /\D(CAP340|AP340|CAP350|350|1200)\D/) ;
        $objtype = 'SNMP::Info::Layer3::Aironet' if ($desc =~ /Aironet/ and $desc =~ /\D(AP4800)\D/) ;
        $objtype = 'SNMP::Info::Layer3::C6500'   if $desc =~ /(c6sup2|c6sup1)/;
        # Next one untested. Reported working by DA
        $objtype = 'SNMP::Info::Layer3::C6500'   if ($desc =~ /cisco/i and $desc =~ /3750/);
        $objtype = 'SNMP::Info::Layer3::C6500'   if $desc =~ /(s72033_rp|s3223_rp|s222_rp)/;
        # Nortel ERS (Passport) 1600 Series < version 2.1
        $objtype = 'SNMP::Info::Layer3::N1600'  if $desc =~ /(Passport|Ethernet\s+Routing\s+Switch)-16/i;
        #  ERS - BayStack Numbered 
        $objtype = 'SNMP::Info::Layer2::Baystack' if ($desc =~ /^(BayStack|Ethernet\s+Routing\s+Switch)\s[2345](\d){2,3}/i);
        # Nortel Alteon AD Series
        $objtype = 'SNMP::Info::Layer3::AlteonAD' if $desc =~ /Alteon\s[1A][8D]/;
        # Nortel Contivity
        $objtype = 'SNMP::Info::Layer3::Contivity' if $desc =~ /\bCES\b/;

        # Allied Telesyn Layer2 managed switches. They report they have L3 support
        $objtype = 'SNMP::Info::Layer2::Allied' if ($desc =~ /Allied.*AT-80\d{2}\S*/i);

        # Generic device classification based upon sysObjectID
        if (($objtype eq 'SNMP::Info::Layer3') and (defined($id)) and (exists($l3sysoidmap{$id}))) {
            $objtype = $l3sysoidmap{$id};
        }

    # Layer 2 Supported
    } elsif ($info->has_layer(2)) {
        $objtype = 'SNMP::Info::Layer2'; 

        return $objtype unless (defined $desc and $desc !~ /^\s*$/);

        # Device Type Overrides

        #   Catalyst 1900 series override
        $objtype = 'SNMP::Info::Layer2::C1900' if ($desc =~ /catalyst/i and $desc =~ /\D19\d{2}/);

        #   Catalyst 2900 and 3500XL (IOS) series override
        $objtype = 'SNMP::Info::Layer2::C2900' if ($desc =~ /(C2900XL|C2950|C3500XL|C2940|CGESM)/i );

        #   Catalyst WS-C series override 2926,4k,5k,6k in Hybrid
        $objtype = 'SNMP::Info::Layer2::Catalyst' if ($desc =~ /WS-C\d{4}/);

        #   Catalyst 3550 / 3548 Layer2 only switches
        #   Cisco 3400 w/ MetroBase Image
        $objtype = 'SNMP::Info::Layer3::C3550' if ($desc =~ /(C3550|ME340x)/);

        #   Cisco 2970  
        $objtype = 'SNMP::Info::Layer3::C6500' if ($desc =~ /(C2970|C2960)/);

        #  Centillion ATM
        $objtype = 'SNMP::Info::Layer2::Centillion' if ($desc =~ /MCP/);
  
        #  BPS
        $objtype = 'SNMP::Info::Layer2::Baystack' if ($desc =~ /Business\sPolicy\sSwitch/i);

        #  BayStack Numbered
        $objtype = 'SNMP::Info::Layer2::Baystack' if ($desc =~ /^(BayStack|Ethernet\s+(Routing\s+)??Switch)\s[2345](\d){2,3}/i);

        #  Nortel Business Ethernet Switch
        $objtype = 'SNMP::Info::Layer2::Baystack' if ($desc =~ /^Business Ethernet Switch\s[12]\d\d/i);

        #  Nortel AP 222X
        $objtype = 'SNMP::Info::Layer2::NAP222x' if ($desc =~ /Access\s+Point\s+222/);

        #  Orinco
        $objtype = 'SNMP::Info::Layer2::Orinoco' if ($desc =~ /(AP-\d{3}|WavePOINT)/);

        #  Aironet - IOS
        $objtype = 'SNMP::Info::Layer2::Aironet' if ($desc =~ /\b(C1100|C1130|AP1200|C350|C1200|C1240)\b/  and $desc =~ /\bIOS\b/);

        # Aironet - non IOS
        $objtype = 'SNMP::Info::Layer3::Aironet' if ($desc =~ /Cisco/ and $desc =~ /\D(BR500)\D/) ;

        #Nortel 2270
        $objtype = 'SNMP::Info::Layer2::N2270' if ($desc =~ /Nortel\s+(Networks\s+)??WLAN\s+-\s+Security\s+Switch/) ;

        # Generic device classification based upon sysObjectID
        if (($objtype eq 'SNMP::Info::Layer2') and (defined($id)) and (exists($l2sysoidmap{$id}))) {
            $objtype = $l2sysoidmap{$id};
        }

    } elsif ($info->has_layer(1)) {
        $objtype = 'SNMP::Info::Layer1';
        #  Allied crap-o-hub
        $objtype = 'SNMP::Info::Layer1::Allied' if ($desc =~ /allied/i);
        $objtype = 'SNMP::Info::Layer1::Asante' if ($desc =~ /asante/i);

        #  Bay Hub
        $objtype = 'SNMP::Info::Layer1::Bayhub' if ($desc =~ /\bNMM.*Agent/);
        $objtype = 'SNMP::Info::Layer1::Bayhub' if ($desc =~ /\bBay\s*Stack.*Hub/i);

        #  Synoptics Hub
        #  This will override Bay Hub only for specific devices supported by this class
        $objtype = 'SNMP::Info::Layer1::S3000' if ($desc =~ /\bNMM\s+(281|3000|3030)/i);

    # These devices don't claim to have Layer1-3 but we like em anyways.
    } else {
        $objtype = 'SNMP::Info::Layer2::ZyXEL_DSLAM' if ($desc =~ /8-port .DSL Module\(Annex .\)/i);
        # Aruba wireless switches
        $objtype = 'SNMP::Info::Layer2::Aruba' if ($desc =~ /(ArubaOS|AirOS)/);
        #Juniper NetScreen
        $objtype = 'SNMP::Info::Layer3::Netscreen' if ($desc =~ /NetScreen/i);
        # Cisco PIX
        $objtype = 'SNMP::Info::Layer3::Cisco' if ($desc =~ /Cisco PIX Security Appliance/i);
        # Cisco ASA
        $objtype = 'SNMP::Info::Layer3::Cisco' if ($desc =~ /Cisco Adaptive Security Appliance/i);
    }   

    return $objtype; 
}

=item $info->error(no_clear)

Returns Error message if there is an error, or undef if there is not.

Reading the error will clear the error unless you set the no_clear flag.

=cut

sub error {
    my $self     = shift;
    my $no_clear = shift;
    my $err      = $self->{error};

    $self->{error} = undef unless defined $no_clear and $no_clear;
    return $err;
}

=item $info->has_layer(3)

Returns non-zero if the device has the supplied layer in the OSI Model

Returns C<undef> if the device doesn't support the layers() call.

=cut

sub has_layer {
    my $self = shift;
    my $check_for = shift;

    my $layers = $self->layers();
    return undef unless defined $layers;
    return undef unless length($layers);
    return substr($layers,8-$check_for, 1);
}

=item $info->snmp_comm()

Returns SNMP Community string used in connection.

=cut

sub snmp_comm {
    my $self = shift;
    return $self->{snmp_comm};
}

=item $info->snmp_ver()

Returns SNMP Version used for this connection

=cut

sub snmp_ver {
    my $self = shift;
    return $self->{snmp_ver};
} 

=item $info->specify()

Returns an object of a more-specific subclass.  

 my $info = new SNMP::Info(...);
 # Returns more specific object type
 $info = $info->specific();

Usually this method is called internally from new(AutoSpecify => 1)

See device_type() entry for how a subclass is chosen.

=cut

sub specify {
    my $self = shift;

    my $device_type = $self->device_type();
    unless (defined $device_type) {
        $self->error_throw("SNMP::Info::specify() - Could not get info from device");
        return undef;
    }
    return $self if $device_type eq 'SNMP::Info';

    # Load Subclass
    # By evaling a string the contents of device_type now becomes a bareword. 
    eval "require $device_type;";
    if ($@) {
        croak "SNMP::Info::specify() Loading $device_type Failed. $@\n";
    }

    my $args    = $self->args();
    my $session = $self->session();
    my $sub_obj = $device_type->new(%$args,'Session'=>$session,'AutoSpecify' => 0);

    unless (defined $sub_obj) {
        $self->error_throw("SNMP::Info::specify() - Could not connect with new class ($device_type)");
        return $self;
    }

    $self->debug() and print "SNMP::Info::specify() - Changed Class to $device_type.\n";
    return $sub_obj;
}

=item $info->cisco_comm_indexing()

Returns 0.  Is an overridable method used for vlan indexing for
snmp calls on certain Cisco devices. 

See L<ftp://ftp.cisco.com/pub/mibs/supportlists/wsc5000/wsc5000-communityIndexing.html>

=cut

sub cisco_comm_indexing{
    0;
}

=back

=head2 Globals (Scalar Methods)

These are methods to return scalar data from RFC1213.  

Some subset of these is probably available for any network device that speaks SNMP.

=over

=item $info->uptime()

Uptime in hundredths of seconds since device became available.

(B<sysUpTime>)

=item $info->contact()

(B<sysContact>)

=item $info->name()

(B<sysName>)

=item $info->location() 

(B<sysLocation>)

=item $info->layers()

This returns a binary encoded string where each
digit represents a layer of the OSI model served
by the device.  

    eg: 01000010  means layers 2 (physical) and 7 (Application) 
                  are served.

Note:  This string is 8 digits long.  

See $info->has_layer()

(B<sysServices>)

=item $info->ports()

Number of interfaces available on this device.

Not too useful as the number of SNMP interfaces usually does not 
correspond with the number of physical ports

(B<ifNumber>)

=item $info->ipforwarding()

The indication of whether the entity is acting as an IP gateway

Returns either forwarding or not-forwarding

(B<ipForwarding>)

=back

=head2 Table Methods

Each of these methods returns a hash_reference to a hash keyed on the
interface index in SNMP.

Example : $info->interfaces() might return  

    { '1.12' => 'FastEthernet/0',
      '2.15' => 'FastEthernet/1',
      '9.99' => 'FastEthernet/2'
    }

The key is what you would see if you were to do an snmpwalk, and in some cases
changes between reboots of the network device.

=head2 Partial Table Fetches

If you want to get only a part of an SNMP table or a single instance from the
table and you know the IID for the part of the table that you want, you can
specify it in the call:

    $local_routes = $info->ipr_route('192.168.0');

This will only fetch entries in the table that start with C<192.168.0>, which
in this case are routes on the local network. 

Remember that you must supply the partial IID (a numeric OID).

Partial table results are not cached.

=head2 Interface Information

=over

=item $info->interfaces()

This methods is overriden in each subclass to provide a 
mapping between the Interface Table Index (iid) and the physical port name.

=item $info->if_ignore()

Returns a reference to a hash where key values that exist are 
interfaces to ignore.

Ignored interfaces are ones that are usually not physical ports or Virtual Lans (VLANs) such as the Loopback interface,
or the CPU interface. 

=cut

sub if_ignore {
    my %nothing;
    return \%nothing;
}

=item $info->i_index()

Default SNMP IID to Interface index.

(B<ifIndex>)

=item $info->i_description() 

Description of the interface. Usually a little longer single word name that is both
human and machine friendly.  Not always.

(B<ifDescr>)

=item $info->i_type()

Interface type, such as Vlan, 10baseT, Ethernet, Serial

(B<ifType>)

=item $info->i_mtu()

INTEGER. Interface MTU value.

(B<ifMtu>)

=item $info->i_speed()

Speed of the link, human format.  See munge_speed() later in document for details.

(B<ifSpeed>, B<ifHighSpeed> if necessary)

=cut

sub i_speed {
    my $info = shift;
    my $partial = shift;

    my $i_speed = $info->orig_i_speed($partial);
    my $i_up = $info->i_up($partial);

    my $i_speed_high = undef;
    foreach my $i (keys %$i_speed) {
	if ($i_speed->{$i} eq "4294967295") {
	    $i_speed_high = $info->i_speed_high($partial) unless defined($i_speed_high);
	    $i_speed->{$i} = $i_speed_high->{$i} if ($i_speed_high->{$i});
	}
    }
    return $i_speed;
}

=item $info->i_speed_high()

Speed of a high-speed link, human format.  See munge_highspeed() later in
document for details.  You should not need to call this directly, as
i_speed() will call it if it needs to.

(B<ifHighSpeed>)

=item $info->i_mac() 

MAC address of the interface.  Note this is just the MAC of the port, not anything connected to it.

(B<ifPhysAddress>)

=item $info->i_up() 

Link Status of the interface.  Typical values are 'up' and 'down'.

(B<ifOperStatus>)

=item $info->i_up_admin()

Administrative status of the port.  Typical values are 'enabled' and 'disabled'.

(B<ifAdminStatus>)

=item $info->i_lastchange()

The value of sysUpTime when this port last changed states (up,down).

(B<ifLastChange>)

=item $info->i_name()

Interface Name field.  Supported by a smaller subset of devices, this fields is often 
human set.

(B<ifName>)

=item $info->i_alias()

Interface Name field.  For certain devices this is a more human friendly form of i_description().
For others it is a human set field like i_name().

(B<ifAlias>)

=back

=head2 Interface Statistics

=over

=item $info->i_octet_in(), $info->i_octets_out(),
$info->i_octet_in64(), $info->i_octets_out64()

Bandwidth.

Number of octets sent/received on the interface including framing characters.

64 bit version may not exist on all devices. 

NOTE: To manipulate 64 bit counters you need to use Math::BigInt, since the values
are too large for a normal Perl scalar.   Set the global $SNMP::Info::BIGINT to 1 , or
pass the BigInt value to new() if you want SNMP::Info to do it for you.


(B<ifInOctets>) (B<ifOutOctets>)
(B<ifHCInOctets>) (B<ifHCOutOctets>)

=item $info->i_errors_in(), $info->i_errors_out()

Number of packets that contained an error prventing delivery.  See IF-MIB for more info.

(B<ifInErrors>) (B<ifOutErrors>)

=item $info->i_pkts_ucast_in(), $info->i_pkts_ucast_out(),
$info->i_pkts_ucast_in64(), $info->i_pkts_ucast_out64()

Number of packets not sent to a multicast or broadcast address.

64 bit version may not exist on all devices. 

(B<ifInUcastPkts>) (B<ifOutUcastPkts>)
(B<ifHCInUcastPkts>) (B<ifHCOutUcastPkts>)

=item $info->i_pkts_nucast_in(), $info->i_pkts_nucast_out(),

Number of packets sent to a multicast or broadcast address.

These methods are depricated by i_pkts_multi_in() and i_pkts_bcast_in()
according to IF-MIB.  Actual device usage may vary.

(B<ifInNUcastPkts>) (B<ifOutNUcastPkts>)

=item $info->i_pkts_multi_in() $info->i_pkts_multi_out(),
$info->i_pkts_multi_in64(), $info->i_pkts_multi_out64()

Number of packets sent to a multicast address.

64 bit version may not exist on all devices. 

(B<ifInMulticastPkts>) (B<ifOutMulticastPkts>)
(B<ifHCInMulticastPkts>) (B<ifHCOutMulticastPkts>)

=item $info->i_pkts_bcast_in() $info->i_pkts_bcast_out(),
$info->i_pkts_bcast_in64() $info->i_pkts_bcast_out64()

Number of packets sent to a broadcast address on an interface.

64 bit version may not exist on all devices. 

(B<ifInBroadcastPkts>) (B<ifOutBroadcastPkts>)
(B<ifHCInBroadcastPkts>) (B<ifHCOutBroadcastPkts>)

=item $info->i_discards_in() $info->i_discards_out()

"The number of inbound packets which were chosen to be discarded even though
no errors had been detected to prevent their being deliverable to a
higher-layer protocol.  One possible reason for discarding such a packet could
be to free up buffer space."  (IF-MIB)

(B<ifInDiscards>) (B<ifOutDiscards>)

=item $info->i_bad_proto_in()

"For packet-oriented interfaces, the number of packets received via the
interface which were discarded because of an unknown or unsupported protocol.
For character-oriented or fixed-length interfaces that support protocol
multiplexing the number of transmission units received via the interface which
were discarded because of an unknown or unsupported protocol.  For any
interface that does not support protocol multiplexing, this counter will always
be 0."

(B<ifInUnknownProtos>)

=item $info->i_qlen_out()

"The length of the output packet queue (in packets)."

(B<ifOutQLen>)

=item $info->i_specific()

See IF-MIB for full description

(B<ifSpecific>)

=back

=head2 IP Address Table

Each entry in this table is an IP address in use on this device.  Usually 
this is implemented in Layer3 Devices.

=over

=item $info->ip_index()

Maps the IP Table to the IID

(B<ipAdEntIfIndex>)

=item $info->ip_table()

Maps the Table to the IP address

(B<ipAdEntAddr>)

=item $info->ip_netmask()

Gives netmask setting for IP table entry.

(B<ipAdEntNetMask>)

=item $info->ip_broadcast()

Gives broadcast address for IP table entry.

(B<ipAdEntBcastAddr>)

=back

=head2 IP Routing Table

=over

=item $info->ipr_route()

The route in question.  A value of 0.0.0.0 is the default gateway route.

(C<ipRouteDest>)

=item $info->ipr_if()

The interface (IID) that the route is on.  Use interfaces() to map.

(C<ipRouteIfIndex>)

=item $info->ipr_1()

Primary routing metric for this route. 

(C<ipRouteMetric1>)

=item $info->ipr_2()

If metrics are not used, they should be set to -1

(C<ipRouteMetric2>)

=item $info->ipr_3()

(C<ipRouteMetric3>)

=item $info->ipr_4()

(C<ipRouteMetric4>)

=item $info->ipr_5()

(C<ipRouteMetric5>)

=item $info->ipr_dest()

From RFC1213:

  "The IP address of the next hop of this route.
  (In the case of a route bound to an interface
  which is realized via a broadcast media, the value
  of this field is the agent's IP address on that
  interface.)"

(C<ipRouteNextHop>)

=item $info->ipr_type()

From RFC1213:

    other(1),        -- none of the following
    invalid(2),      -- an invalidated route
                     -- route to directly
    direct(3),       -- connected (sub-)network
                     -- route to a non-local
    indirect(4)      -- host/network/sub-network


      "The type of route.  Note that the values
      direct(3) and indirect(4) refer to the notion of
      direct and indirect routing in the IP
      architecture.

      Setting this object to the value invalid(2) has
      the effect of invalidating the corresponding entry
      in the ipRouteTable object.  That is, it
      effectively disassociates the destination
      identified with said entry from the route
      identified with said entry.  It is an
      implementation-specific matter as to whether the
      agent removes an invalidated entry from the table.
      Accordingly, management stations must be prepared
      to receive tabular information from agents that
      corresponds to entries not currently in use.
      Proper interpretation of such entries requires
      examination of the relevant ipRouteType object."

(C<ipRouteType>)

=item $info->ipr_proto()

From RFC1213:

    other(1),       -- none of the following
                    -- non-protocol information,
                    -- e.g., manually configured
    local(2),       -- entries
                    -- set via a network
    netmgmt(3),     -- management protocol
                    -- obtained via ICMP,
    icmp(4),        -- e.g., Redirect
                    -- the remaining values are
                    -- all gateway routing
                    -- protocols
    egp(5),
    ggp(6),
    hello(7),
    rip(8),
    is-is(9),
    es-is(10),
    ciscoIgrp(11),
    bbnSpfIgp(12),
    ospf(13),
    bgp(14)

(C<ipRouteProto>)

=item $info->ipr_age()

Seconds since route was last updated or validated.

(C<ipRouteAge>)

=item $info->ipr_mask()

Subnet Mask of route. 0.0.0.0 for default gateway.

(C<ipRouteMask>)

=item $info->ipr_info()

Reference to MIB definition specific to routing protocol.

(C<ipRouteInfo>)

=back

=head1 SETTING DATA VIA SNMP

This section explains how to use SNMP::Info to do SNMP Set operations.

=over

=item $info->set_METHOD($value)

Sets the global METHOD to value.  Assumes that iid is .0

Returns undef if failed, or the return value from SNMP::Session::set() (snmp_errno)

 $info->set_location("Here!");

=item $info->set_METHOD($value,$iid)

Table Methods. Set iid of method to value. 

Returns undef if failed, or the return value from SNMP::Session::set() (snmp_errno)

 # Disable a port administratively
 my %if_map = reverse %{$info->interfaces()}
 $info->set_i_up_admin('down', $if_map{'FastEthernet0/0'}) 
    or die "Couldn't disable the port. ",$info->error(1);

=back

NOTE: You must be connected to your device with a C<ReadWrite> community string in order
for set operations to work.

NOTE: This will only set data listed in %FUNCS and %GLOBALS.  For data acquired from
overriden methods (subroutines) specific set_METHOD() subroutines will need to be
added if they haven't been already.

=head1 Quiet Mode

SNMP::Info will not chirp anything to STDOUT unless there is a serious error (in which case it will probably
die).

To get lots of debug info, set the Debug flag when calling new() or call $info->debug(1);

When calling a method check the return value.  If the return value is undef then check $info->error()

Beware, calling $info->error() clears the error.

 my $name = $info->name() or die "Couldn't get sysName!" . $name->error();

=head1 EXTENDING SNMP::INFO

=head2 Data Structures required in new Subclass

A class inheriting this class must implement these data
structures : 

=over

=item  $INIT

Used to flag if the MIBs have been loaded yet.

=cut

$INIT    = 0;

=item %GLOBALS

Contains a hash in the form ( method_name => SNMP iid name )
These are scalar values such as name,uptime, etc. 

When choosing the name for the methods, be aware that other new
Sub Modules might inherit this one to get it's features.  Try to
choose a prefix for methods that will give it's own name space inside
the SNMP::Info methods.

=cut

%GLOBALS = (
            # from SNMPv2-MIB
            'id'           => 'sysObjectID',
            'description'  => 'sysDescr',
            'uptime'       => 'sysUpTime',
            'contact'      => 'sysContact',
            'name'         => 'sysName',
            'location'     => 'sysLocation',
            'layers'       => 'sysServices',
            'ports'        => 'ifNumber',
            'ipforwarding' => 'ipForwarding',
            );

=item %FUNCS

Contains a hash in the form ( method_name => SNMP iid)
These are table entries, such as the IfIndex

=cut

%FUNCS   = (
            'interfaces'         => 'ifIndex',
            'i_name'             => 'ifName',
            # IF-MIB::IfEntry
            'i_index'            => 'ifIndex',
            'i_description'      => 'ifDescr',
            'i_type'             => 'ifType',
            'i_mtu'              => 'ifMtu',
            'i_speed'            => 'ifSpeed',
            'i_mac'              => 'ifPhysAddress',
            'i_up_admin'         => 'ifAdminStatus',
            'i_up'               => 'ifOperStatus',
            'i_lastchange'       => 'ifLastChange',
            'i_octet_in'         => 'ifInOctets',
            'i_pkts_ucast_in'    => 'ifInUcastPkts',
            'i_pkts_nucast_in'   => 'ifInNUcastPkts',
            'i_discards_in'      => 'ifInDiscards',
            'i_errors_in'        => 'ifInErrors',
            'i_bad_proto_in'     => 'ifInUnknownProtos',
            'i_octet_out'        => 'ifOutOctets',
            'i_pkts_ucast_out'   => 'ifOutUcastPkts',
            'i_pkts_nucast_out'  => 'ifOutNUcastPkts',
            'i_discards_out'     => 'ifOutDiscards',
            'i_errors_out'       => 'ifOutErrors',
            'i_qlen_out'         => 'ifOutQLen',
            'i_specific'         => 'ifSpecific',
            # IP Address Table
            'ip_index'           => 'ipAdEntIfIndex',
            'ip_table'           => 'ipAdEntAddr',
            'ip_netmask'         => 'ipAdEntNetMask',
            'ip_broadcast'       => 'ipAdEntBcastAddr',
            # ifXTable - Extension Table
            'i_speed_high'       => 'ifHighSpeed',
            'i_pkts_multi_in'    => 'ifInMulticastPkts',
            'i_pkts_multi_out'   => 'ifOutMulticastPkts',
            'i_pkts_bcast_in'    => 'ifInBroadcastPkts',
            'i_pkts_bcast_out'   => 'ifOutBroadcastPkts',
            'i_octet_in64'       => 'ifHCInOctets',
            'i_octet_out64'      => 'ifHCOutOctets',
            'i_pkts_ucast_in64'  => 'ifHCInUcastPkts',
            'i_pkts_ucast_out64' => 'ifHCOutUcastPkts',
            'i_pkts_multi_in64'  => 'ifHCInMulticastPkts',
            'i_pkts_multi_out64' => 'ifHCOutMulticastPkts',
            'i_pkts_bcast_in64'  => 'ifHCInBroadcastPkts',
            'i_pkts_bcast_out64' => 'ifHCOutBroadcastPkts',
            'i_alias'            => 'ifAlias',
            # IP Routing Table
            'ipr_route'=> 'ipRouteDest',
            'ipr_if'   => 'ipRouteIfIndex',
            'ipr_1'    => 'ipRouteMetric1',
            'ipr_2'    => 'ipRouteMetric2',
            'ipr_3'    => 'ipRouteMetric3',
            'ipr_4'    => 'ipRouteMetric4',
            'ipr_5'    => 'ipRouteMetric5',
            'ipr_dest' => 'ipRouteNextHop',
            'ipr_type' => 'ipRouteType',
            'ipr_proto'=> 'ipRouteProto',
            'ipr_age'  => 'ipRouteAge',
            'ipr_mask' => 'ipRouteMask',
            'ipr_info' => 'ipRouteInfo',
           );

=item %MIBS

A list of each mib needed.  

('MIB-NAME' => 'itemToTestForPresence')

The value for each entry should be a MIB object to check for to make sure 
that the MIB is present and has loaded correctly. 

$info->init() will throw an exception if a MIB does not load. 

=cut

%MIBS    = (
            # The "main" MIBs are automagically loaded in Net-SNMP now.
           );

=item %MUNGE

A map between method calls (from %FUNCS or %GLOBALS) and subroutine methods.
The subroutine called will be passed the data as it gets it from SNMP and 
it should return that same data in a more human friendly format. 

Sample %MUNGE:

 (my_ip     => \&munge_ip,
  my_mac    => \&munge_mac,
  my_layers => \&munge_dec2bin
 )

=cut

%MUNGE   = ('ip'                 => \&munge_ip,
            'mac'                => \&munge_mac,
            'i_mac'              => \&munge_mac,
            'layers'             => \&munge_dec2bin,
            'i_speed'            => \&munge_speed,
            'i_speed_high'       => \&munge_highspeed,
            'i_octet_in64'       => \&munge_counter64,
            'i_octet_out64'      => \&munge_counter64,
            'i_pkts_ucast_in64'  => \&munge_counter64,
            'i_pkts_ucast_out64' => \&munge_counter64,
            'i_pkts_mutli_in64'  => \&munge_counter64,
            'i_pkts_multi_out64' => \&munge_counter64,
            'i_pkts_bcast_in64'  => \&munge_counter64,
            'i_pkts_bcast_out64' => \&munge_counter64,
            'i_up'               => \&munge_i_up,
            );

=back

=head2 Sample Subclass

Let's make a sample Layer 2 Device subclass.  This class
will inherit the Cisco Vlan module as an example.

----------------------- snip --------------------------------

 # SNMP::Info::Layer2::Sample

 package SNMP::Info::Layer2::Sample;

 $VERSION = 0.1;

 use strict;

 use Exporter;
 use SNMP::Info::Layer2;
 use SNMP::Info::CiscoVTP;

 @SNMP::Info::Layer2::Sample::ISA = qw/SNMP::Info::Layer2
                                       SNMP::Info::CiscoVTP Exporter/;
 @SNMP::Info::Layer2::Sample::EXPORT_OK = qw//;

 use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE $AUTOLOAD $INIT $DEBUG/;

 %MIBS    = (%SNMP::Info::Layer2::MIBS,
             %SNMP::Info::CiscoVTP::MIBS,
             'SUPER-DOOPER-MIB'  => 'supermibobject'
            );

 %GLOBALS = (%SNMP::Info::Layer2::GLOBALS,
             %SNMP::Info::CiscoVTP::GLOBALS,
             'name'              => 'supermib_supername',
             'favorite_color'    => 'supermib_fav_color_object',
             'favorite_movie'    => 'supermib_fav_movie_val'
             );

 %FUNCS   = (%SNMP::Info::Layer2::FUNCS,
             %SNMP::Info::CiscoVTP::FUNCS,
             # Super Dooper MIB - Super Hero Table
             'super_hero_index'  => 'SuperHeroIfIndex',
             'super_hero_name'   => 'SuperHeroIfName',
             'super_hero_powers' => 'SuperHeroIfPowers'
            );


 %MUNGE   = (%SNMP::Info::Layer2::MUNGE,
             %SNMP::Info::CiscoVTP::MUNGE,
             'super_hero_powers' => \&munge_powers
            );

 # OverRide uptime() method from %SNMP::Info::GLOBALS
 sub uptime {
     my $sample = shift;

     my $name   = $sample->name();

     # this is silly but you get the idea
     return '600' if defined $name ;
 }

 # Create our own munge function
 sub munge_powers {
     my $power = shift;

     # Take the returned obscure value and return something useful.
     return 'Fire' if $power =~ /reallyhot/i;
     return 'Ice'  if $power =~ /reallycold/i;

     # Else 
     return $power;
 }

 # Copious Documentation here!!!
 =head1 NAME
 =head1 AUTHOR
 =head1 SYNOPSIS
 =head1 DESCRIPTION
 =head2 Inherited Classes
 =head2 Required MIBs
 =head1 GLOBALS
 =head2 Overrides
 =head1 TABLE METHODS
 =head2 Overrides
 =cut

 1; # don't forget this line
----------------------- snip --------------------------------

Be sure and send the debugged version to snmp-info-users@lists.sourceforge.net to be 
included in the next version of SNMP::Info.

=head1 SNMP::INFO INTERNALS

=head2 Object Namespace

Internal data is stored with bareword keys. For example $info->{debug}

SNMP Data is stored or marked cached with keys starting with an underscore. 
For example $info->{_name} is the cache for $info->name().

Cached Table data is stored in $info->store() and marked cached per above.

=head2 Package Globals

These set the default value for an object upon creation.

=over

=item $DEBUG

Default 0.  Sends copious debug info to stdout.  This global sets the object's debug status
in new() unless 'Debug' argument passed in new().  Change objects' debug status with
$info->debug().

=cut

$DEBUG = 0;

=item $BIGINT

Default 0.   Set to true to have 64 bit counters return Math::BigInt objects instead of scalar
string values.  See note under Interface Statistics about 64 bit values.

=cut

$BIGINT = 0; 

=item $NOSUCH

Default 1.  Set to false to disable RetryNoSuch option for SNMP::Session.  Or see method in new()
to do it on an object scope.

=cut

$NOSUCH = 1;

=item $REPEATERS

Default 20.  MaxRepeaters for BULKWALK operations.  See C<perldoc SNMP> for more info.  Can change
by passing L<BulkRepeaters> option in new()

=cut

$REPEATERS = 20;

=back

=head2 Data Munging Callback Subroutines

=over

=item munge_speed()

Makes human friendly speed ratings using %SPEED_MAP

 %SPEED_MAP = (
                '56000'      => '56 kbps',
                '64000'      => '64 kbps',
                '115000'     => '115 kpbs',
                '1500000'    => '1.5 Mbps',
                '1536000'    => 'T1',      
                '1544000'    => 'T1',
                '2000000'    => '2.0 Mbps',
                '2048000'    => '2.048 Mbps',
                '3072000'    => 'Dual T1',
                '3088000'    => 'Dual T1',   
                '4000000'    => '4.0 Mbps',
                '10000000'   => '10 Mbps',
                '11000000'   => '11 Mbps',
                '20000000'   => '20 Mbps',
                '16000000'   => '16 Mbps',
                '16777216'   => '16 Mbps',
                '44210000'   => 'T3',
                '44736000'   => 'T3',
                '45000000'   => '45 Mbps',
                '45045000'   => 'DS3',
                '46359642'   => 'DS3',
                '51850000'   => 'OC-1',
                '54000000'   => '54 Mbps',
                '64000000'   => '64 Mbps',
                '100000000'  => '100 Mbps',
                '149760000'  => 'ATM on OC-3',
                '155000000'  => 'OC-3',
                '155519000'  => 'OC-3',
                '155520000'  => 'OC-3',
                '400000000'  => '400 Mbps',
                '599040000'  => 'ATM on OC-12', 
                '622000000'  => 'OC-12',
                '622080000'  => 'OC-12',
                '1000000000' => '1.0 Gbps',
                '2488000000' => 'OC-48',
             )

=cut

%SPEED_MAP = (
                '56000'      => '56 kbps',
                '64000'      => '64 kbps',
                '115000'     => '115 kpbs',
                '1500000'    => '1.5 Mbps',
                '1536000'    => 'T1',      
                '1544000'    => 'T1',
                '2000000'    => '2.0 Mbps',
                '2048000'    => '2.048 Mbps',
                '3072000'    => 'Dual T1',
                '3088000'    => 'Dual T1',   
                '4000000'    => '4.0 Mbps',
                '10000000'   => '10 Mbps',
                '11000000'   => '11 Mbps',
                '20000000'   => '20 Mbps',
                '16000000'   => '16 Mbps',
                '16777216'   => '16 Mbps',
                '44210000'   => 'T3',
                '44736000'   => 'T3',
                '45000000'   => '45 Mbps',
                '45045000'   => 'DS3',
                '46359642'   => 'DS3',
                '51850000'   => 'OC-1',
                '54000000'   => '54 Mbps',
                '64000000'   => '64 Mbps',
                '100000000'  => '100 Mbps',
                '149760000'  => 'ATM on OC-3',
                '155000000'  => 'OC-3',
                '155519000'  => 'OC-3',
                '155520000'  => 'OC-3',
                '400000000'  => '400 Mbps',
                '599040000'  => 'ATM on OC-12', 
                '622000000'  => 'OC-12',
                '622080000'  => 'OC-12',
                '1000000000' => '1.0 Gbps',
                '2488000000' => 'OC-48',
             );

sub munge_speed {
    my $speed = shift;
    my $map   = $SPEED_MAP{$speed};

    #print "  $speed -> $map  " if (defined $map); 
    return $map || $speed;
}

=item munge_highspeed()

Makes human friendly speed ratings for ifHighSpeed

=cut

sub munge_highspeed {
    my $speed = shift;
    my $fmt = "%d Mbps";

    if ($speed > 9999999) {
        $fmt = "%d Tbps";
	$speed /= 1000000;
    } elsif ($speed > 999999) {
        $fmt = "%.1f Tbps";
        $speed /= 1000000.0;
    } elsif ($speed > 9999) {
        $fmt = "%d Gbps";
	$speed /= 1000;
    } elsif ($speed > 999) {
	$fmt = "%.1f Gbps";
	$speed /= 1000.0;
    }
    return sprintf($fmt, $speed);
}

=item munge_ip() 

Takes a binary IP and makes it dotted ASCII

=cut

sub munge_ip {
    my $ip = shift;
    return join('.',unpack('C4',$ip));
}

=item munge_mac()

Takes an octet stream (HEX-STRING) and returns a colon separated ASCII hex string.

=cut

sub munge_mac {
    my $mac = shift;
    return undef unless defined $mac;
    return undef unless length $mac;
    $mac = join(':',map { sprintf "%02x",$_ } unpack('C*',$mac));
    return $mac if $mac =~ /^([0-9A-F][0-9A-F]:){5}[0-9A-F][0-9A-F]$/i;
    return undef;
}

=item munge_prio_mac()

Takes an 8-byte octet stream (HEX-STRING) and returns a colon separated ASCII hex string.

=cut

sub munge_prio_mac {
    my $mac = shift;
    return undef unless defined $mac;
    return undef unless length $mac;
    $mac = join(':',map { sprintf "%02x",$_ } unpack('C*',$mac));
    return $mac if $mac =~ /^([0-9A-F][0-9A-F]:){7}[0-9A-F][0-9A-F]$/i;
    return undef;
}

=item munge_octet2hex()

Takes a binary octet stream and returns an ASCII hex string

=cut

sub munge_octet2hex {
    my $oct = shift;
    return join('',map {sprintf "%x",$_} unpack('C*',$oct));
}

=item munge_dec2bin()

Takes a binary char and returns its ASCII binary representation

=cut

sub munge_dec2bin {
    my $num = shift;
    return undef unless defined $num;
    #return undef unless length($num);
    $num = unpack("B32",pack("N",$num));

    # return last 8 characters only
    $num =~ s/.*(.{8})$/$1/;
    return $num
}

=item munge_bits

Takes a SNMP2 'BITS' field and returns the ASCII bit string

=cut

sub munge_bits {
    my $bits = shift;
    return undef unless defined $bits;

    return unpack("b*",$bits);
}

=item munge_counter64

If $BIGINT is set to true, then a Math::BigInt object is returned.
See Math::BigInt for details.

=cut

sub munge_counter64 {
    my $counter = shift;
    return unless defined $counter;
    return $counter unless $BIGINT;
    my $bigint = Math::BigInt->new($counter);
    return $bigint;
}

=item munge_i_up

There is a collision between data in IF-MIB and RFC-1213. 
For devices that fully implement IF-MIB it might return 7 for 
a port that is down.  This munges the data against the IF-MIB 
by hand.

TODO: Get the precidence of MIBs and overriding of MIB data in Net-SNMP
figured out.  Heirarchy/precendence of MIBS in SNMP::Info.

=cut

sub munge_i_up {
    my $i_up = shift;
    return unless defined $i_up;

    $i_up = 'down' if $i_up eq '7';

    return $i_up;
}

=back

=head2 Internaly Used Functions

=over

=item $info->init()

Used internally.  Loads all entries in %MIBS.

=cut

sub init {
    my $self = shift;

    &SNMP::initMib;
    
    my $version = $SNMP::VERSION;
    my ($major,$minor,$rev) = split('\.',$version);

    if ($major < 5){
        # Seems to work under 4.2.0
    } elsif ($major == 5 and $minor == 0 and $rev < 2){
        carp("Net-SNMP 5.0.1 seems to be rather buggy. Upgrade.\n");
        # This is a bug in net-snmp 5.0.1 perl module
        # see http://groups.google.com/groups?th=47aed6bf7be6a0f5
        &SNMP::init_snmp("perl");
    }
    
    # Add MibDirs
    my $mibdirs = $self->{mibdirs} || [];
    
    foreach my $d (@$mibdirs){
        next unless -d $d;
        print "SNMP::Info::init() - Adding new mibdir:$d\n" if $self->debug(); 
        &SNMP::addMibDirs($d);
    }
    
    my $mibs = $self->mibs();
    
    foreach my $mib (keys %$mibs){
        #print "SNMP::Info::init() - Loading mib:$mib\n" if $self->debug(); 
        &SNMP::loadModules("$mib");

        unless (defined $SNMP::MIB{$mibs->{$mib}}){
            croak "The $mib did not load. See README for $self->{class}\n";
        }    
    }
}

=item $info->args()

Returns a reference to the argument hash supplied to SNMP::Session

=cut

sub args {
    my $self = shift;
    return $self->{args};
}

=item $info->class()

Returns the class name of the object.

=cut

sub class {
    my $self=shift;
    return $self->{class};
}

=item $info->error_throw(error message)

Stores the error message for use by $info->error()

If $info->debug() is true, then the error message is carped too.

=cut

sub error_throw {
    my $self = shift;
    my $error = shift;

    return undef unless defined $error;
    $self->{error} = $error;

    if ($self->debug()){
        $error =~  s/\n+$//;
        carp($error);
    }
}

=item $info->funcs()

Returns a reference to the %FUNCS hash.

=cut

sub funcs {
    my $self=shift;
    return $self->{funcs};
}

=item $info->globals()

Returns a reference to the %GLOBALS hash.

=cut

sub globals {
    my $self=shift;
    return $self->{globals};
}

=item $info->mibs()

Returns a reference to the %MIBS hash.

=cut

sub mibs {
    my $self=shift;
    return $self->{mibs};
}

=item $info->munge()

Returns a reference ot the %MUNGE hash.

=cut

sub munge {
    my $self=shift;
    return $self->{munge};
}

=item $info->nosuch()

Returns NoSuch value set or not in new()

=cut

sub nosuch {
    my $self = shift;
    return $self->{nosuch};
}

=item $info->session()

Gets or Sets the SNMP::Session object.

=cut

sub session {
    my $self = shift;
    $self->{sess} = $_[0] if @_;
    return $self->{sess};
}

=item $info->store(new_store)

Returns or sets hash store for Table functions.

Store is a hash reference in this format :

$info->store = { attribute => { iid => value , iid2 => value2, ... } };

=cut

sub store {
    my $self = shift;
    $self->{store} = $_[0] if @_;
    return $self->{store};
}

=item $info->_global()

Used internally by AUTOLOAD to load dynamic methods from %GLOBALS. 

Example: $info->name() calls autoload which calls $info->_global('name').

=cut

sub _global{
    my $self = shift;
    my $attr = shift;
    my $sess = $self->session();
    return undef unless defined $sess;

    my $globals = $self->globals(); 

    my $oid;
    if (exists $globals->{$attr}) {
        $oid = $globals->{$attr};
    }
    else {
        $oid = $attr;
    }

    # Tag on .0 unless the leaf ends in .number
    unless ($oid =~ /\.\d+$/) {
        $oid .= ".0";
    }

    print "SNMP::Info::_global $attr : $oid\n" if $self->debug();
    my $val = $sess->get($oid); 

    # mark as gotten. Even if it fails below, we don't want to keep failing.
    $self->{"_$attr"}=undef;

    if ($sess->{ErrorStr} ){
        $self->error_throw("SNMP::Info::_global($attr) $sess->{ErrorStr}");
        return undef;
    }

    if (defined $val and $val eq 'NOSUCHOBJECT'){
        $self->error_throw("SNMP::Info::_global($attr) NOSUCHOBJECT");
        return undef;
    }

    if (defined $val and $val eq 'NOSUCHINSTANCE'){
        $self->error_throw("SNMP::Info::_global($attr) NOSUCHINSTANCE");
        return undef;
    }
    # Get the callback hash for data munging
    my $munge = $self->munge();

    # Data Munging
    if (defined $munge->{$attr}){
        my $subref = $munge->{$attr};
        $val = &$subref($val);
    } 

    # Save Cached Value
    $self->{"_$attr"} = $val;

    return $val;
}

=item $info->_set(attr,val,iid)

Used internally by AUTOLOAD to run an SNMP set command for dynamic methods
listed in either %GLOBALS or %FUNCS or a valid mib leaf from a loaded MIB.
Clears attr cache on sucessful set.

Example:  $info->set_name('dog',3) uses autoload to resolve to
$info->_set('name','dog',3);

=cut

sub _set {
    my ($self,$attr,$val,$iid) = @_;

    $iid = defined $iid ? $iid : '.0';
    # prepend dot if necessary to $iid
    $iid = ".$iid" unless $iid =~ /^\./;

    my $sess = $self->session();
    return undef unless defined $sess;

    my $funcs = $self->funcs();
    my $globals = $self->globals(); 

    # Check if this method is from a sub or from the tables.
    if ($self->can($attr)){
        $self->error_throw("SNMP::Info::_set($attr,$val) - Failed. $attr is generated in a sub(). set_$attr sub required.");
        # if sub set_attr() existed, we wouldn't have gotten this far.
        return undef;
    }

    # Lookup oid
    my $oid = undef;
    $oid = $attr if SNMP::translateObj($attr);
    $oid = $globals->{$attr} if defined $globals->{$attr};
    $oid = $funcs->{$attr} if defined $funcs->{$attr};

    unless (defined $oid) { 
        $self->error_throw("SNMP::Info::_set($attr,$val) - Failed to find $attr in \%GLOBALS or \%FUNCS or loaded MIB.");
        return undef;
    }

    $oid .= $iid;
    $oid = &SNMP::translateObj($oid);

    $self->debug() and print "SNMP::Info::_set $attr$iid ($oid) = $val\n";

    my $rv = $sess->set($oid,$val);

    if ($sess->{ErrorStr}){
        $self->error_throw("SNMP::Info::_set $attr$iid $sess->{ErrorStr}");
        return undef;
    }

    delete $self->{"_$attr"};
    return $rv;
}

=item $info->load_all()

Debugging routine.  This does not include any overriden method or method implemented 
by subroutine.

Runs $info->load_METHOD() for each entry in $info->funcs();

Returns $info->store() -- See store() entry.

Note return value has changed since version 0.3

=cut

sub load_all {
    my $self = shift;
    my $sess = $self->session();
    return undef unless defined $sess;

    my $funcs = $self->funcs();
    
    foreach my $attrib (keys %$funcs) {
      $attrib = "load_$attrib";
      $self->$attrib(); 
    }

    $self->{_all}++;

    return $self->store() if defined wantarray;
}

=item $info->all()

Runs $info->load_all() once then returns $info->store();

Use $info->load_all() to reload the data.

Note return value has changed since version 0.3

=cut

sub all {
    my $self = shift;
    my $sess = $self->session();
    return undef unless defined $sess;

    $self->load_all() unless defined $self->{_all};

    return $self->store();    
}

=item $info->_load_attr()

Used internally by AUTOLOAD to fetch data called from methods listed in %FUNCS
or a MIB Leaf node name.

Supports partial table fetches and single instance table fetches.
See L<SNMP::Info/"Partial Table Fetches">.

Called from $info->load_METHOD();

=cut

sub _load_attr {
    my $self = shift;
    my ($attr,$leaf,$partial) = @_;

    my $ver    = $self->snmp_ver();
    my $nosuch = $self->nosuch();
    my $sess   = $self->session();
    my $store  = $self->store();
    my $munge  = $self->munge();
    return undef unless defined $sess;

    # Deal with partial entries.
    my $varleaf = $leaf;
    if (defined $partial) {
        # If we aren't supplied an OID translate
        if ($leaf !~ /^[.\d]*$/) {
            # VarBind will not resolve mixed OID and leaf entries like
            #   "ipRouteMask.255.255".  So we convert to full OID
            my $oid = &SNMP::translateObj($leaf);
            unless (defined $oid) {
                $self->error_throw("SNMP::Info::_load_attr: Can't translate $leaf.$partial.  Missing MIB?\n");
                return undef;
            }
            $varleaf = "$oid.$partial";
        } else {
            $varleaf = "$leaf.$partial";
        }
    }

    $self->debug() and print "SNMP::Info::_load_attr $attr : $leaf", 
        defined $partial ? "($partial / $varleaf)" : '', "\n";

    my $var = new SNMP::Varbind([$varleaf]);

    # So devices speaking SNMP v.1 are not supposed to give out 
    # data from SNMP2, but most do.  Net-SNMP, being very precise 
    # will tell you that the SNMP OID doesn't exist for the device.
    # They have a flag RetryNoSuch that is used for get() operations,
    # but not for getnext().  We set this flag normally, and if we're
    # using V1, let's try and fetch the data even if we get one of those.

#  This code is causing problems if we have an error from any other SNMP
#  operation in the same SNMP session, $sess->{ErrorNum} will still contain
#  the last error.  We have not yet performed a get or getnext operation
#  so if this code is needed, not sure it is at the correct location???
#    my $errornum = $sess->{ErrorNum};
#    if ($ver == 1 and $nosuch and $errornum and $sess->{ErrorStr} =~ /nosuch/i){
#        $errornum = 0; 
#    } elsif ($errornum){
#        $self->error_throw("SNMP::Info::_load_attr: Varbind $varleaf ".$sess->{ErrorStr}."\n");
#        return undef;
#    }

    my $localstore = undef;
    my $errornum = 0;
    my %seen   = ();

    my $vars = [];
    my $bulkwalk_no  = $self->can('bulkwalk_no') ? $self->bulkwalk_no() : 0;
    my $bulkwalk_on  = defined $self->{BulkWalk} ? $self->{BulkWalk} : 1;
    my $can_bulkwalk = $bulkwalk_on && !$bulkwalk_no;
    my $repeaters    = $self->{BulkRepeaters} || $REPEATERS;
    my $bulkwalk     = $can_bulkwalk && $ver != 1;
    my $loopdetect   = defined $self->{LoopDetect} ? $self->{LoopDetect} : 1;

    if (defined $partial) {
	# Try a GET, in case the partial is a leaf OID.
	# Would like to only do this if we know the OID is
	# long enough; implementing that would require a
	# lot of MIB mucking.
	my $try = $sess->get($var);
        $errornum = $sess->{ErrorNum};
	if (defined($try) && $errornum == 0 && $try !~ /^NOSUCH/) {
	    $var->[2] = $try;
	    $vars = [ $var ];
	    $bulkwalk = 1;	# fake a bulkwalk return
        }
        # We want to execute the while loop below for the getnext request.
        if ($ver == 1 and $sess->{ErrorNum} and $sess->{ErrorStr} =~ /nosuch/i){
            $errornum = 0;
	}
    }

    # Use BULKWALK if we can because its faster
    if ($bulkwalk && @$vars == 0){
        ($vars) = $sess->bulkwalk(0, $repeaters, $var);
        if($sess->{ErrorNum}) {
            $self->error_throw("SNMP::Info::_load_atrr: BULKWALK ".$sess->{ErrorStr},"\n");
            return undef;
        }
    }

    while (! $errornum ){
        if ($bulkwalk){
            $var = shift @$vars or last;
        } else {
            # GETNEXT instead of BULKWALK
            $sess->getnext($var);
            $errornum = $sess->{ErrorNum};
        }

        if ($self->debug() > 1) {
            use Data::Dumper;
            print "SNMP::Info::_load_attr $attr : leaf = $leaf , var = ", Dumper($var);
        }

        # Check if we've left the requested subtree
        last if $var->[0] ne $leaf;
        my $iid = $var->[1];
        my $val = $var->[2];

        unless (defined $iid){
            $self->error_throw("SNMP::Info::_load_attr: $attr not here");
            next;
        }

        if ($loopdetect){
        # Check to see if we've already seen this IID (looping)
            if (defined $seen{$iid} and $seen{$iid}){
                $self->error_throw("Looping on: $attr iid:$iid. ");
                last;
            }
            else {
                $seen{$iid}++;
            }
        }

        # Check to make sure we are still in partial land
        if (defined $partial and $iid !~ /^$partial$/ and $iid !~ /^$partial\./){
            $self->debug() and print "$iid makes us leave partial land.\n";
            last;
        }

        # Check if last element, V2 devices may report ENDOFMIBVIEW even if
        # instance or object doesn't exist.
        if ($val eq 'ENDOFMIBVIEW'){
            last;
        }
        # Similarly for SNMPv1 - noSuchName return results in both $iid
        # and $val being empty strings.
        if ($val eq '' and $iid eq ''){
            last;
        }

        if ($val eq 'NOSUCHOBJECT'){
            $self->error_throw("SNMP::Info::_load_attr: $attr :  NOSUCHOBJECT");
            next;
        }
        if ($val eq 'NOSUCHINSTANCE'){
            $self->error_throw("SNMP::Info::_load_attr: $attr :  NOSUCHINSTANCE");
            next;
        }

        # Data Munging
        #   Checks for an entry in %munge and runs the subroutine
        if (defined $munge->{$attr}){
            my $subref = $munge->{$attr};
            $val = &$subref($val);
        } 

        $localstore->{$iid}=$val;
    } 

    # Cache data if we are not getting partial data:
    if (!defined $partial){
        $self->{"_${attr}"}++;
        $store->{$attr}=$localstore;
    } 

    return $localstore;
}

=item $info->_show_attr()

Used internaly by AUTOLOAD to return data called by methods listed in %FUNCS.

Called like $info->METHOD().

The first time ran, it will call $info->load_METHOD().  
Every time after it will return cached data.

=cut

sub _show_attr {
    my $self = shift;
    my $attr = shift;

    my $store = $self->store();
    
    return $store->{$attr};
}

=item $info->snmp_connect_ip() 

Returns true or false based upon snmp connectivity to an IP.

=cut

sub snmp_connect_ip {
    my $self = shift;
    my $ip = shift;
    my $ver = $self->snmp_ver();
    my $comm = $self->snmp_comm();
    
    return undef if ($ip eq '0.0.0.0') or ($ip =~ /^127\./);
    
    # Create session object
    my $snmp_test = new SNMP::Session( 'DestHost' => $ip, 'Community' => $comm, 'Version' => $ver);

    # No session object created
    unless (defined $snmp_test){
        return undef;
    }
    
    # Session object created but SNMP connection failed.
    my $sess_err = $snmp_test->{ErrorStr} || '';
    if ($sess_err){
        return undef;
    }
    
    # Try to get some data from IP
    my $layers = $snmp_test->get('sysServices.0');
    
    $sess_err = $snmp_test->{ErrorStr} || '';
    if ($sess_err){
        return undef;
    }    

    return 1;

}

=back

=head2 AUTOLOAD

Each entry in either %FUNCS, %GLOBALS, or MIB Leaf node names present in
loaded MIBs are used by AUTOLOAD() to create dynamic methods.

Note that this AUTOLOAD is going to be run for all the classes listed in the
@ISA array in a subclass, so will be called with a variety of package names.
We check the %FUNCS and %GLOBALS of the package that is doing the calling at
this given instant.

=over 

=item 1. Returns unless method is listed in %FUNCS, %GLOBALS, or is MIB Leaf
node name in a loaded MIB for given class.

=item 2. Checks for load_ prefix and if present runs $info->_global(method)
for methods which exist in %GLOBALS or are a single instance MIB Leaf node
name, otherwise runs $info->_load_attr(method) for methods which exist in
%FUNCS or are MIB Leaf node name contained within a table.  This always
forces reloading and does not use cached data.

=item 3. Check for set_ prefix and if present runs $info->_set(method).

=item 4. If the method exists in %GLOBALS or is a single instance MIB Leaf
node name it runs $info->_global(method) unless already cached.

=item 5. If the method exists in %FUNCS or is MIB Leaf node name contained
within a table it runs $info->_load_attr(method) if not cached.

=item 6. Otherwise return $info->_show_attr(method).

=back

Override any dynamic method listed in one of these hashes by creating a
subroutine with the same name.

For example to override $info->name() create `` sub name {...}'' in your
subclass.

=cut

sub AUTOLOAD {
    my $self = shift;
    my $sub_name = $AUTOLOAD;

    return if $sub_name =~ /DESTROY$/;

    # package is the first part
    (my $package = $sub_name) =~ s/[^:]*$//;
    # Sub name is the last part
    $sub_name =~ s/.*://;
    #  Enable calls to SUPER class to find autoloaded methods
    $package =~ s/SUPER::$//;

    # Typos in function calls in SNMP::Info subclasses turn into
    # AUTOLOAD requests for non-methods.  While this is deprecated,
    # we'll still get called, so report a less confusing error.
    if (ref($self) !~ /^SNMP::Info/) {
        # croak reports one level too high.  die reports here.
        # I would really like to get the place that's likely to
        # have the typo, but perl doesn't want me to.
        croak("SNMP::Info::AUTOLOAD($AUTOLOAD) called with no class (probably typo of function call to $sub_name)");
    }

    my $attr = $sub_name;
    $attr =~ s/^(load|set)_//;
    $attr =~ s/^orig_//;
    
    # Let's use the %GLOBALS and %FUNCS from the class that 
    #   inherited us.
    my (%funcs,%globals);
    {
        no strict 'refs';
        %funcs = %{$package.'FUNCS'};
        %globals = %{$package.'GLOBALS'};
    }

    # Check if we were called with a MIB leaf node name 
    my $trans = SNMP::translateObj($attr);
    
    my $mib_leaf = 0;
    my $table_leaf = 0;
    if ( defined($trans) ) {
        my $mib = $SNMP::MIB{$trans};
        # We're not a leaf if we don't have access attribute
        # Don't bother if not-accessable
        my $access = $$mib{'access'};
        $mib_leaf = 1 if ( defined $access && $access !~ /NoAccess/ );
        if ($self->debug() and !$mib_leaf) {
            print "SNMP::Info::AUTOLOAD($attr) Leaf not accessable.\n";
        }
        # If we're a leaf check to see if we are in a table
        if ($mib_leaf) {
            my $indexes  = $$mib{'parent'}{'indexes'};
            $table_leaf = 1 if (defined $indexes && scalar( @{$indexes} ) > 0);
        }
    }

    unless( defined $funcs{$attr} or
            defined $globals{$attr} or
            defined $mib_leaf ) {
        $self->error_throw("SNMP::Info::AUTOLOAD($attr) Attribute not found in this device class.");
        return;
    }
    
    # Check for load_ ing.
    if ($sub_name =~ /^load_/){
        if ( defined $globals{$attr} ) {
            return $self->_global( $attr );
        }
        if ( defined $funcs{$attr} ) {
            return $self->_load_attr( $attr,$funcs{$attr},@_ );
        }
        if ( $mib_leaf and !$table_leaf ) {
            return $self->_global( $attr );
        }        
        if ( $table_leaf ) {
            return $self->_load_attr( $attr,$attr,@_ );
        }
    }

    # Check for set_ ing.
    if ($sub_name =~ /^set_/){
        return $self->_set( $attr, @_);
    }

    # Next check for entry in %GLOBALS
    if (defined $globals{$attr} or ( $mib_leaf and !$table_leaf )){
        # Return Cached Value if exists
        return $self->{"_${attr}"} if exists $self->{"_${attr}"};
        # Fetch New Value
        return $self->_global( $attr );
    }

    # Otherwise we must be listed in %FUNCS 

    # Load data if it both not cached and we are not requesting partial info.
    if ( defined $funcs{$attr} ) {
        return $self->_load_attr( $attr, $funcs{$attr},@_ )
            unless (defined $self->{"_${attr}"} and !scalar(@_));
    }
    if ( $table_leaf ) {
        return $self->_load_attr( $attr, $attr,@_ )
            unless (defined $self->{"_${attr}"} and !scalar(@_));
    }

    return $self->_show_attr($attr);
}
1;

=head1 COPYRIGHT AND LICENCE

Changes from SNMP::Info Version 0.7 and on are:
Copyright (c)2003, 2004 Max Baker - All rights reserved.

Original Code is:
Copyright (c) 2002-3, Regents of the University of California
All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Neither the name of the University of California, Santa Cruz nor the 
      names of its contributors may be used to endorse or promote products 
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
