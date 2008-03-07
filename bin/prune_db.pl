#!/usr/bin/perl

###############################################################
# prune_db.pl
#

use lib "<<Make:LIB>>";
use Netdot::Model;
use Netdot::Util::Misc;
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;

my $DEBUG       = 0;
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
           [ -v|--verbose ] [ -g|--debug ] 
           [ -m|--send_mail] [-f|--from] | [-t|--to] | [-s|--subject]
           
    Deletes old items from database as necessary.

    * For tables with corresponding "history" tables:

        We want to keep NUM_DAYS worth of history for every record. But
       if a record doesn't change at all during the last NUM_DAYS, we don't 
       want to lose the history that does exist for it from before that time. 
       To compromise, we will only check the history tables for old data 
       if there are more than NUM_HISTORY items for a record.  If there are 
       more than NUM_HISTORY items for a record, then we drop anything older 
       than NUM_DAYS.

    * For address tracking tables:
    
        We delete records that are older than NUM_DAYS.

           
    -T, --type                     <history|address_tracking) History tables or address tracking tables
    -d, --num_days                 Number of days worth of items to keep (default: $NUM_DAYS);
    -n, --num_history              Number of history items to keep for each record (default: $NUM_HISTORY);
    -v, --verbose                  Print informational output
    -g, --debug                    Print (lots of) debugging output
    -m, --send_mail                Send output via e-mail instead of to STDOUT
    -f, --from                     e-mail From line (default: $FROM)
    -s, --subject                  e-mail Subject line (default: $SUBJECT)
    -t, --to                       e-mail To line (default: $TO)
    
EOF
    
# handle cmdline args
my $result = GetOptions( "T|type=s"        => \$TYPE,
                         "d|num_days=i"    => \$NUM_DAYS,
			 "n|num_history=i" => \$NUM_HISTORY,
			 "m|send_mail"     => \$EMAIL,
			 "f|from:s"        => \$FROM,
			 "t|to:s"          => \$TO,
			 "s|subject:s"     => \$SUBJECT,
			 "h|help"          => \$HELP,
			 "v|verbose"       => \$VERBOSE,
			 "g|debug"         => \$DEBUG,
			 );

if ( ! $result || !$TYPE ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if ( $HELP ) {
    print $usage;
    exit;
}

&debug(sprintf("%s: Executing with: T=\"%s\", d=%d, n=%s\n", $0, $TYPE, $NUM_DAYS, $NUM_HISTORY));

# Get DB handle 
my $dbh = Netdot::Model::db_Main();

# date NUM_DAYS ago
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time-($NUM_DAYS*24*60*60));
$year += 1900; $mon += 1;
my $sqldate = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec);
&debug(sprintf("NUM_DAYS(%d) ago was : %s\n", $NUM_DAYS, $sqldate));

my $start = time;

my %rows_deleted;
my $total_deleted;

if ( $TYPE eq 'history' ){
    my @tables;
    map { push @tables, $_ if ( $_->is_history ) } Netdot->meta->get_tables(with_history=>1);
    
    foreach my $table ( @tables ) {
	my $tablename = lc($table->name);
	my $orig = $table->original_table;
	die "Cannot determine table for history able $tablename\n" unless $orig;
	my $table_id_field = lc($orig)."_id";

	&debug(sprintf("Checking in %s \n", $tablename));

	my $r = 0;
	# for each unique table_id in the history table
	my $q = $dbh->prepare("SELECT $table_id_field, COUNT(id) FROM $tablename GROUP BY $table_id_field");
	$q->execute();
	while (my ($table_id, $count) = $q->fetchrow_array()) {
	    if ( $count > $NUM_HISTORY ) {
		&debug(sprintf("%s record %s has %s history items\n", $tablename, $table_id, $count));
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
	    if ( ($VERBOSE || $DEBUG) ){
		printf("%d rows deleted\n", $r);
	    }
	    $total_deleted += $r;
	}
    }
    $output .= sprintf("A total of %d rows deleted from history tables\n", 
		       $total_deleted) if (($VERBOSE || $DEBUG) && $total_deleted);
    
}elsif ( $TYPE eq 'address_tracking' ){

    my $r1 = $dbh->do("DELETE p,a,f FROM physaddr p, arpcacheentry a, fwtableentry f
                       WHERE p.static=0 AND p.last_seen < '$sqldate'
                       AND a.physaddr=p.id AND f.physaddr=p.id");
    
    my $r2 = $dbh->do("DELETE ip,a FROM ipblock ip, arpcacheentry a, ipblockstatus s
                       WHERE s.name='Discovered' AND ip.status=s.id 
                       AND ip.last_seen < '$sqldate' AND a.ipaddr=ip.id ");
    
    my $r3 = $dbh->do("DELETE a,e FROM arpcache a, arpcacheentry e
                       WHERE a.tstamp < '$sqldate'
                       AND e.arpcache=a.id");
	
    my $r4 = $dbh->do("DELETE f,e FROM fwtable f, fwtableentry e
                       WHERE f.tstamp < '$sqldate'
                       AND e.fwtable=f.id");

    $total_deleted = $r1 + $r2 + $r3 + $r4;
    if ( $total_deleted ){
	foreach my $t (qw /physaddr arpcache arpcacheentry fwtable fwtableentry/){
	    $rows_deleted{$t} = 1;
	}
    }

    $output .= sprintf("A total of %d rows deleted from address tracking tables\n", 
		       $total_deleted) if (($VERBOSE || $DEBUG) && $total_deleted);
    
}else{
    print $usage;
    die "Unknown type: $TYPE\n";
}
 
if ( $total_deleted > 0 ) {
    foreach my $table ( keys %rows_deleted ){
	# now optimize the table to free up the space from the deleted records
	printf("Freeing deleted space in %s\n", $table) if $DEBUG;
	$dbh->do("OPTIMIZE TABLE $table");
    }
}

my $end = time;
$output .= sprintf ("Completed in %d seconds\n", ($end-$start)) if $VERBOSE;

if ( $EMAIL ){
    my $misc = Netdot::Util::Misc->new();
    $misc->send_mail(subject => $SUBJECT, 
		     to      => $TO,
		     from    => $FROM,
		     body    => $output );
}else{
    print STDOUT $output;
}

sub debug {
    my $msg = shift @_;
    print $msg if $DEBUG;
}
