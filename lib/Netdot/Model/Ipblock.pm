package Netdot::Model::Ipblock;

use base 'Netdot::Model';
use Netdot::Util::DNS;
use warnings;
use strict;
use NetAddr::IP;
use Net::IPTrie;

=head1 NAME

Netdot::Ipblock - Manipulate IP Address Space

=head1 SYNOPSIS
    
    my $newblock = Ipblock->insert({address=>'192.168.1.0', prefix=>32});
    print $newblock->cidr;
    my $subnet = $newblock->parent;
    print "Address Usage ", $subnet->address_usage;
    
=cut

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

BEGIN{
    # Load plugin at compile time
    my $ip_name_plugin_class = __PACKAGE__->config->get('DEVICE_IP_NAME_PLUGIN');
    eval  "require $ip_name_plugin_class";
    
    sub load_ip_name_plugin{
	$logger->debug("Loading IP_NAME_PLUGIN: $ip_name_plugin_class");
	return $ip_name_plugin_class->new();
    }
}

my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();

my $dns = Netdot::Util::DNS->new();

my $ip_name_plugin = __PACKAGE__->load_ip_name_plugin();

# The binary tree will reside in memory to speed things up 
# when inserting/deleting individual objects
my $tree4;
my $tree6;

=head1 CLASS METHODS
=cut

##################################################################
=head2 search - Search Ipblock objects

    We override the base search method for these reasons:
    - Ipblock objects are stored as decimal integers, so 
      there must be a conversion prior to searching
    - Allow the user to specify a CIDR address

  Arguments:
    Hash with field/value pairs
  Returns:
    Array of Ipblock objects, iterator or undef
  Examples:
    my @objs = Ipblock->search(field => $keyword);

=cut
sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    # Class::DBI::search() might include an extra 'options' hash ref
    # at the end.  In that case, we want to extract the 
    # field/value hash first.
    my $opts = @args % 2 ? pop @args : {}; 
    my %args = @args;

    if ( defined $args{address} ){
	my ($address, $prefix);
	if ( $args{address} =~ /\/\d+$/ ){
	    # Address is in CIDR format
	    ($address, $prefix) = split /\//, $args{address};
	    $args{address} = $class->ip2int($address);
	    $args{prefix}  = $prefix;
	}else{
	    # Ony convert to integer if address is human-readable
	    if ( $args{address} =~ /$IPV4|$IPV6/ ){
		$args{address} = $class->ip2int($args{address});
	    }
	}
    }
    if ( defined $args{status} ){
	my $statusid = $class->_get_status_id($args{status});
	$args{status} = $statusid;
    }
    return $class->SUPER::search( %args, $opts );
}


##################################################################
=head2 search_like - Search IP Blocks that match the specified regular expression

    We override the base method to adapt to the specific nature of Ipblock objects.

    When specifying an address search, a Perl regular expression is expected.
    The regular expression is applied to the CIDR version of the address.
    The result set is limited by the configuration variable 'IPMAXSEARCH'

    If search is performed on other fields, it behaves as base method (See Class::DBI).

 Arguments: 
    hash with key/value pairs
 Returns:   
    array of Ipblock objects sorted by address
  Examples:
    
    my @ips = Ipblock->search_like(address=>'^192.*\/32')

    Returns all /32 addresses starting with 192

=cut

sub search_like {
    my ($class, %argv) = @_;
    $class->isa_class_method('search_like');

    foreach my $key ( keys %argv ){
	if ( $key eq 'address' ){
	    my @ipb;
	    my $it = __PACKAGE__->retrieve_all;
	    while ( my $ipb = $it->next ){
		$_ = $ipb->cidr();
		push @ipb, $ipb if ( /$argv{address}/ );
		if ( scalar(@ipb) > $class->config->get('IPMAXSEARCH') ){
		    last;
		}
	    }
	    @ipb = sort { $a->address_numeric <=> $b->address_numeric } @ipb;
	    return @ipb;
	}else{
	    return $class->SUPER::search_like(%argv);	
	}
    }
}

##################################################################
=head2 keyword_search - Search by keyword
    
    The list of search fields includes Entity, Site, Description and Comments
    The result set is limited by the configuration variable 'IPMAXSEARCH'

 Arguments: 
    string or substring
 Returns: 
    array of Ipblock objects
  Examples:
    Ipblock->keyword_search('Administration');

=cut
sub keyword_search {
    my ($class, $string) = @_;
    $class->isa_class_method('keyword_search');

    # Add wildcards
    my $crit = "%" . $string . "%";

    my @sites    = Site->search_like  (name => $crit );
    my @ents     = Entity->search_like(name => $crit );
    my %blocks;  # Hash to prevent dups
    map { $blocks{$_} = $_ } __PACKAGE__->search_like(description => $crit);
    map { $blocks{$_} = $_ } __PACKAGE__->search_like(info        => $crit);

    # Add the entities related to the sites matching the criteria
    map { push @ents, $_->entity } 
    map { $_->entities } @sites; 
    # Get the Ipblocks related to those entities
    map { $blocks{$_} = $_ } 
    map { $_->used_blocks, $_->owned_blocks } @ents;
    my @ipb;
    foreach ( keys %blocks ){
	push @ipb, $blocks{$_};
	last if (scalar (@ipb) > $class->config->get('IPMAXSEARCH'));
    }

    @ipb = sort { $a->address_numeric <=> $b->address_numeric } @ipb;
    wantarray ? ( @ipb ) : $ipb[0]; 
}


##################################################################
=head2 get_subnet_addr - Get subnet address for a given address


  Arguments:
    address  ipv4 or ipv6 address
    prefix   dotted-quad netmask or prefix length

  Returns: 
    In scalar context, returns subnet address
    In list context, returns subnet address and prefix length

  Examples:
    my ($subnet,$prefix) = Ipblock->get_subnet_addr( address => $addr
						     prefix  => $prefix );

=cut

sub get_subnet_addr {
    my ($class, %args) = @_;
    $class->isa_class_method('get_subnet_addr');
    
    my $ip;
    unless($ip = NetAddr::IP->new($args{address}, $args{prefix})){
	$class->throw_fatal("Invalid IP: $args{address}/$args{prefix}");
    }
    
    return wantarray ? ($ip->network->addr, $ip->masklen) : $ip->network->addr;
}

##################################################################
=head2 get_host_addrs - Get host addresses for a given block

  Note: This returns the list of possible host addresses in any 
    given IP block, not from the database.

  Arguments:
    Subnet address in CIDR notation
  Returns: 
    Arrayref of host addresses (strings)
  Examples:
    my $hosts = Ipblock->get_host_addrs( $address );

=cut
sub get_host_addrs {
    my ($class, $subnet) = @_;
    $class->isa_class_method('get_host_addrs');

    my $s;
    unless( $s = NetAddr::IP->new($subnet) ){
	$class->throw_fatal("Invalid Subnet: $subnet");
    }
    my $hosts = $s->hostenumref();

    # Remove the prefix.  We just want the addresses
    map { $_ =~ s/(.*)\/\d{2}/$1/ } @$hosts;

    return $hosts;
}

##################################################################
=head2 is_loopback - Check if address is a loopback address

  Arguments:
    address - dotted quad ip address.  Required.
    prefix  - dotted quad or prefix length. Optional. NetAddr::IP will assume it is a host (/32 or /128)

  Returns:
    NetAddr::IP object or 0 if failure
  Example:
    my $flag = Ipblock->is_loopback('127.0.0.1');

=cut
sub is_loopback{
    my ( $class, $address, $prefix ) = @_;
    $class->isa_class_method('is_loopback');

    $class->throw_fatal("Missing required arguments: address")
	unless $address;

    my $ip;
    my $str;
    if ( !($ip = NetAddr::IP->new($address, $prefix)) ||
	 $ip->numeric == 0 ){
	$str = ( $address && $prefix ) ? (join '/', $address, $prefix) : $address;
	$class->throw_user("Invalid IP: $str");
    }

    if ( $ip->within(new NetAddr::IP "127.0.0.0", "255.0.0.0") 
	 || $ip eq '::1' ) {
	return 1;	
    }
    return;
}


##################################################################
=head2 insert - Insert a new block

  Modified Arguments:
    status          - name of, id or IpblockStatus object (default: Container)
    no_update_tree  - Do not update IP tree
  Returns: 
    New Ipblock object or 0
  Examples:
    Ipblock->insert(\%data);
    

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    
    $class->throw_fatal("Missing required arguments: address")
	unless ( exists $argv->{address} );

    $argv->{prefix}        ||= undef;
    $argv->{status}        ||= "Container";
    $argv->{interface}     ||= 0; 
    $argv->{dhcp_enabled}  ||= 0; 
    $argv->{owner}         ||= 0; 
    $argv->{used_by}       ||= 0; 
    $argv->{parent}        ||= 0; 
    
    # $ip is a NetAddr::IP object;
    my $ip;
    $ip = $class->_prevalidate($argv->{address}, $argv->{prefix});
    $argv->{address} = $ip->addr;
    $argv->{prefix}  = $ip->masklen;
    $argv->{version} = $ip->version;
    
    my $statusid     = $class->_get_status_id($argv->{status});
    $argv->{status}  = $statusid;

    $argv->{first_seen} = $class->timestamp,
    $argv->{last_seen}  = $class->timestamp,

    my $no_update_tree = $argv->{no_update_tree};
    delete $argv->{no_update_tree};

    my $newblock = $class->SUPER::insert($argv);
    
    # Update tree unless we're told not to do so for speed reasons
    # (usually because it will be rebuilt at the end of a device update)
    $newblock->_update_tree() unless $no_update_tree;
    
    #####################################################################
    # Now check for rules
    # We do it after inserting because having the object and the tree
    # makes things much simpler.  Workarounds welcome.
    # Notice that we might be told to skip validation
    #####################################################################
    
    unless ( exists $argv->{validate} && $argv->{validate} == 0 ){
	# We need to delete the object before bailing out
	eval { 
	    $newblock->_validate($argv);
	};
	if ( my $e = $@ ){
	    $newblock->delete();
	    $e->rethrow() if ref($e);
	}
    }
    
    # Inherit some of parent's values if it's not an address
    if ( !$newblock->is_address && (int($newblock->parent) != 0) ){
	$newblock->update({owner=>$newblock->parent->owner});
    }
    
    # This is a funny hack to avoid the address being shown in numeric.
    my $id = $newblock->id;
    undef $newblock;
    $newblock = __PACKAGE__->retrieve($id);
    return $newblock;
}

##################################################################
=head2 get_covering_block - Get the closest available block that contains a given block

    When a block is searched and not found, it is useful in some cases to show 
    the closest existing block that would contain it.

 Arguments: 
    IP address and (optional) prefix length
 Returns:   
    Ipblock object or 0 if not found
  Examples:
    my $ip = Ipblock->get_covering_block(address=>$address, prefix=>$prefix);

=cut

sub get_covering_block {
    my ($class, %args) = @_;
    $class->isa_class_method('get_covering_block');
    
    $class->throw_fatal('Ipblock::get_covering_block: Missing required arguments: address')
	unless ( $args{address} );

    my $ip = $class->_prevalidate($args{address}, $args{prefix});

    # Make sure this block does not exist
    if ( $class->search(address=>$ip->addr, prefix=>$ip->masklen) ){
	$class->throw_user(sprintf("Block %s/%s exists in db.  Using wrong method!", 
				   $ip->addr, $ip->masklen));
    }
    
    # Search for this IP in the tree.  We should get the parent node
    my $n = $class->_tree_find(version => $ip->version, 
			       address => $ip->numeric, 
			       prefix  => $ip->masklen);

    if ( $n && $n->data ){
	return Ipblock->retrieve($n->data);
    }
}


##################################################################
=head2 get_roots - Get a list of root blocks

 Arguments:   
    IP version [4|6|all]
 Returns:     
    Array of Ipblock objects, ordered by prefix length
  Examples:
    @list = Ipblock->get_roots($rootversion);

=cut
sub get_roots {
    my ($class, $version) = @_;
    $class->isa_class_method('get_roots');

    $version ||= 4;

    my @ipb;
    if ( $version =~ /^4|6$/ ){
	@ipb = __PACKAGE__->search(version => $version, parent => 0, {order_by => 'address'});
    }elsif ( $version eq "all" ){
	@ipb = __PACKAGE__->search(parent => 0, {order_by => 'address'});
    }else{
	$class->throw_fatal("Unknown version: $version");
    }
    wantarray ? ( @ipb ) : $ipb[0]; 

}

##################################################################
=head2 numhosts - Number of hosts (/32s) in a subnet. 

    Including network and broadcast addresses

  Arguments:
    x: the mask length (i.e. 24)
  Returns:
    a power of 2       

=cut

sub numhosts {
    ## include the network and broadcast address in this count.
    ## will return a power of 2.
    my ($class, $x) = @_;
    $class->isa_class_method('numhosts');
    return 2**(32-$x);
}

##################################################################
=head2 numhosts_v6

IPv6 version of numhosts

=cut

sub numhosts_v6 {
    use bigint;
    my ($class, $x) = @_;
    $class->isa_class_method('numhosts');
    return 2**(128-$x);
}

