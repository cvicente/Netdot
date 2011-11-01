package Netdot::Model::Ipblock;

use base 'Netdot::Model';
use warnings;
use strict;
use Math::BigInt;
use NetAddr::IP;
use Net::IPTrie;
use Storable qw(nfreeze thaw);
use Scalar::Util qw(blessed);
use DBI qw(:sql_types);

=head1 NAME

Netdot::Model::Ipblock - Manipulate IP Address Space

=head1 SYNOPSIS
    
    my $newblock = Ipblock->insert({address=>'192.168.1.0', prefix=>32});
    print $newblock->cidr;
    my $subnet = $newblock->parent;
    print "Address Usage ", $subnet->address_usage;
    
=cut

my $logger = Netdot->log->get_logger('Netdot::Model::Ipblock');

BEGIN{
    # Load plugins at compile time

    my $ip_name_plugin_class = __PACKAGE__->config->get('DEVICE_IP_NAME_PLUGIN');
    eval  "require $ip_name_plugin_class";
    if ( my $e = $@ ){
	die $e;
    }
    
    sub load_ip_name_plugin{
	$logger->debug("Loading IP_NAME_PLUGIN: $ip_name_plugin_class");
	return $ip_name_plugin_class->new();
    }

    my $range_dns_plugin_class = __PACKAGE__->config->get('IP_RANGE_DNS_PLUGIN');
    eval  "require $range_dns_plugin_class";
    if ( my $e = $@ ){
	die $e;
    }
    
    sub load_range_dns_plugin{
	$logger->debug("Loading IP_RANGE_DNS_PLUGIN: $range_dns_plugin_class");
	return $range_dns_plugin_class->new();
    }
}

my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();

my $ip_name_plugin   = __PACKAGE__->load_ip_name_plugin();
my $range_dns_plugin = __PACKAGE__->load_range_dns_plugin();

=head1 CLASS METHODS
=cut

##################################################################
=head int2ip - Convert a decimal IP into a string address

  Arguments:
    address (decimal)
    version (4 or 6)
  Returns:
    string
  Example:
    my $address = Ipblock->int2ip($number, $version);

