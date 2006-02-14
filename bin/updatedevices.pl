#!<<Make:PERL>>

use lib "<<Make:LIB>>";
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;
use Netdot::DeviceManager;
use Netdot::DNSManager;
use NetAddr::IP;

# We construct this early only to be able to access
# the config attribute, which is common to all 
# Netdot libraries
my $dns = Netdot::DNSManager->new();

my ($host, $subnet, $db, $dm);
my $COMSTR          = "public";
my $ADDSUBNETS      = 0;
my $HELP            = 0;
my $DEBUG           = 0;
my $EMAIL           = 0;
my $PRETEND         = 0;
my $RETRIES         = $dns->{config}->{DEFAULT_SNMPRETRIES};
my $TIMEOUT         = $dns->{config}->{DEFAULT_SNMPTIMEOUT};
my $VERSION         = $dns->{config}->{DEFAULT_SNMPVERSION};

my $usage = <<EOF;
 usage: $0 [ -c, --community <string> ] [ -v, --version <1|2|3> ] 
           [ -r, --retries <integer> ] [ -t, --timeout <secs> ]
           [ -g, --debug ] [ -m, --send_mail ] [ -a, --add-subnets ] [ -p, --pretend ]
           -H, --host <hostname|address> | -d, --db |  -s, --subnet <CIDR block>
           
    
    -H, --host <hostname|address>  update given host only.
    -s, --subnet <CIDR block>      specify a v4/v6 subnet to discover
    -c, --community <string>       SNMP community string (default $COMSTR)
    -r, --retries <integer >       SNMP retries (default $RETRIES)
    -t, --timeout <secs>           SNMP timeout in seconds (default $TIMEOUT)
    -v, --version <integer>        SNMP version [1|2|3] (default $VERSION)
    -d, --db                       update only DB existing devices
    -a, --add-subnets              when discovering routers, add subnets to database if they do not exist
    -p, --pretend                  do not commit changes to the db
    -h, --help                     print help (this message)
    -g, --debug                    set syslog level to LOG_DEBUG and print to STDERR
    -m, --send_mail                Send output via e-mail instead of to STDOUT
                                   (Note: debugging output will be sent to STDERR always)
    
EOF
    
use vars qw ( $output );

# handle cmdline args
my $result = GetOptions( "H|host=s"          => \$host,
			 "s|subnet=s"        => \$subnet,
			 "c|community:s"     => \$COMSTR,
			 "r|retries:s"       => \$RETRIES,
			 "t|timeout:s"       => \$TIMEOUT,
			 "v|version:s"       => \$VERSION,
			 "d|db"              => \$db,
			 "a|add-subnets"     => \$ADDSUBNETS,
			 "p|pretend"         => \$PRETEND,
			 "h|help"            => \$HELP,
			 "g|debug"           => \$DEBUG,
			 "m|send_mail"       => \$EMAIL);