##################################################################
=head2 shorten - Hide the unimportant octets from an ip address, based on the subnet

  Arguments:
    Hash with following keys
    ipaddr   a string with the ip address (i.e. 192.0.0.34)
    mask     the network mask (i.e. 16)

 Returns:
    String with just the host parts of the ip address (i.e. 0.34)

  Note: No support for IPv6 yet.

=cut
sub shorten {
    my ($class, %args) = @_;
    $class->isa_class_method('shorten');

    my ($ipaddr, $mask) = ($args{ipaddr}, $args{mask});

    # this code hides the insignificant (unchanging) octets from the ip address based on the subnet
    if( $mask <= 7 ) {
        # no insignificant octets (128.223.112.0)
        $ipaddr = $ipaddr;
    } elsif( $mask <= 15 ) {
        # first octet is insignificant (a.223.112.0)
        $ipaddr = substr($ipaddr, index($ipaddr,".")+1);
    } elsif( $mask <= 23 ) {
        # second octet is insignificant (a.a.112.0)
        $ipaddr = substr($ipaddr, index($ipaddr,".",index($ipaddr,".")+1)+1);
    } else {
        # mask is 24 or bigger, show the entire ip address (would be a.a.a.0, show 128.223.112.0)
        $ipaddr = $ipaddr;
    }

    return $ipaddr;
}

##################################################################
=head2 subnetmask - Mask length of a subnet that can hold $x hosts

  Arguments:
    An integer power of 2
  Returns:
    integer, 0-32
  Examples:
    my $mask = Ipblock->subnetmask(256)    
=cut
sub subnetmask {
    ## expects as a parameter an integer power of 2
    my ($class, $x) = @_;
    $class->isa_class_method('subnetmask');

    return 32 - (log($x)/log(2));
}

##################################################################
=head2 subnetmask_v6 - IPv6 version of subnetmask

=cut
sub subnetmask_v6 {
    my ($class, $x) = @_;
    $class->isa_class_method('subnetmask_v6');

    return 128 - (log($x)/log(2));
}

##################################################################
=head2 build_tree -  Saves IPv4 or IPv6 hierarchy in the DB

  Arguments: 
    IP version [4|6]
  Returns:
    True if successful
  Examples:
    Ipblock->build_tree('4');

=cut
sub build_tree {
    my ($class, $version) = @_;
    $class->isa_class_method('build_tree');

    my $parents = $class->_build_tree_mem($version);

    # Reflect changes in db
    my $dbh = $class->db_Main;
    my $sth;
    eval {
	$sth = $dbh->prepare_cached("UPDATE ipblock SET parent = ? WHERE id = ?");
	foreach ( keys %$parents ){
	    $sth->execute($parents->{$_}, $_);
	}
    };
    if ( my $e = $@ ){
	$class->throw_fatal( $e );
    }
    
    return 1;
}

############################################################################
=head2 retrieve_all_hashref

    Retrieves all IPs from the DB and stores them in a hash, keyed by 
    numeric address. The value is the Ipblock id.

  Arguments: 
    None
  Returns:   
    Hash reference 
  Examples:
    my $db_ips = Ipblock->retriev_all_hash();

=cut
sub retrieve_all_hashref {
    my ($class) = @_;
    $class->isa_class_method('retrieve_all_hashref');

    # Build the search-all-ips SQL
    $logger->debug("Ipblock::retrieve_all_hashref: Retrieving all IPs...");
    my ($ip_aref, %db_ips, $sth);
    
    my $dbh = $class->db_Main;
    eval {
	$sth = $dbh->prepare_cached("SELECT id,address FROM ipblock");	
	$sth->execute();
	$ip_aref = $sth->fetchall_arrayref;
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    # Build a hash of ip addresses.
    foreach my $row ( @$ip_aref ){
	my ($id, $address) = @$row;
	$db_ips{$address} = $id;
    }
    $logger->debug("Ipblock::retrieve_all_hashref: ...done");

    return \%db_ips;
}

##################################################################
=head2 fast_update - Faster updates for specific cases

    This method will traverse a list of hashes containing an IP address
    and other Ipblock values.  If a record does not exist with that address,
    it is created and both timestamps ('first_seen' and 'last_seen') are 
    instantiated, together with other fields.
    If the address already exists, only the 'last_seen' timestamp is
    updated.

    Meant to be used by processes that insert/update large amounts of 
    objects.  We use direct SQL commands for improved speed.

  Arguments: 
    Hash ref keyed by ip address containing a hash with following keys:
    timestamp
    prefix
    version
    status 
  Returns:   
    True if successul
  Examples:
    Ipblock->fast_update(\%ips);

=cut
sub fast_update{
    my ($class, $ips) = @_;
    $class->isa_class_method('fast_update');

    my $start = time;
    $logger->debug("Ipblock::fast_update: Updating IP addresses in DB");
    my $dbh = $class->db_Main;

    if ( $class->config->get('DB_TYPE') eq 'mysql' ){
	# Take advantage of MySQL's "ON DUPLICATE KEY UPDATE" 
	my $sth;
	eval {
	    $sth = $dbh->prepare_cached("INSERT INTO ipblock
                                         (address,prefix,version,status,first_seen,last_seen,
                                         dhcp_enabled,interface,natted_to,owner,parent,used_by,vlan)
                                         VALUES (?, ?, ?, ?, ?, ?,'0','0','0','0','0','0','0')
                                         ON DUPLICATE KEY UPDATE last_seen=VALUES(last_seen);");
	};
	if ( my $e = $@ ){
	    $class->throw_fatal($e);
	}
	foreach my $address ( keys %$ips ){
	    my $attrs = $ips->{$address};
	    # Convert address to decimal format
	    my $dec_addr = $class->ip2int($address);
	    eval{
		$sth->execute($dec_addr, $attrs->{prefix}, $attrs->{version},
			      $attrs->{status}, $attrs->{timestamp}, $attrs->{timestamp});
	    };
	    if ( my $e = $@ ){
		if ( $e =~ /Duplicate/ ){
		    # Since we're parallelizing, an address
		    # might get inserted after we get our list.
		    # Just go on.
		    next;
		}else{
		    $class->throw_fatal($e);
		}
	    }
	    
	}
    }else{
	my $db_ips  = $class->retrieve_all_hashref;

	# Build SQL queries
	my ($sth1, $sth2);
	eval {
	    $sth1 = $dbh->prepare_cached("UPDATE ipblock SET last_seen=?
                                          WHERE id=?");	
	    
	    $sth2 = $dbh->prepare_cached("INSERT INTO ipblock 
                                          (address,prefix,version,status,first_seen,last_seen,
                                           dhcp_enabled,interface,natted_to,owner,parent,used_by,vlan)
                                           VALUES (?, ?, ?, ?, ?, ?,'0','0','0','0','0','0','0')");
	
	    
	};
	if ( my $e = $@ ){
	    $class->throw_fatal($e);
	}
	
	# Now walk our list and do the right thing
	foreach my $address ( keys %$ips ){
	    my $attrs = $ips->{$address};
	    # Convert address to decimal format
	    my $dec_addr = $class->ip2int($address);
	    
	    if ( exists $db_ips->{$dec_addr} ){
		# IP exists
		eval{
		    $sth1->execute($attrs->{timestamp}, $db_ips->{$dec_addr});
		};
		if ( my $e = $@ ){
		    $class->throw_fatal($e);
		}
	    }else{
		# IP does not exist
		eval{
		    $sth2->execute($dec_addr, $attrs->{prefix}, $attrs->{version},
				   $attrs->{status}, $attrs->{timestamp}, $attrs->{timestamp},
			);
		};
		if ( my $e = $@ ){
		    if ( $e =~ /Duplicate/ ){
			# Since we're parallelizing, an address
			# might get inserted after we get our list.
			# Just go on.
			next;
		    }else{
			$class->throw_fatal($e);
		    }
		}
	    }
	}
    }

    my $end = time;
    $logger->debug(sprintf("Ipblock::fast_update: Done Updating: %d addresses in %d secs",
			   scalar(keys %$ips), ($end-$start)));
    return 1;
}


=head1 INSTANCE METHODS
=cut

##################################################################
=head2 address_numeric - Return IP address in decimal

    Addresses are stored in decimal format in the DB, and converted
    automatically to and from their string representations by triggers.
    Sometimes, it is desirable to work with the decimal format of the
    address.  We need to talk directly to the DB to override the triggers.

  Arguments:
    None
  Returns:
    decimal integer
  Examples:
    my $number = $ipblock->address_numeric();

=cut
sub address_numeric {
    my $self = shift;
    $self->isa_object_method('address_numeric');
    my $dbh = $self->db_Main();
    my $id = $self->id;
    use bigint;
    my $address;
    eval {
	($address) = $dbh->selectrow_array("SELECT address 
                                            FROM ipblock 
                                            WHERE id = $id");
    };
    if ( my $e = $@ ){
	$self->throw_user( $e ) if ( $e );
    }
    return $address;
}

##################################################################
=head2 cidr - Return CIDR version of the address

    Returns the address in CIDR notation:
           
               192.168.0.1/32

  Arguments:
    None
  Returns:
    string
  Examples:
    print $ipblock->cidr();

=cut
sub cidr {
    my $self = shift;
    $self->isa_object_method('cidr');
    return $self->address . '/' . $self->prefix;
}

##################################################################
=head2 get_label - Override get_label method

    Returns the address in CIDR notation if it is a net address:
           
               192.168.0.0/24

    or a plain dotted-quad if it is a host address:
           
               192.168.0.1

  Arguments:
    None
  Returns:
    string
  Examples:
    print $ipblock->get_label();

=cut
sub get_label {
    my $self = shift;
    return $self->address if $self->is_address;
    return $self->cidr;
}

##################################################################
=head2 is_address - Is this a host address?  

    Hos addresses are v4 blocks with a /32 prefix or v6 blocks with a /128 prefix

 Arguments: 
    None
 Returns:   
    1 if block is an address, 0 otherwise

=cut

sub is_address {
    my $self = shift;
    $self->isa_object_method('is_address');

    if ( ($self->version == 4 && $self->prefix < 32) 
	 || ($self->version == 6 && $self->prefix < 128) ){
	return 0; 
    }else{
	return 1;
    }
}

##################################################################
=head2 update - Update an Ipblock object in DB

    Modify given fields of an Ipblock and (optionally) all its descendants.

    If recursive flag is on, passed fields must not:
       - be subject to validation, 
       - require that the address space tree be rebuilt 
       - be specific to one block

  Arguments:
    hashref of key/value pairs
  Modified:
    status           object, id or name of IpblockStatus
    validate(flag)   Optionally skip validation step
    recursive(flag)  Update all descendants
  Returns: 
    When recursive, true if successsful. Otherwise, see Class::DBI update()
  Examples:
    $ipblock->update({field1=>value1, field2=>value2, recursive=>1});

=cut
sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');
    my $class = ref($self);

    # Extract non-column options from $argv
    my $validate  = 1;
    my $recursive = 0;
    if ( defined $argv->{validate} ){
	$validate = $argv->{validate};
	delete $argv->{validate};
    }
    if ( defined $argv->{recursive} ){
	$recursive = $argv->{recursive};
	delete $argv->{recursive};
    }

    if ( $recursive ){
	my %data = %{ $argv };
        map { 
	    if ( /^address|prefix|version|interface|status$/ ){
		$self->throw_fatal("$_ is not a valid field for a recursive update");
	    }
	} keys %data;
	
	$self->SUPER::update(\%data);
	$_->update( $argv ) foreach $self->children;
	return 1;
    }

    # We need at least these args before proceeding
    # If not passed, use current values
    $argv->{status}  ||= $self->status;
    $argv->{prefix}  ||= $self->prefix;

    if ( $argv->{address} ){
	my $ip = $class->_prevalidate($argv->{address}, $argv->{prefix});
	if ( my $tmp = $class->search(address => $ip->addr,
				      prefix  => $ip->masklen)->first ){
	    $self->throw_user("Block ".$argv->{address}."/".$argv->{prefix}." already exists in db")
		if ( $tmp->id != $self->id );
	}
    }

    my $statusid = $self->_get_status_id($argv->{status});
    my %state;
    foreach my $key ( keys %$argv ){
	if ( $key eq 'status' ){
	    $state{status} = $statusid;
	}else {
	    $state{$key} = $argv->{$key};
	}
    }
    $state{last_seen} = $self->timestamp;

    # We might need to discard changes.
    # Class::DBI's 'discard_changes' method won't work
    # here because object is changed in the DB
    # (and not in memory) when IP tree is rebuilt.
    #
    # Notice that this would be the perfect place to use DB transactions
    # but the way we do transactions, they cannot be nested, and this
    # method is pretty low level

    my %bak    = $self->get_state();
    my $result = $self->SUPER::update( \%state );

    # This makes sure we have the latest values
    $self = $class->retrieve($self->id);

    # Only rebuild the tree if address/prefix have changed
    if ( $self->address ne $bak{address} || $self->prefix ne $bak{prefix} ){
	$self->_update_tree();
    }

    # Now check for rules
    # We do it after updating and rebuilding the tree because 
    # it makes things much simpler. Workarounds welcome.
    if ( $validate ){
	# If this fails, We need to roll back the object before bailing out
	eval { 
	    $self->_validate($argv) ;
	};
	if ( my $e = $@ ){
	    # Go back to where we were
	    $self->SUPER::update( \%bak );
	    $e->rethrow();
	}
    }
    return $result;
}



##################################################################
=head2 delete - Delete Ipblock object

    We override delete to allow deleting children recursively as an option.
    
  Arguments: 
    recursive      - Remove blocks recursively (default is false)
    stack          - stack level (for recursiveness control)
    no_update_tree - Do not update IP tree
   Returns:
    True if successful
  Examples:
    $ipblock->delete(recursive=>1);

=cut
sub delete {
    my ($self, %args) = @_;
    $self->isa_object_method('delete');
    my $class = ref($self);
    my $stack = $args{stack} || 0;
     
    if ( $args{recursive} ){
	foreach my $ch ( $self->children ){
           $ch->delete(recursive=>1, stack=>$stack+1);
	}
	my $version = $self->version;
	$self->SUPER::delete();
	# We check if this is the first call in the stack
	# to avoid rebuilding the tree unnecessarily for
	# each child
	unless ( $args{no_update_tree} ){
	    $class->build_tree($version) if ( $stack == 0 );
	}
    }else{
	unless ( $args{no_update_tree} ){
	    $self->_delete_from_tree();
	}
	$self->SUPER::delete();
    }    
    return 1;
}
##################################################################
=head2 get_ancestors - Get parents recursively
    
 Arguments: 
    None
 Returns:   
    Array of ancestor Ipblock objects, in order
  Examples:
    my @ancestors = $ip->get_ancestors();

=cut
sub get_ancestors {
    my ($self, $parents) = @_;
    $self->isa_object_method('get_ancestors');

    if ( int($self->parent) != 0 ){
	push @$parents, $self->parent;
	$self->parent->get_ancestors($parents);
	wantarray ? ( @$parents ) : $parents->[0]; 
    }else{
	return;
    }
}

##################################################################
=head2 num_addr - Return the number of usable addresses in a subnet

 Arguments:
    None
 Returns:
    Integer
  Examples:

=cut

sub num_addr {
    my ($self) = @_;
    $self->isa_object_method('num_addr');
    my $class = ref($self);
    
    if ( $self->version == 4 ) {
        return $class->numhosts($self->prefix) - 2;
    }elsif ( $self->version == 6 ) {
        return $class->numhosts_v6($self->prefix) - 2;
    }
}

##################################################################
=head2 address_usage -  Returns the number of hosts in a given container.

  Arguments:
    None
  Returns:
    integer
  Examples:


=cut

sub address_usage {
    use bigint;
    my ($self) = @_;
    $self->isa_object_method('address_usage');

    my $start  = $self->_netaddr->network();
    my $end    = $self->_netaddr->broadcast();
    my $count  = 0;
    my $q;
    my $dbh = $self->db_Main;
    eval {
	$q = $dbh->prepare_cached("SELECT id, address, prefix, version 
                                       FROM ipblock 
                                       WHERE ? <= address AND address <= ?");
	
	$q->execute(scalar($start->numeric), scalar($end->numeric));
    };
    if ( my $e = $@ ){
	$self->throw_fatal( $e );
    }
    
    while ( my ($id, $address, $prefix, $version) = $q->fetchrow_array() ) {
        if( ( $version == 4 && $prefix == 32 ) || ( $version == 6 && $prefix == 128 ) ) {
            $count++;
        }
    }

    return $count;
}

##################################################################
=head2 subnet_usage - Number of hosts covered by subnets in a container

  Arguments:
    None
  Returns:
    integer
  Examples:

=cut

sub subnet_usage {
    my $self = shift;
    $self->isa_object_method('subnet_usage');
    my $class = ref($self);

    $self->throw_user("Call subnet_usage only for Container blocks")
	if ($self->status->name ne 'Container');

    my $start = $self->_netaddr->network();
    my $end   = $self->_netaddr->broadcast();

    use bigint;
    my $count = new Math::BigInt(0);
    my $dbh   = $self->db_Main;
    my $q;
    eval {
	$q = $dbh->prepare_cached("SELECT ipblock.id, ipblock.address, ipblock.version, 
                                          ipblock.prefix, ipblockstatus.name AS status
		  	           FROM ipblock, ipblockstatus
				   WHERE ipblock.status=ipblockstatus.id
				   AND ? <= address AND address <= ?");
	$q->execute(scalar($start->numeric), scalar($end->numeric));
    };
    if ( my $e = $@ ){
	$self->throw_fatal( $e );
    }
    while ( my ($id, $address, $version, $prefix, $status) = $q->fetchrow_array() ) {
	# must not be a host, and must be "reserved" or "subnet" to count towards usage
        if( !(( $version == 4 && $prefix == 32 ) || ( $version == 6 && $prefix == 128 )) 
	    && ($status eq 'Reserved' || $status eq 'Subnet') ) {
            if ( $version == 4 ) {
                $count += $class->numhosts($prefix);
            } elsif ( $version == 6 ) {
                $count += $class->numhosts_v6($prefix);
            }
        }
    }
    return $count;
}

############################################################################
=head2 update_a_records -  Update DNS A record(s) for this ip 

    Creates or updates DNS records based on the output of configured plugin,
    which can, for example, derive the names based on device/interface information.
    
  Arguments:
    arrayref of ip addresses to which main hostname resolves
  Returns:
    True if successful
  Example:
    $self->update_a_records(\@addrs);

=cut
sub update_a_records {
    my ($self, $addrs) = @_;
    $self->isa_object_method('update_a_records');
    
    $self->throw_fatal("Ipblock::update_a_records: Missing required arguments")
	unless $addrs;

    my %hostnameips;
    map { $hostnameips{$_}++ } @$addrs;

    unless ( $self->interface && $self->interface->device ){
	# No reason to go further
	$self->throw_fatal(sprintf('update_a_records: Address %s not associated with any Device'), 
			   $self->address);
    } 
    my $device = $self->interface->device;
    
    # This shouldn't happen
    $self->throw_fatal( sprintf("update_a_records: Device id %d is missing its name!", $device->id) )
	unless $device->name;

    my $zone   = $device->name->zone;
    my $host   = $device->fqdn;

    # Determine what DNS name this IP will have.
    # We delegate this logic to an external plugin to
    # give admin more flexibility
    my $name = $ip_name_plugin->get_name( $self );

    my @arecords = $self->arecords;

    my %rrstate = (name=>$name, zone=>$zone);

    if ( ! @arecords  ){
	# No A records exist for this IP yet.

	# Is this the only ip in this device,
	# or is this the address associated with the hostname?
	if ( exists $hostnameips{$self->address} ){

	    # We should already have an RR created (via Device::assign_name)
	    # Create the A record to link that RR with this Ipobject
	    RRADDR->insert( {rr => $device->name, ipblock => $self} );
	    $logger->info(sprintf("%s: Inserted DNS A record for main device IP %s: %s", 
				  $host, $self->address, $device->name->name));
	}else{
	    # This ip is not associated with the Device name.
	    # Insert and/or assign necessary records
	    my $rr;
	    if ( $rr = RR->search(%rrstate)->first ){
		$logger->debug( sprintf("Ipblock::update_a_records: %s: Name %s: %s already exists.", 
					$host, $self->address, $name) );
	    }else{
		# Create name first
		$rr = RR->insert(\%rrstate);
	    }
	    # And now A record
	    RRADDR->insert({rr => $rr, ipblock => $self});
	    $logger->info( sprintf("%s: Inserted DNS A record for %s: %s", 
				   $host, $self->address, $name) );
	}
    }else{ 
	# "A" records exist.  Update names
	if ( (scalar @arecords) > 1 ){
	    # There's more than one A record for this IP
	    # To avoid confusion, don't update and log.
	    $logger->warn(sprintf("%s: IP %s has more than one A record. Will not update name.", 
				  $host, $self->address));
	}else{
	    my $ar = $arecords[0];
	    my $rr = $ar->rr;
	    # User might not want this updated
	    if ( $rr->auto_update ){
		# We won't update the RR for the IP that the 
		# device name points to
		if ( !exists $hostnameips{$self->address} ){
		    # Check if the name already exists
		    my $other;
		    if ( $other = RR->search(%rrstate)->first ){
			if ( $other->id != $rr->id ){
			    # This means we need to assign the other
			    # name to this IP, not update the current name
			    $ar->update({rr=>$other});
			    $logger->debug(sprintf("%s: Assigned existing name %s to %s", 
						   $host, $name, $self->address));
			    
			    # And get rid of the old name
			    $rr->delete() unless $rr->arecords;
			}
		    }else{
			# The desired name does not exist
			# Now, is pointing to the main name?
			if ( $rr->id == $device->name->id ) {
			    # In that case we have to create a different name
			    my $newrr = RR->insert(\%rrstate);
		    
			    # And link it with this IP
			    $ar->update({rr=>$newrr});
			    $logger->info( sprintf("%s: Updated DNS record for %s: %s", 
						   $host, $self->address, $name) );
			}else{
			    # Just update the current name, then
			    $rr->update(\%rrstate);
			    $logger->debug(sprintf("%s: Updated DNS record for %s: %s", 
						  $host, $self->address, $name));
			}
		    }
		}
	    }
	}
    }

    return 1;
}

#################################################################
=head2 ip2int - Convert IP(v4/v6) address string into its decimal value

 Arguments: 
    address string
 Returns:   
    integer (decimal value of IP address)
  Examples:
    my $integer_addr = Ipblock->ip2int('192.168.0.1');

=cut
sub ip2int {
    my ($self, $address) = @_;
    my $ipobj;
    unless ( $ipobj = NetAddr::IP->new($address) ){
	$self->throw_user("Invalid IP address: $address");
    }
    return ($ipobj->numeric)[0];
}


#################################################################
=head2 validate - Basic validation of IP address

 Arguments: 
    address
    prefix (optional)
 Returns:   
    True or False
  Examples:
    if ( Ipblock->validate($address) ){ } 

=cut
sub validate {
    my ($self, $address, $prefix) = @_;
    
    eval {
	$self->_prevalidate($address, $prefix);
    };
    if ( my $e = $@ ){
	return 0;
    }
    return 1;
}

##################################################################
=head2 get_devices - Get all devices with IPs within this block

  Arguments:
    None
  Returns: 
    Arrayref of device objects
  Examples:
    my $devs = $subnet->get_devices();

=cut
sub get_devices {
    my ($self) = @_;
    $self->isa_object_method('get_devices');
    
    my %devs;
    foreach my $ch ( $self->children ){
	if ( $ch->is_address ){
	    if ( int($ch->interface) && int($ch->interface->device) ){
		my $dev = $ch->interface->device;
		$devs{$dev->id} = $dev;
	    }
	}else{
	    my $ldevs = $ch->get_devices();
	    foreach my $dev ( @$ldevs ){
		$devs{$dev->id} = $dev;
	    }
	}
    }
    my @devs = values %devs;
    return \@devs;
}


##################################################################
#
# Private Methods
#
##################################################################

##################################################################
# _prevalidate - Validate block before creating and updating
#
#     These checks are based on basic IP addressing rules
#
#   Arguments:
#     address
#     prefix    prefix can be null.  NetAddr::IP will assume it is a host (/32 or /128)
#   Returns:
#     NetAddr::IP object or 0 if failure

sub _prevalidate {
    my ($class, $address, $prefix) = @_;

    $class->isa_class_method('_prevalidate');

    $class->throw_fatal("Ipblock::_prevalidate: Missing required arguments: address")
	unless $address;

    unless ( $address =~ /$IPV4/ || $address =~ /$IPV6/ ) {
	$class->throw_user("IP: $address does not match valid patterns");
    }
    if ( $address eq '1.1.1.1' ) {
	$class->throw_user("IP $address is bogus");
    }
    my $ip;
    my $str;
    if ( !($ip = NetAddr::IP->new($address, $prefix)) ||
	 $ip->numeric == 0 ){
	$str = ( $address && $prefix ) ? (join '/', $address, $prefix) : $address;
	$class->throw_user("Invalid IP: $str");
    }

    # Make sure that what we're working with the base address
    # of the block, and not an address within the block
    unless( $ip->network == $ip ){
	$class->throw_user("IP: $str is not base address of block");
    }
    if ( $ip->within(new NetAddr::IP "127.0.0.0", "255.0.0.0") 
	 || $ip eq '::1' ) {
	$class->throw_user("IP $address is a loopback");
    }
    return $ip;
}

##################################################################
# _validate - Validate block when creating and updating
#
#     This method assumes the block has already been inserted in the DB 
#     (and the binary tree has been updated).  This facilitates the checks.
#     These checks are more specific to the way Netdot manages the address space.
#
#   Arguments:
#     Hash ref of arguments passed to insert/set
#   Returns:
#     True if Ipblock is valid.  Throws exception if not.
#   Examples:
#     $ipblock->_validate();


sub _validate {
    my ($self, $args) = @_;
    $self->isa_object_method('_validate');
    $logger->debug("Ipblock::_validate: Checking validity of " . $self->get_label);
    
    # Make these values what the block is being set to
    # or what it already has
    my $statusname;
    if ( $args->{status} ){
	if ( ref($args->{status}) ){
	    $statusname = $args->{status}->name;
	}else{
	    $statusname = $args->{status};
	}
    }else{
	$self->status->name;
    }

    $args->{dhcp_enabled} ||= $self->dhcp_enabled;
   
    my ($pstatus, $parent);
    if ( ($parent = $self->parent) && $parent->id ){
	
	$pstatus = $parent->status->name;
	if ( $self->is_address() ){
	    if ( $pstatus eq "Reserved" ){
		$self->throw_user("Address allocations not allowed under Reserved blocks");
	    }elsif ( $pstatus eq 'Subnet' ){
		if ( $self->address eq $parent->address ){
		    $self->throw_user(sprintf("IP cannot have same address as its subnet: %s == %s", 
					      $self->address, $parent->address));
		}
	    }
	}else{
	    if ( $pstatus ne "Container" ){
		$self->throw_user(sprintf("Block allocations only allowed under Container blocks: %s within %s",
				  $self->get_label, $parent->get_label));
	    }	    
	}
    }
    if ( $statusname eq "Subnet" ){
	# We only want addresses inside a subnet.  If any blocks within this subnet
	# are containers, we'll just remove them.
	foreach my $ch ( $self->children ){
	    unless ( $ch->is_address() || $ch->status->name eq "Container" ){
		my $err = sprintf("%s %s cannot exist within Subnet %s", 
				  $ch->status->name, $ch->cidr, 
				  $self->cidr);
		$self->throw_user($err);
	    }
	    if ( $ch->status->name eq "Container" ){
		my ($addr, $prefix) = ($ch->address, $ch->prefix);
		$ch->delete();
		$logger->warn(sprintf("_validate: Container %s/%s has been deleted because "
                                      . "it fell within a subnet block",
				      $addr, $prefix));
	    }
	}
    }elsif ( $statusname eq "Container" ){
	if ( $args->{dhcp_enabled} ){
		$self->throw_user("Can't enable DHCP in Container blocks");
	}
    }elsif ( $statusname eq "Reserved" ){
	if ( $self->children ){
	    $self->throw_user("Reserved blocks can't contain other blocks");
	}
	if ( $args->{dhcp_enabled} ){
		$self->throw_user("Can't enable DHCP on Reserved blocks");
	}
    }elsif ( $statusname eq "Dynamic" ) {
	unless ( $self->is_address($self) ){
	    $self->throw_user("Only addresses can be set to Dynamic");
	}
	unless ( $pstatus eq "Subnet" ){
		$self->throw_user("Dynamic addresses must be within Subnet blocks");
	}
	unless ( $self->parent->dhcp_enabled ){
		$self->throw_user("Parent Subnet must have DHCP enabled");
	}
    }elsif ( $statusname eq "Static" ) {
	unless ( $self->is_address($self) ){
	    $self->throw_user("Only addresses can be set to Static");
	}
    }
    return 1;
}

##################################################################
#_build_tree_mem -  Builds the IPv4 or IPv6 space tree in memory
#
#     Build digital tree in memory to establish the hierarchy 
#     of all existing Ipblock objects.  
#
#   Arguments: 
#     IP version [4|6]
#   Returns:
#     Hashref with parent data
#   Examples:
#     Ipblock->_build_tree_mem('4');
#
sub _build_tree_mem {
    my ($class, $version) = @_;
    $class->isa_class_method('_build_tree_mem');

    unless ( $version =~ /^4|6$/ ){
	$class->throw_user("Invalid IP version: $version");
    }
    my $tr = Net::IPTrie->new(version=>$version);
    $class->throw_fatal("Error initializing IP Trie") unless defined $tr;

    $logger->debug( sprintf("Ipblock::_build_tree_mem: Building hierarchy for IP space version %d", 
			    $version) );

    # keep tree handy in global vars for faster operations
    # on individual nodes
    $tree4 = $tr if $version == 4;
    $tree6 = $tr if $version == 6;

    # We override Class::DBI for speed.
    # The other trick is to insert all the non-addresses in the tree first,
    # and for the addresses, we only do a search, which avoids
    # traversing the whole tree section between the smallest block
    # and the address.  All we need is the smallest covering block
    my $dbh = $class->db_Main;
    my $sth;
    
    my $size = ( $version == 4 ) ? 32 : 128;
    
    eval {
	$sth = $dbh->prepare_cached("SELECT id,address,prefix,parent 
                                     FROM ipblock 
                                     WHERE version = $version
                                     AND prefix < $size
                                     ORDER BY prefix");	
	$sth->execute();
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    
    my %parents;
    while ( my ($id, $address, $prefix, $parent) = $sth->fetchrow_array ){
	my $node =  $class->_tree_insert(address => $address, 
					 prefix  => $prefix, 
					 version => $version,
					 data    => $id);
	$parents{$id} = $node->parent->data if ( defined $node && $node->parent );
    }

    # Now the addresses
    eval {
	$sth = $dbh->prepare_cached("SELECT id,address,prefix,parent 
                                     FROM ipblock 
                                     WHERE version = $version
                                     AND prefix = $size
                                     ORDER BY prefix");	
	$sth->execute();
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    while ( my ($id, $address, $prefix, $parent) = $sth->fetchrow_array ){
	my $node =  $class->_tree_find(address => $address, 
				       version => $version,
				       prefix  => $prefix);
	
	$parents{$id} = $node->data if ( defined $node && $node->data );
    }
    
    return \%parents;
}


##################################################################
#   Be smart about updating the hierarchy.  Individual addresses
#   are inserted in the current tree to find their parent.
#   Non-address blocks trigger a full tree rebuild
#
#   Arguments:
#     None
#   Returns:
#     True
#   Examples:
#     $newblock->_update_tree();
#
sub _update_tree{
    my ($self) = @_;
    $self->isa_object_method('_update_tree');
    my $class = ref($self);

    if ( $self->is_address ){
	# Search the tree.  
	my $n = $class->_tree_find(version => $self->version, 
				   address => $self->address_numeric,
				   prefix  => $self->prefix);
	
	# Get parent id
	my $parent;
	if ( $n ){
	    if ( $n->iaddress != $self->address_numeric ) {
		$parent = $n->data if ( $n );
	    }else{
		$parent = $n->parent->data if ( $n && $n->parent );
	    }
	    $self->update({parent=>$parent}) if $parent;
	}
    }else{
	# This is a block (subnet, container, etc)
	$class->build_tree($self->version);
    }
    return 1;
}

##################################################################
#   Be smart about deleting an IP from the hierarchy.
#
#   Arguments:
#     None
#   Returns:
#     True
#   Examples:
#     $ip->_delete_from_tree();
#
sub _delete_from_tree{
    my ($self) = @_;
    $self->isa_object_method('_delete_from_tree');
    my $class = ref($self);

    if ( ! $self->is_address ){
	# This is a block (subnet, container, etc)
	# Assign all my children my current parent
	my $parent   = $self->parent;
	my @children = $self->children;
	foreach my $child ( @children ){
	    $child->update({parent=>$parent});
	}
    }
    my $n = $class->_tree_find(version  => $self->version, 
			       address  => $self->address_numeric,
			       prefix   => $self->prefix);
    if ( $n && ($n->iaddress == $self->address_numeric) ){
	$n->delete();
    }
    return 1;
}

##################################################################
# Insert a node in the memory tree
#
#   Arguments:
#     version - IP version
#     address - IP address (numeric)
#     prefix  - IP mask length (optional - defaults to host mask)
#     data    - user data (optional)
#   Returns:
#     Tree node
#   Examples:
#    
#
sub _tree_insert{
    my ($class, %argv) = @_;
    $class->isa_class_method('_tree_insert');
    $class->throw_user("Missing required arguments: version")
	unless ( $argv{version} );
    $class->throw_user("Missing required arguments: address")
	unless ( $argv{address} );
    my $n;

    my %args = ( iaddress=>$argv{address} );
    $args{prefix} = $argv{prefix} if $argv{prefix};
    $args{data}   = $argv{data}   if $argv{data};

    if ( $argv{version} == 4 ){
	$n = $tree4->add(%args);
    }else{
	$n = $tree6->add(%args);
    }
    return $n;
}

##################################################################
# Find a node in the memory tree
#
#   Arguments:
#     version
#     address (numeric)
#     prefix (optional - defaults to host mask)
#   Returns:
#     Tree node
#   Examples:
#    
#
sub _tree_find{
    my ($class, %argv) = @_;
    $class->isa_class_method('_tree_find');
    $class->throw_fatal("Ipblock::_tree_find: Missing required arguments: version")
	unless ( $argv{version} );
    $class->throw_fatal("Ipblock::_tree_find: Missing required arguments: address")
	unless ( $argv{address} );
    my $n;
    my %args = ( iaddress=>$argv{address} );
    $args{prefix} = $argv{prefix} if defined $argv{prefix};

    if ( $argv{version} == 4 ){
	if ( defined $tree4 ){
	    $n = $tree4->find(%args);
	}else{
	    $class->_build_tree_mem(4);
	    $n = $tree4->find(%args);
	}
    }else{
	if ( defined $tree6 ){
	    $n = $tree6->find(%args);
	}else{
	    $class->_build_tree_mem(6);
	    $n = $tree6->find(%args);
	}
    }
    return $n;
}

##################################################################
#
#   Arguments:
#     None
#   Returns:
#     NetAddr::IP object
#   Examples:
#    print $ipblock->_netaddr->broadcast();

sub _netaddr {
    my $self = shift;
    $self->isa_object_method('_netaddr');
    return new NetAddr::IP($self->address, $self->prefix);
}

##################################################################
# Convert from IP address to integer and store in object
# 
#
sub _obj_ip2int {
    my $self = shift;
    my $ipobj;
    my $address = ($self->_attrs('address'))[0];
    my $val = $self->ip2int($address);
    $self->_attribute_store( address => $val );
    return 1;
}

##################################################################
# Convert from integer to IP address and store in object
#
#
sub _obj_int2ip {
    my $self = shift;
    my ($address, $bin, $val);
    $self->throw_fatal("Invalid object") unless $self;

    return unless ( $self->id );

    my $dbh  = $self->db_Main;
    my $id   = $self->id;
    $address = ($dbh->selectrow_array("SELECT address FROM ipblock WHERE id = $id"))[0];

    if ($self->version == 4){
	$val = (new NetAddr::IP $address)->addr();
    }elsif ($self->version == 6) {
	# This code adapted from Net::IP::ip_inttobin()

	use bigint;

	my $dec = new Math::BigInt $address;
	my @hex = (0..9,'a'..'f');
	my $ipv6 = "";

	# Set warnings off, use integers only (loathe Math::BigInt)
	local $^W = 0;
	use integer;
	foreach my $i (0..31)	# 32 hex digits in 128 bits
	{
	    # There is colon separating every group of 4 hex digits
	    $ipv6 = ':' . $ipv6 if ($i > 0 and $i % 4 == 0);
	    # Last hex digit is in low 4 bits
	    $ipv6 =  $hex[$dec % 16] . $ipv6;
	    # Chop off low 4 bits
	    $dec /= 16;
	}
	no integer;

	# Use the compressed version
	$val = (new NetAddr::IP $ipv6)->short();

    }elsif (defined $self->version){
	$self->throw_fatal(sprintf("Invalid IP version: ", $self->version));
    }else {
	$self->throw_fatal(sprintf("Ipblock id %s (%s) has no version", $self->id, $address ));
    }
    $self->_attribute_store( address => $val );    
    return 1;
}

##################################################################
# Add some triggers
#
__PACKAGE__->add_trigger( deflate_for_create => \&_obj_ip2int );
__PACKAGE__->add_trigger( deflate_for_update => \&_obj_ip2int );
__PACKAGE__->add_trigger( select             => \&_obj_int2ip );


#################################################################
# Determine Status.  It can be either a name
# or a IpblockStatus id
# 
sub _get_status_id {
    my ($self, $arg) = @_;
    $self->throw_fatal("_get_status_id: Missing required argument")
	unless $arg;
    my $id;
    if ( ref($arg) && ref($arg) =~ /IpblockStatus/ ){
	# An object
	$id = $arg->id;
    }elsif ( $arg =~ /\d+/ ){
	# An ID
	$id = $arg;
    }elsif ( $arg =~ /\D+/ ){
	# A name
	my $stobj;
 	unless ( $stobj = IpblockStatus->search(name=>$arg)->first ){
 	    $self->throw_fatal("Status $arg not known");
 	}
 	$id = $stobj->id;
    }
    return $id;
}


##################################################################
# Short way to retrieve all the ip addresses from a device
# 
# Apparently one can't bind the "ORDER BY" parameter :-(
#
# usage: 
#   Ipblock->search_devipsbyaddr($dev)

__PACKAGE__->set_sql(devipsbyaddr => qq{
    SELECT device.id, interface.id, interface.name, interface.device, ipblock.id, ipblock.interface, ipblock.address
	FROM ipblock, interface, device
	WHERE interface.id = ipblock.interface AND
	device.id = interface.device AND
	device.id = ?
	ORDER BY ipblock.address
    });

# usage:
#   Ipblock->search_devipsbyint($dev)

__PACKAGE__->set_sql(devipsbyint => qq{
    SELECT device.id, interface.id, interface.name, interface.device, ipblock.id, ipblock.interface, ipblock.address
	FROM ipblock, interface, device
	WHERE interface.id = ipblock.interface AND
	device.id = interface.device AND
	device.id = ?
	ORDER BY interface.name
    });


=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >> with contributions from Nathan Collins and Aaron Parecki.

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

# Make sure to return 1
1;
