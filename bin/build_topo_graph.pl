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
           [-v|--vlans] [-n|names] 
           -f|--filename <name>

    Argument Detail: 
    -r, --root <hostname>        Root host (default: $self{root})
    -d, --depth <integer>        Graph depth. How many hops away from root? (default: $self{depth})
    -f, --filename <name>        File name for image
    -v, --vlans                  Show vlans with lines in different colors
    -n, --names                  Show interface names instead of index numbers

EOF
    
# handle cmdline args
my $result = GetOptions( "r|root=s"      => \$self{root},
			 "d|depth=s"     => \$self{depth},
			 "f|filename=s"  => \$self{filename},
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
    );

printf("$0 Done building %s. Runtime: %s\n", $self{filename}, Netdot->sec2dhms(time-$start));
