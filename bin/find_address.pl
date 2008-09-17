#!<<Make:PERL>>
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;

my %self;
$self{ARP_LIMIT} = 3;
$self{FWT_LIMIT} = 3;

my $USAGE = <<EOF;

 Locate a MAC or IP address.  By default, this script uses Netdot database 
 information.  The user also has the option of performing a "live" search 
 by querying relevant devices in the network.

 Usage: $0 [options] <ether|ip|name>

    Available options:

    -A|--arp_limit   Number of latest ARP cache entries to show (default: $self{ARP_LIMIT})
    -F|--fwt_limit   Number of latest Forwardint Table entries to show (default: $self{FWT_LIMIT})
    -v|--vlan        VLAN id to use when searching addresses "live"
    -f|--forcelive   Force a "live" search
    -d|--debug       Show debugging output
    -h|--help        Show help
    
EOF
    
my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();
my $MAC  = Netdot->get_mac_regex();

# handle cmdline args
my $result = GetOptions( "A|arp_limit:s"  => \$self{ARP_LIMIT},
			 "F|fwt_limit:s"  => \$self{FWT_LIMIT},
                         "v|vlan:s"       => \$self{VLAN},
			 "f|forcelive"    => \$self{FORCE_LIVE},
			 "h|help"         => \$self{HELP},
			 "d|debug"        => \$self{DEBUG},
			 );

my $address = shift @ARGV;

if ( !$result || !$address ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $self{HELP} ) {
    print $USAGE;
    exit;
}

my $logger = Netdot->log->get_logger('Netdot::Model::Device');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);

# Notice that $DEBUG is imported from Log::Log4perl
$logger->level($DEBUG) if ( $self{DEBUG} ); 

print "--------------------\n";

if ( $address =~ /$MAC/ ){
    $address = PhysAddr->format_address($address);

    if ( $self{FORCE_LIVE} ){
	&search_live(mac=>$address, vlan=>$self{VLAN});
    }else{
	&show_mac($address, 1);
    }

}elsif ( $address =~ /$IPV4|$IPV6/ ){
    
    if ( $self{FORCE_LIVE} ){
	&search_live(ip=>$address, vlan=>$self{VLAN});
    }else{
	&show_ip($address);
    }
}else{
    # Try to resolve
    if ( my $ip = (Netdot->dns->resolve_name($address))[0] ){
	if ( $self{FORCE_LIVE} ){
	    &search_live(ip=>$ip, vlan=>$self{VLAN});
	}else{
	    &show_ip($ip);
	}
    }else{
	die "$address not found\n"
    }
}

###############################################################################
# 
# Subroutine Section
#
###############################################################################

###############################################################################
sub show_ip {
    my ($address) = @_;
    my $ip     = Ipblock->search(address=>$address)->first;
    my $parent = $ip->parent;
    my $subnet;
    if ( int($parent->status) && $parent->status->name eq "Subnet" ){
	$subnet = $parent;
    }
    print "\n";
    print "IP Address : ", $address, "\n";
    print "Subnet     : ", $subnet->get_label, ", ", $subnet->description, "\n";
    if ( my $name = Netdot->dns->resolve_ip($address) ){
	print "DNS        : ", $name, "\n";
    }
    if ( $ip ){
	if ( my $arp = $ip->get_last_n_arp($self{ARP_LIMIT}) ){
	    print "\nLast $self{ARP_LIMIT} ARP cache entries:\n\n";
	    my @rows;
	    my %tstamps;
	    my $latest_mac;
	    foreach my $row ( @$arp ){
		my ($iid, $macid, $tstamp) = @$row;
		my $lbl   = Interface->retrieve($iid)->get_label;
		push @{$tstamps{$tstamp}{$macid}}, $lbl;
	    }
	    foreach my $tstamp ( reverse sort keys %tstamps ){
		foreach my $macid ( keys %{$tstamps{$tstamp}} ){
		    my $maclbl   = PhysAddr->retrieve($macid)->get_label;
		    $latest_mac  = $maclbl unless defined $latest_mac;
		    print $tstamp, " ", $maclbl, " ", (join ', ', @{$tstamps{$tstamp}{$macid}}), "\n";
		}
	    }
	    &show_mac($latest_mac);
	}
    }else{
	warn "$address not found in DB.  Try searching live (--forcelive)\n";
	exit 0;
    }
}


