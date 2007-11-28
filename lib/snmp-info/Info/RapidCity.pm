# SNMP::Info::RapidCity
# $Id: RapidCity.pm,v 1.13 2007/11/26 04:24:51 jeneric Exp $
#
# Copyright (c) 2004 Eric Miller, Max Baker
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

package SNMP::Info::RapidCity;
$VERSION = '1.07';
use strict;

use Exporter;
use SNMP::Info;

@SNMP::Info::RapidCity::ISA = qw/SNMP::Info Exporter/;
@SNMP::Info::RapidCity::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

%MIBS    = (
            'RAPID-CITY' => 'rapidCity',
            );

%GLOBALS = (
            'rc_serial'    => 'rcChasSerialNumber',
            'chassis'      => 'rcChasType',
            'slots'        => 'rcChasNumSlots',
            'tftp_host'    => 'rcTftpHost',
            'tftp_file'    => 'rcTftpFile',
            'tftp_action'  => 'rcTftpAction',
            'tftp_result'  => 'rcTftpResult',
            'rc_ch_rev'    => 'rcChasHardwareRevision',
            'rc_base_mac'  => 'rc2kChassisBaseMacAddr',
            'rc_virt_ip'   => 'rcSysVirtualIpAddr',
            'rc_virt_mask' => 'rcSysVirtualNetMask',
            );

%FUNCS  = (
            # From RAPID-CITY::rcPortTable
            'rc_index'          => 'rcPortIndex',
            'rc_duplex'         => 'rcPortOperDuplex',
            'rc_duplex_admin'   => 'rcPortAdminDuplex',
            'rc_speed_admin'    => 'rcPortAdminSpeed',
            'rc_auto'           => 'rcPortAutoNegotiate',
            'rc_alias'          => 'rcPortName',
            # From RAPID-CITY::rc2kCpuEthernetPortTable
            'rc_cpu_ifindex'        => 'rc2kCpuEthernetPortIfIndex',
            'rc_cpu_admin'         => 'rc2kCpuEthernetPortAdminStatus',
            'rc_cpu_oper'          => 'rc2kCpuEthernetPortOperStatus',
            'rc_cpu_ip'            => 'rc2kCpuEthernetPortAddr',
            'rc_cpu_mask'          => 'rc2kCpuEthernetPortMask',
            'rc_cpu_auto'          => 'rc2kCpuEthernetPortAutoNegotiate',
            'rc_cpu_duplex_admin'  => 'rc2kCpuEthernetPortAdminDuplex',
            'rc_cpu_duplex'        => 'rc2kCpuEthernetPortOperDuplex',
            'rc_cpu_speed_admin'   => 'rc2kCpuEthernetPortAdminSpeed',
            'rc_cpu_speed_oper'    => 'rc2kCpuEthernetPortOperSpeed',
            'rc_cpu_mac'           => 'rc2kCpuEthernetPortMgmtMacAddr',
            # From RAPID-CITY::rcVlanPortTable
            'rc_i_vlan_if'      => 'rcVlanPortIndex',
            'rc_i_vlan_num'     => 'rcVlanPortNumVlanIds',
            'rc_i_vlan'         => 'rcVlanPortVlanIds',
            'rc_i_vlan_type'    => 'rcVlanPortType',
            'rc_i_vlan_pvid'    => 'rcVlanPortDefaultVlanId',
            'rc_i_vlan_tag'     => 'rcVlanPortPerformTagging',
            # From RAPID-CITY::rcVlanTable
            'rc_vlan_id'      => 'rcVlanId',
            'v_name'          => 'rcVlanName',
            'rc_vlan_color'   => 'rcVlanColor',
            'rc_vlan_if'      => 'rcVlanIfIndex',
            'rc_vlan_stg'     => 'rcVlanStgId',
            'rc_vlan_type'    => 'rcVlanType',
            'rc_vlan_members' => 'rcVlanPortMembers',
            'rc_vlan_no_join' => 'rcVlanNotAllowToJoin',
            'rc_vlan_mac'     => 'rcVlanMacAddress',
            'rc_vlan_rstatus' => 'rcVlanRowStatus',
            # From RAPID-CITY::rcIpAddrTable
            'rc_ip_index'  => 'rcIpAdEntIfIndex',
            'rc_ip_addr'   => 'rcIpAdEntAddr',
            'rc_ip_type'   => 'rcIpAdEntIfType',
            # From RAPID-CITY::rcChasFanTable
            'rc_fan_op'     => 'rcChasFanOperStatus',
            # From RAPID-CITY::rcChasPowerSupplyTable
            'rc_ps_op'     => 'rcChasPowerSupplyOperStatus',
            # From RAPID-CITY::rcChasPowerSupplyDetailTable
            'rc_ps_type'     => 'rcChasPowerSupplyDetailType',
            'rc_ps_serial'   => 'rcChasPowerSupplyDetailSerialNumber',
            'rc_ps_rev'      => 'rcChasPowerSupplyDetailHardwareRevision',
            'rc_ps_part'     => 'rcChasPowerSupplyDetailPartNumber',
            'rc_ps_detail'     => 'rcChasPowerSupplyDetailDescription',
            # From RAPID-CITY::rcCardTable
            'rc_c_type'     => 'rcCardType',
            'rc_c_serial'   => 'rcCardSerialNumber',
            'rc_c_rev'      => 'rcCardHardwareRevision',
            'rc_c_part'     => 'rcCardPartNumber',
            # From RAPID-CITY::rc2kCardTable
            'rc2k_c_ftype'    => 'rc2kCardFrontType',
            'rc2k_c_fdesc'    => 'rc2kCardFrontDescription',
            'rc2k_c_fserial'  => 'rc2kCardFrontSerialNum',
            'rc2k_c_frev'     => 'rc2kCardFrontHwVersion',
            'rc2k_c_fpart'    => 'rc2kCardFrontPartNumber',
            'rc2k_c_fdate'    => 'rc2kCardFrontDateCode',
            'rc2k_c_fdev'     => 'rc2kCardFrontDeviations',
            'rc2k_c_btype'    => 'rc2kCardBackType',
            'rc2k_c_bdesc'    => 'rc2kCardBackDescription',
            'rc2k_c_bserial'  => 'rc2kCardBackSerialNum',
            'rc2k_c_brev'     => 'rc2kCardBackHwVersion',
            'rc2k_c_bpart'    => 'rc2kCardBackPartNumber',
            'rc2k_c_bdate'    => 'rc2kCardBackDateCode',
            'rc2k_c_bdev'     => 'rc2kCardBackDeviations',
            # From RAPID-CITY::rc2kMdaCardTable
            'rc2k_mda_type'    => 'rc2kMdaCardType',
            'rc2k_mda_desc'    => 'rc2kMdaCardDescription',
            'rc2k_mda_serial'  => 'rc2kMdaCardSerialNum',
            'rc2k_mda_rev'     => 'rc2kMdaCardHwVersion',
            'rc2k_mda_part'    => 'rc2kMdaCardPartNumber',
            'rc2k_mda_date'    => 'rc2kMdaCardDateCode',
            'rc2k_mda_dev'     => 'rc2kMdaCardDeviations',
            );

