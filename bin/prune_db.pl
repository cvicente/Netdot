#!<<Make:PERL>>

###############################################################
# prune_db.pl
#

use lib "<<Make:LIB>>";
use Netdot::Model;
use Netdot::Config;
use DBUTIL;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;
use strict;

my %self;
$self{DEBUG}       = 0;
$self{HELP}        = 0;
$self{VERBOSE}     = 0;
$self{NUM_DAYS}    = 365;
$self{NUM_HISTORY} = 100;
$self{ROTATE}      = 0;

my $usage = <<EOF;
 usage: $0  -H, --history | -F, --fwt | -A, --arp | -M, --macs | -I, --ips | -R, rr | -t, --hostaudit
    [ -d, --num_days <number> ] [ -n, --num_history <number> ] [ -r, --rotate ]
    [ -g, --debug ] [-h, --help]
    
    -H, --history                  History tables
    -F, --fwt                      Forwarding Tables
    -A, --arp                      ARP caches
    -M, --macs                     MAC addresses
    -I, --ips                      IP addresses
    -R, --rr                       DNS Resource Records
    -t, --hostaudit                Host Audit records
    -d, --num_days                 Number of days worth of items to keep (default: $self{NUM_DAYS});
    -n, --num_history              Number of history items to keep for each record (default: $self{NUM_HISTORY});
    -r, --rotate                   Rotate forwarding tables and ARP caches (rather than delete records) 
    -p, --pretend                  Show activity without actually deleting anything
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
    "H|history"       => \$self{HISTORY},
    "F|fwt"           => \$self{FWT},
    "A|arp"           => \$self{ARP},
    "M|macs"          => \$self{MACS},
    "I|ips"           => \$self{IPS},
    "R|rr"            => \$self{RR},
    "t|hostaudit"     => \$self{HOSTAUDIT},
    "d|num_days=i"    => \$self{NUM_DAYS},
    "n|num_history=i" => \$self{NUM_HISTORY},
    "r|rotate"        => \$self{ROTATE},
    "p|pretend"       => \$self{PRETEND},
    "h|help"          => \$self{HELP},
    "g|debug"         => \$self{DEBUG},
    );

if ( $self{HELP} ) {
    print $usage;
    exit;
}

if ( !$result ){
    print $usage;
    die "Error: Problem with cmdline args\n";
}

unless  ( $self{HISTORY} || $self{FWT} || $self{ARP} || $self{MACS} || $self{IPS} || $self{RR} || $self{HOSTAUDIT} ){
    print $usage;
    die "Error: Missing required args\n";
}

# Add a log appender depending on the output type requested
my $logger = Netdot->log->get_logger('Netdot::Model');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);

# Set logging level to debug
# Notice that $DEBUG is imported from Log::Log4perl
$logger->level($DEBUG) if ( $self{DEBUG} );

# Get DB handle 
my $dbh = Netdot::Model::db_Main();
my $db_type = Netdot->config->get('DB_TYPE');

# date NUM_DAYS ago
my $sqldate = Netdot::Model->sqldate_days_ago($self{NUM_DAYS});
$logger->debug(sprintf("NUM_DAYS(%d) ago was : %s", $self{NUM_DAYS}, $sqldate));

my $start = time;
my %rows_deleted;

if ( $self{HISTORY} ){
    my @tables;
    map { push @tables, $_ if ( $_->is_history ) } Netdot->meta->get_tables(with_history=>1);
    
    foreach my $table ( @tables ) {
	my $tablename = lc($table->name);
	my $orig = $table->original_table || 
	    die "Cannot determine table for history able $tablename\n";
	my $table_id_field = lc($orig)."_id";

	$logger->debug("Checking in $tablename");

	my $r = 0;
	# for each unique table_id in the history table
	my $q = $dbh->prepare("SELECT $table_id_field, COUNT(id) FROM $tablename GROUP BY $table_id_field");
	$q->execute();
	while (my ($table_id, $count) = $q->fetchrow_array()) {
	    if ( $count > $self{NUM_HISTORY} ) {
		$logger->debug(sprintf("%s record %d has %d history items. Deleting records from before %s", 
				       $tablename, $table_id, $count, $sqldate));
		###################################
		# Deletes history items that are older than NUM_DAYS.
		# Note that this is run inside an 'if' statement ($count > $NUM_HISTORY), so
		# we will only delete history items older than NUM_DAYS IF there are more
		# than NUM_HISTORY history items.
		$r = $dbh->do("DELETE FROM $tablename WHERE $table_id_field=$table_id AND modified < '$sqldate'") 
		    unless $self{PRETEND};
		$rows_deleted{$tablename} += $r;
	    }
	}
    }
}
    
