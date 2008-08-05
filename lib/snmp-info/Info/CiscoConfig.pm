# SNMP::Info::CiscoConfig
# $Id: CiscoConfig.pm,v 1.8 2008/08/02 03:21:25 jeneric Exp $
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

package SNMP::Info::CiscoConfig;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::CiscoConfig::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::CiscoConfig::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    'CISCO-CONFIG-COPY-MIB' => 'ccCopyTable',
    'CISCO-FLASH-MIB'       => 'ciscoFlashCopyTable',
    'OLD-CISCO-SYS-MIB'     => 'writeMem',
);

%GLOBALS = (

    # OLD-CISCO-SYS-MIB
    'old_write_mem' => 'writeMem',
    'old_write_net' => 'writeNet',
);

%FUNCS = (

    # CISCO-COPY-CONFIG-MIB::ccCopyTable
    'config_protocol'           => 'ccCopyProtocol',
    'config_source_type'        => 'ccCopySourceFileType',
    'config_dest_type'          => 'ccCopyDestFileType',
    'config_server_addr'        => 'ccCopyServerAddress',
    'config_filename'           => 'ccCopyFileName',
    'config_username'           => 'ccCopyUserName',
    'config_password'           => 'ccCopyUserPassword',
    'config_notify_complete'    => 'ccCopyNotificationOnCompletion',
    'config_copy_state'         => 'ccCopyState',
    'config_copy_start_time'    => 'ccCopyTimeStarted',
    'config_copy_complete_time' => 'ccCopyTimeCompleted',
    'config_fail_cause'         => 'ccCopyFailCause',
    'config_row_status'         => 'ccCopyEntryRowStatus',

    # CISCO-FLASH-MIB::ciscoFlashCopyTable
    'flash_copy_cmd'        => 'ciscoFlashCopyCommand',
    'flash_copy_protocol'   => 'ciscoFlashCopyProtocol',
    'flash_copy_address'    => 'ciscoFlashCopyServerAddress',
    'flash_copy_source'     => 'ciscoFlashCopySourceName',
    'flash_copy_dest'       => 'ciscoFlashCopyDestinationName',
    'flash_copy_row_status' => 'ciscoFlashCopyEntryStatus',
);

%MUNGE = ();

sub copy_run_tftp {
    my $ciscoconfig = shift;
    my ( $tftphost, $tftpfile ) = @_;

    srand( time() ^ ( $$ + ( $$ << 15 ) ) );
    my $rand = int( rand( 1 << 24 ) );

    print "Saving running config to $tftphost as $tftpfile\n"
        if $ciscoconfig->debug();

    #Try new method first fall back to old method
    if ( $ciscoconfig->set_config_protocol( 1, $rand ) ) {
        print "Using new method, row iid: $rand\n" if $ciscoconfig->debug();

        #Check each set, delete created row if any fail
        unless ( $ciscoconfig->set_config_source_type( 4, $rand ) ) {
            $ciscoconfig->error_throw("Setting source type failed");
            unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
                $ciscoconfig->error_throw(
                    "Setting source type failed and failed to delete row $rand"
                );
            }
            return;
        }
        unless ( $ciscoconfig->set_config_dest_type( 1, $rand ) ) {
            $ciscoconfig->error_throw("Setting destination type failed");
            unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
                $ciscoconfig->error_throw(
                    "Setting dest type failed and failed to delete row $rand"
                );
            }
            return;
        }
        unless ( $ciscoconfig->set_config_server_addr( $tftphost, $rand ) ) {
            $ciscoconfig->error_throw("Setting tftp server failed");
            unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
                $ciscoconfig->error_throw(
                    "Setting tftp server failed and failed to delete row $rand"
                );
            }
            return;
        }
        unless ( $ciscoconfig->set_config_filename( $tftpfile, $rand ) ) {
            $ciscoconfig->error_throw("Setting file name failed");
            unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
                $ciscoconfig->error_throw(
                    "Setting file name failed and failed to delete row $rand"
                );
            }
            return;
        }
        unless ( $ciscoconfig->set_config_row_status( 1, $rand ) ) {
            $ciscoconfig->error_throw("Initiating transfer failed");
            unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
                $ciscoconfig->error_throw(
                    "Initiating transfer failed and failed to delete row $rand"
                );
            }
            return;
        }
        my $status = 0;
        my $timer  = 0;

       # Hard-coded timeout of approximately 5 minutes, we can wrap this in an
       # option later if needed
        my $timeout = 300;
        while ( $status !~ /successful|failed/ ) {
            my $t = $ciscoconfig->config_copy_state($rand);
            $status = $t->{$rand};
            last if $status =~ /successful|failed/;
            $timer += 1;
            if ( $timer >= $timeout ) {
                $status = 'failed';
                last;
            }
            sleep 1;
        }

        unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
            print "Failed deleting row, iid $rand\n" if $ciscoconfig->debug();
        }

        if ( $status eq 'successful' ) {
            print "Save operation successful\n" if $ciscoconfig->debug();
            return 1;
        }
        if ( $status eq 'failed' ) {
            $ciscoconfig->error_throw("Save operation failed");
            return;
        }

    }

    print "Using old method\n" if $ciscoconfig->debug();
    unless ( $ciscoconfig->set_old_write_net( $tftpfile, $tftphost ) ) {
        $ciscoconfig->error_throw("Save operation failed");
        return;
    }

    return 1;
}

