#!/usr/bin/perl -w

###############################################################
# prune_db.pl
#

use lib "<<Make:LIB>>";
use Netdot::Model;
use DBUTIL;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;
use strict;

my ($HISTORY, $FWT, $ARP, $MACS, $IPS);
my $_DEBUG      = 0;
my $HELP        = 0;
my $VERBOSE     = 0;
my $NUM_DAYS    = 365;
my $NUM_HISTORY = 100;
my $ROTATE      = 0;

my $usage = <<EOF;
 usage: $0   -H|--history | -F|--fwt | -A|--arp | -M|--macs | -I|--ips
    [ -d|--num_days <number> ] [ -n|--num_history <number> ] [ -r|--rotate ]
    [ -g|--debug ] [-h|--help]
    
    -H, --history                  History tables
    -F, --fwt                      Forwarding Tables
    -A, --arp                      ARP caches
    -M, --macs                     MAC addresses
    -I, --ips                      IP addresses
    -d, --num_days                 Number of days worth of items to keep (default: $NUM_DAYS);
    -n, --num_history              Number of history items to keep for each record (default: $NUM_HISTORY);
    -r, --rotate                   Rotate forwarding tables and ARP caches (rather than delete records) 
    -g, --debug                    Print (lots of) debugging output
    -h, --help                     Print help

    Deletes old items from database as necessary.
    
    * For "history" tables:
    
    We want to keep NUM_DAYS worth of history for every record. But
    if a record doesnt change at all during the last NUM_DAYS, we dont 
    want to lose the history that does exist for it from before that time. 
    To compromise, we will only check the history tables for old data 
    if there are more than NUM_HISTORY items for a record.  If there are 
    more than NUM_HISTORY items for a record, then we drop anything older 
    than NUM_DAYS.
    
    * For address tracking tables:
    
    We delete records that are older than NUM_DAYS.
    
    
EOF
    

# handle cmdline args
my $result = GetOptions( 
    "H|history"       => \$HISTORY,
    "F|fwt"           => \$FWT,
    "A|arp"           => \$ARP,
    "M|macs"          => \$MACS,
    "I|ips"           => \$IPS,
    "d|num_days=i"    => \$NUM_DAYS,,
    "n|num_history=i" => \$NUM_HISTORY,
    "r|rotate"        => \$ROTATE,
    "h|help"          => \$HELP,
    "g|debug"         => \$_DEBUG,
    );

if ( $HELP ) {
    print $usage;
    exit;
}

if ( !$result || !($HISTORY || $FWT || $ARP || $MACS || $IPS) ){
    print $usage;
    die "Error: Problem with cmdline args\n";
}

# Add a log appender depending on the output type requested
my $logger = Netdot->log->get_logger('Netdot::Model');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);

# Set logging level to debug
# Notice that $DEBUG is imported from Log::Log4perl
$logger->level($DEBUG) if ( $_DEBUG );

# Get DB handle 
my $dbh = Netdot::Model::db_Main();

# date NUM_DAYS ago
my $epochdate = time-($NUM_DAYS*24*60*60);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime $epochdate;
$year += 1900; $mon += 1;
my $sqldate = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec);

$logger->debug(sprintf("NUM_DAYS(%d) ago was : %s", $NUM_DAYS, $sqldate));

my $start = time;
my %rows_deleted;

if ( $HISTORY ){
    my @tables;
    map { push @tables, $_ if ( $_->is_history ) } Netdot->meta->get_tables(with_history=>1);
    
    foreach my $table ( @tables ) {
	my $tablename = lc($table->name);
	my $orig = $table->original_table;
	die "Cannot determine table for history able $tablename\n" unless $orig;
	my $table_id_field = lc($orig)."_id";

	$logger->debug("Checking in $tablename");

	my $r = 0;
	# for each unique table_id in the history table
	my $q = $dbh->prepare("SELECT $table_id_field, COUNT(id) FROM $tablename GROUP BY $table_id_field");
	$q->execute();
	while (my ($table_id, $count) = $q->fetchrow_array()) {
	    if ( $count > $NUM_HISTORY ) {
		$logger->info(sprintf("%s record %s has %s history items", $tablename, $table_id, $count));
		###################################
		# Deletes history items that are older than NUM_DAYS.
		# Note that this is run inside an 'if' statement ($count > $NUM_HISTORY), so
		# we will only delete history items older than NUM_DAYS IF there are more
		# than NUM_HISTORY history items.
		
		$r = $dbh->do("DELETE FROM $tablename WHERE $table_id_field=$table_id AND modified < '$sqldate'");
	    }
	}
	if ( $r ){
	    $rows_deleted{$tablename} = $r;
	}
    }
}
    
