#!<<Make:PERL>>
#
# updatedevices.pl - Update Netdot Devices
#
# This script retrieves SNMP information from one ore more devices
# and updates the Netdot database.  It can retrive basic device information
# as well as bridge forwarding tables and ARP caches.
#
use lib "<<Make:LIB>>";
use Netdot::Model::Device;
use Netdot::Model::Topology;
use Netdot::Util::Misc;
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;
use Log::Log4perl::Level;
#use Devel::Profiler bad_pkgs => [qw(UNIVERSAL Time::HiRes B Carp Exporter Cwd Config CORE DynaLoader XSLoader AutoLoader
#					DBD::_::st DBD::_::db DBD::st DBD::db DBI::st DBI::db DBI::dr)];

# Variables that will hold given values
my ($host, $blocks, $db, $file);

# Default values
my $communities     = Netdot->config->get('DEFAULT_SNMPCOMMUNITIES');
my $commstrs        = join ", ", @$communities if defined $communities;
my $retries         = Netdot->config->get('DEFAULT_SNMPRETRIES');
my $timeout         = Netdot->config->get('DEFAULT_SNMPTIMEOUT');
my $version         = Netdot->config->get('DEFAULT_SNMPVERSION');
my $from            = Netdot->config->get('ADMINEMAIL');
my $to              = Netdot->config->get('NOCEMAIL');
my $subject         = 'Netdot Device Updates';

# Flags
my ($ADDSUBNETS, $SUBSINHERIT, $BGPPEERS, $INFO, $FWT, $TOPO, $ARP, $PRETEND, $HELP, $_DEBUG, $EMAIL);

# This will be reflected in the history tables
$ENV{REMOTE_USER}   = "netdot";

my $USAGE = <<EOF;
 usage: $0 [ optional args ]

    Scope args:
        -H, --host <hostname|address> | -D, --db |  -B, --block <address/prefix>[, ...] | -E, --file <PATH>

    Action args:
        -I, --info  | -F, --fwt  | -A, --arp | -T, --topology

    Optional args:
        [c, --community] [r, --retries] [o, --timeout] [v, --version] [d, --debug]
        [a, --add-subnets] [i, --subs-inherit] [-b, --with-bgp-peers] [-p, --pretend] 
        
    Email report args:
        [-m|--send-mail] [-f|--from <e-mail>] | [-t|--to <e-mail>] | [-s|--subject <subject>]
          
    Argument Detail: 
    -H, --host <hostname|address>        Update given host only.
    -B, --blocks <address/prefix>[, ...]  Specify an IP block (or blocks) to discover
    -D, --db                             Update only DB existing devices
    -E, --file                           Update devices listed in given file
    -c, --community <string>             SNMP community string(s) (default: $commstrs)
    -r, --retries <integer >             SNMP retries (default: $retries)
    -o, --timeout <secs>                 SNMP timeout in seconds (default: $timeout)
    -v, --version <integer>              SNMP version [1|2|3] (default: $version)
    -I, --info                           Get device info
    -F, --fwt                            Get forwarding tables
    -T, --topology                       Update Topology
    -A, --arp                            Get ARP tables
    -a, --add-subnets                    When discovering routers, add subnets to database if they do not exist
    -i, --subs-inherit                   When adding subnets, have them inherit information from the Device
    -b, --with-bgp-peers                 When discovering routers, maintain their BGP Peers
    -p, --pretend                        Do not commit changes to the database
    -h, --help                           Print help (this message)
    -d, --debug                          Set syslog level to LOG_DEBUG
    -m, --send-mail                      Send logging output via e-mail instead of to STDOUT
    -f, --from                           e-mail From line (default: $from)
    -s, --subject                        e-mail Subject line (default: $subject)
    -t, --to                             e-mail To line (default: $to)

Options override default settings from config file.
    
EOF
    
# handle cmdline args
my $result = GetOptions( "H|host=s"          => \$host,
			 "B|blocks=s"        => \$blocks,
			 "D|db"              => \$db,
			 "E|file=s"          => \$file,
			 "I|info"            => \$INFO,
			 "F|fwt"             => \$FWT,
			 "A|arp"             => \$ARP,
			 "T|topology"        => \$TOPO,
			 "c|communities:s"   => \$commstrs,
			 "r|retries:s"       => \$retries,
			 "o|timeout:s"       => \$timeout,
			 "v|version:s"       => \$version,
			 "a|add-subnets"     => \$ADDSUBNETS,
			 "i|subs-inherit"    => \$SUBSINHERIT,
			 "b|with-bgp-peers"  => \$BGPPEERS,
			 "p|pretend"         => \$PRETEND,
			 "h|help"            => \$HELP,
			 "d|debug"           => \$_DEBUG,
			 "m|send-mail"       => \$EMAIL,
			 "f|from:s"          => \$from,
			 "t|to:s"            => \$to,
			 "s|subject:s"       => \$subject);

