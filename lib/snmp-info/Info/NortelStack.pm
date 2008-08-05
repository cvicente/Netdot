# SNMP::Info::NortelStack
# $Id: NortelStack.pm,v 1.19 2008/08/02 03:21:25 jeneric Exp $
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

package SNMP::Info::NortelStack;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::NortelStack::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::NortelStack::EXPORT_OK = qw//;

use vars qw/$VERSION %FUNCS %GLOBALS %MIBS %MUNGE/;

$VERSION = '2.00';

%MIBS = (

    # S5-ROOT-MIB and S5-TCS-MIB required by the MIBs below
    'S5-AGENT-MIB'   => 's5AgMyGrpIndx',
    'S5-CHASSIS-MIB' => 's5ChasType',
    'S5-REG-MIB'     => 's5ChasTypeVal',
);

%GLOBALS = (

    # From S5-AGENT-MIB
    'ns_ag_ver'    => 's5AgInfoVer',
    'ns_op_mode'   => 's5AgSysCurrentOperationalMode',
    'ns_auto_pvid' => 's5AgSysAutoPvid',
    'tftp_host'    => 's5AgSysTftpServerAddress',
    'tftp_file'    => 's5AgSysBinaryConfigFilename',
    'tftp_action'  => 's5AgInfoFileAction',
    'tftp_result'  => 's5AgInfoFileStatus',
    'vlan'         => 's5AgSysManagementVlanId',

    # From S5-CHASSIS-MIB
    'ns_serial'   => 's5ChasSerNum',
    'ns_ch_type'  => 's5ChasType',
    'ns_cfg_chg'  => 's5ChasGblConfChngs',
    'ns_cfg_time' => 's5ChasGblConfLstChng',
);

%FUNCS = (

    # From S5-AGENT-MIB::s5AgMyIfTable
    'i_cfg_file' => 's5AgMyIfCfgFname',
    'i_cfg_host' => 's5AgMyIfLdSvrAddr',

    # From S5-CHASSIS-MIB::s5ChasGrpTable
    'ns_grp_type' => 's5ChasGrpType',

    # From S5-CHASSIS-MIB::s5ChasComTable
    'ns_com_grp_idx' => 's5ChasComGrpIndx',
    'ns_com_idx'     => 's5ChasComIndx',
    'ns_com_sub_idx' => 's5ChasComSubIndx',
    'ns_com_type'    => 's5ChasComType',
    'ns_com_descr'   => 's5ChasComDescr',
    'ns_com_ver'     => 's5ChasComVer',
    'ns_com_serial'  => 's5ChasComSerNum',

    # From S5-CHASSIS-MIB::s5ChasStoreTable
    'ns_store_grp_idx' => 's5ChasStoreGrpIndx',
    'ns_store_com_idx' => 's5ChasStoreComIndx',
    'ns_store_sub_idx' => 's5ChasStoreSubIndx',
    'ns_store_idx'     => 's5ChasStoreIndx',
    'ns_store_type'    => 's5ChasStoreType',
    'ns_store_size'    => 's5ChasStoreCurSize',
    'ns_store_ver'     => 's5ChasStoreCntntVer',
);

%MUNGE = (
    'ns_ch_type'    => \&SNMP::Info::munge_e_type,
    'ns_grp_type'   => \&munge_ns_grp_type,
    'ns_com_type'   => \&SNMP::Info::munge_e_type,
    'ns_store_type' => \&SNMP::Info::munge_e_type,
);

sub os_ver {
    my $stack = shift;

    my $ver = $stack->ns_ag_ver();
    return unless defined $ver;

    if ( $ver =~ m/(\d+\.\d+\.\d+\.\d+)/ ) {
        return $1;
    }
    if ( $ver =~ m/V(\d+\.\d+\.\d+)/i ) {
        return $1;
    }
    return;
}

sub os_bin {
    my $stack = shift;

    my $ver = $stack->ns_ag_ver();
    return unless defined $ver;

    if ( $ver =~ m/(\d+\.\d+\.\d+\.\d+)/i ) {
        return $1;
    }
    if ( $ver =~ m/V(\d+\.\d+.\d+)/i ) {
        return $1;
    }
    return;
}

