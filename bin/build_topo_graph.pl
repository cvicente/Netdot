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
my %self = ( root=>$nms, vlans=>0, names=>0, depth=>99999 );

my $USAGE = <<EOF;
 
 Build Network Topology Graph

 Usage: $0 [-r|--root <device>] [-d|--depth <integer>] 
           [-v|--vlans] [-n|names] [-F|--format] [-d|--direction]
           -f|--filename <name>

    Argument Detail: 
    -r, --root <hostname>                Root host (default: $self{root})
    -d, --depth <integer>                Graph depth. How many hops away from root? (default: $self{depth})
    -f, --filename <name>                File name for image
    -F, --format <format>                Graphic file format (text|ps|hpgl|gd|gd2|gif|jpeg|png|svg)
    -d, --direction <up_down|left_right> Direction in which graph will be rendered
    -v, --vlans                          Show vlans with lines in different colors
    -n, --names                          Show interface names instead of index numbers

EOF
    
# handle cmdline args
my $result = GetOptions( "r|root=s"      => \$self{root},
			 "d|depth=s"     => \$self{depth},
			 "f|filename=s"  => \$self{filename},
			 "F|format=s"    => \$self{format},
			 "d|direction=s" => \$self{direction},
			 "v|vlans"       => \$self{vlans},
			 "n|names"       => \$self{names},
			 "h|help"        => \$self{help},
    );

if ( !$result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $self{help} ) {
    print $USAGE;
    exit;
}

my $ui = Netdot::UI->new();

my $device_obj  = Device->search(name=>$self{root})->first
    || die "Cannot find root device: $self{root}";

my $id    = $device_obj->id;
my $start = time;
$ui->build_device_topology_graph(id         => $id, 
				 depth      => $self{depth}, 
				 show_vlans => $self{vlans}, 
				 show_names => $self{names},
				 filename   => $self{filename},
				 format     => $self{format},
                                 direction  => $self{direction},
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


