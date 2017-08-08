package Netdot::Exporter;

use base 'Netdot';
use Netdot::Model;
use warnings;
use strict;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);

my $logger = Netdot->log->get_logger('Netdot::Exporter');

my %types = (
    'Nagios'    => 'Netdot::Exporter::Nagios',
    'Sysmon'    => 'Netdot::Exporter::Sysmon',
    'Rancid'    => 'Netdot::Exporter::Rancid',
    'BIND'      => 'Netdot::Exporter::BIND',
    'DHCPD'     => 'Netdot::Exporter::DHCPD',
    'Smokeping' => 'Netdot::Exporter::Smokeping',
    );

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
    subclass arguments
  Returns:
    Netdot::Exporter object
  Examples:
    my $export = Netdot::Exporter->new(type=>'Nagios');
=cut

sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    
    my $type = delete $argv{type};

    if ( $type ) { 
	my $subclass = $types{$type} ||
	    $class->throw_user("Netdot::Exporter::new: Unknown Exporter type: $type");
	eval "use $subclass;";
	$self = $subclass->new(%argv);
    }else {
	bless $self, $class;
    }
    
    return $self;
}

########################################################################

=head2 get_device_info

All device information needed for building monitoring configurations

  Arguments:
    Hash with following keys:
     site (str) - Name of site to filter (defaults to all sites)
  Returns:
    Hash reference where key=device.id
  Examples:
    my $info = Netdot::Exporter->get_device_info();
=cut

