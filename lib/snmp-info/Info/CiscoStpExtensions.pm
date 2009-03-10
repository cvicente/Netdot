# SNMP::Info::CiscoStpExtensions
#
# Copyright (c)2003,2004,2006 Max Baker 
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
#     * Neither the name of the author nor the 
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

package SNMP::Info::CiscoStpExtensions;
$VERSION = '2.00';

use strict;

use Exporter;
use SNMP::Info;
use SNMP::Info::Bridge;

use vars qw/$VERSION $DEBUG %MIBS %FUNCS %GLOBALS %MUNGE %PORTSTAT $INIT/;
@SNMP::Info::CiscoStpExtensions::ISA = qw/SNMP::Info SNMP::Info::Bridge Exporter/;
@SNMP::Info::CiscoStpExtensions::EXPORT_OK = qw//;

%MIBS    = (
	    %SNMP::Info::Bridge::MIBS,
            'CISCO-STP-EXTENSIONS-MIB' => 'stpxSpanningTreeType',
           );

%GLOBALS = (
            %SNMP::Info::Bridge::GLOBALS,
	    'stpx_mst_config_digest' => 'stpxSMSTConfigDigest',
            'stpx_mst_region_name'   => 'stpxMSTRegionName',
            'stpx_mst_region_rev'    => 'stpxSMSTRegionRevision',
	    'stpx_stp_type'          => 'stpxSpanningTreeType',
	    'stpx_bpduguard_enable'  => 'stpxFastStartBpduGuardEnable',
	    'stpx_bpdufilter_enable' => 'stpxFastStartBpduFilterEnable',
           );

%FUNCS   = (
            %SNMP::Info::Bridge::FUNCS,
	    'stpx_rootguard_enabled'      => 'stpxRootGuardConfigEnabled',
	    'stpx_loopguard_enabled'      => 'stpxLoopGuardConfigEnabled',
	    'stpx_port_bpduguard_mode'    => 'stpxFastStartPortBpduGuardMode',
	    'stpx_port_bpdufilter_mode'   => 'stpxFastStartPortBpduFilterMode',
            'stpx_smst_root'              => 'stpxSMSTInstanceCISTRegionalRoot',
            'stpx_smst_vlans_mapped_1k2k' => 'stpxSMSTInstanceVlansMapped1k2k',
            'stpx_smst_vlans_mapped_3k4k' => 'stpxSMSTInstanceVlansMapped3k4k',
           );

%MUNGE   = (
            %SNMP::Info::Bridge::MUNGE,
           'stpx_mst_config_digest'     => \&SNMP::Info::CiscoStpExtensions::oct2str,
           );


# Report version of STP via standard method
sub stp_ver {
     my $self = shift;
     my $stp_ver = $self->SUPER::stp_ver();
     if ( $stp_ver eq 'unknown' ){
	 if ( defined $self->stpx_stp_type() ){
	     $stp_ver = $self->stpx_stp_type();
	 }
     }
     return $stp_ver;
}

sub mst_config_digest {
    my $self = shift;
    return $self->stpx_mst_config_digest;
}

sub mst_region_name {
    my $self = shift;
    return $self->stpx_mst_region_name;
}

sub mst_region_rev {
    my $self = shift;
    return $self->stpx_mst_region_rev;
}