sub copy_run_start {
    my $ciscoconfig = shift;

    srand( time() ^ ( $$ + ( $$ << 15 ) ) );
    my $rand = int( rand( 1 << 24 ) );

    print "Saving running config to memory\n" if $ciscoconfig->debug();

    if ( $ciscoconfig->set_config_source_type( 4, $rand ) ) {
        print "Using new method, row iid: $rand\n" if $ciscoconfig->debug();

        #Check each set, delete created row if any fail
        unless ( $ciscoconfig->set_config_dest_type( 3, $rand ) ) {
            $ciscoconfig->error_throw("Setting dest type failed");
            unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
                $ciscoconfig->error_throw(
                    "Setting dest type failed and failed to delete row $rand"
                );
            }
            return;
        }
        unless ( $ciscoconfig->set_config_row_status( 1, $rand ) ) {
            $ciscoconfig->error_throw("Initiating save failed");
            unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
                $ciscoconfig->error_throw(
                    "Initiating save failed and failed to delete row $rand");
            }
            return;
        }
        my $status = 0;
        my $timer  = 0;

       # Hard-coded timeout of approximately 5 minutes, we can wrap this in an
       # option later if needed
        my $timeout = 300;
        while ( $status !~ /successful|failed/ ) {
            my $t = $ciscoconfig->config_copy_state($rand);
            $status = $t->{$rand};
            last if $status =~ /successful|failed/;
            $timer += 1;
            if ( $timer >= $timeout ) {
                $status = 'failed';
                last;
            }
            sleep 1;
        }

        unless ( $ciscoconfig->set_config_row_status( 6, $rand ) ) {
            print "Failed deleting row, iid $rand\n" if $ciscoconfig->debug();
        }

        if ( $status eq 'successful' ) {
            print "Save operation successful\n" if $ciscoconfig->debug();
            return 1;
        }
        if ( $status eq 'failed' ) {
            $ciscoconfig->error_throw("Save operation failed");
            return;
        }

    }

    print "Using old method\n" if $ciscoconfig->debug();
    unless ( $ciscoconfig->set_old_write_mem(1) ) {
        $ciscoconfig->error_throw("Save operation failed");
        return;
    }

    return 1;
}

1;
__END__


=head1 NAME

SNMP::Info::CiscoConfig - SNMP Interface to Cisco Configuration Files

=head1 AUTHOR

Justin Hunter, Eric Miller

=head1 SYNOPSIS

    my $ciscoconfig = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 

    or die "Can't connect to DestHost.\n";

    my $class = $ciscoconfig->class();
    print " Using device sub class : $class\n";

=head1 DESCRIPTION

SNMP::Info::CiscoConfig is a subclass of SNMP::Info that provides an interface
to F<CISCO-CONFIG-COPY-MIB>, F<CISCO-FLASH-MIB>, and F<OLD-CISCO-SYS-MIB>.
These MIBs facilitate the writing of configuration files.

