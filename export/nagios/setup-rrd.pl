#!/usr/bin/perl

#
# Create RRD files for RTT graphs in Nagios
#
# cvicente@ns 04/07/04

use strict;
use RRDs;
use Data::Dumper;

my $DEBUG = 0;
my $prefix = "/usr/local/nagios";
my $rrddir = "$prefix/rrd";
my $apancfg = "$prefix/etc/apan.cfg";
my $rrdtool = "/usr/local/bin/rrdtool";

open (IN, "$apancfg") or die "Can't open $apancfg: $!\n";
my @lines = <IN>;
close (IN);
print @lines, "\n" if $DEBUG;

#Apan config looks like
#128.223.60.20;RTT;/usr/local/nagios/rrd/128.223.60.20-RTT.rrd;ping;RTT:LINE2;Ping round-trip time;Seconds

my %devs;
# $dev{128.223.60.20} =>  128.223.60.20-RTT

map {
    if (/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/){
	my ($ip,undef,$filename) = split /;/, $_;
	$devs{$ip} = $filename;
    }
} @lines;

print Dumper(%devs) if $DEBUG;

# RRD parameters:
# Step every 5 min.
# Keep 5 min. averages for 30 days and 60 min. averages for 5 years

foreach my $ip (keys %devs){
    print "Going over $ip\n" if $DEBUG;
    my $file = "$devs{$ip}";
    unless (-e "$file"){
	RRDs::create ("$file", "-s 300", "DS:RTT:GAUGE:600:0:U", "RRA:AVERAGE:0.5:1:8640", "RRA:AVERAGE:0.5:12:518400");
	  my $ERR = RRDs::error;
	  print "ERROR while creating $file: $ERR\n" if $ERR;
	  print "Created $file\n";
    }
}
print "Changing ownership of files\n" if $DEBUG;
system ("chown nagios:apache $rrddir/*.rrd"); 

