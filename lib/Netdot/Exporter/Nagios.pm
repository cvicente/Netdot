package Netdot::Exporter::Nagios;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

my $dbh = Netdot::Model->db_Main();

=head1 NAME

Netdot::Exporter::Nagios

=head1 DESCRIPTION

Read relevant info from Netdot and build Nagios2 configuration

=head1 SYNOPSIS

    my $nagios = Netdot::Exporter->new(type=>'Nagios');
    $nagios->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################

=head2 new - Class constructor

  Arguments:
    See Default.conf Nagios section.
    Any explicitely passed arguments override config file
  Returns:
    Netdot::Exporter::Nagios object
  Examples:
    my $nagios = Netdot::Exporter->new(type=>'Nagios');
=cut

sub new{
    my ($class, %argv) = @_;
    my $self = {};

    foreach my $key ( qw /NMS_DEVICE NAGIOS_CHECKS NAGIOS_TIMEPERIODS NAGIOS_DIR 
                          NAGIOS_FILE NAGIOS_NOTIF_FIRST NAGIOS_NOTIF_LAST 
                          NAGIOS_NOTIF_INTERVAL NAGIOS_TRAPS NAGIOS_STRIP_DOMAIN
                          NAGIOS_TEMPLATES NAGIOS_HOSTGROUP_NAME_FIELD 
                          NAGIOS_HOSTGROUP_ALIAS_FIELD/ ){
	$self->{$key} = (exists $argv{$key})? $argv{$key} : Netdot->config->get($key);
    }
     
    $self->{NAGIOS_NOTIF_FIRST} ||= 4;
    $self->{NAGIOS_NOTIF_LAST}  ||= 6;

    defined $self->{NMS_DEVICE} ||
	$self->throw_user("Netdot::Exporter::Nagios: NMS_DEVICE not defined");

    $self->{ROOT} = Device->search(name=>$self->{NMS_DEVICE})->first ||
	$class->throw_user("Netdot::Exporter::Nagios: Monitoring device '" . $self->{NMS_DEVICE}. 
			   "' not found in DB");
    
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
    
    my ( %hostnames, %hosts, %groups, %contacts, %contactlists, %servicegroups );

    # Get Subnet info
    my %subnet_info;
    my $subnetq = $dbh->selectall_arrayref("
                  SELECT    ipblock.id, ipblock.description, entity.name, entity.aliases
                  FROM      ipblockstatus, ipblock
                  LEFT JOIN entity ON (ipblock.used_by=entity.id)
                  WHERE     ipblock.status=ipblockstatus.id 
                        AND (ipblockstatus.name='Subnet' OR ipblockstatus.name='Container')
                 ");
    foreach my $row ( @$subnetq ){
	my ($id, $descr, $entity_name, $entity_alias) = @$row;
	$subnet_info{$id}{entity_name} = $entity_name if defined $entity_name;
	$subnet_info{$id}{entity_alias} = $entity_alias if defined $entity_alias;
	$subnet_info{$id}{description} = $descr;
    }

    # Get Contact Info
    my %contact_info;
    my $clq = $dbh->selectall_arrayref("
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
	$clname =~ s/\s+/_/g;
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
	    $contactlists{$clid}{name} = $contact_info{$clid}{name};
 	    $contactlists{$clid}{level}{$level}{$contid} = $contact;
	}
    }

    $self->{contactlists} = \%contactlists;
    $self->{contacts}     = \%contacts;
    
    my $device_info    = $self->get_device_info();

    my $int2device     = $self->get_int2device();
    my $intid2ifindex  = $self->get_intid2ifindex();
    my $device_parents = $self->get_device_parents($self->{ROOT});
    my $iface_graph    = $self->get_interface_graph();
    
    ######################################################################################
    foreach my $devid ( sort keys %$device_info ){

	# We already search for monitored devices only in get_device_info()
	# Is it within downtime period?
	my $monitored = (!$self->in_downtime($devid))? 1 : 0;
	next unless $monitored;

	my $devh = $device_info->{$devid};
	next unless $devh->{target_addr} && $devh->{target_version};
	my $ip = Ipblock->int2ip($devh->{target_addr}, $devh->{target_version});
	my $target_ip = $ip;
	$hosts{$ip}{ip} = $ip;

	# This is the device name in Netdot. 
	my $hostname = $devh->{hostname} || next;
	$hosts{$ip}{alias} = $hostname;
	$hostname = $self->strip_domain($hostname);
	unless ( exists $hostnames{$hostname} ){
	    $hosts{$ip}{name} = $hostname;
	}	
	$hosts{$ip}{name} ||= $ip;
	$hostnames{$hosts{$ip}{name}} = 1;

	# Template 
	$hosts{$ip}{use_host} = $devh->{mon_template} if defined $devh->{mon_template};

  	# Determine the hostgroup name and alias
 	my $group_name;
	my $group_alias;

	my $name_field  = $self->{NAGIOS_HOSTGROUP_NAME_FIELD};
	my $alias_field = $self->{NAGIOS_HOSTGROUP_ALIAS_FIELD};

	if ( $name_field =~ /^subnet_/o ){
	    my $nf = $name_field;
	    $nf =~ s/^subnet_//;
	    if ( my $subnet = $devh->{subnet} ){
		$group_name = $subnet_info{$subnet}->{$nf};
	    }
	}else {
	    $group_name = $devh->{$name_field};
	}
	if ( $alias_field =~ /^subnet_/o ){
	    my $af = $alias_field;
	    $af =~ s/^subnet_//;
	    if ( my $subnet = $devh->{subnet} ){
		$group_alias = $subnet_info{$subnet}->{$af};
	    }
	}else {
	    $group_alias = $devh->{$alias_field};
	}

 	$group_name  ||= "Unknown";
	$group_alias ||= "Unknown";

 	# Remove illegal chars
	$group_name = $self->_rem_illegal_chars($group_name);
	$groups{$group_name}{alias} = $group_alias;

	# Contact Lists
	my @clids;
	foreach my $clid ( keys %{$devh->{contactlist}} ){
	    my $clname = defined $contact_info{$clid}{name};
	    next unless $clname;
	    unless ( exists $contact_info{$clid} ){
		$logger->warn("Device $hostname ContactList $clname has no contacts. Skipping.");
		next;
	    }
	    $contactlists{$clid}{name} = $contact_info{$clid}{name};
	    push @clids, $clid;
	}

	# Host Parents
	my @parent_names;
	if ( (my @ancestors = $self->get_monitored_ancestors($devid, $device_parents)) ){
	    foreach my $d ( @ancestors ){
		push @parent_names, $self->strip_domain($device_info->{$d}->{hostname});
	    }
	}elsif ( (my $hd = $devh->{host_device}) ){
	    push @parent_names, $self->strip_domain($device_info->{$hd}->{hostname});
	}

	
	# Services monitored via SNMP on the target IP
	if ( $devh->{snmp_managed} ){
	    
	    # Add a bgppeer service check for each monitored BGP peering
	    foreach my $peer_addr ( keys %{$devh->{peering}} ){
		my $peering = $devh->{peering}->{$peer_addr};
		my $srvname = 'BGPPEER_'.$peer_addr;
		$srvname .= '_'. $peering->{asname} if $peering->{asname};
		$srvname = $self->_rem_illegal_chars($srvname);
		my $displayname = $peer_addr;
		$displayname .= ' '. $peering->{asname}  if $peering->{asname};
		$displayname .= ' ('.$peering->{asn}.')' if $peering->{asn};
		$hosts{$ip}{service}{$srvname}{displayname}  = $displayname;
		$hosts{$ip}{service}{$srvname}{type}         = 'BGPPEER';
		$hosts{$ip}{service}{$srvname}{hostname}     = $hosts{$ip}{name};
		$hosts{$ip}{service}{$srvname}{peer_addr}    = $peer_addr;
		$hosts{$ip}{service}{$srvname}{srvname}      = $srvname;
		$hosts{$ip}{service}{$srvname}{community}    = $devh->{community};
		my @peercls;
		if ( $peering->{contactlist} ){
		    push @peercls, $peering->{contactlist};
		}else{
		    push @peercls, @clids;
		}
		$hosts{$ip}{service}{$srvname}{contactlists} = \@peercls;
	    }
	}

	foreach my $intid ( sort keys %{$devh->{interface}} ){   
	    
	    if ( $devh->{snmp_managed} ){
		# Add a ifstatus service check for each monitored interface
		my $iface = $devh->{interface}->{$intid};
		if ( $iface->{monitored} && defined $iface->{admin} && $iface->{admin} eq 'up' ){
		    unless ( $iface->{number} ){
			$logger->warn("$hostname: interface $intid: IFSTATUS check requires ifindex");
			return;
		    }
		    my $srvname = "IFSTATUS_".$iface->{number};
		    $srvname .= "_".$iface->{name} if defined $iface->{name};
		    $srvname = $self->_rem_illegal_chars($srvname);
		    $hosts{$ip}{service}{$srvname}{type}        = 'IFSTATUS';
		    $hosts{$ip}{service}{$srvname}{hostname}    = $hosts{$ip}{name};
		    $hosts{$ip}{service}{$srvname}{ifindex}     = $iface->{number};
		    $hosts{$ip}{service}{$srvname}{srvname}     = $srvname;
		    $hosts{$ip}{service}{$srvname}{name}        = $iface->{name} if $iface->{name};
		    $hosts{$ip}{service}{$srvname}{community}   = $devh->{community};
		    if ( $iface->{name} && $iface->{description} ){
			$hosts{$ip}{service}{$srvname}{displayname} = $iface->{name}." (".$iface->{description}.")";
		    }
		    
		    # If interface has a contactlist, use that, otherwise use Device contactlists
		    my @cls;
		    if ( my $intcl = $iface->{contactlist} ){
			push @cls, $intcl;
		    }else{
			push @cls, @clids;
		    }
		    $hosts{$ip}{service}{$srvname}{contactlists} = \@cls if @cls;
		    
		    # Determine parent service for service dependency.  If neighbor interface is monitored, 
		    # and belongs to parent make ifstatus service on that interface the parent.  
		    # Otherwise, make the ping service of the parent host the parent.
		    if ( my $neighbor = $iface_graph->{$intid} ){
			my $nd = $int2device->{$neighbor};
			if ( $nd && $device_parents->{$devid}->{$nd} ){
			    # Neighbor device is my parent
			    if ( exists $device_info->{$nd} ){
				my $ndh = $device_info->{$nd};
				if ( $ndh->{interface}->{$neighbor}->{monitored} &&
				     $iface->{admin} eq 'up'){
				    if ( my $nifindex = $intid2ifindex->{$neighbor} ){
					$hosts{$ip}{service}{$srvname}{parent_host}    = $self->strip_domain($device_info->{$nd}->{hostname});
					my $p_srv = "IFSTATUS_$nifindex";
					$p_srv .= '_'.$ndh->{interface}->{$neighbor}->{name} if defined $ndh->{interface}->{$neighbor}->{name};
					$p_srv = $self->_rem_illegal_chars($p_srv);
					$hosts{$ip}{service}{$srvname}{parent_service} = $p_srv;
				    }
				}else{
				    $hosts{$ip}{service}{$srvname}{parent_host}    = $self->strip_domain($device_info->{$nd}->{hostname});
				    $hosts{$ip}{service}{$srvname}{parent_service} = 'PING';
				}
			    }else{
				# Look for grandparents then
				if ( my @parents = $self->get_monitored_ancestors($nd, $device_parents) ){
				    my $p = $parents[0]; # Just grab the first one for simplicity
				    $hosts{$ip}{service}{$srvname}{parent_host}    = $self->strip_domain($device_info->{$p}->{hostname});
				    $hosts{$ip}{service}{$srvname}{parent_service} = 'PING';
				}
			    }
			}
		    }
		}
	    }

	    foreach my $ip_id ( sort keys %{$devh->{interface}->{$intid}->{ip} } ){
		
		my $iph = $devh->{interface}->{$intid}->{ip}->{$ip_id};
		next unless $iph->{addr} && $iph->{version};
		my $ip = Ipblock->int2ip($iph->{addr}, $iph->{version});

		if ( $devh->{target_id} == $ip_id ){
		    # This is the target IP
		    if ( @parent_names && defined $parent_names[0] ){
			$hosts{$ip}{parents} = join ',', @parent_names;    
		    }
		}else{
		    # IP is not target IP. We only care about it if it's marked as monitored
		    next unless $iph->{monitored};
		    $hosts{$ip}{ip} = $ip;

		    # Parent is the host with the target IP
		    $hosts{$ip}{parents} = $hosts{$target_ip}{name};
		    
		    # Figure out a unique name for this IP
		    if ( my $name = Netdot->dns->resolve_ip($ip) ){
			$hosts{$ip}{alias} = $name; # fqdn
			$name = $self->strip_domain($name);
			unless ( exists $hostnames{$name} ){
			    $hosts{$ip}{name} = $name;
			}
		    }
		    $hosts{$ip}{name}  ||= $ip;
		    $hosts{$ip}{alias} ||= $hostname.'_'.$ip;
		    $hostnames{$hosts{$ip}{name}} = 1; 
		}

		# Common things to all IPs in this device
		$hosts{$ip}{group} = $group_name;
		push @{ $groups{$group_name}{members} }, $hosts{$ip}{name};
		push @{$hosts{$ip}{contactlists}}, @clids;

		# Add monitored services on this IP
		foreach my $servid ( keys %{$iph->{srv}} ){
		    next unless ( $iph->{srv}->{$servid}->{monitored} );
		    my $srvname = $iph->{srv}->{$servid}->{name};
		    
		    $hosts{$ip}{service}{$srvname}{hostname} = $hosts{$ip}{name};
		    $hosts{$ip}{service}{$srvname}{type}     = $srvname;
		    $hosts{$ip}{service}{$srvname}{srvname}  = $srvname;
		    
		    # Add service to servicegroup
		    push  @{ $servicegroups{$srvname}{members} }, $hosts{$ip}{name};
		    
		    # Add community if SNMP managed
		    if ( $devh->{snmp_managed} ){
			$hosts{$ip}{service}{$srvname}{community} = $devh->{community};
		    }
		    
		    # If service has a contactlist, use that
		    # if not, use Device contactlists
		    my @cls;
		    if ( my $srvcl = $iph->{srv}->{$servid}->{contactlist} ){
			push @cls, $srvcl;
		    }else{
			push @cls, @clids;
		    }
		    $hosts{$ip}{service}{$srvname}{contactlists} = \@cls if @cls;
		}
	    }
	}
    }

    # Print each host and its services together
    foreach my $i ( sort { $hosts{$a}{name} 
			   cmp $hosts{$b}{name} 
		    } keys %hosts ){
	$self->print_host(\%{$hosts{$i}});
	foreach my $s ( sort keys %{$hosts{$i}{service}} ){
	    $self->print_service(\%{$hosts{$i}{service}{$s}});
	}
    }

    $self->print_hostgroups(\%groups);
    $self->print_servicegroups(\%servicegroups);
    $self->print_contacts();

    $self->print_eof($self->{out});

    $logger->info("Netdot::Exporter::Nagios: Configuration written to file: ".$self->{filename});
    close($self->{out});
}


