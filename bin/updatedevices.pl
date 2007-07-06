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
use Netdot::Util::Misc;
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;
use Log::Log4perl::Level;

# Variables that will hold given values
my ($host, $block, $db);

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
my ($ADDSUBNETS, $SUBSINHERIT, $BGPPEERS, $INFO, $FWT, $ARP, $PRETEND, $HELP, $_DEBUG, $EMAIL, $PRETEND);

# This will be reflected in the history tables
$ENV{REMOTE_USER}   = "netdot";

my $USAGE = <<EOF;
 usage: $0 [ optional args ]
           -H, --host <hostname|address> | -d, --db |  -b, --block <address/prefix>
           [-I, --info]  [-F, --fwt]  [-A, --arp]
           [-m|--send_mail] [-f|--from] | [-t|--to] | [-S|--subject]
          
    
    -H, --host <hostname|address>  Update given host only.
    -b, --block <address/prefix>   Specify an IP block to discover
    -d, --db                       Update only DB existing devices
    -c, --community <string>       SNMP community string(s) (default: $commstrs)
    -r, --retries <integer >       SNMP retries (default: $retries)
    -t, --timeout <secs>           SNMP timeout in seconds (default: $timeout)
    -v, --version <integer>        SNMP version [1|2|3] (default: $version)
    -I, --info                     Get device info
    -F, --fwt                      Get forwarding tables
    -A, --arp                      Get ARP tables
    -a, --add-subnets              When discovering routers, add subnets to database if they do not exist
    -i, --subs_inherit             When adding subnets, have them inherit information from the Device
    -B, --with-bgp-peers           When discovering routers, maintain their BGP Peers
    -p, --pretend                  Do not commit changes to the database
    -h, --help                     Print help (this message)
    -g, --debug                    Set syslog level to LOG_DEBUG
    -m, --send_mail                Send logging output via e-mail instead of to STDOUT
    -f, --from                     e-mail From line (default: $from)
    -S, --subject                  e-mail Subject line (default: $subject)
    -t, --to                       e-mail To line (default: $to)

Options override default settings from config file.
    
EOF
    
# handle cmdline args
my $result = GetOptions( "H|host=s"          => \$host,
			 "b|block=s"         => \$block,
			 "d|db"              => \$db,
			 "c|communities:s"   => \$commstrs,
			 "r|retries:s"       => \$retries,
			 "t|timeout:s"       => \$timeout,
			 "v|version:s"       => \$version,
			 "I|info"            => \$INFO,
			 "F|fwt"             => \$FWT,
			 "A|arp"             => \$ARP,
			 "a|add-subnets"     => \$ADDSUBNETS,
			 "i|subs_inherit"    => \$SUBSINHERIT,
			 "B|with-bgp-peers"  => \$BGPPEERS,
			 "p|pretend"         => \$PRETEND,
			 "h|help"            => \$HELP,
			 "g|debug"           => \$_DEBUG,
			 "m|send_mail"       => \$EMAIL,
			 "f|from:s"          => \$from,
			 "t|to:s"            => \$to,
			 "S|subject:s"       => \$subject);

if ( ! $result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $HELP ) {
    print $USAGE;
    exit;
}
if ( ($host && $block) || ($host && $db) || ($block && $db) ){
    print $USAGE;
    die "Error: arguments -H, -s and -d are mutually exclusive\n";
}
unless ( $INFO || $FWT || $ARP ){
    print $USAGE;
    die "Error: You need to specify at least one of -I, -F or -A\n";
}

# Re-read communities, in case we were passed new ones
@$communities = split /,/, $commstrs if defined $commstrs;
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
$logger->info(sprintf("Started at %s", scalar localtime($start)));

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
	$dev->fwt_update();
    }
    if ( $ARP ){
	$dev ||= Device->search(name=>$host)->first;
	$dev->arp_update();	
    }
}elsif ( $block ){
    $logger->info("Updating all devices in block: $block");
    $uargs{block} = $block;
    Device->snmp_update_block(%uargs) if ( $INFO );
    Device->fwt_update_block(%uargs)  if ( $FWT  );
    Device->arp_update_block(%uargs)  if ( $ARP  );	
}elsif ( $db ){
    $logger->info("Updating all devices in the DB");
    Device->snmp_update_all(%uargs) if ( $INFO );
    Device->fwt_update_all(%uargs)  if ( $FWT  );
    Device->arp_update_all(%uargs)  if ( $ARP  );
}else{
    print $USAGE;
    die "Error: You need to specify one of -H, -s or -d\n";
}

$logger->info(sprintf("Total runtime: %s secs\n", (time - $start)));

if ( $EMAIL ){
    my $util = Netdot::Util::Misc->new();
    $util->send_mail(from    => $from,
		     to      => $to,
		     subject => $subject, 
		     body    => $logstr->string);
}

