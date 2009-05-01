package Netdot::Exporter;

use base 'Netdot';
use Netdot::Model;
use warnings;
use strict;
use Carp;
use Fcntl qw(:DEFAULT :flock);

my $logger = Netdot->log->get_logger('Netdot::Exporter');

my %types = (
    'Nagios' => 'Netdot::Exporter::Nagios',
    'Sysmon' => 'Netdot::Exporter::Sysmon',
    'Rancid' => 'Netdot::Exporter::Rancid',
    );

my %_class_data;
my $_cache_timeout = 3600;  # Seconds	

=head1 NAME

Netdot::Exporter - Base class and object factory for Netdot exports

=head1 SYNOPSIS

    my $export = Netdot::Exporter->new(type=>'Nagios');
    $export->generate_configs();

=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    type - Netdot::Exporter type (Nagios|Sysmon|Rancid)
  Returns:
    Netdot::Exporter object
  Examples:
    my $export = Netdot::Exporter->new(type=>'Nagios');
=cut
sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    
    if ( $argv{type} ) { 
	my $subclass = $types{$argv{type}} ||
	    croak "Netodt::Exporter::new: Unknown Exporter type: $argv{type}";
	eval "use $subclass;";
	croak $@ if $@;
	$self = $subclass->new();
    }else {
	bless $self, $class;
    }
    
    $self->{_dbh} = Netdot::Model->db_Main();
    return $self;
}


############################################################################
=head2 get_graph

  Arguments:
    None
  Returns:
    Hash reference
  Examples:

=cut
sub get_graph {
    my ($self) = @_;

    return $self->_cache('graph')
	if $self->_cache('graph');

    $logger->debug("Netdot::Exporter::get_graph: querying database");
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
    
    return $self->_cache('graph', $graph);
}

########################################################################
=head2 get_device_ips

  Arguments:
    None
  Returns:
    Array reference
  Examples:

=cut
sub get_device_ips {
    my ($self) = @_;
    
    return $self->_cache('device_ips')
	if $self->_cache('device_ips');
    
    $logger->debug("Netdot::Exporter::get_monitored_ips: querying database");
    my $device_ips = $self->{_dbh}->selectall_arrayref("
                SELECT   device.id, ipblock.id, interface.monitored, device.monitored,
                         device.down_from, device.down_until
                FROM     device, interface, ipblock
                WHERE    ipblock.interface=interface.id
                  AND    interface.device=device.id
                ORDER BY ipblock.address
         ");
    
    return $self->_cache('device_ips', $device_ips);
}
########################################################################
=head2 get_monitored_ips

  Arguments:
    None
  Returns:
    Array reference
  Examples:

=cut
sub get_monitored_ips {
    my ($self) = @_;

    return $self->_cache('monitored_ips') 
	if $self->_cache('monitored_ips');

    my $device_ips = $self->get_device_ips();
    my @results;
    my %name2ip;
    
    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $int_monitored, $dev_monitored, $down_from, $down_until) = @$row;
	next unless ( $int_monitored && $dev_monitored );
	
	# Check downtime dates to see if this device should be excluded
	if ( $down_from && $down_until && 
	     $down_from ne '0000-00-00' && $down_until ne '0000-00-00' ){
	    my $time1 = Netdot::Model->sqldate2time($down_from);
	    my $time2 = Netdot::Model->sqldate2time($down_until);
	    my $now = time;
	    if ( $time1 < $now && $now < $time2 ){
		$logger->debug("Netdot::Exporter::get_monitored_ips: Device $deviceid".
			       " within scheduled downtime period.  Excluding.");
		next;
	    }
	}
	my $ipobj  = Ipblock->retrieve($ipid);
	
	my $hostname;
	if ( my $name = $self->dns->resolve_ip($ipobj->address) ){
	    $hostname = $name;
	}elsif ( my @arecords = $ipobj->arecords ){
	    $hostname = $arecords[0]->rr->get_label;
	}else{
	    $hostname = $ipobj->address;
	}
	
	unless ( $hostname && $self->dns->resolve_name($hostname) ){
	    $logger->warn($ipobj->address." does not resolve symmetrically.  Using IP address");
	    $hostname = $ipobj->address;
	}
	if ( exists $name2ip{$hostname} ){
	    $logger->warn($hostname." is not unique.  Using IP address");
	    $hostname = $ipobj->address;
	}
	$name2ip{$hostname} = $ipobj->id;
	
	push @results, [$deviceid, $ipid, $ipobj->address, $hostname];
    }
    
    return $self->_cache('monitored_ips', \@results);
}

