#!/usr/bin/perl
#
# Link HorizontalCable (jack) objects to their corresponding Interface objects
# based on the contents of the jack_char field in the Interface table.
# It also removes the contents from the jack_char, room_char and description fields
# 
# The need jack_char and room_char fields in the Interface table comes from
# the fact that not all the horizontal cable information is/was available at
# the time that the Devices were inserted in the database.  
# 
# cv
#
use lib "<<Make:LIB>>";
use Netdot::UI;
use strict;

my $ui = Netdot::UI->new();
my $it = Interface->retrieve_all;

my $dups = 0;
my $oks  = 0;

while ( my $int = $it->next ){
    # Only if it's not already assigned
    if ( $int->jack == 0 ){
	my $jackid;
	if ( $int->jack_char =~ /(\d{3}\w\d{3}\w)/ ){
	    $jackid = $1;
	}elsif ( $int->description =~ /(\d{3}\w\d{3}\w)/ ){
	    $jackid = $1;
	}else{
	    next;
	}
	if ( my $jack = (HorizontalCable->search(jackid => $jackid))[0] ){
	    if ( my $int2 = ($jack->interfaces)[0] ){
		printf ("Jack %s has already been assigned to interface %s:%s\n", 
			$jack->jackid, $int->device->name->name, $int->name);
		$dups++;
		next;
	    }
	    my %tmpint;
	    $tmpint{jack}        = $jack->id;
	    $tmpint{jack_char}   = "";
	    $tmpint{room_char}   = "";
	    $tmpint{description} = "";
	    printf ("Assigned jack %s to %s:%s\n", $jack->jackid, $int->device->name->name, $int->name);
	    unless ( $ui->update(object => $int, state => \%tmpint ) ){
		printf("Error: Could not update %s: %s", $int->name, $ui->error);
		exit;
	    }
	    $oks++;
	}
    }
}


printf("Stats: %s OKs and %s duplicates\n", $oks, $dups);