sub mst_vlan2instance {
    my $self = shift;
    
    # Get MST vlan-to-instance mapping
    my $m1k2k = $self->stpx_smst_vlans_mapped_1k2k;
    my $m3k4k = $self->stpx_smst_vlans_mapped_3k4k;
   
    # Get list of VLANs
    my $vlan_membership = $self->i_vlan_membership;
    my @vlans;
    foreach my $iid ( keys %$vlan_membership ){
	if ( my $vm = $vlan_membership->{$iid} ){
	    foreach my $vid ( @$vm ){
		push @vlans, $vid;
	    }
	}
    }
    my %res;
    foreach my $vlan ( @vlans ){
	if ( $vlan < 2048 ){
	    foreach my $inst ( keys %$m1k2k ){
		my $list = $m1k2k->{$inst};
		my $vlanlist = [split(//, unpack("B*", $list))];
		if ( @$vlanlist[$vlan] ){
		    $res{$vlan} = $inst;
		    last;
		}
	    }
	}else{
	    foreach my $inst ( keys %$m3k4k ){
		my $list = $m3k4k->{$inst};
		my $vlanlist = [split(//, unpack("B*", $list))];
		if ( @$vlanlist[$vlan-2048] ){
		    $res{$vlan} = $inst;
		    last;
		}
	    }	    
	}
    }
    return \%res;
}

sub i_rootguard_enabled {
    my $self    = shift;
    my $partial = shift;

    my $rg_enabled = $self->stpx_rootguard_enabled();
    my $bp_index   = $self->bp_index($partial);

    my %res;
    foreach my $index ( keys %$rg_enabled ){
	my $enabled = $rg_enabled->{$index};
	my $iid     = $bp_index->{$index};
	next unless defined $iid;
	next unless defined $enabled;
	$res{$iid} = $enabled;
    }
    return \%res;
}  

sub i_loopguard_enabled {
    my $self    = shift;
    my $partial = shift;

    my $lg_enabled = $self->stpx_loopguard_enabled();
    my $bp_index   = $self->bp_index($partial);

    my %res;
    foreach my $index ( keys %$lg_enabled ){
	my $enabled = $lg_enabled->{$index};
	my $iid     = $bp_index->{$index};
	next unless defined $iid;
	next unless defined $enabled;
	$res{$iid} = $enabled;
    }
    return \%res;
}  

sub i_bpduguard_enabled {
    my $self    = shift;
    my $partial = shift;

    my $bpdugm_default = $self->stpx_bpduguard_enable();
    my $bp_index       = $self->bp_index($partial);
    my $bpdugm         = $self->stpx_port_bpduguard_mode();
    
    my %res;
    foreach my $index ( keys %$bpdugm ){
	my $mode = $bpdugm->{$index};
	my $iid  = $bp_index->{$index};
	next unless defined $iid;
	next unless defined $mode;
	if ( $mode eq 'default' ){
	    $res{$iid} =  $bpdugm_default;
	}else{
	    $res{$iid} = $mode;
	}
    }
    return \%res;
}

sub i_bpdufilter_enabled {
    my $self    = shift;
    my $partial = shift;

    my $bpdufm_default = $self->stpx_bpdufilter_enable();
    my $bp_index       = $self->bp_index($partial);
    my $bpdufm         = $self->stpx_port_bpdufilter_mode();
    
    my %res;
    foreach my $index ( keys %$bpdufm ){
	my $mode = $bpdufm->{$index};
	my $iid  = $bp_index->{$index};
	next unless defined $iid;
	next unless defined $mode;
	if ( $mode eq 'default' ){
	    $res{$iid} =  $bpdufm_default;
	}else{
	    $res{$iid} = $mode;
	}
    }
    return \%res;
}


sub oct2str {
    my ($v) = @_;
    return sprintf('%s', unpack('H*', $v));
}

1;
__END__

=head1 NAME

SNMP::Info::CiscoStpExtensions - SNMP Interface to CISCO-STP-EXTENSIONS-MIB

=head1 AUTHOR

Carlos Vicente

=head1 SYNOPSIS

=head1 DESCRIPTION

Create or use a subclass of SNMP::Info that inherits this class.  Do not use
directly.

For debugging you can call new() directly as you would in SNMP::Info 

 my $stpx = new SNMP::Info::CiscoStpExtensions(...);

=head2 Inherited Classes

=over

=item SNMP::Info 

=item SNMP::Info::Bridge 

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBAL METHODS

These are methods that return scalar values from SNMP

=over

=item $stpx->stp_ver()

Returns the particular STP version running on this device.  
Meant to override SNMP::Info::Brigde::stp_ver()

Values: pvstPlus, mistp, mistpPvstPlus, mst, rapidPvstPlus

(stpxSpanningTreeType)

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=item $stpx->mst_config_digest()

Returns the Multiple Spanning Tree (MST) configuration digest 

(stpxSMSTConfigDigest)

=item $stpx->mst_region_name()

Returns the Multiple Spanning Tree (MST) region name 

(stpxMSTRegionName)

=item $stpx->mst_region_rev()

Returns the Multiple Spanning Tree (MST) region name 

(stpxSMSTRegionRevision)

=item $stpx->mst_vlan2instance()

Returns the mapping of vlan to MST instance in the form of a hash reference 
with key = VLAN id, value = STP instance

=item $stpx->i_rootguard_enabled()

Returns 1 or 0 depending on whether RootGuard is enabled on a given port.
Format is a hash reference with key = ifIndex, value = [1|0]

(stpxRootGuardConfigEnabled)

=item $stpx->i_loopguard_enabled()

Returns 1 or 0 depending on whether LoopGuard is enabled on a given port.
Format is a hash reference with key = ifIndex, value = [1|0]

(stpxLoopGuardConfigEnabled)

=item $stpx->i_bpduguard_enabled()

Returns 1 or 0 depending on whether BpduGuard is enabled on a given port.
Format is a hash reference with key = ifIndex, value = [1|0]

(stpxFastStartPortBpduGuardMode)

=item $stpx->i_bpdufilter_enabled()

Returns 1 or 0 depending on whether BpduFilter is enabled on a given port.
Format is a hash reference with key = ifIndex, value = [1|0]

(stpxFastStartBpduFilterEnable)

=back
