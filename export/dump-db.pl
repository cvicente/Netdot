#!/usr/bin/perl -w
#
# Dump the Netdot database and scp it to a remote machine
# Useful for simple cron'd backups
#
use strict;
use Getopt::Long;

my $USAGE = <<EOF;
usage: $0 [options]
         
    --db              Name of the database (e.g. netdot)
    --dbtype          Database Type [mysql|pg]
    --host            Destination host to scp file
    --user            SSH user
    --key             Private SSH key
    --dir             Directory in destination host where to copy file
    --help            Display this message

EOF

my %self;

my $result = GetOptions( "db=s"      => \$self{db},
			 "dbtype=s"  => \$self{dbtype}, 
			 "host=s"    => \$self{host},
			 "user=s"    => \$self{user},
			 "key=s"     => \$self{key},
			 "dir=s"     => \$self{dir},
			 "help=s"    => \$self{help},
			 );    

if( ! $result || $self{help} ) {
    print $USAGE;
    exit 0;
}

my $hostname = `hostname`;
my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
    $wday, $yday, $isdst) = localtime;

my $date = sprintf("%04d-%02d-%02d-%02d%02d",
		   $year+1900, $month+1, $day_of_month, , $hours, $minutes);

##
## Dump the database
##
if ($self{dbtype} eq 'mysql'){
    system ("mysqldump  >$hostname-$date.sql");
}elsif ($self{dbtype} eq 'pg'){
    die "$self{dbtype} not yet implemented";
}else{
    die "$self{dbtype} not yet implemented";
}

##
## Copy to remote machine
##
system ("scp -i $self{key} $hostname-$date.sql $self{user}\@$self{host}:$self{dir}");
