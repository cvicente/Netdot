#!/usr/local/bin/perl

use lib "/home/netdot/public_html/lib";
use strict;
use Netdot::DBI;
use Netdot::Netviewer;

my $DEBUG = 1;

my $nv = Netdot::Netviewer->new( foreground => 1 );
my @nodes = Node->retrieve_all();
foreach my $node ( @nodes ) {
  print "node ", $node->name, "\n" if( $DEBUG );
  my @ifs = Node->interfaces();
  $, = " " if( $DEBUG );
  print @ifs if( $DEBUG );
  $nv->build_config( "device", $node->name );
  ################################################
  # get information from the device
  if( my( %node ) = $nv->get_device( "device", $args{node} ) ) {
    ##############################################
    # for each interface just discovered...
    foreach my $newif ( keys %{ $node{interface} } ) {
      ############################################
      # does this ifIndex already exist in the DB?
      if( my $if = (Interface->search( ifindex => $node{interface}{$newif}{ifIndex}))[0] ) {
	;
      } else {
	;
      }
    }
    ##############################################
    # remove each interface that no longer exists
    foreach my $nullif ( @ifs ) {
      ;
    }
  } else {
    warn "Unable to access node ", $node->name, "\n";
  }
}


######################################################################
#  $Log: updatenodes.pl,v $
#  Revision 1.2  2003/07/08 23:22:22  netdot
#  *** empty log message ***
#

__DATA__

  for all nodes n
      get list A of interfaces 
      discover interfaces (list B) on node n
      for interfaces i in list B
          if i.ifIndex exists
             update relevant entries
             remove i from list A
          else 
             add i to Interfaces
      end
      for interfaces i in list A
          remove from Interfaces
      end
  end
