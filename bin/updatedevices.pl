#!<<Make:PERL>>
#
# updatedevices.pl - Update Netdot Devices
#
# This script retrieves SNMP information from one ore more devices
# and updates the Netdot database.  It can retrive basic device information
# as well as bridge forwarding tables and ARP caches. In addition, it can
# execute the topology discovery process.
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model::Device;
use Netdot::Topology;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;

# Variables that will hold given values
my ($host, $blocks, $db, $matching, $file, $commstrs, $version, $sec_name, 
    $sec_level, $auth_proto, $auth_pass, $priv_proto, $priv_pass);

# Default values
my $retries = Netdot->config->get('DEFAULT_SNMPRETRIES');
my $timeout = Netdot->config->get('DEFAULT_SNMPTIMEOUT');

# Flags
my ($ATOMIC, $ADDSUBNETS, $SUBSINHERIT, $BGPPEERS, $RECURSIVE, $INFO, $FWT, 
    $TOPO, $ARP, $AUTO_DNS, $PRETEND, $HELP, $_DEBUG);

$ENV{REMOTE_USER} = "netdot";

my $USAGE = <<EOF;
 usage: $0 [ optional args ]

    Scope args:
        -H, --host <hostname|address> | -D, --db |  -B, --block <address/prefix>[, ...] | -E, --file <PATH>

    Action args:
        -I, --info  | -F, --fwt  | -A, --arp | -T, --topology

    Optional args:
        [-c, --community] [-r, --retries] [-o, --timeout] [-v, --version] [-d, --debug] 
        [--add-subnets <0|1>] [--subs-inherit <0|1>] [--with-bgp-peers <0|1>] 
        [-m, --matching] [--pretend] [--atomic]
        
    Argument Detail: 
    -H, --host <hostname|address>        Update given host only.
    -B, --blocks <address/prefix>[, ...] Specify an IP block (or blocks) to discover
    -D, --db                             Update only DB existing devices
    -m, --matching <regex>               Update only devices whose names match pattern (with -B, -D, -E)
    -E, --file                           Update devices listed in given file
    -c, --communities <string>[, ...]    SNMP community string(s)
    -r, --retries <integer >             SNMP retries (default: $retries)
    -o, --timeout <secs>                 SNMP timeout in seconds (default: $timeout)
    -v, --version <integer>              SNMP version [1|2|3]
    --sec-name <string>                  SNMP security name
    --sec-level <string>                 SNMP security level [noAuthNoPriv|authNoPriv|authPriv]
    --auth-proto <string>                SNMP authentication protocol [MD5|SHA]
    --auth-pass <string>                 SNMP authentication key
    --priv-proto <string>                SNMP privacy protocol [DES|AES]
    --priv-pass <string>                 SNMP privacy key
    -I, --info                           Get device info
    -F, --fwt                            Get forwarding tables
    -T, --topology                       Update Topology
    -A, --arp                            Get ARP tables
    -N, --auto-dns                       Generate DNS records for interface IPs
    --atomic                             Make updates atomic (enable transactions)
    --add-subnets <0|1>                  Enable/Disable trying to add subnets from routing devices
    --subs-inherit <0|1>                 Enable/Disable having new subnets inherit information from device 
    --with-bgp-peers <0|1>               Enable/Disable maintaining BGP peer information
    --pretend                            Do not commit changes to the database
    --recursive                          Recursively discover unknown neighbors (with -T)
    -h, --help                           Print help (this message)
    -d, --debug                          Set syslog level to LOG_DEBUG

Options override default settings from config file.
    
EOF
    
# handle cmdline args
my $result = GetOptions( "H|host=s"          => \$host,
			 "B|blocks=s"        => \$blocks,
			 "D|db"              => \$db,
			 "m|matching=s"      => \$matching,
			 "E|file=s"          => \$file,
			 "I|info"            => \$INFO,
			 "F|fwt"             => \$FWT,
			 "A|arp"             => \$ARP,
			 "T|topology"        => \$TOPO,
			 "N|auto-dns"        => \$AUTO_DNS,
			 "c|communities:s"   => \$commstrs,
			 "r|retries:s"       => \$retries,
			 "o|timeout:s"       => \$timeout,
			 "v|version:s"       => \$version,
			 "sec-name:s"        => \$sec_name,
			 "sec-level:s"       => \$sec_level,
			 "auth-proto:s"      => \$auth_proto,
			 "auth-pass:s"       => \$auth_pass,
			 "priv-proto:s"      => \$priv_proto,
			 "priv-pass:s"       => \$priv_pass,
			 "atomic"            => \$ATOMIC,
			 "add-subnets:s"     => \$ADDSUBNETS,
			 "subs-inherit:s"    => \$SUBSINHERIT,
			 "with-bgp-peers:s"  => \$BGPPEERS,
			 "pretend"           => \$PRETEND,
			 "recursive"         => \$RECURSIVE,
			 "h|help"            => \$HELP,
			 "d|debug"           => \$_DEBUG,
);