# Need to override here since overridden in Layer2 and Layer3 classes
sub serial {
    my $stack = shift;

    my $ver = $stack->ns_serial();
    return $ver unless !defined $ver;

    return;
}

# Pseudo ENTITY-MIB methods for older switches with don't support ENTITY-MIB

# This class supports both stackable and chassis based switches, identify if
# we have a stackable so that we return appropriate entPhysicalClass
sub _ns_e_is_virtual {
    my $stack = shift;

    # We really only need one value, but we want this cached since most
    # methods call it at least via ns_e_index()
    my $v_test = $stack->s5ChasComRelPos() || {};
    return $v_test->{'8.1.0'};
}

# Identify is the stackable is actually a stack vs. single switch
sub _ns_e_is_stack {
    my $stack = shift;

    my $s_test = $stack->ns_e_class() || {};

    foreach my $iid ( keys %$s_test ) {
        my $class = $s_test->{$iid};
        next unless defined $class;
        return 1 if ( $class eq 'stack' );
    }
    return 0;
}

sub ns_e_index {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx = $stack->ns_com_grp_idx($partial) || {};
    my $is_virtual = $stack->_ns_e_is_virtual();

    my %ns_e_index;
    foreach my $iid ( keys %$ns_e_idx ) {

        # Skip backplane, power, sensor, fan, clock - these aren't in the
        # newer devices ENTITY-MIB we're emulating
        next if ( $iid =~ /^[24567]/ );
        next if ( ($is_virtual) and ( $iid =~ /^8/ or $iid eq '1.0.0' ) );

        # Format into consistent integer format so that numeric sorting works
        my $index = join( '', map { sprintf "%02d", $_ } split /\./, $iid );
        $ns_e_index{$iid} = $index;
    }
    return \%ns_e_index;
}

sub ns_e_class {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx   = $stack->ns_e_index($partial) || {};
    my $classes    = $stack->ns_grp_type();
    my $ns_grp_enc = $stack->s5ChasGrpEncodeFactor($partial) || {};
    my $is_virtual = $stack->_ns_e_is_virtual();

    my %ns_e_class;
    foreach my $iid ( keys %$ns_e_idx ) {
        my ( $grp, $idx, $sub ) = split( /\./, $iid );
        next unless defined $grp;
        my $class = $classes->{$grp};
        next unless defined $class;
        my $enc = $ns_grp_enc->{$grp};

        # Handle quirks of dealing with both stacks and chassis
        if ( ( !$is_virtual ) and ( $grp == 1 ) ) {
            $class = 'module';
        }
        if ( ($is_virtual) and ( $grp == 3 ) and !( $idx % $enc ) ) {
            $class = 'chassis';
        }

        $ns_e_class{$iid} = $class;
    }
    return \%ns_e_class;
}

sub ns_e_descr {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx   = $stack->ns_e_index($partial)   || {};
    my $ns_e_descr = $stack->ns_com_descr($partial) || {};

    my %ns_e_descr;
    foreach my $iid ( keys %$ns_e_idx ) {
        my $descr = $ns_e_descr->{$iid};
        next unless defined $descr;

        $ns_e_descr{$iid} = $descr;
    }
    return \%ns_e_descr;
}

sub ns_e_name {
    my $stack   = shift;
    my $partial = shift;

    my $ns_class   = $stack->ns_e_class()                    || {};
    my $ns_e_idx   = $stack->ns_e_index()                    || {};
    my $ns_grp_enc = $stack->s5ChasGrpEncodeFactor($partial) || {};
    my $is_virtual = $stack->_ns_e_is_virtual();

    my %ns_e_name;
    foreach my $iid ( keys %$ns_e_idx ) {

        my ( $grp, $idx, $sub ) = split( /\./, $iid );
        my $class = $ns_class->{$iid};
        next unless defined $class;
        my $enc = $ns_grp_enc->{$grp};

        if ( ( !$is_virtual ) and ( $grp == 1 ) ) {
            $ns_e_name{$iid} = 'Supervisory Module';
        }
        elsif ( $class eq 'stack' ) {
            $ns_e_name{$iid} = 'Stack Master Unit';
        }
        elsif ( $class eq 'chassis' ) {
            if ($is_virtual) {
                my $unit = $idx / $enc;
                $ns_e_name{$iid} = "Switch Unit $unit";
            }
            else {
                $ns_e_name{$iid} = "Chassis";
            }
        }
        elsif ( $class eq 'module' ) {
            if ($is_virtual) {
                my $unit = int( $idx / $enc );
                my $mda  = $idx % $enc;
                $ns_e_name{$iid} = "Switch Unit $unit, MDA $mda";
            }
            elsif ( $sub != 0 ) {
                $ns_e_name{$iid} = "Module Slot $idx, Subcomponent $sub";
            }
            else {
                $ns_e_name{$iid} = "Module Slot $idx";
            }
        }
    }
    return \%ns_e_name;
}

