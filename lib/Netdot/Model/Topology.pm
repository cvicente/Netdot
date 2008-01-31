package Netdot::Model::Topology;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');


# Make sure to return 1
1;

=head1 NAME

Netdot::Model::Topology

=head1 SYNOPSIS

Netdot Device Topology Class

=head1 CLASS METHODS
=cut

######################################################################################
=head2 discover - Discover Topology for devices within given IP block

  Kinds of IP blocks allowed: 'Container' and 'Subnet'
        
  Arguments:
    Hash with following keys:
    ipblock - CIDR block (192.168.0.0/24)
  Returns:

  Examples:
    Netdot::Model::Topology->discover(ipblock=>'192.1.0.0/16');

=cut
sub discover {
    my ($class, %argv) = @_;
    $class->isa_class_method('discover');

    if ( $argv{ipblock} ){
	my $ip = Ipblock->search(address=>$argv{ipblock})->first;
	unless ( $ip ){
	    $class->throw_user("IP block $argv{ipblock} not found in DB");
	}
	if ( $ip->status->name eq 'Container' ){
	    $logger->info(sprintf("Performing topology discovery on IP Block %s", $ip->get_label));
	    # Get all possible subnets
	    my @subnets = Ipblock->search(parent=>$ip, status=>'Subnet');
	    foreach my $s ( @subnets ){
		$class->discover_subnet($s);
	    }
	}elsif ( $ip->status->name eq 'Subnet' ){
	    $class->discover_subnet($ip);
	}else{
	    $class->throw_user(sprintf("Block %s is a %s. Topology discovery only allowed on Container or Subnet Blocks",
				       $ip->get_label, $ip->status->name ));
	}
    }
}

######################################################################################
=head2 discover_subnet - Discover topology for devices within given subnet
        
  Arguments: 
    Ipblock object (subnet)
  Returns:

  Examples:
    Netdot::Model::Topology->discover_subnet($ip_obj);

=cut
sub discover_subnet{
    my ($class, $subnet) = @_;
    $class->isa_class_method('discover_subnet');
    
    my %SOURCES;
    $SOURCES{DP}  = 1 if $class->config->get('TOPO_USE_DP');
    $SOURCES{STP} = 1 if $class->config->get('TOPO_USE_STP');
    $SOURCES{FDB} = 1 if $class->config->get('TOPO_USE_FDB');
    my $MINSCORE  = $class->config->get('TOPO_MIN_SCORE');
    my $srcs = join ',', keys %SOURCES;
    $logger->info(sprintf("Discovering topology for devices on subnet %s, using sources: %s, min score: %s", 
			  $subnet->get_label, $srcs, $MINSCORE));
    my $start = time;

    my ($dp_links, $stp_links, $fdb_links);
    my %devs;
    foreach my $ip ( $subnet->children ){
	if ( int($ip->interface) && int($ip->interface->device) ){
	    my $dev = $ip->interface->device;
	    $devs{$dev->id} = $dev;
	}
    }
    my (@dp_devs, %stp_roots);
    foreach my $devid ( keys %devs ){
	my $dev = $devs{$devid};
	# STP sources
	if ( $SOURCES{STP} ){
	    foreach my $stp_instance ( $dev->stp_instances() ){
		if ( my $root = $stp_instance->root_bridge ){
		    $stp_roots{$root}++;
		}
	    }
	}
	# Discovery Protocol sources
	if ( $SOURCES{DP} ){
	    push @dp_devs, $dev;
	}
    }
    # Determine links
    foreach my $root ( keys %stp_roots ){
	my $links = $class->get_stp_links(root=>$root);
	map { $stp_links->{$_} = $links->{$_} } keys %$links;
    }
    $dp_links = $class->get_dp_links(\@dp_devs) if @dp_devs;

    # Get all existing links
    my %old_links;
    foreach my $devid ( keys %devs ){
	my $dev = $devs{$devid};
	my $n   = $dev->get_neighbors();
	map { $old_links{$_} = $n->{$_} } keys %$n;	
    }
    my %args;
    $args{old_links} = \%old_links;
    $args{dp}        = $dp_links  if $dp_links;
    $args{stp}       = $stp_links if $stp_links;
    $args{fdb}       = $fdb_links if $fdb_links;
    my ($addcount, $remcount) = $class->update_links(%args);
    my $end = time;
    $logger->info(sprintf("Topology discovery on Subnet %s done in %d seconds. Links added: %d, removed: %d", 
			  $subnet->get_label, $end-$start, $addcount, $remcount));

}

