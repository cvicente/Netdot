package Netdot::ObjectAccessRule;

use Apache2::SiteControl::Rule;
@ISA = qw(Apache2::SiteControl::Rule);
use Netdot::Model;
use strict;

my $logger = Netdot->log->get_logger("Netdot::UI");

# This rule is going to be used in a system that automatically grants
# permission for everything (via the GrantAllRule). So this rule will
# only worry about what to deny, and the grants method can return whatever.

sub grants()
{
   return 0;
}

sub denies(){
    my ($this, $user, $action, $object) = @_;
    
    my $user_type = $user->getAttribute('USER_TYPE');
    # Admins have full access to every object
    return 0 if ( $user_type eq "Admin" );

    my $otype;
    if ( !$object || !ref($object) ){
	return 0;
    }

    my $otype = $object->short_class();

    if ( !$otype ){
	$logger->debug("ObjectAccessRule::denies: object not valid");
	return 1;
    }
    
    my $oid = $object->id;
    my $username  = $user->getUsername();
    $logger->debug("ObjectAccessRule::denies: Requesting permission to '$action' $otype ".
		   "id $oid on behalf of $username ($user_type)");

    if ( $user_type eq 'User' || $user_type eq 'Operator' ){

	# Operators have 'view' access to everything
	return 0 if ( $user_type eq 'Operator' && $action eq 'view' );

	my $access;
	if ( !($access = $user->getAttribute('ALLOWED_OBJECTS')) ){
	    $logger->debug("ObjectAccessRule::denies: $username: No 'ALLOWED_OBJECTS' ".
			   "attribute.  Denying access.");
	    return 1;
	}
	if ( exists $access->{$otype} && exists $access->{$otype}->{$oid} ){
	    if ( $otype eq 'Zone' || $otype eq 'Ipblock' ){
		# Users cannot delete these
		# These persmissions will only apply to records in the zone
		if ( $user_type eq 'User' && $action eq 'delete' ){
		    $logger->debug("ObjectAccessRule::denies: '$action' $otype id $oid ".
				   "denied to $username ($user_type)");
		    return 1;
		}
	    }
	    return &_deny_action_access($action, $access->{$otype}->{$oid});

	}elsif ( $otype eq 'Interface' ){
	    # Grant access to any interface of an allowed device
	    my $dev = $object->device;
	    if ( exists $access->{'Device'} && 
		 exists $access->{'Device'}->{$dev->id} ){
		return &_deny_action_access($action, $access->{'Device'}->{$dev->id});
	    }
	}elsif ( $otype eq 'Contact' ){
	    # Grant access to roles (contacts) of an allowed ContactList
	    my $cl = $object->contactlist;
	    if ( exists $access->{'ContactList'} && 
		 exists $access->{'ContactList'}->{$cl->id} ){
		return &_deny_action_access($action, $access->{'ContactList'}->{$cl->id});
	    }
	}elsif ( $otype eq 'Person' ){
	    # Grant access to Person objects with roles (contacts) in a allowed ContactList
	    foreach my $role ( $object->roles ){
		my $cl = $role->contactlist;
		if ( exists $access->{'ContactList'} && 
		     exists $access->{'ContactList'}->{$cl->id} ){
		    return 0 if ( !&_deny_action_access($action, $access->{'ContactList'}->{$cl->id}) );
		}
	    }
	    return 1;
	}elsif ( $otype eq 'Ipblock' ){
	    # Notice that only Ipblocks that are not in the %access hash make it here
	    # for example, individual IP addresses
	    return &_deny_ip_access($action, $access, $object);

	}elsif ( $otype eq 'IpblockAttr' ){
	    # IP attributes match subnet permissions
	    # Notice that users need to edit/delete attributes, even though
	    # they can only view IP addresses
	    my $ipblock = $object->ipblock;
	    my $parent;
	    if ( $parent = $ipblock->parent ){
		if ( exists $access->{'Ipblock'} && 
		     exists $access->{'Ipblock'}->{$parent->id} ){
		    return &_deny_action_access($action, $access->{'Ipblock'}->{$parent->id});
		}
	    }
	}elsif ( $otype eq 'PhysAddr' ){
	    # Grant view access to physaddr if it has a dhcp scope in an allowed subnet
	    if ( my @scopes = $object->dhcp_hosts ){
		foreach my $scope ( @scopes ){
		    if ( $scope->ipblock ){
			my $ipb = $scope->ipblock;
			return 0 if ( !&_deny_ip_access($action, $access, $ipb) );
		    }
		}
	    }
	    # Or if it has ARP entries in an allowed subnet
	    if ( my @arp_entries = $object->arp_entries ){
		foreach my $ae ( @arp_entries ){
		    if ( $ae->ipaddr ){
			my $ipb = $ae->ipaddr;
			return 0 if ( !&_deny_ip_access($action, $access, $ipb) );
		    }
		}
	    }
	    return 1;
	}elsif ( $otype eq 'PhysAddrAttr' ){
	    if ( my @scopes = $object->dhcp_hosts ){
		foreach my $scope ( @scopes ){
		    if ( $scope->ipblock ){
			my $ipblock = $scope->ipblock;
			my $parent;
			if ( $parent = $ipblock->parent ){
			    if ( exists $access->{'Ipblock'} && 
				 exists $access->{'Ipblock'}->{$parent->id} ){
				return 0 if ( !&_deny_action_access($action, 
								    $access->{'Ipblock'}->{$parent->id}) );
			    }
			}
		    }
		}
	    }
	    return 1;
	}elsif ( $otype =~ /^RR/ ){
	    my ($rr, $zone);
	    if ( $otype eq 'RR' ){
		$rr = $object;
	    }else{
		$rr = $object->rr;
	    }
	    $zone = $rr->zone;
	    
	    # Users cannot delete the zone apex
	    if ( $otype eq 'RR' && $rr->name eq '@' && $action eq 'delete' ){
		return 1;
	    }

	    # Users cannot edit or delete NS records
	    if ( $otype eq 'RRNS' && $action ne 'view' ){
		return 1;
	    }

	    # Users cannot edit or delete RRs for Devices or Device IPs
	    if ( $action ne 'view' ){
		if ( $rr->devices ) {
		    $logger->debug("ObjectAccessRule::_denies: ".$rr->get_label.
				   " linked to a Device. Denying access.");
		    return 1;
		}
		my $ret = 0;
		foreach my $arecord ( $rr->a_records ){
		    my $ip = $arecord->ipblock;
		    return 1 if ($ip->interface || $ip->snmp_devices);
		}
	    }

	    # If user has rights on the zone, they have the same rights over records
	    if ( exists $access->{'Zone'}->{$zone->id} ){
		return &_deny_action_access($action, $access->{'Zone'}->{$zone->id});
	    }
	    
	    # At this point, user does not have access to the whole zone.
	    # Grant access to any RR only if the records are associated with an IP 
	    # in an allowed IP block
	    if ( $otype eq 'RRCNAME' ){
		# Search for the record that the CNAME points to
		if ( my $crr = RR->search(name=>$object->cname)->first ){
		    if ( my @ipbs = &_get_rr_ips($crr) ){
			foreach my $ipb ( @ipbs ){
			    next if $ipb == 0;
			    return 1 if ( &_deny_ip_access($action, $access, $ipb, 1) );
			}
			return 0;
		    }
		}
	    }else{
		if ( my @ipbs = &_get_rr_ips($rr) ){
		    foreach my $ipb ( @ipbs ){
			next if !$ipb;
			return 1 if ( &_deny_ip_access($action, $access, $ipb, 1) );
		    }
		    return 0;
		}elsif ( my $cname = $object->cnames->first ){
		    # This RR is the alias of something else
		    if ( my $crr = RR->search(name=>$cname->cname)->first ){
			if ( my @ipbs = &_get_rr_ips($crr) ){
			    foreach my $ipb ( @ipbs ){
				next if $ipb == 0;
				return 1 if ( &_deny_ip_access($action, $access, $ipb, 1) );
			    }
			    return 0;
			}
		    }
		}
	    }
	}
    }
    $logger->debug("ObjectAccessRule::denies: No matching criteria.  Denying access.");
    return 1;
}