if ( $self{MACS} ){
    ###########################################################################################
    # Delete MAC addresses that don't belong to devices (static flag is off)
    # Note: This will also delete FWTableEntry, ArpCacheEntry objects, DhcpScopes, etc.
    my @macs = PhysAddr->search_where(static=>0, last_seen=>{ '<', $sqldate } );
    foreach my $mac ( @macs ){
	$logger->debug(sprintf("Deleting PhysAddr %s", $mac->address));
	unless ( $self{PRETEND} ){
	    $mac->delete;
	    $rows_deleted{physaddr}++;
	}
    }
}
if ( $self{IPS} ){
    ###########################################################################################
    # Delete 'Discovered' and 'Static' IP addresses
    # Note: This will also delete A/AAAA records, ArpCache entries, DhcpScopes, etc.
    my $q = $dbh->prepare("SELECT ipblock.id 
                           FROM   ipblock, ipblockstatus
                           WHERE  (ipblockstatus.name='Discovered'
                              OR  ipblockstatus.name='Static')
                             AND  ipblock.status=ipblockstatus.id
                             AND  ipblock.last_seen < ?");
    $q->execute($sqldate);
    while ( my $id = $q->fetchrow_array() ) {
	if ( my $ip = Ipblock->retrieve($id) ){
	    $logger->debug(sprintf("Deleting IP %s", $ip->address));
	    unless ( $self{PRETEND} ){
		$ip->delete() ;
		$rows_deleted{ipblock}++;
	    }
	}
    }
}

if ( $self{RR} ){
    my $today = Netdot::Model->sqldate_today();
    $logger->debug("Deleting resource records expiring today or before today ($today)");
    my @where = (-and => [expiration => {'<=', $today},
			  expiration => {'<>', '0000-00-00'},
			  expiration => {'<>', '1970-01-01'},
			  expiration => {'<>', '1970-01-02'}]
	);
    
    my @rrs = RR->search_where(@where);

    unless ( $self{PRETEND} ){
	foreach my $rr ( @rrs ){
	    $logger->debug("Deleting RR: ".$rr->get_label);
	    $rr->delete();
	}
    }
    
    $rows_deleted{rr} = scalar(@rrs);
}

if ( $self{HOSTAUDIT} ){
    my $r;
    $logger->debug("Deleting hostaudit records");
    $r = $dbh->do("DELETE FROM hostaudit WHERE tstamp < '$sqldate'")
	unless $self{PRETEND};
    $rows_deleted{hostaudit} = $r;
}

if ( $self{FWT} ){
    if ( $self{ROTATE} ){
	if ( $db_type eq 'mysql' || $db_type eq 'Pg' ){
	    unless ( $self{PRETEND} ){
		&rotate_table('fwtable');
		&rotate_table('fwtableentry');
	    }
	}else{
	    die "Rotate function only implemented in mysql and postgreSQL for now";
	}
    }else{
	###########################################################################################
	# Delete FWTables (also deletes FwtableEntry records)
	$logger->info("Deleting Forwarding Tables older than $sqldate");
	my @fwts = FWTable->search_where(tstamp=>{ '<', $sqldate });
	foreach my $fwt ( @fwts ){
	    $logger->debug("Deleting FWTable id ". $fwt->id);
	    unless ( $self{PRETEND} ){
		$fwt->delete;
		$rows_deleted{fwtable}++;
	    }
	}
	$logger->debug("Freeing deleted space in fwtableentry");
	&optimize_table('fwtableentry') unless $self{PRETEND};
    }
}

if ( $self{ARP} ){
    if ( $self{ROTATE} ){
	if ( $db_type eq 'mysql' or $db_type eq 'Pg' ){
	    unless ( $self{PRETEND} ){
		&rotate_table('arpcache');
		&rotate_table('arpcacheentry');
	    }
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
	    unless ( $self{PRETEND} ){
		$arp->delete;
		$rows_deleted{arpcache}++;
	    }
	}
	$logger->debug("Freeing deleted space in arpcacheentry");
	&optimize_table('arpcacheentry') unless $self{PRETEND};
    }
}

foreach my $table ( keys %rows_deleted ){
    if ( $rows_deleted{$table} ){
	$logger->info(sprintf("A total of %d %s records deleted", 
			      $rows_deleted{$table}, $table));
	# now optimize the table to free up the space from the deleted records
	$logger->debug("Freeing deleted space in $table");
	&optimize_table($table) unless $self{PRETEND};
    }
}
$logger->info(sprintf("$0 total runtime: %s\n", Netdot->sec2dhms(time-$start)));



###########################################################################################
# Subroutines
###########################################################################################

# postgresql and mysql have different commands for cleaning up 
# their tables after a large amount of deletes
sub optimize_table{
    my ($table) = @_;

    if ( $db_type eq 'mysql' ){
        $dbh->do("OPTIMIZE TABLE $table");    
    }elsif( $db_type eq 'Pg' ){
        $dbh->do("VACUUM $table");    
    }else{
        $logger->warn("Could not optimize table $table. Database $db_type not supported");
    }    
    
    return;
}

sub rotate_table{
    my $table = shift;
    
    # We need DBA privileges here
   
    my $db_host = Netdot->config->get('DB_HOST');
    my $db_port = Netdot->config->get('DB_PORT');
    my $db_user = Netdot->config->get('DB_DBA');
    my $db_pass = Netdot->config->get('DB_DBA_PASSWORD');
    my $db_db   = Netdot->config->get('DB_DATABASE');
 
    if ( $db_type ne 'mysql' and $db_type ne 'Pg' ){
        die("didn't recognize the database we're using ($db_type), could not rotate table $table");
    }
    
    my $dbh = &dbconnect($db_type, $db_host, $db_port, $db_user, $db_pass, $db_db) 
	|| die ("Cannot connect to database as root");
    
    
    $dbh->{AutoCommit} = 0; # make sure autocommit is off so we use transactions
    $dbh->{RaiseError} = 1; # make sure we hear about any problems
    
    my $timestamp = time;

    if ( $db_type eq 'mysql' ){
        eval{
            my $q = $dbh->selectall_arrayref("SHOW CREATE TABLE $table");
            my $create_query = $q->[0]->[1];
            $create_query =~ s/AUTO_INCREMENT=[0-9]+/AUTO_INCREMENT=1/;
            $create_query =~ s/CREATE TABLE `(.*)`/CREATE TABLE `$1\_tmp`/;
            $dbh->do($create_query);
            $dbh->do("RENAME TABLE $table TO $table\_$timestamp");
            $dbh->do("RENAME TABLE $1\_tmp TO $table");
        }
    }elsif ( $db_type eq 'Pg' ){
        # the procedure for rotating tables is a bit different for postgres, since it doesn't 
        # recognize the SHOW command.  We instead use the CREATE TABLE AS function of postgres
        # to create an exact copy of the original table, then we'll drop all the records from the original

        my $new_table_name = $table."_".$timestamp;
        eval{
            $dbh->do("CREATE TABLE $new_table_name AS SELECT * FROM $table");
            $dbh->do("DELETE FROM $table");
	    $dbh->do("SELECT setval('".$table."_id_seq', 1, false"); #reset auto_increment
        }
    }else{
	$logger->warn("Could not rotate table $table.  Database $db_type not supported");
    }

    if ( my $e = $@ ){
        $dbh->rollback;
        die "Error rotating table $table with database: $db_type, $db_host, $db_db, changes not commited: $e\n";
    }
    
    $dbh->commit;
    $logger->info("Table $table rotated successfully");
    $dbh->{AutoCommit} = 1; #we can turn autocommit back on since the rest of the transactions are basically atomic
    $logger->debug("Droping $table backups older than $self{NUM_DAYS} days");    
    my $tables_q;
    
    if ( $db_type eq 'mysql' ){
        $tables_q = $dbh->selectall_arrayref("SHOW TABLES");
    }elsif ( $db_type eq 'Pg' ){
        $tables_q = $dbh->selectall_arrayref("SELECT tablename FROM pg_tables");
    }

    my $epochdate = time-($self{NUM_DAYS}*24*60*60); 

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
    
    if ( $db_type eq 'Pg' ){ 
	# Since we just deleted every record from table during the copy, we need to clean up a bit
        &optimize_table($table);
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