######################################################################################
=head2 update_links - Update links between Device Interfaces
    
    The different sources of topology information are assigned specific weights to
    calculate a final score.  Contradicting information lowers the score, while
    corroborating information raises the score in a cumulative fashion.
    Tuples with a score equal or above the configured minimum score are qualified
    to create a link in the database.
    
  Arguments:
    dp        - Hash ref with links discovered by discovery protocols (CDP/LLDP)
    stp       - Hash ref with links discovered by Spanning Tree Protocol
    fdb       - Hash ref with links discovered from forwarding tables
    old_links - Hash ref with current links
  Returns:
    
  Examples:
    Netdot::Model::Topology->update_links(db_links=>$links);

=cut
sub update_links {
    my ($class, %argv) = @_;
    my %links;
    my %WEIGHTS;
    $WEIGHTS{dp}  = $class->config->get('TOPO_WEIGHT_DP');
    $WEIGHTS{stp} = $class->config->get('TOPO_WEIGHT_STP');
    $WEIGHTS{fdb} = $class->config->get('TOPO_WEIGHT_FDB');
    my $MINSCORE  = $class->config->get('TOPO_MIN_SCORE');
    my %hashes;
    my $old_links = $argv{old_links};
    foreach my $source ( qw( dp stp fdb ) ){
	$hashes{$source} = $argv{$source};
    }
    foreach my $source ( keys %hashes ){
	my $score = $WEIGHTS{$source};
	foreach my $int ( keys %{$hashes{$source}} ){
	    my $nei = $hashes{$source}->{$int};
	    ${$links{$int}{$nei}} += $score;
	    $links{$nei}{$int}     = $links{$int}{$nei};
	    if ( scalar(keys %{$links{$int}}) > 1 ){
		foreach my $o ( keys %{$links{$int}} ){
		    ${$links{$int}{$o}} -= $score if ( $o ne $nei );
		}
	    }
	    if ( scalar(keys %{$links{$nei}}) > 1 ){
		foreach my $o ( keys %{$links{$nei}} ){
		    ${$links{$nei}{$o}} -= $score if ( $o != $nei );
		}
	    }
	}
    }
    
    my $addcount = 0;
    my $remcount = 0;
    foreach my $id ( keys %links ){
	foreach my $nei ( keys %{$links{$id}} ){
	    my $score = ${$links{$id}{$nei}};
	    next unless ( $score >= $MINSCORE );
	    if ( (exists($old_links->{$id})  && $old_links->{$id}  == $nei) || 
		 (exists($old_links->{$nei}) && $old_links->{$nei} == $id) ){
		delete $old_links->{$id}  if ( exists $old_links->{$id}  );
		delete $old_links->{$nei} if ( exists $old_links->{$nei} );
	    }else{
		my $int = Interface->retrieve($id) || $class->throw_fatal("Cannot retrieve Interface id $id");
		$int->add_neighbor($nei, $score);
		$addcount++;
	    }
	    delete $links{$id};
	    delete $links{$nei};		
	}
    }
    # Remove old links than no longer exist
    foreach my $id ( keys %$old_links ){
	my $nei = $old_links->{$id};
	my $int = Interface->retrieve($id) || $class->throw_fatal("Cannot retrieve Interface id $id");
	if ( int($int->neighbor) == $nei ){
	    $int->remove_neighbor() ;
	    $remcount++;
	}
    }
    return ($addcount, $remcount);
}

###################################################################################################
=head2 get_dp_links - Get links between devices based on Discovery Protocol (CDP/LLDP) Info 

  Arguments:  
    Reference to array of Device objects
  Returns:    
    Hashref with link info
  Example:
    my $links = Netdot::Model::Topology->get_dp_links(\@devices);

=cut
sub get_dp_links {
    my ($self, $devs) = @_;
    $self->isa_class_method('get_dp_links');

    my %links;
    foreach my $dev ( @$devs ){
	my $n = $dev->get_dp_neighbors();
	map { $links{$_} = $n->{$_} } keys %$n;
    }
    return \%links;
}

###################################################################################################
=head2 get_stp_links - Get links between devices based on STP information

  Arguments:  
    Hashref with the following keys:
     root  - Address of Root bridge
  Returns:    
    Hashref with link info
  Example:
    my $links = Netdot::Model::Topology->get_stp_links(root=>'DEADDEADBEEF');