########################################################################
=head2 get_dependencies - Recursively look for valid parents

    If the parent(s) don't have ip addresses or are not managed,
    try to keep the tree connected anyways

 Arguments: 
   ID of Network Management Device
 Returns:
    Hash ref where key = Ipblock.id, value = Arrayref of parent Ipblock.id' s

=cut
sub get_dependencies{
    my ($self, $nms) = @_;

    return $self->_cache('dependencies')
	if $self->_cache('dependencies');

    defined $nms || 
	$self->throw_fatal("Netdot::Exporter::get_dependencies: Need to pass monitoring device");

    my $graph      = $self->get_graph();
    my $device_ips = $self->get_device_ips();

    my (%device2ips, %ip_monitored);
    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $int_monitored, $dev_monitored) = @$row;
	push @{$device2ips{$deviceid}}, $ipid;
	$ip_monitored{$ipid} = ($int_monitored && $dev_monitored) ? 1 : 0;
    }

    # For each device, the parent list consists of all neighbor devices
    # which are in the path between this device and the monitoring system

    my %parents = %{ $self->_shortest_path_parents($graph, $nms) };

    # Build the IP dependency hash
    my $ipdeps = {};
    foreach my $device ( keys %device2ips ){
	next if ( $device == $nms );
	if ( !exists $parents{$device} ){
 	    if ( $logger->is_debug() ){
 		my $dev = Netdot::Model::Device->retrieve($device);
 		$logger->debug("Netdot::Exporter::get_dependencies: ". $dev->get_label .": No path to NMS.  Assigning NMS as parent.");
	    }
	    push @{$parents{$device}}, $nms;
	}
	foreach my $ipid ( @{$device2ips{$device}} ){
	    my $deps = $self->_get_ip_deps($ipid, $parents{$device}, \%parents, 
					   \%device2ips, \%ip_monitored);
	    $ipdeps->{$ipid} = $deps 
		if ( defined $deps && ref($deps) eq 'HASH' );
	}
    }
    # Convert hash of hashes to hash of arrayrefs
    foreach my $ipid ( keys %$ipdeps ){
	my @list = keys %{$ipdeps->{$ipid}};
	$ipdeps->{$ipid} = \@list;
    }

    return $self->_cache('dependencies', $ipdeps);
}

########################################################################
=head2 open_and_lock - Open and lock file for writing


 Arguments: 
    filename
 Returns:
    File handle reference

=cut
sub open_and_lock {
    my ($self, $filename) = @_;

    eval {
	sysopen(FH, $filename, O_WRONLY | O_CREAT)
	    or $self->throw_user("Exporter::lock_file: Can't open $filename: $!");
	flock(FH, LOCK_EX | LOCK_NB)
	    or $self->throw_user("Exporter::lock_file: Can't lock $filename: $!");
	truncate(FH, 0)
	    or $self->throw_user("Exporter::lock_file: Can't truncate $filename: $!");
    };
    if ( my $e = $@ ){
	$self->throw_fatal($e);
    }else{
	return \*FH;
    }
}

########################################################################
# Private methods
########################################################################