if ( ! $result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $HELP ) {
    print $USAGE;
    exit;
}
if ( ($host && $db) || ($host && $blocks) || ($host && $file ) || ($db && $blocks) || ($db && $file) || ($blocks && $file) ){
    print $USAGE;
    die "Error: arguments -H, -B, -D and -E are mutually exclusive\n";
}
unless ( $INFO || $FWT || $ARP || $TOPO ){
    print $USAGE;
    die "Error: You need to specify at least one of -I, -F, -A or -T\n";
}

if ( $TOPO && ( $host ) ){
    print $USAGE;
    die "Error: Topology discovery can not be applied to hosts";
}

# Re-read communities, in case we were passed new ones
@$communities = split ',', $commstrs if defined $commstrs;
# Remove any spaces
map { $_ =~ s/\s+// } @$communities;

die "Cannot proceed without SNMP communities!\n" 
    unless scalar @$communities;

# Add a log appender depending on the output type requested
my $logger = Netdot->log->get_logger('Netdot::Model::Device');
my ($logstr, $logscr);
if ( $EMAIL ){
    $logstr = Netdot::Util::Log->new_appender('String', name=>'updatedevices.pl');
    $logger->add_appender($logstr);
}else{
    $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
    $logger->add_appender($logscr);
}

if ( $_DEBUG ){
#   Set logging level to debug
#   Notice that $DEBUG is imported from Log::Log4perl
    $logger->level($DEBUG);
}

$logger->warn("Warning: Pretend (-p) flag enabled.  Changes will not be committed to the DB")
    if ( $PRETEND );

my $start = time;
$logger->info(sprintf("$0 started at %s", scalar localtime($start)));

my %uargs = (communities  => $communities, 
	     version      => $version,
	     timeout      => $timeout,
	     retries      => $retries,
	     pretend      => $PRETEND,
	     add_subnets  => $ADDSUBNETS,
	     subs_inherit => $SUBSINHERIT,
	     bgp_peers    => $BGPPEERS,
	     );
if ( $host ){
    $logger->info("Updating single device: $host");
    my $dev;
    if ( $INFO ){
	$uargs{name} = $host;
	$dev = Device->discover(%uargs);
    }
    if ( $FWT ){
	$dev ||= Device->search(name=>$host)->first;
	die "Error: Could not find $host in database\n" unless $dev;
	$dev->fwt_update();
    }
    if ( $ARP ){
	$dev ||= Device->search(name=>$host)->first;
	die "Error: Could not find $host in database\n" unless $dev;
	$dev->arp_update();
    }
}elsif ( $blocks ){
    my @blocks = split ',', $blocks;
    map { $_ =~ s/\s+//g } @blocks;
    $logger->info("Updating all devices in $blocks");
    $uargs{blocks} = \@blocks;
    Netdot::Model::Device->snmp_update_block(%uargs)    if ( $INFO );
    Netdot::Model::Device->fwt_update_block(%uargs)     if ( $FWT  );
    Netdot::Model::Device->arp_update_block(%uargs)     if ( $ARP  );
    Netdot::Model::Topology->discover(blocks=>\@blocks) if ( $TOPO );
}elsif ( $db ){
    $logger->info("Updating all devices in the DB");
    Netdot::Model::Device->snmp_update_all(%uargs) if ( $INFO );
    Netdot::Model::Device->fwt_update_all(%uargs)  if ( $FWT  );
    Netdot::Model::Device->arp_update_all(%uargs)  if ( $ARP  );
    Netdot::Model::Topology->discover              if ( $TOPO );
}elsif ( $file ){
    $logger->info("Updating all devices in given file: $file");
    $uargs{file} = $file;
    Netdot::Model::Device->snmp_update_from_file(%uargs) if ( $INFO );
    Netdot::Model::Device->fwt_update_from_file(%uargs)  if ( $FWT  );
    Netdot::Model::Device->arp_update_from_file(%uargs)  if ( $ARP  );
}else{
    print $USAGE;
    die "Error: You need to specify one of: -H, -B, -E or -D\n";
}

$logger->info(sprintf("$0 total runtime: %s secs\n", (time - $start)));

if ( $EMAIL ){
    my $util = Netdot::Util::Misc->new();
    $util->send_mail(from    => $from,
		     to      => $to,
		     subject => $subject, 
		     body    => $logstr->string);
}

