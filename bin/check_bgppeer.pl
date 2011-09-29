#!/usr/bin/perl -w
#
# check_bgppeer.pl - nagios plugin 
#
# Copyright (C) 2009 Carlos Vicente
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
#
# Report bugs to: cvicente(at)ns.uoregon.edu
#
# 08/05/2009 Version 1.1
# 09/29/2011 Version 1.2 - Fixed incorrect return values
#

use SNMP;
use strict;
use Getopt::Long qw(:config no_ignore_case bundling);

# whois program for Registry database queries
my $whois      = '/usr/bin/whois';
my $whoissrv   = 'whois.arin.net';
my $whoisfield = "ASName";
my $TIMEOUT    = 30;
my %self;

my %ERRORS = (
    'OK'       => 0,
    'WARNING'  => 1,
    'CRITICAL' => 2,
    'UNKNOWN'  => 3,
    );

my %PEERSTATE = (1 => "idle",
		 2 => "connect",
		 3 => "active",
		 4 => "opensent",
		 5 => "openconfirm",
		 6 => "established",
		 7 => "established"    # Deal with JUNOS < 8.0 bug
		 );

my $state = "UNKNOWN";
my $bgpPeerState    = '1.3.6.1.2.1.15.3.1.2';
my $bgpPeerRemoteAs = '1.3.6.1.2.1.15.3.1.9';

my $usage = <<EOF;

  Perl BGP peer check plugin for Nagios
  Monitors BGP session of a particular peer

  Copyright (C) 2009 Carlos Vicente
  $0 comes with ABSOLUTELY NO WARRANTY
  This programm is licensed under the terms of the
  GNU General Public License\n(check source code for details)
  exit $ERRORS{"UNKNOWN"};

  usage: $0 -H <hostname> -a <peer_address> [-c <community>] [-v <1|2|3>]

    -H, --host         Hostname
    -a, --address      BGP Peer remote address (NOT peer ID)
    -c, --comm         SNMP community (default: public)
    -v, --version      SNMP version (default: 1)
    -w, --whois        Query WHOIS for AS name
    -d, --debug        Print debugging output
    -h, --help         Show this message

EOF

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
     print ("ERROR: No response from $self{HOSTNAME} (alarm)\n");
     exit $ERRORS{"UNKNOWN"};
};
alarm($TIMEOUT);


# handle cmdline args
my $result = GetOptions( 
    "H|hostname=s"   => \$self{HOSTNAME},
    "a|address=s"    => \$self{PEER},
    "c|comm=s"       => \$self{COMMUNITY},
    "w|whois"        => \$self{WHOIS},
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
unless ( $self{HOSTNAME} && $self{PEER} ){
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

my @varlist;
push (@varlist, [$bgpPeerState,     $self{PEER}]);
push (@varlist, [$bgpPeerRemoteAs,  $self{PEER}]);

my $vars = new SNMP::VarList(@varlist);
my ($stateval, $as) = $sess->get($vars);
my $bgp_state;

if ( $stateval ){
    $bgp_state = $PEERSTATE{$stateval};
}else{
    $state = 'UNKNOWN';
    print "$state: Peer $self{PEER} not in table\n";
    exit $ERRORS{$state};        
}

if ( $bgp_state eq 'established' || $bgp_state eq 'idle' ) { 
    $state = 'OK';
    print "$state\n";
}else { 
    $state = 'CRITICAL';
    my $asname = "n/a";
    if ( $self{WHOIS} ){
	&debug("Quering WHOIS server $whoissrv");
	
	my @output = `$whois -h $whoissrv AS$as`;
	my ($name, $value);
	foreach (@output) {
	    if (/No entries found/i){
		last;
	    }
	    if (/$whoisfield:/){
		(undef, $asname) = split /\s+/, $_;
		last;
	    }
	}
    }
    print ("$state: $as ($asname) is $bgp_state\n");
}

exit $ERRORS{$state};

sub debug{
    print STDERR @_, "\n" if $self{DEBUG};
}
