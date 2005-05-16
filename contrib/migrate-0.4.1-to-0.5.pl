#!/usr/bin/perl
#
# This script migrates data from the 0.4.1 Netdot database to the 0.5 version.
# It assumes DB is MySQL

use lib "/usr/local/netdot/lib";
use Netdot::DeviceManager;
use Netdot::DNSManager;
use Netdot::IPManager;
use Data::Dumper;
use strict;

my $DEBUG = 1;

my $olddb = "netdot-041";
my $newdb = "netdot";
my $user  = "root";
my $pass  = "";

my $dm  = Netdot::DeviceManager->new();
my $dns = Netdot::DNSManager->new();
my $ipm = Netdot::IPManager->new();

# The following tables will be ignored:
# Cable, CableStrand, CableStrand_history, CableType, Cable_history
# ComponentType, Device_history, Entity_history, Interface_history, 
# Ip_history, Meta, Name, Name_history, Netviewer, NvIfReserved, 
# Person_history, Product_history, Site_history, StrandStatus, Subnet_history
#
# The following tables are to be moved without changes
#
my @tables_to_move = qw /Availability Circuit CircuitStatus CircuitType Circuit_history Connection 
                         Connection_history Contact ContactList ContactType Contact_history EntitySite EntityType 
                         InterfaceDep Service/;

# Make sure the tables in new db are empty first
foreach my $table ( @tables_to_move ){
    system ("echo DELETE FROM $table| mysql $newdb");
}

# Fix some details
system("echo UPDATE Contact SET notify_email=0     WHERE notify_email     IS NULL | mysql $olddb");
system("echo UPDATE Contact SET notify_pager=0     WHERE notify_pager     IS NULL | mysql $olddb");
system("echo UPDATE Contact SET notify_voice=0     WHERE notify_voice     IS NULL | mysql $olddb");
system("echo UPDATE Contact SET escalation_level=0 WHERE escalation_level IS NULL | mysql $olddb");

system("echo UPDATE Contact_history SET notify_email=0     WHERE notify_email     IS NULL | mysql $olddb");
system("echo UPDATE Contact_history SET notify_pager=0     WHERE notify_pager     IS NULL | mysql $olddb");
system("echo UPDATE Contact_history SET notify_voice=0     WHERE notify_voice     IS NULL | mysql $olddb");
system("echo UPDATE Contact_history SET escalation_level=0 WHERE escalation_level IS NULL | mysql $olddb");

system ("mysqldump -t -c $olddb @tables_to_move | mysql $newdb");


#
# Now start with the conversions
#

my $dbh1 = DBI->connect("DBI:mysql:$olddb:localhost", 
                        $user,
                        $pass,
                        { RaiseError => 1 });


my $lookup;

######################################################################
# Site
######################################################################
# Only change is new 'number' field
# U of O puts numbers by the name, between parenthesis
# We'll insert those in the new number field

system ("echo DELETE FROM Site| mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, name, aliases, availability, street1, street2, pobox, city, state
            zip, country, contactlist, info
     FROM Site
");
$lookup->execute();
while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	if ( $key eq "name" && $hr->{$key} =~ /\((\w+)\)/ ){
	    $obj{$key}   = $hr->{$key};
	    $obj{number} = $1;
	}else{
	    $obj{$key}   = $hr->{$key};
	}
    }
    &insert("Site", \%obj); 
}

######################################################################
# Person
######################################################################
# Only change is that 'availability' is no longer there

system ("echo DELETE FROM Person| mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, firstname, lastname, aliases, position, entity, location
            email, office, home, cell, pager, emailpager, fax, info
     FROM Person
");
$lookup->execute();
while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	if ( $key ne "availability" ){
	    $obj{$key} = $hr->{$key};
	}
    }
    &insert("Person", \%obj); 
}
######################################################################
# Ip
######################################################################
#
# IPs and subnets have been merged into the Ipblock table
#
system ("echo DELETE FROM Ipblock | mysql $newdb");

my $statusid;
unless ( $statusid = (IpblockStatus->search(name=>"Static"))[0] ){
    print "Error: Can't find id for IpblockStatus Static\n";
    exit;
}

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, interface, address
     FROM Ip
");
$lookup->execute();
while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	$obj{$key} = $hr->{$key};
    }
    $obj{prefix}      = "32";
    $obj{version}     = "4";
    $obj{status}      = $statusid;
    $obj{first_seen}  = $dm->timestamp;
    
    &insert("Ipblock", \%obj); 
}

######################################################################
# Subnet
######################################################################

my $sub_status;
my $cont_status;
unless ( $sub_status = (IpblockStatus->search(name=>"Subnet"))[0] ){
    print "Error: Can't find id for IpblockStatus Subnet\n";
    exit;
}
unless ( $cont_status = (IpblockStatus->search(name=>"Container"))[0] ){
    print "Error: Can't find id for IpblockStatus Container\n";
    exit;
}

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT address, prefix, description, entity, info
     FROM Subnet
");
$lookup->execute();
LOOP: while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	# Ignore /32 subnets.  Those are probably loopbacks
	next LOOP if ( $key eq "prefix" and $hr->{$key} == 32 );
	
	if ( $key eq "description" ){
	    if ($hr->{description} =~ /unused/i){
		$obj{status}  = $cont_status;
	    }else{
		$obj{status}  = $sub_status;
	    }
	}
	$obj{$key} = $hr->{$key};
    }
    $obj{version} = "4";
    $obj{first_seen}  = $dm->timestamp;
    
    &insert("Ipblock", \%obj); 
}

# Build the IP tree

