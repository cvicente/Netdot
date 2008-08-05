# $Id: CiscoImage.pm,v 1.11 2008/08/02 03:21:25 jeneric Exp $
#
# Copyright (c) 2005 Matt Tuttle
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

package SNMP::Info::CiscoImage;

use strict;
use Exporter;
use SNMP::Info;

@SNMP::Info::CiscoImage::ISA       = qw/SNMP::Info Exporter/;
@SNMP::Info::CiscoImage::EXPORT_OK = qw//;

use vars qw/$VERSION %MIBS %FUNCS %GLOBALS %MUNGE/;

$VERSION = '2.00';

%MIBS = ( 'CISCO-IMAGE-MIB' => 'ciscoImageString', );

%GLOBALS = ();

%FUNCS = ( 'ci_images' => 'ciscoImageString', );

%MUNGE = ();

1;
__END__

=head1 NAME

SNMP::Info::CiscoImage - SNMP Interface to image strings for Cisco Devices

=head1 AUTHOR

Matt Tuttle (C<mtuttle@americanhebrewacademy.org>)

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you.
 my $ci = new SNMP::Info(
                AutoSpecify => 1,
                Debug       => 1,
                # These arguments are passed directly on to SNMP::Session
                DestHost    => 'myswitch',
                Community   => 'public',
                Version     => 2
                )
    or die "Can't connect to DestHost.\n";

 my $class = $ci->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

SNMP::Info::CiscoImage is a subclass of SNMP::Info that provides access to
image strings embedded in an image running on Cisco Devices.

Use or create in a subclass of SNMP::Info.  Do not use directly.

=head2 Inherited Classes

None.

=head2 Required MIBs

=over

=item F<CISCO-IMAGE-MIB>

=back

MIBs can be found at ftp://ftp.cisco.com/pub/mibs/v2/v2.tar.gz

=head1 GLOBALS

None.

=head1 TABLE METHODS

=over

=item $ci->ci_images()

Returns the table of image strings.

C<ciscoImageString>

=back

=cut
