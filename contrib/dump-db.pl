#!/usr/bin/perl
#
# Dump the Netdot database and scp it to one or more machines.
#
# Useful for simple cron'd backups
#
use strict;

###########################################################
# Configuration section
###########################################################

my %dst = ( 
	    host1 => {
		user => 'user1',
		key  => '/home/user1/.ssh/id_dsa',
		dir  => '/home/user1/' },
	    host2 => {
		user => 'user2',
		key  => '/home/user2/.ssh/id_dsa',
		dir  => '/home/user2/' },
	    );

my $db   = "netdot";

###########################################################
# End of configuration section
###########################################################



my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
	$wday, $yday, $isdst) = localtime;

my $date = sprintf("%04d-%02d-%02d-%02d%02d",
		   $year+1900, $month+1, $day_of_month, , $hours, $minutes);

system ("mysqldump netdot >netdot-$date.sql");

foreach my $host ( keys %dst ){
    system ("scp -i $dst{$host}{key} netdot-$date.sql $dst{$host}{user}\@$host:$dst{$host}{dir}");
}