#####################################################################################

=head2 print_host

    Generate host section

=cut

sub print_host {
    my ($self, $argv) = @_;

    my $name      = $argv->{name};
    my $alias     = $argv->{alias};
    my $ip        = $argv->{ip};
    my $group     = $argv->{group};
    my $parents   = $argv->{parents};
    my $use_host  = $argv->{use_host};
    my @cls       = @{ $argv->{contactlists} } if $argv->{contactlists};
    my $out       = $self->{out};

    my $generic_host = $self->{NAGIOS_TEMPLATES}->{generic_host};
    my $generic_trap = $self->{NAGIOS_TEMPLATES}->{generic_trap};
    my $generic_ping = $self->{NAGIOS_TEMPLATES}->{generic_ping};

    # Use the generic template if not passed to us
    $use_host ||= $generic_host;

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
		print $out "\tuse                    $use_host\n";
		print $out "\thost_name              $name\n";
		print $out "\talias                  $alias\n";
		print $out "\taddress                $ip\n";
		print $out "\tparents                $parents\n" if ($parents);
		print $out "\tcontact_groups         $contact_groups\n";
		print $out "}\n\n";
		if ( $self->{NAGIOS_TRAPS} ){
		    print $out "define service{\n";
		    print $out "\tuse                     $generic_trap\n";
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
	print $out "\tuse                    $use_host\n";
	print $out "\thost_name              $name\n";
	print $out "\talias                  $alias\n";
	print $out "\taddress                $ip\n";
	print $out "\tparents                $parents\n" if ($parents);
	print $out "\tcontact_groups         nobody\n";
	print $out "}\n\n";
	
	if ( $self->{NAGIOS_TRAPS} ){
	    # Define a TRAP service for every host
	    print $out "define service{\n";
	    print $out "\tuse                     $generic_trap\n";
	    print $out "\thost_name               $name\n";
	    print $out "\tcontact_groups          nobody\n";
	    print $out "}\n\n";
	}
    }
    
    # Add ping service for every host
    print $out "define service{\n";
    print $out "\tuse                    $generic_ping\n";
    print $out "\thost_name              $name\n";
    print $out "}\n\n";

}