###############################################################################
sub show_mac {
    my ($address, $show_arp) = @_;
    
    my $mac = PhysAddr->search(address=>$address)->first;
    if ( !$mac ){
	warn "$address not found in DB.  Try searching live (--forcelive)\n";
	exit 0;
    }

    print "\n";
    print "MAC Address : ", $mac->address,    "\n";
    print "Vendor      : ", $mac->vendor,     "\n";
    print "First Seen  : ", $mac->first_seen, "\n";
    print "Last Seen   : ", $mac->last_seen,  "\n";

    my $fwt        = $mac->get_last_n_fte($self{FWT_LIMIT});
    my $arp        = $mac->get_last_n_arp($self{ARP_LIMIT});
    my @devices    = $mac->devices;
    if ( @devices ){
	print "Devices using this address: ";
	print join(', ', map { $_->get_label } @devices), "\n";
	
    }
    my @interfaces = $mac->interfaces;
    if ( @interfaces ){
	print "Interfaces using this address: ";
	print join(', ', map { $_->get_label } @interfaces), "\n";
    }
    print "\n";

    if ( $fwt && scalar @$fwt ){
	my %tstamps;
        foreach my $row ( @$fwt ){
            my ($tstamp, $iid) = @$row;
            my $iface = Interface->retrieve($iid);
            my $lbl   = $iface->get_label;
	    push @{$tstamps{$tstamp}}, $lbl;
        }

	print "Last $self{FWT_LIMIT} forwarding table entries:\n\n";

	foreach my $tstamp ( reverse sort keys %tstamps ){
            print $tstamp, ", ", join ', ', @{$tstamps{$tstamp}}, "\n";
	}
    }

    if ( $show_arp ){
	print "\nLast $self{ARP_LIMIT} ARP cache entries:\n\n";

	if ( $arp && scalar @$arp ){
	    my %tstamps;
	    foreach my $row ( @$arp ){
		my ($iid, $ipid, $tstamp) = @$row;
		my $lbl    = Interface->retrieve($iid)->get_label;
		push @{$tstamps{$tstamp}{$ipid}}, $lbl;
	    }
	    foreach my $tstamp ( reverse sort keys %tstamps ){
		foreach my $ipid ( keys %{$tstamps{$tstamp}} ){
		    my $iplbl   = Ipblock->retrieve($ipid)->get_label;
		    print $tstamp, ", ", $iplbl, ", ", (join ', ', @{$tstamps{$tstamp}{$ipid}}), "\n";
		}
	    }
	}
    }
    print "\n";
    if ( scalar(@interfaces) == 1 && int($interfaces[0]->neighbor) ){
	print "Neighbor interface: ", $interfaces[0]->neighbor->get_label, "\n";
    }else{
	my $edge_port = $mac->find_edge_port();
	&print_location($edge_port) if $edge_port;
    }
}

###############################################################################
sub search_live{
    my %argv = @_;

    my $info = Device->search_address_live(%argv);
    if ( $info ){
	print "Address: $address\n";
	print "ARP entries: \n";
	foreach my $id ( keys %{$info->{routerports}} ){
	    my $iface = Interface->retrieve($id);
	    my $ip  = (keys %{$info->{routerports}{$id}})[0];
	    my $mac = $info->{routerports}{$id}{$ip};
	    print $iface->get_label, ", ", $ip, ", ", $mac, "\n";
	}
	print "\n";
	print "FWT entries: \n";
	foreach my $id ( keys %{$info->{switchports}} ){
	    my $iface = Interface->retrieve($id);
	    print $iface->get_label;
	    print " ";
	}
	print "\n";
	&print_location($info->{edge}) if $info->{edge};
	
    }else{
	die "$address not found\n";
    }
}

###############################################################################
sub print_location{
    my $port = shift;
    return unless $port;
    my $iface = Interface->retrieve($port);
    return unless $iface;
    my $info  = '';
    $info    .= ', '.$iface->description if $iface->description;
    my $jack  = ($iface->jack)? $iface->jack->get_label : $iface->jack_char;
    $info    .= ', '.$jack if $jack;
    print "\nLocation: ", $iface->get_label, $info, "\n";
}
