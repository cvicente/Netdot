#!/usr/bin/perl
#
#  Read relevant info from Netdot and 
#  build Nagios 2.0 configuration
#

use NetdotExport;
use lib "/usr/local/netdot/lib";
use Netdot::DBI;
use strict;
use Data::Dumper;

###################################################
########## Config Section #########################

# Print debugging info
my $DEBUG = 0;

# Add Round Trip Time service (using APAN add-on)
my $ADDRTT = 1;

# Add 'TRAP' service?
my $ADDTRAPS = 1;

########## Input and output files ################
my $cfg_ext  = "cfg";        # config file extension
my $skel_ext = "cfg.skel";   # skeleton file extension
my @files = qw ( hosts );    # list of files we'll create

if ( $ADDRTT ){
    push @files, 'apan';
}

########## For Service/Host escalation:###########

my $first_notification    = 4;
my $last_notification     = 6;
my $notification_interval = 0;  #(min)

# Map Netdot service names to Nagios plugin names
my %servchecks = (
		  PING   => "check_host_alive",
		  HTTP   => "check_http",
		  HTTPS  => "check_https",
		  FTP    => "check_ftp",
		  NTP    => "check_ntp",
		  DNS    => "check_dns",
		  LDAP   => "check_ldap",
		  MYSQL  => "check_mysql",
		  NNTP   => "check_nntp",
		  POP3   => "check_pop",
		  POP3S  => "check_spop",
		  SMTP   => "check_smtp",
		  SSH    => "check_ssh",
		  BGP    => "check_bgp",
		  DHCPD  => "check_dhcp",
		  IMAP   => "check_imap",
		  IMAPS  => "check_simap",
		  RADIUS => "check_radius",
		  TIME   => "check_time",
		  TELNET => "check_telnet",
		);

# Map Netdot's 'availability' to Nagios timeperiods
my %timeperiods = (
		   '24x7'                     => '24x7',
		   '8:00-17:00'               => 'workhours',
		   'Extended Workhours'       => 'extendedworkhours',
		   'Never'                    => 'none'
		   );

########## End Config Section #####################
###################################################

my $usage = "Usage: $0 \n";

if (scalar (@ARGV) != 0){
    print $usage;
    exit;
}

my (%hosts, %groups, %name2ip, %ip2name, %contacts, %contactlists, %services, %servicegroups);