unless ( $ipm->build_tree(4) ){
    print $ipm->error;
}


######################################################################
# Device
######################################################################
#
# Most important change is that now names are DNS Resource Records
#
system ("echo DELETE FROM Device  | mysql $newdb");
system ("echo DELETE FROM PhysAddr| mysql $newdb");
system ("echo DELETE FROM RR      | mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, name, aliases, type, sysdescription, physaddr, oobname, oobnumber, 
     entity, contactlist, person, managed, community, serialnumber, productname,
     inventorynumber, maint_covered, site, room, rack, dateinstalled, info
     FROM Device
");

$lookup->execute();

my %prod2type;  #We'll use this later

while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	if ( $key eq "name" ){
	    my $rr;
	    if ($rr = $dns->insert_rr(name        => $hr->{$key}, 
				      contactlist => $hr->{contactlist})){
		$obj{name} = $rr;
	    }else{
		printf("Could not insert DNS entry %s: %s", $hr->{$key}, $dns->error);
	    }
	}elsif ( $key eq "type" ){
	    if ( ! exists $prod2type{$hr->{productname}} ){
		$prod2type{$hr->{productname}} = $hr->{type};
	    }
	}elsif ( $key eq "physaddr" ){
	    if ( $hr->{$key} =~ /[0-9A-Fa-f]{12}/ ){
		# Insert in new table if needed
		my $id;
		if ( my $o = (PhysAddr->search(address=>$hr->{physaddr}))[0] ){
		    $id = $o->id;
		}else{
		    my %ph = ( address => uc($hr->{physaddr}) );
		    $id = &insert("PhysAddr", \%ph); 
		}
		$obj{physaddr} = $id;
	    }else{
		$obj{physaddr} = 0;		
	    }
	}elsif ( $key eq "managed" ){
	    $obj{monitored}    = $hr->{$key};
	    $obj{snmp_managed} = $hr->{$key};
	}elsif ( $key eq "info" ){
	    if ( $hr->{room} =~ /\w+/ ){
		$obj{info} = "Room: $hr->{room}\n" . $hr->{$key};
	    }else{
		$obj{info} = $hr->{$key};
	    }
	}else{
	    $obj{$key} = $hr->{$key};
	}
    }
    if ( ! defined($obj{monitored})     ) { $obj{monitored}     =  1 };
    if ( ! defined($obj{maint_covered}) ) { $obj{maint_covered} =  0 };

    &insert("Device", \%obj); 
}
######################################################################
# Interface
######################################################################
system ("echo DELETE FROM Interface| mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, device, name, physaddr, number, type, description, speed,
     status, managed, room, jack, info
     FROM Interface
");

$lookup->execute();

while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	if ( $key eq "status" ){
	    $obj{admin_status} = $hr->{$key};
	}elsif( $key eq "managed" ){
	    $obj{monitored} = $hr->{$key};
	    $obj{snmp_managed} = $hr->{$key};
	}elsif( $key eq "jack" ){
	    $obj{jack_char} = $hr->{$key};
	}elsif( $key eq "room" ){
	    $obj{room_char} = $hr->{$key};
	}else{
	    $obj{$key} = $hr->{$key};
	}
    }
    &insert("Interface", \%obj); 
}
######################################################################
# Entity
######################################################################
#
# I won't bother with bgppeerip
#
system ("echo DELETE FROM Entity| mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, name, aliases, type, availability, contactlist,
     acctnumber, maint_contract, autsys, info
     FROM Entity
");

$lookup->execute();

while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	if ( $key eq "autsys" ){
	    $obj{asname} = $hr->{$key};
	    if ( $hr->{autsys} =~ /(\d+)/ ){
		$obj{asnumber} = $1;
	    }
	}else{
	    $obj{$key} = $hr->{$key};
	}
    }
    &insert("Entity", \%obj); 

}

######################################################################
# Product
######################################################################
system ("echo DELETE FROM Product| mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, name, description, sysobjectid, manufacturer, info
     FROM Product
");

$lookup->execute();

while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	$obj{$key} = $hr->{$key};
    }
    $obj{type} = $prod2type{$obj{id}} || 0;
    &insert("Product", \%obj); 
}
######################################################################
# DeviceType
######################################################################
# DeviceType is now ProductType
# 
system ("echo DELETE FROM ProductType| mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, name, info
     FROM DeviceType
");

$lookup->execute();

while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	$obj{$key} = $hr->{$key};
    }
    &insert("ProductType", \%obj); 
}

######################################################################
# IpService
######################################################################
# New table has new fields: monitored, monitoredstatus 
#
system ("echo DELETE FROM IpService| mysql $newdb");

undef $lookup;
$lookup = $dbh1->prepare("
     SELECT id, ip, service, contactlist
     FROM IpService
");

$lookup->execute();

while ( my $hr = $lookup->fetchrow_hashref ){
    my %obj;
    foreach my $key ( keys %$hr ){
	$obj{$key} = $hr->{$key};
    }
    $obj{monitored}       = 1;
    $obj{monitorstatus} = 0;
    &insert("IpService", \%obj); 
}


print "Migration process finished\n";

######################################################################
######################################################################
# Subroutine section
######################################################################
######################################################################

sub insert {
    my ($table, $state) = @_;
    my $id;
    unless ( $id = $dm->insert(table=>$table, state=>$state) ){
	print $dm->error;
	print "We were inserting \n", Dumper( %$state ), "\n" if $DEBUG;
	exit;
    }else{
	print "Inserted $table ", $id, "\n" if $DEBUG;
	return $id;
    }
}
