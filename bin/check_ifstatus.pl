#!/usr/bin/perl -w
#
# check_ifstatus.pl - Nagios plugin 
#
# Copyright (C) 2009 Carlos Vicente - University of Oregon
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
# Report bugs to: cvicente(at)ns.uoregon.edu
#
# 07/28/2009 Version 1.0
# 09/29/2011 Version 1.1 - Fixed incorrect return values
#

use SNMP;
use strict;
use Getopt::Long qw(:config no_ignore_case bundling);
my %ERRORS = (
    'OK'       => 0,
    'WARNING'  => 1,
    'CRITICAL' => 2,
    'UNKNOWN'  => 3,
    );

my $state = 'UNKNOWN';
my %self;
my $oper_status_oid  = '.1.3.6.1.2.1.2.2.1.8';
my $admin_status_oid = '.1.3.6.1.2.1.2.2.1.7';
my $descr_oid        = '.1.3.6.1.2.1.2.2.1.2';
my $alias_oid        = '.1.3.6.1.2.1.31.1.1.1.18';

my $usage = <<EOF;

 Interface status plugin for Nagios
 Status is critical if the Interface oper status is down
 but its admin status is up.  This avoids notifying for
 interfaces that have been intentionally turned off.

 Copyright (C) 2009 Carlos Vicente
 $0 comes with ABSOLUTELY NO WARRANTY
 This programm is licensed under the terms of the
 GNU General Public License (check source code for details)

 usage: $0  -H <hostname> -i <ifIndex> [-c <community>] [-v <1|2|3>]

    -H, --host         Hostname
    -i, --ifindex      Interface index
    -c, --comm         SNMP community (default: public)
    -v, --version      SNMP version (default: 1)
    -d, --debug        Print debugging output
    -h, --help         Show this message
    
EOF
    
# handle cmdline args
my $result = GetOptions( 
    "H|hostname=s"   => \$self{HOSTNAME},
    "i|ifindex=s"    => \$self{IFINDEX},
    "c|comm=s"       => \$self{COMMUNITY},
    "v|version=s"    => \$self{VERSION},
    "d|debug"        => \$self{DEBUG},
    "h|help"         => \$self{HELP},
    );

if( ! $result ) {
    print $usage;
    print "Error: Problem with cmdline args\n";
    exit $ERRORS{'UNKNOWN'};
}
if( $self{HELP} ) {
    print $usage;
    exit $ERRORS{'UNKNOWN'};
}
unless ( $self{HOSTNAME} && $self{IFINDEX} ){
    print $usage;
    print "Missing required parameters\n";
    exit $ERRORS{'UNKNOWN'};
}

$self{COMMUNITY} ||= 'public';
$self{VERSION}   ||= '1';

&debug("Connecting to $self{HOSTNAME}");
my $sess = new SNMP::Session( 
    DestHost    => $self{HOSTNAME},
    Community   => $self{COMMUNITY},
    Version     => $self{VERSION},
    );

# No session object created
unless ( $sess ){
    $state = 'UNKNOWN';
    print "$state: Connection failed\n";
    exit $ERRORS{$state};
}

# Session object created but SNMP connection failed.
my $sess_err = $sess->{ErrorStr} || '';
if ( $sess_err ){
    $state = 'UNKNOWN';
    print "$state: $sess_err\n";
    exit $ERRORS{$state};    
}

my $vars = new SNMP::VarList([$admin_status_oid,$self{IFINDEX}], [$oper_status_oid,$self{IFINDEX}], 
			     [$descr_oid,$self{IFINDEX}], [$alias_oid,$self{IFINDEX}]);
my ($admin_status, $oper_status, $descr, $alias) = $sess->get($vars);

if ( !(defined $admin_status) || $admin_status eq "" ||
     !(defined $oper_status)  || $oper_status eq "" ){
    $state = 'UNKNOWN';
    print "$state: Missing data\n";
    exit $ERRORS{$state};    
}
if ( ($admin_status != 1 && $admin_status != 2) || 
     ($oper_status  != 1 && $oper_status  != 2) ){
    $state = 'UNKNOWN';
    print "$state: Invalid data\n";
    debug ("admin_status: $admin_status, oper_status: $oper_status");
    exit $ERRORS{$state};    
}

if ( $alias =~ /NOSUCH/ ){
    $alias = 'n/a';
}
$descr .= " ($alias)";

# We only care if the interface is admin up but oper down
if ( $admin_status == 1 && $oper_status == 2 ){
    $state = 'CRITICAL';
    print "$state: $descr\n";
}elsif ( ($admin_status == 1 && $oper_status == 1) ||
	 ($admin_status == 2 && $oper_status == 2) ) {
    $state = 'OK';
    print "$state $descr\n";
}else{
    $state = 'UNKNOWN';
    print "$state: Invalid data\n";
    debug ("admin_status: $admin_status, oper_status: $oper_status");
    exit $ERRORS{$state};    
}
exit $ERRORS{$state};

sub debug{
    print STDERR @_, "\n" if $self{DEBUG};
}
