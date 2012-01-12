package Netdot::Exporter::Nagios;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::Nagios - Read relevant info from Netdot and build Nagios2 configuration

=head1 SYNOPSIS

    my $nagios = Netdot::Exporter->new(type=>'Nagios');
    $nagios->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Exporter::Nagios object
  Examples:
    my $nagios = Netdot::Exporter->new(type=>'Nagios');
=cut

sub new{
    my ($class, %argv) = @_;
    my $self = {};

    foreach my $key ( qw /NMS_DEVICE NAGIOS_CHECKS NAGIOS_TIMEPERIODS NAGIOS_DIR NAGIOS_FILE NAGIOS_NOTIF_FIRST 
                          NAGIOS_NOTIF_LAST NAGIOS_NOTIF_INTERVAL NAGIOS_TRAPS NAGIOS_STRIP_DOMAIN/ ){
	$self->{$key} = Netdot->config->get($key);
    }
     
    $self->{NAGIOS_NOTIF_FIRST} ||= 4;
    $self->{NAGIOS_NOTIF_LAST}  ||= 6;

    defined $self->{NMS_DEVICE} ||
	$self->throw_user("Netdot::Exporter::Nagios: NMS_DEVICE not defined");

    $self->{ROOT} = Device->search(name=>$self->{NMS_DEVICE})->first ||
	$class->throw_user("Netdot::Exporter::Nagios: Monitoring device '" . $self->{NMS_DEVICE}. "' not found in DB");
    
    $self->{NAGIOS_FILE} || 
	$class->throw_user("Netdot::Exporter::Nagios: NAGIOS_FILE not defined");
    
    # Open output file for writing
    $self->{filename} = $self->{NAGIOS_DIR}."/".$self->{NAGIOS_FILE};

    bless $self, $class;

    $self->{out} = $self->open_and_lock($self->{filename});
    return $self;
}

############################################################################
=head2 generate_configs - Generate configuration files for Nagios

  Arguments:
    None
  Returns:
    True if successful
  Examples:
    $nagios->generate_configs();