if ( ! $result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $HELP ) {
    print $USAGE;
    exit;
}
if ( ($host && $db) || ($host && $blocks) || ($host && $file ) || ($db && $blocks) 
     || ($db && $file) || ($blocks && $file) ){
    print $USAGE;
    die "Error: arguments -H, -B, -D and -E are mutually exclusive\n";
}
unless ( $INFO || $FWT || $ARP || $TOPO || $AUTO_DNS ){
    print $USAGE;
    die "Error: You need to specify at least one of -I, -F, -A, -T or N\n";
}

foreach my $flagref ( \$ADDSUBNETS, \$SUBSINHERIT, \$BGPPEERS ){
    if ( defined $$flagref && !($$flagref =~ /^(:?0|1)$/o) ){
	print $USAGE;
	die "Error: Invalid value for boolean parameter";
    }
}

# Common update arguments
my %uargs = (version      => $version,
	     timeout      => $timeout,
	     retries      => $retries,
	     sec_name     => $sec_name,
	     sec_level    => $sec_level,
	     auth_proto   => $auth_proto,
	     auth_pass    => $auth_pass,
	     priv_proto   => $priv_proto,
	     priv_pass    => $priv_pass,
    );

my @communities = split ',', $commstrs if defined $commstrs;
# Remove any spaces
map { $_ =~ s/\s+// } @communities;

$uargs{communities} = \@communities if @communities;

# Add a log appender 
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);

# Associate new screen appender with relevant loggers
my $logger = Netdot->log->get_logger('Netdot::Model::Device');
$logger->add_appender($logscr);

my $dns_logger = Netdot->log->get_logger('Netdot::Model::DNS');
$dns_logger->add_appender($logscr);

my $ip_logger = Netdot->log->get_logger('Netdot::Model::Ipblock');
$ip_logger->add_appender($logscr);

if ( $_DEBUG ){
    $logger->level($DEBUG);
    $dns_logger->level($DEBUG); 
    $ip_logger->level($DEBUG); 
}

$logger->warn("Warning: Pretend (-p) flag enabled.  Changes will not be committed to the DB")
    if ( $PRETEND );

my $start = time;
$logger->info(sprintf("$0 started at %s", scalar localtime($start)));

if ( $INFO || $FWT || $ARP ){
    
    # Arguments specific to these functions
    my %dargs = (
	pretend      => $PRETEND,
	atomic       => $ATOMIC,
	add_subnets  => $ADDSUBNETS,
	subs_inherit => $SUBSINHERIT,
	bgp_peers    => $BGPPEERS,
	do_info      => $INFO,
	do_fwt       => $FWT,
	do_arp       => $ARP,
	matching     => $matching,
	);

    # Add the common update arguments
    while ( my($key, $val) = each %uargs ){
	$dargs{$key} = $val;
    }

    if ( $host ){
	$logger->info("Updating single device: $host");
	$dargs{name} = $host;
	eval {
	    Device->discover(%dargs);
	};
	die "ERROR: $@\n" if $@;
	
    }elsif ( $blocks ){
	my @blocks = split ',', $blocks;
	map { $_ =~ s/\s+//g } @blocks;
	$logger->info("Updating all devices in $blocks");
	$dargs{blocks} = \@blocks;
	Netdot::Model::Device->snmp_update_block(%dargs);
	
    }elsif ( $db ){
	$logger->info("Updating all devices in the DB");
	Netdot::Model::Device->snmp_update_all(%dargs);
	
    }elsif ( $file ){
	$logger->info("Updating all devices in given file: $file");
	$dargs{file} = $file;
	Netdot::Model::Device->snmp_update_from_file(%dargs);
	
    }else{
	print $USAGE;
	die "Error: You need to specify one of: -H, -B, -E, or -D\n";
    }
}

if ( $AUTO_DNS ){
    if ( $host || $blocks || $file ){
	die "Error: AUTO DNS option only works with -D"
    }elsif ( $db ){
	$logger->info("Generating DNS for interface IPs on all devices");
	Netdot::Model::Device->do_auto_dns_all();
    }
}

if ( $TOPO ){
    $logger = Netdot->log->get_logger('Netdot::Topology');
    $logger->level($DEBUG) if ( $_DEBUG ); # Notice that $DEBUG is imported from Log::Log4perl
    $logger->add_appender($logscr);
    $uargs{recursive} = 1 if $RECURSIVE;
    Netdot::Topology->discover(%uargs);
}

$logger->info(sprintf("$0 total runtime: %s", Netdot->sec2dhms(time-$start)));

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2016 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut
