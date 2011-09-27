package Netdot::Model::Device;

use base 'Netdot::Model';
use warnings;
use strict;
use SNMP::Info;
use Netdot::Util::DNS;
use Netdot::Topology;
use Parallel::ForkManager;
use Data::Dumper;

# Timeout seconds for SNMP queries 
# (different from SNMP connections)
my $TIMEOUT = Netdot->config->get('SNMP_QUERY_TIMEOUT');

# Define some signal handlers
$SIG{ALRM} = sub{ die "timeout" };

# Some regular expressions
my $IPV4        = Netdot->get_ipv4_regex();

# Other fixed variables
my $MAXPROCS    = Netdot->config->get('SNMP_MAX_PROCS');

# Objects we need here
my $logger      = Netdot->log->get_logger('Netdot::Model::Device');

my %IGNOREDVLANS;
map { $IGNOREDVLANS{$_}++ } @{ Netdot->config->get('IGNOREVLANS') };

my @MIBDIRS;
foreach my $md ( @{ Netdot->config->get('SNMP_MIB_DIRS') } ){
    push @MIBDIRS, Netdot->config->get('NETDOT_PATH')."/".$md;
}

=head1 NAME

Netdot::Model::Device - Network Device Class

=head1 SYNOPSIS

=head1 CLASS METHODS
=cuts


############################################################################
=head2 search - Search Devices

    Overrides base method to extend functionality:

  Arguments:
    Hash with the following keys:
      name         - Can be either a string, RR object RR id or IP address, 
                     String can be FQDN or hostname.
      producttype  - Search for all Devices of a certain product type

      The rest of the fields in the Device table.
  Returns:
    Array of Device objects or iterator (depending on context)

  Exampless:    
    my @devs = Device->search(name=>'localhost.localdomain');

=cut
sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    # Class::DBI::search() might include an extra 'options' hash ref
    # at the end.  In that case, we want to extract the 
    # field/value hash first.
    my $opts = @args % 2 ? pop @args : {}; 
    my %argv = @args;
    
    my $dev;
    
    if ( exists $argv{name} ){
	my $foundname = 0;
	if ( ref($argv{name}) =~ /RR/ ){ 
	    # We were passed a RR object.  
	    # Proceed as regular search
	}elsif ( Ipblock->matches_ip($argv{name}) ){
	    # Looks like an IP address
	    if ( my $ip = Ipblock->search(address=>$argv{name})->first ){
		if ( $ip->interface && ($dev = $ip->interface->device) ){
		    $argv{name} = $dev->name;
		    $foundname = 1;
		}else{
		    $logger->debug(sub{"Device::search: Address $argv{name} exists but no Device associated"});
		}
	    }else{
		$logger->debug(sub{"Device::search: $argv{name} not found in DB"});
	    }
	}
	if ( !$foundname ){
	    # Notice that we could be looking for a RR with an IP address as name
	    # So go on.
	    # name is either a string or a RR id
	    if ( $argv{name} =~ /\D+/ ){
		# argument has non-digits, so it's not an id.  Look up RR name
		if ( my @rrs = RR->search(name=>$argv{name}) ){
		    if ( scalar @rrs == 1 ){
			$argv{name} = $rrs[0];
		    }else{
			# This means we have the same RR name on different zones
			# Try to resolve the name and look up IP address
			if ( my @ips = Netdot->dns->resolve_name($argv{name}) ){
			    foreach my $ip ( @ips ){
				$logger->debug(sub{"Device::search: $argv{name} resolves to $ip"});
				if ( my $ip = Ipblock->search(address=>$ip)->first ){
				    if ( $ip->interface && ($dev = $ip->interface->device) ){
					$argv{name} = $dev->name;
				    }elsif ( my @arecords = $ip->arecords ){
					# The IP is not assigned to any device interfaces
					# but there might be a device with a name and A record
					# associated with this IP
					$argv{name} = $arecords[0]->rr;
				    }else{
					$argv{name} = 0;
				    }
				}
			    }
			}
		    }
		}else{
		    # No use searching for a non-digit string in the name field
		    $argv{name} = 0;
		}
	    }
	}
    }elsif ( exists $argv{producttype} ){
	return $class->search_by_type($argv{producttype});
    }

    # Proceed as a regular search
    return $class->SUPER::search(%argv, $opts);
}

############################################################################
=head2 search_address_live
    
    Query relevant devices for ARP and FWT entries in order to locate 
    a particular address in the netwrok.

  Arguments: 
    mac     - MAC address (required unless ip is given)
    ip      - IP address (required unless mac is given)
    vlan    - VLAN id (optional but useful)
  Returns: 
    Hashref with following keys:
    edge - Edge port interface id
    arp  - Hashref with key=interface, value=hashref with key=ip, value=mac
    fwt  - Hashref with key=interface, value=number of macs
  Examples:
    my $info = Device->search_address_live(mac=>'DEADDEADBEEF', vlan=60);

=cut
sub search_address_live {
    my ($class, %argv) = @_;
    $class->isa_class_method('search_address_live');
    $class->throw_fatal("Device::search_address_live: Cannot proceed without a MAC or IP")
	unless ( $argv{mac} || $argv{ip} );

    my (@fwt_devs, @arp_devs);
    my ($vlan, $subnet);
    my %results;

    if ( $argv{vlan} ){
	$vlan = Vlan->search(vid=>$argv{vlan})->first;
	$class->throw_user("Cannot find VLAN id $argv{vlan}\n")
	    unless $vlan;
    }

    if ( $argv{ip} ){
	my $ipblock = Ipblock->search(address=>$argv{ip})->first;
	if ( $ipblock ){
	    if ( $ipblock->is_address ){
		$subnet = $ipblock->parent;
	    }else{
		$subnet = $ipblock;
	    }
	    if ( !$vlan ){
		$vlan = $subnet->vlan if $subnet->vlan;
	    }
	    @arp_devs = @{$subnet->get_devices()};
	}else{
	    $subnet = Ipblock->get_covering_block(address=>$argv{ip});
	    if ( $subnet ){
		if ( !$vlan ){
		    $vlan = $subnet->vlan if ( $subnet && $subnet->vlan );
		}
		@arp_devs = @{$subnet->get_devices()};
	    }
	}
    }

    if ( $vlan ){
	my @ivlans = $vlan->interfaces;
	my %fwt_devs;
	foreach my $iface ( map { $_->interface } @ivlans ){
	    $fwt_devs{$iface->device->id} = $iface->device;
	}
	@fwt_devs = values %fwt_devs;
	
	if ( !@arp_devs && !$subnet ){
	    foreach my $subnet  ( $vlan->subnets ){
		@arp_devs = @{$subnet->get_devices()};
	    }
	}
    }else{
	if ( $subnet && !@fwt_devs ){
	    @fwt_devs = @{$subnet->get_devices()};
	}else{
	    $class->throw_user("Device::search_address_live: Cannot proceed without VLAN or IP information\n");
	}
    }

    my (@fwts);
    my %routerports;
    foreach my $dev ( @arp_devs ){
	my $cache;
	$dev->_netdot_rebless();
	eval {
	    $cache = $class->_exec_timeout($dev->fqdn, sub{ return $dev->get_arp() });
	};
	$logger->debug($@) if $@;
	if ( $cache ){
	    foreach my $intid ( keys %$cache ){
		foreach my $ip ( keys %{$cache->{$intid}} ){
		    next if ( $argv{ip} && ($ip ne $argv{ip}) );
		    my $mac = $cache->{$intid}->{$ip};
		    next if ( $argv{mac} && ($mac ne $argv{mac}) );
		    # We now have a mac address if we didn't have it yet
		    unless ( $argv{mac} ){
			$argv{mac} = $mac;
		    }
		    # Keep record of all the interfaces where this ip was seen
		    $routerports{$intid}{$ip} = $mac;
		    $results{mac} = $mac;
		    $results{ip}  = $ip;
		}
	    }
	}
	# Do not query all the routers unless needed.
	if ( %routerports ){
	    $results{routerports} = \%routerports;
	    last;
	}
    }

    # If we do not have a MAC at this point, there's no point in getting FWTs
    if ( $argv{mac} ){
	$results{mac} = $argv{mac};
	foreach my $dev ( @fwt_devs ){
	    my $fwt;
	    my %args;
	    $args{vlan} = $vlan->vid if ( $vlan );
	    eval {
		$fwt = $class->_exec_timeout($dev->fqdn, sub{ return $dev->get_fwt(%args) } );
	    };
	    $logger->debug($@) if $@;
	    push @fwts, $fwt if $fwt;
	}
	
	my %switchports;
	foreach my $fwt ( @fwts ){
	    foreach my $intid ( keys %{$fwt} ){
		foreach my $mac ( keys %{$fwt->{$intid}} ){
		    next if ( $mac ne $argv{mac} );
		    # Keep record of all the interfaces where it was seen
		    # How many MACs were on that interface is essential to 
		    # determine the edge port
		    $switchports{$intid} = scalar(keys %{$fwt->{$intid}});
		}
	    }
	}
	$results{switchports} = \%switchports if %switchports;

	# Now look for the port with the least addresses
	my @ordered = sort { $switchports{$a} <=> $switchports{$b} } keys %switchports;
	$results{edge} = $ordered[0] if $ordered[0];
    }
    
    if ( %results ){
	if ( $results{mac} ){
	    if ( my $vendor = PhysAddr->vendor($results{mac}) ){
		$results{vendor} = $vendor;
	    }
	}
	if ( $results{ip} ){
	    if ( my $name = Netdot->dns->resolve_ip($results{ip}) ){
		$results{dns} = $name;
	    }
	}
	return \%results;
    }
}


############################################################################
=head2 search_like -  Search for device objects.  Allow substrings

    We override the base class to:
     - allow 'name' to be searched as part of a hostname
     - search 'name' in aliases field if a RR is not found
     - add 'zone' to the list of arguments

  Arguments: 
    Hash with key/value pairs

  Returns: 
    Array of Device objects or iterator

  Exampless:
    my @switches = Device->search_like(name=>'-sw');

=cut
sub search_like {
    my ($class, %argv) = @_;
    $class->isa_class_method('search_like');

    if ( exists $argv{name} ){
	my %args = (name=>$argv{name});
	$args{zone} = $argv{zone} if $argv{zone};
	if ( my @rrs = RR->search_like(%args) ){
	    return map { $class->search(name=>$_) } @rrs;
	}elsif ( $class->SUPER::search_like(aliases=>$argv{name}) ){
	    return $class->SUPER::search_like(aliases=>$argv{name});
	}
	$logger->debug(sub{"Device::search_like: $argv{name} not found"});
	return;
    }elsif ( exists $argv{producttype} ){
	return $class->search_by_type($argv{producttype});
    }else{
	return $class->SUPER::search_like(%argv);
    }
}


############################################################################
=head2 assign_name - Determine and assign correct name to device

    This method will try to find or create an appropriate 
    Resource Record for a Device, given a hostname or ip address,
    and optionally a sysname as a backup in case that name or IP do
    not resolve.

  Arguments: 
    hash with following keys:
        host    - hostname or IP address (string)
        sysname - System name value from SNMP
  Returns:    
    RR object if successful
  Examples:
    my $rr = Device->assign_name($host)
=cut
sub assign_name {
    my ($class, %argv) = @_;
    $class->isa_class_method('assign_name');
    my $host    = $argv{host};
    my $sysname = $argv{sysname};
    $class->throw_fatal("Model::Device::assign_name: Missing arguments: host")
	unless $host;

    # An RR record might already exist
    if ( defined $host && (my @rrs = RR->search(name=>$host)) ){
	if ( scalar @rrs == 1 ){
	    $logger->debug(sub{"Name $host exists in DB"});
	    return $rrs[0];
	}
    }
    # An RR matching $host does not exist, or the name exists in 
    # multiple zones
    my @ips;
    if ( Ipblock->matches_ip($host) ){
	# we were given an IP address
	if ( my $ipb = Ipblock->search(address=>$host)->first ){
	    if ( $ipb->interface && ( my $dev = $ipb->interface->device ) ){
		$logger->debug("Device::assign_name: A Device with IP $host already exists: " . $dev->get_label);
		return $dev->name;
	    }
	}
	push @ips, $host;
    }else{
	# We were given a name (not an address)
	# Resolve to an IP address
	if ( defined $host && (@ips = Netdot->dns->resolve_name($host)) ){
	    my $str = join ', ', @ips;
	    $logger->debug(sub{"Device::assign_name: $host resolves to $str"});
	}else{
	    $logger->debug(sub{"Device::assign_name: $host does not resolve"});
	}
    }
    my $fqdn;
    my %args;
    my $ip;
    if ( @ips ){
	# At this point, we were either passed an IP
	# or we got one or more from DNS.  The idea is to obtain a FQDN
	# We'll use the first IP that resolves
	foreach my $i ( @ips ){
	    if ( $fqdn = Netdot->dns->resolve_ip($i) ){
		$logger->debug(sub{"Device::assign_name: $i resolves to $fqdn"});
		if ( my $rr = RR->search(name=>$fqdn)->first ){
		    $logger->debug(sub{"Device::assign_name: RR $fqdn already exists in DB"});
		    return $rr;
		}
		$ip = $i; 
		last;
	    }else{
		$logger->debug(sub{"Device::assign_name: $ip does not resolve"} );
	    }
	}
    }
    # At this point, if we haven't got a fqdn, then use the sysname argument, and if not given,
    # use the name or IP address passed as the host argument
    $fqdn ||= $sysname;
    $fqdn ||= $host;
    $fqdn = lc($fqdn);

    # Check if we have a matching domain
    if ( $fqdn =~ /\./  && !Ipblock->matches_ip($fqdn) ){
   	# Notice that we search the whole string.  That's because
	# the hostname part might have dots.  The Zone search method
	# will take care of that.
	if ( my $zone = (Zone->search(name=>$fqdn))[0] ){
            $args{zone} = $zone->name;
	    $args{name} = $fqdn;
	    $args{name} =~ s/\.$args{zone}//;
        }else{
	    $logger->debug(sub{"Device::assign_name: $fqdn not found" });
	    # Assume the zone to be everything to the right
	    # of the first dot. This might be a wrong guess
	    # but it is as close as I can get.
	    my @sections = split '\.', $fqdn;
	    $args{name} = shift @sections;
	    $args{zone} = join '.', @sections;
	}
    }else{
	$args{name} = $fqdn;
    }
    
    # Try to create the RR object
    # This will also create the Zone object if necessary
    my $rr = RR->insert(\%args);
    $logger->info(sprintf("Inserted new RR: %s", $rr->get_label));
    # Make sure name has an associated IP and A record
    if ( $ip ){
	my $ipb = Ipblock->search(address=>$ip)->first ||
	    Ipblock->insert({address=>$ip, status=>'Static'});
	my $rraddr = RRADDR->find_or_create({ipblock=>$ipb, rr=>$rr});
    }
    return $rr;
}

############################################################################
=head2 insert - Insert new Device
    
    We override the insert method for extra functionality:
     - More intelligent name assignment
     - Assign defaults
     - Assign contact lists

  Arguments:
    Hashref with Device fields and values, plus:
    contacts    - ContactList object(s) (array or scalar)
  Returns:
    New Device object

  Examples:
    my $newdevice = Device->insert(\%args);

=cut
sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');

    # name is required
    if ( !exists($argv->{name}) ){
	$class->throw_fatal('Model::Device::insert: Missing required arguments: name');
    }

    # Get the default owner entity from config
    my $config_owner  = Netdot->config->get('DEFAULT_DEV_OWNER');
    my $default_owner = Entity->search(name=>$config_owner)->first || Entity->search(name=>'Unknown')->first;

    # Assign defaults
    # These will be overridden by the given arguments

    my %devtmp = (
	community          => 'public',
	customer_managed   => 0,
	collect_arp        => 0,
	collect_fwt        => 0,
	canautoupdate      => 0,
	date_installed     => $class->timestamp,
	monitor_config     => 0,
	monitored          => 0,
	owner              => $default_owner,
	snmp_bulk          => $class->config->get('DEFAULT_SNMPBULK'),
	snmp_managed       => 0,
	snmp_polling       => 0,
	snmp_down          => 0,
	snmp_conn_attempts => 0,
	auto_dns           => $class->config->get('UPDATE_DEVICE_IP_NAMES'),
	);

    # Add given args (overrides defaults).
    # Extract special arguments that affect the inserted device
    my (@contacts, $info);
    foreach my $key ( keys %{$argv} ){
	if ( $key eq 'contacts' ){
	    @contacts = $argv->{contacts};
	}elsif ( $key eq 'info' ){
	    $info = $argv->{info};
	    $devtmp{snmp_managed} = 1;
	}else{
	    $devtmp{$key} = $argv->{$key};
	}
    }
    if ( exists $devtmp{snmp_managed} ){
	if ( !$devtmp{snmp_managed} ){
	    # Means it's being set to 0 or undef
	    # Turn off other flags
	    $devtmp{canautoupdate} = 0;
	    $devtmp{snmp_polling}  = 0;
	    $devtmp{collect_arp}   = 0;
	    $devtmp{collect_fwt}   = 0;
	}
    }


    ###############################################
    # Assign the correct name
    # argument 'name' can be passed either as a RR object
    # or as a string.
    if ( ref($argv->{name}) =~ /RR/ ){
	# We are being passed the RR object
	$devtmp{name} = $argv->{name};
    }else{
	# A string hostname was passed
	if ( my $rr = RR->search(name=>$argv->{name})->first ){
	    $devtmp{name} = $rr;
	}else{
	    $devtmp{name} = RR->insert({name=>$argv->{name}});
	}
    }
    if ( my $dbdev = $class->search(name=>$devtmp{name})->first ){
	$logger->debug(sprintf("Device::insert: Device %s already exists in DB as %s",
			       $argv->{name}, $dbdev->fqdn));
	return $dbdev;
    }

    $class->_validate_args(\%devtmp);
    my $self = $class->SUPER::insert( \%devtmp );
    
    if ( @contacts ){
	$self->add_contact_lists(@contacts);
    }else{
	$self->add_contact_lists();
    }

    return $self;
}

############################################################################
=head2 get_snmp_info - SNMP-query a Device for general information
    
    This method can either be called on an existing object, or as a 
    class method.

  Arguments:
    Arrayref with the following keys:
     host         - hostname or IP address (required unless called as object method)
     session      - SNMP Session (optional)
     communities  - SNMP communities
     version      - SNMP version
     sec_name     - SNMP Security Name
     sec_level    - SNMP Security Level
     auth_proto   - SNMP Authentication Protocol
     auth_pass    - SNMP Auth Key
     priv_proto   - SNMP Privacy Protocol
     priv_pass    - SNMP Privacy Key
     timeout      - SNMP timeout
     retries      - SNMP retries
     bgp_peers    - (flag) Retrieve bgp peer info
  Returns:
    Hash reference containing SNMP information
  Examples:
    
    Instance call:
    my $info = $device->get_snmp_info();

    Class call:
    my $info = Device->get_snmp_info(host=>$hostname, communities=>['public']);

