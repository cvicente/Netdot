#!/usr/bin/perl
#
# Import a list of IP blocks and addresses from a CSV file
# (See sample input file ip_list.txt)
#
use lib "/usr/local/netdot/lib";
use Netdot::Model;
use strict;

my $file = $ARGV[0] or die "Need input file\n";
open(FILE, $file) or die "Cannot open $file: $!\n";


while (<FILE>){
    next if /^#|^\s/;
    my($block, $status, $owner, $used_by, $description) = split(',', $_);
    my($address, $prefix) = split(/\//, $block);
    die "Syntax error: Block must be in CIDR notation: $block\n"
	unless ($address && $prefix);
    die "Unrecognized status: $status\n"
	unless ( $status =~ /^Dynamic|Static|Container|Reserved|Subnet$/ );
    
    my ($ent1, $ent2);
    if ($owner){
	$ent1 = Entity->find_or_create({name=>$owner});
    }
    if ($used_by){
	$ent2 = Entity->find_or_create({name=>$used_by});
    }
    if (my $ip = Ipblock->search(address=>$address)->first){
	print "IP " . $ip->get_label . " exists.  Updating.\n";
	$ip->update({status         => $status, 
		     owner          => $ent1, 
		     used_by        => $ent2, 
		     description    => $description,
		    });
    }else{
	my $newip;
	eval {
	    $newip = Ipblock->insert({address     => $address,
				      prefix      => $prefix,
				      status      => $status,
				      owner       => $ent1,
				      used_by     => $ent2,
				      description => $description,
				      no_update_tree => 1,
				     });
	};
	if ( my $e = $@ ){
	    die "ERROR: $e\n";
	}else{
	    print "Inserted " . $newip->get_label. "\n";
	}
    }
}

Ipblock->build_tree(4);
Ipblock->build_tree(6);