#####################################################################################

=head2 print_service

    Generate service section

=cut

sub print_service {
    my ($self, $argv) = @_;
    my $hostname    = $argv->{hostname};
    my $srvname     = $argv->{srvname};
    my $type        = $argv->{type};
    my $displayname = $argv->{displayname} || $srvname;

    my $checkcmd;
    unless ( $checkcmd = $self->{NAGIOS_CHECKS}{$type} ){
	$logger->warn("Service check for $srvname not implemented." . 
		      " Skipping $srvname check for host $hostname.");
	return;
    }

    my @cls = @{ $argv->{contactlists} } if $argv->{contactlists};
    my $out = $self->{out};
    my $contactlists = $self->{contactlists};
    my $generic_service = $self->{NAGIOS_TEMPLATES}->{generic_service};

    
    if ( $srvname =~ /^BGPPEER/o || $srvname =~ /^IFSTATUS/o ){
	if ( my $community = $argv->{community} ){
	    $checkcmd .= "!$community";				
	}else{
	    $logger->warn("Service check for $srvname requires a SNMP community." .
			  " Skipping $srvname check for host $hostname.");
	    return;
	}
    }
    if ( $srvname =~ /^IFSTATUS/o ){
	my $ifindex = $argv->{ifindex};
	$checkcmd .= "!$ifindex"; # Pass the argument to the check command
    }

    if ( $srvname =~ /^BGPPEER/o ){
	my $peer_addr;
	unless ( $peer_addr = $argv->{peer_addr} ){
	    $logger->warn("Service check for $srvname requires peer_addr." . 
			  " Skipping $srvname check for host $hostname.");
	    return;
	}
	$checkcmd .= "!$peer_addr"; # Pass the argument to the check command
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
		print $out "\tuse                   $generic_service\n";
		print $out "\thost_name             $hostname\n";
		print $out "\tservice_description   $srvname\n";
		print $out "\tdisplay_name          $displayname\n";
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
	print $out "\tuse                  $generic_service\n";
	print $out "\thost_name            $hostname\n";
	print $out "\tservice_description  $srvname\n";
	print $out "\tdisplay_name         $displayname\n";
	print $out "\tcontact_groups       nobody\n";
	print $out "\tcheck_command        $checkcmd\n";
	print $out "}\n\n";
    }

    # Add service dependencies if needed
    if ( $argv->{parent_host} && $argv->{parent_service} ){
	$self->print_servicedep($hostname, $srvname, $argv->{parent_host}, $argv->{parent_service});
    }
}