%MUNGE = (
            'rc_base_mac' => \&SNMP::Info::munge_mac,
            'rc_vlan_mac' => \&SNMP::Info::munge_mac,
            'rc_cpu_mac'  => \&SNMP::Info::munge_mac,         
         );

# Need to override here since overridden in Layer2 and Layer3 classes
sub serial {
    my $rapidcity = shift;

    my $ver = $rapidcity->rc_serial();
    return $ver unless !defined $ver;
    
    return undef;
}

sub i_duplex {
    my $rapidcity = shift;
    my $partial = shift;
    
    my $rc_duplex = $rapidcity->rc_duplex($partial) || {};
    my $rc_cpu_duplex = $rapidcity->rc_cpu_duplex($partial) || {};

    my %i_duplex;
    foreach my $if (keys %$rc_duplex){
        my $duplex = $rc_duplex->{$if};
        next unless defined $duplex; 
    
        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;
        $i_duplex{$if}=$duplex; 
    }
    
    # Get CPU Ethernet Interfaces for 8600 Series
    foreach my $iid (keys %$rc_cpu_duplex){
        my $c_duplex = $rc_cpu_duplex->{$iid};
        next unless defined $c_duplex;

       	$i_duplex{$iid} = $c_duplex;
    }

    return \%i_duplex;
}

