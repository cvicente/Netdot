# SNMP::Info::Layer3::AlteonAD
# Eric Miller
# $Id: AlteonAD.pm,v 1.12 2007/11/26 04:24:51 jeneric Exp $
#
# Copyright (c) 2004 Eric Miller
# All Rights Reserved
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

package SNMP::Info::Layer3::AlteonAD;
$VERSION = '1.07';

use strict;

use Exporter;
use SNMP::Info;
use SNMP::Info::Layer3;
use SNMP::Info::Bridge;

use vars qw/$VERSION $DEBUG %GLOBALS %FUNCS $INIT %MIBS %MUNGE /;

@SNMP::Info::Layer3::AlteonAD::ISA = qw/SNMP::Info SNMP::Info::Layer3 SNMP::Info::Bridge Exporter/;
@SNMP::Info::Layer3::AlteonAD::EXPORT_OK = qw//;

%MIBS = (
          %SNMP::Info::MIBS,
          %SNMP::Info::Layer3::MIBS,
          %SNMP::Info::Bridge::MIBS,
          'ALTEON-TIGON-SWITCH-MIB' => 'agSoftwareVersion',
          'ALTEON-TS-PHYSICAL-MIB'  => 'agPortTableMaxEnt',
          'ALTEON-TS-NETWORK-MIB'   => 'agPortTableMaxEnt',
        );

%GLOBALS = (
            %SNMP::Info::GLOBALS,
            %SNMP::Info::Layer3::GLOBALS,
            %SNMP::Info::Bridge::GLOBALS,
            'sw_ver'           => 'agSoftwareVersion',
            'tftp_action'  => 'agTftpAction',
            'tftp_host'    => 'agTftpServer',
            'tftp_file'    => 'agTftpCfgFileName',
            'tftp_result'  => 'agTftpLastActionStatus',
           );

%FUNCS = (
            %SNMP::Info::FUNCS,
            %SNMP::Info::Layer3::FUNCS,
            %SNMP::Info::Bridge::FUNCS,
            # From agPortCurCfgTable
            'ag_p_cfg_idx'        => 'agPortCurCfgIndx',
            'ag_p_cfg_pref'       => 'agPortCurCfgPrefLink',
            'ag_p_cfg_pvid'       => 'agPortCurCfgPVID',
            'ag_p_cfg_fe_auto'    => 'agPortCurCfgFastEthAutoNeg',
            'ag_p_cfg_fe_mode'    => 'agPortCurCfgFastEthMode',
            'ag_p_cfg_ge_auto'    => 'agPortCurCfgGigEthAutoNeg',
            'ag_p_cfg_name'       => 'agPortCurCfgPortName',
            # From portInfoTable
            'p_info_idx'     => 'portInfoIndx',
            'p_info_mode'    => 'portInfoMode',
            # From portInfoTable
            'ip_cfg_vlan'     => 'ipCurCfgIntfVlan',
         );
         
%MUNGE = (
            %SNMP::Info::MUNGE,
            %SNMP::Info::Layer3::MUNGE,
            %SNMP::Info::Bridge::MUNGE,
         );

sub model {
    my $alteon = shift;
    my $desc = $alteon->description();
    return undef unless defined $desc;

    return 'AD2' if ($desc =~ /AD2/);
    return 'AD3' if ($desc =~ /AD3/);
    return 'AD4' if ($desc =~ /AD4/);
    return '180' if ($desc =~ /180/);
    return '183' if ($desc =~ /183/);
    return '184' if ($desc =~ /184/);
    
    return $desc;
}

sub vendor {
    return 'nortel';
}

sub os {
    return 'webos';
}

sub os_ver {
    my $alteon = shift;
    my $version = $alteon->sw_ver();
    return undef unless defined $version;

    return $version;
}

sub interfaces {
    my $alteon = shift;
    my $interfaces = $alteon->i_index();
    my $descriptions = $alteon->i_description();

    my %interfaces = ();
    foreach my $iid (keys %$interfaces){
        my $desc = $descriptions->{$iid};
        next unless defined $desc;

        if ($desc =~ /(^net\d+)/) {
            $desc  = $1;
        }
        elsif (($iid > 256) and ($iid < 266)) {
            $desc = ($iid % 256);
        }
        $interfaces{$iid} = $desc;
    }
    return \%interfaces;
}

