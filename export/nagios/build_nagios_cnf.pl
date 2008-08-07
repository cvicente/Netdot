#!/usr/bin/perl
#
#  Read relevant info from Netdot and 
#  build Nagios 2.0 configuration
#

use lib "<<Make:LIB>>";
use Netdot::Export;
use Netdot::Model;
use strict;
use Data::Dumper;
use Getopt::Long;

use Netdot::Util::DNS;
my $dns    = Netdot::Util::DNS->new();
my $export = Netdot::Export->new();

use vars qw( %self $USAGE %hosts %groups %contacts %contactlists %services %servicegroups );

&set_defaults();

my $USAGE = <<EOF;
usage: $0 [options]
    --monitor         <hostname> Monitoring system name
    --dir             <path> Path to configuration file
    --cfg_ext         <extension> Config file extension (default: $self{cfg_ext})
    --skel_ext        <extension> Skeleton file extension (default: $self{skel_ext})
    --files           <file1,file2,...> List of files to process (default: $self{files})
    --first_notif     <n>   First event to be notified when escalating (default: $self{first_notif})
    --last_notif      <n>   Last event to be notified when escalating (default: $self{last_notif})
    --notif_interval  <min> Notification Interval for escalations (default: $self{notif_interval})
    --rtt             Add Round Trip Time graphs using APAN add-on (default: $self{rtt})
    --traps           Add trap service to all hosts (default: $self{traps})
    --strip_domain    <domain_name> Strip off domain name from device name
    --debug           Print debugging output
    --help            Display this message
EOF

&setup();
&gather_data();
&build_configs();


##################################################
sub set_defaults {
    %self = (
	dir             => '.',
	cfg_ext         => 'cfg',
	skel_ext        => 'cfg.skel',
	files           => 'hosts',
	first_notif     => 4,
	last_notif      => 6,
	notif_interval  => 0,
	rtt             => 0,
	traps           => 1,
	help            => 0,
	debug           => 0, 
	);
}

