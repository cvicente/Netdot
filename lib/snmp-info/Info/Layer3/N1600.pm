# SNMP::Info::Layer3::N1600 - SNMP Interface to Nortel N16XX devices
# Eric Miller
#
# Copyright (c) 2005 Eric Miller
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
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

package SNMP::Info::Layer3::N1600;
# $Id: N1600.pm,v 1.8 2007/11/26 04:24:52 jeneric Exp $

use strict;

use Exporter;
use SNMP::Info::Layer3;
use SNMP::Info::SONMP;

use vars qw/$VERSION $DEBUG %GLOBALS %FUNCS $INIT %MIBS %MUNGE/;

$VERSION = '1.07';

@SNMP::Info::Layer3::N1600::ISA = qw/SNMP::Info::Layer3 SNMP::Info::SONMP Exporter/;
@SNMP::Info::Layer3::N1600::EXPORT_OK = qw//;

%MIBS = ( %SNMP::Info::Layer3::MIBS,
          %SNMP::Info::SONMP::MIBS,
          'SWL2MGMT-MIB' => 'swL2MgmtMIB',
          'RAPID-CITY' => 'rapidCity',
        );

%GLOBALS = (
            %SNMP::Info::Layer3::GLOBALS,
            %SNMP::Info::SONMP::GLOBALS,
           );

%FUNCS   = (
            %SNMP::Info::Layer3::FUNCS,
            %SNMP::Info::SONMP::FUNCS,
            # SWL2MGMT-MIB
            # swL2PortInfoTable
            'n1600_nway_status'  => 'swL2PortInfoNwayStatus',
            # swL2PortCtrlTable
            'n1600_nway_state'   => 'swL2PortCtrlNwayState',
           );

%MUNGE = (
            # Inherit all the built in munging
            %SNMP::Info::Layer3::MUNGE,
            %SNMP::Info::SONMP::MUNGE,
         );

# Method OverRides

sub bulkwalk_no { 1; }

sub model {
    my $n1600 = shift;
    my $id = $n1600->id();
    
    unless (defined $id){
        print " SNMP::Info::Layer3::N1600::model() - Device does not support sysObjectID\n" if $n1600->debug(); 
        return undef;
    }
    
    my $model = &SNMP::translateObj($id);

    return $id unless defined $model;

    $model =~ s/^rcA//i;
    return $model;
}

sub vendor {
    return 'nortel';
}

sub os {
    return 'passport';
}

sub os_ver {
    my $n1600 = shift;
    my $descr = $n1600->description();
    return undef unless defined $descr;

    if ($descr =~ m/(\d+\.\d+\.\d+\.\d+)/){
        return $1;
    }

    return undef;
}

sub interfaces {
    my $n1600 = shift;
    my $partial = shift;

    my $i_index = $n1600->i_index($partial) || {};
    
    my %if;
    foreach my $iid (keys %$i_index){
        my $index = $i_index->{$iid};
        next unless defined $index;

        my $slotport = "1.$index";
        $if{$iid} = $slotport;
    }
    return \%if;
}

sub i_duplex {
    my $n1600 = shift;
    my $partial = shift;

    my $nway_status = $n1600->n1600_nway_status($partial) || {};
    
    my %i_duplex;
    foreach my $iid (keys %$nway_status){
        my $duplex = $nway_status->{$iid};
        next unless defined $duplex;
        next if $duplex =~ /other/i;
        $i_duplex{$iid} = 'half' if $duplex =~ /half/i;
        $i_duplex{$iid} = 'full' if $duplex =~ /full/i;
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $n1600 = shift;
    my $partial = shift;

    my $nway_state = $n1600->n1600_nway_state($partial) || {};
    
    my %i_duplex;
    foreach my $iid (keys %$nway_state){
        my $duplex = $nway_state->{$iid};
        next unless defined $duplex;
        next if $duplex =~ /other/i;
        $i_duplex{$iid} = 'half' if $duplex =~ /half/i;
        $i_duplex{$iid} = 'full' if $duplex =~ /full/i;
        $i_duplex{$iid} = 'auto' if $duplex =~ /nway-enabled/i;
    }
    return \%i_duplex;
}

# Required for SNMP::Info::SONMP
sub index_factor {
    return 64;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::N1600 - SNMP Interface to Nortel 16XX Network Devices

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $n1600 = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          # These arguments are passed directly on to SNMP::Session
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 1
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $n1600->class();

 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Provides abstraction to the configuration information obtainable from a Nortel 
N16XX device through SNMP. 

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

my $n1600 = new SNMP::Info::Layer3::N1600(...);

=head2 Inherited Classes

=over

=item SNMP::Info::Layer3

=item SNMP::Info::SONMP

=back

=head2 Required MIBs

=over

=item SWL2MGMT-MIB

=item RAPID-CITY

=item Inherited Classes' MIBs

See classes listed above for their required MIBs.

=back

MIBs can be found on the CD that came with your product.

Or, they can be downloaded directly from Nortel regardless of support
contract status.

Go to http://www.nortel.com Techninal Support, Browse Technical Support,
Select by product, Java Device Manager, Software.  Download the latest version.
After installation, all mibs are located under the install directory under mibs
and the repspective product line.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $n1600->bulkwalk_no

Return C<1>.  Bulkwalk is currently turned off for this class.

=item $n1600->model()

Returns model type.  Checks $n1600->id() against the 
RAPID-CITY-MIB and then parses out rcA.

=item $n1600->vendor()

Returns 'nortel'

=item $n1600->os()

Returns 'passport'

=back

=head2 Overrides

=over

=item  $n1600->index_factor()

Required by SNMP::Info::SONMP.  Number representing the number of ports
reserved per slot within the device MIB.

Returns 64 since largest switch has 48 ports.  Since these switches can
not stack, the only requirment to reserve more than the max number of ports.

=back

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::SONMP

See documentation in SNMP::SONMP::Layer3 for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=head2 Overrides

=over

=item $n1600->interfaces()

Returns reference to hash of interface names to iids.

Places a 1 in front of index number.  This is required for compatibilty with
SNMP::Info::SONMP.

=item $n1600->i_duplex()

Returns reference to hash of interface operational link duplex status. 

=item $n1600->i_duplex_admin()

Returns reference to hash of interface administrative link duplex status. 

=back

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::SONMP

See documentation in L<SNMP::Info::SONMP/"TABLE METHODS"> for details.

=cut
