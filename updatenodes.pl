#!/usr/local/bin/perl

use lib "/home/netdot/public_html/lib";
use strict;
use Netdot::DBI;
use Netdot::Netviewer;

my $DEBUG = 1;
my %ifnames = ( physaddr => "ifPhysAddress",
		ifindex => "instance",
		iftype => "ifType",
		ifalias => "descr",
		ifspeed => "ifSpeed",
		ifadminstatus => "ifAdminStatus" );

my $nv = Netdot::Netviewer->new( foreground => 0 );
my @nodes = Node->retrieve_all();
foreach my $node ( @nodes ) {
  print "!!!!!!!! node ", $node->name, "\n" if( $DEBUG );
  my @ifs = Node->interfaces();
  $, = " " if( $DEBUG );
  print @ifs if( $DEBUG );
  $nv->build_config( "device", $node->name );
  ################################################
  # get information from the device
  if( my( %dev ) = $nv->get_device( "device", $node->name ) ) {
    ##############################################
    # for each interface just discovered...
    foreach my $newif ( keys %{ $dev{interface} } ) {
      ############################################
      # set up IF state data
      my( %iftmp, %iptmp );
      $iftmp{node} = $node->id;
      $iftmp{ifdescr} = $newif;
      foreach my $dbname ( keys %ifnames ) {
	if( $ifnames{$dbname} eq "descr" ) {
	  if( $dev{interface}{$newif}{$ifnames{$dbname}} ne "-" ) {
	    $iftmp{$dbname} = $dev{interface}{$newif}{$ifnames{$dbname}};
	  }
	} else {
	  $iftmp{$dbname} = $dev{interface}{$newif}{$ifnames{$dbname}};
	}
      }
      ############################################
      # does this ifIndex already exist in the DB?
      if( my $if = (Interface->search( ifindex => $dev{interface}{$newif}{ifIndex}))[0] ) {
	update( obj => \$if, state => \%iftmp );
      } else {
	insert( obj => "Interface", state => \%iptmp );
      }
      if( exists( $dev{interface}{$newif}{ipAdEntIfIndex} ) ) {
	foreach my $newip( keys %{ $dev{interface}{$newif}{ipAdEntIfIndex}}){
	  $iptmp{interface} = $if->id;
	  $iptmp{address} = $newip;
	  $iptmp{mask} = $dev{interface}{$newif}{ipAdEntIfIndex}{$newip};
	  ########################################
	  # does this ip already exist in the DB?
	  if( my $ip = (Ip->search( address => $newip ))[0] ) {
	    update( obj => \$ip, state => \%iptmp );
	  } else {
	    insert( obj => "Ip", state => \%iptmp );
	}
      }
    }
    ##############################################
    # remove each interface that no longer exists
    foreach my $nonif ( @ifs ) {
      ;
    }
  } else {
    warn "Unable to access node ", $node->name, "\n";
  }
}


######################################################################
sub update {
  my( %argv ) = @_;
  my($obj) = $argv{object};
  my($state) = %{ $argv{state} };
  my $change = 0;
  foreach my $col ( keys %state ) {
    if( $state{$col} ne $obj->$col ) {
      $change = 1;
      $obj->set( $col, $state{$col} );
    }
  }
  if( $change ) {
    $obj->update;
  }
}


######################################################################
sub insert {
  my( %argv ) = @_;
  my($obj) = $argv{object};
  my($state) = %{ $argv{state} };
  $obj->create( \%state );
}


######################################################################
sub remove {
  ;
}

######################################################################
#  $Log: updatenodes.pl,v $
#  Revision 1.3  2003/07/10 20:54:10  netdot
#  more work to complete this.  still fleshing algorithm out.
#
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