##################################################
sub setup{

    my $result = GetOptions( "monitor=s"        => \$self{monitor},
			     "dir=s"            => \$self{dir},
			     "cfg_ext=s"        => \$self{cfg_ext}, 
			     "skel_ext=s"       => \$self{skel_ext}, 
			     "files=s"          => \$self{files},
			     "first_notif=i"    => \$self{first_notif},
			     "last_notif=i"     => \$self{last_notif},
			     "notif_interval=i" => \$self{notif_interval},
			     "rtt"              => \$self{rtt},
			     "traps"            => \$self{traps},
			     "strip_domain=s"   => \$self{strip_domain},
			     "debug"            => \$self{debug},
			     "h"                => \$self{help},
			     "help"             => \$self{help},
			     );
    
    if( ! $result || $self{help} ) {
	print $USAGE;
	exit 0;
    }
    if( ! $self{monitor} ){
	print $USAGE;
	die "Please specify the name of the monitoring device\n";
    }
    
    @{ $self{files_array} } = split ',', $self{files};

    # Put APAN's stuff in a separate file
    if ( $self{rtt} ){
	push @{ $self{files_array} }, 'apan';
    }
  
    # Map Netdot's service names to Nagios' plugin names
    # Make sure you have all these checks defined in your Nagios config
    %{$self{servchecks}} = (
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
    
    # Map Netdot's 'availability' to Nagios' timeperiods
    %{$self{timeperiods}} = (
			     '24x7'                     => '24x7',
			     '8:00-17:00'               => 'workhours',
			     'Extended Workhours'       => 'extendedworkhours',
			     'Never'                    => 'none'
			     );
    
}

##################################################
sub gather_data{
    my (%name2ip, %ip2name);
    
    my $monitor = Device->search(name=>$self{monitor})->first 
	|| die "Cannot find monitor device";
    
    my $device_ips = $export->get_device_ips();

    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $int_monitored, $dev_monitored) = @$row;
	next unless ($int_monitored && $dev_monitored);

	my $ipobj = Ipblock->retrieve($ipid);
	# Determine the group name for this device
	my $group;
	if ( int($ipobj->parent) != 0 ){
	    if ( int($ipobj->parent->used_by) != 0 ){
		$group = $ipobj->parent->used_by->name;
	    }elsif ( $ipobj->parent->description ){
		$group = $ipobj->parent->description;
	    }else{
		$group = $ipobj->parent->address;
	    }
	}elsif ( int($ipobj->interface->device->used_by) != 0 ){
	    $group = $ipobj->interface->device->used_by->name;
	}
	unless ( $group ){
	    warn "Address ", $ipobj->address, " in unknown network\n";
	    $group = "Unknown";
	}
	#Remove illegal chars for Nagios
	$group =~ s/[\(\),]//g;  
	$group =~ s/^\s*(.)\s*$/$1/;
	$group =~ s/[\/\s]/_/g;  
	$group =~ s/&/and/g;     
	$hosts{$ipobj->id}{ip}    = $ipobj->address;
	$hosts{$ipobj->id}{ipobj} = $ipobj;
	
	# Assign most specific contactlist 
	# Order is: interface, device and then entity
	# 
	my $clobj;
	if( ($clobj = $ipobj->interface->contactlist) != 0 ){
	    push @{ $hosts{$ipobj->id}{contactlists} }, $clobj;
	    
        # Devices can have many contactlists
	# This gets me DeviceContacts objects (join table)
	}elsif(  (my @dcs = $ipobj->interface->device->contacts) ){
	    foreach my $dc ( @dcs ){
		push @{ $hosts{$ipobj->id}{contactlists} }, $dc->contactlist;
	    }
	}elsif( ($clobj = $ipobj->interface->device->used_by->contactlist) != 0 ){
	    push @{ $hosts{$ipobj->id}{contactlists} }, $clobj;
	}
	
	foreach my $clobj ( @{ $hosts{$ipobj->id}{contactlists} } ){
	    $contactlists{$clobj->id}{name} = join '_', split /\s+/, $clobj->name;
	    $contactlists{$clobj->id}{obj}  = $clobj;
	}
	
	$hosts{$ipobj->id}{group} = $group;
	
	my $name;
	if ( $name = $dns->resolve_ip($ipobj->address) ){
	    
	}elsif ( my @arecords = $ipobj->arecords ){
	    $name = $arecords[0]->rr->get_label;
	}else{
	    $name = $ipobj->address;
	}
	$name =~ s/$self{strip_domain}// if $self{strip_domain};

	$hosts{$ipobj->id}{name} = $name;
	push @{ $groups{$group}{members} }, $name;
	$name2ip{$name} = $ipobj->id;
	$ip2name{$ipobj->id} = $name;
	
	# Add services (if any)
	foreach my $ipsrv ( $ipobj->services ){
	    my $srvname = $ipsrv->service->name;
	    my $srvclobj;
	    warn "Service $srvname being added to IP ",$ipobj->address, "\n" if $self{debug};
	    push  @{ $servicegroups{$srvname}{members} }, $name ;
	    
	    # If service has a contactlist, use that
	    # if not, use the associated IP's contactlists
	    #
	    my $srvclobj;
	    if ( ($srvclobj = $ipsrv->contactlist) != 0 ) {
		push @{ $services{$name}{$srvname}{contactlists} }, $srvclobj;
		$contactlists{$srvclobj->id}{name} = join '_', split /\s+/, $srvclobj->name;
		$contactlists{$srvclobj->id}{obj}  = $srvclobj;
		warn "Contactlist ". $srvclobj->name ." assigned to service $srvname for IP ".
		    $ipobj->address ."\n" if $self{debug};
	    }elsif( $hosts{$ipobj->id}{contactlists} ){
		$services{$name}{$srvname}{contactlists} = $hosts{$ipobj->id}{contactlists};
	    }else{
		warn "Service $srvname for IP ". $ipobj->address ." has no contactlist defined\n" 
		    if $self{debug};
	    }
	    # Add the SNMP community in case it's needed
	    $services{$name}{$srvname}{community} =  $ipobj->interface->device->community;
	}
    } #foreach ip
    
    # Now that we have everybody in, assign parent list.
    my $dependencies = $export->get_dependencies($monitor->id);
    foreach my $ipid ( keys %hosts ){
	next unless defined $dependencies->{$ipid};
	if ( my @parentlist = @{$dependencies->{$ipid}} ){
	    my @names;
	    foreach my $parent ( @parentlist ){
		if ( !exists $ip2name{$parent} ){
		    warn "IP $ipid parent $parent not in monitored list."
			." Skipping.\n";
		    next;
		}
		push @names, $ip2name{$parent};
	    }
	    $hosts{$ipid}{parents} = join ',', @names;
	}else{
	    $hosts{$ipid}{parents} = undef;
	}
    }

    print Dumper(%hosts) if $self{debug};

    
    # Classify contacts by their escalation-level
    # We'll create a contactgroup for each level
    
    foreach my $clid ( keys %contactlists ){
	my $clobj = $contactlists{$clid}{obj};
	
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
    print Dumper(%groups) if $self{debug};   

}