sub ns_e_hwver {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx = $stack->ns_e_index($partial) || {};
    my $ns_e_ver = $stack->ns_com_ver($partial) || {};

    my %ns_e_hwver;
    foreach my $iid ( keys %$ns_e_idx ) {
        my $ver = $ns_e_ver->{$iid};
        next unless defined $ver;

        $ns_e_hwver{$iid} = $ver;
    }
    return \%ns_e_hwver;
}

sub ns_e_vendor {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx = $stack->ns_e_index($partial) || {};

    my %ns_e_vendor;
    foreach my $iid ( keys %$ns_e_idx ) {
        my $vendor = 'nortel';

        $ns_e_vendor{$iid} = $vendor;
    }
    return \%ns_e_vendor;
}

sub ns_e_serial {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx    = $stack->ns_e_index($partial)    || {};
    my $ns_e_serial = $stack->ns_com_serial($partial) || {};

    my %ns_e_serial;
    foreach my $iid ( keys %$ns_e_idx ) {
        my $serial = $ns_e_serial->{$iid};
        next unless defined $serial;

        $ns_e_serial{$iid} = $serial;
    }
    return \%ns_e_serial;
}

sub ns_e_type {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx  = $stack->ns_e_index($partial)  || {};
    my $ns_e_type = $stack->ns_com_type($partial) || {};
    my $is_stack  = $stack->_ns_e_is_stack();
    my $ch_type   = $stack->ns_ch_type();

    my %ns_e_type;
    foreach my $iid ( keys %$ns_e_idx ) {
        my $type = $ns_e_type->{$iid};
        next unless defined $type;

        if ( $is_stack and $iid =~ /^1/ ) {
            $type = $ch_type;
        }
        $ns_e_type{$iid} = $type;
    }
    return \%ns_e_type;
}

sub ns_e_pos {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx   = $stack->ns_e_index($partial)            || {};
    my $ns_grp_enc = $stack->s5ChasGrpEncodeFactor($partial) || {};
    my $is_stack   = $stack->_ns_e_is_stack();
    my $is_virtual = $stack->_ns_e_is_virtual();

    my %ns_e_pos;
    foreach my $iid ( keys %$ns_e_idx ) {
        my ( $grp, $pos, $idx ) = split( /\./, $iid );
        next unless defined $grp;
        next unless defined $pos;

        if ( $grp == 1 ) {
            if ($is_stack) {
                $pos = -1;
            }
            else {
                $pos = 99;
            }
        }
        elsif ( $grp == 3 and $idx == 0 ) {
            my $enc = $ns_grp_enc->{$grp};
            if ( $is_virtual and ( $pos % $enc ) ) {
                $pos = int( $pos % $enc );
            }
            elsif ( $is_virtual and !$is_stack and !( $pos % $enc ) ) {
                $pos = -1;
            }
            elsif ( $is_virtual and !( $pos % $enc ) ) {
                $pos = ( $pos / $enc );
            }
        }
        elsif ( !$is_stack and $grp == 3 ) {
            $pos = $idx;
        }
        elsif ( $grp == 8 ) {
            $pos = -1;
        }
        $ns_e_pos{$iid} = $pos;
    }
    return \%ns_e_pos;
}