foreach my $ipobj ( Ipblock->retrieve_all ){
    
    # Ignore if set to not monitor
    next unless ( $ipobj->interface->monitored 
		  && $ipobj->interface->device->monitored );
    
    $hosts{$ipobj->id}{ip} = $ipobj->address;
    $hosts{$ipobj->id}{ipobj} = $ipobj;
    my $group;
    if ( ! $ipobj->interface->device->entity ){
	warn "Entity not assigned for ",$ipobj->interface->device->name, "\n";
	$group = 'unknown';
    }else {
	$group = join '_', split /\s+/, $ipobj->interface->device->entity->name;
	$group =~ s/[\(\),]//g;  #Remove illegal chars for Nagios
    }
    
    # Assign most specific contactlist 
    # Order is: interface, device and then entity
    #
    my $clobj;
    if ( ($clobj = $ipobj->interface->contactlist) != 0 ||
	 ($clobj = $ipobj->interface->device->contactlist) != 0 ||
	 ($clobj = $ipobj->interface->device->entity->contactlist) != 0 ){
	$contactlists{$clobj->id}{name} = join '_', split /\s+/, $clobj->name;
	$hosts{$ipobj->id}{contactlist} = $clobj->id;
    }else{
	$hosts{$ipobj->id}{contactlist} = 0;
    }
    $hosts{$ipobj->id}{group} = $group;
    
    # For a given IP addres we'll try to get its name directly
    # from the DNS.  If it's not there, or if it's not unique
    # the name will be the device name plus the interface name
    # plus the IP address
    my $hostname;
    unless ( ($hostname = &resolve($ipobj->address)) && !exists $name2ip{$hostname} ){
	$hostname = $ipobj->interface->device->name->name
	    . "-" . $ipobj->interface->name
	    . "-" . $ipobj->address;
	warn "Assigned name $hostname \n" if $DEBUG;
    }
    $hosts{$ipobj->id}{name} = $hostname;
    push @{ $groups{$group}{members} }, $hostname;
    $name2ip{$hostname} = $ipobj->id;
    $ip2name{$ipobj->id} = $hostname;
    
    # Add services (if any)
    foreach my $ipsrv ( $ipobj->services ){
	my $srvname = $ipsrv->service->name;
	my $srvclobj;
	warn "Service $srvname being added to IP ",$ipobj->address, "\n" if $DEBUG;
	push  @{ $servicegroups{$srvname}{members} }, $hostname ;

	# Assign most specific contactlist 
	# Order is: service, interface, device and then entity
	#
	my $srvclobj;
	if ( ($srvclobj = $ipsrv->contactlist) != 0 ||
	     ($srvclobj = $ipsrv->ip->interface->contactlist) != 0 ||
	     ($srvclobj = $ipsrv->ip->interface->device->contactlist) != 0 ||
	     ($srvclobj = $ipsrv->ip->interface->device->entity->contactlist) ){
	    $services{$hostname}{$srvname}{contactlist} = $srvclobj->id;
	    $contactlists{$srvclobj->id}{name} = join '_', split /\s+/, $srvclobj->name;
	    warn "Contactlist ",$srvclobj->name, " assigned to service $srvname for IP ",$ipobj->address, "\n" if $DEBUG;
	}else{
	    $services{$hostname}{$srvname}{contactlist} = 0;
	    warn "Service $srvname for IP ", $ipobj->address, " has no contactlist defined\n" if $DEBUG;
	}
        # Add the SNMP community in case it's needed
	$services{$hostname}{$srvname}{community} =  $ipobj->interface->device->community;
    }
} #foreach ip

# Now that we have everybody in, assign parent list.

foreach my $ipid ( keys %hosts ){
    my @parentlist;
    my $ipobj = $hosts{$ipid}{ipobj};
    if ( my $intobj = $ipobj->interface ){
	if ( scalar(@parentlist = &getparents($intobj)) ){
	    $hosts{$ipid}{parents} = join ',', map { $ip2name{$_} } @parentlist;
	}else{
	    $hosts{$ipid}{parents} = undef;
	}
    }
}

# Classify contacts by their escalation-level
# We'll create a contactgroup for each level

foreach my $clid ( keys %contactlists ){
    my $clobj;
    unless ( $clobj = ContactList->retrieve($clid) ){
	warn "Error retrieving ContactList id $clid: $contactlists{$clid}{name}\n";
	next;
    }
    foreach my $contact ( $clobj->contacts ){
	
	# Skip if no availability
	next if ( ($contact->notify_email == 0 || $contact->notify_email->name eq "Never") && 
		  ($contact->notify_pager == 0 || $contact->notify_pager->name eq "Never") );
	
	# Get common info and store it separately
	# to create a template
	my $contactname = '';
	$contactname = join ' ', ($contact->person->firstname, $contact->person->lastname);
	$contactname =~ s/^\s*(.*)\s*$/$1/;
	$contactname =~ s/\s+/_/g;
	if ( ! exists ($contacts{$contactname}) ){
	    $contacts{$contactname}{email} = $contact->person->email;
	    $contacts{$contactname}{pager} = $contact->person->emailpager;
	}
	
	# Then group by escalation level
	my $level;
	if ( ! defined ($contact->escalation_level) ){
	    $level = 0;  # Assume it's lowest if not there.
	}else{
	    $level = $contact->escalation_level;
	}
	$contactlists{$clid}{level}{$level}{$contact->id}{name} = $contactname;
    }
}
print Dumper(%groups) if $DEBUG;

