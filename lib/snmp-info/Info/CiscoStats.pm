# SNMP::Info::CiscoStats
# $Id: CiscoStats.pm,v 1.22 2008/08/02 03:21:25 jeneric Exp $
#
# Changes since Version 0.7 Copyright (c) 2008 Max Baker
# All rights reserved.
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

package SNMP::Info::CiscoStats;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::CiscoStats::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::CiscoStats::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = (
    'SNMPv2-MIB'            => 'sysDescr',
    'CISCO-PROCESS-MIB'     => 'cpmCPUTotal5sec',
    'CISCO-MEMORY-POOL-MIB' => 'ciscoMemoryPoolUsed',
    'OLD-CISCO-SYSTEM-MIB'  => 'writeMem',
    'CISCO-PRODUCTS-MIB'    => 'sysName',

    # some older catalysts live here
    'CISCO-STACK-MIB'                 => 'wsc1900sysID',
    'CISCO-ENTITY-VENDORTYPE-OID-MIB' => 'cevChassis',
    'CISCO-FLASH-MIB'                 => 'ciscoFlashDeviceSize',
);

%GLOBALS = (
    'description' => 'sysDescr',

    # We will use the numeric OID's so that we don't require people
    # to install v1 MIBs, which can conflict.
    # OLD-CISCO-CPU-MIB:avgBusyPer
    'ios_cpu'      => '1.3.6.1.4.1.9.2.1.56.0',
    'ios_cpu_1min' => '1.3.6.1.4.1.9.2.1.57.0',
    'ios_cpu_5min' => '1.3.6.1.4.1.9.2.1.58.0',

    # CISCO-PROCESS-MIB
    'cat_cpu'      => 'cpmCPUTotal5sec.9',
    'cat_cpu_1min' => 'cpmCPUTotal1min.9',
    'cat_cpu_5min' => 'cpmCPUTotal5min.9',

    # OLD-CISCO-SYSTEM-MIB
    'write_mem' => 'writeMem',
);

%FUNCS = (

    # CISCO-MEMORY-POOL-MIB::ciscoMemoryPoolTable
    'cisco_mem_free' => 'ciscoMemoryPoolFree',
    'cisco_mem_used' => 'ciscoMemoryPoolUsed',

    # CISCO-FLASH-MIB::ciscoFlashDeviceTable
    'cisco_flash_size' => 'ciscoFlashDeviceSize',
);

%MUNGE = ();

sub os {
    my $l2 = shift;
    my $descr = $l2->description() || '';

    # order here matters - there are Catalysts that run IOS and have catalyst
    # in their description field.
    return 'ios'      if ( $descr =~ /IOS/ );
    return 'catalyst' if ( $descr =~ /catalyst/i );
    return;
}

sub os_ver {
    my $l2    = shift;
    my $os    = $l2->os();
    my $descr = $l2->description();

    # Older Catalysts
    if (    defined $os
        and $os eq 'catalyst'
        and defined $descr
        and $descr =~ m/V(\d{1}\.\d{2}\.\d{2})/ )
    {
        return $1;
    }

    # Newer Catalysts and IOS devices
    if ( defined $descr
        and $descr =~ m/Version (\d+\.\d+\([^)]+\)[^,\s]*)(,|\s)+/ )
    {
        return $1;
    }
    return;
}

sub cpu {
    my $self    = shift;
    my $ios_cpu = $self->ios_cpu();
    return $ios_cpu if defined $ios_cpu;
    my $cat_cpu = $self->cat_cpu();
    return $cat_cpu;
}

sub cpu_1min {
    my $self         = shift;
    my $ios_cpu_1min = $self->ios_cpu_1min();
    return $ios_cpu_1min if defined $ios_cpu_1min;
    my $cat_cpu_1min = $self->cat_cpu_1min();
    return $cat_cpu_1min;
}

sub cpu_5min {
    my $self         = shift;
    my $ios_cpu_5min = $self->ios_cpu_5min();
    return $ios_cpu_5min if defined $ios_cpu_5min;
    my $cat_cpu_5min = $self->cat_cpu_5min();
    return $cat_cpu_5min;
}

sub mem_free {
    my $self = shift;

    my $mem_free;

    my $cisco_mem_free = $self->cisco_mem_free() || {};

    foreach my $mem_free_val ( values %$cisco_mem_free ) {
        $mem_free += $mem_free_val;
    }

    return $mem_free;
}

sub mem_used {
    my $self = shift;

    my $mem_used;

    my $cisco_mem_used = $self->cisco_mem_used() || {};

    foreach my $mem_used_val ( values %$cisco_mem_used ) {
        $mem_used += $mem_used_val;
    }

    return $mem_used;
}