sub ns_e_fwver {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx   = $stack->ns_e_index($partial)            || {};
    my $ns_e_ver   = $stack->ns_store_ver($partial)          || {};
    my $ns_e_type  = $stack->ns_store_type($partial)         || {};
    my $ns_grp_enc = $stack->s5ChasGrpEncodeFactor($partial) || {};
    my $is_virt    = $stack->_ns_e_is_virtual();

    my %ns_e_fwver;
    foreach my $iid ( keys %$ns_e_type ) {
        my $type = $ns_e_type->{$iid};
        next unless defined $type;
        next unless $type =~ /(rom|boot|fw)/i;
        my $ver = $ns_e_ver->{$iid};
        next unless defined $ver;
        $iid =~ s/\.\d+$//;

        if ($is_virt) {
            my ( $grp, $idx, $pos ) = split( /\./, $iid );
            my $enc = $ns_grp_enc->{$grp};
            $idx = $idx * $enc;
            $iid = "3.$idx.$pos";
        }
        $ns_e_fwver{$iid} = $ver;
    }
    return \%ns_e_fwver;
}

sub ns_e_swver {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx   = $stack->ns_e_index($partial)            || {};
    my $ns_e_ver   = $stack->ns_store_ver($partial)          || {};
    my $ns_e_type  = $stack->ns_store_type($partial)         || {};
    my $ns_grp_enc = $stack->s5ChasGrpEncodeFactor($partial) || {};
    my $is_virt    = $stack->_ns_e_is_virtual();

    my %ns_e_swver;
    foreach my $iid ( keys %$ns_e_type ) {
        my $type = $ns_e_type->{$iid};
        next unless defined $type;
        next unless $type =~ /(flash)/i;
        my $ver = $ns_e_ver->{$iid};
        next unless defined $ver;
        $iid =~ s/\.\d+$//;

        if ($is_virt) {
            my ( $grp, $idx, $pos ) = split( /\./, $iid );
            my $enc = $ns_grp_enc->{$grp};
            $idx = $idx * $enc;
            $iid = "3.$idx.$pos";
        }
        $ns_e_swver{$iid} = $ver;
    }
    return \%ns_e_swver;
}

sub ns_e_parent {
    my $stack   = shift;
    my $partial = shift;

    my $ns_e_idx   = $stack->ns_e_index($partial)            || {};
    my $ns_grp_enc = $stack->s5ChasGrpEncodeFactor($partial) || {};
    my $is_stack   = $stack->_ns_e_is_stack();
    my $is_virtual = $stack->_ns_e_is_virtual();

    my %ns_e_parent;
    foreach my $iid ( keys %$ns_e_idx ) {
        my $index = $ns_e_idx->{$iid};
        my ( $grp, $idx, $pos ) = split( /\./, $iid );
        next unless defined $grp;
        if ( $grp == 8 ) {
            $ns_e_parent{$iid} = '0';
        }
        if ( $grp == 1 ) {
            if ($is_stack) {
                $ns_e_parent{$iid} = '0';
            }
            else {
                $ns_e_parent{$iid} = '080100';
            }
        }
        if ( $grp == 3 ) {
            my $enc = $ns_grp_enc->{$grp};
            if ( $idx % $enc ) {
                my $npos   = ( $idx % $enc ) * $enc;
                my @parent = ( $grp, $npos, $pos );
                my $parent = join( '', map { sprintf "%02d", $_ } @parent );
                $ns_e_parent{$iid} = $parent;
            }
            elsif ($is_stack) {
                $ns_e_parent{$iid} = '010100';
            }
            elsif ( $is_virtual and !$is_stack ) {
                $ns_e_parent{$iid} = 0;
            }
            elsif ( $pos == 0 ) {
                $ns_e_parent{$iid} = '080100';
            }
            else {
                my $parent = $iid;
                $parent =~ s/\.\d+$/\.00/;
                $parent = join( '', map { sprintf "%02d", $_ } split /\./,
                    $parent );
                $ns_e_parent{$iid} = $parent;
            }
        }
        next;
    }
    return \%ns_e_parent;
}

sub munge_ns_grp_type {
    my $oid = shift;

    my %e_class = (
        Sup    => 'stack',
        Bkpl   => 'backplane',
        Brd    => 'module',
        Pwr    => 'powerSupply',
        TmpSnr => 'sensor',
        Fan    => 'fan',
        Clk    => 'other',
        Unit   => 'chassis',
    );

    my $name = &SNMP::translateObj($oid);
    $name =~ s/s5ChasGrp//;
    if ( ( defined($name) ) and ( exists( $e_class{$name} ) ) ) {
        $name = $e_class{$name};
    }
    return $name if defined($name);
    return $oid;
}

