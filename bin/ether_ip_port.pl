#!<<Make:PERL>>
#
# ether_ip_port.pl -- Export text files merging ethernet address, ip address
# and switch port location.  A single datestamped file
# containing a single output line for each ethernet address is the
# result.
#
# These exported text files allow us to keep longer history, since netdot's
# database has to be pruned of older records regularly to keep it functional
#
# Output syntax:
# <MAC address> <IP address 1>...<IP address N> <device1.ifIndex> [MAC count]... <deviceN.ifIndex> [MAC count]
#
# This should be run as a cron job, right after the forwarding tables and ARP caches are retrieved
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Model;
use Data::Dumper;
use NetAddr::IP;

my $DEBUG = 0;

my $USAGE = "
$0 <dir path>
  
  <dir path> -- Directory path where the files will be written.
 
";

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
$year += 1900; $mon += 1; $mday = sprintf("%02d", $mday);
my $DATE    = $year.$mon.$mday.$hour;
my $FILEDIR = $ARGV[0] or die $USAGE;
my $OUTFILE = "$FILEDIR/$DATE";

open(OUTFILE, ">$OUTFILE") or die "Cannot write to $OUTFILE: $!\n";

my $dbh = Netdot::Model->db_Main();

# Find the most recent poll
my $st = $dbh->prepare("
        SELECT  MAX(fwtable.tstamp)
        FROM    fwtable, device, interface
        WHERE   fwtable.device = device.id
            AND interface.device = device.id");
$st->execute();
my $last_tstamp = $st->fetchrow_array();

my $st2 = $dbh->prepare("
   SELECT p.address, i.number, rr.name
   FROM   physaddr p, interface i, rr, fwtable ft, fwtableentry fte, device d
   WHERE  fte.physaddr=p.id
      AND fte.fwtable=ft.id
      AND fte.interface=i.id
      AND i.device=d.id
      AND d.name=rr.id
      AND ft.tstamp=?;
");

$st2->execute($last_tstamp);
my $frows = $st2->fetchall_arrayref();

my (%macs, %ports);
foreach my $row (@$frows){
    my ($mac, $ifindex, $host) = @$row;
    $macs{$mac}{$host} = $ifindex;
    $ports{$host}{$ifindex}{$mac} = 1;
}

print "macs hash contains: ", Dumper(%macs), "\n" if $DEBUG;
print "ports hash contains:  ", Dumper(%ports), "\n" if $DEBUG;

my $st3 = $dbh->prepare("
   SELECT p.address, ip.address, i.number, rr.name
   FROM   physaddr p, interface i, arpcacheentry arpe, 
          arpcache arp, ipblock ip, device d, rr
   WHERE  arpe.physaddr=p.id 
      AND arpe.interface=i.id 
      AND arpe.ipaddr=ip.id 
      AND arpe.arpcache=arp.id 
      AND i.device=d.id
      AND d.name=rr.id
      AND arp.tstamp=?
");
$st3->execute($last_tstamp);
my $arows = $st3->fetchall_arrayref();

my %arp;
foreach my $row (@$arows){
    my ($mac, $ip, $ifindex, $host) = @$row;
    $arp{$mac}{$ip}{$host} = $ifindex;
}
print "arp hash contains: ", Dumper(%arp), "\n" if $DEBUG;



foreach my $mac ( keys %macs ){
    print OUTFILE "$mac";
    my @arp_ports;
    foreach my $decip ( keys %{$arp{$mac}} ){
	my $ip = NetAddr::IP->new($decip)->addr();
	print OUTFILE " $ip";
	foreach my $host ( keys %{$arp{$mac}{$decip}} ){
	    my $arp_port = "$host.$arp{$mac}{$decip}{$host}";
	    push @arp_ports, $arp_port;
	}
    }
    print OUTFILE " ", join(" ", @arp_ports) if @arp_ports;
    foreach my $host ( keys %{$macs{$mac}} ){
	my $ifindex = $macs{$mac}{$host};
	my $count = scalar(keys %{$ports{$host}{$ifindex}});
	print OUTFILE " $host.$ifindex [$count]";
    }
    print OUTFILE "\n";
}

close(OUTFILE);
