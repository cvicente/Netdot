#!/usr/bin/perl
#
# Imports closet info from csv file

use lib "PREFIX/lib";
use Netdot::UI;
use Data::Dumper;
use strict;

my $ui = Netdot::UI->new();

my $usage = "
Usage: $0 <file>\n";

# A line looks like:
#
#Lawrence,1,2,208,A Closet,door=35.5"w 64" x 46",custodial supplies, electrical,excellent fluorescent,none found,,1/4-20A wall    2/2-15A wall   3/6-strip            ,protectors (300),630,,1,19" x 4' floor mount,no,3-4 units,~35 ft. sq.,~15 ft. sq. free backboard,300 pr,,24 strands,,,,X,18-ST        6-SC,,,all,,,3-48 port   1-24 port,44.5 blocks - rooms         4 blocks - patch panels        23 blocks - switches,5-partials,,needs to be painted,AT&T(24); 2-AMD; Molex,yes,65-75,backboard needs to be painted,
#
#

my $file = $ARGV[0] || die $usage;
open (FILE, $file)  || die "Can't open $file\n";


my %columns = ('Building Name'=>0, 'Building Number'=>1, 'Floor'=>2, 'Closet Number'=>3, 'Closet Name'=>4, 'Dimensions'=>5,'Shared With'=>6, 'Lighting'=>7, 'HVAC Type'=>8, 'Outlets'=>10, 'Ground Buss'=>11, 'Access Key Type'=>12, 'Asbestos Tiles'=>13, 'Racks Installed'=>14, 'Rack Type'=>15, 'RU Available'=>17, 'Wall Space Used'=>18, 'Wall Space Avail'=>19, 'Pair Count'=>20, 'Patch Panels'=>33, '110 Blocks'=>34, '66 Blocks'=>35, 'CATV Taps'=>36, 'New Backboard Needed'=>37, 'Work Needed'=>41, 'Closet Comments'=>42);

while ( my $line = <FILE> ){
    next if $line =~ /^#/;
    next unless $line =~ /\w+/;
    chomp($line);
    my @vals = split /,/, $line;

    my $siteobj;
    unless ( $siteobj = (Site->search(number => $vals[$columns{'Building Number'}]))[0] ){
	# We're assuming that all sites exist
	print "ERROR: Site not found: $vals[$columns{'Name'}]\n";
	next;
    }
    my $floorobj;
    my %tmp = (site=>$siteobj->id, level=>$vals[$columns{"Floor"}] );
    unless ( $floorobj = (Floor->search(\%tmp))[0] ){
	my $floorid;
	unless ( $floorid = $ui->insert(table=>"Floor", state => \%tmp) ){
	    print "Error: ", $ui->error, "\n";
	    exit;
	}else{
	    $floorobj = Floor->retrieve($floorid);
	    print "Inserted Floor: $vals[$columns{'Floor'}] in site $vals[$columns{'Building Name'}]\n";
	}
    }
    my $closetname = $vals[$columns{'Closet Name'}];
    # Just the get one-letter name
    $closetname =~ s/(\w) Closet/$1/;
    my $closetobj;
    my $comments = $vals[$columns{'Closet Comments'}] . "\n" if ($vals[$columns{'Closet Comments'}]);
    $comments .= "Lighting: " . $vals[$columns{'Lighting'}] . "\n" if ($vals[$columns{'Lighting'}]);
    $comments .= "Wall Space Used: " . $vals[$columns{'Wall Space Used'}] . "\n" if ($vals[$columns{'Wall Space Used'}]);
    $comments .= "Wall Wpace Avail: " . $vals[$columns{'Wall Space Avail'}] . "\n" if ($vals[$columns{'Wall Space Avail'}]);
    $comments .= "New Backboard Needed: " . $vals[$columns{'New Backboard Needed'}] . "\n" if ($vals[$columns{'New Backboard Needed'}]);

    my %closettmp = (name            => $closetname,
		     number          => $vals[$columns{'Closet Number'}],
		     site            => $siteobj->id,
		     floor           => $floorobj->id,
		     dimensions      => $vals[$columns{'Dimensions'}],
		     racks           => $vals[$columns{'Racks Installed'}],
		     outlets         => $vals[$columns{'Outlets'}],
		     ru_avail        => $vals[$columns{'RU Available'}],
		     patch_panels    => $vals[$columns{'Patch Panels'}],
		     '110_blocks'    => $vals[$columns{'110 Blocks'}],
		     '66_blocks'     => $vals[$columns{'66 Blocks'}],
		     catv_taps       => $vals[$columns{'CATV Taps'}],
		     access_key_type => $vals[$columns{'Access Key Type'}],
		     work_needed     => $vals[$columns{'Work Needed'}],
		     shared_with     => $vals[$columns{'Shared With'}],
		     hvac_type       => $vals[$columns{'HVAC Type'}],
		     ground_buss     => $vals[$columns{'Ground Buss'}],
		     asbestos_tiles  => $vals[$columns{'Asbestos Tiles'}],
		     rack_type       => $vals[$columns{'Rack Type'}],
		     pair_count      => $vals[$columns{'Pair Count'}],
		     info            => $comments,
		     );
    
    unless ( $closetobj = (Closet->search(name=>$closetname, site=>$siteobj->id))[0] ){
	unless ( $ui->insert(table=>"Closet", state => \%closettmp) ){
	    print "Error: ", $ui->error, "\n";
	    print Dumper(%closettmp);
	    exit;
	}else{
	    print "Inserted Closet: $closetname in site ", $siteobj->name, "\n";
	}
    }else{
	unless ( $ui->update( object=>$closetobj, state => \%closettmp) ){
	    print "Error: ", $ui->error, "\n";
	    print Dumper(%closettmp);
	    exit;
	}else{
	    print "Updated Closet: $closetname in site ", $siteobj->name, "\n";
	}

    }
    
}
