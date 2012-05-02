#!/usr/bin/perl
#
# This script builds grep'able text files to allow users 
# to look up device information quickly from the command
# line
# 
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model;
use Data::Dumper;
use Getopt::Long;

use vars qw( %self $USAGE $q1 $q2 );

&set_defaults();

my $USAGE = <<EOF;
usage: $0 --dir <PATH> --suffix <STRING>

    --dir             <PATH> Path to configuration file
    --suffix          <STRING> Extension for file names (default: $self{suffix})
    --debug           Print debugging output
    --help            Display this message

EOF

&setup();
&gather_data();
&build_configs();


##################################################
sub set_defaults {
    %self = ( 
	      dir             => '',
	      suffix          => '-devices.txt',
	      help            => 0,
	      debug           => 0, 
	      );
}

##################################################
sub setup{
    
    my $result = GetOptions( 
			     "dir=s"            => \$self{dir},
			     "debug"            => \$self{debug},
			     "h"                => \$self{help},
			     "help"             => \$self{help},
			     );
    
    if( ! $result || $self{help} ) {
	print $USAGE;
	exit 0;
    }

    unless ( $self{dir} && $self{suffix} ) {
	print "ERROR: Missing required arguments\n";
	die $USAGE;
    }
}

##################################################
sub gather_data{
    
    &debug("Executing SQL query 1");

    my $dbh = Netdot::Model->db_Main();
    $q1 = $dbh->selectall_arrayref("
                SELECT     a.serial_number, d.rack, d.info, site.name, dr.name, rr.name, zone.name, 
                           i.id, i.name, i.number, i.description, i.neighbor, i.room_char, i.jack_char, 
                           hc.jackid, p.name, pt.name, e.name, ir.name
                 FROM      asset a, rr, zone, product p, producttype pt, entity e, interface i
                 LEFT JOIN (horizontalcable hc CROSS JOIN room ir) ON (hc.id=i.jack AND hc.room=ir.id), 
                           device d 
                 LEFT JOIN (site) ON (d.site=site.id)
                 LEFT JOIN (room dr) ON (d.room=dr.id)
                WHERE      i.device=d.id
                  AND      d.name=rr.id
                  AND      rr.zone=zone.id
                  AND      a.product_id=p.id
                  AND      d.asset_id=a.id
                  AND      p.type=pt.id
                  AND      p.manufacturer=e.id
         ");

    &debug("Executing SQL query 2");

    $q2 = $dbh->selectall_arrayref("
                SELECT  i1.id, i2.id, i2.name, rr2.name, zone2.name
                FROM    device d1, device d2, interface i1, interface i2,
                        rr rr1, rr rr2, zone zone1, zone zone2
                WHERE   i1.device = d1.id AND i2.device = d2.id
                    AND d1.name = rr1.id AND rr1.zone = zone1.id
                    AND d2.name = rr2.id AND rr2.zone = zone2.id
                    AND i2.neighbor = i1.id AND i1.neighbor = i2.id
         ");
}

##################################################
sub build_configs{

    &debug("Building data structures");

    my %product_types;

    foreach my $row ( @$q1 ){
	my ($serialnumber, $rack, $info, $site, $droom, $rrname, $zone, 
	    $iid, $iname, $inumber, $idescription, $ineighbor, $iroomchar, $ijackchar,
	    $ijack, $product, $pt, $manufacturer, $iroom) = @$row;

	next unless $pt;

	my $name = $rrname . "." . $zone;

	$product_types{$pt}{$name}{serialnumber}                      = $serialnumber;
	$product_types{$pt}{$name}{site}                              = $site;
	$product_types{$pt}{$name}{room}                              = $droom;
	$product_types{$pt}{$name}{rack}                              = $rack;
	$product_types{$pt}{$name}{model}                             = $product;
	$product_types{$pt}{$name}{manufacturer}                      = $manufacturer;
	$product_types{$pt}{$name}{info}                              = $info;
	$product_types{$pt}{$name}{interfaces}{$inumber}{id}          = $iid;
	$product_types{$pt}{$name}{interfaces}{$inumber}{number}      = $inumber;
	$product_types{$pt}{$name}{interfaces}{$inumber}{name}        = $iname;
	$product_types{$pt}{$name}{interfaces}{$inumber}{description} = $idescription;
	$product_types{$pt}{$name}{interfaces}{$inumber}{neighbor}    = $ineighbor;
	$product_types{$pt}{$name}{interfaces}{$inumber}{room_char}   = $iroomchar;
	$product_types{$pt}{$name}{interfaces}{$inumber}{jack_char}   = $ijackchar;
	$product_types{$pt}{$name}{interfaces}{$inumber}{jack}        = $ijack;
	$product_types{$pt}{$name}{interfaces}{$inumber}{room}        = $iroom;
    }

    # Build a hash of neighbor names keyed by id
    my %neighbors;
    foreach my $row ( @$q2 ){
	my ($i1id, $i2id, $i2name, $i2dev, $i2zone) = @$row;

	my $neighbor_name = "$i2dev.$i2zone [$i2name]";
	$neighbors{$i1id} = $neighbor_name;
    }

    &debug("Done building data structures");

    foreach my $pt ( keys %product_types ){
	next unless ( keys %{$product_types{$pt}} );
	my $filename = $pt;
	$filename =~ s/\s+/-/g;
	$filename .= $self{suffix};
	$filename = lc($filename);
	$filename = $self{dir}."/".$filename;
	
	&debug("Writing to $filename");

	open (FILE, ">$filename") 
	    or die "Couldn't open $filename: $!\n";

	print FILE "            ****        THIS FILE WAS GENERATED FROM A DATABASE         ****\n";
	print FILE "            ****           ANY CHANGES YOU MAKE WILL BE LOST            ****\n\n";
	
	foreach my $name ( sort keys %{$product_types{$pt}} ){
	    my $d = $product_types{$pt}{$name};
	    print FILE $name, " -- Building: ",     $d->{site},         "\n";
	    print FILE $name, " -- Room: ",         $d->{room},         "\n";
	    print FILE $name, " -- Rack: ",         $d->{rack},         "\n";
	    print FILE $name, " -- Model: ",        $d->{model},        "\n";
	    print FILE $name, " -- Manufacturer: ", $d->{manufacturer}, "\n";
	    print FILE $name, " -- s/n: ",          $d->{serialnumber}, "\n";
	    my @info_lines = split /\n+/, $d->{info};
	    foreach my $line ( @info_lines ){
		print FILE $name, " -- Info: $line\n";
	    }
		
	    foreach my $p ( sort { $a <=> $b } keys %{$d->{interfaces}} ){
		my $i    = $d->{interfaces}{$p};
		my $iid  = $i->{id};
		my $room = ( $i->{room} )? $i->{room} : $i->{room_char};
		my $jack = ( $i->{jack} )? $i->{jack} : $i->{jack_char};
		my $neighbor = ""; 
		if ( my $nid = $i->{neighbor} ){
		    $neighbor = "link: ". $neighbors{$iid};
		}
		# Sometimes description has carriage returns
		my $description = $i->{description};
		chomp($description);

		print FILE $name, ", port ", $i->{number}, ", ", $i->{iname}, ", ", $room, ", ", $jack, 
		$description, ", ", $neighbor, "\n";

	    }
	    print FILE "\n";
	}    
	close (FILE) or warn "$filename did not close nicely\n";
    }
}

sub debug {
    print STDERR "DEBUG: ", @_, "\n" if $self{debug};
}
