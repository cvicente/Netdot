#!/usr/local/bin/perl

use lib "/home/netdot/public_html/lib";
use strict;
use Socket;
use Netdot::DBI;
use Netdot::Netviewer;
use Data::Dumper;

my $DEBUG = 0;
my %ifnames = ( physaddr => "ifPhysAddress",
		ifindex => "instance",
		iftype => "ifType",
		ifalias => "descr",
		ifspeed => "ifSpeed",
		ifadminstatus => "ifAdminStatus" );
my $usage = 
"usage: $0 [-h|-v]
       -h  print help (this message)
       -v  be verbose \n";

if( @ARGV ) {
  if( $ARGV[0] =~ /^-h$/o || $ARGV[0] =~ /^--help$/o ) {
    print $usage; 
    exit;
  } elsif( $ARGV[0] eq "-v" ) {
    $DEBUG = 1;
  } else {
    die $usage;
  }
}

my $nv = Netdot::Netviewer->new( foreground => 0 );
my @nodes = Node->retrieve_all();

print "Fetching current list of nodes....\n" if( $DEBUG );
foreach my $node ( @nodes ) {
  my %ifs;
  print "Checking node ", $node->name, " \n" if( $DEBUG );
  map { $ifs{ $_->id } = 1 } Node->interfaces();
  $nv->build_config( "device", $node->name );
  ################################################
  # get information from the device
  if( my( %dev ) = $nv->get_device( "device", $node->name ) ) {
    print "Have node ", $node->name, " information\n" if( $DEBUG );
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
	print "Interface node ", $node->name, ":$newif exists; updating\n"
	  if( $DEBUG );
	update( object => \$if, state => \%iftmp ); 
	delete( $ifs{ $if->id } );
      } else {
	$iftmp{managed} = 0;
	print "Interface node ", $node->name, ":$newif doesn't exist; ",
	  "inserting\n" if( $DEBUG );
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
	    print "Subnet $net exists \n" if( $DEBUG );
	    ; # do nothing
	  } else {
	    my %tmp;
	    $tmp{address} = $net;
	    $tmp{entity} = 0;
	    print "Subnet $net doesn't exist; inserting\n" if( $DEBUG );
	    $subnet = insert( object => "Subnet", state => \%tmp );
	  }
	  $iptmp{interface} = $if->id;
	  $iptmp{subnet} = $subnet->id;
	  $iptmp{address} = $newip;
	  $iptmp{mask} = $dev{interface}{$newif}{ipAdEntIfIndex}{$newip};
	  ########################################
	  # does this ip already exist in the DB?
	  if( $ip = (Ip->search( address => $newip ))[0] ) {
	    print "Interface $newif IP $newip exists; updating\n" if($DEBUG);
	    update( object => \$ip, state => \%iptmp );
	  } else {
	    print "Interface $newif IP $newip doesn't exist; inserting\n" 
	      if($DEBUG);
	    $ip = insert( object => "Ip", state => \%iptmp );
	  }
	} # for
      }
    }
    ##############################################
    # remove each interface that no longer exists
    foreach my $nonif ( keys %ifs ) {
      print "Node ", $node->name, " Interface ifIndex $nonif ",
	"doesn't exist; removing\n" if( $DEBUG );
      remove( object => "Interface", id => $nonif );
    }
  } else {
    print "Unable to access node ", $node->name, "\n" if( $DEBUG );
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
      eval { $obj->set( $col, $state{$col} ); }
	or die "Unable to set $col to $state{$col}: $@ \n";
    }
  }
  if( $change ) {
    eval { $obj->update; } 
      or die "Unable to update: $@\n";
  }
}


######################################################################
sub insert {
  my( %argv ) = @_;
  my($obj) = $argv{object};
  my(%state) = %{ $argv{state} };
  my($ret);
  eval { $ret = $obj->create( \%state ); }
    or die "Unable to insert into $obj: $@\n";
  return $ret;
}


######################################################################
sub remove {
  my(%argv) = @_;
  my($obj) = $argv{object};
  my($id) = $argv{id};
  my $o = $obj->retrieve( $id );
  eval { $o->delete; }
    or die "Unable to delete: $@ \n";
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
#  Revision 1.6  2003/07/11 21:15:22  netdot
#  looks near final; added code to delete stuff
#
#  Revision 1.5  2003/07/11 15:28:11  netdot
#  added series of eval statements
#
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