sub i_duplex_admin {
    my $rapidcity = shift;
    my $partial = shift;

    my $rc_duplex_admin = $rapidcity->rc_duplex_admin() || {};
    my $rc_auto = $rapidcity->rc_auto($partial) || {};
    my $rc_cpu_auto = $rapidcity->rc_cpu_auto($partial) || {};
    my $rc_cpu_duplex_admin = $rapidcity->rc_cpu_duplex_admin($partial) || {};
 
    my %i_duplex_admin;
    foreach my $if (keys %$rc_duplex_admin){
        my $duplex = $rc_duplex_admin->{$if};
        next unless defined $duplex;
        my $auto = $rc_auto->{$if}||'false';
        
        my $string = 'other';
        $string = 'half' if ($duplex =~ /half/i and $auto =~ /false/i);
        $string = 'full' if ($duplex =~ /full/i and $auto =~ /false/i);
        $string = 'auto' if $auto =~ /true/i;    

        $i_duplex_admin{$if}=$string; 
    }
    
    # Get CPU Ethernet Interfaces for 8600 Series
    foreach my $iid (keys %$rc_cpu_duplex_admin){
        my $c_duplex = $rc_cpu_duplex_admin->{$iid};
        next unless defined $c_duplex;
        my $c_auto = $rc_cpu_auto->{$iid};

	my $string = 'other';
        $string = 'half' if ($c_duplex =~ /half/i and $c_auto =~ /false/i);
        $string = 'full' if ($c_duplex =~ /full/i and $c_auto =~ /false/i);
        $string = 'auto' if $c_auto =~ /true/i;    

       	$i_duplex_admin{$iid} = $string;
    }
    
    return \%i_duplex_admin;
}

sub set_i_duplex_admin {
    my $rapidcity = shift;
    my ($duplex, $iid) = @_;

    $duplex = lc($duplex);
    return undef unless ($duplex =~ /(half|full|auto)/ and $iid =~ /\d+/);

    # map a textual duplex to an integer one the switch understands
    my %duplexes = qw/full 2 half 1/;
    my $i_auto = $rapidcity->rc_auto($iid);

    if ($duplex eq "auto") {
        return $rapidcity->set_rc_auto('1', $iid);
    }
    elsif (($duplex ne "auto") and ($i_auto->{$iid} eq "1")) {
        return undef unless ($rapidcity->set_rc_auto('2', $iid));
        return $rapidcity->set_rc_duplex_admin($duplexes{$duplex}, $iid);
    }
    else {
        return $rapidcity->set_rc_duplex_admin($duplexes{$duplex}, $iid);
    }
    return undef;
}

sub set_i_speed_admin {
    my $rapidcity = shift;
    my ($speed, $iid) = @_;

    return undef unless ($speed =~ /(10|100|1000|auto)/i and $iid =~ /\d+/);
    
    # map a textual duplex to an integer one the switch understands
    my %speeds = qw/10 1 100 2 1000 3/;  
    my $i_auto = $rapidcity->rc_auto($iid);

    if ($speed eq "auto") {
        return $rapidcity->set_rc_auto('1', $iid);
    }
    elsif (($speed ne "auto") and ($i_auto->{$iid} eq "1")) {
        return undef unless ($rapidcity->set_rc_auto('2', $iid));
        return $rapidcity->set_rc_speed_admin($speeds{$speed}, $iid);
    }
    else {
        return $rapidcity->set_rc_speed_admin($speeds{$speed}, $iid);
    }        
    return undef;
}

sub v_index {
    my $rapidcity = shift;
    my $partial = shift;

    return $rapidcity->rc_vlan_id($partial);
}

sub i_vlan {
    my $rapidcity = shift;
    my $partial = shift;

    my $i_pvid = $rapidcity->rc_i_vlan_pvid($partial) || {};
    
    return $i_pvid;
}

