#!/usr/bin/perl -w
#
# Imports jack data from text file.  
# Format looks like:
#
#Floor,Room No,Jack ID,Closet,Plate Number,Comments
#001,100,108A,A,F001A108A,
#
# Plate number format means:
#
# F    = Faceplate
# 017  = Building
# A    = Closet
# 085A = Jack ID (first in faceplate)

use lib "PREFIX/lib";
use Netdot::UI;
use Data::Dumper;
use strict;

#
# Since there is no cable type info, assume they're all Cat5
#
my $typename = "Cat5 UTP";
my $type;

my $ui = Netdot::UI->new();

my $usage = "
Usage: $0 <file>\n";

my $file = $ARGV[0] || die $usage;
open (FILE, $file) || die "Can't open $file\n";

my %t;

while ( my $line = <FILE> ){
    next if $line =~ /^#/;
    next unless $line =~ /\w+/;
    chomp($line);
    my ($floor, $room, $jack, $closet, $plate, $comments) = split /,/, $line;
    my $site;
    $floor =~ s/^0+//;   # Remove leading zeroes
    unless ( $plate =~ /^F(\d{3}).*/){
	print "Error in Plate format?: $plate\n";
	exit;
    }
    $site = $1;
    my $sitenum = $site;
    $sitenum =~ s/^0+//;
    my $siteobj;
    unless ( $siteobj = (Site->search( number => $sitenum ))[0] ){
	print "Site not found: $site, $sitenum\n";
	exit;
    }
    # Store everything in a hash
    $t{$sitenum}{$floor}{$room}{$jack}{closet} = $closet;
    $t{$sitenum}{$floor}{$room}{$jack}{plate} = $plate;
    $t{$sitenum}{$floor}{$room}{$jack}{comments} = $comments;
}

#print Dumper(%t);

unless ( $type = (CableType->search(name=>"$typename"))[0] ){
    print "Error determining type $typename\n";
    exit;
}

foreach my $sitenum ( keys %t ){
    my $siteobj = (Site->search( number => $sitenum ))[0];
    my $siteid = $siteobj->id;
    foreach my $floor ( keys %{ $t{$sitenum} } ){
	my $floorid;
	my %tmp = (site=>$siteid, level=>$floor );
	unless ( $floorid = (Floor->search(\%tmp))[0] ){
	    unless ( $floorid = $ui->insert(table=>"Floor", state => \%tmp) ){
		print "Error: ", $ui->error, "\n";
		exit;
	    }else{
		print "Inserting Floor: $floor in site $sitenum \n";
	    }
	}
	foreach my $room ( keys %{ $t{$sitenum}{$floor} } ){
	    my $roomid;
	    my %tmp = (floor=>$floorid, name=>$room);
	    unless ( $roomid = (Room->search(\%tmp))[0] ){
		unless ( $roomid = $ui->insert(table=>"Room", state => \%tmp) ){
		    print "Error:", $ui->error, "\n";
		    exit;
		}else{
		    print "Inserting Room: $room in floor $floor in site $sitenum\n";
		}
	    }
	    foreach my $jack ( keys %{ $t{$sitenum}{$floor}{$room} } ){
		# First make sure closet exists
		my $closetid;
		my $closet = $t{$sitenum}{$floor}{$room}{$jack}{closet};
		my %closettmp = (name=>$closet, site=>$siteid);
		unless ( $closetid = (Closet->search(\%closettmp))[0] ){
		    unless ( $closetid = $ui->insert(table=>"Closet", state => \%closettmp) ){
			print "Error: ", $ui->error, "\n";
			exit;
		    }else{
			print "Inserting Closet: $closet in floor $floor in site $sitenum\n";
		    }
		}
		my $jackobj;
		my $faceplateid = $t{$sitenum}{$floor}{$room}{$jack}{plate};
		# Build the long jack id
		my $jackid = $faceplateid;
		$jackid =~ s/^F(\w{4}).*$/$1$jack/;
		my %tmp = (jackid=>$jackid, room=>$roomid, closet=>$closetid, 
			   faceplateid=>$faceplateid, 
			   info=>$t{$sitenum}{$floor}{$room}{$jack}{comments},
			   type=>$type->id);
		if ( $jackobj = (HorizontalCable->search(jackid=>$jackid))[0] ){
		    # Update if necessary
		    unless ( $ui->update(object=>$jackobj, state => \%tmp) ){
			print "Error:", $ui->error, "\n";
			exit;
		    }		    
		}else{
		    unless ( $jackobj = $ui->insert(table=>"HorizontalCable", state => \%tmp) ){
			print "Error:", $ui->error, "\n";
			exit;
		    }else{
			print "Inserting Jack: $jackid\n";
		    }
		}
	    }
	}
    }
}