=cut
sub generate_configs {
    my ($self) = @_;
    
    my ( %hosts, %groups, %contacts, %contactlists, %services, %servicegroups );

    # Get Subnet info
    my %subnet_info;
    my $subnetq = $self->{_dbh}->selectall_arrayref("
                  SELECT    ipblock.id, ipblock.description, entity.name
                  FROM      ipblockstatus, ipblock
                  LEFT JOIN entity ON (ipblock.used_by=entity.id)
                  WHERE     ipblock.status=ipblockstatus.id 
                        AND (ipblockstatus.name='Subnet' OR ipblockstatus.name='Container')
                 ");
    foreach my $row ( @$subnetq ){
	my ($id, $descr, $entity) = @$row;
	$subnet_info{$id}{entity}      = $entity if defined $entity;
	$subnet_info{$id}{description} = $descr;
    }

    # Get Contact Info
    my %contact_info;
    my $clq = $self->{_dbh}->selectall_arrayref("
                  SELECT    contactlist.id, contactlist.name,
                            contact.id, contact.escalation_level, 
                            person.firstname, person.lastname, person.email, person.emailpager,
                            email_period.name, pager_period.name
                  FROM      contactlist, person, contact
                  LEFT JOIN availability email_period ON (email_period.id=contact.notify_email)
                  LEFT JOIN availability pager_period ON (pager_period.id=contact.notify_pager)
                  WHERE     contact.contactlist=contactlist.id
                      AND   contact.person=person.id
                 ");
    foreach my $row ( @$clq ){
	my ($clid, $clname, $contid, $esc_level,
	    $person_first, $person_last, $email, $pager, 
	    $email_period, $pager_period) = @$row;
	$contact_info{$clid}{name} = $clname;
	my $contname;
	$contname = $person_first if defined $person_first;
	$contname .= ' '.$person_last if defined $person_last;
	if ( $contname ){
	    $contname =~ s/^\s*(.*)\s*$/$1/;
	    $contname =~ s/\s+/_/g;
	}
	if ( $contid ){
	    $contact_info{$clid}{contact}{$contid}{name}         = $contname;
	    $contact_info{$clid}{contact}{$contid}{email}        = $email;
	    $contact_info{$clid}{contact}{$contid}{pager}        = $pager;
	    $contact_info{$clid}{contact}{$contid}{esc_level}    = $esc_level;
	    $contact_info{$clid}{contact}{$contid}{email_period} = $email_period;
	    $contact_info{$clid}{contact}{$contid}{pager_period} = $pager_period;
	}
    }

     # Classify contacts by their escalation-level
     # We'll create a contactgroup for each level
     foreach my $clid ( keys %contact_info ){
 	foreach my $contid ( keys %{$contact_info{$clid}{contact}} ){
	    my $contact = $contact_info{$clid}{contact}{$contid};
 	    # Skip if no availability
 	    next if ( (!$contact->{email_period} || $contact->{email_period} eq "Never") && 
 		      (!$contact->{pager_period} || $contact->{pager_period} eq "Never") );
	    
 	    # Get common info and store it separately
 	    # to create a template
	    my $name = $contact->{name};
 	    if ( !exists ($contacts{$name}) ){
		$contacts{$name} = $contact;
 	    }

 	    # Then group by escalation level
 	    my $level = $contact->{esc_level} || 0;
 	    $contactlists{$clid}{level}{$level}{$contid} = $contact;
	}
     }

    $self->{contactlists} = \%contactlists;
    $self->{contacts}     = \%contacts;

    # Get Service info
    my %service_info;
    my $serviceq = $self->{_dbh}->selectall_arrayref("
                  SELECT    ipblock.id, service.id, service.name, 
                            ipservice.monitored, ipservice.contactlist
                  FROM      ipblock, ipservice, service
                  WHERE     ipservice.ip=ipblock.id 
                    AND     ipservice.service=service.id
                 ");
    foreach my $row ( @$serviceq ){
	my ($ipid, $service_id, $service_name, $monitored, $clid) = @$row;
	$service_info{$ipid}{$service_id}{name} = $service_name;
	$service_info{$ipid}{$service_id}{monitored} = $monitored;
	$service_info{$ipid}{$service_id}{contactlist} = $clid if $clid;
    }
	
    my $device_info    = $self->get_device_info();
    my $int2device     = $self->get_int2device();
    my $intid2ifindex  = $self->get_intid2ifindex();
    my $device_parents = $self->get_device_parents($self->{ROOT});
    my $iface_graph    = $self->get_interface_graph();
    
    ######################################################################################
    foreach my $devid ( sort { $device_info->{$a}->{hostname} 
			       cmp $device_info->{$b}->{hostname} 
			   } keys %$device_info ){
	my %hostargs;
	
	# Is it within downtime period
	my $monitored = (!$self->in_downtime($devid))? 1 : 0;
	next unless $monitored;

	# Determine name
	my $hostname = $device_info->{$devid}->{hostname} || next;
	$hostargs{name} = $self->strip_domain($hostname);

	# Determine IP
	$hostargs{ip} = $self->get_device_main_ip($devid);
	unless ( $hostargs{ip} ){
	    $logger->warn("Cannot determine IP address for $hostname. Skipping");
	    next;
	}

  	# Determine the group name
 	my $group;
	if ( my $subnet = $device_info->{$devid}->{subnet} ){
	    $group = $subnet_info{$subnet}->{entity} || 
		$subnet_info{$subnet}->{description};
	}
	unless ( $group ){ 
	    if ( my $entity = $device_info->{$devid}->{used_by} ){
		$group = $entity;
	    }
	}
 	unless ( $group ){
 	    $logger->warn("Device $hostname in unknown group");
 	    $group = "Unknown";
 	}
 	# Remove illegal chars
 	$group =~ s/[\(\),]//g;  
 	$group =~ s/^\s*(.)\s*$/$1/;
 	$group =~ s/[\/\s]/_/g;  
 	$group =~ s/&/and/g;     
 	$hostargs{group} = $group;

	# Contact Lists
	my @clids;
	if ( @clids = keys %{$device_info->{$devid}->{contactlist}} ){
	    foreach my $clid ( @clids ){
		unless ( exists $contact_info{$clid} ){
		    $logger->warn("Device $hostname ContactList id $clid not valid (no contacts?)");
		    next;
		}
		next unless defined $contact_info{$clid}{name};
		$contactlists{$clid}{name} = $contact_info{$clid}{name};
		$contactlists{$clid}{name} =~ s/\s+/_/g;
		push @{$hostargs{contactlists}}, $clid;
	    }
	}

	# Host Parents
	my @parent_names;
	foreach my $d ( $self->get_monitored_ancestors($devid, $device_parents) ){
	    my $name = $self->strip_domain($device_info->{$d}->{hostname});
	    push @parent_names, $name;
	}
	if ( @parent_names && defined $parent_names[0] ){
	    $hostargs{parents} = join ',', @parent_names;    
	}

	push @{ $groups{$group}{members} }, $hostargs{name};
	$self->print_host(%hostargs);

 	# Add monitored services on the target IP
	my $target_ip = $device_info->{$devid}->{ipid};
	if ( defined $target_ip && exists $service_info{$target_ip} ){
	    foreach my $servid ( keys %{$service_info{$target_ip}} ){
		next unless ( $service_info{$target_ip}->{$servid}->{monitored} );
		my %args;
		$args{hostname} = $hostargs{name};
		my $srvname = $service_info{$target_ip}->{$servid}->{name};
		$args{srvname} = $srvname;

		# Add service to servicegroup
		push  @{ $servicegroups{$srvname}{members} }, $hostargs{name};

		# Add community if SNMP managed
		if ( $device_info->{$devid}->{snmp_managed} ){
		    $args{community} = $device_info->{$devid}->{community};
		}
		
		# If service has a contactlist, use that
		# if not, use Device contactlists
		my @cls;
		if ( my $srvcl = $service_info{$target_ip}->{contactlist} ){
		    push @cls, $srvcl;
		}else{
		    push @cls, @clids;
		}
		$args{contactlists} = \@cls if @cls;
		$self->print_service(%args);
	    }
	}

	# Services monitored via SNMP
	if ( $device_info->{$devid}->{snmp_managed} ){

	    # Add a bgppeer service check for each monitored BGP peering
	    foreach my $peeraddr ( keys %{$device_info->{$devid}->{peering}} ){
		my $peering = $device_info->{$devid}->{peering}->{$peeraddr};
		next unless ( $peering->{monitored} );
		my %args;
		$args{hostname}     = $hostargs{name};
		$args{peeraddr}     = $peeraddr;
		$args{srvname}      = "BGPPEER";
		$args{community}    = $device_info->{$devid}->{community};
		$args{contactlists} = \@clids;
		$self->print_service(%args);
	    }
	    
	    # Add a ifstatus service check for each monitored interface
	    foreach my $ifid ( keys %{$device_info->{$devid}->{interface}} ){
		my $iface = $device_info->{$devid}->{interface}->{$ifid};
		if ( $iface->{monitored} && defined $iface->{admin} && $iface->{admin} eq 'up' ){
		    my %args;
		    $args{hostname}  = $hostargs{name};
		    $args{ifindex}   = $iface->{number};
		    $args{srvname}   = "IFSTATUS";
		    $args{community} = $device_info->{$devid}->{community};

		    # If interface has a contactlist, use that, otherwise use Device contactlists
		    my @cls;
		    if ( my $intcl = $iface->{contactlist} ){
			push @cls, $intcl;
		    }else{
			push @cls, @clids;
		    }
		    $args{contactlists} = \@cls if @cls;

		    # Determine parent service for service dependency.  If neighbor interface is monitored, 
		    # and belongs to parent make ifstatus service on that interface the parent.  
		    # Otherwise, make the ping service of the parent host the parent.
		    if ( my $neighbor = $iface_graph->{$ifid} ){
			my $nd = $int2device->{$neighbor};
			if ( $nd && $device_parents->{$devid}->{$nd} ){
			    # Neighbor device is my parent
			    if ( exists $device_info->{$nd} ){
				if ( $device_info->{$nd}->{interface}->{$neighbor}->{monitored} ){
				    if ( my $nifindex = $intid2ifindex->{$neighbor} ){
					$args{parent_host}    = $self->strip_domain($device_info->{$nd}->{hostname});
					$args{parent_service} = "IFSTATUS_$nifindex";
				    }
				}else{
				    $args{parent_host}    = $self->strip_domain($device_info->{$nd}->{hostname});
				    $args{parent_service} = 'PING';
				}
			    }else{
				# Look for grandparents then
				if ( my @parents = $self->get_monitored_ancestors($nd, $device_parents) ){
				    my $p = $parents[0]; # Just grab the first one for simplicity
				    $args{parent_host}    = $self->strip_domain($device_info->{$p}->{hostname});
				    $args{parent_service} = 'PING';
				}
			    }
			}
		    }
		    $self->print_service(%args);
		}
	    }
	}
	
    }

    $self->print_hostgroups(\%groups);
    $self->print_servicegroups(\%servicegroups);
    $self->print_contacts();

    $logger->info("Netdot::Exporter::Nagios: Configuration written to file: ".$self->{filename});
    close($self->{out});
}


#####################################################################################
sub print_host {
    my ($self, %argv) = @_;

    my $name      = $argv{name};
    my $ip        = $argv{ip};
    my $group     = $argv{group};
    my $parents   = $argv{parents};
    my @cls       = @{ $argv{contactlists} } if $argv{contactlists};
    my $out       = $self->{out};

    my $contactlists = $self->{contactlists};
    my %levels;
    if ( @cls ) {
	# This will make sure we're looping through the highest level number
	map { map { $levels{$_} = '' } keys %{$contactlists->{$_}->{level}} } @cls;
    }else{
	$logger->warn("Host $name (IP $ip) does not have a valid Contact Group!");
    }
    print $out "########################################################################\n";
    print $out "# host $name\n";
    print $out "########################################################################\n";
	
    if ( keys %levels ){
	my $first   = 1;
	my $fn      = $self->{NAGIOS_NOTIF_FIRST};
	my $ln      = $self->{NAGIOS_NOTIF_LAST};

	foreach my $level ( sort { $a <=> $b } keys %levels ){
	    my @contact_groups;
	    foreach my $clid ( @cls ){
		# Make sure this contact list has this level defined
		if( $contactlists->{$clid}->{level}->{$level} ){
		    push @contact_groups, $contactlists->{$clid}->{name} . "-level_$level";
		}
	    }
	    my $contact_groups = join ',', @contact_groups;
	    
	    if ( $first ){
		print $out "define host{\n";
		print $out "\tuse                    generic-host\n";
		print $out "\thost_name              $name\n";
		print $out "\talias                  $group\n";
		print $out "\taddress                $ip\n";
		print $out "\tparents                $parents\n" if ($parents);
		print $out "\tcontact_groups         $contact_groups\n";
		print $out "}\n\n";
		if ( $self->{NAGIOS_TRAPS} ){
		    print $out "define service{\n";
		    print $out "\tuse                     generic-trap\n";
		    print $out "\thost_name               $name\n";
		    print $out "\tcontact_groups          $contact_groups\n";
		    print $out "}\n\n";
		}
		$first = 0;
	    }else{
		print $out "define hostescalation{\n";
		print $out "\thost_name                $name\n";
		print $out "\tfirst_notification       $fn\n";
		print $out "\tlast_notification        $ln\n";
		print $out "\tnotification_interval    ".$self->{NAGIOS_NOTIF_INTERVAL}."\n";
		print $out "\tcontact_groups           $contact_groups\n";
		print $out "}\n\n";
		
		if ( $self->{NAGIOS_TRAPS} ){
		    print $out "define serviceescalation{\n";
		    print $out "\thost_name                $name\n";
		    print $out "\tservice_description      TRAP\n";
		    print $out "\tfirst_notification       $fn\n";
		    print $out "\tlast_notification        $ln\n";
		    print $out "\tnotification_interval    ".$self->{NAGIOS_NOTIF_INTERVAL}."\n";
		    print $out "\tcontact_groups           $contact_groups\n";
		    print $out "}\n\n";
		}
		
		$fn += $ln - $fn + 1;
		$ln += $ln - $fn + 1;
	    }
	}   
	
    }
    if ( !@cls || !keys %levels ){
	print $out "define host{\n";
	print $out "\tuse                    generic-host\n";
	print $out "\thost_name              $name\n";
	print $out "\talias                  $group\n";
	print $out "\taddress                $ip\n";
	print $out "\tparents                $parents\n" if ($parents);
	print $out "\tcontact_groups         nobody\n";
	print $out "}\n\n";
	
	if ( $self->{NAGIOS_TRAPS} ){
	    # Define a TRAP service for every host
	    print $out "define service{\n";
	    print $out "\tuse                     generic-trap\n";
	    print $out "\thost_name               $name\n";
	    print $out "\tcontact_groups          nobody\n";
	    print $out "}\n\n";
	}
    }
    
    # Add ping service for every host
    print $out "define service{\n";
    print $out "\tuse                    generic-ping\n";
    print $out "\thost_name              $name\n";
    print $out "}\n\n";

}

#####################################################################################
sub print_service {
    my ($self, %argv) = @_;
    my ($hostname, $srvname) = @argv{'hostname', 'srvname'};

    my $checkcmd;
    unless ( $checkcmd = $self->{NAGIOS_CHECKS}{$srvname} ){
	$logger->warn("Service check for $srvname not implemented." . 
		      " Skipping $srvname check for host $hostname.");
	return;
    }

    my @cls = @{ $argv{contactlists} } if $argv{contactlists};
    my $out = $self->{out};
    my $contactlists = $self->{contactlists};

    
    if ( $srvname eq "BGPPEER" || $srvname eq "IFSTATUS" ){
	if ( my $community = $argv{community} ){
	    $checkcmd .= "!$community";				
	}else{
	    $logger->warn("Service check for $srvname requires a SNMP community." .
			  " Skipping $srvname check for host $hostname.");
	    return;
	}
    }
    if ( $srvname eq "IFSTATUS" ){
	my $ifindex;
	unless ( $ifindex = $argv{ifindex} ){
	    $logger->warn("Service check for $srvname requires ifindex." . 
			  " Skipping $srvname check for host $hostname.");
	    return;
	}
	$srvname  .= "_$ifindex"; # Make the service name unique
	$checkcmd .= "!$ifindex"; # Pass the argument to the check command
    }

    if ( $srvname eq "BGPPEER" ){
	my $peeraddr;
	unless ( $peeraddr = $argv{peeraddr} ){
	    $logger->warn("Service check for $srvname requires peeraddr." . 
			  " Skipping $srvname check for host $hostname.");
	    return;
	}
	$srvname  .= "_$peeraddr"; # Make the service name unique
	$checkcmd .= "!$peeraddr"; # Pass the argument to the check command
    }
    
    my %levels;
    if ( @cls ){
	# This will make sure we're looping through the highest level number
	map { map { $levels{$_} = '' } keys %{ $contactlists->{$_}->{level} } } @cls;
    }else{
	$logger->warn("Service ". $srvname  ." on ". $hostname .
		      " does not have a valid Contact Group");
    }
    if ( keys %levels ){
	my $first  = 1;
	my $fn     = $self->{NAGIOS_NOTIF_FIRST};
	my $ln     = $self->{NAGIOS_NOTIF_LAST};
	
	foreach my $level ( sort { $a <=> $b } keys %levels ){
	    my @contact_groups;
	    foreach my $clid ( @cls ){
		# Make sure this contact list has this level defined
		if( $contactlists->{$clid}->{level}->{$level} ){
		    push @contact_groups, $contactlists->{$clid}->{name} . "-level_$level";
		}
	    }
	    my $contact_groups = join ',', @contact_groups;
	    
	    if ( $first ){
		print $out "define service{\n";
		print $out "\tuse                   generic-service\n";
		print $out "\thost_name             $hostname\n";
		print $out "\tservice_description   $srvname\n";
		print $out "\tcontact_groups        $contact_groups\n";
		print $out "\tcheck_command         $checkcmd\n";
		print $out "}\n\n";
		
		$first = 0;
	    }else{
		print $out "define serviceescalation{\n";
		print $out "\thost_name                $hostname\n";
		print $out "\tservice_description      $srvname\n";
		print $out "\tfirst_notification       $fn\n";
		print $out "\tlast_notification        $ln\n";
		print $out "\tnotification_interval    ".$self->{NAGIOS_NOTIF_INTERVAL}."\n";
		print $out "\tcontact_groups           $contact_groups\n";
		print $out "}\n\n";
		
		$fn += $ln - $fn + 1;
		$ln += $ln - $fn + 1;
	    }
	}	   
    }
    if ( ! @cls || ! keys %levels ){
	print $out "define service{\n";
	print $out "\tuse                  generic-service\n";
	print $out "\thost_name            $hostname\n";
	print $out "\tservice_description  $srvname\n";
	print $out "\tcontact_groups       nobody\n";
	print $out "\tcheck_command        $checkcmd\n";
	print $out "}\n\n";
    }

    # Add service dependencies if needed
    if ( $argv{parent_host} && $argv{parent_service} ){
	$self->print_servicedep($hostname, $srvname, $argv{parent_host}, $argv{parent_service});
    }
}

#####################################################################################
sub print_contacts {
    my($self) = @_;
    my $out = $self->{out};
    my $contacts     = $self->{contacts};
    my $contactlists = $self->{contactlists};

    # Create the contact templates (with a person's common info)
    # A person might be a contact for several groups/events
    
    foreach my $name ( keys %$contacts ){
	print $out "define contact{\n";
	print $out "\tname                            $name\n";
	print $out "\tuse                             generic-contact\n";
	print $out "\talias                           $name\n";
	print $out "\temail                           ".$contacts->{$name}->{email}."\n" if $contacts->{$name}->{email};
	print $out "\tpager                           ".$contacts->{$name}->{pager}."\n" if $contacts->{$name}->{pager};
	print $out "\tregister                        0 ; (THIS WILL BE INHERITED LATER)\n";  
	print $out "}\n\n";
	
    }
    
    # Create specific contacts (notification periods vary in each case)
    foreach my $clid ( keys %$contactlists  ){
	my $clname = $contactlists->{$clid}->{name};
	next unless $clname;
	foreach my $level ( sort {$a <=> $b} keys %{ $contactlists->{$clid}->{level} } ){
	    my @members;
	    foreach my $contactid ( keys %{ $contactlists->{$clid}->{level}->{$level} } ){
		my $contact = $contactlists->{$clid}->{level}->{$level}->{$contactid};
		my $name    = $contact->{name};
		# One for e-mails
		if ( my $period = $contact->{email_period} ){
		    if ( exists $self->{NAGIOS_TIMEPERIODS}{$period} ){
			if ((my $emailperiod = $self->{NAGIOS_TIMEPERIODS}{$period}) ne 'none' ){
			    my $contactname = "$name-$clname-email-level_$level";
			    push @members, $contactname;
			    print $out "define contact{\n";
			    print $out "\tcontact_name                    $contactname\n";
			    print $out "\tuse                             $name\n";
			    print $out "\tservice_notification_period     $emailperiod\n";
			    print $out "\thost_notification_period        $emailperiod\n";
			    print $out "\tservice_notification_commands   notify-by-email\n";
			    print $out "\thost_notification_commands      host-notify-by-email\n";
			    print $out "}\n\n";
			}
		    }else{
			$logger->warn("$period is not a defined timeperiod");
		    }
		}
		# And one for paging
		if ( my $period = $contact->{pager_period} ){
		    if ( exists($self->{NAGIOS_TIMEPERIODS}{$period}) ){
			if ((my $pagerperiod = $self->{NAGIOS_TIMEPERIODS}{$period}) ne 'none' ){
			    my $contactname = "$name-$clname-pager-level_$level";
			    push @members, $contactname;
			    print $out "define contact{\n";
			    print $out "\tcontact_name                    $contactname\n";
			    print $out "\tuse                             $name\n";
			    print $out "\tservice_notification_period     $pagerperiod\n";
			    print $out "\thost_notification_period        $pagerperiod\n";
			    print $out "\tservice_notification_commands   notify-by-epager\n";
			    print $out "\thost_notification_commands      host-notify-by-epager\n";
			    print $out "}\n\n";
			}
		    }else{
			$logger->warn("$period is not a defined timeperiod");
		    }
		}
	    }
	    # Create the contactgroup
	    my $members = join ',', @members;
	    
	    print $out "define contactgroup{\n";
	    print $out "\tcontactgroup_name       $clname-level_$level\n";
	    print $out "\talias                   $clname\n";
	    print $out "\tmembers                 $members\n";
	    print $out "}\n\n";
	}
    }
}


#####################################################################################
sub print_hostgroups{
    my ($self, $groups) = @_;

    my $out = $self->{out};
    foreach my $group ( keys %$groups ){
	my $hostlist = join ',', @{ $groups->{$group}->{members} };
	print $out "define hostgroup{\n";
	print $out "\thostgroup_name      $group\n";
	print $out "\talias               $group\n";
	print $out "\tmembers             $hostlist\n";
	print $out "}\n\n";
    }
}

#####################################################################################
sub print_servicegroups{
    my ($self, $groups) = @_;

    my $out = $self->{out};
    foreach my $group ( keys %$groups ){
	# servicegroup members are like:
	# members=<host1>,<service1>,<host2>,<service2>,...,
	my $hostlist = join ',', map { "$_,$group" }@{ $groups->{$group}{members} };
	print $out "define servicegroup{\n";
	print $out "\tservicegroup_name      $group\n";
	print $out "\talias                  $group\n";
	print $out "\tmembers                $hostlist\n";
	print $out "}\n\n";
    }
}

#####################################################################################
sub print_servicedep{
    my ($self, $hostname, $service, $parent_hostname, $parent_service) = @_;

    my $out = $self->{out};
    print $out "define servicedependency{\n";
    print $out "\tdependent_host_name            $hostname\n";
    print $out "\tdependent_service_description  $service\n";
    print $out "\thost_name                      $parent_hostname\n";
    print $out "\tservice_description            $parent_service\n";
    print $out "\tinherits_parent                1\n";
    # Do not check if parent is in Critical, Warning, Unknown or Pending state
    print $out "\texecution_failure_criteria	 c,w,u,p\n"; 
    print $out "}\n\n";
}

############################################################################
=head2 get_interface_graph

  Arguments:
    None
  Returns:
    Hash reference
  Examples:

=cut
sub get_interface_graph {
    my ($self) = @_;

    $logger->debug("Netdot::Exporter::get_interface_graph: querying database");
    my $graph = {};
    my $links = $self->{_dbh}->selectall_arrayref("
                SELECT  i1.id, i2.id 
                FROM    interface i1, interface i2
                WHERE   i2.neighbor = i1.id AND i1.neighbor = i2.id
            "); 
    foreach my $link ( @$links ) {
	my ($fr, $to) = @$link;
	$graph->{$fr} = $to;
	$graph->{$to} = $fr;
    }
    
    return $graph;
}

########################################################################
=head2 get_int2device - Interface id to Device id mapping

  Arguments:
    None
  Returns:
    Hash reference
  Examples:
    
=cut
sub get_int2device {
    my ($self) = @_;

    my $device_info = $self->get_device_info();
    my %map;
    foreach my $dev ( keys %$device_info ){
	foreach my $int ( keys %{$device_info->{$dev}->{interface}} ){
	    $map{$int} = $dev;
	}
    }
    return \%map;
}

########################################################################
=head2 get_intid2ifindex - Interface id to ifIndex mapping

  Arguments:
    None
  Returns:
    Hash reference
  Examples:
    
=cut
sub get_intid2ifindex {
    my ($self) = @_;

    my $device_info = $self->get_device_info();
    my %map;
    foreach my $dev ( keys %$device_info ){
	foreach my $int ( keys %{$device_info->{$dev}->{interface}} ){
	    $map{$int} = $device_info->{$dev}->{interface}->{$int}->{number};
	}
    }
    return \%map;
}

########################################################################
=head2 strip_domain - Strip domain name from hostname if necessary

  Arguments:
    hostname string
  Returns:
    string
  Examples:
    
=cut
sub strip_domain {
    my ($self, $hostname) = @_;

    return unless $hostname;
    if ( Netdot->config->get('NAGIOS_STRIP_DOMAIN') ){
	my $domain = Netdot->config->get('DEFAULT_DNSDOMAIN');
	$hostname =~ s/\.$domain// ;
    }
    return $hostname;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut

#Be sure to return 1
1;