#####################################################################################

=head2 print_contacts

    Generate contacts section

=cut

sub print_contacts {
    my($self) = @_;
    my $out = $self->{out};
    my $contacts        = $self->{contacts};
    my $contactlists    = $self->{contactlists};
    my $generic_contact = $self->{NAGIOS_TEMPLATES}->{generic_contact};

    # Create the contact templates (with a person's common info)
    # A person might be a contact for several groups/events
    
    foreach my $name ( keys %$contacts ){
	print $out "define contact{\n";
	print $out "\tname                            $name\n";
	print $out "\tuse                             $generic_contact\n";
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
			    print $out "\tservice_notification_commands   notify-service-by-email\n";
			    print $out "\thost_notification_commands      notify-host-by-email\n";
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
	    my $members = join ',', sort @members;
	    
	    print $out "define contactgroup{\n";
	    print $out "\tcontactgroup_name       $clname-level_$level\n";
	    print $out "\talias                   $clname\n";
	    print $out "\tmembers                 $members\n";
	    print $out "}\n\n";
	}
    }
}


#####################################################################################

=head2 print_hostgroups

=cut

sub print_hostgroups{
    my ($self, $groups) = @_;

    my $out = $self->{out};
    foreach my $group ( keys %$groups ){
	my $alias = $groups->{$group}->{alias} || $group;
	next unless ( defined $groups->{$group}->{members} && 
		      ref($groups->{$group}->{members}) eq 'ARRAY' );
	my $hostlist = join ',', sort @{ $groups->{$group}->{members} };
	print $out "define hostgroup{\n";
	print $out "\thostgroup_name      $group\n";
	print $out "\talias               $alias\n";
	print $out "\tmembers             $hostlist\n";
	print $out "}\n\n";
    }
}

