#!/usr/local/bin/perl

use lib "/home/netdot/public_html/lib";
use strict;
use Netdot::DBI;
use Netdot::Netviewer;

my @nodes = Node->retrieve_all();
foreach my $node ( @nodes ) {
  print "node ", $node->name, "\n";
  my @ifs = Node->interfaces();
  $, = " ";
  print @ifs;
}
