# SNMP::Info::Layer3::Dell - SNMP Interface to Dell devices
# Eric Miller
#
# Copyright (c) 2006 Eric Miller
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

package SNMP::Info::Layer3::Dell;
# $Id: Dell.pm,v 1.7 2007/11/26 04:24:52 jeneric Exp $

use strict;

use Exporter;
use SNMP::Info::Layer3;

use vars qw/$VERSION $DEBUG %GLOBALS %FUNCS $INIT %MIBS %MUNGE/;

$VERSION = '1.07';

@SNMP::Info::Layer3::Dell::ISA = qw/SNMP::Info::Layer3 Exporter/;
@SNMP::Info::Layer3::Dell::EXPORT_OK = qw//;

%MIBS = ( %SNMP::Info::Layer3::MIBS,
          'RADLAN-Physicaldescription-MIB'   => 'rlPhdStackReorder',
          'RADLAN-rlInterfaces'              => 'rlIfNumOfLoopbackPorts',
          'RADLAN-HWENVIROMENT'              => 'rlEnvPhysicalDescription',
          'Dell-Vendor-MIB'                  => 'productIdentificationVersion',
        );

%GLOBALS = (
            %SNMP::Info::Layer3::GLOBALS,
            'os_ver'        => 'productIdentificationVersion',
            'dell_id_name'  => 'productIdentificationDisplayName',
           );

%FUNCS   = (
            %SNMP::Info::Layer3::FUNCS,
            # RADLAN-rlInterfaces:swIfTable
            'dell_duplex_admin' => 'swIfDuplexAdminMode',
            'dell_duplex'       => 'swIfDuplexOperMode',
            'dell_tag_mode'     => 'swIfTaggedMode',
            'dell_i_type'            => 'swIfType',
            'dell_fc_admin'     => 'swIfFlowControlMode',
            'dell_speed_admin'  => 'swIfSpeedAdminMode',
            'dell_auto'         => 'swIfSpeedDuplexAutoNegotiation',
            'dell_fc'           => 'swIfOperFlowControlMode',
            # RADLAN-Physicaldescription-MIB:rlPhdUnitGenParamTable
            'dell_unit'      => 'rlPhdUnitGenParamStackUnit',
            'dell_sw_ver'    => 'rlPhdUnitGenParamSoftwareVersion',           
            'dell_fw_ver'    => 'rlPhdUnitGenParamFirmwareVersion',
            'dell_hw_ver'    => 'rlPhdUnitGenParamHardwareVersion',
            'dell_serial_no' => 'rlPhdUnitGenParamSerialNum',
            'dell_asset_no'  => 'rlPhdUnitGenParamAssetTag',
            # RADLAN-COPY-MIB:rlCopyTable
            'dell_cp_idx'     => 'rlCopyIndex',
            'dell_cp_sloc'    => 'rlCopySourceLocation',           
            'dell_cp_sip'     => 'rlCopySourceIpAddress',
            'dell_cp_sunit'   => 'rlCopySourceUnitNumber',
            'dell_cp_sfile'   => 'rlCopySourceFileName',
            'dell_cp_stype'   => 'rlCopySourceFileType',
            'dell_cp_dloc'    => 'rlCopyDestinationLocation',
            'dell_cp_dip'     => 'rlCopyDestinationIpAddress',           
            'dell_cp_dunit'   => 'rlCopyDestinationUnitNumber',
            'dell_cp_dfile'   => 'rlCopyDestinationFileName',
            'dell_cp_dtype'   => 'rlCopyDestinationFileType',
            'dell_cp_state'   => 'rlCopyOperationState',
            'dell_cp_bkgnd'   => 'rlCopyInBackground',
            'dell_cp_rstatus' => 'rlCopyRowStatus',
            # RADLAN-HWENVIROMENT:rlEnvMonSupplyStatusTable
            'dell_pwr_src'    => 'rlEnvMonSupplySource',
            'dell_pwr_state'  => 'rlEnvMonSupplyState',           
            'dell_pwr_desc'   => 'rlEnvMonSupplyStatusDescr',
            # RADLAN-HWENVIROMENT:rlEnvMonFanStatusTable
            'dell_fan_state' => 'rlEnvMonFanState',
            'dell_fan_desc'  => 'rlEnvMonFanStatusDescr',
           );


%MUNGE = (
            %SNMP::Info::Layer3::MUNGE,
         );

