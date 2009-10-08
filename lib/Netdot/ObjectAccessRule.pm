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
	$logger->debug("Netdot::ObjectAccessRule::denies: object not valid");
	return 1;
    }
    
    my $oid = $object->id;
    my $username  = $user->getUsername();
    $logger->debug("Netdot::ObjectAccessRule::denies: Requesting permission to '$action' $otype id $oid on behalf of $username ($user_type)");

    if ( $user_type eq 'User' || $user_type eq 'Operator' ){

	# Operators have 'view' access to everything
	return 0 if ( $user_type eq "Operator" && $action eq 'view' );

	my $access;
	if ( !($access = $user->getAttribute('ALLOWED_OBJECTS')) ){
	    $logger->debug("Netdot::ObjectAccessRule::denies: $username: No 'ALLOWED_OBJECTS' attribute.  Denying access.");
	    return 1;
	}
	if ( exists $access->{$otype} && exists $access->{$otype}->{$oid} ){
	    if ( $otype eq 'Zone' ){
		# Users cannot delete Zones
		# These persmissions will only apply to records in the zone
		if ( $user_type eq 'User' && $action eq 'delete' ){
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
	    # Grant access to Block's children
	    my $parent = $object->parent;
	    if ( exists $access->{'Ipblock'} && 
		 exists $access->{'Ipblock'}->{$parent->id} ){
		if ( $action eq 'delete' ){
		    # Allow user to delete children blocks if the have 'edit' access to the parent
		    return &_deny_action_access('edit', $access->{'Ipblock'}->{$parent->id});
		}else{
		    return &_deny_action_access($action, $access->{'Ipblock'}->{$parent->id});
		}
	    }
	}elsif ( $otype =~ /^RR/ ){
	    my ($rr, $zone);
	    if ( $otype eq 'RR' ){
		$rr = $object;
	    }else{
		$rr = $object->rr;
	    }
	    $zone = $rr->zone;

	    # Users cannot edit RRs for Device IPs
	    foreach my $arecord ( $rr->arecords ){
		my $ip = $arecord->ipblock;
		if ( int($ip->interface) != 0 ){
		    $logger->debug("Netdot::ObjectAccessRule::_denies: ".$rr->get_label." linked to Device interface. Denying access.");
		    return 1;
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
		    if ( my @ipbs = &_get_rr_subnets($crr) ){
			foreach my $ipb ( @ipbs ){
			    next if $ipb == 0;
			    return 1 if ( &_deny_action_access($action, $access->{'Ipblock'}->{$ipb->id}) );
			}
			return 0;
		    }
		}
	    }else{
		if ( my @ipbs = &_get_rr_subnets($rr) ){
		    foreach my $ipb ( @ipbs ){
			next if scalar($ipb) == 0;
			return 1 if ( &_deny_action_access($action, $access->{'Ipblock'}->{$ipb->id}) );
		    }
		    return 0;
		}elsif ( my $cname = $object->cnames->first ){
		    # This RR is the alias of something else
		    if ( my $crr = RR->search(name=>$cname->cname)->first ){
			if ( my @ipbs = &_get_rr_subnets($crr) ){
			    foreach my $ipb ( @ipbs ){
				next if $ipb == 0;
				return 1 if ( &_deny_action_access($action, $access->{'Ipblock'}->{$ipb->id}) );
			    }
			    return 0;
			}
		    }
		}
	    }
	}
    }
    $logger->debug("Netdot::ObjectAccessRule::denies: No matching criteria.  Denying access.");
    return 1;
}

##################################################################################
# Given an RR object, return the list of subnets where its A/AAAA records are
#
sub _get_rr_subnets {
    my ($rr) = @_;

    Netdot->throw_fatal("Missing arguments")
	unless ( $rr );

    if ( my @rraddrs = $rr->arecords ){
	my %ipblocks;
	foreach my $rraddr ( @rraddrs ){
	    my $ipb = $rraddr->ipblock;
	    $ipblocks{$ipb->parent->id} = $ipb->parent if int($ipb->parent);
	}
	if ( %ipblocks ){
	    my @ipblist = values %ipblocks;
	    if ( $logger->is_debug() ){
		my $list = join ', ', map { $_->get_label } @ipblist;
		$logger->debug("Netdot::ObjectAccessRule::_get_rr_subnets: subnets for RR $rr: ".$rr->id.": $list");
	    }
	    return @ipblist;
	}else{
	    $logger->debug("Netdot::ObjectAccessRule::_get_rr_subnets: no ipblocks found for RR: ".$rr->id);
	    return;
	}
    }	    
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
	$logger->debug("Netdot::ObjectAccessRule::_deny_action_access: access was explicitly denied for this object");
	return 1;
    }

    # This assumes actions and access rights are the same
    if ( exists $access->{$action} ){
	return 0; # Do not deny access
    }
    $logger->debug("Netdot::ObjectAccessRule::_deny_action_access: access for $action not found.  Denying access.");
    return 1;
}

1;
