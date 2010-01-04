package Netdot::Exporter;

use base 'Netdot';
use Netdot::Model;
use warnings;
use strict;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);

my $logger = Netdot->log->get_logger('Netdot::Exporter');

my %types = (
    'Nagios' => 'Netdot::Exporter::Nagios',
    'Sysmon' => 'Netdot::Exporter::Sysmon',
    'Rancid' => 'Netdot::Exporter::Rancid',
    'BIND'   => 'Netdot::Exporter::BIND',
    'DHCPD'  => 'Netdot::Exporter::DHCPD',
    );

my %_class_data;
my $_cache_timeout = 60;  # Seconds	

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
	    $class->throw_user("Netdot::Exporter::new: Unknown Exporter type: $argv{type}");
	eval "use $subclass;";
	if ( my $e = $@ ){
	    $class->throw_user($e);
	}
	$self = $subclass->new();
    }else {
	bless $self, $class;
    }
    
    $self->{_dbh} = Netdot::Model->db_Main();
    return $self;
}

########################################################################
=head2 get_device_info

  Arguments:
    None
  Returns:
    Hash reference where key=device.id
  Examples:
    my $ips = Netdot::Model::Exporter->get_device_info();
=cut
sub get_device_info {
    my ($self) = @_;
    
    return $self->_cache('device_info')	if $self->_cache('device_info');

    my %device_info;
    $logger->debug("Netdot::Exporter::get_device_info: querying database");
    my $rows = $self->{_dbh}->selectall_arrayref("
                SELECT    device.id, device.snmp_managed, device.community,
                          device.down_from, device.down_until, entity.name, contactlist.id,
                          target.id, target.address, target.version, target.parent, rr.name, zone.name,
                          interface.id, interface.number, interface.admin_status, interface.monitored, interface.contactlist,
                          bgppeering.bgppeeraddr, bgppeering.monitored
                FROM      rr, zone, interface, device
                LEFT JOIN ipblock target ON device.snmp_target=target.id
                LEFT JOIN entity ON device.used_by=entity.id
                LEFT JOIN devicecontacts ON device.id=devicecontacts.device
                LEFT JOIN contactlist ON contactlist.id=devicecontacts.contactlist
                LEFT JOIN bgppeering ON device.id=bgppeering.device
                WHERE     device.monitored=1
                     AND  interface.device=device.id                  
                     AND  device.name=rr.id 
                     AND  rr.zone=zone.id
         ");
    
    $logger->debug("Netdot::Exporter::get_device_info: building data structure");
    foreach my $row ( @$rows ){
	my ($devid, $devsnmp, $community, 
	    $down_from, $down_until, $entity, $clid,
	    $target_id, $target_addr, $target_version, $subnet, $name, $zone, 
	    $intid, $intnumber, $intadmin, $intmon, $intcl,
	    $peeraddr, $peermon) = @$row;
	my $hostname = $name.'.'.$zone;
	$device_info{$devid}{ipid}         = $target_id;
	$device_info{$devid}{ipaddr}       = $target_addr;
	$device_info{$devid}{ipversion}    = $target_version;
	$device_info{$devid}{subnet}       = $subnet;
	$device_info{$devid}{hostname}     = $hostname;
	$device_info{$devid}{community}    = $community;
	$device_info{$devid}{snmp_managed} = $community;
	$device_info{$devid}{down_from}    = $down_from;
	$device_info{$devid}{down_until}   = $down_until;
	$device_info{$devid}{used_by}      = $entity if defined $entity;
	$device_info{$devid}{contactlist}{$clid} = 1 if defined $clid;
	$device_info{$devid}{peering}{$peeraddr}{monitored}  = $peermon if defined $peeraddr;
	$device_info{$devid}{interface}{$intid}{number}      = $intnumber;
	$device_info{$devid}{interface}{$intid}{admin}       = $intadmin;
	$device_info{$devid}{interface}{$intid}{monitored}   = $intmon;
	$device_info{$devid}{interface}{$intid}{contactlist} = $intcl;
    }

    return $self->_cache('device_info', \%device_info);
}

########################################################################
=head2 get_device_main_ip 

  Arguments:
    devicd id
  Returns:
    IP address string
  Examples:
    
=cut
sub get_device_main_ip {
    my ($self, $devid) = @_;

    $self->throw_fatal("Missing required arguments")
	unless $devid;

    my $device_info = $self->get_device_info();
    return unless exists $device_info->{$devid};

    my $ip;
    if ( $device_info->{$devid}->{ipaddr} && $device_info->{$devid}->{version} ){
	$ip = Ipblock->int2ip($device_info->{$devid}->{ipaddr}, $device_info->{$devid}->{ipversion});
    }elsif ( $ip = (Netdot->dns->resolve_name($device_info->{$devid}->{hostname}))[0] ){
	# we're done here
    }else{
	# Grab the first IP we can get
	my $device = Device->retrieve($devid);
	if ( my $ips = $device->get_ips() ){
	    $ip = $ips->[0]->address if $ips->[0];
	}
    }
    return $ip;
}

########################################################################
=head2 get_device_parents

  Arguments:
    Device id of NMS (root of the tree)
  Returns:
    Hash reference
  Examples:

=cut
sub get_device_parents {
    my ($self, $nms) = @_;

    $self->throw_fatal("Missing required arguments")
	unless $nms;

    return $self->_shortest_path_parents($nms);
}

########################################################################
=head2 - get_monitored_ancestors

  Arguments:
    Device id
  Returns:
    Array of device IDs
  Examples:

=cut
sub get_monitored_ancestors {
    my ($self, $devid, $device_parents) = @_;
    
    $self->throw_fatal("Missing required arguments")
	unless ( $devid && $device_parents );

    return unless defined $device_parents->{$devid};

    my $device_info = $self->get_device_info();
    my @ids;

    foreach my $parent_id ( keys %{$device_parents->{$devid}} ){
	if ( exists $device_info->{$parent_id} ){
	    push @ids, $parent_id;
	}
    }
    return @ids if @ids;
    
    foreach my $parent_id ( keys %{$device_parents->{$devid}} ){
	return $self->get_monitored_ancestors($parent_id, $device_parents);
    }
}

############################################################################
=head2 _get_device_graph

  Arguments:
    None
  Returns:
    Hash reference
  Examples:

=cut
sub get_device_graph {
    my ($self) = @_;

    return $self->_cache('device_graph')
	if $self->_cache('device_graph');

    $logger->debug("Netdot::Exporter::get_device_graph: querying database");
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
    
    return $self->_cache('device_graph', $graph);
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
=head2 in_downtime - Check if device is within scheduled downtime

 Arguments: 
    device id
 Returns:
    1 or 0

=cut
sub in_downtime{
    my ($self, $devid) = @_;
    
    my $device_info = $self->get_device_info();
    my $dev = $device_info->{$devid} || return;
    my ($down_from, $down_until) = ($dev->{down_from}, $dev->{down_until});
    if ( $down_from && $down_until &&
	 $down_from ne '0000-00-00' && $down_until ne '0000-00-00' ){
	my $time1 = Netdot::Model->sqldate2time($down_from);
	my $time2 = Netdot::Model->sqldate2time($down_until);
	my $now = time;
	if ( $time1 < $now && $now < $time2 ){
	    $logger->debug("Netdot::Exporter::is_in_downtime: Device $devid".
			   " within scheduled downtime period");
	    return 1;
	}
    }
    return 0;
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
# Returns:
#    Hash ref where key = Device.id, value = Hashref where keys = parent Device.id's
#
sub _shortest_path_parents {
    my ($self, $s) = @_;
    
    $self->throw_fatal("Missing required arguments") unless ( $s );

    my $graph = $self->get_device_graph();

    $logger->debug("Netdot::Exporter::_shortest_path_parents: Determining all shortest paths to Device id $s");

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
    return \%parents;
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

#Be sure to return 1
1;
