package Netdot::Exporter::Nagios;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;
use Carp;

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

    foreach my $key ( qw /NMS_DEVICE NAGIOS_CHECKS NAGIOS_TIMEPERIODS NAGIOS_DIR NAGIOS_CFG_EXT NAGIOS_SKEL_EXT 
                          NAGIOS_FILES NAGIOS_NOTIF_FIRST NAGIOS_NOTIF_LAST NAGIOS_NOTIF_INTERVAL 
                          NAGIOS_GRAPH_RTT NAGIOS_RTT_RRD_DIR NAGIOS_TRAPS NAGIOS_STRIP_DOMAIN/ ){
	$self->{$key} = Netdot->config->get($key);
    }
     
    defined $self->{NMS_DEVICE} ||
	croak "Netdot::Exporter::Nagios: NMS_DEVICE not defined";

    $self->{MONITOR} = Device->search(name=>$self->{NMS_DEVICE})->first 
	|| croak "Netdot::Exporter::Nagios: Monitoring device '" . $self->{NMS_DEVICE}. "' not found in DB";
    
    ref($self->{NAGIOS_FILES}) eq 'ARRAY' || 
	croak "Netdot::Exporter::Nagios: NAGIOS_FILES not configured or invalid.";
    
    $self->{NAGIOS_NOTIF_FIRST} ||= 4;
    $self->{NAGIOS_NOTIF_LAST}  ||= 6;

    if ( $self->{NAGIOS_GRAPH_RTT} ){
	$self->{NAGIOS_RTT_RRD_DIR} || 
	    croak "Netdot::Exporter::Nagios: NAGIOS_RTT_RRD_DIR not configured.";
    }

    bless $self, $class;
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

    # Put APAN's stuff in a separate file
    if ( Netdot->config->get('NAGIOS_GRAPH_RTT') ){
	push @{ $self->{NAGIOS_FILES} }, 'apan';
    }

    my %ip2name;
    my $device_ips = $self->get_monitored_ips();
    
    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $address, $hostname) = @$row;
	
	my $ipobj  = Ipblock->retrieve($ipid);
	my $device = Device->retrieve($deviceid);
	
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
	}elsif ( int($device->used_by) != 0 ){
	    $group = $device->used_by->name;
	}
	unless ( $group ){
	    $logger->warn("Address " . $address . " in unknown network");
	    $group = "Unknown";
	}
	
	# Remove illegal chars for Nagios
	$group =~ s/[\(\),]//g;  
	$group =~ s/^\s*(.)\s*$/$1/;
	$group =~ s/[\/\s]/_/g;  
	$group =~ s/&/and/g;     
	$hosts{$ipid}{ip}    = $address;
	$hosts{$ipid}{ipobj} = $ipobj;
	
	# Assign most specific contactlist 
	# Order is: interface, device and then entity
	# 
	my $clobj;
	if( ($clobj = $ipobj->interface->contactlist) != 0 ){
	    push @{ $hosts{$ipid}{contactlists} }, $clobj;
	    
	    # Devices can have many contactlists
	    # This gets me DeviceContacts objects (join table)
	}elsif( my @dcs = $device->contacts ){
	    foreach my $dc ( @dcs ){
		push @{ $hosts{$ipid}{contactlists} }, $dc->contactlist;
	    }
	}elsif( ($clobj = $device->used_by->contactlist) != 0 ){
	    push @{ $hosts{$ipid}{contactlists} }, $clobj;
	}
	
	foreach my $clobj ( @{ $hosts{$ipid}{contactlists} } ){
	    my $name = $clobj->name;
	    next unless defined $name;
	    $contactlists{$clobj->id}{name} = join '_', split /\s+/, $name;
	    $contactlists{$clobj->id}{obj}  = $clobj;
	}
	
	$hosts{$ipid}{group} = $group;

	if ( Netdot->config->get('NAGIOS_STRIP_DOMAIN') ){
	    my $domain = Netdot->config->get('DEFAULT_DNSDOMAIN');
	    $hostname =~ s/\.$domain// ;
	}

	$hosts{$ipid}{name} = $hostname;
	push @{ $groups{$group}{members} }, $hostname;
	$ip2name{$ipid} = $hostname;

	# Add services (if any)
	foreach my $ipsrv ( $ipobj->services ){
	    my $srvname = $ipsrv->service->name;
	    my $srvclobj;
	    $logger->debug("Service $srvname added to IP " . $address);
	    push  @{ $servicegroups{$srvname}{members} }, $hostname ;

	    # If service has a contactlist, use that
	    # if not, use the associated IP's contactlists
	    #
	    if ( ($srvclobj = $ipsrv->contactlist) != 0 ) {
		push @{ $services{$hostname}{$srvname}{contactlists} }, $srvclobj;
		$contactlists{$srvclobj->id}{name} = join '_', split /\s+/, $srvclobj->name;
		$contactlists{$srvclobj->id}{obj}  = $srvclobj;
		$logger->debug("Contactlist ". $srvclobj->name ." assigned to service $srvname for IP " . $address);
	    }elsif( $hosts{$ipid}{contactlists} ){
		$services{$hostname}{$srvname}{contactlists} = $hosts{$ipid}{contactlists};
	    }else{
		$logger->debug("Service $srvname for IP ". $address ." has no contactlist defined\n");
	    }
	    # Add the SNMP community in case it's needed
	    $services{$hostname}{$srvname}{community} = $device->community;
	}
    } #foreach ip

    # Now that we have everybody in, assign parent list.
    my $dependencies = $self->get_dependencies($self->{MONITOR});
    foreach my $ipid ( keys %hosts ){
	next unless defined $dependencies->{$ipid};
	if ( my @parentlist = @{$dependencies->{$ipid}} ){
	    my @names;
	    foreach my $parent ( @parentlist ){
		if ( !exists $ip2name{$parent} ){
		    $logger->warn("IP $ipid parent $parent not in monitored list." .
				  " Skipping.");
		    next;
		}
		push @names, $ip2name{$parent};
	    }
	    $hosts{$ipid}{parents} = join ',', @names;
	}else{
	    $hosts{$ipid}{parents} = undef;
	}
    }

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


    #######################################################################################3
    # Start writing config files
    #
    foreach my $file ( @{ $self->{NAGIOS_FILES} } ){
	# Open skeleton file for reading
	my $skel_file = $self->{NAGIOS_DIR}."/$file.".$self->{NAGIOS_SKEL_EXT};
	open (SKEL, "$skel_file") or die "Can't open $skel_file\n";
	
	# Open output file for writing
	my $out_file = $self->{NAGIOS_DIR}."/$file.".$self->{NAGIOS_CFG_EXT};
	my $out = $self->open_and_lock($out_file);
	
	while ( <SKEL> ){
	    if (/<INSERT HOST DEFINITIONS>/){
		
		foreach my $ipid ( sort { $hosts{$a}{name} cmp $hosts{$b}{name} } keys %hosts ){
		    my $name     = $hosts{$ipid}{name};
		    my $ip       = $hosts{$ipid}{ip};
		    my $group    = $hosts{$ipid}{group};
		    my $parents  = $hosts{$ipid}{parents};
		    my @cls      = @{ $hosts{$ipid}{contactlists} } if $hosts{$ipid}{contactlists};
		    
		    my %levels;
		    if ( @cls ) {
			# This will make sure we're looping through the highest level number
			map { map { $levels{$_} = '' } keys %{ $contactlists{$_->id}{level} } } @cls;
		    }else{
			$logger->warn("Host $name (IP id $ipid) does not have a valid Contact Group!");
		    }

		    if ( keys %levels ){
			my $first   = 1;
			my $fn      = $self->{NAGIOS_NOTIF_FIRST};
			my $ln      = $self->{NAGIOS_NOTIF_FIRST};
			
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
		    if ( !@cls || ! keys %levels ){
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
			    print $out "\tuse                    generic-trap\n";
			    print $out "\thost_name              $name\n";
			    print $out "\tcontact_groups         nobody\n";
			    print $out "}\n\n";
			}
		    }
		    
		    if ( $self->{NAGIOS_GRAPH_RTT} ){
			# Define RTT (Round Trip Time) as a service
			print $out "define service{\n";
			print $out "\thost_name              $name\n";
			print $out "\tuse                    generic-RTT\n";
			print $out "}\n\n";
			
			print $out "define serviceextinfo{\n";
			print $out "\thost_name              $name\n";
			print $out "\tservice_description    RTT\n";
			print $out "\tnotes                  Round Trip Time Statistics\n";
			print $out "\tnotes_url              /nagios/cgi-bin/apan.cgi?host=$ip&service=RTT\n";
			print $out "\ticon_image             graph.png\n";
			print $out "\ticon_image_alt         View RTT graphs\n";
			print $out "}\n\n";
			
		    }else{
			
			# Nagios requires at least one service per host
			print $out "define service{\n";
			print $out "\tuse                    generic-ping\n";
			print $out "\thost_name              $name\n";
			print $out "}\n\n";
		    }
		    
		}
		
	    }elsif (/<INSERT APAN DEFINITIONS>/){
		
		foreach my $ipid ( keys %hosts ){
		    my $name = $hosts{$ipid}{name};
		    $name =~ s/\//-/;
		    my $ip = $hosts{$ipid}{ip};
		    my $dir = $self->{NAGIOS_RTT_RRD_DIR};
		    print $out "$ip;RTT;$dir/$ip-RTT.rrd;ping;RTT:LINE2;Ping round-trip time;Seconds\n"; 
		}
		
	    }elsif (/<INSERT CONTACT DEFINITIONS>/){
		# Create the contact templates (with a person's common info)
		# A person might be a contact for several groups/events
		
		foreach my $name (keys %contacts){
		    print $out "define contact{\n";
		    print $out "\tname                            $name\n";
		    print $out "\tuse                             generic-contact\n";
		    print $out "\talias                           $name\n";
		    print $out "\temail                           $contacts{$name}{email}\n" if $contacts{$name}{email};
		    print $out "\tpager                           $contacts{$name}{pager}\n" if $contacts{$name}{pager};
		    print $out "\tregister                        0 ; (THIS WILL BE INHERITED LATER)\n";  
		    print $out "}\n\n";
		    
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
				if ( exists($self->{NAGIOS_TIMEPERIODS}{$contact->notify_email->name}) ){
				    if ((my $emailperiod = $self->{NAGIOS_TIMEPERIODS}{$contact->notify_email->name}) ne 'none' ){
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
				    $logger->warn($contact->notify_email->name . " is not a defined timeperiod");
				}
			    }
			    # And one for paging
			    if ( int($contact->notify_pager) ){
				if ( exists($self->{NAGIOS_TIMEPERIODS}{$contact->notify_pager->name}) ){
				    if ((my $pagerperiod = $self->{NAGIOS_TIMEPERIODS}{$contact->notify_pager->name}) ne 'none' ){
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
				    $logger->warn($contact->notify_pager->name . " is not a defined timeperiod");
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
		
	    }elsif (/<INSERT HOST GROUP DEFINITIONS>/){
		foreach my $group ( keys %groups ){
		    
		    my $hostlist = join ',', @{ $groups{$group}{members} };
		    print $out "define hostgroup{\n";
		    print $out "\thostgroup_name      $group\n";
		    print $out "\talias               $group\n";
		    print $out "\tmembers             $hostlist\n";
		    print $out "}\n\n";
		}
		
	    }elsif (/<INSERT SERVICE GROUP DEFINITIONS>/){
		foreach my $group ( keys %servicegroups ){
		    
		    # servicegroup members are like:
		    # members=<host1>,<service1>,<host2>,<service2>,...,
		    my $hostlist = join ',', map { "$_,$group" }@{ $servicegroups{$group}{members} };
		    print $out "define servicegroup{\n";
		    print $out "\tservicegroup_name      $group\n";
		    print $out "\talias                  $group\n";
		    print $out "\tmembers                $hostlist\n";
		    print $out "}\n\n";
		}
		
	    }elsif (/<INSERT SERVICE DEFINITIONS>/){
		
		foreach my $name ( keys %services ){
		    foreach my $srvname ( keys %{ $services{$name} } ){
			if ( !exists $self->{NAGIOS_CHECKS}{$srvname} ){
			    $logger->warn("Service check for $srvname not implemented." . 
					  " Skipping $srvname check for host $name.");
			    next;
			}
			my $checkcmd = $self->{NAGIOS_CHECKS}{$srvname};
			
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
			    $logger->warn("Service ". $srvname  ." on ". $name .
					  " does not have a valid Contact Group");
			}
			if ( keys %levels ){
			    my $first  = 1;
			    my $fn     = $self->{NAGIOS_NOTIF_FIRST};
			    my $ln     = $self->{NAGIOS_NOTIF_LAST};
			    
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
				    print $out "define service{\n";
				    print $out "\tuse                  generic-service\n";
				    print $out "\thost_name            $name\n";
				    print $out "\tservice_description  $srvname\n";
				    print $out "\tcontact_groups       $contact_groups\n";
				    print $out "\tcheck_command        $checkcmd\n";
				    print $out "}\n\n";
				    
				    $first = 0;
				}else{
				    
				    print $out "define serviceescalation{\n";
				    print $out "\thost_name                $name\n";
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
			    print $out "\thost_name            $name\n";
			    print $out "\tservice_description  $srvname\n";
			    print $out "\tcontact_groups       nobody\n";
			    print $out "\tcheck_command        $checkcmd\n";
			    print $out "}\n\n";
			}
		    }
		}
		
	    }else{
		print $out $_;
	    }
	}
	$logger->info("Netdot::Exporter::Nagios: Configuration written to file: $out_file");
	close(SKEL);
	close($out);
    }
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 University of Oregon, all rights reserved.

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
