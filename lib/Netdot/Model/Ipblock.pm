package Netdot::Model::Ipblock;

use base 'Netdot::Model';
use Netdot::Util::DNS;
use warnings;
use strict;
use NetAddr::IP;

=head1 NAME

Netdot::Ipblock - Manipulate IP Address Space

=head1 SYNOPSIS
    
    my $newblock = Ipblock->insert({address=>'192.168.1.0', prefix=>32});
    print $newblock->cidr;
    my $subnet = $newblock->parent;
    print "Address Usage ", $subnet->address_usage;
    
=cut


my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();

my $logger = Netdot->log->get_logger('Netdot::Model::Device');
my $dns    = Netdot::Util::DNS->new();

BEGIN{
    # Load plugin at compile time
    my $ip_name_plugin_class = __PACKAGE__->config->get('DEVICE_IP_NAME_PLUGIN');
    eval  "require $ip_name_plugin_class";
    
    sub load_ip_name_plugin{
	return $ip_name_plugin_class->new();
    }
}

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

    if ( exists $args{address} ){
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
    map { $_->used_blocks, $_->own_blocks } @ents;
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
    status    name of, id or IpblockStatus object (default: Container)
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
    $argv->{dns_delegated} ||= 0; 
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

    my $newblock = $class->SUPER::insert($argv);
    
    # Rebuild tree
    $class->build_tree($ip->version);
    
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
	    $e->rethrow();
	}
    }
    
    # Inherit some of parent's values if it's not an address
    if ( !$newblock->is_address && (int($newblock->parent) != 0) ){
	my %state = ( dns_delegated => $newblock->parent->dns_delegated, 
		      owner         => $newblock->parent->owner );
	$newblock->update(\%state);
    }
    
    # This is a funny hack to avoid the address being shown in numeric.
    my $id = $newblock->id;
    undef $newblock;
    $newblock = __PACKAGE__->retrieve($id);
    return $newblock;
}


##################################################################
=head2 get_covering_block - Get the closest available block that contains a given block

    When a block is searched and not found, it is useful to show the closest existing block
    that would contain it.  

 Arguments: 
    IP address and (optional) prefix
 Returns:   
    Ipblock object or 0 if not found
  Examples:
    my $ip = Ipblock->get_covering_block(address=>$address, prefix=>$prefix);

=cut

#  The fastest way to do it is inserting it, building the IP tree,
#  retrieving the parent, and then removing it.
#  A faster and more elegant way would be to apply the trie
#  algorithm in build_tree for this block only, without inserting it.