=cut
sub get_snmp_info {
    my ($self, %args) = @_;
    my $class = ref($self) || $self;
    
    my %dev;

    my $sinfo = $args{session};
    if ( $sinfo ){
	$args{host} = $sinfo->{args}->{DestHost};
    }else{
	if ( ref($self) ){
	    if ( $self->snmp_target ){
		$args{host} = $self->snmp_target->address;
		$logger->debug(sub{"Device::get_snmp_info: Using configured target address: $args{host}"});
	    }else{
		$args{host} = $self->fqdn;
	    }
	}else {
	    $self->throw_fatal('Model::Device::get_snmp_info: Missing required parameters: host')
		unless $args{host};
	}
	# Get SNMP session
	my %sess_args;
	$sess_args{host} = $args{host};
	foreach my $arg ( qw( communities version timeout retries sec_name sec_level
                              auth_proto auth_pass priv_proto priv_pass) ){
	    $sess_args{$arg} = $args{$arg} if defined $args{$arg};
	}
	$sinfo = $self->_get_snmp_session(%sess_args);
    }

    $dev{_sclass} = $sinfo->class();

    # Assign the snmp_target by resolving the name
    # SNMP::Info still does not support IPv6, so for now...
    my @ips = Netdot->dns->resolve_name($args{host}, {v4_only=>1});
    $dev{snmp_target} = $ips[0] if defined $ips[0];

    $logger->debug("Device::get_snmp_info: SNMP target is $dev{snmp_target}");
    
    $dev{community}    = $sinfo->snmp_comm;
    $dev{snmp_version} = $sinfo->snmp_ver;

    ################################################################
    # SNMP::Info methods that return hash refs
    my @SMETHODS = qw( hasCDP e_descr
		       interfaces i_index i_name i_type i_alias i_description 
		       i_speed i_up i_up_admin i_duplex i_duplex_admin 
		       ip_index ip_netmask i_mac
		       i_vlan_membership qb_v_name v_name v_state
		       );

    if ( $sinfo->can('ipv6_addr_prefix') ){
	# This version of SNMP::Info supports fetching IPv6 addresses
	push @SMETHODS, qw(ipv6_addr_prefix);
    }

    if ( $self->config->get('GET_DEVICE_MODULE_INFO') ){
	push @SMETHODS, qw( e_type e_parent e_name e_class e_pos e_descr
                            e_hwver e_fwver e_swver e_model e_serial e_fru );
    }

    if ( $args{bgp_peers} || $self->config->get('ADD_BGP_PEERS')) {
	push @SMETHODS, qw( bgp_peers bgp_peer_id bgp_peer_as );
    }

    my %hashes;
    foreach my $method ( @SMETHODS ){
	$hashes{$method} = $sinfo->$method;
    }

    ################################################################
    # Device's global vars
    $dev{layers}       = $sinfo->layers;
    my $ipf = $sinfo->ipforwarding || 'unknown';
    $dev{ipforwarding} = ( $ipf eq 'forwarding') ? 1 : 0;
    $dev{sysobjectid}  = $sinfo->id;
    if ( defined $dev{sysobjectid} ){
	$dev{sysobjectid} =~ s/^\.(.*)/$1/;  # Remove unwanted first dot
	my %IGNORED;
	map { $IGNORED{$_}++ }  @{ $self->config->get('IGNOREDEVS') };
	if ( exists($IGNORED{$dev{sysobjectid}}) ){
	    $self->throw_user(sprintf("%s Product id %s ignored per configuration option (IGNOREDEVS)", 
				      $args{host}, $dev{sysobjectid}));
	}
    }

    $dev{model}          = $sinfo->model();
    $dev{os}             = $sinfo->os_ver();
    $dev{physaddr}       = $sinfo->b_mac() || $sinfo->mac();
    $dev{sysname}        = $sinfo->name();
    $dev{router_id}      = $sinfo->root_ip();
    $dev{sysdescription} = $sinfo->description();
    $dev{syscontact}     = $sinfo->contact();
    $dev{productname}    = $hashes{'e_descr'}->{1};
    $dev{manufacturer}   = $sinfo->vendor();
    $dev{serial_number}  = $sinfo->serial();

    $dev{syslocation}    = $sinfo->location();
    # Remove leading and trailing white space
    if ( $dev{syslocation} ){
	$dev{syslocation} =~ s/(\w+)\s+$/$1/;
	$dev{syslocation} =~ s/^\s+(\w+)/$1/;
    }
    ################################################################
    # Get STP (Spanning Tree Protocol) stuff

    my $collect_stp = 1;
    if ( ref($self) && !$self->collect_stp ){
	$collect_stp = 0;
    }
    
    if ( $self->config->get('GET_DEVICE_STP_INFO') && $collect_stp ){
	if ( defined $dev{physaddr} ){
	    $dev{stp_type} = $sinfo->stp_ver();
	    
	    if ( defined $dev{stp_type} && $dev{stp_type} ne 'unknown' ){
		# Get STP port id
		$hashes{'i_stp_id'} = $sinfo->i_stp_id;
		
		# Store the vlan status
		my %vlan_status;
		foreach my $vlan ( keys %{$hashes{v_state}} ){
		    my $vid = $vlan;
		    $vid =~ s/^1\.//;
		    $vlan_status{$vid} = $hashes{v_state}->{$vlan}; 
		}

		if ( $dev{stp_type} eq 'ieee8021d' || $dev{stp_type} eq 'mst' ){
		    
		    # Standard values (make it instance 0)
		    my $stp_p_info = $self->_get_stp_info(sinfo=>$sinfo);
		    foreach my $method ( keys %$stp_p_info ){
			$dev{stp_instances}{0}{$method} = $stp_p_info->{$method};
		    }
		    
		    # MST-specific
		    if ( $dev{stp_type} eq 'mst' ){
			# Get MST-specific values
			$dev{stp_mst_region} = $sinfo->mst_region_name();
			$dev{stp_mst_rev}    = $sinfo->mst_region_rev();
			$dev{stp_mst_digest} = $sinfo->mst_config_digest();
			
			# Get the mapping of vlans to STP instance
			$dev{stp_vlan2inst} = $sinfo->mst_vlan2instance();
			my $mapping = join ', ', 
			map { sprintf("%s=>%s", $_, $dev{stp_vlan2inst}->{$_}) } keys %{$dev{stp_vlan2inst}};
			$logger->debug(sub{"Device::get_snmp_info: $args{host} MST VLAN mapping: $mapping"});
			
			# Now, if there's more than one instance, we need to get
			# the STP standard info for at least one vlan on that instance.

			# Cisco case: query repeatedly for each "community@vlan_id"
			# Notice that we query every vlan on purpose. I have seen cases
			# where even though a vlan is mapped to a particular instance, the query
			# will not return the necessary values, but querying other vlans mapped to the same instance does

			
			if ( $sinfo->cisco_comm_indexing() ){
			    foreach my $vid ( keys %{$dev{stp_vlan2inst}} ){
				next if ( exists $IGNOREDVLANS{$vid} );
				next unless $vlan_status{$vid} eq 'operational';
				my $mst_inst = $dev{stp_vlan2inst}->{$vid};
				my $comm = $sinfo->snmp_comm . '@' . $vid;
				eval {
				    my $vsinfo = $class->_get_snmp_session('host'        => $args{host},
									   'communities' => [$comm],
									   'version'     => $sinfo->snmp_ver,
									   'sclass'      => $sinfo->class);
				    my $stp_p_info = $class->_exec_timeout( $args{host}, 
									    sub{  return $self->_get_stp_info(sinfo=>$vsinfo) } );
				    foreach my $method ( keys %$stp_p_info ){
					$dev{stp_instances}{$mst_inst}{$method} = $stp_p_info->{$method};
				    }

				    my $i_stp_info = $class->_exec_timeout( $args{host}, 
									    sub{  return $self->_get_i_stp_info(sinfo=>$vsinfo) } );
				    foreach my $field ( keys %$i_stp_info ){
					foreach my $i ( keys %{$i_stp_info->{$field}} ){
					    $dev{interface}{$i}{$field} = $i_stp_info->{$field}->{$i};
					}
				    }
				};
				if ( my $e = $@ ){
				    $logger->error(sprintf("Could not get SNMP session for %s with community %s",
							   $args{host}, $comm));
				    next;
				}
			    }
			}
		    }
		}elsif ( $dev{stp_type} =~ /pvst/i ){
		    # Get stp info for each vlan
		    # STPInstance numbers match vlan id's
		    if ( $sinfo->cisco_comm_indexing() ){
			my %vlans;
			foreach my $p ( keys %{$hashes{'i_vlan_membership'}} ){
			    my $vlans = $hashes{'i_vlan_membership'}->{$p};
			    map { $vlans{$_}++ } @$vlans; 
			}
			foreach my $vid ( keys %vlans ){
			    next if ( exists $IGNOREDVLANS{$vid} );
			    next unless $vlan_status{$vid} eq 'operational';
			    my $comm = $sinfo->snmp_comm . '@' . $vid;
			    eval {
				my $vsinfo = $class->_get_snmp_session('host'        => $args{host},
								       'communities' => [$comm],
								       'version'     => $sinfo->snmp_ver,
								       'sclass'      => $sinfo->class);
				my $stp_p_info = $class->_exec_timeout( $args{host}, 
									sub{  return $self->_get_stp_info(sinfo=>$vsinfo) } );
				foreach my $method ( keys %$stp_p_info ){
				    $dev{stp_instances}{$vid}{$method} = $stp_p_info->{$method};
				}

				my $i_stp_info = $class->_exec_timeout( $args{host}, 
									sub{  return $self->_get_i_stp_info(sinfo=>$vsinfo) } );
				foreach my $field ( keys %$i_stp_info ){
				    foreach my $i ( keys %{$i_stp_info->{$field}} ){
					$dev{interface}{$i}{$field} = $i_stp_info->{$field}->{$i};
				    }
				}
			    };
			    if ( my $e = $@ ){
				$logger->error(sprintf("Could not get SNMP session for %s with community %s",
						       $args{host}, $comm));
				next;
			    }
			}
		    }
		}
	    }
	}
    }

    # Set some defaults specific to device types
    if ( $dev{ipforwarding} ){
	$dev{bgplocalas}  =  $sinfo->bgp_local_as();
	$dev{bgpid}       =  $sinfo->bgp_id();
    }

    ################################################################
    # CDP/LLDP stuff
    if ( $hashes{hasCDP} ){
	# Call all the relevant methods
	my %dp_hashes;
	my @dp_methods = qw ( c_id c_ip c_port c_platform );
	foreach my $m ( @dp_methods ){
	    $dp_hashes{$m} = $sinfo->$m;
	}
	# Translate keys into iids
	my $c_ifs = $sinfo->c_if();
	while ( my ($key, $iid) = each %$c_ifs ){
	    next unless $iid;
	    foreach my $m ( @dp_methods ){
		next if !exists $dp_hashes{$m}->{$key};
		# SNMP::Info can include values from both LLDP and CDP
		# which means that for each port, we can have different
		# values.  We save them all in a comma-separated list
		if ( exists $hashes{$m}->{$iid} ){
		    # Use a hash for fast lookup
		    my %vals;
		    map { $vals{$_}++ } split ';', $hashes{$m}->{$iid};
		    if ( ! exists $vals{$dp_hashes{$m}->{$key}} ){
			# Append new value to list
			$vals{$dp_hashes{$m}->{$key}}++;
		    }
		    $hashes{$m}->{$iid} = join ';', keys %vals;
		}else{
		    $hashes{$m}->{$iid} = $dp_hashes{$m}->{$key};
		}
	    }
	}
    }

    ################################################################
    # Modules

    if ( $self->config->get('GET_DEVICE_MODULE_INFO') ){
	# DeviceModule field name to SNMP::Info method conversion table
	my %MFIELDS = ( name         => 'e_name',    type         => 'e_type',
			contained_in => 'e_parent',  class        => 'e_class',    
			pos          => 'e_pos',     hw_rev       => 'e_hwver',
			fw_rev       => 'e_fwver',   sw_rev       => 'e_swver',
			model        => 'e_model',   serial_number => 'e_serial',
			fru          => 'e_fru',     description  => 'e_descr',
	    );
	    
	foreach my $key ( keys %{ $hashes{e_class} } ){
	    $dev{module}{$key}{number} = $key;;
	    foreach my $field ( keys %MFIELDS ){
		my $method = $MFIELDS{$field};
		if ( defined($hashes{$method}->{$key}) && $hashes{$method}->{$key} =~ /\w+/ ){
		    if ( $field eq 'fru' ){
			# This is boolean
			$dev{module}{$key}{$field} = ( $hashes{$method}->{$key} eq 'true' )? 1 : 0;
		    }else{
			$dev{module}{$key}{$field} = $hashes{$method}->{$key};
		    }
		}
	    }
	}
	
    }


    ################################################################
    # Interface stuff
    
    sub _check_if_status_down{
	my ($dev, $iid) = @_;
	return 1 if ( (defined $dev->{interface}{$iid}{admin_status}) &&
		      ($dev->{interface}{$iid}{admin_status} eq 'down') );
	return 0;
    }
    
    ################################################################
    # IPv4 addresses and masks 
    #
    while ( my($ip,$iid) = each %{ $hashes{'ip_index'} } ){
	next if &_check_if_status_down(\%dev, $iid);
	next if Ipblock->is_loopback($ip);
	next if ( $ip eq '0.0.0.0' || $ip eq '255.255.255.255' );
	$dev{interface}{$iid}{ips}{$ip}{address} = $ip;
	$dev{interface}{$iid}{ips}{$ip}{version} = 4;
	if ( my $mask = $hashes{'ip_netmask'}->{$ip} ){
	    my ($subnet, $len) = Ipblock->get_subnet_addr(address => $ip, 
							  prefix  => $mask );
	    $dev{interface}{$iid}{ips}{$ip}{subnet} = "$subnet/$len";
	}
    }

    ################################################################
    # IPv6 addresses and prefixes
    # Stuff in this hash looks like this:
    # 2.16.32.1.4.104.13.1.0.2.0.0.0.0.0.0.0.9	=> 49.2.16.32.1.4.104.13.1.0.2.0.0.0.0.0.0.0.0.64
    #
    while ( my($key,$val) = each %{$hashes{'ipv6_addr_prefix'}} ){
	my ($iid, $addr, $pfx, $len);
	if ( $key =~ /^\d+\.\d+\.([\d\.]+)$/ ) {
	    $addr = $self->_octet_string_to_v6($1);
	}
	if ( $val =~ /^(\d+)\.\d+\.\d+\.([\d\.]+)\.(\d+)$/ ) {
	    # ifIndex, type, size, prefix length
	    $iid = $1; $len = $3;
	    $pfx = $self->_octet_string_to_v6($2);
	}
	if ( $iid && $addr && $pfx && $len ){
	    next if &_check_if_status_down(\%dev, $iid);
	    $dev{interface}{$iid}{ips}{$addr}{address} = $addr;
	    $dev{interface}{$iid}{ips}{$addr}{version} = 6;
	    $dev{interface}{$iid}{ips}{$addr}{subnet}  = "$pfx/$len";
	}else{
	    # What happened?
	    $logger->warn("$args{host}: Unrecognized ipv6_addr_prefix entry: $key => $val")
	}
    }


    ################################################################
    # IPv6 link-local addresses
    unless ( $self->config->get('IGNORE_IPV6_LINK_LOCAL') ){
	my $ipv6_index = $sinfo->ipv6_index();
	my ($iid, $addr);
	while ( my($key,$val) = each %$ipv6_index ){
	    if ( $key =~ /^\d+\.\d+\.([\d\.]+)$/ ) {
		$addr = $self->_octet_string_to_v6($1);
		next unless Ipblock->is_link_local($addr);
		$iid = $val;
		$dev{interface}{$iid}{ips}{$addr}{address} = $addr;
		$dev{interface}{$iid}{ips}{$addr}{version} = 6;
	    }else{
		# What happened?
		$logger->warn("$args{host}: Unrecognized ipv6_index entry: $key => $val")
	    }
	}
    }
    
    # Netdot Interface field name to SNMP::Info method conversion table
    my %IFFIELDS = ( type                => 'i_type',
		     description         => 'i_alias',		     speed               => 'i_speed',
		     admin_status        => 'i_up_admin',	     oper_status         => 'i_up', 
		     physaddr            => 'i_mac', 		     oper_duplex         => 'i_duplex',
		     admin_duplex        => 'i_duplex_admin',	     stp_id              => 'i_stp_id',
		     dp_remote_id        => 'c_id',		     dp_remote_ip        => 'c_ip',
		     dp_remote_port      => 'c_port',		     dp_remote_type      => 'c_platform',
		     );
    
    ##############################################
    # for each interface discovered...

    unless ( scalar keys %{ $hashes{interfaces} } ){
	$logger->debug(sub{"$args{host} did not return any interfaces"});
    }

    foreach my $iid ( keys %{ $hashes{interfaces} } ){
	# check whether it should be ignored
	my $name = $hashes{i_description}->{$iid};
	if ( $name ){
	    if ( my $ifreserved = $self->config->get('IFRESERVED') ){
		if ( $name =~ /$ifreserved/i ){
		    $logger->debug(sub{"Device::get_snmp_info: $args{host}: Interface $name ignored per config option (IFRESERVED)"});
		    delete $dev{interface}{$iid}; # Could have been added above
		    next;
		}
	    }
	    $dev{interface}{$iid}{name} = $name;
	}else{
	    $dev{interface}{$iid}{name} = $iid;
	}
	$dev{interface}{$iid}{number} = $iid;

	foreach my $field ( keys %IFFIELDS ){
	    my $method = $IFFIELDS{$field};
	    if ( exists $hashes{$method}->{$iid} ){
		if ( $field =~ /_enabled/ ){
		    # These are all booleans
		    $dev{interface}{$iid}{$field} = ( $hashes{$method}->{$iid} eq 'true' )? 1 : 0;
		}else{
		    $dev{interface}{$iid}{$field} = $hashes{$method}->{$iid};
		}
 	    }elsif ( $field =~ /^dp_/ ) {
 		# Make sure we erase any old discovery protocol values
 		$dev{interface}{$iid}{$field} = "";
	    }
	}
  
	################################################################
	# Vlan info
	# 
	my ($vid, $vname);
	# These are all the vlans that are enabled on this port.
	if ( my $vm = $hashes{'i_vlan_membership'}->{$iid} ){
	    foreach my $vid ( @$vm ){
		if ( exists $IGNOREDVLANS{$vid} ){
		    $logger->debug(sub{"Device::get_snmp_info: $args{host} VLAN $vid ignored per configuration option (IGNOREVLANS)"});
		    next;
		}
		$dev{interface}{$iid}{vlans}{$vid}{vid} = $vid;
	    }
	}
	foreach my $vid ( keys %{$dev{interface}{$iid}{vlans}} ){
	    # Get VLAN names
	    $vname = $hashes{'qb_v_name'}->{$vid}; # Standard MIB
	    unless ( $vname ){
		# We didn't get a vlan name in the standard place
		# Try Cisco location
		# SNMP::Info should be doing this for me :-(
		if ( $sinfo->cisco_comm_indexing ){
		    my $hvname = $hashes{'v_name'};
		    foreach my $key ( keys %$hvname ){
			if ( $key =~ /^(\d+\.$vid)$/ ){
			    $vname = $hvname->{$key};
			    last;
			}
		    }
		}
	    }
	    $dev{interface}{$iid}{vlans}{$vid}{vname} = $vname if defined ($vname);

	    if ( $dev{stp_type} ){
		if ( $dev{stp_type} eq 'mst' ){
		    # Get STP instance where this VLAN belongs
		    # If there is no mapping, make it instance 0
		    $dev{interface}{$iid}{vlans}{$vid}{stp_instance} = $dev{stp_vlan2inst}->{$vid} || 0;
		}elsif ( $dev{stp_type} =~ /pvst/i ){
		    # In PVST, we number the instances the same as VLANs
		    $dev{interface}{$iid}{vlans}{$vid}{stp_instance} = $vid;
		}elsif ( $dev{stp_type} eq 'ieee8021d' ){
		    $dev{interface}{$iid}{vlans}{$vid}{stp_instance} = 0;
		}
	    }
	}
    }
    
    ##############################################
    # Deal with BGP Peers
    # only proceed if we were told to discover peers, either directly or in the config file
    if ( $args{bgp_peers} || $self->config->get('ADD_BGP_PEERS')) {

	if ( scalar keys %{$hashes{'bgp_peers'}} ){
	    $logger->debug(sub{"Device::get_snmp_info: Checking for BGPPeers"});
	    
	    ##############################################
	    # for each BGP Peer discovered...
	    foreach my $peer ( keys %{$hashes{'bgp_peers'}} ) {
		$dev{bgppeer}{$peer}{address} = $peer;
		unless ( $dev{bgppeer}{$peer}{bgppeerid} = $hashes{'bgp_peer_id'}->{$peer} ){
		    $logger->warn("Could not determine BGP peer id of peer $peer");
		}
		my $asn = $hashes{'bgp_peer_as'}->{$peer};
		if ( ! $asn ){
		    $logger->warn("Could not determine AS number of peer $peer");
		}else{
		    $dev{bgppeer}{$peer}{asnumber} = $asn;
		    $dev{bgppeer}{$peer}{asname}   = "AS $asn";
		    $dev{bgppeer}{$peer}{orgname}  = "AS $asn";
		    
		    if ( Netdot->config->get('DO_WHOISQ') ){
			# We enabled whois queries in config
			if ( my $as_info = $self->_get_as_info($asn) ){
			    $dev{bgppeer}{$peer}{asname}  = $as_info->{asname};
			    $dev{bgppeer}{$peer}{orgname} = $as_info->{orgname};
			}
		    }
		}
	    }
	}
    }else{
	$logger->debug(sub{"Device::get_snmp_info: BGP Peer discovery not enabled"});
    }

    # Remove whitespace at beginning and end
    while ( my ($key, $val) = each %dev){
	next unless defined $val;
	$val =~ s/^\s+//;
	$val =~ s/\s+$//;
	$dev{$key} = $val;
    }

    $logger->debug(sub{"Device::get_snmp_info: Finished getting SNMP info from $args{host}"});
    return \%dev;
}


#########################################################################
=head2 snmp_update_all - Update SNMP info for every device in DB
    
  Arguments:
    communities   Arrayref of SNMP communities
    version       SNMP version
    timeout       SNMP timeout
    retries       SNMP retries
    do_info       Update Device Info
    do_fwt        Update Forwarding Tables
    do_arp        Update ARP caches
    add_subnets   Flag. When discovering routers, add subnets to database if they do not exist
    subs_inherit  Flag. When adding subnets, have them inherit information from the Device
    bgp_peers     Flag. When discovering routers, update bgp_peers
    pretend       Flag. Do not commit changes to the database
  Returns:
    True if successful
    
  Examples:
    Device->snmp_update_all();

=cut
sub snmp_update_all {
    my ($class, %argv) = @_;
    $class->isa_class_method('snmp_update_all');
    my $start = time;

    my @devs   = $class->retrieve_all();
    my $device_count = $class->snmp_update_parallel(devs=>\@devs, %argv);
    my $end = time;
    $logger->info(sprintf("All Devices updated. %d devices in %s", 
			  $device_count, $class->sec2dhms($end-$start) ));
    
}

####################################################################################
=head2 snmp_update_block - Discover and/or update all devices in given IP blocks
    
  Arguments:
    Hash with the following keys:
    blocks        Arrayref of IP block addresses in CIDR or dotted mask notation
    communities   Arrayref of SNMP communities
    version       SNMP version
    timeout       SNMP timeout
    retries       SNMP retries
    do_info       Update Device Info
    do_fwt        Update Forwarding Tables
    do_arp        Update ARP caches
    add_subnets   Flag. When discovering routers, add subnets to database if they do not exist
    subs_inherit  Flag. When adding subnets, have them inherit information from the Device
    bgp_peers     Flag. When discovering routers, update bgp_peers
    pretend       Flag. Do not commit changes to the database

  Returns:
    True if successful
    
  Examples:
    Device->snmp_update_block(blocks=>"192.168.0.0/24");

=cut
sub snmp_update_block {
    my ($class, %argv) = @_;
    $class->isa_class_method('snmp_update_block');

    my $blocks;
    $class->throw_fatal("Model::Device::snmp_update_block: Missing or invalid required argument: blocks")
	unless ( defined($blocks = $argv{blocks}) && ref($blocks) eq 'ARRAY' );
    delete $argv{blocks};
    
    # Just for logging
    my $blist = join ', ', @$blocks;

    my %h;
    foreach my $block ( @$blocks ){
	# Get a list of host addresses for the given block
	my $hosts = Ipblock->get_host_addrs($block);
	foreach my $host ( @$hosts ){
	    $h{$host} = "";
	}
    }
    $logger->debug(sub{"SNMP-discovering all devices in $blist"});
    my $start = time;

    # Call the more generic method
    $argv{hosts} = \%h;
    my $device_count = $class->snmp_update_parallel(%argv);

    my $end = time;
    $logger->info(sprintf("Devices in $blist updated. %d devices in %s", 
			  $device_count, $class->sec2dhms($end-$start) ));

}

####################################################################################
=head2 snmp_update_from_file - Discover and/or update all devices in a given file
    
  Arguments:
    Hash with the following keys:
    file          Path to file with list of hosts (IPs or hostnames) one per line
    communities   Arrayref of SNMP communities
    version       SNMP version
    timeout       SNMP timeout
    retries       SNMP retries
    add_subnets   Flag. When discovering routers, add subnets to database if they do not exist
    subs_inherit  Flag. When adding subnets, have them inherit information from the Device
    bgp_peers     Flag. When discovering routers, update bgp_peers
    pretend       Flag. Do not commit changes to the database

  Returns:
    True if successful
    
  Examples:
    Device->snmp_update_from_file("/path/to/file");

=cut
sub snmp_update_from_file {
    my ($class, %argv) = @_;
    $class->isa_class_method('snmp_update_from_file');

    my $file;
    $class->throw_fatal("Model::Device::snmp_update_from_file:Missing required argument: file")
	unless defined( $file = $argv{file} );
    delete $argv{file};

    # Get a list of hosts from given file
    my $hosts = $class->_get_hosts_from_file($file);

    $logger->debug(sub{"SNMP-discovering all devices in $file"});
    my $start = time;
    
    # Call the more generic method
    $argv{hosts} = $hosts;
    my $device_count = $class->snmp_update_parallel(%argv);

    my $end = time;
    $logger->info(sprintf("Devices in %s updated. %d devices in %s", 
			  $file, $device_count, $class->sec2dhms($end-$start)));
		  
}


#########################################################################
=head2 discover - Insert or update a device after getting its SNMP info.

    Adjusts a number of settings when inserting, based on certain
    info obtained via SNMP.    
    
  Arguments:
    Hash containing the following keys:
    name          Host name or ip address (required)
    main_ip       Main IP address (optional)
    session       SNMP Session (optional)
    communities   Arrayref of SNMP communities
    version       SNMP version
    timeout       SNMP timeout
    retries       SNMP retries
    sec_name      SNMP Security Name
    sec_level     SNMP Security Level
    auth_proto    SNMP Authentication Protocol
    auth_pass     SNMP Auth Key
    priv_proto    SNMP Privacy Protocol
    priv_pass     SNMP Privacy Key
    do_info       Update device info
    do_fwt        Update forwarding tables
    do_arp        Update ARP cache
    add_subnets   Flag. When discovering routers, add subnets to database if they do not exist
    subs_inherit  Flag. When adding subnets, have them inherit information from the Device
    bgp_peers     Flag. When discovering routers, update bgp_peers
    pretend       Flag. Do not commit changes to the database
    info          Hashref with SNMP info (optional)
    timestamp     Time Stamp (optional)
  Returns:
    New or existing Device object
  Examples:
    Device->discover(name=>$hostname, communities=>["public"]);
    Device->discover(name=>$hostname, info=>$info);

