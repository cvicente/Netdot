#!/usr/bin/perl -w

###############################################################
# prune_db.pl
#

use lib "PREFIX/lib";
use Netdot::UI;
use Data::Dumper;
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;

my $ui = Netdot::UI->new();

my $DEBUG       = 0;
my $HELP        = 0;
my $VERBOSE     = 0;
my $EMAIL       = 0;
my $NUM_MONTHS  = 12;
my $NUM_HISTORY = 100;
my $output;

my $usage = <<EOF;
 usage: $0 [ -m|--num_months <number> ] [ -n|--num_history <number> ] 
           [ -v|--verbose ] [ -g|--debug ] [ -e|--send_mail ]  
           
    Deletes old items from the history tables as necessary.

    What is considered "old"?

    We want to keep NUM_MONTHS worth of information for every record. But
    if a record doesn't change at all during the last NUM_MONTHS, we don't 
    want to lose the history that does exist for it from before that time. 
    To compromise, we will only check the history tables for old data 
    if there are more than NUM_HISTORY items for a record.
    
    If there are more than NUM_HISTORY items for a record, then we drop 
    anything older than NUM_MONTHS.

           
    -m, --num_months               Number of months worth of history items to keep (default: $NUM_MONTHS);
    -n, --num_history              Number of history items to keep for each record (default: $NUM_HISTORY);
    -v, --verbose                  Print informational output
    -g, --debug                    Print (lots of) debugging output
    -e, --send_mail                Send output via e-mail instead of to STDOUT
    
EOF
    
# handle cmdline args
my $result = GetOptions( "m|num_months=i"  => \$NUM_MONTHS,
			 "n|num_history=i" => \$NUM_HISTORY,
			 "e|send_mail"     => \$EMAIL,
			 "h|help"          => \$HELP,
			 "v|verbose"       => \$VERBOSE,
			 "g|debug"         => \$DEBUG,
			 );

if( ! $result ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if( $HELP ) {
    print $usage;
    exit;
}

# Get DB handle 
my $dbh = $ui->{dbh};

my @tables;
map { push @tables, $_ if ($_ =~ /_history/ ) } sort $dbh->tables;
map { $_ =~ s/\`//g } @tables;
map { $_ =~ s/\_history//g } @tables;


# date NUM_MONTHS ago
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time-($NUM_MONTHS*30*24*60*60)); # 30 days/month
$year += 1900; $mon += 1;
printf("NUM_MONTHS(%d) ago was : %d/%d\n", $NUM_MONTHS, $year, $mon) if $DEBUG;
my $sqldate = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec);

my $start = time;

foreach my $table (@tables) {
    my $history_table    = $table."_history";
    my $table_id_field   = lc($table)."_id";
    my $total_deleted    = 0;
    
    printf("Checking in %s \n", $history_table) if $DEBUG;

    # for each unique table_id in the history table
    my $q = $dbh->prepare("SELECT $table_id_field, COUNT(id) FROM $history_table GROUP BY $table_id_field");
    $q->execute();
    while (my ($table_id, $count) = $q->fetchrow_array()) {
    	if ($count > $NUM_HISTORY) {
            printf("%s record %s has %s history items\n", $history_table, $table_id, $count) if $DEBUG;

            ###################################
            # Deletes history items that are older than NUM_MONTHS.
            # Note that this is run inside an 'if' statement ($count > $NUM_HISTORY), so
            # we will only delete history items older than NUM_MONTHS IF there are more
            # than NUM_HISTORY history items.

            my $r = $dbh->do("DELETE FROM $history_table WHERE $table_id_field=$table_id AND modified < '$sqldate'");
            if ( $r ){
                if ( $VERBOSE ){
                    printf("%d rows deleted\n", $r) if $DEBUG;
                }
                $total_deleted += $r;
            }
        }
    }
    $output .= sprintf("A total of %d rows deleted from %s\n", 
		       $total_deleted, $history_table) if (($VERBOSE || $DEBUG) && $total_deleted);    

    if ($total_deleted > 0) {
        # now optimize the table to free up the space from the deleted records
        printf("Freeing deleted space in %s\n", $history_table) if $DEBUG;
        $dbh->do("OPTIMIZE TABLE $history_table");
    }
}

my $end = time;
$output .= sprintf ("Completed in %d seconds\n", ($end-$start)) if $VERBOSE;

if ($EMAIL){
    if (! $ui->send_mail(subject=>"Netdot DB Maintenance", 
			 to=>$ui->{config}->{'ADMINEMAIL'}, body=>$output)){
	die "Problem sending mail: ", $ui->error;
    }
}else{
    print STDOUT $output;
}
