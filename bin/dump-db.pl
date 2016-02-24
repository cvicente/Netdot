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
    --master-data         Include master data in dump (MySQL)
    --help                Display this message
EOF

my $result = GetOptions( "dbtype=s"    => \$self{dbtype}, 
			 "dbuser=s"    => \$self{dbuser}, 
			 "dbpass=s"    => \$self{dbpass}, 
			 "dir:s"       => \$self{dir},
			 "master-data" => \$self{master_data},
			 "help=s"      => \$self{help},
			 "debug"       => \$self{debug},
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
    my @args = ('--opt', "-u$self{dbuser}", "-p$self{dbpass}");
    push @args, '--master-data' if $self{master_data};
    my $dump_args = join ' ', @args;
    system ("mysqldump $dump_args netdot >$file");
}elsif ($self{dbtype} eq 'pg'){
    die "$self{dbtype} not yet implemented";
}else{
    die "$self{dbtype} not yet implemented";
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

=cut