=cut
sub discover {
    my ($class, %argv) = @_;
    
    $class->isa_class_method('discover');

    my $name = $argv{name} || 
	$class->throw_fatal("Model::Device::discover: Missing required arguments: name");

    my $info  = $argv{info}    || 0;
    my $sinfo = $argv{session} || 0;
    my $dev;
    my $ip;

    if ( $dev = Device->search(name=>$name)->first ){
        $logger->debug(sub{"Device::discover: Device $name already exists in DB"});

    }else{
	# Device not found by that name
	# We need to check and make sure there isn't a device in 
	# the database with the same phyiscal address and/or serial number 

	unless ( $info ){
	    unless ( $sinfo ){
		$sinfo = $class->_get_snmp_session(host        => $name,
						   communities => $argv{communities},
						   version     => $argv{version},
						   timeout     => $argv{timeout},
						   retries     => $argv{retries},
						   sec_name    => $argv{sec_name},
						   sec_level   => $argv{sec_level},
						   auth_proto  => $argv{auth_proto},
						   auth_pass   => $argv{auth_pass},
						   priv_proto  => $argv{priv_proto},
						   priv_pass   => $argv{priv_pass},
		    );
	    }
	    $info = $class->_exec_timeout($name, 
					  sub{ return $class->get_snmp_info(session   => $sinfo,
									    bgp_peers => $argv{bgp_peers},
						   ) });
	}
    }
    
    my $device_is_new = 0;
	
    unless ( $dev ){ #still no dev! guess we better make it!
    	$logger->debug(sub{"Device::discover: Device $name does not yet exist"});
	# Set some values in the new Device based on the SNMP info obtained
	my $main_ip = $argv{main_ip} || $class->_get_main_ip($info);
	my $host    = $main_ip || $name;
	my $newname = $class->assign_name(host=>$host, sysname=>$info->{sysname});

	my %devtmp = (snmp_managed  => 1,
		      snmp_polling  => 1,
		      canautoupdate => 1,
		      # These following two could have changed in get_snmp_session
		      # so we grab them from %info instead of directly from %argv
		      community     => $info->{community},
		      snmp_version  => $info->{snmp_version},
		      );

	if ( defined $devtmp{snmp_version} && $devtmp{snmp_version} == 3 ){
	    my %arg2field = (sec_name   => 'snmp_securityname',
			     sec_level  => 'snmp_securitylevel',
			     auth_proto => 'snmp_authprotocol',
			     auth_pass  => 'snmp_authkey',
			     priv_proto => 'snmp_privprotocol',
			     priv_pass  => 'snmp_privkey',
		);

	    foreach my $arg ( keys %arg2field ){
		$devtmp{$arg2field{$arg}} = $argv{$arg} if defined $argv{$arg};
	    }
	}

	################################################################
	# Try to guess product type based on name
	if ( my $NAME2TYPE = $class->config->get('DEV_NAME2TYPE') ){
	    foreach my $str ( keys %$NAME2TYPE ){
		if ( $newname->get_label =~ /$str/ ){
		    $info->{type} = $NAME2TYPE->{$str};
		    last;
		}
	    }
	}
	# If not, assign type based on layers
	if ( !$info->{type} && $info->{layers} ){
	    $info->{type}  = "Hub"     if ( $class->_layer_active($info->{layers}, 1) );
	    $info->{type}  = "Switch"  if ( $class->_layer_active($info->{layers}, 2) );
	    $info->{type}  = "Router"  if ( $class->_layer_active($info->{layers}, 3) && $info->{ipforwarding} );
	    $info->{type}  = "Server"  if ( $class->_layer_active($info->{layers}, 7) );
	    $info->{type}  = "Unknown" unless defined $info->{type};
	}
	$logger->debug(sub{sprintf("%s type is: %s", $newname->get_label, $info->{type})});

	if ( $info->{layers} ){
	    # We collect rptrAddrTrackNewLastSrcAddress from hubs
	    if ( $class->_layer_active($info->{layers}, 1) ){
		$devtmp{collect_fwt} = 1;
	    }
	    if ( $class->_layer_active($info->{layers}, 2) ){
		$devtmp{collect_fwt} = 1;
		$devtmp{collect_stp} = 1;
	    }
	    if ( $class->_layer_active($info->{layers}, 3) 
		 && $info->{ipforwarding} ){
		$devtmp{collect_arp} = 1;
	    }
	}
	# Catch any other Device fields passed to us
	# This will override the previous default values
	foreach my $field ( $class->meta_data->get_column_names ){
	    if ( defined $argv{$field} ){
		$devtmp{$field} = $argv{$field};
	    }
	}

	# Add contacts argument if passed
	$devtmp{contacts} = $argv{contacts} if defined $argv{contacts};

	# Try to assign a Site based on syslocation
	if ( !$devtmp{site} && (my $loc = $info->{syslocation}) ){
	    if ( my $site = Site->search_like(name=>"%$loc%")->first ){
		$devtmp{site} = $site;
	    }
	}
	# Insert the new Device
	$devtmp{name} = $newname;
	$dev = $class->insert(\%devtmp);
	$logger->info(sprintf("Inserted new Device: %s", $dev->get_label));
	$device_is_new = 1;
    }
    
    # Get relevant snmp_update args
    my %uargs;
    foreach my $field ( qw(communities version timeout retries sec_name sec_level auth_proto auth_pass priv_proto priv_pass
                           add_subnets subs_inherit bgp_peers pretend do_info do_fwt do_arp timestamp) ){
	$uargs{$field} = $argv{$field} if defined ($argv{$field});
    }
    $uargs{session}       = $sinfo if $sinfo;
    $uargs{info}          = $info;
    $uargs{device_is_new} = $device_is_new;

    # Update Device with SNMP info obtained
    $dev->snmp_update(%uargs);
    
    return $dev;
}

#########################################################################
=head2 get_all_from_block - Retrieve devices with addresses within an IP block

  Arguments:
    block - IP block in CIDR notation
  Returns:
    Array ref of Device objects
  Examples:
    my $devs = Device->get_all_from_block('192.168.1.0/24');

=cut
sub get_all_from_block {
    my ($class, $block) = @_;
    $class->isa_class_method('get_all_from_block');

    defined $block || 
	$class->throw_fatal("Model::Device::get_all_from_block: Missing required arguments: block");

    my $devs;
    if ( my $ipb = Ipblock->search(address=>$block)->first ){
	$devs = $ipb->get_devices();
    }else{
	# Get a list of host addresses for the given block
	# This is highly inefficient
	my $hosts = Ipblock->get_host_addrs($block);
	my %devs; #index by id to avoid duplicates
	foreach my $ip ( @$hosts ){
	    if ( my $ipb = Ipblock->search(address=>$ip)->first ){
		if ( $ipb->interface && $ipb->interface->device ){
		    my $dev = $ipb->interface->device;
		    $devs->{$dev->id} = $dev; 
		}
	    }
	}
	$devs = \values %{$devs};
    }
    return $devs;
}

#################################################################
=head2 get_macs_from_all
    
    Retrieve all MAC addresses that belong to Devices

  Arguments: 
    None
  Returns:   
    Hashref with key=address, value=device
  Examples:
   my $devmacs = Device->get_macs_from_all();

=cut
sub get_macs_from_all {
    my ($class) = @_;
    $class->isa_class_method('get_macs_from_all');

    # Build the SQL query
    $logger->debug(sub{ "Device::get_macs_from_all: Retrieving all Device MACs..." });

    my $dbh = $class->db_Main;
    my $aref1 = $dbh->selectall_arrayref("SELECT p.address, d.id
                                          FROM physaddr p, device d
                                          WHERE d.physaddr=p.id
                                         ");
    my $aref2 = $dbh->selectall_arrayref("SELECT p.address, d.id
                                          FROM physaddr p, device d, interface i
                                          WHERE i.device=d.id AND i.physaddr=p.id
                                         ");
    # Build a hash of mac addresses to device ids
    my %dev_macs;
    foreach my $row ( @$aref1 ){
	my ($address, $id) = @$row;
	$dev_macs{$address} = $id;
    }
    foreach my $row ( @$aref2 ){
	my ($address, $id) = @$row;
	$dev_macs{$address} = $id;
    }
    return \%dev_macs;
    
}
#################################################################
=head2 get_within_downtime
    
    Get the devices within downtime.

  Arguments:
    None
  Returns:   
    Array of Device objects
  Examples:  
    my @devices = Device->get_within_downtime();

=cut
sub get_within_downtime {
    my ($class) = @_;
    $class->isa_class_method('get_within_downtime');

    my $now = $class->time2sqldate(time);
    my @devices = Device->retrieve_from_sql(qq{
        down_from <= '$now'
        AND down_until >= '$now'
    });
    return @devices;
}

#################################################################
=head2 get_ips_from_all
    
    Retrieve all IP addresses that belong to Devices

  Arguments: 
    None
  Returns:   
    Hashref with key=address (Decimal), value=device
  Examples:
   my $devips = Device->get_ips_from_all();

=cut
sub get_ips_from_all {
    my ($class) = @_;
    $class->isa_class_method('get_ips_from_all');

    # Build the SQL query
    $logger->debug(sub{ "Device::get_ips_from_all: Retrieving all Device IPs..." });

    my $dbh = $class->db_Main;
    my $aref = $dbh->selectall_arrayref("SELECT ip.address, d.id
                                         FROM   ipblock ip, device d, interface i
                                         WHERE  i.device=d.id AND ip.interface=i.id
                                         ");
    # Build a hash of mac addresses to device ids
    my %dev_ips;
    foreach my $row ( @$aref ){
	my ($address, $id) = @$row;
	$dev_ips{$address} = $id;
    }
    return \%dev_ips;
    
}


##################################################################

=head1 INSTANCE METHODS

=cut

############################################################################
############################################################################
########################## INSTANCE METHODS ################################
############################################################################
############################################################################


############################################################################
=head2 add_contact_lists - Add Contact Lists to Device
    
  Arguments:
    Array reference of ContactList objects or single ContactList object.
    If called with no arguments, it assigns the default contact list.
  Returns:
    Array of DeviceContacts objects
  Examples:

    $self->add_contact_lists(\@cl);
    
=cut
sub add_contact_lists{
    my ($self, $argv) = @_;
    $self->isa_object_method('add_contact_lists');

    my @cls;
    if ( ! $argv ){
	my $confcl = $self->config->get('DEFAULT_CONTACTLIST');
	if ( my $default_cl = ContactList->search(name=>$confcl)->first ){
	    push @cls, $default_cl;
	}else{
	    $logger->warn("add_contact_lists: Default Contact List not found: $confcl");
	    return;
	}
    }else{
	if( ref($argv) eq "ARRAY" ){
	    @cls = @{ $argv };
	}else{
	    push @cls, $argv;
	}
    }
    my @ret;
    foreach my $cl ( @cls ){
	my $n = DeviceContacts->insert({ device => $self, contactlist => $cl });
	push @ret, $n;
    }
    return @ret;
}

############################################################################
=head2 has_layer - Determine if Device performs a given OSI layer function
    

  Arguments:
    Layer number
  Returns:
    True/False

  Examples:
    $device->has_layer(2);

=cut
sub has_layer {
    my ($self, $layer) = @_;
    $self->isa_object_method('has_layer');

    my $layers = $self->layers();
    return undef unless defined($layers);
    return undef unless length($layers);
    return substr($layers,8-$layer, 1);
}

############################################################################
=head2 list_layers - Return a list of active OSI layers
    
  Arguments:
    None
  Returns:
    Array of scalars
  Examples:
    $device->list_layers();

=cut
sub list_layers {
    my ($self) = @_;
    $self->isa_object_method('list_layers');
    my @layers;
    for ( my($i)=1; $i<=8; $i++ ){
	push @layers, $i if ( $self->has_layer($i) );
    }
    return @layers;
}

#########################################################################
=head2 arp_update - Update ARP cache in DB
    
  Arguments:
    Hash with the following keys:
    session        - SNMP Session
    cache          - hash reference with arp cache info (optional)
    timestamp      - Time Stamp (optional)
    no_update_tree - Do not update IP tree
    atomic         - Flag. Perform atomic updates.
  Returns:
    True if successful
    
  Examples:
    $self->arp_update();

=cut
sub arp_update {
    my ($self, %argv) = @_;
    $self->isa_object_method('arp_update');
    my $class = ref($self);

    my $host      = $self->fqdn;
    my $dbh       = $self->db_Main;
    my $timestamp = $argv{timestamp} || $self->timestamp;

    unless ( $self->collect_arp ){
	$logger->debug(sub{"Device::arp_update: $host excluded from ARP collection. Skipping"});
	return;
    }
    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::arp_update: $host in downtime. Skipping"});
	return;
    }

    # Fetch from SNMP if necessary
    my $cache = $argv{cache} || $class->_exec_timeout($host, sub{ return $self->get_arp(session=>$argv{session}) });
    
    unless ( keys %$cache ){
	$logger->debug("$host: ARP cache empty");
	return;	
    }
    
    # Measure only db update time
    my $start = time;
    $logger->debug(sub{"$host: Updating ARP cache"});
  
    # Create ArpCache object
    
    my $ac;
    eval {
	$ac = ArpCache->insert({device=>$self->id, tstamp=>$timestamp});
    };
    if ( my $e = $@ ){
	$logger->warn(sprintf("Device %s: Could not insert ArpCache at %s: %s", $self->fqdn, $timestamp, $e));
	return;
    }
	
    $self->_update_macs_from_arp_cache(caches    => [$cache], 
				       timestamp => $timestamp, 
				       atomic    => $argv{atomic},
	);

    $self->_update_ips_from_arp_cache(caches         => [$cache], 
				      timestamp      => $timestamp, 
				      no_update_tree => $argv{no_update_tree},
				      atomic         => $argv{atomic},
	);

    my ($arp_count, @ce_updates);

    foreach my $version ( keys %$cache ){
	foreach my $intid ( keys %{$cache->{$version}} ){
	    foreach my $ip ( keys %{$cache->{$version}{$intid}} ){
		my $mac = $cache->{$version}{$intid}{$ip};
		$arp_count++;
		push @ce_updates, {
		    arpcache  => $ac->id,
		    interface => $intid,
		    ipaddr    => Ipblock->ip2int($ip),
		    physaddr  => $mac,
		};
	    }
	}
    }
    if ( $argv{atomic} ){
	Netdot::Model->do_transaction( sub{ return ArpCacheEntry->fast_insert(list=>\@ce_updates) } );
    }else{
	ArpCacheEntry->fast_insert(list=>\@ce_updates);
    }

    # Set the last_arp timestamp
    $self->update({last_arp=>$timestamp});

    my $end = time;
    $logger->debug(sub{ sprintf("$host: ARP cache updated. %s entries in %s", 
				$arp_count, $self->sec2dhms($end-$start) )});

    return 1;
}

############################################################################
=head2 get_arp - Fetch ARP and IPv6 ND tables

  Arguments:
    session - SNMP session (optional)
  Returns:
    Hashref of hashrefs containing:
      ip version -> interface id -> mac address = ip address
  Examples:
    my $cache = $self->get_arp(%args)
=cut
sub get_arp {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_arp');
    my $host = $self->fqdn;

    unless ( $self->collect_arp ){
	$logger->debug(sub{"Device::get_arp: $host excluded from ARP collection. Skipping"});
	return;
    }
    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::get_arp: $host in downtime. Skipping"});
	return;
    }

    # This will hold both ARP and v6 ND caches
    my %cache;

    ### v4 ARP
    my $start = time;
    my $arp_count = 0;
    my $arp_cache = $self->_get_arp_from_snmp(session=>$argv{session});
    foreach ( keys %$arp_cache ){
	$cache{'4'}{$_} = $arp_cache->{$_};
	$arp_count+= scalar(keys %{$arp_cache->{$_}})
    }
    my $end = time;
    $logger->info(sub{ sprintf("$host: ARP cache fetched. %s entries in %s", 
				$arp_count, $self->sec2dhms($end-$start) ) });

    ### v6 ND
    $start = time;
    my $nd_count = 0;
    my $nd_cache  = $self->_get_v6_nd_from_snmp(session=>$argv{session});
    # Here we have to go one level deeper in order to
    # avoid losing the previous entries
    foreach ( keys %$nd_cache ){
	foreach my $ip ( keys %{$nd_cache->{$_}} ){
	    $cache{'6'}{$_}{$ip} = $nd_cache->{$_}->{$ip};
	    $nd_count++;
	}
    }
    $end = time;
    $logger->info(sub{ sprintf("$host: IPv6 ND cache fetched. %s entries in %s", 
				$nd_count, $self->sec2dhms($end-$start) ) });

    return \%cache;
}



#########################################################################
=head2 fwt_update - Update Forwarding Table in DB
    
  Arguments:
    Hash with the following keys:
    session        - SNMP Session (optional)
    fwt            - hash reference with FWT info (optional)
    timestamp      - Time Stamp (optional)
    atomic         - Flag.  Perform atomic updates.
  Returns:
    True if successful
    
  Examples:
    $self->fwt_update();

=cut
sub fwt_update {
    my ($self, %argv) = @_;
    $self->isa_object_method('fwt_update');
    my $class = ref($self);

    my $host      = $self->fqdn;
    my $dbh       = $self->db_Main;
    my $timestamp = $argv{timestamp} || $self->timestamp;
    
    unless ( $self->collect_fwt ){
	$logger->debug(sub{"Device::fwt_update: $host excluded from FWT collection. Skipping"});
	return;
    }
    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::fwt_update: $host in downtime. Skipping"});
	return;
    }

    # Fetch from SNMP if necessary
    my $fwt = $argv{fwt} || $class->_exec_timeout($host, sub{ return $self->get_fwt(session=>$argv{session}) } );

    unless ( keys %$fwt ){
	$logger->debug("$host: FWT empty");
	return;	
    }
    
    # Measure only db update time
    my $start = time;

    $logger->debug(sub{"$host: Updating Forwarding Table (FWT)"});
    
    # Create FWTable object
    my $fw;
    eval {
	$fw = FWTable->insert({device  => $self->id,
			       tstamp  => $timestamp});
    };
    if ( my $e = $@ ){
	$logger->warn(sprintf("Device %s: Could not insert FWTable at %s: %s", $self->fqdn, $timestamp, $e));
	return;
    }
    $self->_update_macs_from_fwt(caches    => [$fwt], 
				 timestamp => $timestamp,
				 atomic    => $argv{atomic},
	);
    
    my @fw_updates;
    foreach my $intid ( keys %{$fwt} ){
	foreach my $mac ( keys %{$fwt->{$intid}} ){
	    push @fw_updates, {
		fwtable   => $fw->id,
		interface => $intid,
		physaddr  => $mac,
	    };
	}
    }

    if ( $argv{atomic} ){
	Netdot::Model->do_transaction( sub{ return FWTableEntry->fast_insert(list=>\@fw_updates) } );
    }else{
	FWTableEntry->fast_insert(list=>\@fw_updates);
    }
    
    ##############################################################
    # Set the last_fwt timestamp
    $self->update({last_fwt=>$timestamp});

    my $end = time;
    $logger->debug(sub{ sprintf("$host: FWT updated. %s entries in %s", 
				scalar @fw_updates, $self->sec2dhms($end-$start) )});
    
    return 1;
}


############################################################################
=head2 get_fwt - Fetch forwarding tables

  Arguments:
    session - SNMP session (optional)
  Returns:
    Hashref
  Examples:
    my $fwt = $self->get_fwt(%args)
=cut
sub get_fwt {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_fwt');
    my $class = ref($self);
    my $host = $self->fqdn;
    my $fwt = {};

    unless ( $self->collect_fwt ){
	$logger->debug(sub{"Device::get_fwt: $host excluded from FWT collection. Skipping"});
	return;
    }
    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::get_fwt: $host in downtime. Skipping"});
	return;
    }

    my $start     = time;
    my $fwt_count = 0;
    $fwt = $self->_get_fwt_from_snmp(session=>$argv{session});
    map { $fwt_count+= scalar(keys %{$fwt->{$_}}) } keys %$fwt;
    my $end = time;
    $logger->info(sub{ sprintf("$host: FWT fetched. %s entries in %s", 
			       $fwt_count, $self->sec2dhms($end-$start) ) });
   return $fwt;
}


############################################################################
=head2 delete - Delete Device object
    
    We override the insert method for extra functionality:
     - Remove orphaned Resource Records if necessary
     - Remove orphaned Asset records if necessary

  Arguments:
    None
  Returns:
    True if successful

  Examples:
    $device->delete();

=cut
sub delete {
    my ($self) = @_;
    $self->isa_object_method('delete');
    
    my $asset = $self->asset_id;
    
    # We don't want to delete dynamic addresses
    if ( my $ips = $self->get_ips ){
	foreach my $ip ( @$ips ) {
	    if ( $ip->status && $ip->status->name eq 'Dynamic' ){
		$ip->update({interface=>undef});
	    }
	}
    }
    
    # If the RR had a RRADDR, it was probably deleted.  
    # Otherwise, we do it here.
    my $rrid = ( $self->name )? $self->name->id : "";
    
    $self->SUPER::delete();
    
    if ( my $rr = RR->retrieve($rrid) ){
	$rr->delete() unless $rr->arecords;
    }
    
    if ( $asset && !($asset->devices || $asset->device_modules) ){
	$asset->delete();
    }
    
    return 1;
}

############################################################################
=head2 short_name - Get/Set name of Device
   
    The device name is actually a pointer to the Resorce Record (RR) table

  Arguments:
    name string (optional)
  Returns:
    Short name of Device (Resource Record Name)
  Examples:
    $device->short_name('switch1');

=cut
sub short_name {
    my ($self, $name) = @_;
    $self->isa_object_method('short_name');
    
    my $rr;
    $self->throw_fatal("Model::Device::short_name: Device id ". $self->id ." has no RR defined") 
	unless ( $rr = $self->name );
    if ( $name ){
	$rr->name($name);
	$rr->update;
    }
    return $rr->name;
}

############################################################################
=head2 product_type - Get Device type
   
  Arguments:
    None
  Returns:
    ProductType object name
  Examples:
    $device->product_type();

=cut
sub product_type {
    my ($self) = @_;
    $self->isa_object_method('product_type');
    if (($self->product) && ($self->product->type)){	 
	return $self->product->type->name;
    }
}

############################################################################
=head2 fqdn - Get Fully Qualified Domain Name
   
  Arguments:
    None
  Returns:
    FQDN string
  Examples:
   print $device->fqdn(), "\n";

=cut

sub fqdn {
    my $self = shift;
    $self->isa_object_method('fqdn');
    return $self->name->get_label;
}

############################################################################
=head2 get_label - Overrides label method
   
  Arguments:
    None
  Returns:
    FQDN string
  Examples:
   print $device->get_label(), "\n";

=cut

sub get_label {
    my $self = shift;
    $self->isa_object_method('get_label');
    return $self->fqdn;
}

############################################################################
=head2 is_in_downtime - Is this device within downtime period?

  Arguments:
    None
  Returns:
    True or false
  Examples:
    if ( $device->is_in_downtime ) ...

=cut
sub is_in_downtime {
    my ($self) = @_;

    if ( $self->down_from && $self->down_until && 
	 $self->down_from ne '0000-00-00' && $self->down_until ne '0000-00-00' ){
	my $time1 = $self->sqldate2time($self->down_from);
	my $time2 = $self->sqldate2time($self->down_until);
	my $now = time;
	if ( $time1 < $now && $now < $time2 ){
	    return 1;
	}
    }
    return 0;
}

############################################################################
=head2 update - Update Device in Database
    
    We override the update method for extra functionality:
      - Update 'last_updated' field with current timestamp
      - snmp_managed flag turns off all other snmp access flags
      - Update asset product if necessary

  Arguments:
    Hash ref with Device fields
  Returns:
    See Class::DBI update()
  Example:
    $device->update( \%data );

=cut

sub update {
    my ($self, $argv) = @_;
    
    # Update the timestamp
    $argv->{last_updated} = $self->timestamp;

    if ( exists $argv->{snmp_managed} && !($argv->{snmp_managed}) ){
	# Means it's being set to 0 or undef
	# Turn off other flags
	$argv->{canautoupdate} = 0;
	$argv->{snmp_polling}  = 0;
	$argv->{collect_arp}   = 0;
	$argv->{collect_fwt}   = 0;
    }
    $self->_validate_args($argv);

    if ( $argv->{product} && $self->asset_id ){
	$self->asset_id->update({product_id=>$argv->{product}});
    }

    return $self->SUPER::update($argv);
}

############################################################################
=head2 update_bgp_peering - Update/Insert BGP Peering information using SNMP info

    
  Arguments:
    Hash with the following keys
    peer - Hashref containing Peer SNMP info:
      address
      asname
      asnumber
      orgname
      bgppeerid
    oldpeerings - Hash ref containing old peering objects
  Returns:
    BGPPeering object or undef if error
  Example:
    foreach my $peer ( keys %{$info->{bgppeer}} ){
	$self->update_bgp_peering(peer        => $info->{bgppeer}->{$peer},
				  oldpeerings => \%oldpeerings);
    }

=cut

sub update_bgp_peering {
    my ($self, %argv) = @_;
    my ($peer, $oldpeerings) = @argv{"peer", "oldpeerings"};
    $self->isa_object_method('update_bgp_peering');

    $self->throw_fatal("Model::Device::update_bgp_peering: Missing required arguments: peer, oldpeerings")
	unless ( $peer && $oldpeerings );
    my $host = $self->fqdn;

    my $p; # bgppeering object

    # Check if we have basic Entity info
    my $entity;
    if ( exists ($peer->{asname}) || 
	 exists ($peer->{orgname})|| 
	 exists ($peer->{asnumber}) ){
	
	my $entityname = $peer->{orgname} || $peer->{asname};
	$entityname .= " ($peer->{asnumber})";
	
	# Check if Entity exists
	#
	if ( $entity = Entity->search(asnumber => $peer->{asnumber})->first ||
	     Entity->search(asname => $peer->{asname})->first               ||
	     Entity->search(name   => $peer->{orgname})->first
	     ){
	    # Update AS stuff
	    $entity->update({asname   => $peer->{asname},
			     asnumber => $peer->{asnumber}});
	}else{
	    # Doesn't exist. Create Entity
	    #
	    # Build Entity info
	    #
	    my %etmp = ( name     => $entityname,
			 asname   => $peer->{asname},
			 asnumber => $peer->{asnumber},
		);
	
	    $logger->info(sprintf("%s: Peer Entity %s not found. Inserting", 
				  $host, $entityname ));
	    
	    $entity = Entity->insert( \%etmp );
	    $logger->info(sprintf("%s: Created Peer Entity %s.", $host, $entityname));
	}
	
	# Make sure Entity has role "peer"
	if ( my $type = (EntityType->search(name => "Peer"))[0] ){
	    my %eroletmp = ( entity => $entity, type => $type );
	    my $erole;
	    if ( $erole = EntityRole->search(%eroletmp)->first ){
		$logger->debug(sub{ sprintf("%s: Entity %s already has 'Peer' role", 
					    $host, $entityname )});
	    }else{
		EntityRole->insert(\%eroletmp);
		$logger->info(sprintf("%s: Added 'Peer' role to Entity %s", 
				      $host, $entityname ));
	    }
	}
	
    }else{
	$logger->warn( sprintf("%s: Missing peer info. Cannot associate peering %s with an entity", 
			       $host, $peer->{address}) );
    }
    $entity ||= 0;
    
    # Create a hash with the peering's info for update or insert
    my %pstate = (device      => $self,
		  entity      => $entity,
		  bgppeerid   => $peer->{bgppeerid},
		  bgppeeraddr => $peer->{address});
	
    # Check if peering exists
    foreach my $peerid ( keys %{ $oldpeerings } ){

	my $oldpeer = $oldpeerings->{$peerid};
	if ( $oldpeer->bgppeeraddr eq $peer->{address} ){
	    
	    # Peering Exists.  
	    $p = $oldpeer;
	    
	    # Delete from list of old peerings
	    delete $oldpeerings->{$peerid};
	    last;
	}
    }
    if ( $p ){
	# Update in case anything has changed
	my $r = $p->update(\%pstate);
	$logger->debug(sub{ sprintf("%s: Updated Peering with: %s. ", $host, $entity->name)}) if $r;
	
    }else{
	# Peering Doesn't exist.  Create.
	# 
	$pstate{monitored} = 1;
	$p = BGPPeering->insert(\%pstate);
	my $peer_label = $entity ? $entity->name : $peer->address;
	$logger->info(sprintf("%s: Inserted new Peering with: %s. ", $host, $peer_label));
    }
    return $p;
}


############################################################################
=head2 snmp_update - Update Devices using SNMP information


  Arguments:
    Hash with the following keys:
    do_info        Update device info (default)
    do_fwt         Update forwarding tables
    do_arp         Update ARP cache
    info           Hashref with device info (optional)
    communities    Arrayref of SNMP Community strings
    version        SNMP Version [1|2|3]
    timeout        SNMP Timeout
    retries        SNMP Retries
    session        SNMP Session
    add_subnets    Flag. When discovering routers, add subnets to database if they do not exist
    subs_inherit   Flag. When adding subnets, have them inherit information from the Device
    bgp_peers      Flag. When discovering routers, update bgp_peers
    pretend        Flag. Do not commit changes to the database
    timestamp      Time Stamp (optional)
    no_update_tree Flag. Do not update IP tree.
    atomic         Flag. Perform atomic updates.
    device_is_new  Flag. Specifies that device was just created.

  Returns:
    Updated Device object

  Example:
    my $device = $device->snmp_update(do_info=>1, do_fwt=>1);

=cut

sub snmp_update {
    my ($self, %argv) = @_;
    $self->isa_object_method('snmp_update');
    my $class = ref($self);
    unless ( $argv{do_info} || $argv{do_fwt} || $argv{do_arp} ){
	$argv{do_info} = 1;
    }
    my $atomic = defined $argv{atomic} ? $argv{atomic} : $self->config->get('ATOMIC_DEVICE_UPDATES');

    my $host = $self->fqdn;
    my $timestamp = $argv{timestamp} || $self->timestamp;

    my $sinfo = $argv{session};
    unless ( $argv{info} || $sinfo ){
	$sinfo = $self->_get_snmp_session(communities => $argv{communities},
					  version     => $argv{version},
					  timeout     => $argv{timeout},
					  retries     => $argv{retries},
					  sec_name    => $argv{sec_name},
					  sec_level   => $argv{sec_level},
					  auth_proto  => $argv{auth_proto},
					  auth_pass   => $argv{auth_pass},
					  priv_proto  => $argv{priv_proto},
					  priv_pass   => $argv{priv_pass},
	    );
    }
    
    # Re-bless into appropriate sub-class if needed
    my %r_args;
    if ( $sinfo ){
	$r_args{sclass}       = $sinfo->class;
	$r_args{sysobjectid}  = $sinfo->id;
    }elsif ( $argv{info} ){
	$r_args{sclass}     ||= $argv{info}->{_sclass};
	$r_args{sysobjectid}  = $argv{info}->{sysobjectid};
    }
    $self->_netdot_rebless(%r_args);

    if ( $argv{do_info} ){
	my $info = $argv{info} || 
	    $class->_exec_timeout($host, sub{ return $self->get_snmp_info(session   => $sinfo,
									  bgp_peers => $argv{bgp_peers}) });

	if ( $atomic && !$argv{pretend} ){
	    Netdot::Model->do_transaction( sub{ return $self->info_update(add_subnets   => $argv{add_subnets},
									  subs_inherit  => $argv{subs_inherit},
									  bgp_peers     => $argv{bgp_peers},
									  session       => $sinfo,
									  info          => $info,
									  device_is_new => $argv{device_is_new},
						    ) } );
	}else{
	    $self->info_update(add_subnets   => $argv{add_subnets},
			       subs_inherit  => $argv{subs_inherit},
			       bgp_peers     => $argv{bgp_peers},
			       pretend       => $argv{pretend},
			       session       => $sinfo,
			       info          => $info,
			       device_is_new => $argv{device_is_new},
		);
	}
    }
    if ( $argv{do_fwt} ){
	if ( $self->collect_fwt ){
	    $self->fwt_update(session   => $sinfo, 
			      timestamp => $timestamp,
			      atomic    => $atomic,
		);
	}else{
	    $logger->debug(sub{"Device::snmp_update: $host excluded from FWT collection. Skipping"});
	    return;
	}
    }
    if ( $argv{do_arp} ){
	if ( $self->has_layer(3) && $self->collect_arp ){
	    $self->arp_update(session        => $sinfo, 
			      timestamp      => $timestamp,
			      no_update_tree => $argv{no_update_tree},
			      atomic         => $atomic,
		);
	}else{
	    $logger->debug(sub{"Device::snmp_update: $host excluded from ARP collection. Skipping"});
	    return;
	}
    }
    $logger->info("Device::snmp_update: $host: Finished updating");
}


############################################################################
=head2 info_update - Update Device in Database using SNMP info

    Updates an existing Device based on information gathered via SNMP.  
    This is exclusively an object method.

  Arguments:
    Hash with the following keys:
    session       SNMP session (optional)
    info          Hashref with Device SNMP information. 
                  If not passed, this method will try to get it.
    communities   Arrayref of SNMP Community strings
    version       SNMP Version [1|2|3]
    timeout       SNMP Timeout
    retries       SNMP Retries
    sec_name      SNMP Security Name
    sec_level     SNMP Security Level
    auth_proto    SNMP Authentication Protocol
    auth_pass     SNMP Auth Key
    priv_proto    SNMP Privacy Protocol
    priv_pass     SNMP Privacy Key
    add_subnets   Flag. When discovering routers, add subnets to database if they do not exist
    subs_inherit  Flag. When adding subnets, have them inherit information from the Device
    bgp_peers     Flag. When discovering routers, update bgp_peers
    pretend       Flag. Do not commit changes to the database
    device_is_new Flag. Specifies that device was just created.

  Returns:
    Updated Device object

  Example:
    my $device = $device->info_update();

=cut
sub info_update {
    my ($self, %argv) = @_;
    $self->isa_object_method('info_update');
    
    my $class = ref $self;
    my $start = time;
    my $dbh = $class->db_Main;
    my $sql = "SELECT id, dp_remote_id, dp_remote_ip, dp_remote_port, dp_remote_type FROM interface WHERE device = $self";
    my $before_stmt = $dbh->prepare($sql);
    my $after_stmt = $dbh->prepare($sql);
    #running this sql query so we can compare the interfaces on this device before the update, with the interfaces
    #after the update, so we'll know which links to update in the topography graph
    $before_stmt->execute();
    
    # Show full name in output
    my $host = $self->fqdn;

    my $info = $argv{info};
    unless ( $info ){
	# Get SNMP info
	if ( $argv{session} ){
	    $info = $class->_exec_timeout($host, 
					  sub{ return $self->get_snmp_info(bgp_peers => $argv{bgp_peers},
									   session   => $argv{session},
						   ) });
	    
	}else{
	    my $version = $argv{snmp_version} || $self->snmp_version 
		|| $self->config->get('DEFAULT_SNMPVERSION');
	    
	    my $timeout     = $argv{timeout}     || $self->config->get('DEFAULT_SNMPTIMEOUT');
	    my $retries     = $argv{retries}     || $self->config->get('DEFAULT_SNMPRETRIES');
	    my $communities = $argv{communities} || [$self->community]        || $self->config->get('DEFAULT_SNMPCOMMUNITIES');
	    my $sec_name    = $argv{sec_name}    || $self->snmp_securityname  || $self->config->get('DEFAULT_SNMP_SECNAME');
	    my $sec_level   = $argv{sec_level}   || $self->snmp_securitylevel || $self->config->get('DEFAULT_SNMP_SECLEVEL');
	    my $auth_proto  = $argv{auth_proto}  || $self->snmp_authprotocol  || $self->config->get('DEFAULT_SNMP_AUTHPROTO');
	    my $auth_pass   = $argv{auth_pass}   || $self->snmp_authkey       || $self->config->get('DEFAULT_SNMP_AUTHPASS');
	    my $priv_proto  = $argv{priv_proto}  || $self->snmp_privprotocol  || $self->config->get('DEFAULT_SNMP_PRIVPROTO');
	    my $priv_pass   = $argv{priv_pass}   || $self->snmp_privkey       || $self->config->get('DEFAULT_SNMP_PRIVPASS');
	    $info = $class->_exec_timeout($host, 
					  sub{ return $self->get_snmp_info(communities => $communities, 
									   version     => $version,
									   timeout     => $timeout,
									   retries     => $retries,
									   sec_name    => $sec_name,
									   sec_level   => $sec_level,
									   auth_proto  => $auth_proto,
									   auth_pass   => $auth_pass,
									   priv_proto  => $priv_proto,
									   priv_pass   => $priv_pass,
									   bgp_peers   => $argv{bgp_peers},
						   ) });
	}
    }
    unless ( $info ){
	$logger->error("$host: No SNMP info received");
	return;	
    }
    unless ( ref($info) eq 'HASH' ){
	$self->throw_fatal("Model::Device::info_update: Invalid SNMP data structure");
    }
    
    # Pretend works by turning off autocommit in the DB handle and rolling back
    # all changes at the end
    if ( $argv{pretend} ){
        $logger->info("$host: Performing a dry-run");
        unless ( Netdot::Model->db_auto_commit(0) == 0 ){
            $self->throw_fatal("Model::Device::info_update: Unable to set AutoCommit off");
        }
    }
    
    # Data that will be passed to the update method
    my %devtmp;

    ##############################################################
    if ( my $bm = $self->_assign_base_mac($info) ){
	$devtmp{physaddr} = $bm;
    }

    ##############################################################
    # Fill in some basic device info
    foreach my $field ( qw( community snmp_version layers ipforwarding sysname 
                            sysdescription syslocation os collect_arp collect_fwt ) ){
	$devtmp{$field} = $info->{$field} if exists $info->{$field};
    }
    
    ##############################################################
    if ( my $ipb = $self->_assign_snmp_target($info) ){
	$devtmp{snmp_target} = $ipb;
    }

    ##############################################################
    $devtmp{product} = $self->_assign_product($info);
    
    ##############################################################
    # Asset
    my $sn   = $info->{serial_number};
    my $prod = $devtmp{product};
    if ( $sn && $prod){
	$devtmp{asset_id} = Asset->find_or_create({serial_number=>$sn, product_id=>$prod});
    }elsif ( $sn ){
	$devtmp{asset_id} = Asset->find_or_create({serial_number=>$sn});	
    }else{
    	$logger->debug(sub{"$host did not return serial number" });
    }
    
    ##############################################################
    if ( $devtmp{product} && $argv{device_is_new} ){
	my $val = $self->_assign_device_monitored($devtmp{product});
	$devtmp{monitored}    = $val;
	$devtmp{snmp_polling} = $val;
    }

    ##############################################################
    if ( $argv{device_is_new} && (my $g = $self->_assign_monitor_config_group($info)) ){
	$devtmp{monitor_config}       = 1;
	$devtmp{monitor_config_group} = $g;
    }

    ##############################################################
    # Spanning Tree
    $self->_update_stp_info($info, \%devtmp);
    
    ##############################################################
    $self->_update_modules($info);

    ##############################################
    $self->_update_interfaces(info            => $info, 
			      add_subnets     => $argv{add_subnets}, 
			      subs_inherit    => $argv{subs_inherit},
			      overwrite_descr => ($info->{ipforwarding})? 1 : 0,
	);
    
    ###############################################################
    # Update BGP info
    #
    my $update_bgp = defined($argv{bgp_peers}) ? 
	$argv{bgp_peers} : $self->config->get('ADD_BGP_PEERS');
    
    if ( $update_bgp ){
	$self->_update_bgp_info($info, \%devtmp);
    }

    ##############################################################
    # Update Device object
    $self->update(\%devtmp);
    
    my $end = time;
    $logger->debug(sub{ sprintf("%s: SNMP update completed in %s", 
				$host, $self->sec2dhms($end-$start))});

    if ( $argv{pretend} ){
	$logger->debug(sub{"$host: Rolling back changes"});
	eval {
	    $self->dbi_rollback;
	};
	if ( my $e = $@ ){
	    $self->throw_fatal("Model::Device::info_update: Rollback Failed!: $e");
	}
	$logger->debug(sub{"Model::Device::info_update: Turning AutoCommit back on"});
	unless ( Netdot::Model->db_auto_commit(1) == 1 ){
	    $self->throw_fatal("Model::Device::info_update: Unable to set AutoCommit on");
	}
    }


    #now that the updates have been done, lets take the "after" shot
    $after_stmt->execute();

    my @interfaces_to_check = ();
    #lets build two hashes to store before and after information in, the key of the hash will be the interface
    #id, the value will be a concatenation of all the data
    my %before_hash;
    my %after_hash;
    while( my @row = $before_stmt->fetchrow_array() ){
	my $i;
	for ($i=1; $i<5; $i++){
	    $row[$i] ||= 0; # Avoid warnings about concatenation of uninitialized values
	}
	$before_hash{$row[0]} = $row[1].$row[2].$row[3].$row[4];
    }
    while( my @row = $after_stmt->fetchrow_array() ){
	my $i;
	for ($i=1; $i<5; $i++){
	    $row[$i] ||= 0; # Avoid warnings about concatenation of uninitialized values
	}
        $after_hash{$row[0]} = $row[1].$row[2].$row[3].$row[4];
    }

    #we will have to loop through each hash, since before_hash might have some keys that after_hash doesn't, and visa versa
    #these checking operations should be very efficient however
    foreach( keys %before_hash ){
        if ( exists $before_hash{$_} && exists $after_hash{$_} && $before_hash{$_} ne $after_hash{$_} ){
            push(@interfaces_to_check, $_);
        }
    }
    foreach( keys %after_hash ){
        if ( exists $before_hash{$_} && exists $after_hash{$_} && $before_hash{$_} ne $after_hash{$_} ){
            push(@interfaces_to_check, $_);
        }
    }
    #now we'll put our findings in a hash to pass to Topology->discover.  We want to exclude all protocols except dp
    #print "So we're going to look at @interfaces_to_check <br/>";
    my %topo_argv = ();
    if( ( scalar @interfaces_to_check) && !$argv{pretend} ){
    	$topo_argv{'interfaces'} = (\@interfaces_to_check);
    	$topo_argv{'exclude_stp'} = 1;
    	$topo_argv{'exclude_fdb'} = 1;
    	$topo_argv{'exclude_p2p'} = 1;
    	Netdot::Topology->discover(%topo_argv);
    }	
    

    return $self;
}

############################################################################
=head2 add_ip - Add an IP address (assumes only one interface)
   
  Arguments:
    IP address in dotted-quad notation
  Returns:
    Ipblock object
  Examples:
    $device->add_ip('10.0.0.1');

=cut
sub add_ip {
    my ($self, $address) = @_;
    $self->isa_object_method('add_ip');
    my $int = ($self->interfaces)[0];
    my $n = Ipblock->insert({address=>$address, interface=>$int, status=>'Static'});
    return $n;
}
############################################################################
=head2 get_ips - Get all IP addresses from a device
   
  Arguments:
    Hash with the following keys:
       sort_by  [address|interface]
  Returns:
    Arrayref of Ipblock objects
  Examples:
    print $_->address, "\n" foreach $device->get_ips( sort_by => 'address' );

=cut
sub get_ips {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_ips');
    
    $argv{sort_by} ||= "address";
    
    my @ips;
    if ( $argv{sort_by} eq "address" ){
	@ips = Ipblock->search_devipsbyaddr($self->id);
    }elsif ( $argv{sort_by} eq "interface" ){
	@ips = Ipblock->search_devipsbyint($self->id);
    }else{
	$self->throw_fatal("Model::Device::get_ips: Invalid sort criteria: $argv{sort_by}");
    }
    return \@ips;
}

############################################################################
=head2 get_neighbors - Get all Interface neighbors

  Arguments:
    None
  Returns:
    Hash ref with key = local int id, value = remote int id
  Examples:
    my $neighbors = $device->get_neighbors();
=cut
sub get_neighbors {
    my ($self, $devs) = @_;
    $self->isa_object_method('get_neighbors');

    my %res;
    foreach my $int ( $self->interfaces ){
	my $n = $int->neighbor();
	$res{$int->id} = $n if $n;
    }
    return \%res;
}

############################################################################
=head2 get_circuits - Get all Interface circuits

  Arguments:
    None
  Returns:
    Array of circuit objects
  Examples:
    my @circuits = $device->get_circuits();
=cut
sub get_circuits {
    my ($self) = @_;
    $self->isa_object_method('get_circuits');

    my @res;
    foreach my $int ( $self->interfaces ){
	my $c = $int->circuit();
	push @res, $c if ( $c );
    }
    return @res if @res;
    return;
}

############################################################################
=head2 remove_neighbors - Remove neighbors from all interfaces
   
  Arguments:
    None
  Returns:
    True
  Examples:
    $device->remove_neighbors();
=cut
sub remove_neighbors {
    my ($self) = @_;
    foreach my $int ( $self->interfaces ){
	$int->remove_neighbor();
    }
}

############################################################################
=head2 get_subnets  - Get all the subnets in which this device has any addresses
   
  Arguments:
    None
  Returns:
    hashref of Ipblock objects, keyed by id
  Examples:
    my %s = $device->get_subnets();
    print $s{$_}->address, "\n" foreach keys %s;

=cut
sub get_subnets {
    my $self = shift;
    $self->isa_object_method('get_subnets');
    
    my %subnets;
    foreach my $ip ( @{ $self->get_ips() } ){
	my $subnet;
	if ( ($subnet = $ip->parent) 
	     && $subnet->status 
	     && $subnet->status->name eq "Subnet" ){
	    $subnets{$subnet->id} = $subnet;
	}
    }
    return \%subnets;
}

############################################################################
=head2 add_interfaces - Manually add a number of interfaces to an existing device

    The new interfaces will be added with numbers starting after the highest existing 
    interface number

  Arguments:
    Number of interfaces
  Returns:
    Arrayref of new interface objects
  Examples:
    $device->add_interfaces(2);

=cut

sub add_interfaces {
    my ($self, $num) = @_;
    $self->isa_object_method('add_interfaces');

    unless ( $num > 0 ){
	$self->throw_user("Invalid number of Interfaces to add: $num");
    }
    # Determine highest numbered interface in this device
    my @ints;
    my $start;
    my $ints = $self->ints_by_number;
    if ( defined $ints && scalar @$ints ){
 	my $lastidx = @$ints - 1;
	$start = int ( $ints->[$lastidx]->number );
    }else{
	$start = 0;
    }
    my %tmp = ( device => $self->id, number => $start );
    my $i;
    my @newints;
    for ( $i = 0; $i < $num; $i++ ){
	$tmp{number}++;
	push @newints, Interface->insert( \%tmp );
    }
    return \@newints;
}

############################################################################
=head2 ints_by_number - Retrieve interfaces from a Device and sort by number.  

    The number field can actually contain alpha characters. If so, 
    sort alphanumerically, removing any non-alpha characters.  Otherwise,
    sort numerically.
    
  Arguments:  
    None
  Returns:    
    Sorted arrayref of interface objects
  Examples:
    print $_->number, "\n" foreach @{ $device->ints_by_number() };

=cut

sub ints_by_number {
    my $self = shift;
    $self->isa_object_method('ints_by_number');

    my @ifs = $self->interfaces();

    my ($nondigit, $letters);
    for ( @ifs ) { 
	if ($_->number =~ /\D/){ 
	    $nondigit = 1;  
	    if ($_->number =~ /[A-Za-z]/){ 
		$letters = 1;  
	    }
	}
    }

    if ( $nondigit ){
	    my @tmp;
	    foreach my $if ( @ifs ){
		my $num = $if->number;
		$num =~ s/\W+//g;
		push @tmp, [$num, $if];
	    }
	if ( $letters ){
	    @ifs = map { $_->[1] } sort { $a->[0] cmp $b->[0] } @tmp;	    
	}else{
	    @ifs = map { $_->[1] } sort { $a->[0] <=> $b->[0] } @tmp;
	}
    }else{
	@ifs = sort { $a->number <=> $b->number } @ifs;
    }

    return \@ifs;
}

############################################################################
=head2 ints_by_name - Retrieve interfaces from a Device and sort by name.  

    This method deals with the problem of sorting Interface names that contain numbers.
    Simple alphabetical sorting does not yield useful results.

  Arguments:  
    None
  Returns:    
    Sorted arrayref of interface objects
  Exampless:

=cut

sub ints_by_name {
    my $self = shift;
    $self->isa_object_method('ints_by_name');

    my @ifs = $self->interfaces;
    
    # The following was borrowed from Netviewer
    # and was slightly modified to handle Netdot Interface objects.
    # Yes. It is ugly.
    @ifs = ( map { $_->[0] } sort { 
	       $a->[1] cmp $b->[1]
	    || $a->[2] <=> $b->[2]
	    || $a->[3] <=> $b->[3]
	    || $a->[4] <=> $b->[4]
	    || $a->[5] <=> $b->[5]
	    || $a->[6] <=> $b->[6]
	    || $a->[7] <=> $b->[7]
	    || $a->[8] <=> $b->[8]
	    || $a->[0]->name cmp $b->[0]->name }  
	     map{ [ $_, $_->name =~ /^(\D+)\d/, 
		    ( split( /\D+/, $_->name ))[0,1,2,3,4,5,6,7,8] ] } @ifs);
    
    return \@ifs;
}

############################################################################
=head2 ints_by_speed - Retrieve interfaces from a Device and sort by speed.  

  Arguments:  
    None
  Returns:    
    Sorted array of interface objects

=cut

sub ints_by_speed {
    my $self = shift;
    $self->isa_object_method('ints_by_speed');

    my @ifs = Interface->search( device => $self->id, {order_by => 'speed'});
    
    return \@ifs;
}

############################################################################
=head2 interfaces_by_vlan - Retrieve interfaces from a Device and sort by vlan ID

Arguments:  None
Returns:    Sorted arrayref of interface objects

Note: If the interface has/belongs to more than one vlan, sort function will only
use one of the values.

=cut

sub ints_by_vlan {
    my $self = shift;
    $self->isa_object_method('ints_by_vlan');

    my @ifs = $self->interfaces();
    my @tmp = map { [ ($_->vlans) ? ($_->vlans)[0]->vlan->vid : 0, $_] } @ifs;
    @ifs = map { $_->[1] } sort { $a->[0] <=> $b->[0] } @tmp;

    return \@ifs;
}

############################################################################
=head2 ints_by_jack - Retrieve interfaces from a Device and sort by Jack id

Arguments:  None
Returns:    Sorted arrayref of interface objects

=cut

sub ints_by_jack {
    my ( $self ) = @_;

    $self->isa_object_method('ints_by_jack');
    
    my @ifs = $self->interfaces();

    my @tmp = map { [ ($_->jack) ? $_->jack->jackid : 0, $_] } @ifs;
    @ifs = map { $_->[1] } sort { $a->[0] cmp $b->[0] } @tmp;

    return \@ifs;
}

############################################################################
=head2 ints_by_descr - Retrieve interfaces from a Device and sort by description

Arguments:  None
Returns:    Sorted arrayref of interface objects

=cut

sub ints_by_descr {
    my ( $self, $o ) = @_;
    $self->isa_object_method('ints_by_descr');

    my @ifs = Interface->search( device => $self->id, {order_by => 'description'});

    return \@ifs;
}

############################################################################
=head2 ints_by_monitored - Retrieve interfaces from a Device and sort by 'monitored' field

Arguments:  None
Returns:    Sorted arrayref of interface objects

=cut

sub ints_by_monitored {
    my ( $self, $o ) = @_;
    $self->isa_object_method('ints_by_monitored');

    my @ifs = Interface->search( device => $self->id, {order_by => 'monitored DESC'});

    return \@ifs;
}

############################################################################
=head2 ints_by_status - Retrieve interfaces from a Device and sort by 'status' field

Arguments:  None
Returns:    Sorted arrayref of interface objects

=cut

sub ints_by_status {
    my ( $self, $o ) = @_;
    $self->isa_object_method('ints_by_status');

    my @ifs = Interface->search( device => $self->id, {order_by => 'oper_status'});

    return \@ifs;
}

############################################################################
=head2 ints_by_snmp - Retrieve interfaces from a Device and sort by 'snmp_managed' field

Arguments:  None
Returns:    Sorted arrayref of interface objects

=cut

sub ints_by_snmp {
    my ( $self, $o ) = @_;
    $self->isa_object_method('ints_by_snmp');

    my @ifs = Interface->search( device => $self->id, {order_by => 'snmp_managed DESC'});

    return \@ifs;
}

############################################################################
=head2 interfaces_by - Retrieve sorted list of interfaces from a Device

    This will call different methods depending on the sort field specified

  Arguments:
    Hash with the following keys:
      sort_by  [number|name|speed|vlan|jack|descr|monitored|snmp]
  Returns:    
    Sorted arrayref of interface objects
  Examples:
    print $_->name, "\n" foreach $device->interfaces_by('name');
    
=cut

sub interfaces_by {
    my ( $self, $sort ) = @_;
    $self->isa_object_method('interfaces_by');

    $sort ||= "number";

    if ( $sort eq "number" ){
	return $self->ints_by_number;
    }elsif ( $sort eq "name" ){
	return $self->ints_by_name;
    }elsif( $sort eq "speed" ){
	return $self->ints_by_speed;
    }elsif( $sort eq "vlan" ){
	return $self->ints_by_vlan;
    }elsif( $sort eq "jack" ){
	return $self->ints_by_jack;
    }elsif( $sort eq "descr"){
	return $self->ints_by_descr;
    }elsif( $sort eq "monitored"){
	return $self->ints_by_monitored;
    }elsif( $sort eq "snmp"){
	return $self->ints_by_snmp;
    }elsif( $sort eq "oper_status"){
	return $self->ints_by_status;
    }else{
	$self->throw_fatal("Model::Device::interfaces_by: Unknown sort field: $sort");
    }
}

############################################################################
=head2 bgppeers_by_ip - Sort by remote IP

  Arguments:  
    Array ref of BGPPeering objects
  Returns:    
    Sorted arrayref of BGPPeering objects
=cut
sub bgppeers_by_ip {
    my ( $self, $peers ) = @_;
    $self->isa_object_method('bgppeers_by_ip');

    my @peers = map { $_->[1] } 
    sort  { pack("C4"=>$a->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) 
		cmp pack("C4"=>$b->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/); }  
    map { [$_->bgppeeraddr, $_] } @$peers ;
    
    return unless scalar @peers;
    return \@peers;
}

############################################################################
=head2 bgppeers_by_id - Sort by BGP ID

  Arguments:  
    Array ref of BGPPeering objects
  Returns:    
    Sorted arrayref of BGPPeering objects

=cut
sub bgppeers_by_id {
    my ( $self, $peers ) = @_;
    $self->isa_object_method('bgppeers_by_id');

    my @peers = map { $_->[1] } 
    sort  { pack("C4"=>$a->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) 
		cmp pack("C4"=>$b->[0] =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/); }  
    map { [$_->bgppeerid, $_] } @$peers ;
    
    return unless scalar @peers;
    return \@peers;
}

############################################################################
=head2 bgppeers_by_entity - Sort by Entity name, AS number or AS Name

  Arguments:  
    Array ref of BGPPeering objects, 
    Entity table field to sort by [name*|asnumber|asname]
  Returns:    
    Sorted array of BGPPeering objects

=cut
sub bgppeers_by_entity {
    my ( $self, $peers, $sort ) = @_;
    $self->isa_object_method('bgppeers_by_id');

    $sort ||= "name";
    unless ( $sort =~ /name|asnumber|asname/ ){
	$self->throw_fatal("Model::Device::bgppeers_by_entity: Invalid Entity field: $sort");
    }
    my $sortsub = ($sort eq "asnumber") ? 
	sub{$a->entity->$sort <=> $b->entity->$sort} :
	sub{$a->entity->$sort cmp $b->entity->$sort};
    my @peers = sort $sortsub @$peers;
    
    return unless scalar @peers;
    return \@peers;
}


############################################################################
=head2 get_bgp_peers - Retrieve BGP peers that match certain criteria and sort them

    This overrides the method auto-generated by Class::DBI

 Arguments:  
    Hash with the following keys:
    entity    <string>  Return peers whose entity name matches <string>
    id        <integer> Return peers whose ID matches <integer>
    ip        <address> Return peers whose Remote IP matches <address>
    as        <integer> Return peers whose AS matches <integer>
    type      <string>  Return peers of type [internal|external|all*]
    sort      <string>  Sort by [entity*|asnumber|asname|id|ip]

    (*) default

  Returns:    
    Sorted arrayref of BGPPeering objects
  Examples:
    print $_->entity->name, "\n" foreach @{ $device->get_bgp_peers() };

=cut
sub get_bgp_peers {
    my ( $self, %argv ) = @_;
    $self->isa_object_method('get_bgp_peers');

    $argv{type} ||= "all";
    $argv{sort} ||= "entity";
    my @peers;
    if ( $argv{entity} ){
	@peers = grep { $_->entity->name eq $argv{entity} } $self->bgppeers;
    }elsif ( $argv{id} ){
	@peers = grep { $_->bgppeerid eq $argv{id} } $self->bgppeers;	
    }elsif ( $argv{ip} ){
	@peers = grep { $_->bgppeeraddr eq $argv{id} } $self->bgppeers;	
    }elsif ( $argv{as} ){
	@peers = grep { $_->asnumber eq $argv{as} } $self->bgppeers;	
    }elsif ( $argv{type} ){
	if ( $argv{type} eq "internal" ){
	    @peers = grep { $_->entity->asnumber == $self->bgplocalas } $self->bgppeers;
	}elsif ( $argv{type} eq "external" ){
	    @peers = grep { $_->entity->asnumber != $self->bgplocalas } $self->bgppeers;
	}elsif ( $argv{type} eq "all" ){
	    @peers = $self->bgppeers();
	}else{
	    $self->throw_fatal("Model::Device::get_bgp_peers: Invalid type: $argv{type}");
	}
    }elsif ( ! $argv{sort} ){
	$self->throw_fatal("Model::Device::get_bgp_peers: Missing or invalid search criteria");
    }
    if ( $argv{sort} =~ /entity|asnumber|asname/ ){
	$argv{sort} =~ s/entity/name/;
	return $self->bgppeers_by_entity(\@peers, $argv{sort});
    }elsif( $argv{sort} eq "ip" ){
	return $self->bgppeers_by_ip(\@peers);
    }elsif( $argv{sort} eq "id" ){
	return $self->bgppeers_by_id(\@peers);
    }else{
	$self->throw_fatal("Model::Device::get_bgp_peers: Invalid sort argument: $argv{sort}");
    }
    
    return \@peers if scalar @peers;
    return;
}

###################################################################################################
=head2 set_overwrite_if_descr - Set the overwrite_description flag in all interfaces of this device

    This flag controls whether the ifAlias value returned from the Device should
    overwrite the value of the Interface description field in the database.  
    Some devices return a null string, which would erase any user-entered descriptions in Netdot.
    This method sets that value of this flag for each interface in the device.

  Arguments:  
    0 or 1 (true or false)
  Returns:    
    True if successful
  Example:
    $device->set_overwrite_if_descr(1);
$logger->info
=cut
sub set_overwrite_if_descr {
    my ($self, $value) = @_;
    $self->isa_object_method("set_overwrite_if_descr");
    
    $self->throw_fatal("Model::Device::set_overwrite_if_descr: Invalid value: $value.  Should be 0|1")
	unless ( $value =~ /^0|1$/ );

    foreach my $int ( $self->interfaces ){
	$int->update({overwrite_descr=>$value});
    }
    
    return 1;
}

###################################################################################################
=head2 set_interfaces_auto_dns - Sets auto_dns flag on all IP interfaces of this device

  Arguments:  
    0 or 1 (true or false)
  Returns:    
    True if successful
  Example:
    $device->set_interfaces_auto_dns(1);
$logger->info
=cut
sub set_interfaces_auto_dns {
    my ($self, $value) = @_;
    $self->isa_object_method("set_interfaces_auto_dns");
    
    $self->throw_fatal("Model::Device::set_interfaces_auto_dns: Invalid value: $value. Should be 0|1")
	unless ( $value =~ /^0|1$/ );

    foreach my $int ( $self->interfaces ){
	# Ony interfaces with IP addresses
	next unless $int->ips;
	$int->update({auto_dns=>$value});
    }
    
    return 1;
}


#####################################################################
#
# Private methods
#
#####################################################################

############################################################################
# Validate arguments to insert and update
# 
#   Arguments:
#     hash reference with field/value pairs for Device
#   Returns:
#     True or throws exceptions
#
sub _validate_args {
    my ($proto, $args) = @_;
    my ($self, $class);
    if ( $class = ref $proto ){
	$self = $proto;
    }else{
	$class = $proto;
    }
    
    # We need a name always
    $args->{name} ||= $self->name if ( defined $self );
    unless ( $args->{name} ){
	$class->throw_user("Name cannot be null");
    }
    
    # SNMP Version
    if ( defined $args->{snmp_version} ){
	if ( $args->{snmp_version} !~ /^1|2|3$/ ){
	    $class->throw_user("Invalid SNMP version.  It must be either 1, 2 or 3");
	}
    }

    # Asset
    if ( $args->{asset_id} && (my $asset = Asset->retrieve(int($args->{asset_id}))) ){
	# is there a device associated with this asset number we're given?
	if ( my $otherdev = ($asset->devices)[0] ){
	    if ( defined $self ){
		if ( $self->id != $otherdev->id ){
		    my $msg = sprintf("%s: S/N %s belongs to existing device: %s", 
				      $self->fqdn, $asset->serial_number, $otherdev->fqdn);
		    if ( Netdot->config->get('ENFORCE_DEVICE_UNIQUENESS') ){
			$self->throw_user($msg); 
		    }else{
			$logger->warn($msg);
		    }
		}
	    }else{
		my $msg = sprintf("S/N %s belongs to existing device: %s",
				  $asset->serial_number, $otherdev->fqdn);
		if ( Netdot->config->get('ENFORCE_DEVICE_UNIQUENESS') ){
		    $class->throw_user($msg);
		}else{
		    $logger->warn($msg);
		}
	    }
	}
    }
    
    # Base bridge MAC
    if ( defined $args->{physaddr} ){
	# Notice we use int() to stringify the object if it is one
	if ( my $mac = PhysAddr->retrieve(int($args->{physaddr})) ){
	    my $address = $mac->address;
	    if ( my $otherdev = ($mac->devices)[0] ){
		if ( defined $self ){
		    if ( $self->id != $otherdev->id ){
			# Another device has this address!
			my $msg = sprintf("%s: At least one other device with this base MAC: %s already exists: %s", 
					  $self->fqdn, $address, $otherdev->fqdn);
			if ( Netdot->config->get('ENFORCE_DEVICE_UNIQUENESS') ){
			    $class->throw_user($msg); 
			}else{
			    $logger->warn($msg);
			}
		    }
		}else{
		    my $msg = sprintf("At least one other device with this base MAC: %s already exists: %s", 
				      $address, $otherdev->fqdn);
		    if ( $class->config->get('ENFORCE_DEVICE_UNIQUENESS') ){
			$class->throw_user($msg); 
		    }else{
			$logger->warn($msg);
		    }
		}
	    }
	}
    }
    return 1;
}

########################################################################################
# _layer_active - Determine if a particular layer is active in the layers bit string
#    
#
#   Arguments:
#     layers bit string
#     layer number
#   Returns:
#     True/False
#
#   Examples:
#     $class->_layer_active(2);
#
sub _layer_active {
    my ($class, $layers, $layer) = @_;
    $class->isa_class_method('_layer_active');
    
    $class->throw_fatal("Model::Device::_layer_active: Missing required arguments: layers && layer")
	unless ( $layers && $layer );
    
    return substr($layers,8-$layer, 1);
}

# ############################################################################
# _get_snmp_session - Establish a SNMP session.  Tries to reuse sessions.
#    
#   Arguments:
#     Arrayref with the following keys (mostly optional):
#      host         IP or hostname (required unless called as instance method)
#      communities  Arrayref of SNMP Community strings
#      version      SNMP version
#      sec_name     SNMP Security Name
#      sec_level    SNMP Security Level
#      auth_proto   SNMP Authentication Protocol
#      auth_pass    SNMP Auth Key
#      priv_proto   SNMP Privacy Protocol
#      priv_pass    SNMP Privacy Key
#      bulkwalk     Whether to use SNMP BULK
#      timeout      SNMP Timeout
#      retries      Number of retries after Timeout
#      sclass       SNMP::Info class
#
#   Returns:
#     SNMP::Info object if successful
#
#   Examples:
#    
#     Instance call:
#     my $session = $device->get_snmp_session();
#
#     Class call:
#     my $session = Device->get_snmp_session(host=>$hostname, communities=>['public']);
#

