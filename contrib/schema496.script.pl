#!/usr/bin/perl
#
# Move services from Device to Ip
# (Schema change in 496 revision)
# 

use DBI;
use strict;
use Data::Dumper;

my $dbh = DBI->connect ("dbi:mysql:netdot", "netdot_user", "netdot_pass");

# Get all the instances of IpService

my $sth1 = $dbh->prepare("SELECT id, ip 
                          FROM IpService
                         ");
$sth1->execute;

while ( my ($IpServiceid, $device) = $sth1->fetchrow_array ){
    
    # For each device in IpService, get all its interfaces
    
    my $sth2 = $dbh->prepare(
			     "SELECT id, name
			      FROM Interface
			      WHERE device = $device
                             ");
    $sth2->execute();
    
    my %ints;
    # For each interface, get its ip address(es)
    while ( my ($Intid, $name) = $sth2->fetchrow_array ){
	my $sth3 = $dbh->prepare(
			     "SELECT id
			      FROM Ip
			      WHERE interface = $Intid"
			     );
	$sth3->execute();
	
	while ( my ($Ipid) = $sth3->fetchrow_array ){
	    push @{ $ints{$name} }, $Ipid;
	}
    }
    
    # If there's more than one interface with an ip address
    # try one called 'loopback'.  If not, just grab the first one
    # If the chosen interface has more than one ip, also grab
    # the first one.

    my $newid;
    my $found = 0;
    foreach my $name ( keys %ints ){
	if ( $name =~ /Loopback/i ){
	    $newid = $ints{$name}[0];
	    $found = 1;
	    last;
	}
    }
    if (! $found ){
	foreach my $name ( keys %ints ){
	    $newid = $ints{$name}[0];
	    last;
	}
    }
    
#    print Dumper(%ints);
    
    # Assign the ip address' id to the IpService table
    
    unless (
	    $dbh->do(
		     "UPDATE IpService
	              SET ip=\'$newid\'
		      WHERE id=\'$IpServiceid\'
                      ")    
	    ){
	die "Error in Update\n";
    }
}