# Now build the config files
foreach my $file (@files){
    
    # Open skeleton file for reading
    my $skel_file = "$file.$skel_ext";
    open (SKEL, "$skel_file") 
	or die "Can't open $skel_file\n";
    
    # Open output file for writing
    my $out_file = "$file.$cfg_ext";
    open (OUT, ">$out_file") 
	or die "Can't open $out_file\n";
    select (OUT);
    
    while (<SKEL>){
	if (/<INSERT DATE>/){
	    print "#\t-- Generated by $0 on ", scalar localtime,  "--\n" ;
	    
	}elsif (/<INSERT HOST DEFINITIONS>/){
	    
	    foreach my $ipid ( keys %hosts ){
		my $hostname = $hosts{$ipid}{name};
		my $ip       = $hosts{$ipid}{ip};
		my $group    = $hosts{$ipid}{group};
		my $parents  = $hosts{$ipid}{parents};
		my $clid     = $hosts{$ipid}{contactlist};
		
		if ( ! $clid || ! ( keys %{ $contactlists{$clid}{level}} ) ){

		    warn "$hostname does not have a valid Contact Group!\n";
		    print "define host{\n";
		    print "\tuse                    generic-host\n";
		    print "\thost_name              $hostname\n";
		    print "\talias                  $group\n";
		    print "\taddress                $ip\n";
		    print "\tparents                $parents\n" if ($parents);
		    print "\tcontact_groups         nobody\n";
		    print "}\n\n";
		    
		    if ( $ADDTRAPS ){
			# Define a TRAP service for every host
			print "define service{\n";
			print "\tuse                    generic-trap-service\n";
			print "\thost_name              $hostname\n";
			print "\tcontact_groups         nobody\n";
			print "\tnotification_options   c\n";
			print "}\n\n";
		    }
		}else{
		    my $clname = $contactlists{$clid}{name} || 'nobody';
		    my $first  = 1;
		    my $fn     = $first_notification;
		    my $ln     = $last_notification;
		    foreach my $level ( sort keys %{ $contactlists{$clid}{level} } ){
			if ($first){
			    print "define host{\n";
			    print "\tuse                    generic-host\n";
			    print "\thost_name              $hostname\n";
			    print "\talias                  $group\n";
			    print "\taddress                $ip\n";
			    print "\tparents                $parents\n" if ($parents);
			    print "\tcontact_groups         $clname-level_$level\n";
			    print "}\n\n";
			    if ( $ADDTRAPS ){
				print "define service{\n";
				print "\tuse                     generic-trap-service\n";
				print "\thost_name               $hostname\n";
				print "\tcontact_groups          $clname-level_$level\n";
				print "}\n\n";
			    }
			    $first = 0;
			}else{
			    print "define hostescalation{\n";
			    print "\thost_name                $hostname\n";
			    print "\tfirst_notification       $fn\n";
			    print "\tlast_notification        $ln\n";
			    print "\tnotification_interval    $notification_interval\n";
			    print "\tcontact_groups           $clname-level_$level\n";
			    print "}\n\n";
			    
			    if ( $ADDTRAPS ){
				print "define serviceescalation{\n";
				print "\thost_name                $hostname\n";
				print "\tservice_description      TRAP\n";
				print "\tfirst_notification       $fn\n";
				print "\tlast_notification        $ln\n";
				print "\tnotification_interval    $notification_interval\n";
				print "\tcontact_groups           $clname-level_$level\n";
				print "}\n\n";
			    }
			    
			    $fn += $ln - $fn + 1;
			    $ln += $ln - $fn + 1;
			}
		    }	   
		    
		}
		if ( $ADDRTT ){
		    # Define RTT (Round Trip Time) as a service
		    print "define service{\n";
		    print "\thost_name              $hostname\n";
		    print "\tservice_description    RTT\n";
		    print "\tcheck_command          apan!ping!2000.0,60%!5000.0,100%\n";
		    print "\tname                   RTT\n";
		    print "\tuse                    generic-ping\n";
		    print "\tnormal_check_interval  5\n";
		    print "\tcontact_groups         nobody\n";
		    print "}\n\n";
		    
		    print "define serviceextinfo{\n";
		    print "\thost_name              $hostname\n";
		    print "\tservice_description    RTT\n";
		    print "\tnotes                  Round Trip Time Statistics\n";
		    print "\tnotes_url              /nagios/cgi-bin/apan.cgi?host=$ip&service=RTT\n";
		    print "\ticon_image             graph.png\n";
		    print "\ticon_image_alt         View RTT graphs\n";
		    print "}\n\n";
		    
		}else{
		    
		    # Nagios requires at least one service per host
		    print "define service{\n";
		    print "\tuse                    generic-ping\n";
		    print "\thost_name              $hostname\n";
		    print "\tcontact_groups         nobody\n";
		    print "\tnotification_options   c\n";
		    print "}\n\n";
		}
		
	    }
	    
	}elsif (/<INSERT APAN DEFINITIONS>/){
	    
	    foreach my $ipid ( keys %hosts ){
		my $name = $hosts{$ipid}{name};
		$name =~ s/\//-/;
		my $ip = $hosts{$ipid}{ip};
		print "$ip;RTT;/usr/local/nagios/rrd/$ip-RTT.rrd;ping;RTT:LINE2;Ping round-trip time;Seconds\n"; 
	    }
	    
	}elsif (/<INSERT CONTACT DEFINITIONS>/){
	    # Create the contact templates (with a person's common info)
	    # A person might be a contact for several groups/events
	    
	    foreach my $name (keys %contacts){
		print "define contact{\n";
		print "\tname                            $name\n";
		print "\tuse                             generic-contact\n";
		print "\talias                           $name\n";
		print "\temail                           $contacts{$name}{email}\n" if $contacts{$name}{email};
		print "\tpager                           $contacts{$name}{pager}\n" if $contacts{$name}{pager};
		print "\tregister                        0 ; (THIS WILL BE INHERITED LATER)\n";  
		print "}\n\n";
		
	    }
	    
	    # Create specific contacts (notification periods vary in each case)
	    foreach my $cl ( keys %contactlists  ){
		my $clname = $contactlists{$cl}{name};
		foreach my $level ( sort {$a <=> $b} keys %{ $contactlists{$cl}{level} } ){
		    my @members;
		    foreach my $contactid ( keys %{ $contactlists{$cl}{level}{$level} } ){
			my $name = $contactlists{$cl}{level}{$level}{$contactid}{name};
			my $contact = Contact->retrieve($contactid);
			# One for e-mails
			if (int($contact->notify_email)){
			    if ( exists($timeperiods{$contact->notify_email->name}) ){
				if ((my $emailperiod = $timeperiods{$contact->notify_email->name}) ne 'none' ){
				    my $contactname = "$name-$clname-email-level_$level";
				    push @members, $contactname;
				    print "define contact{\n";
				    print "\tcontact_name                    $contactname\n";
				    print "\tuse                             $name\n";
				    print "\tservice_notification_period     $emailperiod\n";
				    print "\thost_notification_period        $emailperiod\n";
				    print "\tservice_notification_commands   notify-by-email\n";
				    print "\thost_notification_commands      host-notify-by-email\n";
				    print "}\n\n";
				}
			    }else{
				warn $contact->notify_email->name, " is not a defined timeperiod\n" if ($DEBUG);
			    }
			}
			# And one for paging
			if (int($contact->notify_pager)){
			    if ( exists($timeperiods{$contact->notify_pager->name}) ){
				if ((my $pagerperiod = $timeperiods{$contact->notify_pager->name}) ne 'none' ){
				    my $contactname = "$name-$clname-pager-level_$level";
				    push @members, $contactname;
				    print "define contact{\n";
				    print "\tcontact_name                    $contactname\n";
				    print "\tuse                             $name\n";
				    print "\tservice_notification_period     $pagerperiod\n";
				    print "\thost_notification_period        $pagerperiod\n";
				    print "\tservice_notification_commands   notify-by-epager\n";
				    print "\thost_notification_commands      host-notify-by-epager\n";
				    print "}\n\n";
				}
			    }else{
				warn $contact->notify_pager->name, " is not a defined timeperiod\n" if ($DEBUG);
			    }
			}
		    }
		    # Create the contactgroup
		    my $members = join ',', @members;
		    
		    print "define contactgroup{\n";
		    print "\tcontactgroup_name       $clname-level_$level\n";
		    print "\talias                   $clname\n";
		    print "\tmembers                 $members\n";
		    print "}\n\n";
		}
	    }
	    
	}elsif (/<INSERT HOST GROUP DEFINITIONS>/){
	    foreach my $group (keys %groups){
		
		my $hostlist = join ',', @{ $groups{$group}{members} };
		print "define hostgroup{\n";
		print "\thostgroup_name      $group\n";
		print "\talias               $group\n";
		print "\tmembers             $hostlist\n";
		print "}\n\n";
	    }
	    
	}elsif (/<INSERT SERVICE GROUP DEFINITIONS>/){
	    foreach my $group (keys %servicegroups){
		
		# servicegroup members are like:
		# members=<host1>,<service1>,<host2>,<service2>,...,
		my $hostlist = join ',', map { "$_,$group" }@{ $servicegroups{$group}{members} };
		print "define servicegroup{\n";
		print "\tservicegroup_name      $group\n";
		print "\talias                  $group\n";
		print "\tmembers                $hostlist\n";
		print "}\n\n";
	    }
	    
	}elsif (/<INSERT SERVICE DEFINITIONS>/){
	    
	    foreach my $hostname ( keys %services ){
		foreach my $srvname ( keys %{ $services{$hostname} } ){
		    if (exists $servchecks{$srvname}){
			my $checkcmd = $servchecks{$srvname};
			
			# Add community argument for checks that use SNMP
			if ( $checkcmd eq "check_bgp"){
			    $checkcmd .= "!$services{$hostname}{$srvname}{community}";
			}
			
			my $clid = $services{$hostname}{$srvname}{contactlist};
			if ( ! $clid ){
			    
			    print "define service{\n";
			    print "\tuse                  generic-service\n";
			    print "\thost_name            $hostname\n";
			    print "\tservice_description  $srvname\n";
			    print "\tcontact_groups       nobody\n";
			    print "\tcheck_command        $checkcmd\n";
			    print "}\n\n";
			    
			}else{
			    my $clname = $contactlists{$clid}{name} || 'nobody';
			    my $first  = 1;
			    my $fn     = $first_notification;
			    my $ln     = $last_notification;
			    foreach my $level ( sort keys %{ $contactlists{$clid}{level} } ){
				
				if ($first){
				    print "define service{\n";
				    print "\tuse                  generic-service\n";
				    print "\thost_name            $hostname\n";
				    print "\tservice_description  $srvname\n";
				    print "\tcontact_groups       $clname-level_$level\n";
				    print "\tcheck_command        $checkcmd\n";
				    print "}\n\n";
				    
				    $first = 0;
				}else{
				    
				    print "define serviceescalation{\n";
				    print "\thost_name                $hostname\n";
				    print "\tservice_description      $srvname\n";
				    print "\tfirst_notification       $fn\n";
				    print "\tlast_notification        $ln\n";
				    print "\tnotification_interval    $notification_interval\n";
				    print "\tcontact_groups           $clname-level_$level\n";
				    print "}\n\n";
				    
				    $fn += $ln - $fn + 1;
				    $ln += $ln - $fn + 1;
				}
			    }	   
			}
			
		    }else{
			warn "Warning: service check for $srvname not implemented.  Skipping $srvname check for host $hostname.\n";
		    }
		}
	    }
	    
	}else{
	    print $_;
	}
    }
    print STDOUT "OK: Nagios configuration written to file: $out_file\n";    
    close(SKEL);
    close(OUT);
}
