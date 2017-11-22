#!<<Make:PERL>>
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;

my %self;
$self{ARP_LIMIT} = 0;
$self{FWT_LIMIT} = 0;

my $USAGE = <<EOF;

    Locate a device given its name, MAC or IP address.  

  Usage: $0 [options] <ether|ip|name>

    Available options:

    -A|--arp_limit <value>  Number of latest ARP cache entries to show (default: $self{ARP_LIMIT})
    -F|--fwt_limit <valud>  Number of latest Forwarding Table entries to show (default: $self{FWT_LIMIT})
    -d|--debug              Show debugging output
    -h|--help               Show help
    
EOF
    
my $MAC  = Netdot->get_mac_regex();

# handle cmdline args
my $result = GetOptions( "A|arp_limit:s"  => \$self{ARP_LIMIT},
			 "F|fwt_limit:s"  => \$self{FWT_LIMIT},
			 "h|help"         => \$self{HELP},
			 "d|debug"        => \$self{DEBUG},
    );

my $address = shift @ARGV;

if ( !$result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $self{HELP} ) {
    print $USAGE;
    exit;
}
if ( !$address ) {
    print $USAGE;
    die "Error: Missing address or name\n";
}

my $logger = Netdot->log->get_logger('Netdot::Model::Device');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);

# Notice that $DEBUG is imported from Log::Log4perl
$logger->level($DEBUG) if ( $self{DEBUG} ); 

print "--------------------\n";

if ( $address =~ /^$MAC$/ ){
    $address = PhysAddr->format_address_db($address);
    &show_mac($address, 1);

}elsif ( Ipblock->matches_ip($address) ){
    &show_ip($address, 1);
}else{
    # Try to resolve
    if ( my @ips = Netdot->dns->resolve_name($address) ){
	foreach my $ip ( @ips ){
	    &show_ip($ip, 1);
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
    my ($address, $show_arp) = @_;
    my $ip = Ipblock->search(address=>$address)->first;
    my $subnet;
    if ( $ip ){
	my $parent = $ip->parent;	
	if ( int($parent->status) && $parent->status->name eq "Subnet" ){
	    $subnet = $parent;
	}
	print "\n";
	print "IP Address : ", $address, "\n";
	if ( $subnet ){
	    print "Subnet     : ", $subnet->get_label, ", ", $subnet->description, "\n";
	}
	if ( my $name = Netdot->dns->resolve_ip($address) ){
	    print "DNS        : ", $name, "\n";
	}
	if ( $show_arp ){
	    my $last_n = $self{ARP_LIMIT} || 1;
	    if ( my $arp = $ip->get_last_n_arp($last_n) ){
		my @rows;
		my %tstamps;
		my $latest_mac;
		foreach my $row ( @$arp ){
		    my ($iid, $macid, $tstamp) = @$row;
		    my $lbl   = Interface->retrieve($iid)->get_label;
		    push @{$tstamps{$tstamp}{$macid}}, $lbl;
		}
		if ( $self{ARP_LIMIT} ){
		    print "\nLatest ARP cache entries:\n\n";
		}
		foreach my $tstamp ( reverse sort keys %tstamps ){
		    foreach my $macid ( keys %{$tstamps{$tstamp}} ){
			my $mac   = PhysAddr->retrieve($macid)->address;
			$latest_mac  = $mac unless defined $latest_mac;
			if ( $self{ARP_LIMIT} ){
			    print $tstamp, " ", PhysAddr->format_address(address => $mac), " ", (join ', ', @{$tstamps{$tstamp}{$macid}}), "\n";
			}
		    }
		}
		&show_mac($latest_mac);
	    }
	}
    }else{
	print "$address not found in DB";
	exit 0;
    }
}


###############################################################################
sub show_mac {
    my ($address, $show_arp) = @_;
    
    my $mac = PhysAddr->search(address=>$address)->first;
    if ( !$mac ){
	print "$address not found in DB\n";
	exit 0;
    }

    print "\n";
    print "MAC Address : ", $mac->address,    "\n";
    print "Vendor      : ", $mac->vendor,     "\n";
    print "First Seen  : ", $mac->first_seen, "\n";
    print "Last Seen   : ", $mac->last_seen,  "\n";

    my $last_n_fte = $self{FWT_LIMIT} || 1;
    my $last_n_arp = $self{ARP_LIMIT} || 1;

    my $fwt        = $mac->get_last_n_fte($last_n_fte);
    my $arp        = $mac->get_last_n_arp($last_n_arp);
    my @devices    = $mac->devices;
    if ( @devices ){
	print "\nDevices using this address: ";
	print join(', ', map { $_->get_label } @devices), "\n";
    }
    my @interfaces = $mac->interfaces;
    if ( @interfaces ){
	print "\nInterfaces using this address: ";
	print join(', ', map { $_->get_label } @interfaces), "\n";
    }

    if ( $self{FWT_LIMIT} ){
	if ( $fwt && scalar @$fwt ){
	    my %tstamps;
	    foreach my $row ( @$fwt ){
		my ($tstamp, $iid) = @$row;
		my $iface = Interface->retrieve($iid);
		my $lbl   = $iface->get_label;
		push @{$tstamps{$tstamp}}, $lbl;
	    }

	    print "\nLatest forwarding table entries:\n\n";
	    
	    foreach my $tstamp ( reverse sort keys %tstamps ){
		print $tstamp, ", ", join ', ', @{$tstamps{$tstamp}}, "\n";
	    }
	}
    }

    my ($latest_ip_id, $latest_ip);
    if ( $show_arp ){
	if ( $self{ARP_LIMIT} ){
	    print "\nLatest ARP cache entries:\n\n";
	}

	if ( $arp && scalar @$arp ){
	    my %tstamps;
	    foreach my $row ( @$arp ){
		my ($iid, $ipid, $tstamp) = @$row;
		$latest_ip_id = $ipid unless $latest_ip_id;
		my $lbl = Interface->retrieve($iid)->get_label;
		push @{$tstamps{$tstamp}{$ipid}}, $lbl;
	    }
	    if ( $self{ARP_LIMIT} ){
		foreach my $tstamp ( reverse sort keys %tstamps ){
		    foreach my $ipid ( keys %{$tstamps{$tstamp}} ){
			my $iplbl   = Ipblock->retrieve($ipid)->get_label;
			print $tstamp, ", ", $iplbl, ", ", (join ', ', @{$tstamps{$tstamp}{$ipid}}), "\n";
		    }
		}
	    }
	    $latest_ip = Ipblock->retrieve($latest_ip_id)->address;
	}
    }
    
    &show_ip($latest_ip) if $latest_ip;

    if ( scalar(@interfaces) == 1 && int($interfaces[0]->neighbor) ){
	print "\nNeighbor interface: ", $interfaces[0]->neighbor->get_label, "\n";
    }else{
	my $edge_port = $mac->find_edge_port();
	&print_location($edge_port) if $edge_port;
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
    print "\nLocation    : ", $iface->get_label, $info;
    print "\nModel       : ", $iface->device->product->get_label;
    print "\n\n";
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut
