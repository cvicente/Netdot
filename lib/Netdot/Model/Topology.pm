package Netdot::Model::Topology;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Topology');
my $MAC    = Netdot->get_mac_regex();
my $IP     = Netdot->get_ipv4_regex();



# Make sure to return 1
1;

=head1 NAME

Netdot::Model::Topology

=head1 SYNOPSIS

Netdot Device Topology Class

=head1 CLASS METHODS
=cut

######################################################################################
=head2 discover - Discover Topology for devices within (optional) given IP block

  Kinds of IP blocks allowed: 'Container' and 'Subnet'
        
  Arguments:
    None
  Returns:
    True
  Examples:
    Netdot::Model::Topology->discover();

=cut
sub discover {
    my ($class, %argv) = @_;
    $class->isa_class_method('discover');

    my %SOURCES;
    $SOURCES{DP}  = 1 if $class->config->get('TOPO_USE_DP');
    $SOURCES{STP} = 1 if $class->config->get('TOPO_USE_STP');
    $SOURCES{FDB} = 1 if $class->config->get('TOPO_USE_FDB');
    $SOURCES{P2P} = 1 if $class->config->get('TOPO_USE_P2P');
    my $MINSCORE  = $class->config->get('TOPO_MIN_SCORE');
    my $srcs = join ', ', keys %SOURCES;
    
    $logger->info(sprintf("Discovering Network Topology using sources: %s. Min score: %s", 
			  $srcs, $MINSCORE));

    my $start = time;
    my $stp_links = $class->get_stp_links() if ( $SOURCES{STP} );
    my $fdb_links = $class->get_fdb_links() if ( $SOURCES{FDB} );
    my $dp_links  = $class->get_dp_links()  if ( $SOURCES{DP}  );
    my $p2p_links = $class->get_p2p_links() if ( $SOURCES{P2P} );

    $logger->debug(sprintf("Netdot::Model::Topology: All links determined in %s", 
			   $class->sec2dhms(time - $start)));

    # Get all existing links
    my %old_links;
    my $dbh = $class->db_Main;
    foreach my $row (@{$dbh->selectall_arrayref("SELECT id, neighbor FROM interface WHERE neighbor != 0")}) {
	my ($id, $neighbor) = @$row;
	$old_links{$id} = $neighbor;
    }
    
    my %args;
    $args{old_links} = \%old_links;
    $args{dp}        = $dp_links  if $dp_links;
    $args{stp}       = $stp_links if $stp_links;
    $args{fdb}       = $fdb_links if $fdb_links;
    $args{p2p}       = $p2p_links if $p2p_links;
    my ($addcount, $remcount) = $class->update_links(%args);
    my $end = time;
    $logger->info(sprintf("Topology discovery done in %s. Links added: %d, removed: %d", 
			  $class->sec2dhms($end-$start), $addcount, $remcount));
    return 1;
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
    Array with: number of links added, number of links removed
  Examples:
    Netdot::Model::Topology->update_links(db_links=>$links);

=cut
sub update_links {
    my ($class, %argv) = @_;
    my %WEIGHTS;
    $WEIGHTS{dp}  = $class->config->get('TOPO_WEIGHT_DP');
    $WEIGHTS{stp} = $class->config->get('TOPO_WEIGHT_STP');
    $WEIGHTS{fdb} = $class->config->get('TOPO_WEIGHT_FDB') / 2;
    $WEIGHTS{p2p} = $class->config->get('TOPO_WEIGHT_P2P');
    my $MINSCORE  = $class->config->get('TOPO_MIN_SCORE');
    my %hashes;
    my $old_links = $argv{old_links};
    foreach my $source ( qw( dp stp fdb p2p ) ){
	$hashes{$source} = $argv{$source};
    }

    my %links;
    foreach my $source ( keys %hashes ){
	my $score = $WEIGHTS{$source};
	while ( my ($int, $nei) = each %{$hashes{$source}} ){
	    ${$links{$int}{$nei}} += $score;
	    $links{$nei}{$int}     = $links{$int}{$nei};
	    if ( scalar(keys %{$links{$int}}) > 1 ){
		foreach my $o ( keys %{$links{$int}} ){
		    ${$links{$int}{$o}} -= $score if ( $o != $nei );
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
	    next unless defined $links{$id}{$nei};
	    my $score = ${$links{$id}{$nei}};
	    next unless ( $score >= $MINSCORE );
	    if ( (exists($old_links->{$id})  && $old_links->{$id}  == $nei) || 
		 (exists($old_links->{$nei}) && $old_links->{$nei} == $id) ){
		delete $old_links->{$id}  if ( exists $old_links->{$id}  );
		delete $old_links->{$nei} if ( exists $old_links->{$nei} );
	    }else{
		my $int = Interface->retrieve($id) || $class->throw_fatal("Cannot retrieve Interface id $id");
		eval {
		    $int->add_neighbor(id=>$nei, score=>$score);
		};
		if ( my $e = $@ ){
		    $logger->warn($e);
		}else{
		    $addcount++;
		}
	    }
	    delete $links{$id};
	    delete $links{$nei};		
	}
    }
    # Remove old links than no longer exist
    foreach my $id ( keys %$old_links ){
	my $nei  = $old_links->{$id};
	my $int  = Interface->retrieve($id);
	unless ( $int ){
	    $logger->warn("Cannot retrieve Interface id $id");
	    next;
	}
	my $nint = Interface->retrieve($nei);
	unless ( $nint ){
	    $logger->warn("Cannot retrieve Interface id $nei");
	    next;
	}
	# Do not remove neighbors if the neighbor_fixed flag is on
        unless ( $int->neighbor_fixed || $nint->neighbor_fixed ){
	    if ( int($int->neighbor) == $nei ){
		$int->remove_neighbor();
		$remcount++;
	    }
	}
    }
    return ($addcount, $remcount);
}

###################################################################################################
=head2 get_dp_links - Get links between devices based on Discovery Protocol (CDP/LLDP) Info 

  Arguments:  
    None
  Returns:    
    Hashref with link info
  Example:
    my $links = Netdot::Model::Topology->get_dp_links(\@devices);

=cut
sub get_dp_links {
    my ($class, %argv) = @_;
    $class->isa_class_method('get_dp_links');

    my $start = time;

    # Using raw database access because Class::DBI was too slow here
    my $dbh = $class->db_Main;
    my $results;
    my $sth = $dbh->prepare("SELECT device, id, dp_remote_ip, dp_remote_id, dp_remote_port 
                             FROM interface 
                             WHERE (dp_remote_ip IS NOT NULL OR dp_remote_id IS NOT NULL) 
                               AND dp_remote_port IS NOT NULL");
    $sth->execute;
    $results = $sth->fetchall_arrayref;

    # Now go through everything looking for results
    my %links = ();
    my $allmacs = Device->get_macs_from_all();
    my $allips  = Device->get_ips_from_all();
    my %ips2discover;

    foreach my $row ( @$results ){
        my ($did, $iid, $r_ip, $r_id, $r_port) = @$row;
	# In theory this is not needed, but I've seen some funny results from that query
	next unless ( ($r_ip || $r_id) && $r_port );

        next if (exists $links{$iid});

        my $rem_dev = 0;

        # Find the connected device
        if ( $r_ip ) {
            foreach my $rem_ip ( split ';', $r_ip ) {
                my $decimalip = Ipblock->ip2int($rem_ip);
                next unless (exists $allips->{$decimalip});
		$rem_dev = $allips->{$decimalip};
		last if $rem_dev;
		unless ($rem_dev) {
		    $logger->debug("Topology::get_dp_links: Interface id $iid: ".
				   "Remote Device IP not found: $r_ip");
		}
            }
	}
        if ( !$rem_dev && $r_id ) {  
            foreach my $rem_id (split ';', $r_id){
                if ( $rem_id =~ /($MAC)/i ){
                    my $mac = PhysAddr->format_address($1);
                    if ( !exists $allmacs->{$mac} ){
                        $logger->debug("Topology::get_dp_links: Interface id $iid: ".
				       "Remote Device MAC not found: $mac");
			next;
		    }
		    $rem_dev = $allmacs->{$mac};
		}elsif ( $rem_id =~ /($IP)/ ){
		    # Turns out that some devices send IP addresses as IDs
		    my $decimalip = Ipblock->ip2int($1);
		    $rem_dev = $allips->{$decimalip};
		    last if $rem_dev;
		    unless ($rem_dev) {
			$logger->debug("Topology::get_dp_links: Interface id $iid: ".
				       "Remote Device IP not found: $rem_id");
		    }
		}else{
		    # Try to find the device name
		    $rem_dev = Device->search(sysname=>$rem_id)->first 
			|| Device->search(name=>$rem_id)->first;
		    unless ($rem_dev) {
			$logger->debug("Topology::get_dp_links: Interface id $iid: ".
				       "Remote Device name not found: $rem_id");
		    }
		}
		last if $rem_dev;
            }
            unless ( $rem_dev ) {
                $logger->debug("Topology::get_dp_links: Interface id $iid: ".
			       "Remote Device not found: $r_id");
            }
        } 

	unless ( $rem_dev ) {
	    if ( $class->config->get('ADD_UNKNOWN_DP_DEVS') ){
		if ( $r_ip ){
		    foreach my $ip ( split ';', $r_ip ) {
			if ( Ipblock->validate($ip) ){
			    $ips2discover{$ip} = '';
			    $logger->debug("Topology::get_dp_links: Interface id $iid: ".
					   "Adding remote device $ip to discover list");
			}
		    }
		}elsif ( $r_id ){
		    foreach my $rem_id ( split ';', $r_id ) {
			if ( $rem_id =~ /($IP)/ ){
			    my $ip = $1;
			    if ( Ipblock->validate($ip) ){
				$ips2discover{$ip} = '';
				$logger->debug("Topology::get_dp_links: Interface id $iid: ".
					       "Adding remote device $ip to discover list");
			    }
			}
		    }
		}
	    }else{
		my $str = "";
		$str .= "id=$r_id"   if $r_id;
		$str .= ", ip=$r_ip" if $r_ip;
		my $int = Interface->retrieve($iid);
		$logger->warn(sprintf("Topology::get_dp_links: %s: ".
				      "Remote Device not found: %s", $int->get_label, $str));
	    }
	    next;
	}

       # Now we have a remote device in $rem_dev
        if ( $r_port ) {
	    my $rem_int;
            foreach my $rem_port ( split ';', $r_port ) {
                # Try name first, then number, then description (if it is unique)
                $rem_int = Interface->search(device=>$rem_dev, name=>$rem_port)->first
		    || Interface->search(device=>$rem_dev, number=>$rem_port)->first;
		unless ( $rem_int ){
		    my @ints = Interface->search(device=>$rem_dev, description=>$rem_port);
		    $rem_int = $ints[0] if ( scalar @ints == 1 );
		}
                if ( $rem_int ){
                    $links{$iid} = $rem_int->id;
                    $links{$rem_int->id} = $iid;
		    $logger->debug(sprintf("Topology::get_dp_links: Found link: %d -> %d", 
					   $iid, $rem_int->id));
		    last;
                }
            }
	    unless ( $rem_int ){
		my $int = Interface->retrieve($iid);
		my $dev = ref($rem_dev) ? $rem_dev : Device->retrieve($rem_dev);
		$logger->warn(sprintf("Topology::get_dp_links: %s: Port %s not found in Device: %s", 
				      $int->get_label, $r_port, $dev->get_label));
	    }
        }else{
	    my $int = Interface->retrieve($iid);
            $logger->warn(sprintf("Topology::get_dp_links: %s: Remote Port not defined", $int->get_label));
        }
    }

    $logger->debug(sprintf("Topology::get_dp_links: Links determined in %s", 
			   $class->sec2dhms(time - $start)));
    
    if ( keys %ips2discover ){
	$logger->info("Topology::get_dp_links: Discovering unknown neighbors");
	Device->snmp_update_parallel(hosts=>\%ips2discover);
	$logger->info("Topology::get_dp_links: You may have to discover topology again to make sure any newly added neighbors are linked");
    }
    return \%links;
}

###################################################################################################
=head2 get_fdb_links - Get links between devices based on Forwarding Database (FDB) information

  Arguments:  
    none
  Returns:    
    Hashref with link info
  Example:
    my $links = Netdot::Model::Topology->get_fdb_links;

=cut
sub get_fdb_links {
    my ($class, %argv) = @_;
    $class->isa_class_method('get_fdb_links');
    my $start = time;
    my $dbh   = $class->db_Main;

    # Build a hash with device base macs for faster lookups later
    my $base_macs_q = $dbh->selectall_arrayref("
       SELECT  device.id, physaddr.address 
       FROM    device, physaddr
       WHERE   device.physaddr=physaddr.id");
    my %base_macs;
    foreach my $row ( @$base_macs_q ) {
	my ($id, $address) = @$row;
	$base_macs{$id} = $address;
    }

    # This value loosely represents a perceived completeness of the forwarding tables.
    # It is used to determine how much our results are to be trusted.
    # The closer this value is to 1 (that is, 100%), the stricter this code is about
    # reporting discovered links.  In our experience, surprisingly low values (25%)
    # yield surprisingly accurate results.
    my $fdb_completeness_ratio = Netdot->config->get('FDB_COMPLETENESS_RATIO') || .5;
    $logger->debug("FDB_COMPLETENESS_RATIO > $fdb_completeness_ratio");

    # For each VLAN we analyze, we can't assume that all devices with memberships on 
    # those VLANs are on the same physical segment.  For that reason, this code tries
    # to find possible 'islands' of devices in each vlan.  We've seen cases where
    # special purpose devices that connect to every VLAN (for management purposes)
    # cause this to break.  We then provide the user with this configuration option to
    # improve the reliability of this code.
    my %excluded_devices;
    if ( defined Netdot->config->get('FDB_EXCLUDE_DEVICES') ){
	foreach my $mac ( @{Netdot->config->get('FDB_EXCLUDE_DEVICES')} ){
	    $mac = PhysAddr->format_address($mac);
	    my $addr = PhysAddr->search(address=>$mac)->first;
	    next unless $addr;
	    my $device = Device->search(physaddr=>$addr)->first;
	    next unless $device;
	    $excluded_devices{$device->id} = 1 if $device;
	}    
    }

    # Find the most recent query for every Vlan
    my $vlanstatement = $dbh->prepare("
        SELECT MAX(tstamp), interfacevlan.vlan
        FROM fwtable, interfacevlan, device, interface
        WHERE fwtable.device = device.id
            AND interface.device = device.id
            AND interfacevlan.interface = interface.id
        GROUP BY interfacevlan.vlan");
    $vlanstatement->execute;

    my ($maxtstamp, $vlan);
    $vlanstatement->bind_columns(\$maxtstamp, \$vlan);

    my $fdbstatement = $dbh->prepare_cached("
            SELECT   fwtable.device, interface.id, physaddr.address
            FROM     interface, interfacevlan, fwtable, fwtableentry, physaddr
            WHERE    fwtable.device = interface.device
                AND  fwtable.tstamp = ?
                AND  fwtableentry.fwtable = fwtable.id
                AND  fwtableentry.interface = interface.id
                AND  interfacevlan.vlan = ?
                AND  interfacevlan.interface = interface.id
                AND  fwtableentry.physaddr = physaddr.id
        ");

    my %links;  # The links we find go here

    my %devices; # Device ids to Device objects -- just for debugging
    foreach my $device ( Device->retrieve_all ){
        $devices{$device->id} = $device;
    }

    my %infrastructure_macs = %{ PhysAddr->infrastructure() };
    my %interface_macs;
    my $int_macs_q = $dbh->selectall_arrayref("SELECT physaddr.address, interface.id 
                                               FROM   physaddr, interface
                                               WHERE  interface.physaddr=physaddr.id");
    foreach my $row ( @$int_macs_q ){
	my ( $address, $interface ) = @$row;
	$interface_macs{$address} = $interface;
    }

    # Some utility functions
    #
    sub hash_intersection {
	my ($a, $b) = @_;
	my %combo = ();
	for my $k (keys %$a) { $combo{$k} = 1 if (exists $b->{$k}) }
	return \%combo;
    }
    sub hash_union {
	my ($a, $b) = @_;
	my %combo = ();
	for my $k (keys %$a) { $combo{$k} = 1 }
	for my $k (keys %$b) { $combo{$k} = 1 }
	return \%combo;
    }
    # Returns true if hashes have at least one key in common
    sub hash_match {
	my ($a, $b) = @_;
	my $smallest = (scalar keys %$a < scalar keys %$b)? $a : $b;
	my $largest = ( $smallest == $a )? $b : $a;
	for my $k (keys %$smallest) { return 1 if (exists $largest->{$k}) }
	return 0;
    }
    
    # Find groups of devices on the same physical segment by checking to 
    # see if they have addresses in common
    sub break_into_groups {
	my (%argv) = @_;
	my ($class, $device_addresses, $devices, $infrastructure_macs, $excluded_devices) 
	    = @argv{'class', 'device_addresses', 'devices', 'infrastructure_macs', 'excluded_devices'};
	
	$logger->debug(" " . (scalar keys %$device_addresses) . " devices");
	my (%admap, %damap);
	foreach my $device ( keys %$device_addresses ){
	    # Ignore devices that can affect the grouping results
	    next if ( exists $excluded_devices->{$device} );
	    $logger->debug("    " . (scalar keys %{$device_addresses->{$device}}) . " addresses on device $device");
	    foreach my $address (keys %{$device_addresses->{$device}}) {
		$admap{$address}{$device}   = 1;
		$damap{$device}{$address} = 1;
	    }
	}

	my @groups;

	# This threshold represents the maximum number of layer2 devices that 
	# should be expected to exist in a given layer2 network
	my $threshold = Netdot->config->get('FDB_MAX_NUM_DEVS_IN_SEGMENT');

	# A variation of depth-first search
	my %seen;
	foreach my $address ( keys %admap ){
	    next if ( exists $infrastructure_macs->{$address} );
	    next if exists $seen{$address};
	    my (@astack, @dstack);
	    push @astack, $address;
	    my %group;
	    while ( @astack || @dstack ){
		if ( @astack ){
		    my $address = pop @astack;
		    next if exists $seen{$address};
		    $seen{$address} = 1;
		    my $num_devs = scalar keys %{ $admap{$address} };
		    if ( $num_devs > $threshold ){
			$logger->info("  Topology::get_fdb_links: Skipping too popular address $address ".
				      "(num_devs $num_devs > threshold $threshold)");
			next;
		    }

		    foreach my $device ( keys %{$admap{$address}} ){
			next if exists $seen{$device};
			push @dstack, $device;
		    }
		}
		if ( @dstack ){
		    my $device = pop @dstack;
		    next if exists $seen{$device};
		    $seen{$device} = 1;
		    $group{$device} = 1;
		    foreach my $address ( keys %{$damap{$device}} ){
			next if exists $seen{$address};
			next if ( exists $infrastructure_macs->{$address} );
			push @astack, $address;
		    }
		}
	    }
	    push @groups, \%group;
	}
	return \@groups;
    }
    
    while ( $vlanstatement->fetch ) {
	my @single_entry_links;
        my $vid = Vlan->retrieve(id=>$vlan)->vid;
        $logger->debug("Discovering how vlan " . $vid . " was connected at $maxtstamp");
	
        $fdbstatement->execute($maxtstamp, $vlan);
        
        my ($device, $ifaceid, $address);
        $fdbstatement->bind_columns(\$device, \$ifaceid, \$address);
	
        my $d = {};
        while ( $fdbstatement->fetch ){
	    next if ( exists $excluded_devices{$device} );
	    $d->{$device}{$ifaceid}{$address} = 1;
	}

	if ( 1 >= keys %$d ){
	    $logger->debug("  Only one device on vlan $vid");
	    next;
	}

	$logger->debug("vlan " . $vid . " has " . (scalar keys %$d) .  " devices at time $maxtstamp");
	$logger->debug("Creating a hash of addresses keyed by device");
	my $device_addresses = {};
	foreach my $device (keys %$d) {
	    $device_addresses->{$device} = {} unless exists $device_addresses->{$device};
	    foreach my $interface (keys %{$d->{$device}}) {
		# This should find non-bridging devices connected to this interface
		if ( 1 == scalar keys %{$d->{$device}{$interface} }){
		    my $address = (keys %{$d->{$device}{$interface}})[0];
		    if ( my $neighbor = $interface_macs{$address} ){
			push @single_entry_links, [$interface, $neighbor];
		    }
		}
		$device_addresses->{$device} = &hash_union($device_addresses->{$device}, 
							   $d->{$device}{$interface})
	    }
	}
	my $groups;
	$logger->debug("  Breaking devices up into separate layer2 networks");
	$groups = &break_into_groups(class               => $class, 
				     device_addresses    => $device_addresses, 
				     devices             => \%devices, 
				     infrastructure_macs => \%infrastructure_macs, 
				     excluded_devices    => \%excluded_devices,
	    );
	
	$logger->debug("  We now have " . scalar @$groups . " groups");
	
	foreach my $group ( @$groups ) {
	    my @possiblelinks;
	    if ( $logger->is_debug ){
		my @lbls = map { $devices{$_}->get_label } keys %$group;
		$logger->debug("  This group has: " . (join ', ', @lbls));
	    }
	    my $num_devs = scalar keys %$group;
	    next if ( 1 == $num_devs );

	    # Only consider base MACs
	    my %universal;
	    foreach my $device ( keys %$group ){
		$universal{$base_macs{$device}} = 1 if ( exists $base_macs{$device} );
	    }
	    my $universal_size = scalar keys %universal;
	    $logger->debug("  Universal contains: " . (join ', ', keys %universal));
	    
	    $logger->debug("  Starting interface checks");
	    foreach my $device ( keys %$group ){
		next if ( 0 == scalar keys %{$device_addresses->{$device}} );
		
		foreach my $device2 ( keys %$group ) {
		    next if ( $device2 == $device );
		    next if ( 0 == scalar keys %{$device_addresses->{$device2}} );
		    
		    foreach my $interface (keys %{$d->{$device}}) {
			my $ihash = $d->{$device}{$interface};
			next if ( 0 == scalar keys %$ihash );

			my $r_ihash = &hash_intersection($ihash, \%universal);

			foreach my $interface2 (keys %{$d->{$device2}}) {
			    my $ihash2 = $d->{$device2}{$interface2};
			    next if (0 == scalar keys %$ihash2);

			    if ( 0 == scalar keys %{&hash_intersection($ihash2, $ihash)} ){

				my $r_ihash2        = &hash_intersection($ihash2, \%universal);
				my $i_address_union = &hash_union($r_ihash, $r_ihash2);
				my $combo_size      = scalar keys %$i_address_union;
				my $percentage      = $combo_size / $universal_size;
				
				if ( $percentage > $fdb_completeness_ratio ){
				    push @possiblelinks, [ $percentage, $interface, $interface2 ];
				}
			    }
			}
		    }
		}
	    }
	    
	    $logger->debug("   " . (scalar @possiblelinks) . " possible links");
	    
	    @possiblelinks = sort { $b->[0] <=> $a->[0] } @possiblelinks;
	    foreach my $l ( @possiblelinks ){
		my ($percent, $from, $to) = @$l;
		next if ( exists $links{$from} );
		next if ( exists $links{$to} );
		if ( $logger->is_debug() ){
		    my $toi   = Interface->retrieve(id=>$to);
		    my $fromi = Interface->retrieve(id=>$from);
		    $logger->debug("Topology::get_fdb_links: Found link (" . int(100*$percent) . "%): " 
				   . $fromi->get_label . " -> " . $toi->get_label );
		}
		$links{$from} = $to;
		$links{$to}   = $from;
	    }
	}
	# Single entry links
	foreach my $l ( @single_entry_links ){
	    my ($from, $to) = @$l;
	    next if ( exists $links{$from} );
	    next if ( exists $links{$to} );
	    if ( $logger->is_debug() ){
		my $toi   = Interface->retrieve(id=>$to);
		my $fromi = Interface->retrieve(id=>$from);
		$logger->debug("Topology::get_fdb_links: Found link (single entry): " 
			       . $fromi->get_label . " -> " . $toi->get_label );
	    }
	    $links{$from} = $to;
	    $links{$to}   = $from;
	}

    }


    $logger->debug(sprintf("Topology::get_fdb_links: Links determined in %s", 
			   $class->sec2dhms(time - $start)));
    return \%links;
    
}

###################################################################################################
=head2 get_stp_links - Get links between all devices based on STP information

  Arguments:  
    None
  Returns:    
    Hashref with link info
  Example:
    my $links =Netdot::Model::Topology->get_stp_links();

=cut
sub get_stp_links {
    my ($class, %argv) = @_;
    $class->isa_class_method('get_stp_links');
    my $start = time;
    my (%stp_roots, %stp_links);
    my $it = Device->retrieve_all;
    while ( my $dev = $it->next ){
	foreach my $stp_instance ( $dev->stp_instances() ){
	    if ( my $root = $stp_instance->root_bridge ){
		$stp_roots{$root}++;
	    }
	}
    }
    my $devicemacs = Device->get_macs_from_all();
    # Determine links
    foreach my $root ( keys %stp_roots ){
	my $links = $class->get_tree_stp_links(root=>$root, devicemacs=>$devicemacs);
	map { $stp_links{$_} = $links->{$_} } keys %$links;
    }
    $logger->debug(sprintf("Topology::get_stp_links: Links determined in %s", 
			   $class->sec2dhms(time - $start)));
    
    return \%stp_links;
}

###################################################################################################
=head2 get_tree_stp_links - Get links between devices in a Spanning Tree

  Arguments:  
    Hashref with the following keys:
    root  - Address of Root bridge
    devicemacs - Hashref of Device MACs
  Returns:    
    Hashref with link info
  Example:
    my $links = Netdot::Model::Topology->get_tree_stp_links(root=>'DEADDEADBEEF');

=cut
sub get_tree_stp_links {
    my ($class, %argv) = @_;
    $class->isa_class_method('get_tree_stp_links');

    defined $argv{root} || $class->throw_fatal("Missing required argument: root");
    my $allmacs = $argv{devicemacs} || $class->throw_fatal("Missing required argument: devicemacs");
    
    # Retrieve all the InterfaceVlan objects that participate in this tree
    my %ivs;
    my @stp_instances = STPInstance->search(root_bridge=>$argv{root});
    map { map { $ivs{$_->id} = $_ } $_->stp_ports } @stp_instances;
    

    # Run the analysis.  The designated bridge on a given segment will 
    # have its own base MAC as the designated bridge and its own STP port ID as 
    # the designated port.  The non-designated bridge will point to the 
    # designated bridge instead.
    my %links;
    $logger->debug(sprintf("Topology::get_tree_stp_links: Determining topology for STP tree with root at %s", 
			   $argv{root}));

    my (%far, %near);
    foreach my $ivid ( keys %ivs ){
	my $iv = $ivs{$ivid};
	if ( defined $iv->stp_state && $iv->stp_state =~ /^forwarding|blocking$/ ){
	    if ( $iv->stp_des_bridge && scalar $iv->interface->device ){
		my $des_b     = $iv->stp_des_bridge;
		my $des_p     = $iv->stp_des_port;
		my $int       = $iv->interface->id;
		my $device_id = $iv->interface->device->id;
		# Now, the trick is to determine if the MAC in the designated
		# bridge value belongs to this same switch
		# It can either be the base bridge MAC, or the MAC of one of the
		# interfaces in the switch
		next unless exists $allmacs->{$des_b};
		my $des_device = $allmacs->{$des_b};

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
		$logger->debug(sprintf("Topology::get_tree_stp_links: Found link: %d -> %d", 
				       $int, $r_int));
	    }else{
		# Octet representations may not match
		foreach my $r_des_p ( keys %{$near{$des_b}} ){
		    if ( $class->_cmp_des_p($r_des_p, $des_p) ){
			my $r_int = $near{$des_b}{$r_des_p};
			$links{$int} = $r_int;
			$logger->debug(sprintf("Topology::get_tree_stp_links: Found link: %d -> %d", 
					       $int, $r_int));
		    }
		}
	    }
	}else{
	    $logger->debug(sprintf("Topology::get_tree_stp_links: Designated bridge %s not found", 
				   $des_b));
	}
    }
    return \%links;
}

###################################################################################################
=head2 get_p2p_links - Get Point-to-Point links based on network prefix

    Take advantage of the fact that point to point links between routers are usually configured
    to use IP subnets of /30 prefix length.  

  Arguments:  
    None
  Returns:    
    Hashref with link info
  Example:
    my $links = Netdot::Model::Topology->get_p2p_links();

=cut
sub get_p2p_links {
    my ($class, %argv) = @_;
    $class->isa_class_method('get_p2p_links');
    my $start = time;
    my %links;
    my @blocks = Ipblock->search(prefix=>'30');
    foreach my $block ( @blocks ){
	next unless ( $block->status->name eq 'Subnet' );
	$logger->debug(sprintf("Topology::get_p2p_links: Checking Subnet %s",
			       $block->get_label));
	my @ips = $block->children;
	if ( scalar(@ips) == 2 ){
	    my @ints;
	    foreach my $ip ( @ips ){
		if ( $ip->interface ){
		    my $type = $ip->interface->type || 'unknown';
		    # Ignore 'propVirtual' interfaces, sice most likely these
		    # are not where the actual physical connection happens
		    push @ints, $ip->interface if ( $type ne 'propVirtual' );
		}
	    }
	    if ( scalar(@ints) == 2 ){
		$logger->debug(sprintf("Topology::get_p2p_links: Found link: %d -> %d", 
				       $ints[0], $ints[1]));
		$links{$ints[0]} = $ints[1];
	    }
	}
    }
    $logger->debug(sprintf("Topology::get_p2p_links: Links determined in %s", 
			   $class->sec2dhms(time - $start)));
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
    my ($class, $a, $b) = @_;
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

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 University of Oregon, all rights reserved.

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