Use or create a subclass of SNMP::Info that inherits this one.
Do not use directly.

=head2 Inherited Classes

=over

None.

=back

=head2 Required MIBs

=over

=item F<CISCO-CONFIG-COPY-MIB>

=item F<CISCO-FLASH-MIB>

=item F<OLD-CISCO-SYS-MIB>

=back

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $ciscoconfig->old_write_mem()

(C<writeMem>)

=item $ciscoconfig->old_write_net()

(C<writeNet>)

=back

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

=over

=back

=head2 Config Copy Request Table  (C<ccCopyTable>)

=over

=item $ciscoconfig->config_protocol()

(C<ccCopyProtocol>)

=item $ciscoconfig->config_source_type()

(C<ccCopySourceFileType>)

=item $ciscoconfig->config_dest_type()

(C<ccCopyDestFileType>)

=item $ciscoconfig->config_server_addr()

(C<ccCopyServerAddress>)

=item $ciscoconfig->config_filename()

(C<ccCopyFileName>)

=item $ciscoconfig->config_username()

(C<ccCopyUserName>)

=item $ciscoconfig->config_password()

(C<ccCopyUserPassword>)

=item $ciscoconfig->config_notify_complete()

(C<ccCopyNotificationOnCompletion>)

=item $ciscoconfig->config_copy_state()

(C<ccCopyState>)

=item $ciscoconfig->config_copy_start_time()

(C<ccCopyTimeStarted>)

=item $ciscoconfig->config_copy_complete_time()

(C<ccCopyTimeCompleted>)

=item $ciscoconfig->config_fail_cause()

(C<ccCopyFailCause>)

=item $ciscoconfig->config_row_status()

(C<ccCopyEntryRowStatus>)

=back

=head2 Flash Copy Table (C<ciscoFlashCopyTable>)

Table of Flash copy operation entries.

=over

=item $ciscoconfig->flash_copy_cmd()

(C<ciscoFlashCopyCommand>)

=item $ciscoconfig->flash_copy_protocol()

(C<ciscoFlashCopyProtocol>)

=item $ciscoconfig->flash_copy_address()

(C<ciscoFlashCopyServerAddress>)

=item $ciscoconfig->flash_copy_source()

(C<ciscoFlashCopySourceName>)

=item $ciscoconfig->flash_copy_dest()

(C<ciscoFlashCopyDestinationName>)

=item $ciscoconfig->flash_copy_row_status()

(C<ciscoFlashCopyEntryStatus>)

=back

=head1 SET METHODS

These are methods that provide SNMP set functionality for overridden methods
or provide a simpler interface to complex set operations.  See
L<SNMP::Info/"SETTING DATA VIA SNMP"> for general information on set
operations. 

=over

=item $ciscoconfig->copy_run_tftp (tftpserver, tftpfilename )

Store the running configuration on a TFTP server.  Equivalent to the CLI
commands "copy running-config tftp" or "write net".

This method attempts to use newer "copy running-config tftp" procedure first
and then the older "write net" procedure if that fails.  The newer procedure
is supported Cisco devices with the F<CISCO-CONFIG-COPY-MIB> available, Cisco
IOS software release 12.0 or on some devices as early as release 11.2P.  The
older procedure has been depreciated by Cisco and is utilized only to support
devices running older code revisions.

 Example:
 $ciscoconfig->copy_run_tftp('1.2.3.4', 'myconfig') 
    or die Couldn't save config. ",$ciscoconfig->error(1);

=item $ciscoconfig->copy_run_start()

Copy the running configuration to the start up configuration.  Equivalent to
the CLI command C<"copy running-config startup-config"> or C<"write mem">.

This method attempts to use newer C<"copy running-config startup-config">
procedure first and then the older C<"write mem"> procedure if that fails.
The newer procedure is supported Cisco devices with the
F<CISCO-CONFIG-COPY-MIB> available, Cisco IOS software release 12.0 or on
some devices as early as release 11.2P.  The older procedure has been
depreciated by Cisco and is utilized only to support devices running older
code revisions.

 Example:
 $ciscoconfig->copy_run_start()
    or die "Couldn't save config. ",$ciscoconfig->error(1);

=back

=cut