#####################################################################################

=head2 print_servicegroups

=cut

sub print_servicegroups{
    my ($self, $groups) = @_;

    my $out = $self->{out};
    foreach my $group ( keys %$groups ){
	# servicegroup members are like:
	# members=<host1>,<service1>,<host2>,<service2>,...,
	my $hostlist = join ',', sort map { "$_,$group" }@{ $groups->{$group}{members} };
	print $out "define servicegroup{\n";
	print $out "\tservicegroup_name      $group\n";
	print $out "\talias                  $group\n";
	print $out "\tmembers                $hostlist\n";
	print $out "}\n\n";
    }
}

#####################################################################################

=head2 print_servicedep

=cut

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
    my $links = $dbh->selectall_arrayref("
                SELECT  i1.id, i2.id 
                FROM    interface i1, interface i2
                WHERE   i1.id > i2.id AND i2.neighbor = i1.id AND i1.neighbor = i2.id
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

########################################################################
# Remove illegal chars

sub _rem_illegal_chars {
    my ($self, $string) = @_;
    return unless $string;
    $string =~ s/[\(\),'";]//g;  
    $string =~ s/^\s*(.*)\s*$/$1/;
    $string =~ s/[\/\s]/_/g;  
    $string =~ s/&/and/g;
    return $string;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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
