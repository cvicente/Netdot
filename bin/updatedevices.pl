#!/usr/local/bin/perl

use lib "/home/netdot/public_html/lib";
use Getopt::Long;
use strict;
use Socket;
use Netdot::DBI;
use Netdot::Netviewer;
use Data::Dumper; 

my $help = 0;
my $DEBUG = 0;
my %ifnames = ( physaddr => "ifPhysAddress",
		index => "instance",
		type => "ifType",
		description => "descr",
		speed => "ifSpeed",
		status => "ifAdminStatus" );
my $usage = <<EOF;
usage: $0 -n|--device <host> -h|--help -v|--verbose

    -n  <host>: update given device only.  Skipping this will update all devices in DB.
    -h        : print help (this message)
    -v        : be verbose
EOF

my ($device, $host, @devices);

# handle cmdline args
my $result = GetOptions( "n=s" => \$host,
			 "device=s" => \$host,
			 "h" => \$help,
			 "help" => \$help,
			 "v" => \$DEBUG,
			 "verbose" => \$DEBUG );
if( ! $result ) {
  die "Error: Problem with cmdline args\n";
}
if( $help ) {
  print $usage;
  exit;
}
    
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
  if( my( %dev ) = $nv->get_device( "device", $device->name ) ) {
    print "Have device ", $device->name, " information\n" if( $DEBUG );
    if( $dev{sysUpTime} < 0 ) {
      printf "Device %s has sysUpTime value of %d; skipping\n", 
	$device->name, $dev{sysUpTime} if( $DEBUG );
      next;
    }
    my %ntmp;
    $ntmp{sysdescription} = $dev{sysDescr};
    $ntmp{physaddr} = $dev{dot1dBaseBridgeAddress};
    $ntmp{physaddr} =~ s/^0x//; 
    $ntmp{serialnumber} = $dev{entPhysicalSerialNum};
    unless( update( object => $device, state => \%ntmp ) ) {
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
      $iftmp{device} = $device->id;
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
      if( $if = (Interface->search( device => $device->id, index => $dev{interface}{$newif}{instance}))[0] ) {
	print "Interface device ", $device->name, ":$newif exists; updating\n"
	  if( $DEBUG );
	delete( $ifs{ $if->id } );
	unless( update( object => $if, state => \%iftmp ) ) {
	  next;
	}
      } else {
	$iftmp{managed} = 0;  #can't be null
	$iftmp{speed} ||= 0; #can't be null
	print "Interface device ", $device->name, ":$newif doesn't exist; ",
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
      next if ($intobj->device->type->name eq "Hub");
  
      print "Device ", $device->name, " Interface Index", $intobj->index,
	"doesn't exist; removing\n" if( $DEBUG );
      unless( remove( object => "Interface", id => $nonif ) ) {
	next;
      }
    }
  } else {
    print "Unable to access device ", $device->name, "\n" if( $DEBUG );
    warn "Unable to access device ", $device->name, "\n";
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