# Method OverRides

sub bulkwalk_no { 1; }

sub model {
    my $dell = shift;

    my $name = $dell->dell_id_name();
    
    if ($name =~ m/(\d+)/){
        return $1;
    }

    return undef;
}

sub vendor {

    return 'dell';
}

sub os {

    return 'dell';
}

sub serial {
    my $dell    = shift;

    my $numbers = $dell->dell_serial_no();
    
    foreach my $key (keys %$numbers){
        my $serial = $numbers->{$key};  
        return $serial if (defined $serial and $serial !~ /^\s*$/);
        next;
    }

    return undef;
}

# Descriptions are all the same, so use name instead
sub interfaces {
    my $dell = shift;
    my $partial = shift;

    my $interfaces = $dell->i_index($partial) || {};
    my $names = $dell->orig_i_name($partial) || {};

    my %interfaces = ();
    foreach my $iid (keys %$interfaces){
        my $name = $names->{$iid};
        next unless defined $name;

        $interfaces{$iid} = $name;
    }
    
    return \%interfaces;
}

sub i_duplex_admin {
    my $dell = shift;
    my $partial = shift;
    
    my $interfaces  = $dell->interfaces($partial) || {};
    my $dell_duplex = $dell->dell_duplex_admin($partial) || {};
    my $dell_auto   = $dell->dell_auto($partial) || {};
 
    my %i_duplex_admin;
    foreach my $if (keys %$interfaces){
        my $duplex = $dell_duplex->{$if};
        next unless defined $duplex;
        my $auto = $dell_auto->{$if}||'false';
    
        $duplex = 'half' if ($duplex =~ /half/i and $auto =~ /false/i);
        $duplex = 'full' if ($duplex =~ /half/i and $auto =~ /false/i);
        $duplex = 'auto' if $auto =~ /true/i;
        $i_duplex_admin{$if}=$duplex; 
    }
    return \%i_duplex_admin;
}

# Normal BRIDGE-MIB not working?  Use Q-BRIDGE-MIB for macsuck
sub fw_mac {
    my $dell = shift;
    my $partial = shift;

    return $dell->qb_fw_mac($partial);
}

sub fw_port {
    my $dell = shift;
    my $partial = shift;

    return $dell->qb_fw_port($partial);
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::Dell - SNMP Interface to Dell Power Connect Network Devices

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $dell = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $dell->class();

 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from an 
Dell Power Connect device through SNMP. 

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

my $dell = new SNMP::Info::Layer3::Dell(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item Dell-Vendor-MIB

=item RADLAN-Physicaldescription-MIB

=item RADLAN-rlInterfaces

=item RADLAN-HWENVIROMENT

=item Inherited Classes' MIBs

See classes listed above for their required MIBs.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $dell->os_ver()

(B<productIdentificationVersion>)

=item $dell->dell_id_name()

(B<productIdentificationDisplayName>)

=item $dell->model()

Returns model type.  Returns numeric from (B<productIdentificationDisplayName>).

=item $dell->vendor()

Returns dell

=item $dell->os()

Returns dell

=back

=head2 Overrides

=over

=item $dell->bulkwalk_no

Return C<1>.  Bulkwalk is currently turned off for this class.

=item $dell->serial()

Returns serial number. (B<rlPhdUnitGenParamSerialNum>)

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 RADLAN Interface Table (B<swIfTable>)

=over

=item $dell->dell_duplex_admin()

(B<swIfDuplexAdminMode>)

=item $dell->dell_duplex()

(B<swIfDuplexOperMode>)

=item $dell->dell_tag_mode()

(B<swIfTaggedMode>)

=item $dell->dell_i_type()

(B<swIfType>)

=item $dell->dell_fc_admin()

(B<swIfFlowControlMode>)

=item $dell->dell_speed_admin()

(B<swIfSpeedAdminMode>)

=item $dell->dell_auto()

(B<swIfSpeedDuplexAutoNegotiation>)

=item $dell->dell_fc()

(B<swIfOperFlowControlMode>)

=back

=head2 Overrides

=over

=item $dell->interfaces()

Returns the map between SNMP Interface Identifier (iid) and physical port name.
Uses name instead of description since descriptions are not unique.

Only returns those iids that have a name listed in $l3->i_name()

=item $dell->i_duplex_admin()

Returns reference to hash of iid to current link administrative duplex setting.

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=cut
