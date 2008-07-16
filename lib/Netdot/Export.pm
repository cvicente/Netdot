package Netdot::Export;

use base 'Netdot';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Export');

=head1 NAME

Netdot::Export - Methods for scripts that export netdot data

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Export object
  Examples:
    my $export = Netdot::Export->new();
=cut
sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    bless $self, $class;
    $self->{_dbh} = Netdot::Model->db_Main();
    return $self;
}

########################################################################
sub get_graph {
    my ($self) = @_;
    unless ( $self->{_graph} ) {
	$logger->debug("Netdot::Export::get_graph: querying database");
        my $graph = {};
        my $links = $self->{_dbh}->selectall_arrayref("
                SELECT  d1.id, d2.id 
                FROM    device d1, device d2, interface i1, interface i2
                WHERE   i1.device = d1.id AND i2.device = d2.id
                    AND i2.neighbor = i1.id AND i1.neighbor = i2.id
            ");
        foreach my $link (@$links) {
            my ($fr, $to) = @$link;
            $graph->{$fr}{$to}  = 1;
            $graph->{$to}{$fr}  = 1;
        }
	$self->{_graph} = $graph;
    }
    return $self->{_graph};
}

########################################################################
sub get_device_ips {
    my ($self) = @_;
    unless ( $self->{_device_ips} ){
	$logger->debug("Netdot::Export::get_device_ips: querying database");
	my $device_ips = $self->{_dbh}->selectall_arrayref("
                SELECT   device.id, ipblock.id, ipblock.address, interface.monitored, device.monitored
                FROM     device, interface, ipblock
                WHERE    ipblock.interface=interface.id
                  AND    interface.device=device.id
                ORDER BY ipblock.address
         ");
	$self->{_device_ips} = $device_ips;
    }
    return $self->{_device_ips};
}

########################################################################
# Recursively look for valid parents
# If the parent(s) don't have ip addresses or are not managed,
# try to keep the tree connected anyways
# Arguments: 
#   ID of Network Management Device
# Returns:
#   Hash ref where key = Ipblock.id, value = Arrayref of parent Ipblock.id' s
########################################################################
sub get_dependencies{
    my ($self, $nms) = @_;
    defined $nms || $self->throw_fatal("Need to pass monitoring device");

    my $graph      = $self->get_graph();
    my $device_ips = $self->get_device_ips();

    my (%device2ips, %ip_monitored);
    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $ipaddr, $int_monitored, $dev_monitored) = @$row;
	push @{$device2ips{$deviceid}}, $ipid;
	$ip_monitored{$ipid} = ($int_monitored && $dev_monitored) ? 1 : 0;
    }

    # For each device, the parent list consists of all neighbor devices
    # which are in the path between this device and the monitoring system
    my %parents = ();
    foreach my $d ( keys %$graph ) {
	$parents{$d} = [];
	foreach my $neighbor ( keys %{$graph->{$d}} ) {
	    if ( $self->dfs($neighbor, $nms, $graph, $d) ) {
		push @{$parents{$d}}, $neighbor;
	    }
	}
	unless ( scalar @{$parents{$d}} ){
	    if ( $logger->is_debug() ){
		my $dev = Netdot::Model::Device->retrieve($d);
		$logger->debug("Device ". $dev->get_label .": No path to NMS.  Assigning NMS as parent.");
		push @{$parents{$d}}, $nms;
	    }
	}
    }

    # Build the IP dependency hash
    my $ipdeps = {};
    foreach my $device ( keys %parents ){
	foreach my $ipid ( @{$device2ips{$device}} ){
	    my $deps = $self->get_ip_deps($ipid, $parents{$device}, \%parents, 
					  \%device2ips, \%ip_monitored);
	    $ipdeps->{$ipid} = $deps if defined $deps;
	}
    }

    # Convert hash of hashes to hash of arrayrefs
    foreach my $ipid ( keys %$ipdeps ){
	my @list = keys %{$ipdeps->{$ipid}};
	$ipdeps->{$ipid} = \@list;
    }
    return $ipdeps;
}

##################################
# Depth first search
sub dfs {
    my ($self, $s, $t, $graph, $forbidden, $seen) = @_;
    defined $s         || $self->throw_fatal("No saource vertex");
    defined $t         || $self->throw_fatal("No target vertex");
    defined $graph     || $self->throw_fatal("No graph");
    defined $forbidden || $self->throw_fatal("No forbidden vertex");
    $seen ||= {};
    
    $seen->{$s} = 1;
    if ($s == $t) { # Base case 
	return 1; 
    } else { # Recursive case
	foreach my $n ( keys %{$graph->{$s}} ) {
	    next if exists $seen->{$n};
	    next if $forbidden == $n;
	    if ( $self->dfs($n, $t, $graph, $forbidden, $seen) ) {
		return 1;
	    }
	}
	return 0;
    }
}

##################################
# Recursively look for monitored ancestors
sub get_ip_deps {
    my ($self, $ipid, $parents, $ancestors, $device2ips, $ip_monitored) = @_;
    my %deps;
    foreach my $parent ( @$parents ){
	foreach my $ipid2 ( @{$device2ips->{$parent}} ){
	    if ( $ip_monitored->{$ipid2} ){
		$deps{$ipid2} = 1;
	    }
	}
    }
    if ( %deps ){
	return \%deps;
    }else{
	if ( $logger->is_debug() ){
	    my $ipb = Netdot::Model::Ipblock->retrieve($ipid);
	    $logger->debug($ipb->get_label .": no monitored parents found.  Looking for ancestors.");
	}
	my @grandparents;
	foreach my $parent ( @$parents ){
	    push @grandparents, @{$ancestors->{$parent}};
	}
	$self->get_ip_deps($ipid, \@grandparents, $ancestors, $device2ips, $ip_monitored);
    }
}



1;
