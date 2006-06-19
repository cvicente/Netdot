#!/usr/bin/perl -w
#
# Dump the Netdot database and scp it to a remote machine
# Useful for simple cron'd backups
#
use strict;
use Getopt::Long;
use Data::Dumper;

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
			 "dbpass=s"  => \$self{dbpass}, 
			 "host=s"    => \$self{host},
			 "user=s"    => \$self{user},
			 "key=s"     => \$self{key},
			 "dir=s"     => \$self{dir},
			 "help=s"    => \$self{help},
			 "debug"     => \$self{debug},
			 );    

if( ! $result || $self{help} ) {
    print $USAGE;
    exit 0;
}

print Dumper(%self) if $self{debug};

unless ( $self{db} && $self{dbtype} && $self{user} && $self{key} && $self{host} && $self{dir} ){
    print "Missing required arguments\n";
    print $USAGE;
    exit 1;
}
my $hostname = `hostname`;
chomp($hostname);

my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
    $wday, $yday, $isdst) = localtime;

my $date = sprintf("%04d-%02d-%02d-%02d%02d",
		   $year+1900, $month+1, $day_of_month, , $hours, $minutes);

my $file = "$hostname-$date.sql";

## Dump the database
if ($self{dbtype} eq 'mysql'){
    system ("mysqldump -u root -p$self{dbpass} $self{db} >$file");
}elsif ($self{dbtype} eq 'pg'){
    die "$self{dbtype} not yet implemented";
}else{
    die "$self{dbtype} not yet implemented";
}

## Copy to remote machine
system ("scp -i $self{key} $file $self{user}\@$self{host}:$self{dir}");
