#!/usr/bin/perl

use lib "/usr/local/netdot/lib";
use Getopt::Long;
use strict;
use NetAddr::IP;
use Netdot::DBI;
use Netdot::GUI;
use Netdot::Netviewer;
use Data::Dumper; 

my $help = 0;
my $DEBUG = 0;
my %problemHubs = ( 
                     '1.3.6.1.4.1.11.2.3.7.8.2.5' => 1,
                   );
my $TEST = 0;


my %ifnames = ( physaddr => "ifPhysAddress",
		number => "instance",
		type => "ifType",
		description => "descr",
		speed => "ifSpeed",
		status => "ifAdminStatus" );


my $usage = <<EOF;
usage: $0 -d|--device <host> -h|--help -v|--verbose

    -d, --device <host>  update given device only.  
                         Skipping this will update all devices in DB.
    -h, --help           print help (this message)
    -v, --verbose        be verbose
    -t, --test           run through the routines, but do not make changes

EOF

my ($device, $host, @devices);

# handle cmdline args
my $result = GetOptions( "d|device=s" => \$host,
			 "h|help" => \$help,
			 "v|verbose" => \$DEBUG,
			 "t|test" => \$TEST );
if( ! $result ) {
  die "Error: Problem with cmdline args\n";
}
if( $help ) {
  print $usage;
  exit;
}

my $gui = Netdot::GUI->new();    
my $nv = Netdot::Netviewer->new( foreground => '0', loglevel => 'LOG_ERR' );


if (defined $host){
    if ($device = (Device->search(name => $host))[0]){
	push @devices, $device;
    }else{
	die "$host not found on db\n";
    }
}else{
    print "Fetching current list of devices....\n" if( $DEBUG );
    @devices = Device->retrieve_all();
}

my @ifrsv = NvIfReserved->retrieve_all();