1;

__END__

=head1 NAME

SNMP::Info::NortelStack - SNMP Interface to the Nortel F<S5-AGENT-MIB> and
F<S5-CHASSIS-MIB>

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $stack = new SNMP::Info(
                    AutoSpecify => 1,
                    Debug       => 1,
                    # These arguments are passed directly on to SNMP::Session
                    DestHost    => 'myswitch',
                    Community   => 'public',
                    Version     => 2
                    ) 
    or die "Can't connect to DestHost.\n";

 my $class = $stack->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::NortelStack is a subclass of SNMP::Info that provides an interface
to F<S5-AGENT-MIB> and F<S5-CHASSIS-MIB>.  These MIBs are used across the
Nortel Stackable Ethernet Switches (BayStack), as well as, older Nortel
devices such as the Centillion family of ATM switches.

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item F<S5-AGENT-MIB>

=item F<S5-CHASSIS-MIB>

=item F<S5-ROOT-MIB> and F<S5-TCS-MIB> are required by the other MIBs.

=back

=head1 GLOBAL METHODS

These are methods that return scalar values from SNMP

=over

=item $stack->os_ver()

Returns the software version extracted from (C<s5AgInfoVer>)

=item $stack->os_bin()

Returns the firmware version extracted from (C<s5AgInfoVer>)

=item  $stack->serial()

Returns serial number of the chassis

(C<s5ChasSerNum>)

=item $stack->ns_ag_ver()

Returns the version of the agent in the form
'major.minor.maintenance[letters]'. 

(C<s5AgInfoVer>)

=item $stack->ns_op_mode()

Returns the stacking mode. 

(C<s5AgSysCurrentOperationalMode>)

=item $stack->tftp_action()

This object is used to download or upload a config file or an image file.

(C<s5AgInfoFileAction>)

=item $stack->tftp_result()

Returns the status of the latest action as shown by $stack->tftp_action().

(C<s5AgInfoFileStatus>)

=item $stack->ns_auto_pvid()

Returns the value indicating whether adding a port as a member of a VLAN
automatically results in its PVID being set to be the same as that VLAN ID.

(C<s5AgSysAutoPvid>)

=item $stack->tftp_file()

Name of the binary configuration file that will be downloaded/uploaded when
the $stack->tftp_action() object is set.

(C<s5AgSysBinaryConfigFilename>)

=item $stack->tftp_host()

The IP address of the TFTP server for all TFTP operations.

(C<s5AgSysTftpServerAddress>)

=item $stack->vlan()

Returns the VLAN ID of the system's management VLAN.

(C<s5AgSysManagementVlanId>)

=item $stack->ch_ser()

Returns the serial number of the chassis.

(C<s5ChasSerNum>)

=item $stack->ns_cfg_chg()

Returns the total number of configuration changes (other than attachment
changes, or physical additions or removals) in the chassis that have been
detected since cold/warm start.

(C<s5ChasGblConfChngs>)

=item $stack->ns_cfg_time()

Returns the value of C<sysUpTime> when the last configuration change (other
than attachment changes, or physical additions or removals) in the chassis
was detected.

(C<s5ChasGblConfLstChng>)

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Agent Interface Table (C<s5AgMyIfTable>)

=over

=item $stack->i_cfg_file()

Returns reference to hash.  Key: Table entry, Value: Name of the file

(C<s5AgMyIfCfgFname>)

=item $stack->i_cfg_host()

Returns reference to hash.  Key: Table entry, Value: IP address of the load
server

(C<s5AgMyIfLdSvrAddr>)

=back

=head2 Chassis Components Table (C<s5ChasComTable>)

=over

=item $stack->ns_com_grp_idx()

Returns reference to hash.  Key: Table entry, Value: Index of the chassis
level group which contains this component.

(C<s5ChasComGrpIndx>)

=item $stack->ns_com_idx()

Returns reference to hash.  Key: Table entry, Value: Index of the component
in the group.  For modules in the 'board' group, this is the slot number.

(C<s5ChasComIndx>)

=item $stack->ns_com_sub_idx()

Returns reference to hash.  Key: Table entry, Value: Index of the
sub-component in the component.

(C<s5ChasComSubIndx>)

