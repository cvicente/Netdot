#!/usr/bin/perl
#
#  Read relevant info from Netdot and 
#  build Sysmon configuration
#

use NetdotExport;
use lib "/usr/local/netdot/lib";
use Netdot::DBI;
use strict;


###################################################
########## Config Section #########################

# Print debugging info
my $DEBUG = 0;

# Our root in the dependency tree
# This should be the switch that the machine
# running sysmon is connected to
my $root = "cc-ns-bb";

########## Input and output files ################

my $DIR = "/usr/local/netdot/export";
my $OUT = "$DIR/netmon/sysmon.conf";

########## End Config Section #####################
###################################################

my $usage = "Usage: $0 \n";

if (scalar (@ARGV) != 0){
    print $usage;
    exit;
}

my (%hosts, %name2ip, %ip2name );

foreach my $ipobj ( Ipblock->retrieve_all ){
   
    next if $ipobj->address =~ /^127\.0\.0/;

    # For now, don't monitor any 10.x.x.x address space
    next if $ipobj->address =~ /^10\./;
 
    # Ignore those set as 'not monitored'
    next unless ( $ipobj->interface->monitored
		  && $ipobj->interface->device->monitored );
    
    # For a given IP addres we'll try to get its name directly
    # from the DNS.  
    my $name;
    if ( ! ($name = &resolve($ipobj->address)) || ! &resolve($name) ){
	warn $ipobj->address, " does not resolve at all or symmetrically.  Using ip as name\n";
	$name = $ipobj->address;
    }elsif ( exists $name2ip{$name} ){
	warn $name, " is not unique.  Using ip as name\n" if ($DEBUG);
	$name = $ipobj->address;
    }
    $hosts{$ipobj->id}{name} = $name;
    $ip2name{$ipobj->id} = $name;
    $name2ip{$name} = $ipobj->id;
    

} #foreach ip

# Now that we have everybody in
# assign parent list

foreach my $ipid (keys %hosts){
    my @parentlist;
    my $ipobj = Ipblock->retrieve($ipid);
    if ( my $intobj = $ipobj->interface ){
	if ( scalar(@parentlist = &getparents($intobj)) ){
	    @{ $hosts{$ipid}{parents} } = map { $ip2name{$_} } @parentlist;
	}else{
	    $hosts{$ipid}{parents} = undef;
	}
    }
}

# Now build the config file
    
# Open output file for writing
open (OUT, ">$OUT") 
    or die "Can't open $OUT $!\n";
select (OUT);

print <<EOP;
root \"$root\"\;
config queuetime 30\;
config maxqueued 500\;
config noheartbeat\;
config logging syslog \"local2\"\;
config statusfile html \"/usr/local/nsweb/sysmon.html\"\;
EOP


foreach my $ipid ( keys %hosts ){
    my $name = $hosts{$ipid}{name};

    printf "\n";
    printf "object $name \{\n";
    printf "   ip \"$name\"\;\n";
    printf "   type ping\;\n";
    printf "   desc \"$name\"\;\n";

    foreach my $parent ( @{ $hosts{$ipid}{parents} } ){
	next if ($parent eq "");
	print "   dep \"$parent\"\;\n";
    }
    
    print "\}\;";
    print "\n";

}
    	    
print STDOUT "OK: Sysmon configuration written to $OUT\n";    
close(OUT);