foreach my $device ( @devices ) {
  my %ifs;
  print "Checking device ", $device->name, " \n" if( $DEBUG );
  map { $ifs{ $_->id } = 1 } $device->interfaces();
  my $comstr = $device->community || Netviewer->community;
  $nv->build_config( "device", $device->name, $comstr );
  ################################################
  # get information from the device
  my %dev;
  if( (%dev  = $nv->get_device( "device", $device->name )) && exists $dev{sysUpTime} ) {
    print "Have device ", $device->name, " information\n" if( $DEBUG );
    if ($dev{sysUpTime} < 0 ) {
	printf "Device %s has sysUpTime value of %d; skipping\n", 
	$device->name, $dev{sysUpTime} if( $DEBUG );
	next;
    }
    my %devtmp;
    $devtmp{sysdescription} = $dev{sysDescr};

    ###############################################
    # Try to assign Product based on SysObjectID
    if( my $prod = (Product->search( sysobjectid => $dev{sysObjectID} ))[0] ) {
	print "System ID matches ", $prod->name, "\n";
	$devtmp{productname} = $prod->id;
    }else{
	print "No Products found with System ID ", $dev{sysObjectID}, "\n";
    }

    if( length( $dev{dot1dBaseBridgeAddress} ) > 0 
        && $dev{dot1dBaseBridgeAddress} eq "noSuchObject" ) {
      # Remove the '0x' from the MAC address
      $devtmp{physaddr} = $dev{dot1dBaseBridgeAddress};
      $devtmp{physaddr} =~ s/^0x//; 
    }
    if( length( $dev{entPhysicalSerialNum} ) > 0 
        && $dev{entPhysicalSerialNum} ne "noSuchObject" ) {
      $devtmp{serialnumber} = $dev{entPhysicalSerialNum};
    }

    if( ! $TEST ) {
       unless( $gui->update( object => $device, state => \%devtmp ) ) {
	  next;
       }
    }

    ##############################################
    # for each interface just discovered...
    my %dbips;
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
      my( %iftmp, $if );
      $iftmp{device} = $device->id;
      $iftmp{name} = $newif;
      foreach my $dbname ( keys %ifnames ) {
	if( $ifnames{$dbname} eq "descr" ) {
	    if( $dev{interface}{$newif}{$ifnames{$dbname}} ne "-" 
		&& $dev{interface}{$newif}{$ifnames{$dbname}} ne "not assigned" ) {
		$iftmp{$dbname} = $dev{interface}{$newif}{$ifnames{$dbname}};
	    }
	} else {
	  $iftmp{$dbname} = $dev{interface}{$newif}{$ifnames{$dbname}};
	}
      }
      $iftmp{physaddr} =~ s/^0x//;
      ############################################
      # does this ifIndex already exist in the DB?
      if( $if = (Interface->search( device => $device->id, number => $dev{interface}{$newif}{instance}))[0] ) {
	print "Interface device ", $device->name, ":$newif exists; updating\n"
	  if( $DEBUG );
	delete( $ifs{ $if->id } );

	if( ! $TEST ) {
	   unless( $gui->update( object => $if, state => \%iftmp ) ) {
	      next;
	   }
	}

      } else {
	$iftmp{managed} = 0;
	$iftmp{speed} ||= 0; #can't be null
	print "Interface device ", $device->name, ":$newif doesn't exist; ",
	  "inserting\n" if( $DEBUG );

	if( ! $TEST ) {
	   unless( my $ifid = $gui->insert( table => "Interface", 
					    state => \%iftmp ) ) {
	      print "Error inserting Interface\n" if ($DEBUG);
	      next;
	   }else{
	      unless( $if = Interface->retrieve($ifid) ) {
		 print "Couldn't retrieve Interface id $ifid\n" if ($DEBUG);
		 next;
	      }
	   }
	}

      }
      ################################################################
      # Update IPs
      
      if( exists( $dev{interface}{$newif}{ipAdEntIfIndex} ) ) {
	  map { $dbips{ $_->id } = 1 } $if->ips();
	  foreach my $newip( keys %{ $dev{interface}{$newif}{ipAdEntIfIndex}}){
	      my %iptmp;

	      my( $ipobj, $maskobj, $subnet, $ipdbobj );
	      $iptmp{mask} = $dev{interface}{$newif}{ipAdEntIfIndex}{$newip};

	      unless ($ipobj = new NetAddr::IP ($newip, $iptmp{mask})){
		  print "Could not create ip object: $newip<br>\n" if ($DEBUG);
		  next;
	      }
	      if ($newip =~ /127\.0\.0\./){
		  print "Skipping loopback address: $newip\n" if ($DEBUG);
		  next;
	      }
	      
	      ########################################
	      # does this subnet already exist?
	      if( $subnet = (Subnet->search( address => $ipobj->network->addr, prefix => $ipobj->masklen ) )[0] ) {
		  print "Subnet ",$ipobj->network, " exists\n" if( $DEBUG );
		  $iptmp{subnet} = $subnet->id;
	      } else {
		  my %iptmp;
		  print "Subnet ",$ipobj->network, " does not exist\n" if( $DEBUG );
		  $iptmp{address} = $ipobj->addr;
		  $iptmp{entity} = 0;
		  $iptmp{subnet} = 0;
		  #print "Subnet $ipobj->addr doesn't exist; inserting\n" if( $DEBUG );
		  #unless( $subnet = insert( object => "Subnet", state => \%tmp ) ){
		  #  next;
		  #}
	      }
	      $iptmp{interface} = $if->id;
	      $iptmp{address} = $newip;
	      ########################################
	      # does this ip already exist in the DB?
	      if( $ipdbobj = (Ip->search( address => $newip ))[0] ) {
		  print "Interface $newif IP $newip exists; updating\n" if($DEBUG);
		  if( ! $TEST ) {
		      unless( $gui->update( object => $ipdbobj, state => \%iptmp ) ) {
			  next;
		      }
		  }
		  delete( $dbips{ $ipdbobj } );
	      } else {
		  print "Interface $newif IP $newip doesn't exist; inserting\n" if($DEBUG);
		  if( ! $TEST ) {
		      if ( my $ipid  = $gui->insert( table => "Ip", state => \%iptmp ) ){
			  $ipdbobj = Ip->retrieve($ipid);
		      }else{
			  next;
		      }
		  }
	      }
	  } # for
      }
  }
    ##############################################
    # for each hubport just discovered...
    
    # 
    # Hack for HP-ICF-OID::hpAdvStkEnetSHAgent
    # These hubs assign a random value for the port group number
    # every time they reboot.  For that reason we do those manually
    # (don't add or remove their ports here)
    
    unless ( exists($problemHubs{$dev{sysObjectID}} )){
	
	foreach my $newport ( keys %{ $dev{hubPorts} } ) {
	    ############################################
	    # set up IF state data
	    my (%porttmp, $if);
	    $porttmp{device} = $device->id;
	    $porttmp{name} = $newport;
	    $porttmp{number} = $newport;
	    
	    ############################################
	    # does this ifIndex already exist in the DB?
	    if( $if = (Interface->search( device => $device->id, number => $newport ))[0] ) {
		print "Interface device ", $device->name, ":$newport exists; updating\n"
		    if( $DEBUG );
		delete( $ifs{ $if->id } );
		unless( $gui->update( object => $if, state => \%porttmp ) ) {
		    next;
		}
	    } else {
		$porttmp{managed} = 0;
		$porttmp{speed} ||= 0; #can't be null
		print "Interface device ", $device->name, ":$newport doesn't exist; ",
		"inserting\n" if( $DEBUG );
		unless ( my $ifid = $gui->insert( table => "Interface", state => \%porttmp ) ) {
		    print "Error inserting Interface\n" if ($DEBUG);
		    next;
		}else{
		    unless ( $if = Interface->retrieve($ifid) ) {
			print "Couldn't retrieve Interface id $ifid\n" if ($DEBUG);
			next;
		    }
		}
	    }
	    
	} # end foreach my $newport

    }
    
    ##############################################
    # remove each interface that no longer exists
    
    unless ( exists($problemHubs{$dev{sysObjectID}} )){
	
	foreach my $nonif ( keys %ifs ) {
	    my $ifobj = Interface->retrieve($nonif);
	    print "Device ", $device->name, " Interface number ", $ifobj->number,
	    " doesn't exist; removing\n" if( $DEBUG );
	    if( ! $TEST ) {
		unless( $gui->remove( table => "Interface", id => $nonif ) ) {
		    next;
		}
	    }
	}
    }
    ##############################################
    # remove each ip address  that no longer exists
    foreach my $nonip ( keys %dbips ) {
      my $ipobj = Ip->retrieve($nonip);
      print "Device ", $device->name, " Ip Address ", $ipobj->address,
	" doesn't exist; removing\n" if( $DEBUG );
      
      if( ! $TEST ) {
	 unless( $gui->remove( table => "Ip", id => $nonip ) ) {
	    next;
	 }
      }

    }
  } else {
    print "Unable to access device ", $device->name, "\n" if( $DEBUG );
    warn "Unable to access device ", $device->name, "\n";
  }
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


