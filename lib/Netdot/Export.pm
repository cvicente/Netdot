package Netdot::Export;
#
# Common routines for scripts that export netdot data
#
# 
use strict;
use Socket;
use Exporter ;
use Data::Dumper;

use vars qw ( @EXPORT @ISA @EXPORT_OK);

@ISA       = qw( Exporter ) ;
@EXPORT    = qw( get_dependencies get_device_ips );
@EXPORT_OK = qw();

my $DEBUG = 0;
my ($dbh, $graph, $device_ips);

########################################################################
sub get_dbh {
    unless ( $dbh ){
        $dbh = Netdot::Model->db_Main();	
    }
    return $dbh;
}

########################################################################
sub get_graph {
    unless ( $graph ) {
        $graph = {};
	$dbh = &get_dbh();
        my $links = $dbh->selectall_arrayref("
                SELECT d1.id, d2.id 
                FROM device d1, device d2, interface i1, interface i2
                WHERE i1.device = d1.id AND i2.device = d2.id
                    AND i2.neighbor = i1.id AND i1.neighbor = i2.id
            ");
        foreach my $link (@$links) {
            my ($fr, $to) = @$link;
            $graph->{$fr}{$to}  = 1;
            $graph->{$to}{$fr}  = 1;
        }
    }
    return $graph;
}

########################################################################
sub get_device_ips {
    unless ( $device_ips ){
	$dbh = &get_dbh();
	$device_ips = $dbh->selectall_arrayref("
                SELECT   device.id, ipblock.id, ipblock.address, interface.monitored, device.monitored
                FROM     device, interface, ipblock
                WHERE    ipblock.interface=interface.id
                  AND    interface.device=device.id
                ORDER BY ipblock.address
         ");
    }
    return $device_ips;
}
########################################################################
# Recursively look for valid parents
# If the parent(s) don't have ip addresses or are not managed,
# try to keep the tree connected anyways
# Arguments: 
#   Hash ref of host ips
# Returns:
#   Hash ref of arrayrefs of parent ips
########################################################################
sub get_dependencies{
    my ($monitor, $ips) = @_;
    defined $monitor || die "Need to pass monitoring device";
    defined $ips     || die "Need to pass IPs";

    my $graph      = &get_graph();
    my $device_ips = &get_device_ips();

    my (%device2ips, %ip_monitored);
    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $ipaddr, $int_monitored, $dev_monitored) = @$row;
	push @{$device2ips{$deviceid}}, $ipid;
	$ip_monitored{$ipid} = ($int_monitored && $dev_monitored) ? 1 : 0;
    }

    sub dfs {
        my $s         = shift || die "No source vertex";
        my $t         = shift || die "No target vertex";
        my $graph     = shift || die "No graph";
        my $forbidden = shift || die "No forbidden vertex";
        my $seen      = shift || {};

        $seen->{$s} = 1;
        if ($s == $t) { # Base case 
            return 1; 
        } else { # Recursive case
            foreach my $n ( keys %{$graph->{$s}} ) {
                next if exists $seen->{$n};
                next if $forbidden == $n;

                if (dfs($n, $t, $graph, $forbidden, $seen)) {
                    return 1;
                }
            }

            return 0;
        }
    }

    # I am unsure where this code wants to live.  For this code to get doing, it
    # needs a hashref, called $ips, which maps devices to a listref of the IP
    # addresses of that device.  If none of the ip's of that device are monitored,
    # then the hashref should be empty.  It also needs a hashref of hashrefs called
    # "graph", where, if there is a network link between device A and B, then it is
    # true that $graph->{A}{B} = $graph->{B}{A} = 1

    my %parents = ();
    foreach my $d (keys %$graph) {
	$parents{$d} = [];
	foreach my $neighbor ( keys %{$graph->{$d}} ) {
	    if (dfs($neighbor, $monitor, $graph, $d)) {
		push @{$parents{$d}}, $neighbor;
	    }
	}
    }

    my $ipdeps = {};
    foreach my $device ( keys %parents ){
	foreach my $ipid ( @{$device2ips{$device}} ){
	    foreach my $parent ( @{$parents{$device}} ){
		foreach my $ipid2 ( @{$device2ips{$parent}} ){
		   $ipdeps->{$ipid}{$ipid2} = 1 if $ip_monitored{$ipid2};
		}
	    }
	}
    }
    
    foreach my $ipid ( keys %$ipdeps ){
	my @list = keys %{$ipdeps->{$ipid}};
	$ipdeps->{$ipid} = \@list;
    }
    return $ipdeps;
}



1;
