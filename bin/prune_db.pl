#!/usr/bin/perl

###############################################################
# prune_db.pl
#

use lib "<<Make:LIB>>";
use Netdot::Model;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;
use strict;

my $_DEBUG      = 0;
my $HELP        = 0;
my $VERBOSE     = 0;
my $EMAIL       = 0;
my $TYPE;
my $NUM_DAYS    = 365;
my $NUM_HISTORY = 100;
my $FROM        = Netdot->config->get('ADMINEMAIL');
my $TO          = Netdot->config->get('NOCEMAIL');
my $SUBJECT     = 'Netdot DB Maintenance';
my $output;

my $usage = <<EOF;
 usage: $0   -T|--type <history|address_tracking>
    [ -d|--num_months <number> ] [ -n|--num_history <number> ] 
    [ -g|--debug ] 
    [ -m|--send_mail] [-f|--from] | [-t|--to] | [-s|--subject]
    
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
    
    
    -T, --type                     <history|address_tracking> History tables or address tracking tables
    -d, --num_days                 Number of days worth of items to keep (default: $NUM_DAYS);
    -n, --num_history              Number of history items to keep for each record (default: $NUM_HISTORY);
    -g, --debug                    Print (lots of) debugging output
    -m, --send_mail                Send output via e-mail instead of to STDOUT
    -f, --from                     e-mail From line (default: $FROM)
    -s, --subject                  e-mail Subject line (default: $SUBJECT)
    -t, --to                       e-mail To line (default: $TO)
    
EOF
    

# handle cmdline args
my $result = GetOptions( 
    "T|type=s"        => \$TYPE,
    "d|num_days=i"    => \$NUM_DAYS,
    "n|num_history=i" => \$NUM_HISTORY,
    "m|send_mail"     => \$EMAIL,
    "f|from:s"        => \$FROM,
    "t|to:s"          => \$TO,
    "s|subject:s"     => \$SUBJECT,
    "h|help"          => \$HELP,
    "g|debug"         => \$_DEBUG,
    );

if ( $HELP ) {
    print $usage;
    exit;
}

if ( ! $result || ! $TYPE ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}

# Add a log appender depending on the output type requested
my $logger = Netdot->log->get_logger('Netdot::Model');
my ($logstr, $logscr);
if ( $EMAIL ){
    $logstr = Netdot::Util::Log->new_appender('String', name=>'prune_db.pl');
    $logger->add_appender($logstr);
}else{
    $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
    $logger->add_appender($logscr);
}

#   Set logging level to debug
#   Notice that $DEBUG is imported from Log::Log4perl
if ( $_DEBUG ){
    $logger->level($DEBUG);
}

$logger->debug(sprintf("%s: Executing with: T=\"%s\", d=%d, n=%s", $0, $TYPE, $NUM_DAYS, $NUM_HISTORY));

# Get DB handle 
my $dbh = Netdot::Model::db_Main();

# date NUM_DAYS ago
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time-($NUM_DAYS*24*60*60));
$year += 1900; $mon += 1;
my $sqldate = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec);
$logger->debug(sprintf("NUM_DAYS(%d) ago was : %s", $NUM_DAYS, $sqldate));

my $start = time;
my %rows_deleted;

if ( $TYPE eq 'history' ){
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
    
}elsif ( $TYPE eq 'address_tracking' ){

    my $num_arpe = ArpCacheEntry->count_all;
    my $num_fte  = FWTableEntry->count_all;

    ###########################################################################################
    # Delete non-static MAC addresses
    # Note: This will also delete FWTableEntry, ArpCacheEntry objects, etc.
    my @macs = PhysAddr->search_where(static=>0, last_seen=>{ '<', $sqldate } );
    $rows_deleted{physaddr} = scalar @macs;
    foreach my $mac ( @macs ){
	$logger->debug(sprintf("Deleting PhysAddr id %d", $mac->id));
	$mac->delete;
    }

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

    $rows_deleted{arpcacheentry} = ($num_arpe - ArpCacheEntry->count_all);
    $rows_deleted{fwtableentry}  = ($num_fte  - FWTableEntry->count_all);

    ###########################################################################################
    # Delete FWTable and ARPCache objects
    my @fwts = FWTable->search_where(tstamp=>{ '<', $sqldate });
    $rows_deleted{fwtable} = scalar @fwts;
    foreach my $fwt ( @fwts ){
	$logger->debug(sprintf("Deleting FWTable id %d", $fwt->id));
	$fwt->delete;
    }

    my @arpcs = ArpCache->search_where(tstamp=>{ '<', $sqldate });
    $rows_deleted{arpcache} = scalar @arpcs;
    foreach my $arpc ( @arpcs ){
	$logger->debug(sprintf("Deleting ArpCache id %d", $arpc->id));
	$arpc->delete;
    }

}else{
    print $usage;
    die "Unknown type: $TYPE\n";
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

if ( $EMAIL ){
    Netdot->send_mail(subject => $SUBJECT, 
		      to      => $TO,
		      from    => $FROM,
		      body    => $logstr->string );
}