sub i_vlan_membership {
    my $rapidcity = shift;

    my $rc_v_ports = $rapidcity->rc_vlan_members();

    my $i_vlan_membership = {};
    foreach my $vlan (keys %$rc_v_ports) {
        my $portlist = [split(//, unpack("B*", $rc_v_ports->{$vlan}))];
        my $ret = [];

        # Convert portlist bit array to ifIndex array
        for (my $i = 0; $i <= scalar(@$portlist); $i++) {
	    push(@{$ret}, $i) if (@$portlist[$i]);
        }

        #Create HoA ifIndex -> VLAN array
        foreach my $port (@{$ret}) {
	    push(@{$i_vlan_membership->{$port}}, $vlan);
        }
    }
    return $i_vlan_membership;
}

sub set_i_pvid {
    my $rapidcity = shift;
    my ($vlan_id, $ifindex) = @_; 

    return undef unless ( $rapidcity->validate_vlan_param ($vlan_id, $ifindex) );

    unless ( $rapidcity->set_rc_i_vlan_pvid($vlan_id, $ifindex) ) {
        $rapidcity->error_throw("Unable to change PVID to $vlan_id on IfIndex: $ifindex");
        return undef;
    }
    return 1;
}

sub set_i_vlan {
    my $rapidcity = shift;
    my ($new_vlan_id, $ifindex) = @_;

    return undef unless ( $rapidcity->validate_vlan_param ($new_vlan_id, $ifindex) );

    my $vlan_p_type = $rapidcity->rc_i_vlan_type($ifindex);
    unless ( $vlan_p_type->{$ifindex} =~ /access/ ) {
        $rapidcity->error_throw("Not an access port");
        return undef;
    }

    my $i_pvid = $rapidcity->rc_i_vlan_pvid($ifindex);

    # Store current untagged VLAN to remove it from the port list later
    my $old_vlan_id = $i_pvid->{$ifindex};
    print "Changing VLAN: $old_vlan_id to $new_vlan_id on IfIndex: $ifindex\n" if $rapidcity->debug();

    # Check if port in forbidden list for the VLAN, haven't seen this used, but we'll check anyway
    return undef unless ($rapidcity->check_forbidden_ports($new_vlan_id, $ifindex));

    # Remove port from old VLAN from egress list
    return undef unless ($rapidcity->remove_from_egress_portlist($old_vlan_id, $ifindex));

    # Add port to egress list for VLAN
    return undef unless ($rapidcity->add_to_egress_portlist($new_vlan_id, $ifindex));

    # Set new untagged / native VLAN
    # Some models/versions do this for us also, so check to see if we need to set
    $i_pvid = $rapidcity->rc_i_vlan_pvid($ifindex);

    my $cur_i_pvid = $i_pvid->{$ifindex};
    print "Current PVID: $cur_i_pvid\n" if $rapidcity->debug();
    unless ($cur_i_pvid eq $new_vlan_id) {
        return undef unless ($rapidcity->set_i_pvid($new_vlan_id, $ifindex));
    }

    print "Successfully changed VLAN: $old_vlan_id to $new_vlan_id on IfIndex: $ifindex\n" if $rapidcity->debug();
    return 1;
}

sub set_add_i_vlan_tagged {
    my $rapidcity = shift;
    my ($vlan_id, $ifindex) = @_;

    return undef unless ( $rapidcity->validate_vlan_param ($vlan_id, $ifindex) );

    print "Adding VLAN: $vlan_id to IfIndex: $ifindex\n" if $rapidcity->debug();

    # Check if port in forbidden list for the VLAN, haven't seen this used, but we'll check anyway
    return undef unless ($rapidcity->check_forbidden_ports($vlan_id, $ifindex));

    # Add port to egress list for VLAN
    return undef unless ($rapidcity->add_to_egress_portlist($vlan_id, $ifindex));

    print "Successfully added IfIndex: $ifindex to VLAN: $vlan_id egress list\n" if $rapidcity->debug();
    return 1;
}

sub set_remove_i_vlan_tagged {
    my $rapidcity = shift;
    my ($vlan_id, $ifindex) = @_;

    return undef unless ( $rapidcity->validate_vlan_param ($vlan_id, $ifindex) );

    print "Removing VLAN: $vlan_id from IfIndex: $ifindex\n" if $rapidcity->debug();

    # Remove port from egress list for VLAN
    return undef unless ($rapidcity->remove_from_egress_portlist($vlan_id, $ifindex));

    print "Successfully removed IfIndex: $ifindex from VLAN: $vlan_id egress list\n" if $rapidcity->debug();
    return 1;
}

#
# Need to be able to construct a single set with multiple oids 
#
#sub set_create_vlan {
#    my $rapidcity = shift;
#    my ($name, $vlan_id) = @_;
#    return undef unless ($vlan_id =~ /\d+/);
#
#    my $activate_rv = $rapidcity->set_rc_vlan_rstatus(4, $vlan_id);
#    unless ($activate_rv) {
#        print "Error: Unable to activate VLAN: $vlan_id\n" if $rapidcity->debug();
#        return undef;
#    }
#    my $rv = $rapidcity->set_v_name($name, $vlan_id);
#    unless ($rv) {
#        print "Error: Unable to create VLAN: $vlan_id\n" if $rapidcity->debug();
#        return undef;
#    }
#    return 1;
#}

sub set_delete_vlan {
    my $rapidcity = shift;
    my ($vlan_id) = shift;
    return undef unless ($vlan_id =~ /^\d+$/);

    unless ( $rapidcity->set_rc_vlan_rstatus('6', $vlan_id) ) {
        $rapidcity->error_throw("Unable to delete VLAN: $vlan_id");
        return undef;
    }
    return 1;
}

#
# These are internal methods and are not documented.  Do not use directly. 
#
sub check_forbidden_ports {
    my $rapidcity = shift;
    my ($vlan_id, $ifindex) = @_;

    my $iv_forbidden = $rapidcity->rc_vlan_no_join($vlan_id);

    my @forbidden_ports = split(//, unpack("B*", $iv_forbidden->{$vlan_id}));
    print "Forbidden ports: @forbidden_ports\n" if $rapidcity->debug();
    if ( defined($forbidden_ports[$ifindex]) and ($forbidden_ports[$ifindex] eq "1")) {
        $rapidcity->error_throw("IfIndex: $ifindex in forbidden list for VLAN: $vlan_id unable to add");
        return undef;
    }
    return 1;
}

sub add_to_egress_portlist {
    my $rapidcity = shift;
    my ($vlan_id, $ifindex) = @_;

    my $iv_members   = $rapidcity->rc_vlan_members($vlan_id);

    my @egress_list = split(//, unpack("B*", $iv_members->{$vlan_id}));
    print "Original egress list for VLAN: $vlan_id: @egress_list \n" if $rapidcity->debug();
    $egress_list[$ifindex] = '1';
    # Some devices do not populate the portlist with all possible ports.
    # If we have lengthened the list fill all undefined elements with zero.
    foreach my $item (@egress_list) {
        $item = '0' unless (defined($item));
    }
    print "Modified egress list for VLAN: $vlan_id: @egress_list \n" if $rapidcity->debug();
    my $new_egress = pack("B*", join('', @egress_list));

    unless ( $rapidcity->set_rc_vlan_members($new_egress, $vlan_id) ) {
        $rapidcity->error_throw("Unable to add VLAN: $vlan_id to IfIndex: $ifindex egress list");
        return undef;
    }
    return 1;
}

sub remove_from_egress_portlist {
    my $rapidcity = shift;
    my ($vlan_id, $ifindex) = @_;

    my $iv_members   = $rapidcity->rc_vlan_members($vlan_id);

    my @egress_list = split(//, unpack("B*", $iv_members->{$vlan_id}));
    print "Original egress list for VLAN: $vlan_id: @egress_list \n" if $rapidcity->debug();
    # Some devices may remove automatically, so check state before set
    if ( defined($egress_list[$ifindex]) and ($egress_list[$ifindex] eq "1")) {
        $egress_list[$ifindex] = '0';
        print "Modified egress list for VLAN: $vlan_id: @egress_list \n" if $rapidcity->debug();
        my $new_egress = pack("B*", join('', @egress_list));

        unless ( $rapidcity->set_rc_vlan_members($new_egress, $vlan_id) ) {
            $rapidcity->error_throw("Unable to remove IfIndex: $ifindex from VLAN: $vlan_id egress list");
            return undef;
        }  
    }
    return 1;
}

sub validate_vlan_param {
    my $rapidcity = shift;
    my ($vlan_id, $ifindex) = @_;

    # VID and ifIndex should both be numeric
    unless ( defined $vlan_id and defined $ifindex and $vlan_id =~ /^\d+$/ and $ifindex =~ /^\d+$/ ) {
        $rapidcity->error_throw("Invalid parameter");
        return undef;
    }
    
    # Check that ifIndex exists on device
    my $index = $rapidcity->interfaces($ifindex);

    unless ( exists $index->{$ifindex} ) {
        $rapidcity->error_throw("ifIndex $ifindex does not exist");
        return undef;
    }

    #Check that VLAN exists on device
    unless ( $rapidcity->rc_vlan_id($vlan_id) ) {
        $rapidcity->error_throw("VLAN $vlan_id does not exist or is not operational");
        return undef;
    }

    return 1;
}

1;

__END__

=head1 NAME

SNMP::Info::RapidCity - SNMP Interface to the Nortel RapidCity MIB

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $rapidcity = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class = $rapidcity->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::RapidCity is a subclass of SNMP::Info that provides an interface
to the C<RAPID-CITY> MIB.  This MIB is used across the Nortel Ethernet Routing
Switch and Ethernet Switch product lines (Formerly known as Passport,
BayStack, and Acclear).

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item RAPID-CITY

=back

=head1 GLOBAL METHODS

These are methods that return scalar values from SNMP

=over

=item  $rapidcity->rc_base_mac()

(B<rc2kChassisBaseMacAddr>)

=item  $rapidcity->rc_serial()

(B<rcChasSerialNumber>)

=item  $rapidcity->rc_ch_rev()

(B<rcChasHardwareRevision>)

=item  $rapidcity->chassis()

(B<rcChasType>)

=item  $rapidcity->slots()

(B<rcChasNumSlots>)

=item  $rapidcity->rc_virt_ip()

(B<rcSysVirtualIpAddr>)

=item  $rapidcity->rc_virt_mask()

(B<rcSysVirtualNetMask>)

=item  $rapidcity->tftp_host()

(B<rcTftpHost>)

=item  $rapidcity->tftp_file()

(B<rcTftpFile>)

=item  $rapidcity->tftp_action()

(B<rcTftpAction>)

=item  $rapidcity->tftp_result()

(B<rcTftpResult>)

=back

=head2 Overrides

=over

=item  $rapidcity->serial()

Returns serial number of the chassis

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $rapidcity->i_duplex()

Returns reference to map of IIDs to current link duplex.

=item $rapidcity->i_duplex_admin()

Returns reference to hash of IIDs to admin duplex setting.

=item $rapidcity->i_vlan()

Returns a mapping between ifIndex and the PVID or default VLAN.

=item $rapidcity->i_vlan_membership()

Returns reference to hash of arrays: key = ifIndex, value = array of VLAN IDs.
These are the VLANs which are members of the egress list for the port.

  Example:
  my $interfaces = $rapidcity->interfaces();
  my $vlans      = $rapidcity->i_vlan_membership();
  
  foreach my $iid (sort keys %$interfaces) {
    my $port = $interfaces->{$iid};
    my $vlan = join(',', sort(@{$vlans->{$iid}}));
    print "Port: $port VLAN: $vlan\n";
  }

=back

=head2 RAPID-CITY Port Table (B<rcPortTable>)

=over

=item $rapidcity->rc_index()

(B<rcPortIndex>)

=item $rapidcity->rc_duplex()

(B<rcPortOperDuplex>)

=item $rapidcity->rc_duplex_admin()

(B<rcPortAdminDuplex>)

=item $rapidcity->rc_speed_admin()

(B<rcPortAdminSpeed>)

=item $rapidcity->rc_auto()

(B<rcPortAutoNegotiate>)

=item $rapidcity->rc_alias()

(B<rcPortName>)

=back

=head2 RAPID-CITY CPU Ethernet Port Table (B<rc2kCpuEthernetPortTable>)

=over

=item $rapidcity->rc_cpu_ifindex()

(B<rc2kCpuEthernetPortIfIndex>)

=item $rapidcity->rc_cpu_admin()

(B<rc2kCpuEthernetPortAdminStatus>)

=item $rapidcity->rc_cpu_oper()

(B<rc2kCpuEthernetPortOperStatus>)

=item $rapidcity->rc_cpu_ip()

(B<rc2kCpuEthernetPortAddr>)

=item $rapidcity->rc_cpu_mask()

(B<rc2kCpuEthernetPortMask>)

=item $rapidcity->rc_cpu_auto()

(B<rc2kCpuEthernetPortAutoNegotiate>)

=item $rapidcity->rc_cpu_duplex_admin()

(B<rc2kCpuEthernetPortAdminDuplex>)

=item $rapidcity->rc_cpu_duplex()

(B<rc2kCpuEthernetPortOperDuplex>)

=item $rapidcity->rc_cpu_speed_admin()

(B<rc2kCpuEthernetPortAdminSpeed>)

=item $rapidcity->rc_cpu_speed_oper()

(B<rc2kCpuEthernetPortOperSpeed>)

=item $rapidcity->rc_cpu_mac()

(B<rc2kCpuEthernetPortMgmtMacAddr>)

=back

=head2 RAPID-CITY VLAN Port Table (B<rcVlanPortTable>)

=over

=item $rapidcity->rc_i_vlan_if()

(B<rcVlanPortIndex>)

=item $rapidcity->rc_i_vlan_num()

(B<rcVlanPortNumVlanIds>)

=item $rapidcity->rc_i_vlan()

(B<rcVlanPortVlanIds>)

=item $rapidcity->rc_i_vlan_type()

(B<rcVlanPortType>)

=item $rapidcity->rc_i_vlan_pvid()

(B<rcVlanPortDefaultVlanId>)

=item $rapidcity->rc_i_vlan_tag()

(B<rcVlanPortPerformTagging>)

=back

=head2 RAPID-CITY VLAN Table (B<rcVlanTable>)

=over

=item $rapidcity->rc_vlan_id()

(B<rcVlanId>)

=item $rapidcity->v_name()

(B<rcVlanName>)

=item $rapidcity->rc_vlan_color()

(B<rcVlanColor>)

=item $rapidcity->rc_vlan_if()

(B<rcVlanIfIndex>)

=item $rapidcity->rc_vlan_stg()

(B<rcVlanStgId>)

=item $rapidcity->rc_vlan_type()

(B<rcVlanType>)

=item $rapidcity->rc_vlan_members()

(B<rcVlanPortMembers>)

=item $rapidcity->rc_vlan_mac()

(B<rcVlanMacAddress>)

=back

=head2 RAPID-CITY IP Address Table (B<rcIpAddrTable>)

=over

=item $rapidcity->rc_ip_index()

(B<rcIpAdEntIfIndex>)

=item $rapidcity->rc_ip_addr()

(B<rcIpAdEntAddr>)

=item $rapidcity->rc_ip_type()

(B<rcIpAdEntIfType>)

=back

=head2 RAPID-CITY Chassis Fan Table (B<rcChasFanTable>)

=over

=item $rapidcity->rc_fan_op()

(B<rcChasFanOperStatus>)

=back

=head2 RAPID-CITY Power Supply Table (B<rcChasPowerSupplyTable>)

=over

=item $rapidcity->rc_ps_op()

(B<rcChasPowerSupplyOperStatus>)

=back

=head2 RAPID-CITY Power Supply Detail Table (B<rcChasPowerSupplyDetailTable>)

=over

=item $rapidcity->rc_ps_type()

(B<rcChasPowerSupplyDetailType>)

=item $rapidcity->rc_ps_serial()

(B<rcChasPowerSupplyDetailSerialNumber>)

=item $rapidcity->rc_ps_rev()

(B<rcChasPowerSupplyDetailHardwareRevision>)

=item $rapidcity->rc_ps_part()

(B<rcChasPowerSupplyDetailPartNumber>)

=item $rapidcity->rc_ps_detail()

(B<rcChasPowerSupplyDetailDescription>)

=back

=head2 RAPID-CITY Card Table (B<rcCardTable>)

=over

=item $rapidcity->rc_c_type()

(B<rcCardType>)

=item $rapidcity->rc_c_serial()

(B<rcCardSerialNumber>)

=item $rapidcity->rc_c_rev()

(B<rcCardHardwareRevision>)

=item $rapidcity->rc_c_part()

(B<rcCardPartNumber>)

=back

=head2 RAPID-CITY 2k Card Table (B<rc2kCardTable>)

=over

=item $rapidcity->rc2k_c_ftype()

(B<rc2kCardFrontType>)

=item $rapidcity->rc2k_c_fdesc()

(B<rc2kCardFrontDescription>)

=item $rapidcity->rc2k_c_fserial()

(B<rc2kCardFrontSerialNum>)

=item $rapidcity->rc2k_c_frev()

(B<rc2kCardFrontHwVersion>)

=item $rapidcity->rc2k_c_fpart()

(B<rc2kCardFrontPartNumber>)

=item $rapidcity->rc2k_c_fdate()

(B<rc2kCardFrontDateCode>)

=item $rapidcity->rc2k_c_fdev()

(B<rc2kCardFrontDeviations>)

=item $rapidcity->rc2k_c_btype()

(B<rc2kCardBackType>)

=item $rapidcity->rc2k_c_bdesc()

(B<rc2kCardBackDescription>)

=item $rapidcity->rc2k_c_bserial()

(B<rc2kCardBackSerialNum>)

=item $rapidcity->rc2k_c_brev()

(B<rc2kCardBackHwVersion>)

=item $rapidcity->rc2k_c_bpart()

(B<rc2kCardBackPartNumber>)

=item $rapidcity->rc2k_c_bdate()

(B<rc2kCardBackDateCode>)

=item $rapidcity->rc2k_c_bdev()

(B<rc2kCardBackDeviations>)

=back

=head2 RAPID-CITY MDA Card Table (B<rc2kMdaCardTable>)

=over

=item $rapidcity->rc2k_mda_type()

(B<rc2kMdaCardType>)

=item $rapidcity->rc2k_mda_desc()

(B<rc2kMdaCardDescription>)

=item $rapidcity->rc2k_mda_serial()

(B<rc2kMdaCardSerialNum>)

=item $rapidcity->rc2k_mda_rev()

(B<rc2kMdaCardHwVersion>)

=item $rapidcity->rc2k_mda_part()

(B<rc2kMdaCardPartNumber>)

=item $rapidcity->rc2k_mda_date()

(B<rc2kMdaCardDateCode>)

=item $rapidcity->rc2k_mda_dev()

(B<rc2kMdaCardDeviations>)

=back

=head1 SET METHODS

These are methods that provide SNMP set functionality for overridden methods or
provide a simpler interface to complex set operations.  See
L<SNMP::Info/"SETTING DATA VIA SNMP"> for general information on set operations. 

=over

=item $rapidcity->set_i_speed_admin(speed, ifIndex)

Sets port speed, must be supplied with speed and port ifIndex.  Speed choices
are 'auto', '10', '100', '1000'.

 Example:
 my %if_map = reverse %{$rapidcity->interfaces()};
 $rapidcity->set_i_speed_admin('auto', $if_map{'1.1'}) 
    or die "Couldn't change port speed. ",$rapidcity->error(1);

=item $rapidcity->set_i_duplex_admin(duplex, ifIndex)

Sets port duplex, must be supplied with duplex and port ifIndex.  Speed choices
are 'auto', 'half', 'full'.

  Example:
  my %if_map = reverse %{$rapidcity->interfaces()};
  $rapidcity->set_i_duplex_admin('auto', $if_map{'1.1'}) 
    or die "Couldn't change port duplex. ",$rapidcity->error(1);

=item $rapidcity->set_i_vlan(vlan, ifIndex)

Changes an access (untagged) port VLAN, must be supplied with the numeric VLAN ID
and port ifIndex.  This method will modify the port's VLAN membership and PVID
(default VLAN).  This method should only be used on end station (non-trunk) ports.

  Example:
  my %if_map = reverse %{$rapidcity->interfaces()};
  $rapidcity->set_i_vlan('2', $if_map{'1.1'}) 
    or die "Couldn't change port VLAN. ",$rapidcity->error(1);

=item $rapidcity->set_i_pvid(pvid, ifIndex)

Sets port PVID or default VLAN, must be supplied with the numeric VLAN ID and
port ifIndex.  This method only changes the PVID, to modify an access (untagged)
port use set_i_vlan() instead.

  Example:
  my %if_map = reverse %{$rapidcity->interfaces()};
  $rapidcity->set_i_pvid('2', $if_map{'1.1'}) 
    or die "Couldn't change port PVID. ",$rapidcity->error(1);

=item $rapidcity->set_add_i_vlan_tagged(vlan, ifIndex)

Adds the port to the egress list of the VLAN, must be supplied with the numeric
VLAN ID and port ifIndex.

  Example:
  my %if_map = reverse %{$rapidcity->interfaces()};
  $rapidcity->set_add_i_vlan_tagged('2', $if_map{'1.1'}) 
    or die "Couldn't add port to egress list. ",$rapidcity->error(1);

=item $rapidcity->set_remove_i_vlan_tagged(vlan, ifIndex)

Removes the port from the egress list of the VLAN, must be supplied with the
numeric VLAN ID and port ifIndex.

  Example:
  my %if_map = reverse %{$rapidcity->interfaces()};
  $rapidcity->set_remove_i_vlan_tagged('2', $if_map{'1.1'}) 
    or die "Couldn't add port to egress list. ",$rapidcity->error(1);

=item $rapidcity->set_delete_vlan(vlan)

Deletes the specified VLAN from the device.

=cut