##################################################################################
# Given an RR object, return the list of IP addresses from A records
#
sub _get_rr_ips {
    my ($rr) = @_;
    Netdot->throw_fatal("Missing arguments") unless ( $rr );
    return map { $_->ipblock } $rr->a_records;
}

##################################################################################
# Return 1 or 0 depending on the action and the permission for the 
# particular object
#
sub _deny_action_access {
    my ($action, $access) = @_;

    Netdot->throw_fatal("Missing arguments")
	unless ( $action );

    if ( exists $access->{none} ){
	$logger->debug("ObjectAccessRule::_deny_action_access: access was explicitly denied for this object");
	return 1;
    }

    # This assumes actions and access rights are the same
    if ( exists $access->{$action} ){
	return 0; # Do not deny access
    }
    $logger->debug("ObjectAccessRule::_deny_action_access: access for $action not found.  Denying access.");
    return 1;
}

##################################################################################
# ip addresses inherit ancestor permissions
# RRs inherit IP address permissions, but users are allowed to edit and delete RRs
sub _deny_ip_access {
    my ($action, $access, $ipblock, $is_rr) = @_;
    if ( $action ne 'view' && ($ipblock->interface || $ipblock->snmp_devices) ){
	$logger->debug("ObjectAccessRule::_deny_ip_access: ".$ipblock->get_label.
		       " linked to Device. Denying access.");
	return 1;
    }
    unless ( $is_rr ){
	if ( $ipblock->is_address && ($action eq 'delete' || $action eq 'edit') ){
	    $logger->debug("ObjectAccessRule::_deny_ip_access: ".$ipblock->get_label
			   ." Users cannot edit or delete IP addresses. Denying access.");
	    return 1;
	}
    }
    if ( $ipblock->status ){
	my $status = $ipblock->status->name;
	if ( $status eq 'Dynamic' || $status eq 'Reserved' ){
	    $logger->debug("ObjectAccessRule::_deny_ip_access: ".$ipblock->get_label
			   ." is Dynamic or Reserved. Denying access.");
	    return 1;
	}
    }
    # Deny unless there's an ancestor which is permitted. This includes
    # subnets, containers, etc.
    my $deny = 1;
    foreach my $ancestor ( $ipblock->get_ancestors ){
	if ( exists $access->{'Ipblock'}->{$ancestor->id} ){
	    $deny = &_deny_action_access($action, $access->{'Ipblock'}->{$ancestor->id});
	    last if $deny == 0;
	}
    }
    return $deny;

    $logger->debug("ObjectAccessRule::_deny_ip_access: ".$ipblock->get_label
		   ." not within allowed block. Denying access.");
    return 1;
}



1;