=item $stack->ns_com_type()

Returns reference to hash.  Key: Table entry, Value: Type

(C<s5ChasComType>)

=item $stack->ns_com_descr()

Returns reference to hash.  Key: Table entry, Value: Description

(C<s5ChasComDescr>)

=item $stack->ns_com_ver()

Returns reference to hash.  Key: Table entry, Value: Version

(C<s5ChasComVer>)

=item $stack->ns_com_serial()

Returns reference to hash.  Key: Table entry, Value: Serial Number

(C<s5ChasComSerNum>)

=back

=head2 Storage Area Table (C<s5ChasStoreTable>)

=over

=item $stack->ns_store_grp_idx()

Returns reference to hash.  Key: Table entry, Value: Index of the chassis
level group.

(C<s5ChasStoreGrpIndx>)

=item $stack->ns_store_idx()

Returns reference to hash.  Key: Table entry, Value: Index of the group.

(C<s5ChasStoreComIndx>)

=item $stack->ns_store_sub_idx()

Returns reference to hash.  Key: Table entry, Value: Index of the
sub-component.

(C<s5ChasStoreSubIndx>)

=item $stack->ns_store_idx()

Returns reference to hash.  Key: Table entry, Value: Index of the storage
area.

(C<s5ChasStoreIndx>)

=item $stack->ns_store_type()

Returns reference to hash.  Key: Table entry, Value: Type

(C<s5ChasStoreType>)

=item $stack->ns_store_size()

Returns reference to hash.  Key: Table entry, Value: Size

(C<s5ChasStoreCurSize>)

=item $stack->ns_store_ver()

Returns reference to hash.  Key: Table entry, Value: Version

(C<s5ChasStoreCntntVer>)

=back

=head2 Pseudo F<ENTITY-MIB> information

These methods emulate F<ENTITY-MIB> Physical Table methods using
F<S5-CHASSIS-MIB>. 

=over

=item $stack->ns_e_index()

Returns reference to hash.  Key: IID, Value: Integer, Indices are combined
into a six digit integer, each index is two digits padded with leading zero if
required.

=item $stack->ns_e_class()

Returns reference to hash.  Key: IID, Value: General hardware type
(C<s5ChasGrpDescr>).

Group is stripped from the string.  Values may be Supervisory Module,
Back Plane, Board, Power Supply, Sensor, Fan, Clock, Unit.

=item $stack->ns_e_descr()

Returns reference to hash.  Key: IID, Value: Human friendly name

(C<s5ChasComDescr>)

=item $stack->ns_e_name()

Returns reference to hash.  Key: IID, Value: Human friendly name

=item $stack->ns_e_hwver()

Returns reference to hash.  Key: IID, Value: Hardware version

(C<s5ChasComVer>)

=item $stack->ns_e_vendor()

Returns reference to hash.  Key: IID, Value: nortel

=item $stack->ns_e_serial()

Returns reference to hash.  Key: IID, Value: Serial number

(C<s5ChasComSerNum>)

=item $stack->ns_e_pos()

Returns reference to hash.  Key: IID, Value: The relative position among all
entities sharing the same parent.

(C<s5ChasComSubIndx>)

=item $stack->ns_e_type()

Returns reference to hash.  Key: IID, Value: Type of component/sub-component
as defined under C<s5ChasComTypeVal> in F<S5-REG-MIB>.

=item $stack->ns_e_fwver()

Returns reference to hash.  Key: IID, Value: Firmware revision.

Value of C<s5ChasStoreCntntVer> for entries with rom, boot, or firmware in
C<s5ChasStoreType>.

=item $stack->ns_e_swver()

Returns reference to hash.  Key: IID, Value: Software revision.

Value of C<s5ChasStoreCntntVer> for entries with "flash" in
C<s5ChasStoreType>.

=item $stack->ns_e_parent()

Returns reference to hash.  Key: IID, Value: The value of ns_e_index() for the
entity which 'contains' this entity.  A value of zero indicates	this entity
is not contained in any other entity.

=back

=head1 Data Munging Callback Subroutines

=over

=item $stack->munge_ns_grp_type()

Munges C<s5ChasGrpType> into an C<ENTITY-MIB PhysicalClass> equivalent. 

=back

=cut
