#!/usr/local/bin/perl

use lib "/home/netdot/public_html/lib";
use strict;
use Socket;
use Netdot::DBI;
use Netdot::Netviewer;
use Data::Dumper;

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
  my %ifs;
  print "!!!!!!!! node ", $node->name, "\n" if( $DEBUG );
  map { $ifs{ $_->id } = 1 } Node->interfaces();
  $nv->build_config( "device", $node->name );
  print "have config....\n";
  ################################################
  # get information from the device
  if( my( %dev ) = $nv->get_device( "device", $node->name ) ) {
    ##############################################
    # for each interface just discovered...
    foreach my $newif ( keys %{ $dev{interface} } ) {
      ############################################
      # set up IF state data
      my( %iftmp, %iptmp, $if );
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
      if( $if = (Interface->search( node => $node->id, ifindex => $dev{interface}{$newif}{instance}))[0] ) {
	update( object => \$if, state => \%iftmp ); 
	delete( $ifs{ $if->id } );
      } else {
	$iftmp{managed} = 0;
	$if = insert( object => "Interface", state => \%iftmp );
      }
      if( exists( $dev{interface}{$newif}{ipAdEntIfIndex} ) ) {
	foreach my $newip( keys %{ $dev{interface}{$newif}{ipAdEntIfIndex}}){
	  my( $ip, $subnet );
	  my $net = calc_subnet
	    ( $newip, $dev{interface}{$newif}{ipAdEntIfIndex}{$newip} );
	  ########################################
	  # does this subnet already exist?
	  if( $subnet = (Subnet->search( address => $net ) )[0] ) {
	    ; # do nothing
	  } else {
	    my %tmp;
	    $tmp{address} = $net;
	    $subnet = insert( object => "Subnet", state => \%tmp );
	  }
	  $iptmp{interface} = $if->id;
	  $iptmp{subnet} = $subnet->id;
	  $iptmp{address} = $newip;
	  $iptmp{mask} = $dev{interface}{$newif}{ipAdEntIfIndex}{$newip};
	  ########################################
	  # does this ip already exist in the DB?
	  if( $ip = (Ip->search( address => $newip ))[0] ) {
	    print "have ip $ip; would go to update\n";
	    update( object => \$ip, state => \%iptmp );
	  } else {
	    $ip = insert( object => "Ip", state => \%iptmp );
	  }
	} # for
      }
    }
    ##############################################
    # remove each interface that no longer exists
    foreach my $nonif ( keys %ifs ) {
      print "id $nonif \n";
    }
  } else {
    warn "Unable to access node ", $node->name, "\n";
  }
}


######################################################################
sub update {
  my( %argv ) = @_;
  my($obj) = $argv{object};
  my(%state) = %{ $argv{state} };
  my $change = 0;
  return;
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
  my(%state) = %{ $argv{state} };
  return $obj->create( \%state );
}


######################################################################
sub remove {
  my(%argv) = @_;
  my($obj) = $argv{object};
  $obj->delete;
}


######################################################################
sub calc_subnet {
  my( $ip, $mask ) = @_;
  my $decip = unpack('N', (pack ('C*', split (/\./, $ip))));
  my $decmask = unpack('N', (pack ('C*', split (/\./, $mask))));
  return inet_ntoa(pack('N',$decip & $decmask));
}

######################################################################
#  $Log: updatenodes.pl,v $
#  Revision 1.4  2003/07/11 00:03:23  netdot
#  more work fleshing out algorithm
#
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