if( ! $result ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if( $HELP ) {
    print $usage;
    exit;
}
if ( ($host && $subnet) || ($host && $db) || ($subnet && $db) ){
    print $usage;
    die "Error: arguments -H, -s and -d are mutually exclusive\n";
}
if ( $DEBUG ){
    $dm = Netdot::DeviceManager->new(loglevel=>'LOG_DEBUG', foreground=>1);
}else{
    $dm = Netdot::DeviceManager->new();
}

if ( $PRETEND ){
    # Tell the DB to not commit
    # This should not affect the web interface because it uses a separate
    # connection
    $dm->db_auto_commit(0);
    $output .= "Note: Executing with -p (pretend) flag.  Changes will not be committed to the DB\n";
}

# This will be reflected in the history tables
$ENV{REMOTE_USER} = "netdot";

if ( $host ){
    $output .= "Discovering single device: $host\n";
    &discover({host=>$host, comstr=>$COMSTR});

}elsif( $subnet ){
    my $start = time;
    $output .= sprintf ("Discovering all devices in subnet: $subnet\n");
    $output .= sprintf ("Started at %s\n", scalar localtime($start));
    my $net = NetAddr::IP->new($subnet);
    # Make sure we work with the network address
    $net = $net->network();
    my %devices;
    for (my $nip = $net+1; $nip < $nip->broadcast; $nip++){
	# We want to get the device object before calling update_device
	# in order to keep a list of checked devices
	my $argv = {};
	if ( $argv = $dm->find_dev($nip->addr) ){
	    # We now have device and comstr in $argv
	    my $device = $argv->{device};
	    my $name = ($device->name) ? $device->name->name : $device->id;
	    $argv->{host} = $nip->addr;
	    # Make sure we don't query the same device more than once
	    if (exists $devices{$device->id}){
		printf ("Device %s already queried. Skipping\n", $name) if $DEBUG;
		next;
	    }
	    $devices{$device->id} = '';
	    unless ( $device->canautoupdate ){
		printf ("Device %s was set to not auto-update. Skipping \n", $name) if $DEBUG;
		next;
	    }
	}else{
	    $argv->{device}  = 'NEW'; # Tell update_device to not look for a device object
	    $argv->{host}    = $nip->addr;
	    $argv->{comstr}  = $COMSTR;
	}
	&discover($argv);
    }
    $output .= sprintf ("Total runtime: %s secs\n", (time-$start));

}elsif( $db ){
    $output .= sprintf ("Updating all devices in the DB\n");
    my $start = time;
    $output .= sprintf ("Started at %s\n", scalar localtime($start));
    my $it = Device->retrieve_all;
    while ( my $device = $it->next ) {
	my $name = ($device->name) ? $device->name->name : $device->id;
	unless ( $device->canautoupdate ){
	    printf ("Device %s was set to not auto-update. Skipping \n", $name) if $DEBUG;
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
	    &discover({host   => $target, 
		     comstr => $device->community,
		     device => $device });
	}else{
	    die "Could not determine target address or hostname";
	}
    }
    $output .= sprintf ("Total runtime: %s secs\n", (time-$start));
}else{
    print $usage;
    die "Error: You need to specify one of -H, -s or -d\n";
}

if ( $output ){
    if ( $EMAIL ){
	if ( ! $dm->send_mail(subject=>"Netdot Device Updates", body=>$output) ){
	    die "Problem sending mail: ", $dm->error;
	}
    }else{
	print STDOUT $output;
    }
}

# Fetch SNMP info and update database
sub discover {
    my $argv = shift;
    my $r;
    $argv->{addsubnets} = $ADDSUBNETS;

    # Get both name and IP for better error reporting
    my ($name, $ip);
    my $v4 = '(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})';
    if ( $host =~ /$v4/ || $host =~ /:/ ){
	# $host looks like an IP address
	if ( $argv->{device} && $argv->{device}->name ){
	    # use whatever is in the DB
	    $name = $argv->{device}->name->name;
	}else{
	    # or resolve it
	    $name = $dns->resolve_ip($argv->{host}) || "?";
	}
	$ip   = $argv->{host};
    }else{
	# $host looks like a name
	$name = $argv->{host};
	$ip   = ($dns->resolve_name($name))[0] || "?";
    }

    # Fetch SNMP info from device
    # We do this first to avoid unnecessarily calling update_device
    # (within a transaction) if host does not respond
    unless ( $argv->{info} = $dm->get_dev_info(host     => $argv->{host}, 
					       comstr   => $argv->{comstr},
					       version  => $VERSION,
					       timeout  => $TIMEOUT,
					       retries  => $RETRIES) ){
	# error should be set
	my $err = sprintf("Error %s (%s): %s\n", $name, $ip, $dm->error);
	$output .= $err;
	print $err if $DEBUG;
	return 0;
    }

    if ( $PRETEND ){
	# AutoCommit has been turned off, so rollback each update
	if ( $r = $dm->update_device($argv) ){
	    $output .= sprintf ("%s", $dm->output);
	    $dm->db_rollback;
	}else{
	    my $err = sprintf("Error: %s\n", $dm->error);
	    $output .= $err;
	    print $err if $DEBUG;
	    $dm->db_rollback;
	    return 0;
	}
    }else{
	# Update device in database (atomically)
	if ( $r = $dm->do_transaction( sub{ return $dm->update_device(@_) }, $argv) ) {
	    $output .= sprintf ("%s", $dm->output);
	}else{
	    my $err  = sprintf("Error: %s\n", $dm->error);
	    $output .= $err;
	    print $err if $DEBUG;
	    return 0;
	}
    }
    return $r;
}