##################################################
sub build_configs{
    
    foreach my $file ( @{ $self{files_array} } ){
	# Open skeleton file for reading
	my $skel_file = "$self{dir}/$file.$self{skel_ext}";
	open (SKEL, "$skel_file") or die "Can't open $skel_file\n";
	
	# Open output file for writing
	my $out_file = "$self{dir}/$file.$self{cfg_ext}";
	open (OUT, ">$out_file") or die "Can't open $out_file\n";
	select (OUT);
	
	while (<SKEL>){
	    if (/<INSERT DATE>/){
		print "#\t-- Generated by $0 on ", scalar localtime,  "--\n" ;
		
	    }elsif (/<INSERT HOST DEFINITIONS>/){
		
		foreach my $ipid ( keys %hosts ){
		    my $name = $hosts{$ipid}{name};
		    my $ip       = $hosts{$ipid}{ip};
		    my $group    = $hosts{$ipid}{group};
		    my $parents  = $hosts{$ipid}{parents};
		    my @cls      = @{ $hosts{$ipid}{contactlists} } if $hosts{$ipid}{contactlists};
		    
		    my %levels;
		    if ( @cls ) {
			# This will make sure we're looping through the highest level number
			map { map { $levels{$_} = '' } keys %{ $contactlists{$_->id}{level} } } @cls;
		    }else{
			warn "Host $name (IP id $ipid) does not have a valid Contact Group!\n";
		    }

		    if ( keys %levels ){
			my $first   = 1;
			my $fn      = $self{first_notif};
			my $ln      = $self{last_notif};
			
			foreach my $level ( sort keys %levels ){
			    my @contact_groups;
			    foreach my $cl ( @cls ){
				# Make sure this contact list has this level defined
				if( $contactlists{$cl->id}{level}{$level} ){
				    push @contact_groups, "$contactlists{$cl->id}{name}" . "-level_$level";
				}
			    }
			    my $contact_groups = join ',', @contact_groups;
			    
			    if ( $first ){
				print "define host{\n";
				print "\tuse                    generic-host\n";
				print "\thost_name              $name\n";
				print "\talias                  $group\n";
				print "\taddress                $ip\n";
				print "\tparents                $parents\n" if ($parents);
				print "\tcontact_groups         $contact_groups\n";
				print "}\n\n";
				if ( $self{traps} ){
				    print "define service{\n";
				    print "\tuse                     generic-trap\n";
				    print "\thost_name               $name\n";
				    print "\tcontact_groups          $contact_groups\n";
				    print "}\n\n";
				}
				$first = 0;
			    }else{
				print "define hostescalation{\n";
				print "\thost_name                $name\n";
				print "\tfirst_notification       $fn\n";
				print "\tlast_notification        $ln\n";
				print "\tnotification_interval    $self{notif_interval}\n";
				print "\tcontact_groups           $contact_groups\n";
				print "}\n\n";
				
				if ( $self{traps} ){
				    print "define serviceescalation{\n";
				    print "\thost_name                $name\n";
				    print "\tservice_description      TRAP\n";
				    print "\tfirst_notification       $fn\n";
				    print "\tlast_notification        $ln\n";
				    print "\tnotification_interval    $self{notif_interval}\n";
				    print "\tcontact_groups           $contact_groups\n";
				    print "}\n\n";
				}
				
				$fn += $ln - $fn + 1;
				$ln += $ln - $fn + 1;
			    }
			}   
			
		    }
		    if ( !@cls || ! keys %levels ){
			print "define host{\n";
			print "\tuse                    generic-host\n";
			print "\thost_name              $name\n";
			print "\talias                  $group\n";
			print "\taddress                $ip\n";
			print "\tparents                $parents\n" if ($parents);
			print "\tcontact_groups         nobody\n";
			print "}\n\n";
			
			if ( $self{addtraps} ){
			    # Define a TRAP service for every host
			    print "define service{\n";
			    print "\tuse                    generic-trap\n";
			    print "\thost_name              $name\n";
			    print "\tcontact_groups         nobody\n";
			    print "}\n\n";
			}
		    }
		    
		    if ( $self{rtt} ){
			# Define RTT (Round Trip Time) as a service
			print "define service{\n";
			print "\thost_name              $name\n";
			print "\tuse                    generic-RTT\n";
			print "}\n\n";
			
			print "define serviceextinfo{\n";
			print "\thost_name              $name\n";
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
			print "\thost_name              $name\n";
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
			    if ( int($contact->notify_email) ){
				if ( exists($self{timeperiods}{$contact->notify_email->name}) ){
				    if ((my $emailperiod = $self{timeperiods}{$contact->notify_email->name}) ne 'none' ){
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
				    warn $contact->notify_email->name, " is not a defined timeperiod\n" 
					if ($self{debug});
				}
			    }
			    # And one for paging
			    if ( int($contact->notify_pager) ){
				if ( exists($self{timeperiods}{$contact->notify_pager->name}) ){
				    if ((my $pagerperiod = $self{timeperiods}{$contact->notify_pager->name}) ne 'none' ){
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
				    warn $contact->notify_pager->name, " is not a defined timeperiod\n" 
					if ($self{debug});
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
		
		foreach my $name ( keys %services ){
		    foreach my $srvname ( keys %{ $services{$name} } ){
			if (! exists $self{servchecks}{$srvname}){
			    warn "Warning: service check for $srvname not implemented.";
			    warn "Skipping $srvname check for host $name.\n";
			    next;
			}
			my $checkcmd = $self{servchecks}{$srvname};
			
			# Add community argument for checks that use SNMP
			if ( $checkcmd eq "check_bgp"){
			    $checkcmd .= "!$services{$name}{$srvname}{community}";
			}
			my @cls = @{ $services{$name}{$srvname}{contactlists} } 
			if $services{$name}{$srvname}{contactlists};
			
			my %levels;
			if ( @cls ){
			    # This will make sure we're looping through the highest level number
			    map { map { $levels{$_} = '' } keys %{ $contactlists{$_->id}{level} } } @cls;
			}else{
			    warn "Service ". $srvname  ." on ". $name 
				." does not have a valid Contact Group\n";
			}
			if ( keys %levels ){
			    my $first  = 1;
			    my $fn     = $self{first_notif};
			    my $ln     = $self{last_notif};
			    
			    foreach my $level ( sort keys %levels ){
				my @contact_groups;
				foreach my $cl ( @cls ){
				    # Make sure this contact list has this level defined
				    if( $contactlists{$cl->id}{level}{$level} ){
					push @contact_groups, "$contactlists{$cl->id}{name}" . "-level_$level";
				    }
				}
				my $contact_groups = join ',', @contact_groups;
				
				foreach my $level ( sort keys %levels ){
				    
				    if ($first){
					print "define service{\n";
					print "\tuse                  generic-service\n";
					print "\thost_name            $name\n";
					print "\tservice_description  $srvname\n";
					print "\tcontact_groups       $contact_groups\n";
					print "\tcheck_command        $checkcmd\n";
					print "}\n\n";
					
					$first = 0;
				    }else{
					
					print "define serviceescalation{\n";
					print "\thost_name                $name\n";
					print "\tservice_description      $srvname\n";
					print "\tfirst_notification       $fn\n";
					print "\tlast_notification        $ln\n";
					print "\tnotification_interval    $self{notif_interval}\n";
					print "\tcontact_groups           $contact_groups\n";
					print "}\n\n";
					
					$fn += $ln - $fn + 1;
					$ln += $ln - $fn + 1;
				    }
				}	   
			    }
			}
			if ( ! @cls || ! keys %levels ){
			    
			    print "define service{\n";
			    print "\tuse                  generic-service\n";
			    print "\thost_name            $name\n";
			    print "\tservice_description  $srvname\n";
			    print "\tcontact_groups       nobody\n";
			    print "\tcheck_command        $checkcmd\n";
			    print "}\n\n";
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
}