sub get_device_info {
    my ($self, %argv) = @_;

    # Don't cache if asked to filter by site
    unless (exists $argv{site}){
	return $self->cache('exporter_device_info')	if $self->cache('exporter_device_info');
    }

    my %device_info;
    $logger->debug("Netdot::Exporter::get_device_info: querying database");

    my $dbh = Netdot::Model->db_Main();
    my $query = "
          SELECT    d.id, d.snmp_managed, d.community, d.snmp_target, d.host_device,
                    d.monitoring_template, d.down_from, d.down_until, entity.name, entity.aliases,
                    p.name, ptype.name, manuf.name,
                    site.name, site.number, site.aliases, contactlist.id,
                    i.id, i.number, i.name, i.description, i.admin_status, i.monitored, i.contactlist, i.speed,
                    ip.id, ip.address, ip.version, ip.parent, ip.monitored, rr.name, zone.name,
                    service.id, service.name, ipservice.monitored, ipservice.contactlist,
                    bgppeering.bgppeeraddr, bgppeering.contactlist, peer.asnumber, peer.asname
          FROM      rr, zone, device d
          LEFT OUTER JOIN (bgppeering, entity peer) ON d.id=bgppeering.device 
                           AND bgppeering.entity=peer.id
                           AND bgppeering.monitored=1
          LEFT OUTER JOIN (asset, product p, producttype ptype, entity manuf) ON asset.id=d.asset_id
                           AND asset.product_id=p.id
                           AND p.type=ptype.id
                           AND manuf.id=p.manufacturer
          LEFT OUTER JOIN devicecontacts ON d.id=devicecontacts.device
          LEFT OUTER JOIN contactlist ON contactlist.id=devicecontacts.contactlist
          LEFT OUTER JOIN entity ON d.used_by=entity.id
          LEFT OUTER JOIN site ON d.site=site.id,
                     interface i 
          LEFT OUTER JOIN ipblock ip ON ip.interface=i.id
          LEFT OUTER JOIN ipservice ON ipservice.ip=ip.id
          LEFT OUTER JOIN service ON ipservice.service=service.id
          WHERE     d.monitored='1'
               AND  i.device=d.id                  
               AND  d.name=rr.id 
               AND  rr.zone=zone.id
         ";
    
    $query .= " AND site.name=?" if exists $argv{site};
    my $sth = $dbh->prepare($query);
    if ($argv{site}){
	$sth->execute($argv{site});
    }else{
	$sth->execute();
    }

    my $rows = $sth->fetchall_arrayref();
    $logger->debug("Netdot::Exporter::get_device_info: building data structure");
    foreach my $row ( @$rows ){

	my ($devid, $dev_snmp, $community, $target_id, $host_device,
	    $mon_template, $down_from, $down_until, $entity_name, $entity_alias, 
	    $pname, $ptype, $manuf,
	    $site_name, $site_number, $site_alias, $clid,
	    $intid, $intnumber, $intname, $intdesc, $intadmin, $intmon, $intcl, $intspeed,
	    $ip_id, $ip_addr, $ip_version, $subnet, $ip_mon, $name, $zone,
	    $srv_id, $srv_name, $srv_mon, $srv_cl,
	    $peer_addr, $peer_cl, $peer_asn, $peer_asname) = @$row;
	my $hostname = ($name eq '@')? $zone : $name.'.'.$zone;
	$device_info{$devid}{target_id}    = $target_id;
	$device_info{$devid}{hostname}     = $hostname;
	$device_info{$devid}{pname}        = $pname if defined $pname;
	$device_info{$devid}{ptype}        = $ptype if defined $ptype;
	$device_info{$devid}{manuf}        = $manuf if defined $manuf;
	$device_info{$devid}{host_device}  = $host_device;
	$device_info{$devid}{community}    = $community;
	$device_info{$devid}{snmp_managed} = $dev_snmp;
	$device_info{$devid}{mon_template} = $mon_template;
	$device_info{$devid}{down_from}    = $down_from;
	$device_info{$devid}{down_until}   = $down_until;
	$device_info{$devid}{usedby_entity_name}  = $entity_name  if defined $entity_name;
	$device_info{$devid}{usedby_entity_alias} = $entity_alias if defined $entity_alias;
	$device_info{$devid}{site_name}    = $site_name    if defined $site_name;
	$device_info{$devid}{site_number}  = $site_number  if defined $site_number;
	$device_info{$devid}{site_alias}   = $site_alias   if defined $site_alias;
	$device_info{$devid}{contactlist}{$clid}{clid} = $clid if defined $clid;
	if ( $peer_addr ){
	    $device_info{$devid}{peering}{$peer_addr}{contactlist} = $peer_cl;
	    $device_info{$devid}{peering}{$peer_addr}{asn}         = $peer_asn    if $peer_asn;
	    $device_info{$devid}{peering}{$peer_addr}{asname}      = $peer_asname if $peer_asname;
	}
	$device_info{$devid}{interface}{$intid}{number}       = $intnumber;
	$device_info{$devid}{interface}{$intid}{name}         = $intname;
	$device_info{$devid}{interface}{$intid}{description}  = $intdesc;
	$device_info{$devid}{interface}{$intid}{admin}        = $intadmin;
	$device_info{$devid}{interface}{$intid}{monitored}    = $intmon;
	$device_info{$devid}{interface}{$intid}{contactlist}  = $intcl;
	$device_info{$devid}{interface}{$intid}{speed}        = $intspeed;
	if ( defined $ip_id ){
	    $device_info{$devid}{interface}{$intid}{ip}{$ip_id}{addr}      = $ip_addr;
	    $device_info{$devid}{interface}{$intid}{ip}{$ip_id}{version}   = $ip_version;
	    $device_info{$devid}{interface}{$intid}{ip}{$ip_id}{subnet}    = $subnet;
	    $device_info{$devid}{interface}{$intid}{ip}{$ip_id}{monitored} = $ip_mon;
	    if ( defined $target_id && $ip_id == $target_id ){
		$device_info{$devid}{target_addr} = $ip_addr;
		$device_info{$devid}{target_version} = $ip_version;
	    }
	    if ( defined $srv_id ){
		$device_info{$devid}{interface}{$intid}{ip}{$ip_id}{srv}{$srv_id}{name}        = $srv_name;
		$device_info{$devid}{interface}{$intid}{ip}{$ip_id}{srv}{$srv_id}{monitored}   = $srv_mon;
		$device_info{$devid}{interface}{$intid}{ip}{$ip_id}{srv}{$srv_id}{contactlist} = $srv_cl;
	    }
	}
    }
    
    # Don't cache if asked to filter by site
    unless (exists $argv{site}){
	$self->cache('exporter_device_info', \%device_info);
    }
    return \%device_info;
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

    return Device->shortest_path_parents($nms);
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

########################################################################

=head2 open_and_lock - Open and lock file for writing


 Arguments: 
    filename
 Returns:
    File handle reference

=cut

sub open_and_lock {
    my ($self, $filename) = @_;

    sysopen(FH, $filename, O_WRONLY | O_CREAT)
	or $self->throw_user("Can't open $filename: $!");
    flock(FH, LOCK_EX | LOCK_NB)
	or $self->throw_user("Can't lock $filename: $!");
    truncate(FH, 0)
	or $self->throw_user("Can't truncate $filename: $!");
    
    return \*FH;

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
	    $logger->debug("Netdot::Exporter::in_downtime: Device $devid".
			   " within scheduled downtime period");
	    return 1;
	}
    }
    return 0;
}

########################################################################

=head2 print_eof - Print End of File marker

 Arguments: 
    filehandle
 Returns:
    Nothing

=cut

sub print_eof {
    my ($self, $fh) = @_;
    $self->throw_fatal("Netdot::Model::Exporter::print_eof: Filehandle required")
	unless $fh;
    print $fh "\n#### EOF ####\n";
}

=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>
Peter Boothe

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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
