#!/usr/bin/perl -w
#
#
use lib "/usr/local/netdot/lib";
use Netdot::Model;
use NetAddr::IP;
use strict;

my $strip_domain = 'uoregon.edu';
my $group_source = 'used_by';
my %templates = ('None'                       => 0,
		 'Generic SNMP-enabled Host'  => 1,
		 'ucd/net SNMP Host'          => 3,
		 'Karlnet Wireless Bridge'    => 4,
		 'Cisco Router'               => 5,
		 'Netware 4/5 Server'         => 6,
		 'Windows 2000/XP Host'       => 7,
		 'Local Linux Machine'        => 8,
		 );


my $dbh = Netdot::Model->db_Main();

my $query = $dbh->selectall_arrayref("
                SELECT     rr.name, zone.mname, ipblock.address, site.name, p.name, pt.name, 
                           d.id, d.snmp_managed, d.snmp_polling, d.community, d.snmp_version, e.name, m.name
                FROM      rr, zone, producttype pt, device d
                LEFT JOIN (site) ON (d.site=site.id)
                LEFT JOIN (ipblock) ON (d.snmp_target=ipblock.id)
                LEFT JOIN (entity e) ON (d.used_by=e.id),
                           product p
                LEFT JOIN (entity m) ON (p.manufacturer=m.id)
                WHERE      d.name=rr.id
                  AND      rr.zone=zone.id
                  AND      d.product=p.id
                  AND      p.type=pt.id
                ORDER BY   rr.name
         ");

foreach my $row ( @$query ){
    my ($name, $domain, $iaddress, $site, $product, $ptype, 
	$device_id, $managed, $enabled, $community, $version, $used_by, $mfg) = @$row;

    next unless $managed;
    my $host = $name . "." . $domain;
    my $address;
    if ( $iaddress ){
	$address = NetAddr::IP->new($iaddress)->addr();
    }
    $address ||= $host;
    $host =~ s/\.$strip_domain//;
    my $group;
    if ( $group_source eq 'used_by' ){
	$group = $used_by;
    }elsif ( $group_source eq 'site' ){
	$group = $site;
    }
    $group       ||= 'unknown';
    $group        =~ s/\s+/_/g;
    $mfg         ||= 'unknown';
    $ptype       ||= 'unknown';
    $version     ||= 2;
    $community   ||= "public";
    my $disabled = ($enabled)? 0 : 1;

    # Try to assign a template based on the device type
    my $template_name = 'Generic SNMP-enabled Host';
    if ( $ptype eq 'Server' ){
	if ( $product =~ /Net-SNMP/ ){
	    $template_name = 'ucd/net SNMP Host';
	}elsif ( $product =~ /Windows/ ){
	    $template_name = 'Windows 2000/XP Host';
	}
    }elsif ( $ptype eq 'Router' ){
	if ( $mfg =~ /Cisco/ ){
	    $template_name = 'Cisco Router';
	}
    }

    my $template = $templates{$template_name};

    my @fields = ($device_id, $host, $address, $template, $group, $disabled, $version, $community);

    print join ";", @fields;
    print "\n";
}
