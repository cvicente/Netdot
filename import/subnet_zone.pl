#!/usr/bin/perl
#
# Import subnet-to-zone assignments from text file
# (See sample input file subnet_zone.txt)
#
use lib "<<Make:LIB>>";
use Netdot::Model;
use strict;

my $file = $ARGV[0] or die "Need input file\n";
open(FILE, $file) or die "Cannot open $file: $!\n";

while (<FILE>){
    next if /^#|^\s/;
    my($ipblock, $zone) = split(',', $_);
    $ipblock =~ s/\s+//g;
    $zone =~ s/\s+//g;
    my ($ipb, $z);
    if ( !($ipb = Ipblock->search(address=>$ipblock)->first) ){
	die "Ipblock $ipblock not found";
    }
    if ( !($z = Zone->search(name=>$zone)->first) ){
	die "Zone $zone not found";
    }
    my %args = (zone=>$z, subnet=>$ipb);
    if (! SubnetZone->search(%args) ){
	print "Inserting SubnetZone for zone: $zone, ipblock: $ipblock\n";
	SubnetZone->insert(\%args);
    }
}