sub _get_snmp_session {
    my ($self, %argv) = @_;

    my $class;
    my $sclass = $argv{sclass} if defined ( $argv{sclass} );

    if ( $class = ref($self) ){
	# Being called as an instance method

	# Do not continue unless snmp_managed flag is on
	$self->throw_user(sprintf("Device %s not SNMP-managed. Aborting.", $self->fqdn))
	    unless $self->snmp_managed;

	# Do not continue if we've exceeded the connection attempts threshold
	$self->throw_user(sprintf("Device %s has been marked as snmp_down. Aborting.", $self->fqdn))
	    if ( $self->snmp_down == 1 );

	# Fill up SNMP arguments from object if it wasn't passed to us
	if ( !defined $argv{communities} && $self->community ){
	    push @{$argv{communities}}, $self->community;
	}
	$argv{bulkwalk} ||= $self->snmp_bulk;
	$argv{version}  ||= $self->snmp_version;
	if ( $argv{version} == 3 ){
	    $argv{sec_name}   ||= $self->snmp_securityname;
	    $argv{sec_level}  ||= $self->snmp_securitylevel;
	    $argv{auth_proto} ||= $self->snmp_authprotocol;
	    $argv{auth_pass}  ||= $self->snmp_authkey;
	    $argv{priv_proto} ||= $self->snmp_privprotocol;
	    $argv{priv_pass}  ||= $self->snmp_privkey;
	}

	# We might already have a SNMP::Info class
	$sclass ||= $self->{_sclass};
	
	# Fill out some arguments if not given explicitly
	unless ( $argv{host} ){
	    if ( $self->snmp_target ){
		$argv{host} = $self->snmp_target->address;
	    }else{
		$argv{host} = $self->fqdn;
	    }
	}
	$self->throw_user(sprintf("Could not determine IP nor hostname for Device id: %d", $self->id))
	    unless $argv{host};
	
    }else{
	$self->throw_fatal("Model::Device::_get_snmp_session: Missing required arguments: host")
	    unless $argv{host};
    }

    # If we still don't have any communities, get defaults from config file
    $argv{communities} = $self->config->get('DEFAULT_SNMPCOMMUNITIES')
	unless defined $argv{communities};
    
    $sclass ||= 'SNMP::Info';
    
    # Set defaults
    my %sinfoargs = ( DestHost      => $argv{host},
		      Version       => $argv{version} || $self->config->get('DEFAULT_SNMPVERSION'),
		      Timeout       => (defined $argv{timeout}) ? $argv{timeout} : $self->config->get('DEFAULT_SNMPTIMEOUT'),
		      Retries       => (defined $argv{retries}) ? $argv{retries} : $self->config->get('DEFAULT_SNMPRETRIES'),
		      AutoSpecify   => 1,
		      Debug         => ( $logger->is_debug() )? 1 : 0,
		      BulkWalk      => (defined $argv{bulkwalk}) ? $argv{bulkwalk} :  $self->config->get('DEFAULT_SNMPBULK'),
		      BulkRepeaters => 20,
		      MibDirs       => \@MIBDIRS,
		      );

    # Turn off bulkwalk if we're using Net-SNMP 5.2.3 or 5.3.1.
    if ( $sinfoargs{BulkWalk} == 1  && ($SNMP::VERSION eq '5.0203' || $SNMP::VERSION eq '5.0301') 
	&& !$self->config->get('IGNORE_BUGGY_SNMP_CHECK')) {
	$logger->info("Turning off bulkwalk due to buggy Net-SNMP $SNMP::VERSION");
	$sinfoargs{BulkWalk} = 0;
    }

    my ($sinfo, $layers);

    # Deal with the number of connection attempts and the snmp_down flag
    # We need to do this in a couple of places
    sub _check_max_attempts {
	my ($self, $host) = @_;
	return unless ref($self); # only applies to instance calls
	my $max = $self->config->get('MAX_SNMP_CONNECTION_ATTEMPTS');
	my $count = $self->snmp_conn_attempts || 0;
	$count++;
	$self->update({snmp_conn_attempts=>$count});
	$logger->info(sprintf("Device::_get_snmp_session: %s: Failed connection attempts: %d",
			      $host, $count));
	if ( $max == 0 ){
	    # This setting implies that we're told not to limit maximum connections
	    return;
	}
	if ( $count >= $max ){
	    $self->update({snmp_down=>1});
	}
    }

    if ( $sinfoargs{Version} == 3 ){
	$sinfoargs{SecName}   = $argv{sec_name}   if $argv{sec_name};
	$sinfoargs{SecLevel}  = $argv{sec_level}  if $argv{sec_level};
	$sinfoargs{AuthProto} = $argv{auth_proto} if $argv{auth_proto};
	$sinfoargs{AuthPass}  = $argv{auth_pass}  if $argv{auth_pass};
	$sinfoargs{PrivProto} = $argv{priv_proto} if $argv{priv_proto};
	$sinfoargs{PrivPass}  = $argv{priv_pass}  if $argv{priv_pass};

	$logger->debug(sub{ sprintf("Device::get_snmp_session: Trying SNMPv%d session with %s",
				    $sinfoargs{Version}, $argv{host})});
	
	$sinfo = $sclass->new( %sinfoargs );

	if ( defined $sinfo ){
	    # Check for errors
	    if ( my $err = $sinfo->error ){
		$self->throw_user(sprintf("Device::_get_snmp_session: SNMPv%d error: device %s: %s", 
					  $sinfoargs{Version}, $argv{host}, $err));
	    }
	    
	    # Test for connectivity
	    $layers = $sinfo->layers() || 
		$self->throw_user(sprintf("Device::_get_snmp_session: %s: SNMPv%d failed: No sysServices", 
					  $argv{host}, $sinfoargs{Version}));
	    
	}else {
	    &_check_max_attempts($self, $argv{host});
	    $self->throw_user(sprintf("Device::get_snmp_session: %s: SNMPv%d failed", 
				      $argv{host}, $sinfoargs{Version}));
	}
   
    }else{
	# Try each community
	foreach my $community ( @{$argv{communities}} ){

	    $sinfoargs{Community} = $community;
	    $logger->debug(sub{ sprintf("Device::_get_snmp_session: Trying SNMPv%d session with %s, community %s",
					$sinfoargs{Version}, $argv{host}, $sinfoargs{Community})});
	    $sinfo = $sclass->new( %sinfoargs );
	    
	    # If v2 failed, try v1
 	    if ( !defined $sinfo && $sinfoargs{Version} == 2 ){
 		$logger->debug(sub{ sprintf("Device::_get_snmp_session: %s: SNMPv%d failed. Trying SNMPv1", 
 					    $argv{host}, $sinfoargs{Version})});
 		$sinfoargs{Version} = 1;
 		$sinfo = $sclass->new( %sinfoargs );
 	    }
	    
	    if ( defined $sinfo ){
		# Check for errors
		if ( my $err = $sinfo->error ){
		    $self->throw_user(sprintf("Device::_get_snmp_session: SNMPv%d error: device %s, community '%s': %s", 
					      $sinfoargs{Version}, $argv{host}, $sinfoargs{Community}, $err));
		}
		# Test for connectivity
		$layers = $sinfo->layers() || 
		    $self->throw_user(sprintf("Device::_get_snmp_session: %s: SNMPv%d failed: No sysServices", 
					      $argv{host}, $sinfoargs{Version}));

		last; # If we made it here, we are fine.  Stop trying communities

	    }else{
		$logger->debug(sub{ sprintf("Device::_get_snmp_session: Failed SNMPv%s session with %s community '%s'", 
					    $sinfoargs{Version}, $argv{host}, $sinfoargs{Community})});
	    }

	} #end foreach community

	unless ( defined $sinfo ){
	    &_check_max_attempts($self, $argv{host});
	    $self->throw_user(sprintf("Device::_get_snmp_session: Cannot connect to %s.  Tried communities: %s", 
				      $argv{host}, (join ', ', @{$argv{communities}}) ));
	}
    }


    if ( $class ){
	# We're called as an instance method

	# Save SNMP::Info class
	$logger->debug(sub{"Device::get_snmp_session: $argv{host} is: ", $sinfo->class() });
	$self->{_sclass} = $sinfo->class();
	
	my %uargs;

	# Reset dead counter and snmp_down flag
	$uargs{snmp_conn_attempts} = 0; $uargs{snmp_down} = 0;

	# We might have tried a different SNMP version and community above. Rectify DB if necessary
	$uargs{snmp_version} = $sinfoargs{Version}   if ( !$self->snmp_version || $self->snmp_version ne $sinfoargs{Version}  );
	$uargs{snmp_bulk}    = $sinfoargs{BulkWalk}  if ( !$self->snmp_bulk    || $self->snmp_bulk    ne $sinfoargs{BulkWalk} );
	if ( $sinfoargs{Version} == 3 ){
	    # Store v3 parameters
	    $uargs{snmp_securityname}  = $sinfoargs{SecName}   if (!$self->snmp_securityname  || $self->snmp_securityname  ne $sinfoargs{SecName});
	    $uargs{snmp_securitylevel} = $sinfoargs{SecLevel}  if (!$self->snmp_securitylevel || $self->snmp_securitylevel ne $sinfoargs{SecLevel});
	    $uargs{snmp_authprotocol}  = $sinfoargs{AuthProto} if (!$self->snmp_authprotocol  || $self->snmp_authprotocol  ne $sinfoargs{AuthProto});
	    $uargs{snmp_authkey}       = $sinfoargs{AuthPass}  if (!$self->snmp_authkey       || $self->snmp_authkey       ne $sinfoargs{AuthPass});
	    $uargs{snmp_privprotocol}  = $sinfoargs{PrivProto} if (!$self->snmp_privprotocol  || $self->snmp_privprotocol  ne $sinfoargs{PrivProto});
	    $uargs{snmp_privkey}       = $sinfoargs{PrivPass}  if (!$self->snmp_privkey       || $self->snmp_privkey       ne $sinfoargs{PrivPass});
	}else{
	    $uargs{community} = $sinfoargs{Community} if (!$self->community || $self->community ne $sinfoargs{Community});
	}
	$self->update(\%uargs) if ( keys %uargs );
    }
    $logger->debug(sub{ sprintf("SNMPv%d session with host %s established", $sinfoargs{Version}, $argv{host}) });

    # We want to do our own 'munging' for certain things
    my $munge = $sinfo->munge();
    delete $munge->{'i_speed'};      # We store these as integers in the db.  Munge at display
    $munge->{'i_speed_high'} = sub{ return $self->_munge_speed_high(@_) };
    $munge->{'stp_root'}     = sub{ return $self->_stp2mac(@_) };
    $munge->{'stp_p_bridge'} = sub{ return $self->_stp2mac(@_) };
    foreach my $m ('i_mac', 'fw_mac', 'mac', 'b_mac', 'at_paddr', 'rptrAddrTrackNewLastSrcAddress',
		   'stp_p_port'){
	$munge->{$m} = sub{ return $self->_oct2hex(@_) };
    }
    return $sinfo;
}

#########################################################################
# Return device's main IP, which will determine device's main name
#
sub _get_main_ip {
    my ($class, $info) = @_;

    $class->throw_fatal("Model::Device::_get_main_ip: Missing required argument (info)")
	unless $info;
    my @methods = @{$class->config->get('DEVICE_NAMING_METHOD_ORDER')};
    $class->throw_fatal("Model::Device::_get_main_ip: Missing or invalid configuration variable: DEVICE_NAMING_METHOD_ORDER")
	unless scalar @methods;

    my %allips;
    my @allints = keys %{$info->{interface}};
    map { map { $allips{$_} = '' } keys %{$info->{interface}->{$_}->{ips}} } @allints;
    
    my $ip;
    if ( scalar(keys %allips) == 1 ){
	$ip = (keys %allips)[0];
	$logger->debug(sub{"Device::_get_main_ip: Device has one IP: $ip" });
    }
    foreach my $method ( @methods ){
	$logger->debug(sub{"Device::_get_main_ip: Trying method $method" });
	if ( $method eq 'sysname' && $info->{sysname} ){
	    my @resips = Netdot->dns->resolve_name($info->{sysname});
	    foreach my $resip ( @resips ){
		if ( defined $resip && exists $allips{$resip} ){
		    $ip = $resip;
		    last;
		}
	    }
	}elsif ( $method eq 'highest_ip' ){
	    my %dec;
	    foreach my $int ( @allints ){
		map { $dec{$_} = Ipblock->ip2int($_) } keys %allips;
	    }
	    my @ordered = sort { $dec{$b} <=> $dec{$a} } keys %dec;
	    $ip = $ordered[0];
	}elsif ( $method =~ /loopback/ ){
	    my %loopbacks;
	    foreach my $int ( @allints ){
		my $name = $info->{interface}->{$int}->{name};
		if (  $name && $name =~ /^loopback(\d+)/i ){
		    $loopbacks{$int} = $1;
		}
	    }
	    my @ordered = sort { $loopbacks{$a} <=> $loopbacks{$b} } keys %loopbacks;
	    my $main_int;
	    if ( $method eq 'lowest_loopback' ){
		$main_int = shift @ordered;
	    }elsif ( $method eq 'highest_loopback' ){
		$main_int = pop @ordered;
	    }
	    if ( $main_int ){
		$ip = (keys %{$info->{interface}->{$main_int}->{ips}})[0];
	    }
	}elsif ( $method eq 'router_id' ){
	    $ip = $info->{router_id} if defined $info->{router_id};
	}elsif ( $method eq 'snmp_target' ){
	    $ip = $info->{snmp_target};
	}
	
	if ( defined $ip ){
	    if ( Ipblock->matches_v4($ip) && Ipblock->validate($ip) ){
		$logger->debug(sub{"Device::_get_main_ip: Chose $ip using naming method: $method" });
		return $ip ;
	    }else{
		$logger->debug(sub{"Device::_get_main_ip: $ip not valid.  Ignoring"});
		# Keep trying
		undef($ip);
	    }
	    
	}
    }
    $logger->debug(sub{"Device::_get_main_ip: Could not determine the main IP for this device"});
    return;
}

#########################################################################
# Retrieve STP info
sub _get_stp_info {
    my ($self, %argv) = @_;

   my $sinfo = $argv{sinfo};
    my %res;
    foreach my $method ( 
	'stp_root', 'stp_root_port', 'stp_priority', 
	'i_stp_bridge', 'i_stp_port', 'i_stp_state', 
	){
	$res{$method} = $sinfo->$method;
    }
    return \%res;
}

#########################################################################
# Retrieve STP interface info
sub _get_i_stp_info {
    my ($self, %argv) = @_;

    # Map method name to interface field name
    my %STPFIELDS = (
	'i_bpdufilter_enabled' => 'bpdu_filter_enabled',
	'i_bpduguard_enabled'  => 'bpdu_guard_enabled',
	'i_rootguard_enabled'  => 'root_guard_enabled',
	'i_loopguard_enabled'  => 'loop_guard_enabled',
	);

    my $sinfo = $argv{sinfo};
    my %res;
    foreach my $method ( 
	'i_rootguard_enabled', 'i_loopguard_enabled', 
	'i_bpduguard_enabled', 'i_bpdufilter_enabled' 
	){
	$res{$STPFIELDS{$method}} = $sinfo->$method;
	foreach my $i ( keys %{$res{$STPFIELDS{$method}}} ){
	    $res{$STPFIELDS{$method}}->{$i} = ($res{$STPFIELDS{$method}}->{$i} eq 'true' || 
					       $res{$STPFIELDS{$method}}->{$i} eq 'enable' )? 1 : 0;
	}
    }
    return \%res;
}

