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

use vars qw( %self $USAGE $query );

&set_defaults();

my $USAGE = <<EOF;
usage: $0 --dir <DIR> --suffix <STRING>

    --dir             <path> Path to configuration file
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
    
    &debug("Executing SQL statement");

    my $dbh = Netdot::Model->db_Main();
    $query = $dbh->selectall_arrayref("
                SELECT     d.serialnumber, d.rack, d.info, site.name, dr.name, rr.name, zone.mname, 
                           i.name, i.number, i.description, i.neighbor, i.room_char, i.jack_char, 
                           hc.jackid, p.name, pt.name, e.name, ir.name
                 FROM      rr, zone, product p, producttype pt, entity e, interface i 
                 LEFT JOIN (horizontalcable hc, room ir) ON (hc.id=i.jack AND hc.room=ir.id), 
                           device d 
                 LEFT JOIN (site) ON (d.site=site.id)
                 LEFT JOIN (room dr) ON (d.room=dr.id)
                WHERE      i.device=d.id
                  AND      d.name=rr.id
                  AND      rr.zone=zone.id
                  AND      d.product=p.id
                  AND      p.type=pt.id
                  AND      p.manufacturer=e.id
         ");
}

##################################################
sub build_configs{

    &debug("Building data structures");

    my %product_types;

    foreach my $row ( @$query ){
	my ($serialnumber, $rack, $info, $site, $droom, $rrname, $zone, 
	    $iname, $inumber, $idescription, $ineighbor, $iroomchar, $ijackchar,
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
	$product_types{$pt}{$name}{interfaces}{$inumber}{number}      = $inumber;
	$product_types{$pt}{$name}{interfaces}{$inumber}{name}        = $iname;
	$product_types{$pt}{$name}{interfaces}{$inumber}{description} = $idescription;
	$product_types{$pt}{$name}{interfaces}{$inumber}{neighbor}    = $ineighbor;
	$product_types{$pt}{$name}{interfaces}{$inumber}{room_char}   = $iroomchar;
	$product_types{$pt}{$name}{interfaces}{$inumber}{jack_char}   = $ijackchar;
	$product_types{$pt}{$name}{interfaces}{$inumber}{jack}        = $ijack;
	$product_types{$pt}{$name}{interfaces}{$inumber}{room}        = $iroom;
    }


    foreach my $pt ( keys %product_types ){
	next unless ( keys %{$product_types{$pt}} );
	my $filename = $pt;
	$filename =~ s/\s+/-/g;
	$filename .= $self{suffix};
	$filename = lc($filename);
	$filename = $self{dir}."/".$filename;
	
	open (FILE, ">$filename") 
	    or die "Couldn't open $filename: $!\n";
	select (FILE);
	
	&debug("Writing to $filename");

	print "            ****        THIS FILE WAS GENERATED FROM A DATABASE         ****\n";
	print "            ****           ANY CHANGES YOU MAKE WILL BE LOST            ****\n";
	
	foreach my $name ( sort keys %{$product_types{$pt}} ){
	    my $d = $product_types{$pt}{$name};
	    print $name, " -- Building: ",     $d->{site},         "\n";
	    print $name, " -- Room: ",         $d->{room},         "\n";
	    print $name, " -- Rack: ",         $d->{rack},         "\n";
	    print $name, " -- Model: ",        $d->{model},        "\n";
	    print $name, " -- Manufacturer: ", $d->{manufacturer}, "\n";
	    print $name, " -- s/n: ",          $d->{serialnumber}, "\n";
	    my @info_lines = split /\n+/, $d->{info};
	    foreach my $line ( @info_lines ){
		print $name, " -- Info: $line\n";
	    }
		
	    foreach my $p ( sort { $a <=> $b } keys %{$d->{interfaces}} ){
		my $i = $d->{interfaces}{$p};
		my $room = ( $i->{room} )? $i->{room} : $i->{room_char};
		my $jack = ( $i->{jack} )? $i->{jack} : $i->{jack_char};
		my $neighbor = ""; 
		if ( my $nid = $i->{neighbor} ){
		    $neighbor = "link: ". Interface->retrieve($nid)->get_label();
		}
		# Sometimes description has carriage returns
		my $description = $i->{description};
		chomp($description);

		print $name, ", port ", $i->{number}, ", ", $i->{iname}, ", ", $room, ", ", $jack, 
		$description, ", ", $neighbor, "\n";

	    }
	    print "\n";
	}    
	close (FILE) or warn "$filename did not close nicely\n";
    }
}

sub debug {
    print @_, "\n" if $self{debug};
}
