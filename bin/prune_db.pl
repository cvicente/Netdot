#!/usr/bin/perl -w

###############################################################
# prune_db.pl
#
# Deletes old items from the history tables as necessary.
#
# What is considered "old"?
#
# We want to keep a year's worth of information for every record. But
# if a record doesn't change at all this year, we don't want to lose
# the history that does exist for it from last year. To compromise, 
# we will only check the history tables for old data if there are 
# more than NUM_HISTORY items for a record.
#
# If there are more than NUM_HISTORY items for a record, then we drop 
# anything older than one year.
#
# NUM_HISTORY is defined in the config file.
#

use lib "/usr/local/netdot/lib";
use Netdot::UI;
use Data::Dumper;

my $ui = Netdot::UI->new();

my $NUM_HISTORY = $ui->{config}->{NUM_HISTORY};

my @tables;
map { push @tables, $_ if ($_ =~ /_history/ ) } sort $ui->{dbh}->tables;
map { $_ =~ s/\`//g } @tables;
map { $_ =~ s/\_history//g } @tables;


# one year ago
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time-(365*24*60*60));
$year += 1900; $mon += 1;


my $start = time;

foreach my $table (@tables) {
    my $history_table    = $table."_history";
    my $table_id_field   = lc($table)."_id";

    # for each unique table_id in the history table
    my $q = $ui->{dbh}->prepare("SELECT $table_id_field, COUNT(id) FROM $history_table GROUP BY $table_id_field");
    $q->execute();
    while (my ($table_id, $count) = $q->fetchrow_array()) {
        if ($count > $NUM_HISTORY) {

            ###################################
            # Deletes history items that are older than one year.
            # Note that this is run inside an 'if' statement ($count > $NUM_HISTORY), so
            # we will only delete history items older than one year IF there are more
            # than NUM_HISTORY history items.

            my $sqldate = sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hour,$min,$sec);
            my $qd = $ui->{dbh}->prepare("DELETE FROM $history_table WHERE $table_id_field=$table_id AND modified < '$sqldate'");
            $qd->execute();

            # note: it is possible that this delete statement will not do anything, in the case that
            # there have been more than NUM_HISTORY changes within this year.



#            ###################################
#            # Deletes history items for any record that has more
#            # than NUM_HISTORY history items in the database.
#
#            # find the NUM_HISTORYth oldest row
#            my $q2 = $ui->{dbh}->prepare("SELECT modified FROM $history_table WHERE $table_id_field = $table_id ORDER BY modified DESC LIMIT $limit,1");
#            $q2->execute();
#            my $modified = $q2->fetchrow_array();
#
#            # delete all rows older than the NUM_HISTORYth oldest row
#            my $qd = $ui->{dbh}->prepare("DELETE FROM $history_table WHERE $table_id_field=$table_id AND modified <= '$modified'");
#            $qd->execute();

        }
    }
}

my $end = time;

print "Completed in ".($end-$start)." seconds\n";