=cut
sub int2ip {
    my ($class, $address, $version) = @_;
    
    if ( !defined($address) || !defined($version) ){
	$class->throw_fatal(sprintf("Missing required arguments: address and/or version "));
    }
    
    my $val;
    if ( $version == 4 ){
	$val = (new NetAddr::IP $address)->addr();
    }elsif ( $version == 6 ) {
	# This code adapted from Net::IP::ip_inttobin()
	
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

	# Per RFC 5952 recommendation
	$val = lc($val);

    }else{
	$class->throw_fatal(sprintf("Invalid IP version: %s", $version));
    }
    return $val;
}

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
   
    if ( defined $args{status} ){
	my $statusid = $class->_get_status_id($args{status});
	$args{status} = $statusid;
    }
    if ( defined $args{address} ){
	if ( $args{address} =~ /\/\d+$/ ){
	    # Address is in CIDR format
	    my ($address, $prefix) = split /\//, $args{address};
	    $args{address} = $class->ip2int($address);
	    $args{prefix}  = $prefix;
	}elsif ( $args{address} =~ /\D/ ){
	    # Address contains non-digits
	    if ( $class->matches_ip($args{address}) ){
		# Ony convert to integer if address matches valid IP formats
		$args{address} = $class->ip2int($args{address});
	    }else{
		$class->throw_user(sprintf("Address %s does not match valid IP v4/v6 formats", $args{address}));
	    }
	}
	if ( $class->config->get('DB_TYPE') eq 'mysql' ){
	    # Deal with mysql bug 
	    # http://bugs.mysql.com/bug.php?id=60213
	    # We have to build our own query
	    my @keys = keys %args;
	    my @vals = values %args;
	    my $q = join(' AND ', map { "$_=?" } @keys);
	    my @cols = ('id');
	    my %essential = $class->meta_data->get_column_order_brief;
	    push @cols, keys %essential;
	    my $cols = join ',', @cols;
	    my $dbh = $class->db_Main();
	    my $sth = $dbh->prepare_cached("SELECT $cols FROM ipblock WHERE $q;");
	    for my $i (1..scalar(@keys)){
		if ( $keys[$i-1] eq 'address' ){
		    # Notice that we force the value to be a string
		    $sth->bind_param($i, "".$vals[$i-1], SQL_INTEGER);
		}else{
		    $sth->bind_param($i, $vals[$i-1]);		    
		}
	    }
	    $sth->execute;
	    return $class->sth_to_objects($sth);
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
	    my $pattern = $argv{address};
	    $pattern =~ s/\./\\./g;
	    
	    # we assume we are looking for IPs that start with the pattern
	    # because I do not think it is likely to search for a middle substring
	    # without knowing the beginning.
	    my $prefix = $pattern;  # this is string prefix not the IP prefix
	    my $ip_version;
	    my $has_prefix = 0;
	    my $ip_pattern;  # the pattern without IP prefix
	    my $slash_prefix;
	    my $lower;
	    my $upper;
	    $prefix =~ s/^\^//;
	    if ( $prefix =~ /\/\d+$/ ) {  # if it has an IP prefix slash in it
		$has_prefix = 1;
		($prefix, $slash_prefix) = split /\//, $prefix;
	    }
	    $ip_pattern = $prefix;
	    if ( $prefix =~ /\./ ) {  # IPv4
		$ip_version = 4;
		$prefix =~ s/^(.*)\\\.[^\.]*/$1/;
		$lower = $prefix;
		$upper = $prefix;
		do {
		    $lower = $lower . "\\" . ".0";
		    $upper = $upper . "\\" . ".255";
		} while (($lower =~ tr/\.//) < 3);
		$lower =~ s/\\\./\./g;
		$upper =~ s/\\\./\./g;
	    } elsif ( $prefix =~ /:/ ) {  #IPv6
		$ip_version = 6;
		$prefix =~ s/^(.*):[^:]*/$1/;
		$lower = $prefix;
		$upper = $prefix;
		do {
		    $lower = $lower . ":0";
		    $upper = $upper . ":FFFF";
		} while (($lower =~ tr/://) < 7);
	    } else {  # no indication (no '.' or ':'): search the old way
		my @ipb;
		my $it = $class->retrieve_all;
		while ( my $ipb = $it->next ) {
		    if ( $ipb->cidr() =~ /$pattern/ ){
			push @ipb, $ipb;
		    }
		    if ( scalar(@ipb) > $class->config->get('IPMAXSEARCH') ){
			last;
		    }
		}
		@ipb = sort { $a->address_numeric <=> $b->address_numeric } @ipb;
		return @ipb;
	    }
	    $lower = $class->ip2int($lower);
	    $upper = $class->ip2int($upper);
	    
	    my $dbh = $class->db_Main;
	    my $sth;
	    eval {
		$sth = $dbh->prepare("SELECT address, prefix, version FROM ipblock WHERE address>=? AND address<=?");
		$sth->execute($lower, $upper);
	    };
	    $class->throw_fatal("$@") if $@;
	    
	    my @ipb;
	    while ( my ($ipbn, $prf, $ver) = $sth->fetchrow_array() ){
		if ( $ipbn && $prf && $ver ) {
		    # $ipbn is the numerical format
		    # $ipbh is the human-readable format
		    # $ipb is the Ipblock object
		    my $ipb = $class->search(address=>$ipbn)->first;
		    my $ipbh = $class->int2ip($ipbn, $ver);
		    
		    # traditionally expected matching method
		    if ( $ipb->cidr() =~ /$pattern/ ){
			push @ipb, $ipb;
		    }
		    # an alternative matching method which also might help
		    elsif ( defined($slash_prefix) && $slash_prefix ne "" && $ipbh =~ /$ip_pattern/ && $prf eq $slash_prefix ){
			push @ipb, $ipb;
		    } elsif ( (!defined($slash_prefix) || (defined($slash_prefix) && $slash_prefix eq "")) && $ipbh =~ /$ip_pattern/ ) {
			# this case might be the same as the first 'if'
			push @ipb, $ipb;
		    }
		    
		    # checking for upper limit of number of matches
		    if ( scalar(@ipb) > $class->config->get('IPMAXSEARCH') ){
			last;
		    }
		} # `prefix` in the database should be non-nullable defined by netdot.meta.
		  # Therefore we do not look at the case when it is not defined.
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

    # Use the SiteSubnet relationship if available
    map { $blocks{$_->subnet} = $_->subnet } map { $_->subnets } @sites; 
    
    # Add the entities related to the sites matching the criteria
    map { push @ents, $_->entity } map { $_->entities } @sites; 
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
=head2 get_unused_subnets - Retrieve subnets with no addresses

  Arguments:
    version - 4 or 6 (defaults to all)
  Returns: 
    Array of Ipblock objects
  Examples:
    my @unused = Ipblock->get_unused_subnets(version=>4);
=cut

sub get_unused_subnets {
    my ($class, %args) = @_;
    $class->isa_class_method('get_unused_subnets');
    my @ids;
    my $query = "SELECT     subnet.id, address.id 
                 FROM       ipblockstatus, ipblock subnet
                 LEFT JOIN  ipblock address ON (address.parent=subnet.id)
                 WHERE      subnet.status=ipblockstatus.id 
                    AND     ipblockstatus.name='Subnet'";

    if ( $args{version} ){
	$query .= " AND subnet.version=$args{version}";
    }
    my $dbh = $class->db_Main;
    my $sth = $dbh->prepare_cached($query);
    $sth->execute();
    my $rows = $sth->fetchall_arrayref();
    my %subs;
    foreach my $row ( @$rows ){
	my ($subnet, $address) = @$row;
	if ( defined $address ){
	    $subs{$subnet}{$address} = 1;
	}else{
	    $subs{$subnet} = {};
	}
    }

    foreach my $subnet ( keys %subs ){
	if ( !keys %{$subs{$subnet}} ){
	    push @ids, $subnet;
	}
    }
    my @result;
    foreach my $id ( @ids ){
	my $ip = Ipblock->retrieve($id);
	if ( defined $args{version} && $args{version} == 4 ){
	    # Ignore IPv4 multicast blocks
	    if ( $ip->_netaddr->within(new NetAddr::IP "224.0.0.0/4") ){
		next;
	    }
	}
	push @result, $ip;
    }
    @result = sort { $a->address_numeric <=> $b->address_numeric } @result;
    return @result;
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
=head2 is_loopback - Check if address is a loopback address

  Arguments:
    address - dotted quad ip address.  Required.
    prefix  - dotted quad or prefix length. Optional. NetAddr::IP will assume it is a host (/32 or /128)

  Returns:
    1 or 0
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
    if ( !($ip = NetAddr::IP->new($address, $prefix))){
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
=head2 is_link_local - Check if address is v6 Link Local

    Can be called as either class or instance method

  Arguments:
    address - IPv6 address. Required if called as class method
    prefix  - Prefix length. Optional. NetAddr::IP will assume it is a host (/128)
  Returns:
    1 or 0
  Example:
    my $flag = Ipblock->is_link_local('fe80::1');
    my $flag = $ipblock->is_link_local();

=cut
sub is_link_local{
    my ( $self, $address, $prefix ) = @_;
    my $class = ref($self);
    my $ip;
    if ( $class ){
	$ip = $self->_netaddr();
    }else{
	$self->throw_fatal("Missing required arguments: address")
	    unless $address;
	my $str;
	if ( !($ip = NetAddr::IP->new6($address, $prefix))){
	    $str = ( $address && $prefix ) ? (join '/', $address, $prefix) : $address;
	    $self->throw_user("Invalid IP: $str");
	}
    }
    if ( $ip->within(NetAddr::IP->new6("fe80::/10")) ) {
	return 1;	
    }
    return 0;
}

##################################################################
=head2 within - Check if address is within block

  Arguments:
    address - dotted quad ip address.  Required.
    block   - dotted quad network address.  Required.

  Returns:
    True or false
  Example:
    Ipblock->within('127.0.0.1', '127.0.0.0/8');

=cut
sub within{
    my ($class, $address, $block) = @_;
    $class->isa_class_method('within');
    
    $class->throw_fatal("Ipblock::within: Missing required arguments: address and/or block")
	unless ( $address && $block );
    
    unless ( $block =~ /\// ){
	$class->throw_user("Ipblock::within: $block not a valid CIDR string")
    }
    my ($baddr, $bprefix) = split /\//, $block;
    
    if ( (my $ip      = NetAddr::IP->new($address)) && 
	 (my $network = NetAddr::IP->new($baddr, $bprefix)) 
	){
	return 1 if $ip->within($network);
    }
    
    return 0;
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

    unless ( $argv->{status} ){
	if (defined $argv->{prefix} && 
	    ($class->matches_v4($argv->{address}) && $argv->{prefix} eq '32') || 
	    ($class->matches_v6($argv->{address}) && $argv->{prefix} eq '128')) {
	    $argv->{status} = "Static";
	} else {
	    $argv->{status} = "Container";
	}
    }
    
    # $ip is a NetAddr::IP object;
    my $ip;
    $ip = $class->_prevalidate($argv->{address}, $argv->{prefix});
    $argv->{address} = $ip->addr;
    $argv->{prefix}  = $ip->masklen;
    $argv->{version} = $ip->version;
    
    my $statusid     = $class->_get_status_id($argv->{status});
    $argv->{status}  = $statusid;

    my $timestamp = $class->timestamp;
    $argv->{first_seen} = $timestamp;
    $argv->{last_seen}  = $timestamp;

    my $no_update_tree = $argv->{no_update_tree};
    delete $argv->{no_update_tree};

    my $validate  = 1;
    if ( defined $argv->{validate} ){
	$validate = $argv->{validate};
	delete $argv->{validate};
    }

    my $newblock = $class->SUPER::insert($argv);
    
    # Update tree unless we're told not to do so for speed reasons
    # (usually because it will be rebuilt at the end of a device update)
    unless ( $no_update_tree ){
	eval {
            $newblock->_update_tree();
        };
	if ( my $e = $@ ){
            # assume any errors from _update_tree are caused by $newblock
	    $newblock->delete();
	    $e->rethrow() if ref($e);
	}
    }
    
    #####################################################################
    # Now check for rules
    # We do it after inserting because having the object and the tree
    # makes things much simpler.  Workarounds welcome.
    # Notice that we might be told to skip validation
    #####################################################################
    
    # This is a funny hack to avoid the address being shown in numeric.
    # It also makes sure that the object's attributes are updated before
    # calling validation methods
    my $id = $newblock->id;
    undef $newblock;
    $newblock = $class->retrieve($id);

    if ( $validate ){
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
    if ( !$newblock->is_address && $newblock->parent ){
	$newblock->SUPER::update({owner=>$newblock->parent->owner});
    }
    
    # Generate a hostaudit entry if necessary to trigger
    # a DHCP update
    if ( $newblock->status->name eq 'Dynamic' ){
	my %args;
	$args{operation} = 'insert';
	my (@fields, @values);
	foreach my $col ( $newblock->columns ){
	    if ( defined $newblock->$col ){ 
		push @fields, $col;
		if ( $newblock->$col && blessed($newblock->$col) ){
		    push @values, $newblock->$col->get_label();
		}else{
		    push @values, $newblock->$col;
		}
	    } 
	}
	$args{fields} = join ',', @fields;
	$args{values} = join ',', map { "'$_'" } @values if @values;
	$newblock->_host_audit(%args);
    }
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

    my @ipargs = ($args{address});
    push @ipargs, $args{prefix} if defined $args{prefix};
    my $ip = NetAddr::IP->new(@ipargs);
    return unless defined $ip;

    my $tree = $class->_tree_get($ip->version);

    # Search for this IP in the tree.  We should get the parent node
    my $n = $class->_tree_find(address => ($ip->numeric)[0], 
			       prefix  => $ip->masklen,
			       tree    => $tree,
	);

    if ( $n && $n->data ){
	return Ipblock->retrieve($n->data);
    }
}


##################################################################
=head2 get_roots - Get a list of root IP blocks

    Root IP blocks are blocks at the top of the hierarchy.  
    This list does not include end node addresses.

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
   
    my %where = (parent => undef);
    my %opts  = (order_by => 'address');
    
    my $len;
    my @ipb;
    if ( $version == 4 || $version eq 'all' ){
	$len = 32;
	$where{version} = 4;
	$where{prefix} = { '!=', $len };
	push @ipb, $class->search_where(\%where, \%opts);
    }
    if ( $version == 6 || $version eq 'all' ){
	$len = 128;
	$where{version} = 6;
	$where{prefix} = { '!=', $len };
	push @ipb, $class->search_where(\%where, \%opts);
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
=head2 numhosts_v6 - Number of hosts (/128s) in a v6 block. 


  Arguments:
    x: the mask length (i.e. 64)
  Returns:
    a power of 2       

=cut

sub numhosts_v6 {
    my ($class, $x) = @_;
    $class->isa_class_method('numhosts');
    return Math::BigInt->new(2)->bpow(128-$x);
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

    my ($parents, $current_parents) = $class->_build_tree_mem($version);

    # Reflect changes in db
    my $dbh = $class->db_Main;
    my $sth;
    $sth = $dbh->prepare_cached("UPDATE ipblock SET parent = ? WHERE id = ?");
    foreach ( keys %$parents ){
	$sth->execute($parents->{$_}, $_)
	    unless ( (defined $parents->{$_} && defined $current_parents->{$_}) &&
		     ($parents->{$_} == $current_parents->{$_}) );
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
    $logger->debug(sub{"Ipblock::retrieve_all_hashref: Retrieving all IPs..." });
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
    $logger->debug(sub{"Ipblock::retrieve_all_hashref: ...done" });

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
    $logger->debug(sub{"Ipblock::fast_update: Updating IP addresses in DB" });
    my $dbh = $class->db_Main;

    if ( $class->config->get('DB_TYPE') eq 'mysql' ){
	# Take advantage of MySQL's "ON DUPLICATE KEY UPDATE" 
	my $sth = $dbh->prepare_cached("INSERT INTO ipblock
                                        (address,prefix,version,status,first_seen,last_seen)
                                        VALUES (?, ?, ?, ?, ?, ?)
                                        ON DUPLICATE KEY UPDATE last_seen=VALUES(last_seen);");

	foreach my $address ( keys %$ips ){
	    my $attrs = $ips->{$address};
	    # Convert address to decimal format
	    my $dec_addr = $class->ip2int($address);
	    $sth->execute($dec_addr, $attrs->{prefix}, $attrs->{version},
			  $attrs->{status}, $attrs->{timestamp}, $attrs->{timestamp});
	}
    }else{
	my $db_ips  = $class->retrieve_all_hashref;

	# Build SQL queries
	my $sth1 = $dbh->prepare_cached("UPDATE ipblock SET last_seen=?
                                          WHERE id=?");	
	
	my $sth2 = $dbh->prepare_cached("INSERT INTO ipblock 
                                          (address,prefix,version,status,first_seen,last_seen)
                                           VALUES (?, ?, ?, ?, ?, ?)");
	
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
    $logger->debug(sub{ sprintf("Ipblock::fast_update: Done Updating: %d addresses in %s",
				scalar(keys %$ips), $class->sec2dhms($end-$start)) });
    return 1;
}


##################################################################
=head2 get_maxed_out_subnets - 

  Arguments:
    version (optional)
  Returns:
    Array of arrayrefs containing the subnet object and the percentage of free addresses
  Examples:
    my @maxed_out = Ipblock->get_maxed_out_subnets();

=cut
sub get_maxed_out_subnets {
    my ($self, %args) = @_;
    $self->isa_class_method('get_maxed_out_subnets');

    my $threshold = Netdot->config->get('SUBNET_USAGE_MINPERCENT') 
	|| $self->throw_user("Ipblock::get_maxed_out_subnets: SUBNET_USAGE_MINPERCENT is not defined in config");

    my @result;
    my $query = "SELECT     subnet.id, subnet.version, subnet.prefix
                 FROM       ipblockstatus, ipblock subnet
                 WHERE      subnet.status=ipblockstatus.id 
                    AND     ipblockstatus.name='Subnet'
                 ";
    
    if ( $args{version} ){
	$query .= " AND subnet.version=$args{version}";
    }

    $query .= " ORDER BY   subnet.address";

    my $dbh  = $self->db_Main();
    my $rows = $dbh->selectall_arrayref($query);
    foreach my $row ( @$rows ){
	my ($id, $version, $prefix) = @$row;
	if ( $version == 4 && $prefix >= 30 ){
	    # Ignore point-to-point subnets
	    next;
	}
	my $subnet = Ipblock->retrieve($id);
	my ($total, $used);
	if ( $version == 6 ){
	    $total = new Math::BigInt($subnet->num_addr());
	    $used  = new Math::BigInt($subnet->num_children());
	}else{ 
	    $total = $subnet->num_addr();
	    $used  = $subnet->num_children();
	}
	my $free  = $total - $used;
	my $percent_free = ($free*100/$total);
	
	if ( $percent_free <= $threshold ){
	    push @result, [$subnet, $percent_free];
	}
    }
    return @result;
}

################################################################
=head2 add_range - Add or update a range of addresses
    

  Arguments: 
    Hash with following keys:
      start       - First IP in range
      end         - Last IP in range
      status      - Ipblock status
      parent      - Parent Ipblock id (optional)
      gen_dns     - Boolean.  Auto generate A/AAAA and PTR records
      name_prefix - String to prepend to host part of IP address
      name_suffix - String to append to host part of IP address
      fzone       - Forward Zone id for DNS records
  Returns:   
    Ipblock object of parent block
  Examples:

=cut
sub add_range{
    my ($class, %argv) = @_;
    $class->isa_class_method('add_range');

    my $ipstart  = NetAddr::IP->new($argv{start});
    my $ipend    = NetAddr::IP->new($argv{end});
    unless ( $ipstart <= $ipend ){
	$class->throw_user("Invalid range: $argv{start} - $argv{end}");
    }
    my $version = $ipstart->version;
    my $prefix  = ($version == 4)? 32 : 128;
    
    # Validate parent argument
    if ( $argv{parent} ){
	my $p;
	if ( ref($argv{parent}) ){
	    $p = $argv{parent};
	}else{
	    $p = Ipblock->retrieve($argv{parent});
	}
	my $np = $p->_netaddr();
	unless ( $ipstart->within($np) && $ipend->within($np) ){
	    $class->throw_user("Start and/or end IPs not within given subnet: ".$p->get_label);
	}
    }

    # We want this to happen atomically (all or nothing)
    my @newips;
    Netdot::Model->do_transaction(sub {
	for ( my $i = Math::BigInt->new($ipstart->numeric); $i <= Math::BigInt->new($ipend->numeric); $i++ ){
	    my $ip;
	    if ( $version == 4 ){
		$ip = NetAddr::IP->new($i) || $class->throw_fatal("Problem creating NetAddr::IP object from $i");
	    }elsif ( $version == 6 ){
		$ip = NetAddr::IP->new6($i) || $class->throw_fatal("Problem creating v6 NetAddr::IP object from $i");
	    }
	    my $decimal = $ip->numeric; # Do not remove.  We need the method value as a scalar
	    my %args = (status      => $argv{status},
			used_by     => $argv{used_by},
			description => $argv{description},
		);
	    $args{parent} = $argv{parent} if defined $argv{parent};
	    if ( my $ipb = Ipblock->search(address=>$decimal, prefix=>$prefix)->first ){
		$ipb->update(\%args);
		push @newips, $ipb;
	    }else{
		$args{address} = $ip->addr;
		push @newips, Ipblock->insert(\%args);
	    }
	}

	#########################################
	# Call the plugin that generates DNS records
	if ( $argv{gen_dns} && $argv{fzone} ){
	    if ( $argv{status} ne 'Dynamic' && $argv{status} ne 'Static' ){
		$class->throw_user("DNS records can only be auto-generated for Dynamic or Static IPs");
	    }
	    my $fzone = Zone->retrieve($argv{fzone});
	    $logger->info("Ipblock::add_range: Generating DNS records: $argv{start} - $argv{end}");
	    $range_dns_plugin->generate_records(prefix=>$argv{name_prefix}, 
						suffix=>$argv{name_suffix}, 
						start=>$ipstart, end=>$ipend, 
						fzone=>$fzone);
	}
	
				  }); # end of transaction

    $logger->info("Ipblock::add_range: Did $argv{status} range: $argv{start} - $argv{end}");

    if ( $argv{parent} ){
	if ( ref($argv{parent}) ){
	    return $argv{parent};
	}else{
	    return Ipblock->retrieve($argv{parent});
	}
    }else{
	# Build hierarchy and return parent block
	my $version = $newips[0]->version;
	$class->build_tree($version);
	if ( my $parent = $newips[0]->parent ){
	    my $id = $parent->id;
	    if ( $id != 0 ){
		return Ipblock->retrieve($id); 
	    }
	}
    }
}


################################################################
=head2 remove_range - Remove a range of addresses
    

  Arguments: 
    Hash with following keys:
      start   - First IP in range
      end     - Last IP in range
  Returns:   
    True
  Examples:
    Ipblock->remove_range(start=>$addr1, end=>addr2);
=cut
sub remove_range{
    my ($class, %argv) = @_;
    $class->isa_class_method('remove_range');

    my $ipstart  = NetAddr::IP->new($argv{start});
    my $ipend    = NetAddr::IP->new($argv{end});
    unless ( $ipstart <= $ipend ){
	$class->throw_user("Invalid range: $argv{start} - $argv{end}");
    }
    
    # We want this to happen atomically (all or nothing)
    eval {
	Netdot::Model->do_transaction(sub {
	    for ( my $i=$ipstart->numeric; $i<=$ipend->numeric; $i++ ){
		my $ip = NetAddr::IP->new($i);
		my $ipb = Ipblock->search(address=>$ip)->first;
		$ipb->delete() if $ipb;
	    }
				      });
    };
    if ( my $e = $@ ){
	$class->throw_user($e);
    }
    $logger->info("Ipblock::remove_range: done with $argv{start} - $argv{end}");
    
}

##################################################################
=head2 matches_cidr - Does the given string match an IPv4 or IPv6 CIDR address

 Arguments: 
    string
 Returns:   
    Array containing address and prefix length, or 0 if no match
 Examples:
    Ipblock->matches_cidr('192.168.1.0/16');

=cut
sub matches_cidr {
    my ($class, $string) = @_;

    if ( $string =~ /^(.+)\/(\d+)$/ ){
	my ($addr, $prefix) = ($1, $2);
	if ( $class->matches_ip($addr) ){
	    return ($addr, $prefix);
	}
    }
    return 0;
}

##################################################################
=head2 matches_ip - Does the given string match an IPv4 or IPv6 address

 Arguments: 
    string
 Returns:   
    1 or 0
 Examples:
    Ipblock->matches_ip('192.168.1.0');

=cut
sub matches_ip {
    my ($class, $string) = @_;

    if ( $class->matches_v4($string) || $class->matches_v6($string) ){
	return 1;
    }
    return 0;
}


##################################################################
=head2 matches_v4 - Does the given string match an IPv4 address

 Arguments: 
    string
 Returns:   
    1 or 0
 Examples:
    Ipblock->matches_v4('192.168.1.0');

=cut
sub matches_v4 {
    my ($class, $string) = @_;

    if ( $string =~ /^$IPV4$/ ) {
	return 1;
    }
    return 0;
}
##################################################################
=head2 matches_ip - Does the given string match an IPv6 address

 Arguments: 
    string
 Returns:   
    1 or 0
 Examples:
    Ipblock->matches_v6('192.168.1.0');

=cut
sub matches_v6 {
    my ($class, $string) = @_;

    if ( $string =~ /^$IPV6$/ ) {
	return 1;
    }
    return 0;
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
    if ( $self->address && $self->prefix ){
	return $self->address . '/' . $self->prefix;
    }else{
	return;
    }
}

##################################################################
=head2 full_address

    Returns the address part in FULL notation for ipV4 and ipV6 respectively.
    See NetAddr::IP::full()

  Arguments:
    None
  Returns:
    string
  Examples:
    print $ipblock->full_address();

=cut
sub full_address {
    my $self = shift;
    $self->isa_object_method('full_address');
    return $self->_netaddr->full()
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

    Host addresses are v4 blocks with a /32 prefix or v6 blocks with a /128 prefix

 Arguments: 
    None
 Returns:   
    1 if block is an address, 0 otherwise

=cut

sub is_address {
    my $self = shift;
    $self->isa_object_method('is_address');

    if ( ($self->version == 4 && $self->prefix == 32) 
	 || ($self->version == 6 && $self->prefix == 128) ){
	return 1; 
    }else{
	return 0;
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
    if ( defined $argv->{validate} ){
	$validate = $argv->{validate};
	delete $argv->{validate};
    }

    my $recursive = delete $argv->{recursive};

    # We need at least these args before proceeding
    # If not passed, use current values
    $argv->{status} ||= $self->status;
    $argv->{prefix} = $self->prefix unless $argv->{prefix};

    if ( $argv->{address} && $argv->{prefix} ){
	my $ip = $class->_prevalidate($argv->{address}, $argv->{prefix});
	if ( my $tmp = $class->search(address => $ip->addr,
				      prefix  => $ip->masklen)->first ){
	    $self->throw_user("Block ".$argv->{address}."/".$argv->{prefix}." already exists in db")
		if ( $tmp->id != $self->id );
	}
    }

    my %state = %$argv;
    $state{status} = $self->_get_status_id($argv->{status});

    # We might need to discard changes.
    # Class::DBI's 'discard_changes' method won't work
    # here because object is changed in the DB
    # (and not in memory) when IP tree is rebuilt.
    #
    # Notice that this would be the perfect place to use DB transactions
    # but the way we do transactions, they cannot be nested, and this
    # method is pretty low level

    my %bak    = $self->get_state();
    my $result = $self->SUPER::update(\%state);

    # This makes sure we have the latest values
    $self = $class->retrieve($self->id);


    # Only rebuild the tree if address/prefix have changed
    if ( $self->address ne $bak{address} || $self->prefix ne $bak{prefix} ){
	$self->_update_tree(old_addr=>$bak{address}, old_prefix=>$bak{prefix});
    }

    # Now check for rules
    # We do it after updating and rebuilding the tree because 
    # it makes things much simpler. Workarounds welcome.
    if ( $validate && ($argv->{address} || $argv->{prefix} || $argv->{status}) ){
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

    # Update DHCP scope if needed
    if ( $self->dhcp_scopes ){
	if ( $self->address ne $bak{address} || $self->prefix ne $bak{prefix} ){
	    my $scope = ($self->dhcp_scopes)[0];
	    $scope->update({ipblock=>$self});
	}
    }
    # Generate hostaudit entry if needed
    if ( $self->parent && $self->parent->dhcp_scopes
	 && ($bak{status}->id != $state{status}) ){
	my $dyn_id = IpblockStatus->search(name=>'Dynamic')->first->id;
	if ( $dyn_id == $bak{status}->id || $dyn_id == $state{status} ){
	    my %args;
	    $args{operation} = 'update';
	    $args{fields} = ('status');
	    $args{values} = ($state{status});
	    $self->_host_audit(%args);
	}
    }
	
    if ( $recursive ){
	my %data = %{ $argv };
	foreach my $key ( keys %data ){
	    if ( $key =~ /^(address|prefix|parent|version|interface|status)$/ ){
		delete $data{$key};
	    }
	}
	$data{recursive} = $recursive;
	$data{validate}  = 0;
	$_->update(\%data) foreach $self->children;
    }

    return $result;
}



##################################################################
=head2 delete - Delete Ipblock object

    We override delete to allow deleting children recursively as an option.
    
  Arguments: 
    recursive      - Remove blocks recursively (default is false)
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
     
    my %bak = $self->get_state();

    if ( $args{recursive} ){
	foreach my $ch ( $self->children ){
	    if ( $ch->id == $self->id ){
		$logger->warn("Ipblock::delete: ".$self->get_label()." is parent of itself!. Removing parent.");
		$self->update({parent=>undef});
	    }
	    $ch->delete(recursive=>1);
	}
    }    
    unless ( $args{no_update_tree} ){
	$self->_tree_delete();
    }

    # Generate hostaudit entry if needed
    if ( blessed($self->parent) && $self->parent->dhcp_scopes ){
	my $dyn_id = IpblockStatus->search(name=>'Dynamic')->first->id;
	if ( $dyn_id == $bak{status}->id ){
	    my %args;
	    $args{operation} = 'delete';
	    $args{fields} = 'all';
	    $args{values} = $self->get_label;
	    $self->_host_audit(%args);
	}
    }

    $self->SUPER::delete();

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

    if ( $self->parent ){
	if ( $self->parent->id == $self->id ){
	    $logger->warn("Ipblock::get_ancestors: ".$self->get_label()." is parent of itself!. Removing parent.");
	    $self->update({parent=>undef});
	    return;
	}
	$logger->debug("Ipblock::get_ancestors: ".$self->get_label()." parent: ".$self->parent->get_label());
	push @$parents, $self->parent;
	$self->parent->get_ancestors($parents);
	return wantarray ? ( @$parents ) : $parents->[0]; 
    }else{
	return;
    }
    return;
}

##################################################################
=head2 get_descendants - Get children recursively
    
 Arguments: 
    None
 Returns:   
    arrayref of descendant children IDs
  Examples:
    my $descendants = $ip->get_descendants();

=cut
sub get_descendants {
    my ($self, $t) = @_;
    $self->isa_object_method('get_descendants');
    my $class = ref($self);
   
    my $tree = $self->_tree_get();
    my $n = $class->_tree_find(address  => $self->address_numeric,
			       prefix   => $self->prefix,
			       tree     => $tree,
	);
    my $list = ();
    my $code = sub { 
	my $node = shift @_; 
	push @$list, $node; 
    };

    $class->_tree_traverse(root=>$n, code=>$code, tree=>$tree);

    return $list;
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
	if ( $self->prefix < 31 ){
	    # Subtract network and broadcast addresses
	    return $class->numhosts($self->prefix) - 2;
	}else{
	    return $class->numhosts($self->prefix);
	}
    }elsif ( $self->version == 6 ) {
	# Notice that the first (subnet-router anycast) and last address 
	# are valid in IPv6
        return $class->numhosts_v6($self->prefix);
    }
}

##################################################################
=head2 num_children - Count number of children

  Arguments:
    None
  Returns:
    Integer

=cut
sub num_children {
    my ($self) = @_;
    $self->isa_object_method('num_children');
    my $dbh = $self->db_Main;
    my $sth;
    eval {
	$sth = $dbh->prepare("SELECT COUNT(id) FROM ipblock WHERE parent=?");
	$sth->execute($self->id);
    };
    $self->throw_fatal("$@") if $@;
    my $num= $sth->fetchrow_array() || 0;
    return $num;
}


##################################################################
=head2 address_usage -  Returns the number of hosts in a given container or subnet

  Arguments:
    None
  Returns:
    integer
  Examples:
    my $count = $ipblock->address_usage();

=cut

sub address_usage {
    my ($self) = @_;
    $self->isa_object_method('address_usage');

    my $start  = $self->_netaddr->network();
    my $end    = $self->_netaddr->broadcast();
    my $count  = 0;
    my $q;
    my $dbh = $self->db_Main;
    eval {
	$q = $dbh->prepare_cached("SELECT ipblock.prefix, ipblock.version, ipblockstatus.name 
                                   FROM   ipblock, ipblockstatus 
                                   WHERE  ipblock.status=ipblockstatus.id 
                                     AND  ? <= address AND address <= ?");
	
	$q->execute(scalar($start->numeric), scalar($end->numeric));
    };
    if ( my $e = $@ ){
	$self->throw_fatal( $e );
    }
    
    while ( my ($prefix, $version, $status) = $q->fetchrow_array() ) {
        if( ( $version == 4 && $prefix == 32 ) || ( $version == 6 && $prefix == 128 ) ) {
	    next if $status eq 'Available';
            $count++;
        }
    }

    return $count;
}

##################################################################
=head2 free_space - The free space in this ipblock

  Arguments:
    Maximum block size to partition space into
  Returns:
    an array (possibly empty) of Netaddr::IP objects that fill in all the
    un-subnetted nooks and crannies of this IPblock
  Examples:
    my @freespace = sort $network->free_space;
=cut

sub free_space {
    my ($self, $divide) = @_;
    $self->isa_object_method('free_space');
    
    sub find_first_one {
        my $num = shift;
        if ($num & 1 || $num == 0) { 
            return 0; 
        } else { 
            return 1 + find_first_one($num >> 1); 
        }
    }

    sub fill { 
        # Fill from the given address to the beginning of the given netblock
        # The block will INCLUDE the first address and EXCLUDE the final block
        my ($from, $to, $divide) = @_;

        if ( $from->within($to) || $from->numeric >= $to->numeric ) {  
            # Base case
            return ();
        }
        
        # The first argument needs to be an address and not a subnet.
        my $curr_addr = $from->numeric;
        my $max_masklen = $from->masklen;
        my $numbits = find_first_one($curr_addr);

        my $mask = $max_masklen - $numbits;
        $mask = $divide if ( $divide && $divide =~ /\d+/ && $divide > $mask && 
			     ( ( $from->version == 4 && $divide <= 32 ) 
			       || ( $from->version == 6 && $divide <= 128 ) ) );

        my $subnet = NetAddr::IP->new($curr_addr, $mask);
        while ($subnet->contains($to)) {
            $subnet = NetAddr::IP->new($curr_addr, ++$mask);
        }
	
        my $newfrom = NetAddr::IP->new(
	    $subnet->broadcast->numeric + 1,
	    $max_masklen
            );
	
        return ($subnet, fill($newfrom, $to, $divide));
    }

    my @kids = map { $_->_netaddr } $self->children;
    my $curr = $self->_netaddr->numeric;
    my @freespace = ();
    foreach my $kid (sort { $a->numeric <=> $b->numeric } @kids) {
        my $curr_addr = NetAddr::IP->new($curr);
	unless ( $kid->numeric >= $curr_addr->numeric ){
	    my $class = ref($self);
	    $class->build_tree($self->version);
	    $self->throw_user("child >= parent: $kid >= $curr_addr. IP hierarchy had to be rebuilt. Go back and try again."); 
	}
	
	if (!$kid->contains($curr_addr)) {
	    foreach my $space (&fill($curr_addr, $kid, $divide)) {
		push @freespace, $space;
	    }
	}
	
        $curr = $kid->broadcast->numeric + 1;
    }

    my $end = NetAddr::IP->new($self->_netaddr->broadcast->numeric + 1);
    my $curr_addr = NetAddr::IP->new($curr);
    map { push @freespace, $_ } &fill($curr_addr, $end, $divide);

    return @freespace;
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
    which can, for example, derive the names from device/interface information.
    
  Arguments:
    Hash with following keys:
       hostname_ips   - arrayref of ip addresses to which main hostname resolves to
       num_ips        - Number of IPs in Device
  Returns:
    True if successful
  Example:
    $self->update_a_records(hostname_ips=>\@ips, num_ips=>$num);

=cut
sub update_a_records {
    my ($self, %argv) = @_;
    $self->isa_object_method('update_a_records');
    
    $self->throw_fatal("Ipblock::update_a_records: Missing required arguments")
	unless ( $argv{hostname_ips} && $argv{num_ips} );
    
    my %hostnameips;
    map { $hostnameips{$_}++ } @{$argv{hostname_ips}};

    unless ( $self->interface && $self->interface->device ){
	# No reason to go further
	$self->throw_fatal(sprintf('update_a_records: Address %s not associated with any Device'), 
			   $self->address);
    } 

    unless ( $self->interface->auto_dns ){
	$logger->debug(sprintf("Interface %s configured for no auto DNS", 
			      $self->interface->get_label));
	return;
    }
    
    my $device = $self->interface->device;
    my $host = $device->fqdn;
    
    # This shouldn't happen
    $self->throw_fatal( sprintf("update_a_records: Device id %d is missing its name!", $device->id) )
	unless $device->name;

    # Only generate names for IP blocks that are mapped to a zone
    my $zone;
    unless ( $zone = $self->forward_zone ){
	$logger->debug(sprintf("%s: Cannot determine DNS zone for IP: %s", 
			       $host, $self->get_label));
	return;
	
    }

    # Determine what DNS name this IP will have.
    # We delegate this logic to an external plugin to
    # give admin more flexibility
    my $name = $ip_name_plugin->get_name( $self );

    my @arecords = $self->arecords;

    my %rrstate = (name=>$name, zone=>$zone, auto_update=>1);

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
	    if ( $rr = RR->search(name=>$name, zone=>$zone)->first ){
		$logger->debug(sub{ sprintf("Ipblock::update_a_records: %s: Name %s: %s already exists.", 
					    $host, $self->address, $name) });
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

		# If this is the only IP, or the snmp_target IP, make sure that it uses 
		# the same record that the device uses as its main name
		if ( $argv{num_ips} == 1 ||
		     ($self->interface->device->snmp_target &&
		      $self->interface->device->snmp_target->id == $self->id) ){
		    
		    if ( $rr->id != $self->interface->device->name->id ){
			$ar->delete;
			RRADDR->insert({rr=>$device->name, ipblock=>$self});
			$logger->info(sprintf("%s: UpdatedDNS A record for main device IP %s: %s", 
					      $host, $self->address, $device->name->name));
		    }
		}else{
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
				$logger->debug(sub{ sprintf("%s: Assigned existing name %s to %s", 
							    $host, $name, $self->address)} );
				
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
				$logger->debug(sub{ sprintf("%s: Updated DNS record for %s: %s", 
							    $host, $self->address, $name) });
			    }
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
	    if ( $ch->interface && $ch->interface->device ){
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


################################################################
=head2 get_last_n_arp - Get last N ARP entries

  Arguments: 
    limit  - Return N last entries (default: 10)
  Returns:   
    Array ref of timestamps, PhysAddr IDs and Interface IDs
  Examples:
    print $ip->get_last_n_arp(10);

=cut
sub get_last_n_arp {
    my ($self, $limit) = @_;
    $self->isa_object_method('get_last_n_arp');
	
    my $dbh = $self->db_Main();
    my $id = $self->id;
    my $q1 = "SELECT   arp.tstamp
              FROM     interface i, arpcacheentry arpe, arpcache arp, ipblock ip
              WHERE    ip.id=$id
                AND    arpe.interface=i.id 
                AND    arpe.ipaddr=ip.id 
                AND    arpe.arpcache=arp.id 
              GROUP BY arp.tstamp 
              ORDER BY arp.tstamp DESC
              LIMIT $limit";

    my @tstamps = @{ $dbh->selectall_arrayref($q1) };
    return unless @tstamps;
    my $tstamps = join ',', map { "'$_'" } map { $_->[0] } @tstamps;

    my $q2 = "SELECT   i.id, p.id, arp.tstamp
              FROM     physaddr p, interface i, arpcacheentry arpe, arpcache arp, ipblock ip
              WHERE    ip.id=$id 
                AND    arpe.physaddr=p.id 
                AND    arpe.interface=i.id 
                AND    arpe.ipaddr=ip.id 
                AND    arpe.arpcache=arp.id 
                AND    arp.tstamp IN($tstamps)
              ORDER BY arp.tstamp DESC";

    return $dbh->selectall_arrayref($q2);
}

################################################################
=head2 shared_network_subnets

    Determine if this subnet shares a physical link with another
    subnet based on router interfaces with multiple subnet addresses.

  Arguments: 
    None
  Returns:   
    Array of Ipblock objects or undef if not sharing a link
  Examples:
    my @shared = $subnet->shared_network_subnets();
=cut
sub shared_network_subnets{
    my ($self, %argv) = @_;
    $self->isa_object_method('shared_network_subnets');
    my $dbh = $self->db_Main();
    
    my $query = 'SELECT  other.id 
                 FROM    ipblock me, ipblock other, ipblock myaddr, ipblock otheraddr 
                 WHERE   me.id=? AND myaddr.parent=? AND otheraddr.parent=other.id 
                     AND me.version = other.version
                     AND myaddr.interface=otheraddr.interface 
                     AND myaddr.interface IS NOT NULL AND other.id!=me.id';

    my $sth = $dbh->prepare_cached($query);
    $sth->execute($self->id, $self->id);
    my $rows = $sth->fetchall_arrayref();
    my @subnets;
    foreach my $row ( @$rows ){
	my $b = Ipblock->retrieve($row->[0]);
	push @subnets, $b if $b->status->name eq 'Subnet';
    }
    
    return @subnets if scalar @subnets;
    return;
}

################################################################
=head2 enable_dhcp
    
    Create a subnet dhcp scope and assign given attributes.
    This method will create a shared-network scope if necessary.

  Arguments: 
    Hash containing the following key/value pairs:
      container       - Container (probably global) Scope
      shared_nets     - Hashref with:
                          key = ipblock id
                          value = hashref with attributes
      attributes      - Optional.  This must be a hashref with:
                          key   = attribute name, 
                          value = attribute value
 
  Returns:   
    Scope object (subnet or shared-network)
  Examples:
    $subnet->enable_dhcp(%options);

=cut
sub enable_dhcp{
    my ($self, %argv) = @_;
    $self->isa_object_method('enable_dhcp');
    
    $self->throw_user("Missing required arguments: container")
	unless (defined $argv{container});

    $self->throw_user("Trying to enable DHCP on a non-subnet block")
	if ( $self->status->name ne 'Subnet' );
    
    my $scope;

    if ( $argv{shared_nets} ){
	# Create a shared-network scope that will contain the other subnet scopes

	$self->throw_fatal("Ipblock::enable_dhcp: Argument shared_nets must be hashref")
	    unless ( ref($argv{shared_nets}) eq 'HASH' );

	my %shared_subnets;
	foreach my $id ( keys %{$argv{shared_nets}} ){
	    my $s = Ipblock->retrieve($id);
	    $self->throw_user("Ipblock::enable_dhcp: Shared network ".$s->get_label." is not a Subnet")
		unless $s->status->name eq 'Subnet';
	    $shared_subnets{$id} = $s;
	}
	# Add this subnet in case it wasn't passed in the list
	$shared_subnets{$self->id} = $self;
	my @shared_subnets = values %shared_subnets;

	# Create the shared-network scope
	my $sn_scope;
	$sn_scope = DhcpScope->insert({type      => 'shared-network',
				       subnets   => \@shared_subnets,
				       container => $argv{container}});
	$scope = $sn_scope;
	
	# Insert a subnet scope for each member subnet
	foreach my $s ( @shared_subnets ){
	    my %args = (container => $sn_scope,
			type      =>'subnet', 
			ipblock   => $s);
	    if ( $s->id == $self->id ){
		$args{attributes} = $argv{attributes};
	    }elsif ( my $attrs = $argv{shared_nets}->{$s->id} ){
		$args{attributes} = $attrs;
	    }
	    $scope = DhcpScope->insert(\%args);
	}
    }else{
	my %args = (container => $argv{container},
		    type      =>'subnet', 
		    ipblock   => $self);
	$args{attributes} = $argv{attributes};
	$scope = DhcpScope->insert(\%args);
    }
    
    return $scope;
}

################################################################
=head2 get_dynamic_ranges - List of dynamic ip address ranges for a given subnet
    
    Used by DHCPD configs

  Arguments: 
    None
  Returns:   
    Array of strings (e.g. "192.168.0.10 192.168.0.20")
  Examples:
    my @ranges = $subnet->get_dynamic_ranges();
=cut
sub get_dynamic_ranges {
    my ($self) = @_;
    $self->isa_object_method('get_dynamic_ranges');
    
    $self->throw_fatal("Ipblock::get_dynamic_ranges: Invalid call to this method on a non-subnet")
	if ( $self->status->name ne 'Subnet' );
    
    my $id        = $self->id;
    my $version   = $self->version;
    my $dbh = $self->db_Main;
    my $rows = $dbh->selectall_arrayref("
                SELECT   ipblock.address 
                 FROM    ipblock,ipblockstatus
                WHERE    ipblock.parent=$id 
                     AND ipblock.status=ipblockstatus.id
                     AND ipblockstatus.name='Dynamic'
                ORDER BY ipblock.address
	");
    my @ips = map { $_->[0] } @$rows;

    my @ranges;
    my ($start, $end, $pos);
    $start = shift @ips;
    $end   = $start;
    foreach my $address ( @ips ){
	if ( $address != $end+1 ){
	    my $sa = Ipblock->int2ip($start, $version);
	    my $ea = Ipblock->int2ip($end, $version);
	    push @ranges, "$sa $ea";
	    $start = $address;
	}
	$end = $address;
    }
    if ( $start && $end ){
	my $sa = Ipblock->int2ip($start, $version);
	my $ea = Ipblock->int2ip($end, $version);
	push @ranges, "$sa $ea";
    }

    return @ranges if scalar @ranges;
    return;
}

################################################################
=head2 dns_zones - Get DNS zones related to this block
    
    If this block does not have zones assigned via the SubnetZone
    join table, this method checks this block's ancestors
    and returns the first set of matching zones

  Arguments: 
    None
  Returns:   
    Array of Zone objects
  Examples:
    my @zones = $ipblock->dns_zones;
=cut
sub dns_zones {
    my ($self) = @_;
    $self->isa_object_method('dns_zones');
    my @szones = $self->zones;
    unless ( @szones ){
	foreach my $p ( $self->get_ancestors ){
	    if ( @szones = $p->zones ){
		last;
	    }
	}
    }
    if ( @szones ){
	return map { $_->zone } @szones;
    }
    return;
}

################################################################
=head2 forward_zone - Find the forward zone for this ip or block
    
  Arguments: 
    None
  Returns:   
    Zone object
  Examples:
    my $zone = $ipb->forward_zone();
=cut
sub forward_zone {
    my ($self) = @_;
    $self->isa_object_method('forward_zone');

    my @list;
    if ( my @zones = $self->dns_zones ){
	foreach my $z ( @zones ){
	    if ( $z->name !~ /\.arpa$|\.int$/ ){
		push @list, $z;
	    }
	}
    }
    wantarray ? ( @list ) : $list[0];
}

################################################################
=head2 reverse_zone - Find the in-addr.arpa zone for this ip or block
    
  Arguments: 
    None
  Returns:   
    Zone object
  Examples:
    my $r_zone = $ipb->reverse_zone();
=cut
sub reverse_zone {
    my ($self) = @_;
    $self->isa_object_method('reverse_zone');

    my $rname = RRPTR->get_name(ipblock=>$self);
    my @zones = Zone->search(name=>$rname);
    return $zones[0];
}

############################################################################
=head2 - get_dot_arpa_names

    Return the corresponding in-addr.arpa or ip6.arpa zone names 
    Supports RFC2317 (Classless IN-ADDR.ARPA delegation) notation

  Args: 
    delim (optional) - Delimiter to separate address and mask in RFC2317 cases
  Returns: 
    Array of strings
  Examples:
    my $name = $block->get_dot_arpa_names()

=cut
sub get_dot_arpa_names {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_dot_arpa_names');
    my $delim = $argv{delim} || '-';
    my @names;
    if ( $self->version == 4 ){
	if ( 0 < $self->prefix && $self->prefix <= 8 ){
	    my @subnets = $self->_netaddr->split(8);
	    foreach my $subnet ( @subnets ){
		push @names, (split(/\./, $subnet->addr))[0];
	    }

	}elsif ( $self->prefix <= 16 ){
	    my @subnets = $self->_netaddr->split(16);
	    foreach my $subnet ( @subnets ){
		push @names, join('.', reverse((split(/\./, $subnet->addr))[0..1]));
	    }	    

	}elsif ( $self->prefix <= 24 ){
	    my @subnets = $self->_netaddr->split(24);
	    foreach my $subnet ( @subnets ){
		push @names, join('.', reverse((split(/\./, $subnet->addr))[0..2]));
	    }	    

	}elsif ( $self->prefix < 32 ){
	    # RFC 2317 case
	    my @octets = split('\.', $self->address);
	    push @names, $octets[3].$delim.$self->prefix.".$octets[2].$octets[1].$octets[0]";

	}else {
	    $self->throw_user('Unexpected prefix length:'.$self->prefix);
	}
	map { $_ .= '.in-addr.arpa' } @names;

    }elsif ( $self->version == 6 ){
	if ( my $rem = $self->prefix % 4 ){
	    # prefix is not a multiple of four
	    my $split_size = $self->prefix - $rem + 4;
	    my @subnets = $self->_netaddr->split($split_size);
	    foreach my $subnet ( @subnets ){
		push @names, &_get_v6_arpa($subnet);
	    }
	}else{
	    push @names, &_get_v6_arpa($self->_netaddr);
	}
    }

    sub _get_v6_arpa {
	my ($netaddr) = @_;
	my $name = $netaddr->full();
	$name =~ s/://g;
	my @nibbles = split(//, $name);
	@nibbles = @nibbles[0..($netaddr->masklen/4)-1];
	$name = join('.', reverse @nibbles);
	return lc("$name.ip6.arpa");
    }
    return @names;
}

##################################################################
=head2 get_host_addrs - Get host addresses for a given block

  Note: This returns the list of possible host addresses in any 
    given IP block, not from the database.

  Arguments:
    Subnet address in CIDR notation (not required if called on an object)
  Returns: 
    Arrayref of host addresses (strings)
  Examples:
    Class method:
      my $hosts = Ipblock->get_host_addrs( $address );
    Instance method:
      my $hosts = $subnet->get_host_addrs();

=cut
sub get_host_addrs {
    my ($self) = shift;
    my $class = ref($self);
    my $subnet;
    if ( $class ){
	$subnet = $self->cidr;
    }else{
	$subnet = shift;
    }
        
    my $s;
    unless( $s = NetAddr::IP->new($subnet) ){
	$class->throw_fatal("Invalid Subnet: $subnet");
    }
    # Populating an array with all addresses in most IPv6 blocks
    # will likely break
    if ( $s->version != 4 ){
	$class->throw_user('This method only supports IPv4 blocks');
    }
    my $hosts = $s->hostenumref();

    # Remove the prefix.  We just want the addresses
    map { $_ =~ s/(.*)\/\d{2}/$1/ } @$hosts;

    return $hosts;
}

################################################################
=head2 get_next_free - Get next free address in this subnet

  Arguments: 
    Hash with following keys:
      strategy (first|last)
  Returns:   
    Address string or undef if none available
  Examples:
    my $address = $subnet->get_next_free()
=cut
sub get_next_free {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_next_free');
    my $class = ref($self);
    $self->throw_user("Invalid call to this method on a non-subnet")
	unless ( $self->status->name eq 'Subnet' );

    $logger->debug("Getting next free address in ".$self->get_label);

    my $dbh  = $self->db_Main();
    my $id   = $self->id;
    my $rows = $dbh->selectall_arrayref("
               SELECT   ipblock.address, ipblockstatus.name
               FROM     ipblock, ipblockstatus
               WHERE    ipblock.status=ipblockstatus.id
                 AND    ipblock.parent=$id
               ");

    my %used;
    foreach my $row ( @$rows ){
	my ($numeric, $status) = @$row;
	next unless ( $numeric && $status );
	$used{$numeric} = $status;
    }

    my $strategy = $argv{strategy} || Netdot->config->get('IP_ALLOCATION_STRATEGY');

    my $s = $self->_netaddr;
    if ( $strategy eq 'first' ){
	for ( my $addr=Math::BigInt->new($s->first->numeric); $addr <= $s->last->numeric; $addr++ ){
	    return &_do_addr($class, $addr, \%used, $self->version);
	}
    }elsif ( $strategy eq 'last' ){
	for ( my $addr=Math::BigInt->new($s->last->numeric); $addr >= $s->first->numeric; $addr-- ){
	    return &_do_addr($class, $addr, \%used, $self->version);
	}	
    }else{
	$self->throw_fatal("Ipblock::get_next_free: Invalid strategy: $strategy");
    }

    sub _do_addr(){
	my ($class, $addr, $used, $version) = @_;
	# Ignore anything that exists, unless it's marked as available
	next if (exists $used->{$addr} && $used->{$addr} ne 'Available');
	if ( my $ipb = Ipblock->search(address=>$addr)->first ){
	    # IP may have been incorrectly set as Available
	    # Correct and move on
	    if ( $ipb->arecords || $ipb->dhcp_scopes ){
		$ipb->update({status=>'Static'});
		next;
	    }else{
		return $class->int2ip($addr, $version);
	    }
	}else{
	    return $class->int2ip($addr, $version);
	}
    }
}

##################################################################
=head2 get_addresses_by - Different sorts for ipblock_list page

   Arguments: 
     sort field (Address|Name|Status|Used By|Description|Last Seen)     
  Returns:   
    arrayref of arrayrefs
  Examples:
    my $rows = $subnet->get_addresses_by('Address')

=cut
sub get_addresses_by {
    my ($self, $sort) = @_;
    $self->isa_object_method('get_addresses_by');
    $self->throw_fatal("Ipblock::get_addresses_by: Invalid call to this method for a non-subnet")
	unless ( $self->status && $self->status->name eq 'Subnet' );
    
    $sort ||= 'Address';
    my %sort2field = ('Address'     => 'ipblock.address',
		      'Name'        => 'rr.name',
		      'Status'      => 'ipblockstatus.name',
		      'Used by'     => 'entity.name',
		      'Description' => 'ipblock.description',
		      'Last Seen'   => 'ipblock.last_seen',
	);
    unless ( exists $sort2field{$sort} ){
	$self->throw_fatal("Ipblock::get_addresses_by: Invalid sort string");
    }
    my $id = $self->id;
    my $query = "    
    SELECT    DISTINCT(ipblock.id)
    FROM      ipblockstatus, ipblock 
    LEFT JOIN (rraddr, rr) ON (rraddr.ipblock=ipblock.id AND rraddr.rr=rr.id)
    LEFT JOIN entity ON (ipblock.used_by=entity.id)
    WHERE     ipblock.parent=$id
      AND     ipblock.status=ipblockstatus.id
    ORDER BY  $sort2field{$sort}";

    my $dbh  = $self->db_Main();
    my $rows = $dbh->selectall_arrayref($query);
    my @objects;
    map { push @objects, Ipblock->retrieve($_->[0]) } @$rows;
    return @objects;
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

    unless ( $class->matches_ip($address) ) {
	$class->throw_user("IP: $address does not match valid patterns");
    }

    if ( $address eq '0.0.0.0' || $address eq '::' ){
	$class->throw_user("The unspecified IP: $address is not valid");
    }

    my $ip;
    my $str = ( $address && $prefix ) ? (join('/', $address, $prefix)) : $address;
    if ( !($ip = NetAddr::IP->new($address, $prefix)) || $ip->numeric == 0 ){
	$class->throw_user("Invalid IP: $str");
    }

    # Make sure that what we're working with the base address
    # of the block, and not an address within the block
    unless( $ip->network == $ip ){
	$class->throw_user("IP: $str is not base address of block");
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
    $logger->debug(sub{"Ipblock::_validate: Checking " . $self->get_label });
		   
    my $statusname = $self->status->name || "unknown";
    $logger->debug("Ipblock::_validate: " . $self->get_label . " has status: $statusname");

    my ($pstatus, $parent);
    if ( ($parent = $self->parent) && $parent->id ){
	$logger->debug("Ipblock::_validate: " . $self->get_label . " parent is ", $parent->get_label);
	
	if ( $parent->status && ($pstatus = $parent->status->name)) {
	    if ( $self->is_address() ){
		if ( $pstatus eq "Reserved" ){
		    $self->throw_user($self->get_label.": Address allocations not allowed under Reserved blocks");
		}elsif ( $pstatus eq 'Subnet' && $self->version == 4 && $parent->prefix != 31 ){
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
    }else{
	$logger->debug("Ipblock::_validate: " . $self->get_label . " does not have parent");
    }
    if ( $statusname eq "Subnet" ){
	# We only want addresses inside a subnet. 
	foreach my $ch ( $self->children ){
	    unless ( $ch->is_address() ){
		my $err = sprintf("%s %s cannot exist within Subnet %s", 
				  $ch->status->name, $ch->get_label, $self->get_label);
		$self->throw_user($err);
	    }
	}
    }elsif ( $statusname eq "Reserved" ){
	if ( $self->children ){
	    $self->throw_user($self->get_label.": Reserved blocks can't contain other blocks");
	}
    }elsif ( $statusname eq "Dynamic" ) {
	unless ( $self->is_address($self) ){
	    $self->throw_user($self->get_label.": Only addresses can be set to Dynamic");
	}
	unless ( $pstatus eq "Subnet" ){
	    $self->throw_user($self->get_label.": Dynamic addresses must be within Subnet blocks");
	}
	unless ( $parent->dhcp_scopes ){
	    $self->throw_user($self->get_label.": You need to enable DHCP in this subnet before adding any dynamic addresses");
	}

    }elsif ( $statusname eq "Static" ) {
	unless ( $self->is_address($self) ){
	    $self->throw_user($self->get_label.": Only addresses can be set to Static");
	}

    }elsif ( $statusname eq "Available" ) {
	unless ( $self->is_address($self) ){
	    $self->throw_user($self->get_label.": Only addresses can be set to Available");
	}
	if ( $self->arecords || $self->dhcp_scopes ){
	    $self->throw_user($self->get_label.": Available addresses cannot have A records or DHCP scopes");
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
#     Array with:
#     - Hashref with current parent data
#     - Hashref with new parent data
#   Examples:
#     Ipblock->_build_tree_mem('4');
#
sub _build_tree_mem {
    my ($class, $version) = @_;
    $class->isa_class_method('_build_tree_mem');

    unless ( $version =~ /^4|6$/ ){
	$class->throw_user("Invalid IP version: $version");
    }
    my $tree = Net::IPTrie->new(version=>$version);
    $class->throw_fatal("Error initializing IP Trie") unless defined $tree;

    $logger->debug(sub{ sprintf("Ipblock::_build_tree_mem: Building hierarchy for IPv%d space", 
				$version) });

    # We override Class::DBI for speed.
    # The other trick is to insert all the non-addresses in the tree first,
    # and for the addresses, we only do a search, which avoids
    # traversing the whole tree section between the smallest block
    # and the address.  All we need is the smallest covering block
    my $dbh = $class->db_Main;
    my $sth;
    
    my $size = ( $version == 4 ) ? 32 : 128;
    
    $sth = $dbh->prepare_cached("SELECT   id,address,prefix,parent 
                                 FROM     ipblock 
                                 WHERE    version = $version
                                 ORDER BY prefix");	
    $sth->execute();

    my %current_parents;
    
    my %parents;
    while ( my ($id, $address, $prefix, $parent) = $sth->fetchrow_array ){
	$current_parents{$id} = $parent;
	if ( $prefix == $size ){
	    my $node =  $class->_tree_find(address => $address, 
					   prefix  => $prefix,
					   tree    => $tree,
		);
	    
	    $parents{$id} = (defined $node && $node->data)? $node->data : undef;
	}else{
	    my $node =  $class->_tree_insert(address => $address, 
					     prefix  => $prefix, 
					     data    => $id,
					     tree    => $tree,
		);
	    $parents{$id} = (defined $node && $node->parent)? $node->parent->data : undef;
	}
    }

    
    $class->_tree_save(version=>$version, tree=>$tree);

    return (\%parents, \%current_parents);
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
    my ($self, %argv) = @_;
    $self->isa_object_method('_update_tree');
    my $class = ref($self);
    my $version = $self->version;
    my $tree = $self->_tree_get();

    $logger->debug('Ipblock::_update_tree: Updating tree for '. $self->get_label);

    if ( $self->is_address ){
        # Search the tree.  
        my $n = $class->_tree_find(address => $self->address_numeric,
                prefix  => $self->prefix,
                tree    => $tree,
                );

        # Get parent id
        if ( $n ){
            my $parent;
            if ( $n->data == $self->id ) {
                $parent = $n->parent->data if ( $n && $n->parent );
                $logger->debug("Ipblock::_update_tree: ". $self->get_label ." is in tree");
            }else{
                $parent = $n->data if ( $n->data );
                $logger->debug("Ipblock::_update_tree: ". $self->get_label ." not in tree");
            }
            $self->SUPER::update({parent=>$parent}) if $parent;
        }
    }else{
        # Search by id, and get a list back of matching nodes
        #  then, iterate through them and delete any where the
        #  address doesn't match the current address
        if ($argv{old_addr}) {
            $logger->debug("Ipblock::_update_tree: deleting old address at " . $argv{old_addr} . "/". $argv{old_prefix});
            my $n = $class->_tree_find(str_address => $argv{old_addr}, 
                                       prefix=> $argv{old_prefix},
                                       tree=> $tree);

            if ($n) {
                $n->delete();
            }
        }

    # This is a new block (subnet, container, etc)
    # Insert it in the tree
    my $n = $class->_tree_insert(address => $self->address_numeric,
            prefix  => $self->prefix, 
            data    => $self->id,
            tree    => $tree,
            );

    if ( defined $n && $n->parent && $n->parent->data ){
        my $parent_id = $n->parent->data;
        if ( $parent_id == $self->id ){
            $logger->debug("Ipblock::_update_tree: mask probably changed. Deleting parent node.");
            if ( $n->parent->parent ){
                $parent_id = $n->parent->parent->data;
            }else{ 
                $parent_id = undef;
            }
            $n->parent->delete();
        }

        $logger->debug("Ipblock::_update_tree: ". $self->get_label ." within: $parent_id");
        my %parents;
        $parents{$self->id} = $parent_id;

# Now, deal with my children and my parent's children
# They could be my children or my siblings, so
# we need to rebuild this section of the tree

        my $dbh = $class->db_Main;
	    my $sth1 = $dbh->prepare_cached("SELECT   id,address,prefix,parent 
                                            FROM     ipblock 
                                            WHERE    parent=?
                                               OR    parent=?
					    ORDER BY prefix"
		);
	    $sth1->execute($parent_id, $self->id);
	    while ( my ($id,$address,$prefix,$par) = $sth1->fetchrow_array ){
		my $node;
		# We do not insert end nodes in the tree for speed
		# See _build_tree_mem
		if ( ($version == 4 && $prefix == 32) || ($version == 6 && $prefix == 128) ){
		    $node = $class->_tree_find(address  => $address,
					       prefix   => $prefix,
					       tree     => $tree,
		    );
		    if ( defined $node && $node->data != $par ){
			$logger->debug("Ipblock::_update_tree: node $id has new parent");
			$parents{$id} = $node->data;
		    }
		}else{
		    $node = $class->_tree_insert(address  => $address,
						 prefix   => $prefix,
						 data     => $id,
						 tree     => $tree,
			);
		    if ( defined $node && $node->parent 
			 && $node->parent->data != $par ){
			$logger->debug("Ipblock::_update_tree: node $id has new parent");
			$parents{$id} = $node->parent->data;
		    }
		}
	    }
	    # Now update the DB
	    foreach my $id ( keys %parents ){
		Ipblock->retrieve($id)->update({parent=>$parents{$id}});
	    }
	}else{
	    # This could be a root covering other blocks, so we 
	    # need to build the whole tree
	    $logger->debug("Ipblock::_update_tree: ". $self->get_label ." not within any known blocks");
	    $class->build_tree($self->version);
	}
    }
    
    $class->_tree_save(version=>$self->version, tree=>$tree);
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
#     $ip->_tree_delete();
#
sub _tree_delete{
    my ($self) = @_;
    $self->isa_object_method('_tree_delete');
    my $class = ref($self);

    my $tree = $self->_tree_get();

    if ( ! $self->is_address ){
	# This is a block (subnet, container, etc)
	# Assign all my children my current parent
	if ( my $parent = $self->parent ){
	    my $dbh = $class->db_Main;
	    my $sth = $dbh->prepare_cached("UPDATE ipblock SET parent=? WHERE parent=?");
	    $sth->execute($parent->id, $self->id);
	}
	# Remove this node from the trie
	my $n = $class->_tree_find(address  => $self->address_numeric,
				   prefix   => $self->prefix,
				   tree     => $tree,
	    );
	if ( $n && ($n->data == $self->id) ){
	    $n->delete();
	    $class->_tree_save(version=>$self->version, tree=>$tree);
	}
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
#     tree    - Net::IPTrie object
#   Returns:
#     Tree node
#   Examples:
#    
#
sub _tree_insert{
    my ($class, %argv) = @_;
    $class->isa_class_method('_tree_insert');
    $class->throw_fatal("Missing required arguments")
	unless ( $argv{address} && $argv{tree} );

    my %args = ( iaddress=>$argv{address} );
    $args{prefix} = $argv{prefix} if $argv{prefix};
    $args{data}   = $argv{data}   if $argv{data};

    my $tree = $argv{tree}; 
    
    my $n = $tree->add(%args);
    return $n;
}

##################################################################
# Find a node in the memory tree
#
#   Arguments:
#     address (optoinal - numeric)
#     data (optional - either address or data must be defined)
#     prefix (optional - defaults to host mask)
#     tree - Net::IPTrie object
#   Returns:
#     Tree node
#     Or
#     Arrayref of tree nodes
#   Examples:
#    
#
sub _tree_find{
    my ($class, %argv) = @_;
    $class->isa_class_method('_tree_find');
    $class->throw_fatal("Ipblock::_tree_find: Missing required arguments")
	unless ( (($argv{address} || $argv{str_address}) || $argv{data}) && $argv{tree} );

    my $tree = $argv{tree};

    my $n;
    my $l = ();

    if ($argv{address} || $argv{str_address}) {
      my %args = {};
      if ($argv{address}) {
        $args{iaddress} = $argv{address};
      } else {
        $args{address} = $argv{str_address};
      }
      $args{prefix} = $argv{prefix} if defined $argv{prefix};

      $n = $tree->find(%args);
    } elsif ($argv{data}) {
      # create code to iterate through the tree, and push all nodes
      #  on to the list we return
      my $code = sub {
        my $node = $_[0];
        if ($argv{data} == $node->data) {
	  push @$l, $node;
        }
      };

      $tree->traverse(code=>$code);
    }

    # if we dont have data defined, we must have had an address
    #  so return the single node
    if (!$argv{data}) {
      return $n;
    }

    # if we have $n and data defined, join them
    if ($n && $argv{data}) {
      push @$l, $n;
    }

    return $l;
    
}

##################################################################
# Traverse tree starting at given node
#
#   Arguments:
#     tree - Net::IPTrie object
#     root
#     coderef
#   Returns:
#     Nothing
#   Examples:
#    
#
sub _tree_traverse{
    my ($class, %argv) = @_;
    $class->isa_class_method('_tree_traverse');
    $class->throw_fatal("Ipblock::_tree_traverse: Missing required arguments")
	unless ( $argv{root} && $argv{tree} );

    my $tree = $argv{tree};
    $tree->traverse(root=>$argv{root}, code=>$argv{code});
    
    return 1;
}

##################################################################
#
sub _tree_save {
    my ($class, %argv) = @_;
    $class->throw_fatal("Ipblock::_tree_save: Missing required arguments")
	unless ( $argv{version} && $argv{tree} );

    unless ( ref($argv{tree}) eq 'Net::IPTrie' ){
	$class->throw_fatal("Ipblock::_tree_save: invalid tree object");
    }
    my $frozen = nfreeze($argv{tree});
    my $name = 'iptree'.$argv{version};
    my $cache;
    unless ( $cache = DataCache->find_or_create({name=>$name}) ){
	$class->throw_fatal("Could not find or create cache entry for IP tree: $name");
    }
    $cache->update({data=>$frozen, tstamp=>time});
    $logger->debug("Ipblock::_tree_save: Saved $name");
    return 1;
}

##################################################################
#
sub _tree_get {
    my ($self, $version) = @_;
    my $class = ref($self) || $self;
    
    if ( ref($self) ){
	$version = $self->version;
    }else{
	$class->throw_fatal("Ipblock::_tree_get: Missing required".
			    " arg: 'version' when called as class method")
	    unless ($version);
    }

    my $tree;
    my $name = 'iptree'.$version;
    my $TTL = $self->config->get('IP_TREE_TTL');
    for ( 1..2 ){
	my $cache = DataCache->search(name=>$name)->first;
	if ( defined $cache && (time - $cache->tstamp) < $TTL ){ 
	    $tree = thaw $cache->data;
	    $logger->debug("Ipblock::_tree_get: $name thawed from cache");
	    my $tree_class = ref($tree);
	    if ( $tree_class eq 'Net::IPTrie' ){
		$logger->debug("Ipblock::_tree_get: Retrieved $name");
		return $tree;
	    }else{
		$logger->debug("Not a valid ($name) in cache: ($tree_class). Rebuilding");
		$class->_build_tree_mem($version);
	    }
	}else{
	    $logger->debug("Ipblock::_tree_get: $name expired or not yet built");
	    $class->_build_tree_mem($version);
	}
    }
    $self->throw_fatal("Could not get a valid $name from cache");
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
    $self->throw_fatal("Invalid object") unless $self;

    return unless ( $self->id );

    my $dbh  = $self->db_Main;
    my $id   = $self->id;

    if ( my ($address) = ($dbh->selectrow_array("SELECT address FROM ipblock WHERE id=$id"))[0] ){
	my $val = $self->int2ip($address, $self->version);
	$self->_attribute_store( address => $val );    
    }
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

# Make sure to return 1
1;
