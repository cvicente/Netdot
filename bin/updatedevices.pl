#PERL

use lib "PREFIX/lib";
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;
use Netdot::DeviceManager;
use Netdot::IPManager;
use Netdot::DNSManager;
use NetAddr::IP;

my $usage = <<EOF;
 usage: $0 [ -c, --community <string> ] [ -a|--add-subnets ]
           [ -v, --verbose ] [ -g|--debug ]
           -H|--host <hostname|address> | -d|--db-devices |  -s|--subnet <CIDR block>
    
    -H, --host <hostname|address>  update given host only.
    -s, --subnet <CIDR block>      specify a v4/v6 subnet to discover
    -c, --community <string>       SNMP community string (default "public")
    -d, --db-devices               update only DB existing devices
    -a, --add-subnets              add router-known subnets to database if they do not exist
    -h, --help                     print help (this message)
    -v, --verbose                  be verbose
    -g, --debug                    set syslog level to LOG_DEBUG and print to STDERR
    
EOF
    
my ($host, $subnet, $dm);
my $comstr     = "public";
my $DB         = 0;
my $ADDSUBNETS = 0;
my $HELP       = 0;
my $VERBOSE    = 0;
my $DEBUG      = 0;

# handle cmdline args
my $result = GetOptions( "H|host=s"      => \$host,
			 "s|subnet=s"    => \$subnet,
			 "c|community:s" => \$comstr,
			 "d|db-devices"  => \$DB,
			 "a|add-subnets" => \$ADDSUBNETS,
			 "h|help"        => \$HELP,
			 "v|verbose"     => \$VERBOSE,
			 "g|debug"       => \$DEBUG );

if( ! $result ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if( $HELP ) {
    print $usage;
    exit;
}
if ( ($host && $subnet) || ($host && $DB) || ($subnet && $DB) ){
    print $usage;
    die "Error: arguments -H, -s and -d are mutually exclusive\n";
}

if ($DEBUG){
    $VERBOSE = 1;
    $dm = Netdot::DeviceManager->new( loglevel => "LOG_DEBUG", foreground => 1 );
}else{
    $dm = Netdot::DeviceManager->new();
}
my $ipm = Netdot::IPManager->new();
my $dns = Netdot::DNSManager->new();
my $success = 0;

# This will be reflected in the history tables
$ENV{REMOTE_USER} = "netdot";

if ($host){
    if (my $r = &discover(host => $host, comstr => $comstr)){
	$success = 1;
    }
}elsif($subnet){
    my $net = NetAddr::IP->new($subnet);
    # Make sure we work with the network address
    $net = $net->network();
    my %devices;
    for (my $nip = $net+1; $nip < $nip->broadcast; $nip++){
	if(my $ip = $ipm->searchblocks_addr($nip->addr)){
	    printf ("Address %s found\n", $nip->addr);
	    if ( ($ip->interface) && (my $device = $ip->interface->device) ){
		printf ("Device with Address %s found\n", $ip->address) if $DEBUG;
		# Make sure we don't query the same device more than once
		# (routers have many ips)
		if (exists $devices{$device->id}){
		    printf ("%s already queried.  Skipping\n", $ip->address) if $DEBUG;
		    next;
		}
		$devices{$device->id} = '';
		unless ( $device->canautoupdate ){
		    printf ("Device %s was set to not auto-update. Skipping \n", $nip->addr) if $DEBUG;
		    next;
		}
		# Device exists, so don't pass community
		if (my $r = &discover(host => $ip->address)){
		    $success = 1;
		}
	    }else{
		printf ("Device with Address %s not found\n", $ip->address) if $DEBUG;
		if (my $r = &discover(host => $nip->addr, comstr => $comstr)){
		    $success = 1;
		}
	    }
	}else{
	    printf ("Address %s not found\n", $nip->addr) if $DEBUG;
	    if (my $r = &discover(host => $nip->addr, comstr => $comstr)){
		$success = 1;
	    }
	}
    }
}elsif($DB){
    printf ("Going to update all devices currently in the DB\n") if $VERBOSE;
    my @devices = Device->retrieve_all;
    foreach my $device ( @devices ) {
	unless ( $device->canautoupdate ){
	    printf ("Device %s was set to not auto-update. Skipping \n", $host) if $VERBOSE;
	    next;
	}
	# Use hostname, or else try any of its IPs
	if (defined ($device->name->name)){
	    $host = $device->name->name;
	}else{
	    foreach my $if ($device->interfaces){
		if (my $ip = ($if->ips)[0]){
		    $host = $ip->address;
		    last;
		}
	    }
	}
	if (my $r = &discover(host => $host)){
	    $success = 1;
	}
    }
}else{
    print $usage;
    die "Error: You need to specify one of -H, -s or -d\n";
}


sub discover {
    my (%argv) = @_;
    my $r;
    $argv{addsubnets} = 1 if $ADDSUBNETS;

    # See if device exists
    my ($c, $d) = $dm->find_dev($argv{host});
    $argv{comstr} = $c if defined($c);
    $argv{device} = $d if defined($d);
    printf ("%s", $dm->output) if ($VERBOSE && ! $DEBUG);

    # Fetch SNMP info
    $argv{dev} = $dm->get_dev_info($argv{host}, $argv{comstr});
    unless ($argv{dev}){
	printf("Error: %s\n", $dm->error) if $VERBOSE;
	return 0;
    }
    printf ("%s", $dm->output) if ($VERBOSE && ! $DEBUG);

    # Update database
    if ( $r = $dm->update_device(%argv) ){
	printf ("%s", $dm->output) if ($VERBOSE && ! $DEBUG);
    }else{
	printf("Error: %s\n", $dm->error) if $VERBOSE;
	return 0;
    }
    return $r;
}

