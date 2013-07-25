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
    
    return $self->cache('exporter_device_info')	if $self->cache('exporter_device_info');

    my %device_info;
    $logger->debug("Netdot::Exporter::get_device_info: querying database");
    my $rows = $self->{_dbh}->selectall_arrayref("
          SELECT    d.id, d.snmp_managed, d.community, d.snmp_target,
                    d.down_from, d.down_until, entity.name, entity.aliases,
                    site.name, site.number, site.aliases, contactlist.id,
                    i.id, i.number, i.name, i.description, i.admin_status, i.monitored, i.contactlist,
                    ip.id, ip.address, ip.version, ip.parent, ip.monitored, rr.name, zone.name,
                    service.id, service.name, ipservice.monitored, ipservice.contactlist,
                    bgppeering.bgppeeraddr, bgppeering.monitored, bgppeering.contactlist
          FROM      rr, zone, device d
          LEFT OUTER JOIN bgppeering ON d.id=bgppeering.device
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
         ");
    
    $logger->debug("Netdot::Exporter::get_device_info: building data structure");
    foreach my $row ( @$rows ){
	my ($devid, $dev_snmp, $community, $target_id,
	    $down_from, $down_until, $entity_name, $entity_alias, 
	    $site_name, $site_number, $site_alias, $clid,
	    $intid, $intnumber, $intname, $intdesc, $intadmin, $intmon, $intcl,
	    $ip_id, $ip_addr, $ip_version, $subnet, $ip_mon, $name, $zone,
	    $srv_id, $srv_name, $srv_mon, $srv_cl,
	    $peeraddr, $peermon, $peercl) = @$row;
	my $hostname = ($name eq '@')? $zone : $name.'.'.$zone;
	$device_info{$devid}{target_id}    = $target_id;
	$device_info{$devid}{hostname}     = $hostname;
	$device_info{$devid}{community}    = $community;
	$device_info{$devid}{snmp_managed} = $dev_snmp;
	$device_info{$devid}{down_from}    = $down_from;
	$device_info{$devid}{down_until}   = $down_until;
	$device_info{$devid}{usedby_entity_name}  = $entity_name  if defined $entity_name;
	$device_info{$devid}{usedby_entity_alias} = $entity_alias if defined $entity_alias;
	$device_info{$devid}{site_name}    = $site_name    if defined $site_name;
	$device_info{$devid}{site_number}  = $site_number  if defined $site_number;
	$device_info{$devid}{site_alias}   = $site_alias   if defined $site_alias;
	$device_info{$devid}{contactlist}{$clid} = 1 if defined $clid;
	$device_info{$devid}{peering}{$peeraddr}{monitored}   = $peermon if defined $peeraddr;
	$device_info{$devid}{peering}{$peeraddr}{contactlist} = $peercl  if defined $peeraddr;
	$device_info{$devid}{interface}{$intid}{number}       = $intnumber;
	$device_info{$devid}{interface}{$intid}{name}         = $intname;
	$device_info{$devid}{interface}{$intid}{description}  = $intdesc;
	$device_info{$devid}{interface}{$intid}{admin}        = $intadmin;
	$device_info{$devid}{interface}{$intid}{monitored}    = $intmon;
	$device_info{$devid}{interface}{$intid}{contactlist}  = $intcl;
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
    
    return $self->cache('exporter_device_info', \%device_info);
}

########################################################################

=head2 get_device_main_ip 

  Arguments:
    device id
  Returns:
    IP address string
  Examples:
    my $ip = Netdot::Exporter->get_device_main_ip($devid);

=cut

sub get_device_main_ip {
    my ($self, $devid) = @_;

    $self->throw_fatal("Missing required arguments")
	unless $devid;

    my $device_info = $self->get_device_info();
    return unless exists $device_info->{$devid};

    my $ip;
    if ( $device_info->{$devid}->{ipaddr} && $device_info->{$devid}->{ipversion} ){
	$ip = Ipblock->int2ip($device_info->{$devid}->{ipaddr}, $device_info->{$devid}->{ipversion});
    }elsif ( my @ips = Netdot->dns->resolve_name($device_info->{$devid}->{hostname}, {v4_only=>1}) ){
	# Not sure how management tools will handle v6 addresses, so let's do v4 only for now
	$ip = $ips[0];
    }elsif ( !$ip ){
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
