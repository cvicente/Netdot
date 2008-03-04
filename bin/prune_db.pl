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
my $TABLES;
my $NUM_DAYS    = 365;
my $NUM_HISTORY = 100;
my $FROM        = Netdot->config->get('ADMINEMAIL');
my $TO          = Netdot->config->get('NOCEMAIL');
my $SUBJECT     = 'Netdot DB Maintenance';
my $output;

my $usage = <<EOF;
 usage: $0   -T|--tables <regex>
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

    * For tables with timestamps:
    
        We delete records that are older than NUM_DAYS if there are fewer
        than NUM_HISTORY items in that table.

           
    -T, --tables                   (Perl) Regular expression matching table names. Required.
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
my $result = GetOptions( "T|tables=s"      => \$TABLES,
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

if ( ! $result || !$TABLES ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if ( $HELP ) {
    print $usage;
    exit;
}

&debug(sprintf("%s: Executing with: T=\"%s\", d=%d, n=%s\n", $0, $TABLES, $NUM_DAYS, $NUM_HISTORY));

my @tables;
map { push @tables, $_ if ( $_->name =~ /$TABLES/i ) } Netdot->meta->get_tables(with_history=>1);

# Get DB handle 
my $dbh = Netdot::Model::db_Main();

# date NUM_DAYS ago
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time-($NUM_DAYS*24*60*60));
$year += 1900; $mon += 1;
my $sqldate = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec);
&debug(sprintf("NUM_DAYS(%d) ago was : %s\n", $NUM_DAYS, $sqldate));

my $start = time;

foreach my $table ( @tables ) {
    my $tablename      = lc($table->name);
    my $is_history     = 1 if $table->is_history;
    my $total_deleted  = 0;
    my $r;

    &debug(sprintf("Checking in %s \n", $tablename));

    if ( $is_history ){
	my $ot = $table->original_table;
	next unless $ot;
	my $table_id_field = lc($ot)."_id";

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
	################################################################################################
	# Special cases
    }elsif ( $tablename =~ /^arpcache$|^fwtable$|^physaddr$/ ){
	
	my $q = $dbh->prepare_cached("SELECT COUNT(id) FROM $tablename");
	$q->execute();
	while ( my $count = $q->fetchrow_array() ) {
	    if ( $count > $NUM_HISTORY ) {
		&debug(sprintf("%s has %s items\n", $tablename, $count));
		
		if ( $tablename eq 'physaddr' ){
		    # "Static" means do not delete
		    $r = $dbh->do("DELETE FROM $tablename WHERE static='0' AND last_seen < '$sqldate'");
		}else{
		    $r = $dbh->do("DELETE FROM $tablename WHERE tstamp < '$sqldate'");
		}	    
	    }
	}
    }	
    if ( ($VERBOSE || $DEBUG) && $r > 0 ){
	printf("%d rows deleted\n", $r);
    }
    $total_deleted += $r;
    
    $output .= sprintf("A total of %d rows deleted from %s\n", 
		       $total_deleted, $tablename) if (($VERBOSE || $DEBUG) && $total_deleted);    
    
    if ( $total_deleted > 0 ) {
	# now optimize the table to free up the space from the deleted records
	printf("Freeing deleted space in %s\n", $tablename) if $DEBUG;
	$dbh->do("OPTIMIZE TABLE $tablename");
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
