#!/usr/bin/perl
#
# Import hosts from a CSV file
# Each host is a 4-tuple: (name, zone, IP, MAC)
# which will create DNS records and DHCP reservations in Netdot.
#
# Note: The subnet(s) to which the IPs belong must be DHCP enabled
#
use lib "/usr/local/netdot/lib";
use Netdot::Model;
use strict;

my $file = $ARGV[0] or die "Need input file\n";
open(FILE, $file) or die "Cannot open $file: $!\n";

while (<FILE>){
    next if /^#|^\s/;
    my($name, $zone, $ip, $mac) = split(',', $_);

    my $rr;
    eval {
	$rr = RR->add_host(name=>$name, zone=>$zone,
			   address=>$ip, ethernet=>$mac);
    };
    if (my $e = $@){
	printf("Problem importing %s, %s, %s, %s: $e\n", 
	       $name, $zone, $ip, $mac);
    }else{
	printf("Added %s with MAC %s\n", $rr->get_label, $mac);
    }
}