=cut
sub get_stp_links {
    my ($self, %argv) = @_;
    $self->isa_class_method('get_stp_links');
    
    # Retrieve all the InterfaceVlan objects that participate in this tree
    my %ivs;
    my @stp_instances = STPInstance->search(root_bridge=>$argv{root});
    map { map { $ivs{$_->id} = $_ } $_->stp_ports } @stp_instances;
    
    # Run the analysis.  The designated bridge on a given segment will 
    # have its own base MAC as the designated bridge and its own STP port ID as 
    # the designated port.  The non-designated bridge will point to the 
    # designated bridge instead.
    my %links;
    $logger->debug(sprintf("Netdot::Model::Topology::get_stp_links: Determining topology for STP tree with root at %s", 
			   $argv{root}));
    my (%far, %near);
    foreach my $ivid ( keys %ivs ){
	my $iv = $ivs{$ivid};
	if ( defined $iv->stp_state && $iv->stp_state =~ /^forwarding|blocking$/ ){
	    if ( $iv->stp_des_bridge && int($iv->interface->device->physaddr) ){
		my $des_b     = $iv->stp_des_bridge;
		my $des_p     = $iv->stp_des_port;
		my $int       = $iv->interface->id;
		my $device_id = $iv->interface->device->id;
		# Now, the trick is to determine if the MAC in the designated
		# bridge value belongs to this same switch
		# It can either be the base bridge MAC, or the MAC of one of the
		# interfaces in the switch
		my $physaddr = PhysAddr->search(address=>$des_b)->first;
		next unless $physaddr;
		my $des_device;
		if ( my $dev = ($physaddr->devices)[0] ){
		    $des_device = $dev->id;
		}elsif ( (my $i = ($physaddr->interfaces)[0]) ){
		    if ( my $dev = $i->device ){
			$des_device = $dev->id ;
		    }
		}
		# If the bridge points to itself, it is the designated bridge
		# for the segment, which is nearest to the root
		if ( $des_device && $device_id && $des_device == $device_id ){
		    $near{$des_b}{$des_p} = $int;
		}else{
		    $far{$int}{des_p} = $des_p;
		    $far{$int}{des_b} = $des_b;
		}
	    }
	}
    }
    # Find the port in the designated bridge that is referenced by the far
    # bridge
    foreach my $int ( keys %far ){
	my $des_b = $far{$int}{des_b};
	my $des_p = $far{$int}{des_p};
	if ( exists $near{$des_b} ){
	    if ( exists $near{$des_b}{$des_p} ){
		my $r_int = $near{$des_b}{$des_p};
		$links{$int} = $r_int;
	    }else{
		# Octet representations may not match
		foreach my $r_des_p ( keys %{$near{$des_b}} ){
		    if ( $self->_cmp_des_p($r_des_p, $des_p) ){
			my $r_int = $near{$des_b}{$r_des_p};
			$links{$int} = $r_int;
		    }
		}
	    }
	}else{
	    $logger->debug(sprintf("Netdot::Model::Topology::get_stp_links: Designated bridge %s not found", 
				   $des_b));
	}
    }
    return \%links;
}


#########################################################################################
#
# Private methods
#
#########################################################################################

############################################################################
# Compare designated Port values
# Depending on the vendor (and the switch model within the same vendor)
# the value of dot1dStpPortDesignatedPort might be represented in different
# ways.  I ignore what the actual logic is, but some times the octets
# are swapped, and one of them may have the most significant or second to most
# significant bit turned on.  Go figure.
sub _cmp_des_p {
    my ($self, $a, $b) = @_;
    my ($aa, $ab, $ba, $bb, $x, $y);
    if ( $a =~ /(\w{2})(\w{2})/ ){
	( $aa, $ab ) = ($1, $2);
    }
    if ( $b =~ /(\w{2})(\w{2})/ ){
	( $ba, $bb ) = ($1, $2);
    }
    if ( $aa eq '00' || $aa eq '80' || $aa eq '40' ){
	$x = $ab;
    }else{
	$x = $aa;
    }
    if ( $ba eq '00' || $ba eq '80' || $ba eq '40' ){
	$y = $bb;
    }else{
	$y = $ba;
    }
    if ( $x eq $y ){
	return 1;
    }
    return 0;
}