#########################################################################
# Retrieve a list of device objects from given file (one per line)
#
# Arguments:  File path
# Returns  :  Arrayref of device objects
#
sub _get_devs_from_file {
    my ($class, $file) = @_;
    $class->isa_class_method('get_devs_from_file');

    my $hosts = $class->_get_hosts_from_file($file);
    my @devs;
    foreach my $host ( keys %$hosts ){
	if ( my $dev = $class->search(name=>$host)->first ){
	    push @devs, $dev; 
	}else{
	    $logger->info("Device $host does not yet exist in the Database.");
	}
    }
    $class->throw_user("Device::_get_devs_from_file: No existing devices in list.  You might need to run a discover first.")
	unless ( scalar @devs );

    return \@devs;
}
#########################################################################
# Retrieve a list of hostnames/communities from given file (one per line)
# 
# Arguments:  File path
# Returns  :  Hashref with hostnames (or IP addresses) as key 
#             and SNMP community as value
# 
sub _get_hosts_from_file {
    my ($class, $file) = @_;
    $class->isa_class_method('get_hosts_from_file');

    $class->throw_user("Device::_get_hosts_from_file: Missing or invalid file: $file")
	unless ( defined($file) && -r $file );
  
    open(FILE, "<$file") or 
	$class->throw_user("Can't open file $file for reading: $!");
    
    $logger->debug(sub{"Device::_get_hosts_from_file: Retrieving host list from $file" });

    my %hosts;
    while (<FILE>){
	chomp($_);
	next if ( /^#/ );
	if ( /\w+\s+\w+/ ){
	    my ($host, $comm) = split /\s+/, $_;
	    $hosts{$host} = $comm;
	}
    }
    
    $class->throw_user("Host list is empty!")
	unless ( scalar keys %hosts );
    
    close(FILE);
    return \%hosts;
}

#########################################################################
# Initialize ForkManager
# Arguments:    None
# Returns  :    Parallel::ForkManager object
#
sub _fork_init {
    my ($class) = @_;
    $class->isa_class_method('_fork_init');

    # Tell DBI that we don't want to disconnect the server's DB handle
    my $dbh = $class->db_Main;
    unless ( $dbh->{InactiveDestroy} = 1 ) {
	$class->throw_fatal("Model::Device::_fork_init: Cannot set InactiveDestroy: ", $dbh->errstr);
    }

    # MAXPROCS processes for parallel updates
    $logger->debug(sub{"Device::_fork_init: Launching up to $MAXPROCS children processes" });
    my $pm = Parallel::ForkManager->new($MAXPROCS);

    # Prevent SNMP::Info from loading mib-init in each forked process
    $logger->debug("Device::_fork_init: Loading dummy SNMP::Info object");
    my $dummy = SNMP::Info->new( DestHost    => 'localhost',
				 Version     => 1,
				 AutoSpecify => 0,
				 Debug       => ( $logger->is_debug() )? 1 : 0,
				 MibDirs     => \@MIBDIRS,
	);

    return $pm;
}

#########################################################################
# _fork_end - Wrap up ForkManager
#    Wait for all children
#    Set InactiveDestroy back to default
#
# Arguments:    Parallel::ForkManager object
# Returns  :    True if successful
#
sub _fork_end {
    my ($class, $pm) = @_;
    $class->isa_class_method('_fork_end');

    # Wait for all children to finish
    $logger->debug(sub{"Device::_fork_end: Waiting for children..." });
    $pm->wait_all_children;
    $logger->debug(sub{"Device::_fork_end: All children finished" });

    # Return DBI to its normal DESTROY behavior
    my $dbh = $class->db_Main;
    $dbh->{InactiveDestroy} = 0;
    return 1;
}

####################################################################################
# snmp_update_parallel - Discover and/or update all devices in given list concurrently
#    
#   Arguments:
#     Hash with the following keys:
#     hosts          Hashref of host names and their communities
#     devs           Arrayref of Device objects
#     communities    Arrayref of SNMP communities
#     version        SNMP version
#     timeout        SNMP timeout
#     retries        SNMP retries
#     do_info        Update Device Info
#     do_fwt         Update Forwarding Tables
#     do_arp         Update ARP caches
#     add_subnets    Flag. When discovering routers, add subnets to database if they do not exist
#     subs_inherit   Flag. When adding subnets, have them inherit information from the Device
#     bgp_peers      Flag. When discovering routers, update bgp_peers
#     pretend        Flag. Do not commit changes to the database
#   Returns: 
#     Device count
#
sub snmp_update_parallel {
    my ($class, %argv) = @_;
    $class->isa_class_method('snmp_update_parallel');

    my ($hosts, $devs);
    if ( defined $argv{hosts} ){
	$class->throw_fatal("Model::Device::snmp_update_parallel: Invalid hosts hash") 
	    if ( ref($argv{hosts}) ne "HASH" );
	$hosts = $argv{hosts};
    }elsif ( defined $argv{devs} ){
	$class->throw_fatal("Model::Device::snmp_update_parallel: Invalid devs array") 
	    if ( ref($argv{devs}) ne "ARRAY" );
	$devs = $argv{devs};
    }else{
	$class->throw_fatal("Model::Device::_snmp_update_parallel: Missing required parameters: hosts or devs");
    }
    
    my %uargs;
    foreach my $field ( qw(version timeout retries sec_name sec_level auth_proto auth_pass 
                           priv_proto priv_pass add_subnets subs_inherit bgp_peers pretend 
                           do_info do_fwt do_arp) ){
	$uargs{$field} = $argv{$field} if defined ($argv{$field});
    }

    $uargs{no_update_tree} = 1;
    $uargs{timestamp}      = $class->timestamp;
    my %do_devs;
    
    my $device_count = 0;
    my $start = time;
    # Init ForkManager
    my $pm = $class->_fork_init();

    if ( $devs ){
	foreach my $dev ( @$devs ){
	    # Put in list
	    $do_devs{$dev->id} = $dev;
	}
    }elsif ( $hosts ){
	foreach my $host ( keys %$hosts ){
	    # Give preference to the community associated with the host
	    if ( my $commstr = $hosts->{$host} ){
		$uargs{communities} = [$commstr];
	    }else{
		$uargs{communities} = $argv{communities};
	    }
	    # If the device exists in the DB, we add it to the list
	    my $dev;
	    if ( $dev = $class->search(name=>$host)->first ){
		$do_devs{$dev->id} = $dev;
		$logger->debug(sub{ sprintf("%s exists in DB.", $dev->fqdn) });
	    }else{
		$device_count++;
		# FORK
		$pm->start and next;
		eval {
		    $class->_launch_child(pm   => $pm, 
					  code => sub{ return $class->discover(name=>$host, %uargs) } );
		};
		if ( my $e = $@ ){
		    $logger->error($e);
		    exit 1;
		}
		# Make sure the child process ends
		return;
	    }
	}
    }
    
    # Go over list of existing devices
    while ( my ($id, $dev) = each %do_devs ){
	
	# Make sure we don't launch a process unless necessary
	if ( $dev->is_in_downtime() ){
	    $logger->debug(sub{ sprintf("Model::Device::_snmp_update_parallel: %s in downtime.  Skipping", $dev->fqdn) });
	    next;
	}
	my %args = %uargs;

	if ( $args{do_info} ){
	    unless ( $dev->canautoupdate ){
		$logger->debug(sub{ sprintf("%s excluded from auto-updates", $dev->fqdn) });
		$args{do_info} = 0;
	    }
	}
	if ( $args{do_fwt} ){
	    unless ( $dev->collect_fwt ){
		$logger->debug(sub{ sprintf("%s excluded from FWT collection", $dev->fqdn) });
		$args{do_fwt} = 0;
	    }
	}
	if ( $args{do_arp} ){
	    unless ( $dev->collect_arp ){
		$logger->debug(sub{ sprintf("%s excluded from ARP collection", $dev->fqdn) });
		$args{do_arp} = 0;
	    }
	}
	unless ( $args{do_info} || $args{do_fwt} || $args{do_arp} ){
	    next;
	}
	$device_count++;
	# FORK
	$pm->start and next;
	eval {
	    $class->_launch_child(pm   => $pm, 
				  code => sub{ return $dev->snmp_update(%args) } );
	};
	if ( my $e = $@ ){
	    $logger->error($e);
	    exit 1;
	}
	# Make sure the child process ends
	return;
    }

    # End forking state
    $class->_fork_end($pm);
    
    # Rebuild the IP tree if ARP caches were updated
    if ( $argv{do_arp} ){
	Ipblock->build_tree(4);
	Ipblock->build_tree(6);
    }
    my $runtime = time - $start;
    $class->_update_poll_stats($uargs{timestamp}, $runtime);
    
    return $device_count;
}

############################################################################
#_update_poll_stats
#
#   Arguments:
#       timestamp
#   Returns:
#     True if successful
#   Examples:
#     $class->_update_poll_stats($timestamp);
#
#
sub _update_poll_stats {
    my ($class, $timestamp, $runtime) = @_;
    my $relpath = Netdot->config->get('POLL_STATS_FILE_PATH');
    my $file = Netdot->config->get('NETDOT_PATH')."/".$relpath;
    $class->isa_class_method('_update_poll_stats');
    my $stats = $class->_get_poll_stats($timestamp);
    $class->throw_fatal("Device::_update_poll_stats: Error getting stats")
	unless ($stats && ref($stats) eq "HASH");
    my @vals = ($stats->{ips}, $stats->{macs}, $stats->{arp_devices}, 
		$stats->{fwt_devices}, $runtime);
    my $valstr = 'N:';
    $valstr .= join ':', @vals;
    my $template = "ips:macs:arp_devs:fwt_devs:poll_time";
    $logger->debug("Updating Poll Stats for $timestamp: $template, $valstr");
    RRDs::update($file, "-t", $template, $valstr);
    if ( my $e = RRDs::error ){
	$logger->error("_update_poll_stats: Could not update RRD: $e");
	return;
    }
    return 1;
}

############################################################################
#_get_poll_stats
#
#   Arguments:
#       timestamp
#   Returns:
#     True if successful
#   Examples:
#     $class->_get_poll_stats($timestamp);
#
#
sub _get_poll_stats {
    my ($class, $timestamp) = @_;
    $class->isa_class_method('_update_poll_stats');
    $logger->debug("Getting Poll Stats for $timestamp");
    my $dbh = $class->db_Main;

    my %res;  # Store results here

    ##############################################
    # IP addresses
    my $sth1 = $dbh->prepare('SELECT COUNT(id)
                              FROM   ipblock 
                              WHERE  version=4   AND
                                     prefix=32   AND 
                                     last_seen=?
                             ');

    $sth1->execute($timestamp);
    my $total_ips= $sth1->fetchrow_array() || 0;

    my $sth2 = $dbh->prepare('SELECT COUNT(ip.id)
                              FROM   ipblock ip, interface i
                              WHERE  ip.interface=i.id AND
                                     ip.last_seen=?
                             ');
    $sth2->execute($timestamp);
    my $dev_ips= $sth2->fetchrow_array() || 0;

    $res{ips} = $total_ips - $dev_ips;
    
    ##############################################
    # MAC addresses
    my $sth3 = $dbh->prepare('SELECT COUNT(DISTINCT i.physaddr)
                              FROM   physaddr p, interface i 
                              WHERE  i.physaddr=p.id AND
                                     p.last_seen=?
	                     ');
    $sth3->execute($timestamp);
    my $num_int_macs = $sth3->fetchrow_array() || 0;

    my $sth4 = $dbh->prepare('SELECT COUNT(p.id)
                              FROM   physaddr p, device d
                              WHERE  d.physaddr=p.id AND
                                     p.last_seen=?
                             ');
    $sth4->execute($timestamp);
    my $num_dev_macs = $sth4->fetchrow_array() || 0;

    my $sth5 = $dbh->prepare('SELECT COUNT(id)
                              FROM   physaddr
                              WHERE  last_seen=?
                             ');
    $sth5->execute($timestamp);
    my $total_macs = $sth5->fetchrow_array() || 0;

    $res{macs} = $total_macs - ($num_int_macs + $num_dev_macs);

    ##############################################
    # ARP Devices
    my $sth6 = $dbh->prepare('SELECT COUNT(id)
                              FROM   device
                              WHERE  last_arp=?
                             ');
    $sth6->execute($timestamp);
    $res{arp_devices} = $sth6->fetchrow_array() || 0;

    ##############################################
    # FWT Devices
    my $sth7 = $dbh->prepare('SELECT COUNT(id)
                              FROM   device
                              WHERE  last_fwt=?
                             ');
    $sth7->execute($timestamp);
    $res{fwt_devices} = $sth7->fetchrow_array() || 0;
    
    return \%res;

}

############################################################################
#_get_arp_from_snmp - Fetch ARP tables via SNMP
#
#   Performs some validation and abstracts SNMP::Info logic
#    
#   Arguments:
#       session - SNMP session (optional)
#   Returns:
#       Hash ref.
#   Examples:
#       $self->_get_arp_from_snmp();
#
sub _get_arp_from_snmp {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_arp_from_snmp');
    my $host = $self->fqdn;

    my %cache;
    my $sinfo = $argv{session} || $self->_get_snmp_session();

    my %devints; my %devsubnets;
    foreach my $int ( $self->interfaces ){
	$devints{$int->number} = $int->id;
    }
    $logger->debug(sub{"$host: Fetching ARP cache via SNMP" });
    my ( $at_paddr, $at_netaddr, $at_index );
    $at_paddr  = $sinfo->at_paddr();

    # With the following checks we are trying to query only one
    # OID instead of three, which is a significant performance
    # improvement with very large caches.
    # The optional .1 in the middle is for cases where the old
    # atPhysAddress is used.
    my $use_shortcut = 1;
    my @paddr_keys = keys %$at_paddr;
    if ( $paddr_keys[0] && $paddr_keys[0] =~ /^(\d+)(\.1)?\.($IPV4)$/ ){
	my $idx = $1;
	if ( !exists $devints{$idx} ){
	    $use_shortcut = 0;
	    $logger->debug(sub{"Device::_get_arp_from_snmp: $host: Not using ARP query shortcut"});
	    $at_netaddr = $sinfo->at_netaddr();
	    $at_index   = $sinfo->at_index();
	}
    }
    foreach my $key ( @paddr_keys ){
	my ($ip, $idx, $mac);
	$mac = $at_paddr->{$key};
	if ( $use_shortcut ){
	    if ( $key =~ /^(\d+)(\.1)?\.($IPV4)$/ ){
		$idx = $1;
		$ip  = $3;
	    }else{
		$logger->debug(sub{"Device::_get_arp_from_snmp: $host: Unrecognized hash key: $key" });
		next;
	    }
	}else{
	    $idx = $at_index->{$key};
	    $ip  = $at_netaddr->{$key};
	}
	unless ( $ip && $idx && $mac ){
	    $logger->debug(sub{"Device::_get_arp_from_snmp: $host: Missing information at row: $key" });
	    next;
	}
	# Store in hash
	$cache{$idx}{$ip} = $mac;
    }
    return $self->_validate_arp(\%cache, 4);
}

############################################################################
#_get_v6_nd_from_snmp - Fetch IPv6 Neighbor Discovery tables via SNMP
#
#   Abstracts SNMP::Info logic
#    
#   Arguments:
#       session - SNMP session (optional)
#   Returns:
#     Hash ref.
#   Examples:
#     $self->_get_v6_nd_from_snmp();
#
sub _get_v6_nd_from_snmp {
    my ($self, %argv) = @_;
    $self->isa_object_method('_get_v6_nd_from_snmp');
    my $host = $self->fqdn;
    my %cache;
    my $sinfo = $argv{session} || $self->_get_snmp_session();
    unless ( $sinfo->can('ipv6_n2p_mac') ){
	$logger->debug("Device::_get_v6_nd_from_snmp: This version of SNMP::Info ".
		       "does not support fetching Ipv6 addresses");
	return;
    }
    $logger->debug(sub{"$host: Fetching IPv6 ND cache via SNMP" });
    my $n2p_mac   = $sinfo->ipv6_n2p_mac();
    my $n2p_addr  = $sinfo->ipv6_n2p_addr();
    my $n2p_if    = $sinfo->ipv6_n2p_if();

    unless ( ($n2p_mac && $n2p_addr && $n2p_if) && (%$n2p_mac && %$n2p_addr && %$n2p_if) ){
	$logger->debug(sub{"Device::_get_v6_nd_from_snmp: $host: No IPv6 ND information" });
	return;
    }
    while ( my($row,$val) = each %$n2p_mac ){
	my $idx   = $n2p_if->{$row}; 
	my $ip    = $n2p_addr->{$row}; 
	my $mac   = $val;
	unless ( $idx && $ip && $mac ){
	    $logger->debug(sub{"Device::_get_v6_nd_from_snmp: $host: Missing information in row: $row" });
	    next;
	}
	$cache{$idx}{$ip} = $mac;
    }
    return $self->_validate_arp(\%cache, 6);
}

############################################################################
# _validate_arp - Validate contents of ARP and v6 ND structures
#    
#   Arguments:
#       hashref of hashrefs containing ifIndex, IP address and Mac
#       IP version
#   Returns:
#     Hash ref.
#   Examples:
#     $self->_validate_arp(\%cache, 6);
#
#
sub _validate_arp {
    my ($self, $cache, $version) = @_;
    
    $self->throw_fatal("Device::_validate_arp: Missing required arguments")
	unless ($cache && $version);

    my $host = $self->fqdn();
    
    # Get all interfaces and IPs
    my %devints; my %devsubnets;
    foreach my $int ( $self->interfaces ){
	$devints{$int->number} = $int->id;
	if ( Netdot->config->get('IGNORE_IPS_FROM_ARP_NOT_WITHIN_SUBNET') ){
	    foreach my $ip ( $int->ips ){
		next unless ($ip->version == $version);
		push @{$devsubnets{$int->id}}, $ip->parent->_netaddr 
		    if $ip->parent;
	    }
	}
    }

    my %valid;
    foreach my $idx ( keys %$cache ){
	my $intid = $devints{$idx} if exists $devints{$idx};
	unless ( $intid  ){
	    $logger->warn("Device::_validate_arp: $host: Interface $idx not in database. Skipping");
	    next;
	}
	foreach my $ip ( keys %{$cache->{$idx}} ){
	    if ( $version == 6 && Ipblock->is_link_local($ip) &&
		 Netdot->config->get('IGNORE_IPV6_LINK_LOCAL') ){
		next;
	    }
	    my $mac = $cache->{$idx}->{$ip};
	    my $validmac = PhysAddr->validate($mac); 
	    unless ( $validmac ){
		$logger->debug(sub{"Device::_validate_arp: $host: Invalid MAC: $mac" });
		next;
	    }
	    $mac = $validmac;
	    if ( Netdot->config->get('IGNORE_IPS_FROM_ARP_NOT_WITHIN_SUBNET') ){
		if ( !Netdot->config->get('IGNORE_IPV6_LINK_LOCAL') ){
		    # This check does not work with link-local, so if user wants those
		    # just validate them
		    if ( Ipblock->is_link_local($ip) ){
			$valid{$intid}{$ip} = $mac;
			$logger->debug(sub{"Device::_validate_arp: $host: valid: $idx -> $ip -> $mac" });
			next;
		    }
		}
		foreach my $nsub ( @{$devsubnets{$intid}} ){
		    my $nip = NetAddr::IP->new($ip) or
			$self->throw_fatal(sprintf("Device::_validate_arp: Cannot create NetAddr::IP ".
						   "object from %s", $ip));
		    if ( $nip->within($nsub) ){
			$valid{$intid}{$ip} = $mac;
			$logger->debug(sub{"Device::_validate_arp: $host: valid: $idx -> $ip -> $mac" });
			last;
		    }
		}
	    }else{
		$valid{$intid}{$ip} = $mac;
		$logger->debug(sub{"Device::_validate_arp: $host: valid: $idx -> $ip -> $mac" });
	    }
	}
    }
    return \%valid;
}

############################################################################
#_get_fwt_from_snmp - Fetch fowarding tables via SNMP
#
#     Performs some validation and abstracts snmp::info logic
#     Some logic borrowed from netdisco's macksuck()
#    
#   Arguments:
#     session - SNMP Session (optional)
#     vlan    - Only query table for this VLAN (optional)
#   Returns:
#     Hash ref.
#    
#   Examples:
#     $self->get_fwt_from_snmp;
#
#
sub _get_fwt_from_snmp {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_fwt_from_snmp');
    my $class = ref($self);

    my $host = $self->fqdn;

    unless ( $self->collect_fwt ){
	$logger->debug(sub{"Device::_get_fwt_from_snmp: $host excluded from FWT collection. Skipping"});
	return;
    }

    if ( $self->is_in_downtime ){
	$logger->debug(sub{"Device::_get_fwt_from_snmp: $host in downtime. Skipping"});
	return;
    }

    my $start   = time;
    my $sinfo   = $argv{session} || $self->_get_snmp_session();
    my $sints   = $sinfo->interfaces();

    # Build a hash with device's interfaces, indexed by ifIndex
    my %devints;
    foreach my $int ( $self->interfaces ){
	$devints{$int->number} = $int->id;
    }

    # Fetch FWT. 
    # Notice that we pass the result variable as a parameter since that's the
    # easiest way to append more info later using the same function (see below).
    my %fwt; 
    $logger->debug(sub{"$host: Fetching forwarding table via SNMP" });
    $class->_exec_timeout($host, sub{ return $self->_walk_fwt(sinfo   => $sinfo,
							      sints   => $sints,
							      devints => \%devints,
							      fwt     => \%fwt,
					  ); 
			  });
    
    # For certain Cisco switches you have to connect to each
    # VLAN and get the forwarding table out of it.
    # Notably the Catalyst 5k, 6k, and 3500 series
    my $cisco_comm_indexing = $sinfo->cisco_comm_indexing();
    if ( $cisco_comm_indexing ){
        $logger->debug(sub{"$host supports Cisco community string indexing. Connecting to each VLAN" });
	my $sclass = $sinfo->class();

        # Get list of all active VLANS on this device
	my %vlans;
	foreach my $int ( $self->interfaces ){
	    map { $vlans{$_->vlan->vid}++ } $int->vlans;
	}
	my $v_state = $sinfo->v_state();
	foreach my $vid ( keys %vlans ){
	    my $key = '1.'.$vid;
	    delete $vlans{$vid} unless ( exists $v_state->{$key} 
					 && $v_state->{$key} eq 'operational' ); 
	}

        foreach my $vlan ( sort { $a <=> $b } keys %vlans ){
	    next if ( $argv{vlan} && $argv{vlan} ne $vlan );
	    next if ( $vlan == 0 || $vlan == 1 );  # Ignore vlans 0 and 1
	    my $target = (scalar($self->snmp_target))? $self->snmp_target->address : $host;
	    my %args = ('host'        => $target,
			'communities' => [$self->community . '@' . $vlan],
			'version'     => $self->snmp_version,
			'sclass'      => $sclass,
		);
	    
	    my $vlan_sinfo;
	    eval {
		$vlan_sinfo = $class->_get_snmp_session(%args);
	    };
	    if ( my $e = $@ ){ 
                $logger->error("$host: SNMP error for VLAN $vlan: $e");
                next;
            }
            $class->_exec_timeout($host, sub{ return $self->_walk_fwt(sinfo   => $vlan_sinfo,
								      sints   => $sints,
								      devints => \%devints,
								      fwt     => \%fwt);
				  });
        }
    }
	    
    my $end = time;
    my $fwt_count = 0;
    map { $fwt_count+= scalar keys %{ $fwt{$_} } } keys %fwt;
    $logger->debug(sub{ sprintf("$host: FWT fetched. %d entries in %s", 
				$fwt_count, $self->sec2dhms($end-$start) ) });
    
    return \%fwt;
}

#########################################################################
sub _walk_fwt {
    my ($self, %argv) = @_;
    $self->isa_object_method('_walk_fwt');

    my ($sinfo, $sints, $devints, $fwt) = @argv{"sinfo", "sints", "devints",  "fwt"};
    
    my $host = $self->fqdn;
    
    $self->throw_fatal("Model::Device::_walk_fwt: Missing required arguments") 
	unless ( $sinfo && $sints && $devints && $fwt );


    my %tmp;

    # Try BRIDGE mib stuff first, then REPEATER mib
    if ( my $fw_mac = $sinfo->fw_mac() ){
	
	my $fw_port    = $sinfo->fw_port();
	my $bp_index   = $sinfo->bp_index();
	
	# To map the port in the forwarding table to the
	# physical device port we have this triple indirection:
	#      fw_port -> bp_index -> interfaces
	
	foreach my $fw_index ( keys %$fw_mac ){

	    my $mac = $fw_mac->{$fw_index};
	    unless ( defined $mac ) {
		$logger->debug(sub{"Device::_walk_fwt: $host: MAC not defined at index $fw_index.  Skipping" });
		next;
	    }

	    my $bp_id  = $fw_port->{$fw_index};
	    unless ( defined $bp_id ) {
		$logger->debug(sub{"Device::_walk_fwt: $host: Port $fw_index has no fw_port mapping.  Skipping" });
		next;
	    }
	    
	    my $iid = $bp_index->{$bp_id};
	    unless ( defined $iid ) {
		$logger->debug(sub{"Device::_walk_fwt: $host: Interface $bp_id has no bp_index mapping. Skipping" });
		next;
	    }
	    
	    $tmp{$iid}{$mac} = 1;
	}
    
    }elsif ( my $last_src = $sinfo->rptrAddrTrackNewLastSrcAddress() ){
	
	foreach my $iid ( keys %{ $last_src } ){
	    my $mac = $last_src->{$iid};
	    unless ( defined $mac ) {
		$logger->debug(sub{"Device::_walk_fwt: $host: MAC not defined at rptr index $iid. Skipping" });
		next;
	    }
	    
	    $tmp{$iid}{$mac} = 1;
	}
	    
    }
    
    # Clean up here to avoid repeating these checks in each loop above
    foreach my $iid ( keys %tmp ){
	my $descr = $sints->{$iid};
	unless ( defined $descr ) {
	    $logger->debug(sub{"Device::_walk_fwt: $host: SNMP iid $iid has no physical port matching. Skipping" });
	    next;
	}
	
	my $intid = $devints->{$iid} if exists $devints->{$iid};
	unless ( $intid  ){
	    $logger->warn("Device::_walk_fwt: $host: Interface $iid ($descr) is not in database. Skipping");
	    next;
	}
	
	foreach my $mac ( keys %{ $tmp{$iid} } ){
	    next unless $mac;
	    my $validmac = PhysAddr->validate($mac);
	    if ( $validmac ){
		$mac = $validmac;
	    }else{
		$logger->debug(sub{"Device::_walk_fwt: $host: Invalid MAC: $mac" });
		next;
	    }
	    $fwt->{$intid}->{$mac} = 1;
	    $logger->debug(sub{"Device::_walk_fwt: $host: $iid ($descr) -> $mac" });
	}
	
    }

    return 1;
}

#########################################################################
# Run given code within TIMEOUT time
# Uses ALRM signal to tell process to throw an exception
#
# Rationale: 
# An SNMP connection is established but the agent never replies to a query.  
# In those cases, the standard Timeout parameter for the SNMP session 
# does not help.
#
# Arguments: 
#   hostname
#   code reference
# Returns:
#   Array with results
#
sub _exec_timeout {
    my ($class, $host, $code) = @_;
    $class->isa_class_method("_exec_timeout");

    $class->throw_fatal("Model::Device::_exec_timeout: Missing required argument: code") unless $code;
    $class->throw_fatal("Model::Device::_exec_timeout: Invalid code reference") unless ( ref($code) eq 'CODE' );
    my @result;
    eval {
	alarm($TIMEOUT);
	@result = $code->();
	alarm(0);
    };
    if ( my $e = $@ ){
	my $msg;
	if ( $e =~ /timeout/ ){
	    $class->throw_user("Device $host timed out ($TIMEOUT sec)");
	}else{
	    $class->throw_user("$e");
	}
    }
    wantarray ? @result : $result[0];
}

#########################################################################
#  Executes given code as a child process.  Makes sure DBI handle does
#  not disconnect
#
# Arguments:
#   hash with following keys:
#     code   - Code reference to execute
#     pm     - Parallel::ForkManager object
#   
#
sub _launch_child {
    my ($class, %argv) = @_;
    $class->isa_class_method("_launch_child");

    my ($code, $pm) = @argv{"code", "pm"};

    $class->throw_fatal("Model::Device::_launch_child: Missing required arguments")
	unless ( defined $pm && defined $code );

    # Tell DBI that we don't want to disconnect the server's DB handle
    my $dbh = $class->db_Main;
    unless ( $dbh->{InactiveDestroy} = 1 ) {
	$class->throw_fatal("Model::Device::_launch_child: Cannot set InactiveDestroy: ", $dbh->errstr);
    }
    # Run given code
    $code->();
    $dbh->disconnect();
    $pm->finish; # exit the child process
}

#####################################################################
# _get_as_info - Retrieve info about given Autonomous System Number
# 
# Arguments:
#   asn: Autonomous System Number
# Returns:
#   Hash with keys:
#     asname:  Short name for this AS
#     orgname: Short description for this AS

sub _get_as_info{
    my ($self, $asn) = @_;

    return unless $asn;

    if ( $asn >= 64512 && $asn <= 65535 ){
	$logger->debug("Device::_get_as_info: $asn is IANA reserved");
	return;
    }

    # For some reason, use'ing this module at the top of this
    # file causes mod_perl to raise hell.
    # Loading it this way seems to avoid that problem
    eval "use Net::IRR";
    if ( my $e = $@ ){
	$self->throw_fatal("Model::Device::_get_as_info: Error loading module: $e");
    }

    my %results;

    my $server = $self->config->get('WHOIS_SERVER');
    $logger->debug(sub{"Device::_get_as_info: Querying $server"});
    my $i = Net::IRR->connect(host => $server);
    unless ( $i ){
	$logger->error("Device::_get_as_info: Cannot connect to $server");
	return;
    }
    my $obj = $i->match("aut-num","as$asn");
    unless ( $obj ){
	$logger->warn("Device::_get_as_info: Can't find AS $asn in $server");
	return;
    }
    $i->disconnect();

    if ( $obj =~ /as-name:\s+(.*)\n/ ){
	my $as_name = $1;
	$results{asname} = $as_name;
	$logger->debug(sub{"Device::_get_as_info:: $server: Found asname: $as_name"});
    }
    if ( $obj =~ /descr:\s+(.*)\n/ ){
	my $descr = $1;
	$results{orgname} = $descr;
	$logger->debug(sub{"Device::_get_as_info:: $server: Found orgname: $descr"});
    }
    return \%results if %results;
    return;
}

#####################################################################
# _update_macs_from_fwt - Update MAC addresses
# 
# Arguments:
#   hash with following keys:
#     caches    - Arrayref with FWT info
#     timestamp - Time Stamp
#     atomic    - Perform atomic updates
sub _update_macs_from_fwt {
    my ($class, %argv) = @_;
    my ($caches, $timestamp, $atomic) = @argv{'caches', 'timestamp', 'atomic'};

    my %mac_updates;
    foreach my $cache ( @$caches ){
	foreach my $idx ( keys %{$cache} ){
	    foreach my $mac ( keys %{$cache->{$idx}} ){
		$mac_updates{$mac} = 1;
	    }
	}
    }
    if ( $atomic ){
	Netdot::Model->do_transaction( sub{ return PhysAddr->fast_update(\%mac_updates, $timestamp) } );
    }else{
	PhysAddr->fast_update(\%mac_updates, $timestamp);
    }
    return 1;
}


#####################################################################
# _update_macs_from_arp_cache - Update MAC addresses from ARP cache
# 
# Arguments:
#   hash with following keys:
#     caches    - Arrayref with ARP cache
#     timestamp - Time Stamp
#     atomic    - Perform atomic updates
sub _update_macs_from_arp_cache {
    my ($class, %argv) = @_;
    my ($caches, $timestamp, $atomic) = @argv{'caches', 'timestamp', 'atomic'};

    my %mac_updates;
    foreach my $cache ( @$caches ){
	foreach my $version ( keys %{$cache} ){
	    foreach my $idx ( keys %{$cache->{$version}} ){
		foreach my $mac ( values %{$cache->{$version}->{$idx}} ){
		    $mac_updates{$mac} = 1;
		}
	    }
	}
    }
    if ( $atomic ){
	Netdot::Model->do_transaction( sub{ return PhysAddr->fast_update(\%mac_updates, $timestamp) } );
    }else{
	PhysAddr->fast_update(\%mac_updates, $timestamp);
    }
    return 1;
}

#####################################################################
# _update_ips_from_arp_cache - Update IP addresses from ARP cache
#
# Arguments:
#   hash with following keys:
#     caches         - Arrayref of hashrefs with ARP Cache info
#     timestamp      - Time Stamp
#     no_update_tree - Boolean 
#     atomic         - Perform atomic updates
sub _update_ips_from_arp_cache {
    my ($class, %argv) = @_;
    my ($caches, $timestamp, 
	$no_update_tree, $atomic) = @argv{'caches', 'timestamp', 
					  'no_update_tree', 'atomic'};
    
    my %ip_updates;
    
    my $ip_status = (IpblockStatus->search(name=>'Discovered'))[0];
    $class->throw_fatal("Model::Device::_update_ips_from_cache: IpblockStatus 'Discovered' not found?")
	unless $ip_status;
    
    my %build_tree;
    foreach my $cache ( @$caches ){
	foreach my $version ( keys %{$cache} ){
	    $build_tree{$version} = 1;
	    foreach my $idx ( keys %{$cache->{$version}} ){
		foreach my $ip ( keys %{$cache->{$version}{$idx}} ){
		    my $mac = $cache->{$version}->{$idx}->{$ip};
		    my $prefix = ($version == 4)? 32 : 128;
		    $ip_updates{$ip} = {
			prefix     => $prefix,
			version    => $version,
			timestamp  => $timestamp,
			physaddr   => $mac,
			status     => $ip_status,
		    };
		}
	    }
	}
    }
    
    if ( $atomic ){
	Netdot::Model->do_transaction( sub{ return Ipblock->fast_update(\%ip_updates) } );
    }else{
	Ipblock->fast_update(\%ip_updates);
    }
    
    unless ( $no_update_tree ){
	foreach my $version ( keys %build_tree ){
	    Ipblock->build_tree($version);
	}
    }
    
    return 1;
}


#####################################################################
# Convert octet stream values returned from SNMP into an ASCII HEX string
#
sub _oct2hex {
    my ($self, $v) = @_;
    return uc( sprintf('%s', unpack('H*', $v)) );
}

#####################################################################
# Takes an 8-byte octet stream (HEX-STRING) containing priority+MAC
# (from do1dStp MIBs) and returns a ASCII hex string containing the 
# MAC address only (6 bytes).
# 
sub _stp2mac {
    my ($self, $mac) = @_;
    return undef unless $mac;
    $mac = $self->_oct2hex($mac);
    $mac = substr($mac, 4, 12);
    return $mac if length $mac;
    return undef;
}

#####################################################################
# ifHighSpeed is an estimate of the interface's current bandwidth in units
# of 1,000,000 bits per second.  
# We store interface speed as bps (integer format)
#
sub _munge_speed_high {
    my ($self, $v) = @_;
    return $v * 1000000;
}

##############################################################
# Assign Base MAC
#
# Arguments
#   snmp info hashref
# Returns
#   PhysAddr object
#
sub _assign_base_mac {
    my ($self, $info) = @_;
    
    my $host = $self->fqdn;
    if ( $info->{physaddr} && (my $address = PhysAddr->validate($info->{physaddr})) ) {
	# Look it up
	my $mac;
	if ( $mac = PhysAddr->search(address=>$address)->first ){
	    # The address exists
	    # (may have been discovered in fw tables/arp cache)
	    $mac->update({static=>1, last_seen=>$self->timestamp});
	    $logger->debug(sub{"$host: Using existing $address as base bridge address"});
	    return $mac;
	}else{
	    # address is new.  Add it
	    eval {
		$mac = PhysAddr->insert({address=>$address, static=>1});
	    };
	    if ( my $e = $@ ){
		$logger->debug(sprintf("%s: Could not insert base MAC: %s: %s",
				       $host, $address, $e));
	    }else{
		$logger->info(sprintf("%s: Inserted new base MAC: %s", $host, $mac->address));
		return $mac;
	    }
	}
    }else{
	$logger->debug(sub{"$host did not return base MAC"});
	delete $info->{physaddr};
	return;
    }
}

##############################################################
# Assign the snmp_target address if it's not there yet
#
# Arguments
#   snmp info hashref
# Returns
#   Ipblock object
#
sub _assign_snmp_target {
    my ($self, $info) = @_;
    my $host = $self->fqdn;
    if ( $self->snmp_managed && !$self->snmp_target && $info->{snmp_target} ){
	my $ipb = Ipblock->search(address=>$info->{snmp_target})->first;
	unless ( $ipb ){
	    eval {
		$ipb = Ipblock->insert({address=>$info->{snmp_target}, status=>'Static'});
	    };
	    if ( my $e = $@ ){
		$logger->warn("Device::assign_snmp_target: $host: Could not insert snmp_target address: ". 
			      $info->{snmp_target} .": ", $e);
	    }
	}
	if ( $ipb ){
	    $logger->info(sprintf("%s: SNMP target address set to %s", 
				  $host, $ipb->address));
	    return $ipb;
	}
    }
}

##############################################################
# Assign Product
#
# Arguments
#   snmp info hashref
# Returns
#   Product object
#
sub _assign_product {
    my ($self, $info) = @_;

    my %args;
    if ( $info->{sysobjectid} ){
	$args{sysobjectid} = $info->{sysobjectid};
    }else{
	&_unknown;
    }

    my $name = $info->{model} || $info->{productname};
    if ( defined $name ){
	$args{name}        = $name;
	$args{description} = $name;
    }else{
	&_unknown;
    }
    $args{type}          = $info->{type}         if defined $info->{type};
    $args{manufacturer}  = $info->{manufacturer} if defined $info->{manufacturer}; 
    $args{hostname}      = $self->fqdn;
    
    return Product->find_or_create(%args);

    sub _unknown {
	return Product->search(name=>'Unknown')->first || Product->retrieve(3);
    }
}

##############################################################
# Assign monitored flag based on device type
#
# Arguments
#   Product object
# Returns
#   1 or 0
#
sub _assign_device_monitored {
    my ($self, $product) = @_;
    return unless $product;
    if ( my $ptype = $product->type->name ){
	if ( my $default = $self->config->get('DEFAULT_DEV_MONITORED') ){
	    if ( exists $default->{$ptype} ){
		return $default->{$ptype};
	    }
	}
    }
}
    

##############################################################
# Assign monitor_config_group
#
# Arguments
#   snmp info hashref
# Returns
#   String
#
sub _assign_monitor_config_group{
    my ($self, $info) = @_;
    if ( $self->config->get('DEV_MONITOR_CONFIG') && 
	 (!$self->monitor_config_group || $self->monitor_config_group eq "") ){
	my $monitor_config_map = $self->config->get('DEV_MONITOR_CONFIG_GROUP_MAP') || {};
	my $config_group;
	if ( my $type = $info->{type} ){
	    if ( exists $monitor_config_map->{$type} ){
		return $monitor_config_map->{$type};
	    }
	}
    }
}


##############################################################
# Update Spanning Tree information
#
# Arguments
#   snmp info hashref
#   Device object arguments hashref
# Returns
#   Nothing
#
sub _update_stp_info {
    my ($self, $info, $devtmp) = @_;
    my $host = $self->fqdn;

    ##############################################################
    # Global Spanning Tree Info
    $devtmp->{stp_type}    = $info->{stp_type};
    $devtmp->{stp_enabled} = 1 if ( defined $info->{stp_type} && $info->{stp_type} ne 'unknown' );

    
    ##############################################################
    # Assign MST-specific values
    foreach my $field ( qw( stp_mst_region stp_mst_rev stp_mst_digest ) ){
	if ( exists $info->{$field} ){
	    $devtmp->{$field} = $info->{$field};
	    # Notify if these have changed
	    if ( $field eq 'stp_mst_region' || $field eq 'stp_mst_digest' ){
		if ( defined($self->$field) && ($self->$field ne $devtmp->{$field}) ){
		    $logger->warn(sprintf("%s: $field has changed: %s -> %s", 
					  $host, $self->$field, $devtmp->{$field}));
		}
	    }
	}
    }

    ##############################################################
    # Deal with STP instances
    if ( $devtmp->{stp_enabled} ){
	$logger->debug(sub{ sprintf("%s: STP is enabled", $host)});
	$logger->debug(sub{ sprintf("%s: STP type is: %s", $host, $devtmp->{stp_type})});
	
	# Get all current instances, hash by number
	my %old_instances;
	map { $old_instances{$_->number} = $_ } $self->stp_instances();

	# Go over all STP instances
	foreach my $instn ( keys %{$info->{stp_instances}} ){
	    my $stpinst;
	    my %args = (device=>$self->id, number=>$instn);
	    # Create if it does not exist
	    unless ( $stpinst = STPInstance->search(%args)->first ){
		$stpinst = STPInstance->insert(\%args);
		$logger->info("$host: STP Instance $instn created");
	    }
	    # update arguments for this instance
	    my %uargs;
	    if ( my $root_bridge = $info->{stp_instances}->{$instn}->{stp_root} ){
		if ( defined $stpinst->root_bridge && ($root_bridge ne $stpinst->root_bridge) ){
		    $logger->warn(sprintf("%s: STP instance %s: Root Bridge changed: %s -> %s", 
					  $host, $stpinst->number, $stpinst->root_bridge, $root_bridge));
		}
		$uargs{root_bridge} = $root_bridge;
	    }else{
		$logger->debug(sub{ "$host: STP Designated Root not defined for instance $instn"});
	    }
	    
	    if ( my $root_p = $info->{stp_instances}->{$instn}->{stp_root_port} ){
		if ( defined $stpinst->root_port && $stpinst->root_port != 0 &&
		     ( $root_p != $stpinst->root_port) ){
		    # Do not notify if this is the first time it's set
		    $logger->warn(sprintf("%s: STP instance %s: Root Port changed: %s -> %s", 
					  $host, $stpinst->number, $stpinst->root_port, $root_p));
		}
		$uargs{root_port} = $root_p;
	    }else{
		$logger->debug(sub{"$host: STP Root Port not defined for instance $instn"});
	    }
	    # Finally, just get the priority
	    $uargs{bridge_priority} = $info->{stp_instances}->{$instn}->{stp_priority};
	    if ( defined $stpinst->bridge_priority && $stpinst->bridge_priority ne $uargs{bridge_priority} ){
		$logger->warn(sprintf("%s: STP instance %s: Bridge Priority Changed: %s -> %s", 
				      $host, $stpinst->number, $stpinst->bridge_priority, $uargs{bridge_priority}));
	    }
	    
	    # Update the instance
	    $stpinst->update(\%uargs);
	    
	    # Remove this one from the old list
	    delete $old_instances{$instn};
	}
	# Remove any non-existing STP instances
	foreach my $i ( keys %old_instances ){
	    $logger->info("$host: Removing STP instance $i");
	    $old_instances{$i}->delete;
	}
    }else{
	if ( my @instances = $self->stp_instances() ){
	    $logger->debug(sub{"$host: STP appears disabled.  Removing all existing STP instances"});
	    foreach my $i ( @instances ){
		$i->delete();
	    }
	}
    }
}


##############################################
# Add/Update Modules
#
# Arguments
#   snmp info hashref
# Returns
#   Nothing
#
#
sub _update_modules {
    my ($self, $info) = @_;

    my $host = $self->fqdn;

    # Get old modules (if any)
    my %oldmodules;
    map { $oldmodules{$_->number} = $_ } $self->modules();

    foreach my $number ( sort { $a <=> $b } keys %{ $info->{module} } ){
	my %args = %{$info->{module}->{$number}};
	$args{device} = $self->id;
	my $name = $args{name} || $args{description};

	# find or create asset object for given serial number and product
	if ( my $serial = delete $args{serial_number} ){
	    if ( my $asset = Asset->find_or_create({serial_number=>$serial, product_id=>$self->product}) ){
		$args{asset_id} = $asset->id;
	    }
	}
	# See if it exists
	my $module;
	if ( exists $oldmodules{$number} ){
	    $module = $oldmodules{$number};
	    # Update
	    $module->update(\%args);
	}else{
	    # Create new object
	    $logger->info("$host: New module $number ($name) found. Inserting.");
	    $module = DeviceModule->insert(\%args);
	}
	delete $oldmodules{$number};
    }
    # Remove modules that no longer exist
    foreach my $number ( keys %oldmodules ){
	my $module = $oldmodules{$number};
	$logger->info("$host:  Module no longer exists: $number.  Removing.");
	$module->delete();
    }
}

##############################################
# Add/Update Interfaces
#
# Arguments
#   Hahref with following keys:
#      info            - snmp information
#      add_subnets     - Flag.  Whether to add subnets if layer3 and ipforwarding
#      subs_inherit    - Flag.  Whether subnets inherit parent info.
#      overwrite_descr - Flag.  What to set this field to by default.
# Returns
#   PhysAddr
#
sub _update_interfaces {
    my ($self, %argv) = @_;

    my $host = $self->fqdn;

    my $info = $argv{info};

    # Do not update interfaces for these devices
    # (specified in config file)
    my %IGNORED;
    map { $IGNORED{$_}++ } @{ $self->config->get('IGNOREPORTS') };
    if ( defined $info->{sysobjectid} && exists $IGNORED{$info->{sysobjectid}} ){
	$logger->debug(sub{"Device::info_update: $host ports ignored per configuration option (IGNOREPORTS)"});
	return;
    }
    
    # How to deal with new subnets
    # First grab defaults from config file
    my $add_subnets_default  = $self->config->get('ADDSUBNETS');
    my $subs_inherit_default = $self->config->get('SUBNET_INHERIT_DEV_INFO');
    
    # Then check what was passed
    my $add_subnets   = ( defined($info->{type}) && $info->{ipforwarding} && defined($argv{add_subnets}) ) ? 
	$argv{add_subnets} : $add_subnets_default;
    my $subs_inherit = ( $add_subnets && defined($argv{subs_inherit}) ) ? 
	$argv{subs_inherit} : $subs_inherit_default;
    
    # Get old IPs (if any)
    my %old_ips;
    if ( my $devips = $self->get_ips ){
	foreach ( @$devips ){
	    # Use decimal address in the index to avoid ambiguities with notation
	    my $numip = $_->address_numeric;
	    $old_ips{$numip} = $_;
	}
    }
        
    ##############################################
    # Try to solve the problem with devices that change ifIndex
    # We use the name as the most stable key to identify interfaces
    # If names are not unique, use number
    
    # Get old Interfaces (if any).
    my ( %oldifs, %oldifsbynumber, %oldifsbyname );

    # Index by object id. 	
    map { $oldifs{$_->id} = $_ } $self->interfaces();
    
    # Index by interface name (ifDescr) and number (ifIndex)
    foreach my $id ( keys %oldifs ){
	$oldifsbynumber{$oldifs{$id}->number} = $oldifs{$id}
	if ( defined($oldifs{$id}->number) );
	
	$oldifsbyname{$oldifs{$id}->name} = $oldifs{$id}
	if ( defined($oldifs{$id}->name) );
    }
    
    # Index new interfaces by name to check if any names are repeated
    my $ifkey = 'name';
    my %newifsbyname;
    foreach my $int ( keys %{$info->{interface}} ){
	if ( defined $info->{interface}->{$int}->{name} ){
	    my $n = $info->{interface}->{$int}->{name};
	    $newifsbyname{$n}++;
	    if ( $newifsbyname{$n} > 1 ){
		$ifkey = 'number';
	    }
	}
    }
    foreach my $newif ( sort keys %{ $info->{interface} } ) {

	# Remove the new interface's ip addresses from list to delete
	foreach my $newaddr ( keys %{$info->{interface}->{$newif}->{ips}} ){
	    my $numip = Ipblock->ip2int($newaddr);
	    delete $old_ips{$numip} if exists $old_ips{$numip};
	}

	my $newname   = $info->{interface}->{$newif}->{name};
	my $newnumber = $info->{interface}->{$newif}->{number};
	my $oldif;
	if ( $ifkey eq 'name' ){
	    if ( defined $newname && ($oldif = $oldifsbyname{$newname}) ){
		# Found one with the same name
		$logger->debug(sub{ sprintf("%s: Interface with name %s found", 
					    $host, $oldif->name)});
		
		if ( $oldif->number ne $newnumber ){
		    # New and old numbers do not match for this name
		    $logger->info(sprintf("%s: Interface %s had number: %s, now has: %s", 
					  $host, $oldif->name, $oldif->number, $newnumber));
		}
	    }elsif ( exists $oldifsbynumber{$newnumber} ){
		# Name not found, but found one with the same number
		$oldif = $oldifsbynumber{$newnumber};
		$logger->debug(sub{ sprintf("%s: Interface with number %s found", 
					    $host, $oldif->number)});
	    }
	}else{
	    # Using number as unique reference
	    if ( exists $oldifsbynumber{$newnumber} ){
		$oldif = $oldifsbynumber{$newnumber};
		$logger->debug(sub{ sprintf("%s: Interface with number %s found", 
					    $host, $oldif->number)});
	    }
	}	    
	my $if;
	if ( $oldif ){
	    $if = $oldif;
	}else{
	    # Interface does not exist.  Add it.
	    my $ifname = $info->{interface}->{$newif}->{name} || $newnumber;
	    my %args = (device      => $self, 
			number      => $newif, 
			name        => $ifname,
			doc_status  => 'snmp',
			auto_dns    => $self->auto_dns,
		);
	    # Make sure we can write to the description field when
	    # device is a router
	    $args{overwrite_descr} = 1 if $argv{overwrite_descr}; 

	    ############################################
	    # Determine Monitored flag value
	    $args{monitored} = 0; 
	    my $IFM = $self->config->get('IF_MONITORED');
	    if ( defined $IFM ){
		if ( $IFM == 0 ){
		    # do nothing
		}elsif ( $IFM == 1 ){
		    $args{monitored} = 1;
		}elsif ( $IFM == 2 ){
		    if ( scalar keys %{$info->{interface}->{$newif}->{ips}} ){
			$args{monitored} = 1;
		    }
		}elsif ( $IFM == 3 ){
		    if ( defined $info->{interface}->{$newif}->{ips} && 
			 (my $snmp_target = $self->snmp_target) ){
			foreach my $address ( keys %{ $info->{interface}->{$newif}->{ips} } ){
			    if ( $address eq $snmp_target->address ){
				$args{monitored} = 1;
				last;
			    }
			}
		    }
		}else{
		    $logger->warn("Configured IF_MONITORED value: $IFM not recognized");
		}
	    }
	    
	    $if = Interface->insert(\%args);
	    $logger->info(sprintf("%s: New Interface Inserted", $if->get_label));
	    
	}
	
	$self->throw_fatal("Model::Device::info_update: $host: Could not find or create interface: $newnumber")
	    unless $if;
	
	# Now update it with snmp info
	$if->snmp_update(info          => $info->{interface}->{$newif},
			 add_subnets   => $add_subnets,
			 subs_inherit  => $subs_inherit,
			 stp_instances => $info->{stp_instances},
	    );
	
	# Remove this interface from list to delete
	delete $oldifs{$if->id} if exists $oldifs{$if->id};  
	
    } #end foreach my newif
    
    ##############################################
    # Mark each interface that no longer exists
    #
    foreach my $id ( keys %oldifs ) {
	my $iface = $oldifs{$id};
	if ( $iface->doc_status eq "snmp" ){
	    $logger->info(sprintf("%s: Interface %s no longer exists.  Marking as removed.", 
				  $host, $iface->get_label));
	    # Also, remove any cdp/lldp info from that interface to avoid confusion
	    # while discovering topology
	    $iface->update({doc_status=>'removed', 
			    dp_remote_id=>"", dp_remote_ip=>"", 
			    dp_remote_port=>"", dp_remote_type=>""});
	    $iface->remove_neighbor() if $iface->neighbor();
	}
    }
    
    ##############################################
    # remove ip addresses that no longer exist
    while ( my ($address, $obj) = each %old_ips ){
	# Check that it still exists 
	# (could have been deleted if its interface was deleted)
	next unless ( defined $obj );
	next if ( ref($obj) =~ /deleted/i );

	# Don't delete dynamic addresses, just unset the interface
	if ( $obj->status && $obj->status->name eq 'Dynamic' ){
	    $obj->update({interface=>undef});
	    next;
	}

	# If interface is set to "Ignore IP", don't delete existing IP
	if ( $obj->interface && $obj->interface->ignore_ip ){
	    $logger->debug(sub{sprintf("%s: IP %s not deleted: %s set to Ignore IP", 
				       $host, $obj->address, $obj->interface->get_label)});
	    next;
	}

	$logger->info(sprintf("%s: IP %s no longer exists.  Removing.", 
			      $host, $obj->address));
	$obj->delete(no_update_tree=>1);
    }
    
    ##############################################################
    # Update A records for each IP address
    
    if ( $self->config->get('UPDATE_DEVICE_IP_NAMES') && $self->auto_dns ){
	
	# Get addresses that the main Device name resolves to
	my @hostnameips;
	if ( @hostnameips = Netdot->dns->resolve_name($host) ){
	    $logger->debug(sub{ sprintf("Device::info_update: %s resolves to: %s",
					$host, (join ", ", @hostnameips))});
	}
	
	my @my_ips;
	foreach my $ip ( @{ $self->get_ips() } ){
	    if ( $ip->version == 6 && $ip->is_link_local ){
		# Do not create AAAA records for link-local addresses
		next;
	    }else{
		push @my_ips, $ip;
	    }
	}
	my $num_ips = scalar(@my_ips);
	foreach my $ip ( @my_ips ){
	    # We do not want to stop the process if a name update fails
	    eval {
		$ip->update_a_records(hostname_ips=>\@hostnameips, num_ips=>$num_ips);
	    };
	    if ( my $e = $@ ){
		$logger->error(sprintf("Error updating A record for IP %s: %s",
				       $ip->address, $e));
	    }
	}
    }
}

###############################################################
# Add/Update/Delete BGP Peerings
#
# Arguments
#   snmp info hashref
#   Device object arguments hashref
# Returns
#   Nothing
#

sub _update_bgp_info {
    my ($self, $info, $devtmp) = @_;

    my $host = $self->fqdn;

    # Set Local BGP info
    if( defined $info->{bgplocalas} ){
	$logger->debug(sub{ sprintf("%s: BGP Local AS is %s", $host, $info->{bgplocalas}) });
	$devtmp->{bgplocalas} = $info->{bgplocalas};
    }
    if( defined $info->{bgpid} ){
	$logger->debug(sub{ sprintf("%s: BGP ID is %s", $host, $info->{bgpid})});
	$devtmp->{bgpid} = $info->{bgpid};
    }
    
    # Get current BGP peerings
    #
    my %oldpeerings;
    map { $oldpeerings{ $_->id } = $_ } $self->bgppeers();
    
    # Update BGP Peerings
    #
    foreach my $peer ( keys %{$info->{bgppeer}} ){
	$self->update_bgp_peering(peer        => $info->{bgppeer}->{$peer},
				  oldpeerings => \%oldpeerings);
    }
    # remove each BGP Peering that no longer exists
    #
    foreach my $peerid ( keys %oldpeerings ) {
	my $p = $oldpeerings{$peerid};
	$logger->info(sprintf("%s: BGP Peering with %s (%s) no longer exists.  Removing.", 
			      $host, $p->entity->name, $p->bgppeeraddr));
	$p->delete();
    }
}


###############################################################
# Takes an OID and returns the object name if the right MIB is loaded.
# 
# Arguments: SNMP OID string
# Returns: Object name (scalar)
#
sub _snmp_translate {
    my ($self, $oid) = @_;
    my $name = &SNMP::translateObj($oid);
    return $name if defined($name);
}


#####################################################################
# Converts dotted-decimal octets from SNMP into IPv6 address format, 
# i.e:
# 32.1.4.104.13.1.0.196.0.0.0.0.0.0.0.0 =>
# 2001:0468:0d01:00c4:0000:0000:0000:0000
#
sub _octet_string_to_v6 {
    my ($self, $str) = @_;
    return unless $str;
    my $v6_packed = pack("C*", split(/\./, $str));
    my $v6addr = join(':', map { sprintf("%04x", $_) } unpack("n*", $v6_packed) );
    return $v6addr;
}

################################################################
# Subclass if needed
#
# Arguments
#   Hash
# Returns
#   Device subclass object
# Example
#   $self->_netdot_rebless($sinfo);
#
sub _netdot_rebless {
    my ($self, %argv) = @_;
    my $class = ref($self);
    my $host = $self->fqdn;
    
    my ($sclass, $sysobjectid) = @argv{'sclass', 'sysobjectid'};

    if ( $class ne 'Device' && $class ne __PACKAGE__ ){
	# Looks like we were subclassed already
	$logger->debug("Device::_netdot_rebless: $host: Already reblessed as $class");
	return $self;
    }

    my $new_class = __PACKAGE__;

    if ( defined $sclass && $sclass =~ /Airespace/o ){
	$new_class .= '::Airespace';
	$logger->debug("Device::_netdot_rebless: $host: changed class to $new_class"); 
	bless $self, $new_class;
	return $self;
    }

    # In the other cases, we have more flexibility by mapping OIDs to classes in 
    # the config file.

    my $oid = $sysobjectid;
    $oid  ||= $self->product->sysobjectid if $self->product;
    
    unless ( $oid ){
	$logger->debug("Device::_netdot_rebless: $host: sysObjectID not available");
	return;
    }
    my $obj = $self->_snmp_translate($oid);
    unless ( $obj ){
	$logger->debug("Device::_netdot_rebless: $host: Unknown SysObjectID $oid");
	return;
    }
 
    my %OID2CLASSMAP = %{ $self->config->get('FETCH_DEVICE_INFO_VIA_CLI') };
    foreach my $pat ( keys %OID2CLASSMAP ){
	if ( $obj =~ /$pat/ ){
	    my $subclass = $OID2CLASSMAP{$pat};
	    $new_class .= "::CLI::$subclass";
	    $logger->debug("Device::_netdot_rebless: $host: changed class to $new_class"); 
	    bless $self, $new_class;
	    return $self;
	}
    }
}
    
############################################################################
#
# search_by_type - Get a list of Device objects by type
#
#
__PACKAGE__->set_sql(by_type => qq{
    SELECT d.id
	FROM device d, product p, producttype t, rr
	WHERE d.product = p.id AND
	p.type = t.id AND
	rr.id = d.name AND
	t.id = ?
	ORDER BY rr.name
    });

__PACKAGE__->set_sql(no_type => qq{
    SELECT p.name, p.id, COUNT(d.id) AS numdevs
        FROM device d, product p
        WHERE d.product = p.id AND
        p.type IS NULL
        GROUP BY p.name, p.id
        ORDER BY numdevs DESC
    });

__PACKAGE__->set_sql(by_product_os => qq{
    SELECT id,product,os
        FROM device
        WHERE os is NOT NULL 
        AND os != '0'
        ORDER BY product,os
    });

__PACKAGE__->set_sql(for_os_mismatches => qq{
    SELECT device.id,device.product,device.os,device.name
        FROM   device,product
        WHERE  device.product=product.id
        AND device.os IS NOT NULL
        AND product.latest_os IS NOT NULL
        AND device.os!=product.latest_os
        ORDER BY device.product,device.os
    });

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