sub i_duplex {
    my $alteon = shift;
    
    my $p_mode = $alteon->p_info_mode();
    
    my %i_duplex;
    foreach my $if (keys %$p_mode){
        my $duplex = $p_mode->{$if};
        next unless defined $duplex; 
    
        $duplex = 'half' if $duplex =~ /half/i;
        $duplex = 'full' if $duplex =~ /full/i;
        
        my $idx = $if + 256;
        
        $i_duplex{$idx}=$duplex; 
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $alteon = shift;

    my $ag_pref = $alteon->ag_p_cfg_pref();
    my $ag_fe_auto = $alteon->ag_p_cfg_fe_auto();
    my $ag_fe_mode = $alteon->ag_p_cfg_fe_mode();
    my $ag_ge_auto = $alteon->ag_p_cfg_ge_auto();
 
    my %i_duplex_admin;
    foreach my $if (keys %$ag_pref){
        my $pref = $ag_pref->{$if};
        next unless defined $pref;
        
        my $string = 'other';        
        if ($pref =~ /gigabit/i) {
            my $ge_auto = $ag_ge_auto->{$if};
            $string = 'full' if ($ge_auto =~ /off/i);
            $string = 'auto' if ($ge_auto =~ /on/i);
        }
        elsif ($pref =~ /fast/i) {
            my $fe_auto = $ag_fe_auto->{$if};
            my $fe_mode = $ag_fe_mode->{$if};
            $string = 'half' if ($fe_mode =~ /half/i and $fe_auto =~ /off/i);
            $string = 'full' if ($fe_mode =~ /full/i and $fe_auto =~ /off/i);
            $string = 'auto' if $fe_auto =~ /on/i;
        }
        my $idx = $if + 256;
        
        $i_duplex_admin{$idx}=$string; 
    }
    return \%i_duplex_admin;
}

sub i_vlan {
    my $alteon = shift;

    my $ag_vlans  = $alteon->ag_p_cfg_pvid();
    my $ip_vlans  = $alteon->ip_cfg_vlan();


    my %i_vlan;
    foreach my $if (keys %$ip_vlans){
        my $ip_vlanid = $ip_vlans->{$if};
        next unless defined $ip_vlanid;
        
        $i_vlan{$if}=$ip_vlanid; 
    }
    foreach my $if (keys %$ag_vlans){
        my $ag_vlanid = $ag_vlans->{$if};
        next unless defined $ag_vlanid;
        
        my $idx = $if + 256;   
        $i_vlan{$idx}=$ag_vlanid; 
    }
    return \%i_vlan;
}

sub i_name {
    my $alteon = shift;
    my $p_name = $alteon->ag_p_cfg_name();

    my %i_name;
    foreach my $iid (keys %$p_name){
        my $name = $p_name->{$iid};
        next unless defined $name;
        my $idx = $iid + 256;
        $i_name{$idx} = $name;
    }
    return \%i_name;
}

# Bridge MIB does not map Bridge Port to ifIndex correctly
sub bp_index {
    my $alteon = shift;
    my $b_index = $alteon->orig_bp_index();

    my %bp_index;
    foreach my $iid (keys %$b_index){
        my $port = $b_index->{$iid};
        next unless defined $port;
        $port = $port + 256;

        $bp_index{$iid} = $port;
    }
    return \%bp_index;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::AlteonAD - Perl5 Interface to Nortel Networks' Alteon Ace
Director Series Layer 2-7 Switches.

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $alteon = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $alteon->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Abstraction subclass for Layer 2-7 load balancing switches running Nortel Networks'
Alteon Web OS Traffic Control Software.

For speed or debugging purposes you can call the subclass directly, but not after
determining a more specific class using the method above. 

 my $alteon = new SNMP::Info::Layer3::AlteonAD(...);

=head2 Inherited Classes

=over

=item SNMP::Info

=item SNMP::Info::Bridge

=back

=head2 Required MIBs

=over

=item ALTEON-TIGON-SWITCH-MIB

=item ALTEON-TS-PHYSICAL-MIB

=item ALTEON-TS-NETWORK-MIB

MIBs can be found on the CD that came with your product.

Or, they can be downloaded directly from Nortel Networks regardless of support
contract status.  Go to http://www.nortelnetworks.com Techninal Support,
Browse Technical Support, Select by Product Families, Alteon,
Alteon Web OS Traffic Control Software, Software.  Filter on mibs and download
the latest version's archive.

=item Inherited Classes' MIBs

See L<SNMP::Info/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::Bridge/"Required MIBs"> for its own MIB requirements.

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $alteon->model()

Returns the model extracted from B<sysDescr>

=item $alteon->vendor()

Returns 'nortel'

=item $alteon->os()

Returns 'webos'

=item $alteon->os_ver()

Returns the software version reported by B<agSoftwareVersion>

=item $alteon->tftp_action()

(B<agTftpAction>)

=item $alteon->tftp_host()

(B<agTftpServer>)

=item $alteon->tftp_file()

(B<agTftpCfgFileName>)

=item $alteon->tftp_result()

(B<agTftpLastActionStatus>)

=back

=head2 Globals imported from SNMP::Info

See documentation in L<SNMP::Info/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $alteon->interfaces()

Returns reference to the map between IID and physical port.

Utilizes description for network interfaces.  Ports are determined by
formula (ifIndex mod 256).

=item $alteon->i_duplex()

Returns reference to hash.  Maps port operational duplexes to IIDs.

=item $alteon->i_duplex_admin()

Returns reference to hash.  Maps port admin duplexes to IIDs.

=item $alteon->i_vlan()

Returns reference to hash.  Maps port VLAN ID to IIDs.

=item $alteon->i_name()

Maps (B<agPortCurCfgPortName>) to port and returns the human set port name if exists.

=item $alteon->bp_index()

Returns a mapping between ifIndex and the Bridge Table.

=back

=head2 Table Methods imported from SNMP::Info

See documentation in L<SNMP::Info/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"TABLE METHODS"> for details.

=cut
