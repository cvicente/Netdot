#!<<Make:PERL>>
#
# build_topo_graph.pl - Command-line tool to build the topology graph
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::UI;
use Getopt::Long qw(:config no_ignore_case bundling);

# Default parameters
my $nms = Netdot->config->get('NMS_DEVICE');
my %self = ( root=>$nms, start=>$nms, vlans=>0, names=>0, depth=>99999, minlen=>undef );

my $USAGE = <<EOF;
 
 Build Network Topology Graph

 Usage: $0 [-r|--root <device>] [-d|--depth <integer>] 
           [-u|--depth-up <integer>] [-o|--depth-down <integer>]
           [-V|--specificvlan <vlanid>] [-v|--vlans] [-n|names] 
           [-F|--format] [-D|--direction <up_down|left_right>]
           [-m|--minlen <integer>]
           -f|--filename <name>

    Argument Detail: 
    -r, --root <hostname>                Root host (default: $self{root})
    -s, --start <hostname>               Start host (default: $self{root})
    -d, --depth <integer>                Graph depth. How many hops away from root? (default: $self{depth})
    -u, --depth_up <integer>              Graph depth going up from root
    -o, --depth_down <integer>            Graph depth going down from root
    -f, --filename <name>                File name for image
    -F, --format <format>                Graphic file format (text|ps|hpgl|gd|gd2|gif|jpeg|png|svg)
    -D, --direction <up_down|left_right> Direction in which graph will be rendered
    -V, --specificvlan <vlanid>          The vlan ID of the specific vlan to display
    -v, --vlans                          Show vlans with lines in different colors
    -n, --names                          Show interface names instead of index numbers
    -m, --minlen <integer>               Minimum length of edges

EOF
    
# handle cmdline args
my $result = GetOptions( "r|root=s"         => \$self{root},
			 "s|start=s"        => \$self{start},
			 "d|depth=s"        => \$self{depth},
			 "u|depth_up=s"     => \$self{depth_up},
			 "o|depth_down=s"   => \$self{depth_down},
			 "f|filename=s"     => \$self{filename},
			 "F|format=s"       => \$self{format},
			 "D|direction=s"    => \$self{direction},
			 "V|specificvlan=s" => \$self{specific},
			 "v|vlans"          => \$self{vlans},
			 "n|names"          => \$self{names},
			 "m|minlen=s"       => \$self{minlen},
			 "h|help"           => \$self{help},
    );

if ( !$result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $self{help} ) {
    print $USAGE;
    exit;
}

$self{vlans} = 1 if $self{specific};

my $ui = Netdot::UI->new();

my $device_obj = Device->search(name=>$self{root})->first
    || die "Cannot find root device: $self{root}";
my $start_obj = Device->search(name=>$self{start})->first
    || die "Cannot find start device: $self{start}";

my $rid   = $device_obj->id;
my $sid   = $start_obj->id;
my $start = time;

$ui->build_device_topology_graph(
    id            => $sid, 
    root          => $rid,
    depth         => $self{depth}, 
    depth_up      => $self{depth_up}, 
    depth_down    => $self{depth_down}, 
    show_vlans    => $self{vlans}, 
    specific_vlan => $self{specific}, 
    show_names    => $self{names},
    minlen        => $self{minlen},
    filename      => $self{filename},
    format        => $self{format},
    direction     => $self{direction},
    );

printf("$0 Done building %s. Runtime: %s\n", $self{filename}, Netdot->sec2dhms(time-$start));

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

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


