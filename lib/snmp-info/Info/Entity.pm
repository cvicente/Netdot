# SNMP::Info::Entity
# $Id: Entity.pm,v 1.23 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2008 Max Baker changes from version 0.8 and beyond.
#
# Copyright (c) 2003 Regents of the University of California
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

package SNMP::Info::Entity;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::Entity::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::Entity::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( 'ENTITY-MIB' => 'entPhysicalSerialNum' );

%GLOBALS = ();

%FUNCS = (
    'e_alias'  => 'entPhysicalAlias',
    'e_class'  => 'entPhysicalClass',
    'e_descr'  => 'entPhysicalDescr',
    'e_fwver'  => 'entPhysicalFirmwareRev',
    'e_fru'    => 'entPhysicalIsFRU',
    'e_hwver'  => 'entPhysicalHardwareRev',
    'e_id'     => 'entPhysicalAssetID',
    'e_map'    => 'entAliasMappingIdentifier',
    'e_model'  => 'entPhysicalModelName',
    'e_name'   => 'entPhysicalName',
    'e_parent' => 'entPhysicalContainedIn',
    'e_pos'    => 'entPhysicalParentRelPos',
    'e_serial' => 'entPhysicalSerialNum',
    'e_swver'  => 'entPhysicalSoftwareRev',
    'e_type'   => 'entPhysicalVendorType',
    'e_vendor' => 'entPhysicalMfgName',
);

%MUNGE = ( 'e_type' => \&SNMP::Info::munge_e_type, );

# entPhysicalIndex is not-accessible.  Create to facilitate emulation methods
# in other classes

sub e_index {
    my $entity  = shift;
    my $partial = shift;

    # Force use of MIB leaf to avoid inheritance issues in psuedo classes
    my $e_descr = $entity->entPhysicalDescr($partial);

    return unless ($e_descr);

    my %e_index;

    foreach my $iid ( keys %$e_descr ) {
        $e_index{$iid} = $iid;
    }
    return \%e_index;
}

sub e_port {
    my $entity  = shift;
    my $partial = shift;

    my $e_map = $entity->e_map($partial);

    my %e_port;

    foreach my $e_id ( keys %$e_map ) {
        my $id = $e_id;
        $id =~ s/\.0$//;

        my $iid = $e_map->{$e_id};
        $iid =~ s/.*\.//;

        $e_port{$id} = $iid;
    }

    return \%e_port;
}

1;

__END__

=head1 NAME

SNMP::Info::Entity - SNMP Interface to data stored in F<ENTITY-MIB>. RFC 2737

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $entity = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $entity->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

F<ENTITY-MIB> is used by Layer 2 devices from HP, Aironet, Foundry, Cisco,
and more.

See RFC 2737 for full details.

Create or use a device subclass that inherit this class.  Do not use directly.

For debugging purposes you can call this class directly as you would
SNMP::Info

 my $entity = new SNMP::Info::Entity (...);

=head2 Inherited Classes

none.

=head2 Required MIBs

=over

=item F<ENTITY-MIB>

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBALS

none.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Entity Table

=over

=item $entity->e_index()

Index

(C<entPhysicalIndex>)

=item $entity->e_alias()

Human entered, not usually used.

(C<entPhysicalAlias>)

=item $entity->e_class()

Stack, Module, Container, Port ...

(C<entPhysicalClass>)

=item $entity->e_descr()

Human Friendly

(C<entPhysicalClass>)

=item $entity->e_fwver()

(C<entPhysicalFirmwareRev>)

=item $entity->e_fru()

BOOLEAN. Field Replaceable unit?

(C<entPhysicalFRU>)

=item $entity->e_hwver()

(C<entPhysicalHardwareRev>)

=item $entity->e_id()

This is human entered and not normally used.

(C<entPhysicalAssetID>)

=item $entity->e_map()

See MIB.

(C<entAliasMappingIdentifier>)

=item $entity->e_model()

Model Name of Entity.

(C<entPhysicalModelName>)

=item $entity->e_name()

More computer friendly name of entity.  Parse me.

(C<entPhysicalName>)

=item $entity->e_parent()

0 if root.

(C<entPhysicalContainedIn>)

=item $entity->e_port()

Maps Entity Table entries to the Interface Table (C<IfTable>) using
$entity->e_map()

=item $entity->e_pos()

The relative position among all entities sharing the same parent.

(C<entPhysicalParentRelPos>)

=item $entity->e_serial()

(C<entPhysicalSerialNum>)

=item $entity->e_swver()

(C<entPhysicalSoftwareRev>)

=item $entity->e_type()

This is an OID, which gets munged into the object name if the right
MIB is loaded.

(C<entPhysicalVendorType>)

=item $entity->e_vendor()

Vendor of Module.

(C<entPhysicalMfgName>)

=back

=cut
