#!/usr/bin/perl -w

use lib '/usr/local/netdot/lib';
use Netdot::Model;
use strict;
use Getopt::Long qw(:config no_ignore_case bundling);

my $USAGE = <<EOF;
 usage: $0 -n <prefix> [-s ]
    -n, --network                        Network prefix
    -s, --size                           Maximum block size to partition space into
    -h, --help                           Print help (this message)

EOF
    
# handle cmdline args
my %self;
my $result = GetOptions( "n|network=s" => \$self{prefix},
                         "s|size=s"    => \$self{size},
			 "h|help"      => \$self{help},
);

if ( ! $result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $self{help} ) {
    print $USAGE;
    exit;
}
die "You need to provide a network prefix\n" unless $self{prefix};

my $network = Ipblock->search(address=>$self{prefix})->first || 
    die "Cannot find ".$self{prefix}." in the database\n";

foreach my $block ( sort $network->free_space($self{size}) ){
    print $block, "\n";
}
