#!<<Make:PERL>>
#
# updatedevices.pl - Update Netdot Devices
#
# This script retrieves SNMP information from one ore more devices
# and updates the Netdot database.  It can retrive basic device information
# as well as bridge forwarding tables and ARP caches.
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model::Device;
use Netdot::Model::Topology;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;
#use Devel::Profiler bad_pkgs => [qw(UNIVERSAL Time::HiRes B Carp Exporter Cwd Config CORE DynaLoader XSLoader AutoLoader DBD::_::st DBD::_::db DBD::st DBD::db DBI::st DBI::db DBI::dr)];

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
my ($ATOMIC, $ADDSUBNETS, $SUBSINHERIT, $BGPPEERS, $INFO, $FWT, $TOPO, $ARP, $PRETEND, $HELP, $_DEBUG, $EMAIL);

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
        [--add-subnets] [--subs-inherit] [--with-bgp-peers] [--pretend] [--atomic]
        
    Email report args:
        [--send-mail] [--from <e-mail>] | [--to <e-mail>] | [--subject <subject>]
          
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
    --atomic                             Make updates atomic (enable transactions)
    --add-subnets                        When discovering routers, add subnets to database if they do not exist
    --subs-inherit                       When adding subnets, have them inherit information from the Device
    --with-bgp-peers                     When discovering routers, maintain their BGP Peers
    --pretend                            Do not commit changes to the database
    --send-mail                          Send logging output via e-mail instead of to STDOUT
    --from                               e-mail From line (default: $from)
    --subject                            e-mail Subject line (default: $subject)
    --to                                 e-mail To line (default: $to)
    -h, --help                           Print help (this message)
    -d, --debug                          Set syslog level to LOG_DEBUG

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
			 "atomic"            => \$ATOMIC,
			 "add-subnets"       => \$ADDSUBNETS,
			 "subs-inherit"      => \$SUBSINHERIT,
			 "with-bgp-peers"    => \$BGPPEERS,
			 "pretend"           => \$PRETEND,
			 "send-mail"         => \$EMAIL,
			 "from:s"            => \$from,
			 "to:s"              => \$to,
			 "subject:s"         => \$subject,
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
if ( ($host && $db) || ($host && $blocks) || ($host && $file ) || ($db && $blocks) || ($db && $file) || ($blocks && $file) ){
    print $USAGE;
    die "Error: arguments -H, -B, -D and -E are mutually exclusive\n";
}
unless ( $INFO || $FWT || $ARP || $TOPO ){
    print $USAGE;
    die "Error: You need to specify at least one of -I, -F, -A or -T\n";
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

if ( $INFO || $FWT || $ARP ){
    
    my %uargs = (communities  => $communities, 
		 version      => $version,
		 timeout      => $timeout,
		 retries      => $retries,
		 pretend      => $PRETEND,
		 atomic       => $ATOMIC,
		 add_subnets  => $ADDSUBNETS,
		 subs_inherit => $SUBSINHERIT,
		 bgp_peers    => $BGPPEERS,
		 do_info      => $INFO,
		 do_fwt       => $FWT,
		 do_arp       => $ARP,
	);
    
    if ( $host ){
	$logger->info("Updating single device: $host");
	$uargs{name} = $host;
	Device->discover(%uargs);
	
    }elsif ( $blocks ){
	my @blocks = split ',', $blocks;
	map { $_ =~ s/\s+//g } @blocks;
	$logger->info("Updating all devices in $blocks");
	$uargs{blocks} = \@blocks;
	Netdot::Model::Device->snmp_update_block(%uargs);
	
    }elsif ( $db ){
	$logger->info("Updating all devices in the DB");
	Netdot::Model::Device->snmp_update_all(%uargs);
	
    }elsif ( $file ){
	$logger->info("Updating all devices in given file: $file");
	$uargs{file} = $file;
	Netdot::Model::Device->snmp_update_from_file(%uargs);
	
    }else{
	print $USAGE;
	die "Error: You need to specify one of: -H, -B, -E, -D or -T\n";
    }
}

Netdot::Model::Topology->discover if ( $TOPO );

$logger->info(sprintf("$0 total runtime: %s secs\n", (time - $start)));

if ( $EMAIL ){
    Netdot->send_mail(from    => $from,
		      to      => $to,
		      subject => $subject, 
		      body    => $logstr->string);
}

