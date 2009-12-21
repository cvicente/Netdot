#!/usr/bin/perl

# Generate grep'able circuit info files from Netdot
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model;
use Data::Dumper;
use Getopt::Long;

use vars qw( %self $USAGE @circuits );

&set_defaults();

my $USAGE = <<EOF;
usage: $0 --dir <DIR> --out <FILE>

    --dir             <path> Path to configuration file
    --out             <name> Configuration file name (default: $self{out})
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
	      out             => 'circuits.txt',
	      help            => 0,
	      debug           => 0, 
	      );
}

##################################################
sub setup{
    
    my $result = GetOptions( 
			     "dir=s"            => \$self{dir},
			     "out=s"            => \$self{out},
			     "debug"            => \$self{debug},
			     "h"                => \$self{help},
			     "help"             => \$self{help},
			     );
    
    if( ! $result || $self{help} ) {
	print $USAGE;
	exit 0;
    }

    unless ( $self{dir} && $self{out} ) {
	print "ERROR: Missing required arguments\n";
	die $USAGE;
    }
}

##################################################
sub gather_data{
    
    unless ( @circuits = Circuit->retrieve_all() ){
	die "No circuits found in db\n";
    }
    
}

##################################################
sub build_configs{

    my $file = "$self{dir}/$self{out}";
    open (FILE, ">$file")
	or die "Couldn't open $file: $!\n";

    print FILE "            ****        THIS FILE WAS GENERATED FROM A DATABASE         ****\n";
    print FILE "            ****           ANY CHANGES YOU MAKE WILL BE LOST            ****\n";
    
    @circuits = sort { $a->cid cmp $b->cid } @circuits;
    foreach my $c ( @circuits ){
            my %contacts;
	    my @comments = $c->info;
	    my $prefix = $c->cid . ":" ;
	    $prefix .= " " . $c->linkid->name if ( $c->linkid );
	    print FILE $prefix, ": Type: ", $c->type->name, "\n" if ($c->type);
	    print FILE $prefix, ": Speed: ", $c->speed, "\n" if ($c->speed);
	    print FILE $prefix, ": Provider: ", $c->vendor->name, "\n" if ($c->vendor);
	    foreach my $int ( $c->interfaces ){
		print FILE $prefix, ": Interface: ", $int->get_label, "\n";
		print FILE $prefix, ": DLCI: ", $int->dlci, "\n" if ($int->dlci);
	    }
	    if ( $c->linkid ){
		print FILE $prefix, ": Entity: ", $c->linkid->entity->name, "\n" if ($c->linkid->entity);
		if ( (my $n = $c->linkid->nearend) != 0){
		   print FILE $prefix, ": Origin: ", $n->name, "\n"; 
		   print FILE $prefix, ": Origin: ", $n->street1, "\n"; 
		   print FILE $prefix, ": Origin: ", $n->city, "\n"; 
		}
		map { $contacts{$_->id} = $_ } $c->linkid->entity->contactlist->contacts 
		     if ($c->linkid && $c->linkid->entity && $c->linkid->entity->contactlist);
		if ((my $f = $c->linkid->farend) != 0){
		   map { $contacts{$_->id} = $_ } $f->contactlist->contacts if ($f->contactlist);
		   print FILE $prefix, ": Destination: ", $f->name, "\n"; 
		   print FILE $prefix, ": Destination: ", $f->street1, "\n"; 
		   print FILE $prefix, ": Destination: ", $f->city, "\n"; 
		}
	    }
	    foreach my $contact ( sort { $a->person->lastname cmp $b->person->lastname } 
	    	                  map { $contacts{$_} } keys %contacts ){
		my $person = $contact->person;
		my $pr = $prefix . ": Contacts : " . $person->firstname . " " . $person->lastname;
	    	print FILE $pr, ": Role: ", $contact->contacttype->name, "\n" if ($contact->contacttype);
	    	print FILE $pr, ": Position: ", $person->position, "\n" if ($person->position);
	    	print FILE $pr, ": Office: ", $person->office, "\n" if ($person->office);
	    	print FILE $pr, ": Email: <", $person->email, ">\n" if ($person->email);
	    	print FILE $pr, ": Cell: ", $person->cell, "\n" if ($person->cell);
	    	print FILE $pr, ": Pager: ", $person->pager, "\n" if ($person->pager);
	    	print FILE $pr, ": Email-Pager: ", $person->emailpager, "\n" if ($person->emailpager);
	   }
	   foreach my $l (@comments){
              print FILE $prefix, " Comments: ", $l, "\n";
	   }
	   print FILE "\n";
    }

    close (FILE) or warn "$file did not close nicely\n";
}
