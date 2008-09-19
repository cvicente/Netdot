#!<<Make:PERL>>
#
# Dump the Netdot database
# Useful for simple cron'd backups
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot;
use Getopt::Long;
use Data::Dumper;

my %self;

$self{dbtype} = Netdot->config->get('DB_TYPE');
$self{dbuser} = Netdot->config->get('DB_DBA');
$self{dbpass} = Netdot->config->get('DB_DBA_PASSWORD');
$self{dir}    = '.';

my $USAGE = <<EOF;
usage: $0 [options]
         
    --dbtype <type>       Database Type [mysql|pg] (default: $self{dbtype})
    --dbuser <username>   Database DBA user (default: $self{dbuser})
    --dbpass <password>   Database DBA password
    --dir    <path>       Directory where files should be written (default: $self{dir})
    --help                Display this message
EOF

my $result = GetOptions( "dbtype=s"  => \$self{dbtype}, 
			 "dbuser=s"  => \$self{dbuser}, 
			 "dbpass=s"  => \$self{dbpass}, 
			 "dir:s"     => \$self{dir},
			 "help=s"    => \$self{help},
			 "debug"     => \$self{debug},
			 );    

if( ! $result || $self{help} ) {
    print $USAGE;
    exit 0;
}

print Dumper(%self) if $self{debug};

my $hostname = `hostname`;
chomp($hostname);

my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
    $wday, $yday, $isdst) = localtime;
my $date = sprintf("%04d-%02d-%02d-%02d%02d",
		   $year+1900, $month+1, $day_of_month, , $hours, $minutes);

my $file = $self{dir}."/$hostname-$date.sql";

## Dump the database
if ($self{dbtype} eq 'mysql'){
    system ("mysqldump --opt -u$self{dbuser} -p$self{dbpass} netdot >$file");
}elsif ($self{dbtype} eq 'pg'){
    die "$self{dbtype} not yet implemented";
}else{
    die "$self{dbtype} not yet implemented";
}
