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
"usage: $0 -n|--node <host> -h|--help -v|--verbose

    -n  <host>: update given node only.  Skipping this will update all nodes in DB.
    -h        : print help (this message)
    -v        : be verbose \n";

my ($node, $host, @nodes);

# handle cmdline args
if ( scalar @ARGV > 0 ) {
    while (my $arg = shift @ARGV){
        if ( $arg =~ /^-n$/io || $arg =~ /^--node$/io) {
            $host = shift @ARGV;
        }elsif ( $arg =~ /^-h$/io || $arg =~ /^--help$/io ) {
            print $usage ;
            exit;
        }elsif ( $arg =~ /^-v$/io || $arg =~ /^--verbose$/) {
            $DEBUG = 1 ;
        }else {
            warn "Invalid argument: $arg.\n" ;
            die $usage ;
        }
    }
}
    
my $nv = Netdot::Netviewer->new( foreground => '0', loglevel => 'LOG_ERR' );

if (defined $host){
    if ($node = (Node->search(name => $host))[0]){
	push @nodes, $node;
    }else{
	die "$host not found on db\n";
    }
}else{
    print "Fetching current list of nodes....\n" if( $DEBUG );
    @nodes = Node->retrieve_all();
}

my @ifrsv = NvIfReserved->retrieve_all();

foreach my $node ( @nodes ) {
  my %ifs;
  print "Checking node ", $node->name, " \n" if( $DEBUG );
  map { $ifs{ $_->id } = 1 } $node->interfaces();
  my $comstr = $node->community || Netviewer->community;
  $nv->build_config( "device", $node->name, $comstr );
  ################################################
  # get information from the device
  if( my( %dev ) = $nv->get_device( "device", $node->name ) ) {
    print "Have node ", $node->name, " information\n" if( $DEBUG );
    if( $dev{sysUpTime} < 0 ) {
      printf "Node %s has sysUpTime value of %d; skipping\n", 
	$node->name, $dev{sysUpTime} if( $DEBUG );
      next;
    }
    my %ntmp;
    $ntmp{sysdescription} = $dev{sysDescr};
    $ntmp{physaddr} = $dev{dot1dBaseBridgeAddress};
    $ntmp{physaddr} =~ s/^0x//; 
    unless( update( object => $node, state => \%ntmp ) ) {
      next;
    }
    ##############################################
    # for each interface just discovered...
    foreach my $newif ( keys %{ $dev{interface} } ) {
      ############################################
      # check whether should skip IF
      my $skip = 0;
      foreach my $rsv ( @ifrsv ) {
        my $n = $rsv->name;
        $skip = 1 if( $newif =~ /$n/ );
      }
      next if( $skip );
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
      $iftmp{physaddr} =~ s/^0x//;
      ############################################
      # does this ifIndex already exist in the DB?
      if( $if = (Interface->search( node => $node->id, ifindex => $dev{interface}{$newif}{instance}))[0] ) {
	print "Interface node ", $node->name, ":$newif exists; updating\n"
	  if( $DEBUG );
	delete( $ifs{ $if->id } );
	unless( update( object => $if, state => \%iftmp ) ) {
	  next;
	}
      } else {
	$iftmp{managed} = 0;
	print "Interface node ", $node->name, ":$newif doesn't exist; ",
	  "inserting\n" if( $DEBUG );
	unless( $if = insert( object => "Interface", state => \%iftmp ) ) {
	  next;
	}
      }
      if( exists( $dev{interface}{$newif}{ipAdEntIfIndex} ) ) {
	foreach my $newip( keys %{ $dev{interface}{$newif}{ipAdEntIfIndex}}){
	  ## ignore loopback IPs
	  next if ($newip =~ /127\.0\.0\.1/);
	  my( $ip, $subnet );
	  my $net = calc_subnet
	    ( $newip, $dev{interface}{$newif}{ipAdEntIfIndex}{$newip} );
	  ########################################
	  # does this subnet already exist?
	  if( $subnet = (Subnet->search( address => $net ) )[0] ) {
	    print "Subnet $net exists \n" if( $DEBUG );
	    $iptmp{subnet} = $subnet->id;
	  } else {
	    my %tmp;
	    $tmp{address} = $net;
	    $tmp{entity} = 0;
	    $iptmp{subnet} = 0;
	    #print "Subnet $net doesn't exist; inserting\n" if( $DEBUG );
	    #unless( $subnet = insert( object => "Subnet", state => \%tmp ) ){
	    #  next;
	    #}
	  }
	  $iptmp{interface} = $if->id;
	  $iptmp{address} = $newip;
	  $iptmp{mask} = $dev{interface}{$newif}{ipAdEntIfIndex}{$newip};
	  ########################################
	  # does this ip already exist in the DB?
	  if( $ip = (Ip->search( address => $newip ))[0] ) {
	    print "Interface $newif IP $newip exists; updating\n" if($DEBUG);
	    unless( update( object => $ip, state => \%iptmp ) ) {
	      next;
	    }
	  } else {
	    print "Interface $newif IP $newip doesn't exist; inserting\n" if($DEBUG);
	    unless( $ip = insert( object => "Ip", state => \%iptmp ) ){
	      next;
	    }
	  }
	} # for
      }
    }
    ##############################################
    # remove each interface that no longer exists
    foreach my $nonif ( keys %ifs ) {

      # hubs are somewhat tricky.  Don't delete their ports.
      my $intobj = Interface->retrieve($nonif);
      next if ($intobj->node->type->name eq "Hub");
  
      print "Node ", $node->name, " Interface ifIndex $intobj->ifindex ",
	"doesn't exist; removing\n" if( $DEBUG );
      unless( remove( object => "Interface", id => $nonif ) ) {
	next;
      }
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
  foreach my $col ( keys %state ) {
    if( $state{$col} ne $obj->$col ) {
      $change = 1;
      eval { $obj->set( $col, $state{$col} ); };
      if( $@ ) {
	warn "Unable to set $col to $state{$col}: $@ \n";
	return 0;
      }
    }
  }
  if( $change ) {
    eval { $obj->update; };
    if( $@ ) {
      warn "Unable to update: $@\n";
      return 0;
    }
  }
  return 1;
}


######################################################################
sub insert {
  my( %argv ) = @_;
  my($obj) = $argv{object};
  my(%state) = %{ $argv{state} };
  my($ret);
  eval { $ret = $obj->create( \%state ); };
  if( $@ ) {
    warn "Unable to insert into $obj: $@\n";
    return 0;
  } else {
    return $ret;
  }
}


######################################################################
sub remove {
  my(%argv) = @_;
  my($obj) = $argv{object};
  my($id) = $argv{id};
  my $o = $obj->retrieve( $id );
  eval { $o->delete; };
  if( $@ ) {
    warn "Unable to delete: $@ \n";
    return 0;
  } else {
    return 1;
  }
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
#  Revision 1.11  2003/07/16 22:38:54  netdot
#  disabling chunk of subnet code
#
#  Revision 1.10  2003/07/15 19:11:50  netdot
#  fix for skip interfaces and community string
#
#  Revision 1.9  2003/07/15 16:26:09  netdot
#  series of fixes to make consistent with node.html and more graceful
#  with errors.
#
#  Revision 1.8  2003/07/12 21:07:56  netdot
#  fixed interfaces call
#
#  Revision 1.7  2003/07/11 21:20:20  netdot
#  update general node info
#
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