sub mem_total {
    my $self = shift;

    my $mem_total;

    my $cisco_mem_free = $self->cisco_mem_free() || {};
    my $cisco_mem_used = $self->cisco_mem_used() || {};

    foreach my $mem_entry ( keys %$cisco_mem_free ) {
        my $mem_free = $cisco_mem_free->{$mem_entry} || 0;
        my $mem_used = $cisco_mem_used->{$mem_entry} || 0;
        $mem_total += ( $mem_free + $mem_used );
    }
    return $mem_total;
}

sub flashmem_total {
    my $self = shift;

    my $flashmem_total;

    my $flash_sizes = $self->cisco_flash_size;

    foreach my $flash_index ( keys %$flash_sizes ) {
        $flashmem_total += $flash_sizes->{$flash_index};
    }

    return $flashmem_total;
}

1;
__END__

=head1 NAME

SNMP::Info::CiscoStats - Perl5 Interface to CPU and Memory stats for Cisco
Devices

=head1 AUTHOR

Max Baker

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $ciscostats = new SNMP::Info(
                    AutoSpecify => 1,
                    Debug       => 1,
                    # These arguments are passed directly on to SNMP::Session
                    DestHost    => 'myswitch',
                    Community   => 'public',
                    Version     => 2
                    ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $ciscostats->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::CiscoStats is a subclass of SNMP::Info that provides cpu, memory,
os and version information about Cisco Devices. 

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item F<CISCO-PRODUCTS-MIB>

=item F<CISCO-PROCESS-MIB>

=item F<CISCO-MEMORY-POOL-MIB>

=item F<SNMPv2-MIB>

=item F<OLD-CISCO-SYSTEM-MIB>

=item F<CISCO-STACK-MIB>

=item F<CISCO-ENTITY-VENDORTYPE-OID-MIB>

=item F<CISCO-FLASH-MIB>

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBALS

=over

=item $ciscostats->cpu()

Returns ios_cpu() or cat_cpu(), whichever is available.

=item $ciscostats->cpu_1min()

Returns ios_cpu_1min() or cat_cpu1min(), whichever is available.

=item $ciscostats->cpu_5min()

Returns ios_cpu_5min() or cat_cpu5min(), whichever is available.

=item $ciscostats->mem_total()

Returns mem_free() + mem_used()

=item $ciscostats->os()

Tries to parse if device is running IOS or CatOS from description()

=item $ciscostats->os_ver()

Tries to parse device operating system version from description()

=item $ciscostats->ios_cpu()

Current CPU usage in percent.

C<1.3.6.1.4.1.9.2.1.56.0> = 
C<OLD-CISCO-CPU-MIB:avgBusyPer>

=item $ciscostats->ios_cpu_1min()

Average CPU Usage in percent over the last minute.

C<1.3.6.1.4.1.9.2.1.57.0>

=item $ciscostats->ios_cpu_5min()

Average CPU Usage in percent over the last 5 minutes.

C<1.3.6.1.4.1.9.2.1.58.0>

=item $ciscostats->cat_cpu()

Current CPU usage in percent.

C<CISCO-PROCESS-MIB::cpmCPUTotal5sec.9>

=item $ciscostats->cat_cpu_1min()

Average CPU Usage in percent over the last minute.

C<CISCO-PROCESS-MIB::cpmCPUTotal1min.9>

=item $ciscostats->cat_cpu_5min()

Average CPU Usage in percent over the last 5 minutes.

C<CISCO-PROCESS-MIB::cpmCPUTotal5min.9>

=item $ciscostats->mem_free()

Main DRAM free of the device in bytes.

C<CISCO-MEMORY-POOL-MIB::ciscoMemoryPoolFree>

=item $ciscostats->mem_used()

Main DRAM used of the device in bytes.

C<CISCO-MEMORY-POOL-MIB::ciscoMemoryPoolUsed>

=item $ciscostats->mem_total()

Main DRAM of the device in bytes.

C<CISCO-MEMORY-POOL-MIB::ciscoMemoryPoolFree> +
C<CISCO-MEMORY-POOL-MIB::ciscoMemoryPoolUsed>

=item $ciscostats->flashmem_total()

Flash memory of the device in bytes.

C<CISCO-FLASH-MIB::ciscoFlashDeviceSize>

=back

=head1 TABLE METHODS

=head2 Cisco Memory Pool Table (C<ciscoMemoryPoolTable>)

=over

=item $ciscostats->cisco_mem_free()

The number of bytes from the memory pool that are currently unused on the
managed device.

(C<ciscoMemoryPoolFree>)

=item $ciscostats->cisco_mem_used()

The number of bytes from the memory pool that are currently in use by
applications on the managed device.

(C<ciscoMemoryPoolUsed>)

=back

=head2 Cisco Flash Device Table (C<ciscoFlashDeviceTable>)

=over

=item $ciscostats->cisco_flash_size()

Total size of the Flash device.  For a removable device, the size will be
zero if the device has been removed.

(C<ciscoFlashDeviceSize>)

=back

=cut
