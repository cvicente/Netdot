#!/usr/bin/perl -w

###############################################################
# prune_db.pl
#

use lib "/usr/local/netdot/lib";
use Netdot::Model;
use Netdot::Config;
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
	if ( Netdot->config->get('DB_TYPE') eq 'mysql' or Netdot->config->get('DB_TYPE') eq 'Pg' ){
	    &rotate_table('fwtable');
	    &rotate_table('fwtableentry');
	}else{
	    die "Rotate function only implemented in mysql and postgreSQL for now";
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
	    optomize_table($dbh, $table, $logger);
	}
    }
}
if ( $ARP ){
    if ( $ROTATE ){
	if ( Netdot->config->get('DB_TYPE') eq 'mysql' or Netdot->config->get('DB_TYPE') eq 'Pg' ){
	    &rotate_table('arpcache');
	    &rotate_table('arpcacheentry');
	}else{
	    die "Rotate function only implemented in mysql and postgreSQL for now";
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
	    optomize_table($dbh, $table, $logger);
	}
    }
}


foreach my $table ( keys %rows_deleted ){
    if ( $rows_deleted{$table} ){
	$logger->info(sprintf("A total of %d %s records deleted", 
			      $rows_deleted{$table}, $table));
	# now optimize the table to free up the space from the deleted records
	$logger->debug("Freeing deleted space in $table");
	optomize_table($dbh, $table, $logger);
    }
}
$logger->info(sprintf("$0 total runtime: %s\n", Netdot->sec2dhms(time-$start)));



###########################################################################################
# Subroutines
###########################################################################################

#postgresql and mysql have different commands for cleaning up their tables after a large amount of deletes
sub optomize_table{
    my ($dbh, $table, $logger) = @_;

    my $database_type = Netdot->config->get('DB_TYPE');

    if($database_type eq 'mysql'){
        $dbh->do("OPTIMIZE TABLE $table");    
    }
    elsif($database_type eq 'Pg'){
        $dbh->do("VACUUM $table");    
    }
    #otherwise we don't know how to optomize the table :(
    else{
        $logger->warn("didn't recognize the database we're using, so we could not optomize the table, database is  $database_type, it must be either 'mysql' or 'Pg'");
    }    

    return;
}

sub rotate_table{
    my $table = shift;
    
    # We need DBA privileges here
    my $db_type = Netdot->config->get('DB_TYPE');
    my $db_host = Netdot->config->get('DB_HOST');
    my $db_port = Netdot->config->get('DB_PORT');
    my $db_user = Netdot->config->get('DB_DBA');
    my $db_pass = Netdot->config->get('DB_DBA_PASSWORD');
    my $db_db   = Netdot->config->get('DB_DATABASE');
 
    if($db_type ne 'mysql' and $db_type ne 'Pg'){
        die("didn't recognize the database we're using ($db_type), could not rotate table $table");
    }

    my $dbh = &dbconnect($db_type, $db_host, $db_port, $db_user, $db_pass, $db_db) 
	        || die ("Cannot connect to database as root");
 
    
    $dbh->{AutoCommit} = 0; #make sure autocommit is off so we use transactions
    $dbh->{RaiseError} = 1; #make sure we hear about any problems


    my $timestamp = time;

    if($db_type eq 'mysql'){
        eval{
            my $q = $dbh->selectall_arrayref("SHOW CREATE TABLE $table");
            my $create_query = $q->[0]->[1];
            $create_query =~ s/CREATE TABLE `(.*)`/CREATE TABLE `$1\_tmp`/;
            $dbh->do($create_query);
            $dbh->do("RENAME TABLE $table TO $table\_$timestamp");
            $dbh->do("RENAME TABLE $1\_tmp TO $table");
        }
    }

    else{ #postgre
        #the procedure for rotating tables is a bit different for postgres, since it doesn't 
        #recognize the SHOW command.  We instead use the CREATE TABLE AS function of postgres
        #to create an exact copy of the origional table, then we'll drop all the records from the origional
        #$dbh = DBI->connect("DBI:Pg:dbname=$db_db; host=$db_host", "$db_user", "$db_pass");
   
        my $new_table_name = $table."_".$timestamp;

        eval{
            $dbh->do("CREATE TABLE $new_table_name AS SELECT * FROM $table");
            $dbh->do("DELETE FROM $table");
        }
    }

    if($@){
        my $kill_msg = "Error rotating table $table with database: $db_type, $db_host, $db_db, changes not commited";
        $dbh->rollback;
        $logger->fatal($kill_msg.$@);
        die($kill_msg.$@);       
    }
    
    $dbh->commit;

    $logger->info("Table $table rotated successfully");
    
    $dbh->{AutoCommit} = 1; #we can turn back on autocommit since the rest of the transactions are basically atomic
    
    $logger->debug("Droping $table backups older than $NUM_DAYS days");    
    my $tables_q;
    
    if($db_type eq 'mysql'){
        $tables_q = $dbh->selectall_arrayref("SHOW TABLES");
    }
    else{ #postgre
        $tables_q = $dbh->selectall_arrayref("SELECT tablename FROM pg_tables");
    }

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

    if($db_type eq 'Pg'){ #since we just deleted every from from table during the copy, we need to clean up a bit
        optomize_table($dbh, $table, $logger);
    }

    &dbdisconnect($dbh);

    return 1;
}


=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

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