if ( $MACS ){
    ###########################################################################################
    # Delete non-static MAC addresses
    # Note: This will also delete FWTableEntry, ArpCacheEntry objects.
    my @macs = PhysAddr->search_where(static=>0, last_seen=>{ '<', $sqldate } );
    $rows_deleted{physaddr} = scalar @macs;
    foreach my $mac ( @macs ){
	$logger->debug(sprintf("Deleting PhysAddr id %d", $mac->id));
	$mac->delete;
    }
}
if ( $IPS ){
    ###########################################################################################
    # Delete 'Discovered' IP addresses
    # Note: This will also delete ArpCache entries, etc.
    my $ip_status = IpblockStatus->search(name=>'Discovered')->first;
    die "Can't retrieve IpblockStatus 'Discovered'" 
	unless $ip_status;
    my @ips = Ipblock->search_where(status=>$ip_status, last_seen=>{ '<', $sqldate });
    $rows_deleted{ipblock} = scalar @ips;
    foreach my $ip ( @ips ){
	$logger->debug(sprintf("Deleting Ipblock id %d", $ip->id));
	$ip->delete;
    }
}
if ( $FWT ){
    if ( $ROTATE ){
	if ( Netdot->config->get('DB_TYPE') eq 'mysql' ){
	    &rotate_table('fwtable');
	    &rotate_table('fwtableentry');
	}else{
	    die "Rotate function only implemented in mysql for now";
	}
    }else{
	###########################################################################################
	# Delete FWTables
	$logger->info("Deleting Forwarding Tables older than $sqldate");
	my @fwts = FWTable->search_where(tstamp=>{ '<', $sqldate });
	foreach my $fwt ( @fwts ){
	    $logger->debug("Deleting FWTable id ". $fwt->id);
	    $fwt->delete;
	}
	$logger->info("A total of ". scalar(@fwts) ." records deleted");
	
	foreach my $table ( qw (fwtable fwtableentry) ){
	    $logger->debug("Freeing deleted space in $table");
	    $dbh->do("OPTIMIZE TABLE $table");
	}
    }
}
if ( $ARP ){
    if ( $ROTATE ){
	if ( Netdot->config->get('DB_TYPE') eq 'mysql' ){
	    &rotate_table('arpcache');
	    &rotate_table('arpcacheentry');
	}else{
	    die "Rotate function only implemented in mysql for now";
	}
    }else{
	###########################################################################################
	# Delete ArpCaches
	# Note: This will also delete ArpCacheEntry objects.
	$logger->info("Deleting ARP Caches older than $sqldate");
	
	my @arps = ArpCache->search_where(tstamp=>{ '<', $sqldate });
	foreach my $arp ( @arps ){
	    $logger->debug("Deleting ArpCache id ". $arp->id);
	    $arp->delete;
	}
	$logger->info("A total of ". scalar(@arps) ." records deleted");
	
	foreach my $table ( qw (arpcache arpcacheentry) ){
	    $logger->debug("Freeing deleted space in $table");
	    $dbh->do("OPTIMIZE TABLE $table");
	}
    }
}


foreach my $table ( keys %rows_deleted ){
    if ( $rows_deleted{$table} ){
	$logger->info(sprintf("A total of %d %s records deleted", 
			      $rows_deleted{$table}, $table));
	# now optimize the table to free up the space from the deleted records
	$logger->debug("Freeing deleted space in $table");
	$dbh->do("OPTIMIZE TABLE $table");
    }
}
$logger->info(sprintf("$0 total runtime: %s\n", Netdot->sec2dhms(time-$start)));



###########################################################################################
# Subroutines
###########################################################################################

sub rotate_table{
    my $table = shift;
    
    # We need DBA privileges here
    my $dbh = &dbconnect(Netdot->config->get('DB_TYPE'), 
			 Netdot->config->get('DB_HOST'), 
			 Netdot->config->get('DB_PORT'), 
			 Netdot->config->get('DB_DBA') , 
			 Netdot->config->get('DB_DBA_PASSWORD'), 
			 Netdot->config->get('DB_DATABASE'))
	|| die "Cannot connect to database as root";
    
    my $timestamp = time;
    my $q = $dbh->selectall_arrayref("SHOW CREATE TABLE $table");
    my $create_query = $q->[0]->[1];
    $create_query =~ s/CREATE TABLE `(.*)`/CREATE TABLE `$1\_tmp`/;
    $dbh->do($create_query);
    $dbh->do("RENAME TABLE $table TO $table\_$timestamp");
    $dbh->do("RENAME TABLE $1\_tmp TO $table");
    $logger->info("Table $table rotated successfully");

    $logger->debug("Droping $table backups older than $NUM_DAYS days");
    my $tables_q = $dbh->selectall_arrayref("SHOW TABLES");
    foreach my $row ( @$tables_q ){
	my $tablename = $row->[0];
	if ( $tablename =~ /$table\_(\d+)/ ){
	    my $tstamp = $1;
	    if ( $tstamp < $epochdate ){
		$logger->debug("Droping $table\_$tstamp");
		$dbh->do("DROP TABLE $table\_$tstamp");
	    }
	}
    }
    &dbdisconnect($dbh);
    return 1;
}
