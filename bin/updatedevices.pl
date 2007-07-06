#!<<Make:PERL>>

use lib "<<Make:LIB>>";
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;
use Netdot::DeviceManager;
use Netdot::IPManager;
use Netdot::DNSManager;
use NetAddr::IP;
use Netdot::UI;

my $ui = Netdot::UI->new();

my ($host, $subnet, $dm);
my $comstr          = "public";
my $DB              = 0;
my $ADDSUBNETS      = 0;
my $HELP            = 0;
my $VERBOSE         = 0;
my $DEBUG           = 0;
my $EMAIL           = 0;
my $FROM            = $ui->{config}->{'ADMINEMAIL'};
my $TO              = $ui->{config}->{'NOCEMAIL'};
my $SUBJECT         = 'Netdot Device Updates';

my $usage = <<EOF;
 usage: $0 [ -c, --community <string> ] [ -a|--add-subnets ]
           [ -v, --verbose ] [ -g|--debug ]
           [-m|--send_mail] [-f|--from] | [-t|--to] | [-S|--subject]
           -H|--host <hostname|address> | -d|--db-devices |  -s|--subnet <CIDR block>
           
    
    -H, --host <hostname|address>  update given host only.
    -s, --subnet <CIDR block>      specify a v4/v6 subnet to discover
    -c, --community <string>       SNMP community string (default "public")
    -d, --db-devices               update only DB existing devices
    -a, --add-subnets              when discovering routers, add subnets to database if they do not exist
    -h, --help                     print help (this message)
    -v, --verbose                  be verbose
    -g, --debug                    set syslog level to LOG_DEBUG and print to STDERR
    -m, --send_mail                Send output via e-mail instead of to STDOUT
                                   (Note: debugging output will be sent to STDERR always)
    -f, --from                     e-mail From line (default: $FROM)
    -S, --subject                  e-mail Subject line (default: $SUBJECT)
    -t, --to                       e-mail To line (default: $TO)
    
EOF
    
use vars qw ( $output );

# handle cmdline args
my $result = GetOptions( "H|host=s"          => \$host,
			 "s|subnet=s"        => \$subnet,
			 "c|community:s"     => \$comstr,
			 "d|db-devices"      => \$DB,
			 "a|add-subnets"     => \$ADDSUBNETS,
			 "h|help"            => \$HELP,
			 "v|verbose"         => \$VERBOSE,
			 "g|debug"           => \$DEBUG,
			 "m|send_mail"       => \$EMAIL,
			 "f|from:s"          => \$FROM,
			 "t|to:s"            => \$TO,
			 "S|subject:s"       => \$SUBJECT,
);

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
	    $output .= sprintf ("Address %s found\n", $nip->addr);
	    if ( ($ip->interface) && (my $device = $ip->interface->device) ){
		$output .= sprintf ("Device with Address %s found\n", $ip->address) if $DEBUG;
		# Make sure we don't query the same device more than once
		# (routers have many ips)
		if (exists $devices{$device->id}){
		    $output .= sprintf ("%s already queried.  Skipping\n", $ip->address) if $DEBUG;
		    next;
		}
		$devices{$device->id} = '';
		unless ( $device->canautoupdate && $device->snmp_managed ){
		    $output .= sprintf ("Device %s was set to not auto-update. Skipping \n", $nip->addr) if $DEBUG;
		    next;
		}
		# Device exists, so don't pass community
		if (my $r = &discover(host => $ip->address)){
		    $success = 1;
		}
	    }else{
		$output .= sprintf ("Device with Address %s not found\n", $ip->address) if $DEBUG;
		if (my $r = &discover(host => $nip->addr, comstr => $comstr)){
		    $success = 1;
		}
	    }
	}else{
	    $output .= sprintf ("Address %s not found\n", $nip->addr) if $DEBUG;
	    if (my $r = &discover(host => $nip->addr, comstr => $comstr)){
		$success = 1;
	    }
	}
    }
}elsif($DB){
    $output .= sprintf ("Going to update all devices currently in the DB\n") if $VERBOSE;
    my @devices = Device->retrieve_all;
    foreach my $device ( @devices ) {
	unless ( $device->canautoupdate ){
	    $output .= sprintf ("Device %s was set to not auto-update. Skipping \n", $host) if $DEBUG;
	    next;
	}
	my $target;
	# Try to use existing IP address
	# Start with the one associated with the name
	if ( $device->name && $device->name->arecords ){
	    my $ar  = ($device->name->arecords)[0];
	    $target = $ar->ipblock->address;
	    # Or just grab any address
	}elsif ( my @ips = $dm->getdevips($device) ){
	    $target = $ips[0]->address;
	    # Or use the name
	}elsif ( $device->name && $device->name->name ){
	    # Use FQDN
	    $target = $device->name->name . "." . $device->name->zone->mname;
	}
	if ( $target ){
	    if (my $r = &discover(host => $target)){
		$success = 1;
	    }
	}else{
	    die "Could not determine target address or hostname";
	}
    }
}else{
    print $usage;
    die "Error: You need to specify one of -H, -s or -d\n";
}

if ( $EMAIL && $output ){
    if ( ! $dm->send_mail(from    => $FROM,
			  to      => $TO,
			  subject => $SUBJECT, 
			  body    => $output) ){
	die "Problem sending mail: ", $dm->error;
    }
}else{
    print STDOUT $output;
}

sub discover {
    my (%argv) = @_;
    my $r;
    $argv{addsubnets} = $ADDSUBNETS;

    # See if device exists
    my ($c, $d) = $dm->find_dev($argv{host});
    $argv{comstr} = $c if defined($c);
    $argv{device} = $d if defined($d);
    $output .= sprintf ("%s", $dm->output) if ($VERBOSE && ! $DEBUG);

    # Fetch SNMP info
    $argv{dev} = $dm->get_dev_info($argv{host}, $argv{comstr});
    unless ($argv{dev}){
	$output .= sprintf("Error: %s\n", $dm->error) if $VERBOSE;
	return 0;
    }
    $output .= sprintf ("%s", $dm->output) if ($VERBOSE && ! $DEBUG);

    # Update database
    if ( $r = $dm->update_device(%argv) ){
	$output .= sprintf ("%s", $dm->output) if ($VERBOSE && ! $DEBUG);
    }else{
	$output .= sprintf("Error: %s\n", $dm->error) if $VERBOSE;
	return 0;
    }
    return $r;
}

