#!/usr/bin/perl
#
# Move Address info into Site table
# (Schema change in 491 revision)
# 

use DBI;
use strict;

my $dbh = DBI->connect ("dbi:mysql:netdot", "netdot_user", "netdot_pass");

my %addrsite;

my $sth1 = $dbh->prepare("SELECT id,address FROM Site");
$sth1->execute;

while ( my ($site, $address) = $sth1->fetchrow_array ){
    $addrsite{$address} = $site;
    # Copy contents of Address table into Site table
    my $sth = $dbh->prepare("
                             SELECT street1, street2, pobox, city, state, zip, country 
                             FROM Address 
                             WHERE id = $address"
			    );
    $sth->execute();
    my ($street1,$street2,$pobox,$city,$state,$zip,$country) = $sth->fetchrow_array;
    unless (
	    $dbh->do("
                      UPDATE Site 
                      SET street1=\'$street1\',street2=\'$street2\',pobox=\'$pobox\',city=\'$city\',state=\'$state\',zip=\'$zip\',country=\'$country\' 
                      WHERE id = $site
                     ") 
	    ){
	die "Error in UPDATE Site\n";
    }
    
    #Delete Address Entry
    unless ($dbh->do("DELETE FROM Address 
                      WHERE id= $address")
	    ){
	die "Error in DELETE\n";
    }
}


# Take care of remaining Address entries that don't have a Site
# (Create a Site with name equal to street1 and copy the rest of the address values)

my $sth2 = $dbh->prepare("SELECT id,street1,street2,pobox,city,state,zip,country 
                          FROM Address");
$sth2->execute();
while (my ($id, $street1, $street2, $pobox, $city, $state, $zip, $country) = $sth2->fetchrow_array ){
    unless ( $dbh->do("INSERT INTO Site (name, street1, street2, pobox, city, state, zip, country) 
                      VALUES (\'$street1\',\'$street1\',\'$street2\',\'$pobox\',\'$city\',\'$state\',\'$zip\',\'$country\')"
		     )
	    ){
	die "Error in INSERT\n";
    }
    # Is there better way to get the newly-created record's Id?  :-(
    my $sth;
    $sth = $dbh->prepare("SELECT id 
                          FROM Site
                          WHERE name = \'$street1\'"
			 );
    $sth->execute();
    ($addrsite{$id}) = $sth->fetchrow_array;

    #Delete Address Entry
    unless ($dbh->do("DELETE FROM Address 
                      WHERE id=\'$id\'")
	    ){
	die "Error in DELETE FROM Address\n";
    }

}

# Change value of address field in Person from Address id to Site id

my $sth3;
$sth3 = $dbh->prepare("SELECT id, address
                       FROM Person
                      ");
$sth3->execute();
while (my ($id, $address) = $sth3->fetchrow_array ){
    unless (
	    $dbh->do("UPDATE Person
                      SET address = \'$addrsite{$address}\'
		      WHERE id = $id"
		     ) 
	    ){
	die "Error in UPDATE Person\n";
    }
}
