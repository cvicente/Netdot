package Netdot::Exporter;

use base 'Netdot';
use Netdot::Model;
use warnings;
use strict;
use Carp;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

my %types = (
    'Nagios' => 'Netdot::Exporter::Nagios',
    'Sysmon' => 'Netdot::Exporter::Sysmon',
    'Rancid' => 'Netdot::Exporter::Rancid',
    );
	
=head1 NAME

Netdot::Exporter - Object Factory for Classes that 

=head1 SYNOPSIS


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
    unless ( $self->{_graph} ) {
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
	$self->{_graph} = $graph;
    }
    return $self->{_graph};
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
    unless ( $self->{_device_ips} ){
	$logger->debug("Netdot::Exporter::get_device_ips: querying database");
	my $device_ips = $self->{_dbh}->selectall_arrayref("
                SELECT   device.id, ipblock.id, interface.monitored, device.monitored
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
    my %parents = ();
    foreach my $d ( keys %$graph ) {
	next if ( $d == $nms );
	$parents{$d} = [];
	foreach my $neighbor ( keys %{$graph->{$d}} ) {
	    if ( $self->_dfs($neighbor, $nms, $graph, $d) ) {
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
    return $ipdeps;
}

########################################################################
# Private methods
########################################################################

########################################################################
# Depth first search
sub _dfs {
    my ($self, $s, $t, $graph, $forbidden, $seen) = @_;
    defined $s         || $self->throw_fatal("Netdot::Exporter::_dfs: No saource vertex");
    defined $t         || $self->throw_fatal("Netdot::Exporter::_dfs: No target vertex");
    defined $graph     || $self->throw_fatal("Netdot::Exporter::_dfs: No graph");
    defined $forbidden || $self->throw_fatal("Netdot::Exporter::_dfs: No forbidden vertex");
    $seen ||= {};
    
    $seen->{$s} = 1;
    if ($s == $t) { # Base case 
	return 1; 
    } else { # Recursive case
	foreach my $n ( keys %{$graph->{$s}} ) {
	    next if exists $seen->{$n};
	    next if $forbidden == $n;
	    if ( $self->_dfs($n, $t, $graph, $forbidden, $seen) ) {
		return 1;
	    }
	}
	return 0;
    }
}


########################################################################
# Recursively look for monitored ancestors
sub _get_ip_deps {
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
	    push @grandparents, @{$ancestors->{$parent}} if ( defined $ancestors->{$parent} 
							      && ref($ancestors->{$parent}) eq "ARRAY" );
	}
	if ( @grandparents ){
	    $self->_get_ip_deps($ipid, \@grandparents, $ancestors, $device2ips, $ip_monitored);
	}
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