########################################################################
# Shortest Path Parents
#
# A variation of Dijkstra's single-source shortest paths algorithm 
# to determine all the possible parents of each node that are in the 
# shortest paths between that node and the given source.
#
# Arguments:
#    s          Source vertex
#    graph      Hashref with connected devices 
#               (key=Device ID, value=Device ID)
# Returns:
#    Hash ref where key = Device.id, value = Arrayref of parent Device.id's
#
sub _shortest_path_parents {
    my ($self, $graph, $s) = @_;
    
    $self->throw_fatal("Missing required arguments")
	unless ( $graph && $s );

    $logger->debug("Netdot::Exporter::_sp_parents: Determining all shortest paths to NMS");

    my %cost;
    my %parents;
    my %dist;
    my $infinity = 1000000;
    my @nodes    = keys %$graph;
    my @q        = @nodes;
    
    # Set all distances to infinity, except the source
    # Set default cost to 1
    foreach my $n ( @nodes ) { 
	$dist{$n} = $infinity; 
	$cost{$n} = 1;
    }
    $dist{$s} = 0;

    # Get path costs
    my $q = $self->{_dbh}->selectall_arrayref("SELECT device.id, 
                                                      device.monitoring_path_cost 
                                               FROM   device
                                               WHERE  device.monitoring_path_cost > 1
                                              ");
    foreach my $row ( @$q ){
	my ($id, $cost) = @$row;
	$cost{$id} = $cost;
    }
    
    while ( @q ) {
	
	# sort unsolved by distance from root
	@q = sort { $dist{$a} <=> $dist{$b} } @q;
	
	# we'll solve the closest node.
	my $n = shift @q;
	
	# now, look at all the nodes connected to n
	foreach my $n2 ( keys %{$graph->{$n}} ) {

	    # .. and find out if any of their estimated distances
	    # can be improved if we go through n
	    if ( $dist{$n2} >= ($dist{$n} + $cost{$n}) ) {
		$dist{$n2} = $dist{$n} + $cost{$n};
		# Make sure all our parents have same shortest distance
		foreach my $p ( keys %{$parents{$n2}} ){
		    delete $parents{$n2}{$p} if ( $dist{$p}+$cost{$p} > $dist{$n}+$cost{$n} );
		}
		$parents{$n2}{$n} = 1;
	    }
	}
    }
    # Convert hash of hashes into hash of arrayrefs
    my %results;
    foreach my $n ( keys %parents ){
	my @a = keys %{$parents{$n}};
	$results{$n} = \@a;
    }
    return \%results;
}


########################################################################
# Recursively look for monitored ancestors
#
# Arguments:
#    ipid         Ipblock ID
#    parents      Arrayref of Device IDs
#    ancestors    Hashref containing all Devices and their parents 
#                 where key=Device ID, value=Arrayref of Device IDs
#    device2ips   Hashref with key=Device ID, value=Arrayref of Ipblock IDs
#    ip_monitored Hashref with key=Ipblock, value=monitored flag
#  
#  Returns:
#    Hashref with ip dependencies where key=Ipblock ID
#
sub _get_ip_deps {
    my ($self, $ipid, $parents, $ancestors, $device2ips, $ip_monitored) = @_;
    my %deps;
    foreach my $parent ( @$parents ){
	foreach my $ipid2 ( @{$device2ips->{$parent}} ){
	    next if ( $ipid2 == $ipid );
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
	    $logger->debug("Netdot::Exporter::_get_ip_deps: ". $ipb->get_label .
			   ": no monitored parents found.  Looking for ancestors.");
	}
	my @grandparents;
	foreach my $parent ( @$parents ){
	    push @grandparents, @{$ancestors->{$parent}} if ( defined $ancestors->{$parent} 
							      && ref($ancestors->{$parent}) eq "ARRAY" );
	}
	if ( @grandparents ){
	    $self->_get_ip_deps($ipid, \@grandparents, $ancestors, $device2ips, $ip_monitored);
	}
    }
}


############################################################################
# _cache - Get or set class data cache
#
#  Values time out after $_cache_timeout seconds
#
#  Arguments:
#    cache key
#    cacje data (optional)
#  Returns:
#    cache data or undef if timed out
#  Examples:
#    my $graph = $self->_cache('graph');
#    $self->_cache('graph', $data);
#
#
sub _cache {
    my ($self, $key, $data) = @_;

    $self->throw_fatal("Missing required argument: key")
	unless $key;

    my $timekey = $key."_time";

    if ( defined $data ){
	$_class_data{$key}     = $data;
	$_class_data{$timekey} = time;
    }
    if ( defined $_class_data{$timekey} && 
	 (time - $_class_data{$timekey} > $_cache_timeout) ){
	return;
    }else{
	return $_class_data{$key};
    }
}


=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>
Peter Boothe

=head1 COPYRIGHT & LICENSE

Copyright 2008 University of Oregon, all rights reserved.

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

#Be sure to return 1
1;