sub get_covering_block {
    my ($class, %args) = @_;
    $class->isa_class_method('get_covering_block');
    
    $class->throw_fatal('Ipblock::get_covering_block: Missing required arguments: address')
	unless ( $args{address} );

    my $ip = $class->_prevalidate($args{address}, $args{prefix});

    if ( $class->search(address=>$ip->addr, prefix=>$ip->masklen) ){
	my $msg = sprintf("Block %s/%s exists in db.  Using wrong method!", 
			  $ip->addr, $ip->masklen);
	$class->throw_fatal($msg);
    }
    my %state = ( address => $ip->addr, 
		  prefix  => $ip->masklen,
		  version => $ip->version );
    
    if ( my $ipblock = $class->insert( \%state ) ){
	$logger->debug(sub {sprintf("Ipblock::get_covering_block: Temporarily inserted %s/%s",
				    $ipblock->address, $ipblock->prefix) });

	$class->build_tree($ip->version);

	my $parent;
	if ( int($parent = $ipblock->parent) == 0 ){
	    
	    $logger->debug(sub {sprintf("Ipblock::get_covering_block: Found no parent for %s/%s",
					$ipblock->address, $ipblock->prefix) });
	    # Have to explicitly set to zero because Class::DBI returns
	    # an empty (though non-null) object
	    $parent = 0;
	}
	$ipblock->delete;
	
	$logger->debug(sub { sprintf("Ipblock::get_covering_block: Removed %s/%s",
				     $ip->addr, $ip->masklen) });
	
	$class->build_tree($ip->version);
	return $parent;
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
=head2 build_tree -  Builds the IPv4 or IPv6 space tree

    A very fast, simplified digital tree (or trie) that establishes
    the hierarchy of Ipblock objects.  

  Arguments: 
    IP version [4|6]
  Returns:
    True if successful
  Examples:
    Ipblock->build_tree('4');

=cut

# Background: 
# A trie structure is based on a radix tree using a radix of two.  
# This is commonly used in routing engines, which need to quickly find the best 
# match for a given address against a list of prefixes.
# The term "Trie" is derived from the word "retrieval".
# For more information on digital trees, see:
#    * Algorithms in C, Robert Sedgewick

# How it works:
# A digital tree is built by performing a binary comparison on each bit of 
# the number (in this case, the IP address) sequentially, starting from the 
# most significant bit.  

# Examples:

#  Given these two IP addresses:
#                  bit 31                                0
#                      |                                 |
#    10.0.0.0/8      : 00001010.00000000.00000000.00000000/8
#    10.128.0.0/32   : 00001010.10000000.00000000.00000000/32

#  Starting with the first address:

#  bit     tree position
#  -------------------------------------------------------------------
#  31             0
#  30           0
#  29         0
#  28       0
#  27         1
#  26       0
#  25         1
#  24       0    <-- Prefix position (size - prefix).  Stop and save object id


#  Continuing with the second address:

#  bit     tree position
#  -------------------------------------------------------------------
#  31             0
#  30           0
#  29         0
#  28       0
#  27         1
#  26       0
#  25         1
#  24       0    <-- Object found.  Save id as possible parent
#  23          1  
#  22     0

#  ...continued until bit 0

# Since there are no more objects to process, it is determined
# that the "parent" of the second adddress is the first address.

sub build_tree {
    my ($class, $version) = @_;
    $class->isa_class_method('build_tree');

    my $size;           # Number of bits in the address
    if ( $version == 4 ){
	$size = 32;
    }elsif ( $version == 6 ){
	use bigint; 	# IPv6 numbers are larger than what a normal integer can hold
	$size = 128;
    }else{
	$class->throw_fatal("Invalid IP version: $version");
    }
    
    my $trie = {};      # Empty hashref.  Will store the binary tree
    my %parents;        # Associate Ipblock objects with their parents

    # Retrieve all the Ipblock objects of given version.
    # Order them by prefix to make sure that larger blocks (smallest prefix) are
    # inserted first in the tree
    # We override Class::DBI for speed.
    my $dbh = $class->db_Main;
    my $sth;
    eval {
	$sth = $dbh->prepare_cached("SELECT id,address,prefix,parent 
                                     FROM ipblock 
                                     WHERE version = $version 
                                     ORDER BY prefix");	
	$sth->execute;
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    
    while ( my ($id, $address, $prefix, $parent) = $sth->fetchrow_array ){
	my $p      = $trie;      # pointer that starts at the root
	my $bit    = $size;      # bit position.  Start at the most significant bit
	my $last_p = 0;          # Last possible parent found
	$parent    = 0 if !defined($parent);
	while ($bit > $size - $prefix){
	    $bit--;
	    $last_p = $p->{id} if defined $p->{id};
	    #
	    # If we reach a leaf, all /32s (or /128s) below it
	    # don't need to be inserted in the tree.  
	    # Our purpose is to find parents as quickly as possible
	    last if (defined $last_p && $prefix == $size && !(keys %$p));
	    
	    # bit comparison.
	    # It returns 1 or 0
	    my $r = ($address & 2**$bit)/2**$bit; 
 
	    # Insert the node if it does not exist
	    if (! exists $p->{$r} ){
		$p->{$r} = {};	
	    }
	    # Walk one step down the tree
	    $p = $p->{$r};
	    
	    # Store the id of the object if we have reached 
	    # its prefix position (the rest of the bits are not significant)
	    $p->{id} = $id if ($bit == $size - $prefix);
	}    
	# Parent is the last valid node known
	# (do not save unless it has changed)
	$parents{$id} = $last_p if ($parent != $last_p);
    }
    # Reflect changes in db
    undef $sth;
    eval {
	$sth = $dbh->prepare_cached("UPDATE ipblock SET parent = ? WHERE id = ?");
	foreach (keys %parents){
	    $sth->execute($parents{$_}, $_);
	}
    };
    if ( my $e = $@ ){
	$class->throw_fatal( $e );
    }
    
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
	    if ( /^address|prefix|version|interface|status|physaddr$/ ){
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
    $argv->{address} ||= $self->address;
    $argv->{prefix}  ||= $self->prefix;

    my $ip;
    $ip = $class->_prevalidate($argv->{address}, $argv->{prefix});
    
    if ( my $tmp = $class->search(address => $ip->addr,
				  prefix  => $ip->masklen)->first ){
	$self->throw_user("Block ".$argv->{address}."/".$argv->{prefix}." already exists in db")
	    if ( $tmp->id != $self->id );
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

    my %bak  = $self->get_state();
    my $result = $self->SUPER::update( \%state );

    # Unly rebuild the tree if address/prefix have changed
    if ( $self->address ne $bak{address} || $self->prefix ne $bak{prefix} ){
	$class->build_tree($ip->version);
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
	$class->build_tree($ip->version);
    }
    return $result;
}



##################################################################
=head2 delete - Delete Ipblock object

    We override delete to allow deleting children recursively as an option.
    
  Arguments: 
    recursive  - Remove blocks recursively (default is false)
    stack      - stack level (for recursiveness control)
  Returns:
    True if successful
  Examples:
    $ipblock->delete(recursive=>1);

=cut

sub delete {
    my ($self, %args) = @_;
    $self->isa_object_method('delete');
    my $class = ref($self);
    my $stack = $args{stack}   || 0;
    
    if ( $args{recursive} ){
	foreach my $ch ( $self->children ){
	    $ch->delete(recursive => 1, stack=>$stack+1);
	}
    }
    my $version = $self->version;

    $self->SUPER::delete();

    # We check if this is the first call in the stack
    # to avoid rebuilding the tree unnecessarily
    $class->build_tree($version) if ( $stack == 0 );
    
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
    my $plugin = $self->load_ip_name_plugin();
    my $name   = $plugin->get_name( $self );

    my @arecords = $self->arecords;

    my %rrstate = (name=>$name, zone=>$zone);

    if ( ! @arecords  ){
	# No A records exist for this IP yet.

	# Is this the only ip in this device,
	# or is this the address associated with the hostname?
	my @devips = $device->get_ips();
	if ( (scalar @devips) == 1 || exists $hostnameips{$self->address} ){

	    # We should already have an RR created (via Device::assign_name)
	    # Create the A record to link that RR with this Ipobject
	    RRADDR->insert( {rr => $device->name, ipblock => $self} );
	    $logger->info(sprintf("%s: Inserted DNS A record for %s", 
				  $host, $self->address));
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
		if ( exists $hostnameips{$self->address} ){
		    $logger->debug( sprintf("Ipblock::update_a_records: %s: Will not update DNS for main address: %s", 
					    $host, $self->address) );
		}else{
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

############################################################################
=head2 retrieve_all_hashref

    Retrieves all IPs from the DB and stores them in a hash, keyed by 
    numeric address. The value is the Ipblock id.

  Arguments: 
    None
  Returns:   
    Hash reference 
  Examples:
    my $db_ips = PhysAddr->retriev_all_hash();

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
    physaddr  - String containing the MAC address associated with this IP
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

    my $db_macs = PhysAddr->retrieve_all_hashref;
    my $db_ips  = $class->retrieve_all_hashref;
    
    my $dbh = $class->db_Main;

    # Build SQL queries
    my ($sth1, $sth2, $sth3, $sth4);
    eval {
	$sth1 = $dbh->prepare_cached("UPDATE ipblock SET physaddr=?,last_seen=?
                                      WHERE id=?");	

	$sth2 = $dbh->prepare_cached("UPDATE ipblock SET last_seen=?
                                      WHERE id=?");	

	$sth3 = $dbh->prepare_cached("INSERT INTO ipblock 
                                     (address,prefix,version,status,physaddr,first_seen,last_seen)
                                     VALUES (?, ?, ?, ?, ?, ?, ?)");	
	
	$sth4 = $dbh->prepare_cached("INSERT INTO ipblock 
                                     (address,prefix,version,status,first_seen,last_seen)
                                     VALUES (?, ?, ?, ?, ?, ?, ?)");	
	

    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }

    # Now walk our list and do the right thing

    eval{
	foreach my $address ( keys %$ips ){
	    my $attrs = $ips->{$address};
	    # Convert address to decimal format
	    my $dec_addr = $class->ip2int($address);
	    
	    if ( exists $db_ips->{$dec_addr} ){
		# IP exists
		if ( exists $db_macs->{$attrs->{physaddr}} ){
		    $sth1->execute($db_macs->{$attrs->{physaddr}}, 
				   $attrs->{timestamp}, 
				   $db_ips->{$dec_addr},
				   );
		}else{
		    # MAC does not exist. Should not happen, but...
		    $sth2->execute($attrs->{timestamp}, 
				   $db_ips->{$dec_addr});
		}
	    }else{
		# IP does not exist
		if ( exists $db_macs->{$attrs->{physaddr}} ){
		    $sth3->execute($dec_addr,
				   $attrs->{prefix},
				   $attrs->{version},
				   $attrs->{status},
				   $db_macs->{$attrs->{physaddr}},
				   $attrs->{timestamp}, 
				   $attrs->{timestamp},
				   );
		}else{
		    # MAC does not exist.  Should not happen, but...
		    $sth4->execute($dec_addr,
				   $attrs->{prefix},
				   $attrs->{version},
				   $attrs->{status},
				   $attrs->{timestamp}, 
				   $attrs->{timestamp},
				   );
		}
	    }
	}
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    
    my $end = time;
    $logger->debug(sprintf("Ipblock::fast_update: Done Updating: %d addresses in %d secs",
			   scalar(keys %$ips), ($end-$start)));
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

    unless ( $address =~ /$IPV4/ ||
	     $address =~ /$IPV6/) {
	$class->throw_user("Invalid IP: $address");
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
	$class->throw_user("Invalid IP: $str");
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
    my $statusname = $args->{status} || $self->status->name;
    $args->{dhcp_enabled}            ||= $self->dhcp_enabled;
    $args->{dns_delegated}           ||= $self->dns_delegated;
    
    my ($pstatus, $parent);
    if ( ($parent = $self->parent) && $parent->id ){
	
	$pstatus = $parent->status->name;
	if ( $self->is_address() ){
	    if ( $pstatus eq "Reserved" ){
		$self->throw_user("Address allocations not allowed under Reserved blocks");
	    }
	}else{
	    if ( $pstatus ne "Container" ){
		$self->throw_user("Block allocations only allowed under Container blocks");
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
	if ( $args->{dns_delegated} ){
		$self->throw_user("Can't delegate DNS on Reserved blocks");
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
