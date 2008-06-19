#!/usr/bin/perl
#
# Common routines for scripts that export netdot data into text files
#
# 


package Netdot::Export;

use strict;
use Socket;
use Exporter ;
use Data::Dumper;

use vars qw ( @EXPORT @ISA @EXPORT_OK);

@ISA       = qw( Exporter ) ;
@EXPORT    = qw( get_dependencies resolve );
@EXPORT_OK = qw();

my $DEBUG = 0;


my $graph;
sub get_graph {
    if (!$graph) {
        $graph = {};
        my $dbh = Netdot::Model->db_Main();
        my $links = $dbh->selectall_arrayref("
                SELECT d1.id, d2.id 
                FROM device d1, device d2, interface i1, interface i2
                WHERE i1.device = d1.id AND i2.device = d2.id
                    AND i2.neighbor = i1.id AND i1.neighbor = i2.id
            ");
        foreach my $link (@$links) {
            my ($fr, $to) = @$link;
            $graph->{$fr} = {} unless exists $graph->{$fr};
            $graph->{$to} = {} unless exists $graph->{$to};
            $graph->{$fr}{$to}  = 1;
            $graph->{$to}{$fr}  = 1;
        }
    }

    return $graph;
}

########################################################################
# Recursively look for valid parents
# If the parent(s) don't have ip addresses or are not managed,
# try to keep the tree connected anyways
# Arguments: 
#   interface => scalar: Interface table object
# Returns:
#   array of parent ips
########################################################################
sub get_dependencies{
    my (%args) = @_;
    my $intobj = $args{interface} || die "Need to pass interface object";
    my @parents;
    my $graph = get_graph();

    sub dfs {
        my $s = shift || die "No source vertex";
        my $t = shift || die "No target vertex";
        my $graph = shift || die "No graph";
        my $forbidden = shift || die "No forbidden vertex";
        my $seen = shift || {};

        $seen{$s} = 1;
        if ($s == $t) { # Base case 
            return 1; 
        } else { # Recursive case
            for my $n (keys $graph->{$s}) {
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
    foreach my %neighbor (keys $graph->{$d}) {
        if (dfs($n, $monitor, $graph, $d)) {
            push @{$parents{$d}}, $n
        }
    }

}


sub resolve{
########################################################################
#   Resolve Ip address to name
#
# Arguments: 
#   ip address in dotted-decimal notation (128.223.x.x)
#   or name
# Return values:
#   name or ip address if successful, 0 if error
########################################################################
  
    my $par = shift @_;
    my $ipregex = '(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})';
    if ($par =~ /$ipregex/){
	my $name;
	unless ($name = gethostbyaddr(inet_aton($par), AF_INET)){
	    warn "Can't resolve  $par: $!\n";
	    return 0;
	}
	return $name;
    }else{
	my $ip;
	unless (inet_aton($par) && ($ip = inet_ntoa(inet_aton($par))) ){
	    warn "Can't resolve $par: $!\n";
	    return 0;
	}
	return $ip;
    }
}

1;
