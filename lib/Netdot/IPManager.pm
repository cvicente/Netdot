package Netdot::IPManager;

=head1 NAME

Netdot::IPManager - IP Address Space Functions for Netdot

=head1 SYNOPSIS

  use Netdot::IPManager

  $ipm = Netdot::IPManager->new();  

=cut

use lib "PREFIX/lib";

use base qw( Netdot );
use NetAddr::IP;
use strict;

#Be sure to return 1
1;

=head1 METHODS

=head2 new - Create a new IP object

  $ipm = Netdot::IPManager->new();  

=cut

sub new { 
    my $proto = shift;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new();

    # Some operations require a lot of speed.  We override 
    # Class::DBI to avoid any overhead in certain cases
    eval {
	$self->{dbh} = Netdot::DBI->db_Main();
    };
    if ( $@ ){
	$self->error(sprintf("Can't get db handle: %s\n", $@));
	return 0;
    }
    # Max number of blocks returned by search functions
    $self->{config}->{'MAXSEARCHBLOCKS'} = 200;

    wantarray ? ( $self, '' ) : $self; 
}


=head2 searchblock -  Search IP Blocks
 Arguments: address and (optional) prefix
 Returns: Ipblock object

=cut

sub searchblock {
    my ($self, $address, $prefix) = @_;
    my ($ip, @ipb);
    $self->debug(loglevel => 'LOG_DEBUG',
		 message => "searchblock: args: %s, %s" ,
		 args => [$address, $prefix]);
    unless ($ip = NetAddr::IP->new($address, $prefix)){
	$self->error(sprintf("Invalid address: %s/%s", $address, $prefix));
	return;
    }
    $self->debug(loglevel => 'LOG_DEBUG',
		 message => "searchblock: NetAddr::IP object: %s, %s" ,
		 args => [$ip->addr, $ip->masklen]);
    
    if ($prefix){
	@ipb = Ipblock->search( address => ($ip->numeric)[0], 
				prefix  => $ip->masklen,
				);
    }else{
	@ipb = Ipblock->search( address => ($ip->numeric)[0] );
    }
    $self->debug(loglevel => 'LOG_DEBUG',
		 message => "searchblock: Search returned: %s entries" ,
		 args => [scalar @ipb]);
    
    if (scalar (@ipb) > $self->{config}->{'MAXSEARCHBLOCKS'}){
	$self->error("Too many entries. Please refine search");
	return;
    }    
    wantarray ? ( @ipb ) : $ipb[0]; 

}

=head2 searchblockslike - Search IP Blocks that match certain address substring

 Arguments: address string or substring
 Returns: Ipblock objects

=cut

sub searchblockslike {
    my ($self, $string) = @_;
    my @ipb;
    my $it = Ipblock->retrieve_all;
    while (my $ipb = $it->next){
	$_ = $ipb->address . '/' . $ipb->prefix;
	push @ipb, $ipb if (/$string/);
	if (scalar (@ipb) > $self->{config}->{'MAXSEARCHBLOCKS'}){
	    $self->error("Too many entries. Please refine search");
	    return;
	}
    }
    wantarray ? ( @ipb ) : $ipb[0]; 

}

=head2 getrootblocks  - Get a limited list of root blocks

  Returns:  Array of Ipblock objects, ordered by prefix length
    
=cut

sub getrootblocks {
    my ($self) = @_;
    my @ipb;
    
    eval {
	@ipb = Ipblock->search_roots();
    };
    if ($@){
	$self->error($@);
    }
    wantarray ? ( @ipb ) : $ipb[0]; 
}

=head2 getchildren - Get a block s children
    
=cut
    
sub getchildren {
    my ($self, $id) = @_;
    my @ipb;
    eval {
	@ipb = Ipblock->search_children($id);
    };
    if ($@){
	$self->error("getchildren: $@");
	return;
    }
    wantarray ? ( @ipb ) : $ipb[0]; 
    
}

=head2 issubnet - Is Ipblock a subnet?

Arguments: Ipblock object
Returns: 0 (is address) or 1 (is subnet)

=cut

sub isaddress {
    my ($self, $o) = @_;
    if ( ($o->version == 4 && $o->prefix < 32) 
	 || ($o->version == 6 && $o->prefix < 128) ){
	return 0; 
    }else{
	return 1;
    }
}

=head2 getsubnetaddr - Get subnet address

   my $subnetaddr = $ipm->getsubnetaddr( address => $addr
					 prefix  => $prefix );

Arguments: 
  $address: ipv4 or ipv6 address
  $prefix:  dotted-quad netmask or prefix length
Returns: 
  subnet address

=cut

sub getsubnetaddr {
    my ($self, $address, $prefix) = @_;
    my $ip;
    unless($ip = NetAddr::IP->new($address, $prefix)){
	$self->error("Invalid IP: $address/$prefix");
	return 0;	
    }
    return $ip->network->addr;
    
}
=head2 insertblock -  Insert a new block

Required Arguments: 
    address       ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
Optional Arguments:
    prefix        dotted-quad mask or prefix length (default is /32 or /128)
    status        id of IpblockStatus - or - 
    statusname    name of IpblockStatus
    interface     id of Interface where IP was found
    monitored     whether should be monitored by an NMS
    dhcp_enabled  Include in DHCP config
    dns_delegated Create necessary NS records
Returns: 
    New Ipblock object or 0

=cut

sub insertblock {
    my ($self, %args) = @_;
    my $stobj;
    my $statusid;
    unless ( exists($args{address}) ){
	$self->error("Missing required arg 'address' ");
	return 0;	
    }
    $args{prefix}        ||= undef;
    $args{statusname}    ||= "Container";
    $args{interface}     ||= 0; 
    $args{monitored}     ||= 0; 
    $args{dhcp_enabled}  ||= 0; 
    $args{dns_delegated} ||= 0; 

    my $ip;
    unless( $ip = NetAddr::IP->new($args{address}, $args{prefix}) ){
	$self->error("Invalid IP: $args{address}/$args{prefix}");
	return 0;	
    }
    if ( Ipblock->search(address => ($ip->numeric)[0], prefix => $ip->masklen) ){
	$self->error("Block already exists in db");
	return 0;
    }
    if ( $ip->within(new NetAddr::IP "127.0.0.0", "255.0.0.0") 
	 || $ip eq '::1' ) {
	$self->error("IP is a loopback: ", $ip->addr, "/", $ip->masklen);
	return 0;	
    }elsif ( ( ($ip->version == 4 && $ip->masklen != 32) ||
	       ($ip->version == 6 && $ip->masklen != 128) ) && 
	     $ip->network->broadcast == $ip ) {
	$self->error("Address is broadcast: ", $ip->addr, "/", $ip->masklen);
	return 0;	
    }
    # Determine Status.  It can be either a name
    # or a IpblockStatus id
    # 
    if ( $args{statusname} ){
	unless ( $stobj = (IpblockStatus->search(name => $args{statusname}))[0] ){
	    $self->error("Status $args{statusname} not known");
	    return 0;
	}
	$statusid = $stobj->id;
    }elsif ( $args{status} ){
	unless ( $stobj = IpblockStatus->retrieve( $args{status} ) ){
	    $self->error("Status $args{status} not known");
	    return 0;
	}	
	$statusid = $args{status};
	$args{statusname}  = $stobj->name; # use for validation
    }

    my %state = ( address       => $ip->addr, 
		  prefix        => $ip->masklen,
		  version       => $ip->version,
		  status        => $statusid,
		  interface     => $args{interface},
		  monitored     => $args{monitored},
		  dhcp_enabled  => $args{dhcp_enabled},
		  dns_delegated => $args{dns_delegated},
		  );
    
    $state{first_seen} = $self->timestamp;
    $state{last_seen}  = $self->timestamp;
  
    if ( my $r = $self->insert( table => "Ipblock", state => \%state)){
	# 
	# Rebuild tree
	unless ( $self->build_tree($ip->version) ){
	    return 0;
	    # Error should be set
	}
	#####################################################################
	# Now check for rules
	# We do it after inserting because having the object
	# makes things much simpler.  Workarounds welcome.
	#####################################################################
	$args{id} = $r;
	unless ( $self->_validateblock(\%args) ){

	    $self->debug(loglevel => 'LOG_DEBUG',
			 message => "insertblock: could not validate: %s/%s" ,
			 args => [$ip->addr, $ip->masklen]);

	    $self->remove( table => "Ipblock", id => $r );
	    return 0;
	}
	my $newblock = Ipblock->retrieve($r);

	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "insertblock: inserted %s/%s" ,
		     args => [$newblock->address, $newblock->prefix]);

	return $newblock;
    }else{
	return 0;
    }
}

=head2 changeblock - Change an existing block to something else

 Arguments: 
  id: id of existing Ipblock object
  address: ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
  prefix:  dotted-quad mask or prefix length
 Returns: 
    Changed Ipblock object
    False if error

=cut 

sub changeblock {
    my ($self, %args) = @_;
    unless ( $args{id} && $args{address} && $args{prefix} ){
	$self->error("Missing required args");
	return 0;	
    }
    my $ipblock;
    unless ($ipblock = Ipblock->retrieve($args{id})){
	$self->error("Ipblock id $args{id} not in db");
	return 0;
    }
    # Do some validation
    my $ip;
    unless($ip = NetAddr::IP->new($args{address}, $args{prefix})){
	$self->error("Invalid IP: $args{address}/$args{prefix}");
	return 0;	
    }
    if ( $ip->within(new NetAddr::IP "127.0.0.0", "255.0.0.0") 
	 || $ip eq '::1' ) {
	$self->error("Address is loopback: $args{address}");
	return 0;	
    }elsif ( $ip->network->broadcast == $ip ) {
	$self->error("Address is broadcast: $args{address}");
	return 0;	
    }
    my %state = ( address => $args{address},
		  prefix  => $args{prefix} );

    unless ( $self->update( object => $ipblock, state => \%state)){
	$self->error($self->error);
	return 0;
    }
    return $ipblock;

}

=head2 updateblock -  Update existing IP block


Required Arguments: 
    id           id of existing Ipblock object
Optional Arguments:
    address       ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
    prefix        dotted-quad mask or prefix length
    status        id or name of IpblockStatus
    statusname     name of IpblockStatus
    interface     id of Interface where IP was found
    monitored     Whether should be monitored by an NMS
    entity        Who uses the block
    dhcp_enabled  Include in DHCP config
    dns_delegated Create necessary NS records
Returns: 
    Updated Ipblock object
    False if error

=cut

sub updateblock {
    my ($self, %args) = @_;
    my $stobj;
    my $statusid;
    unless ( exists $args{id} ){
	$self->error("Missing required args");
	return 0;	
    }
    my $ipblock;
    unless ($ipblock = Ipblock->retrieve($args{id})){
	$self->error("Ipblock id $args{id} not in db");
	return 0;
    }
    # Determine Status.  It can be either a name
    # or a IpblockStatus id
    # 
    if ( $args{statusname} ){
	unless ( $stobj = (IpblockStatus->search(name => $args{statusname}))[0] ){
	    $self->error("Status $args{statusname} not known");
	    return 0;
	}
	$statusid = $stobj->id;
    }elsif ( $args{status} ){
	unless ( $stobj = IpblockStatus->retrieve( $args{status} ) ){
	    $self->error("Status $args{status} not known");
	    return 0;
	}	
	$statusid = $args{status};
	$args{statusname}  = $stobj->name; # use for validation
    }
    #####################################################################
    # Now check for rules
    #####################################################################
    unless ( $self->_validateblock(\%args) ){
	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "updateblock: could not validate: %s/%s" ,
		     args => [$ipblock->address, $ipblock->prefix]);
	return 0;
	# Error should be set
    }

    my %state;
    foreach my $key ( keys %args ){
	if ( $key eq 'status' || $key eq 'statusname' ){
	    $state{status} = $statusid;
	}elsif ( $key eq 'last_seen' ){
	    $state{last_seen} = $self->timestamp;
	}else {
	    $state{$key} = $args{$key};
	}
    }
    unless ( $self->update( object => $ipblock, state => \%state)){
	return 0;
    }
    return $ipblock;
}

=head2 _validateblock - Validate blocks before creating and updating

  Arguments:
    ARGS    - Hash ref of arguments passed to insertblock/updateblock. 
  Returns:
    True or False
=cut

sub _validateblock {
    my ($self, $argsref) = @_;
    my %args = %{ $argsref };
    my $ipblock;
    eval {
	$ipblock = Ipblock->retrieve( $args{id} );
	};
    if ( $@ ){
	$self->error("Cannot retrieve ipblock: $@");
	return 0;
    }
    # Values are what the block is being set to
    # or what it already has
    $args{statusname}    ||= $ipblock->status->name;
    $args{dhcp_enabled}  ||= $ipblock->dhcp_enabled;
    $args{dns_delegated} ||= $ipblock->dns_delegated;
    $args{monitored}     ||= $ipblock->monitored;
    
    my $pstatus;
    if ( $ipblock->parent && $ipblock->parent->id ){
	$pstatus = $ipblock->parent->status->name;
	if ( $self->isaddress($ipblock ) ){
	    if ($pstatus eq "Reserved" ){
		$self->error("Address allocations not allowed under Reserved blocks");
		return 0;	    
	    }
	}else{
	    if ($pstatus ne "Container" ){
		$self->error("Block allocations only allowed under Container blocks");
		return 0;	    
	    }	    
	}
    }
    if ( $args{statusname} eq "Subnet" ){
	foreach my $ch ( $ipblock->children ){
	    unless ( $self->isaddress($ch) ){
		$self->error("Subnet blocks can only contain addresses");
		return 0;
	    }
	}
    }elsif ( $args{statusname} eq "Container" ){
	if ( $args{dhcp_enabled} ){
		$self->error("Can't enable DHCP in Container blocks");
		return 0;	    
	}
    }elsif ( $args{statusname} eq "Reserved" ){
	if ( $ipblock->children ){
	    $self->error("Reserved blocks can't contain other blocks");
	    return 0;
	}
	if ( $args{dhcp_enabled} ){
		$self->error("Can't enable DHCP on Reserved blocks");
		return 0;	    	    
	}
	if ( $args{dns_delegated} ){
		$self->error("Can't delegate DNS on Reserved blocks");
		return 0;	    	    
	}
    }elsif ( $args{statusname} eq "Dynamic" ) {
	unless ( $self->isaddress($ipblock) ){
	    $self->error("Only addresses can be set to Dynamic");
	    return 0;	    
	}
	unless ( $pstatus eq "Subnet" ){
		$self->error("Dynamic addresses must be within Subnet blocks");
		return 0;	    
	}
	unless ( $ipblock->parent->dhcp_enabled ){
		$self->error("Parent Subnet must have DHCP enabled");
		return 0;	    
	}
    }elsif ( $args{statusname} eq "Static" ) {
	unless ( $self->isaddress($ipblock) ){
	    $self->error("Only addresses can be set to Static");
	    return 0;	    
	}
    }
    if ( $args{monitored} ){
	unless ( $self->isaddress($ipblock) ){
	    $self->error("Only addresses can be monitored");
	    return 0;	    
	}
    }
    return 1;
}

=head2 removeblock -  Remove IP block

  Arguments: 
    id       id of Ipblock object - or -
    address  ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
    prefix   dotted-quad mask or prefix length
  Returns:
    True or False

=cut

sub removeblock {
    my ($self, %args) = @_;
    my $ipb;
    my $id;
    unless ( $args{id} || ( $args{address} && $args{prefix} ) ){
	$self->error("removeblock: Missing required args");
	return 0;	
    }
    if ( $args{id} ){
	$id = $args{id};
    }else{
	unless ($ipb = $self->searchblock($args{address}, $args{prefix})){
	    return 0;
	}
	$id = $ipb->id;
    }
    # Retrieve object
    my $o;
    unless ( $o = Ipblock->retrieve($id) ){
	$self->error("Ipblock id $id does not exist");
	return 0
    }
    my $version = $o->version;

    unless ($self->remove(table => 'Ipblock', id => $id)){
	$self->error(sprintf("removeblock: %s", $self->error));
	return 0;
    }
    # 
    # Rebuild tree
    unless ( $self->build_tree($version) ){
	return 0;
	# Error should be set
    }

    return 1;
}

=head2 auto_allocate -  Auto-Allocate Block

Given a parent block, and the wanted length, this function will
split the block in sub-blocks of said length and return the first
available one.  The 'strategy' option will decide whether the 
block is the first one from the beginning, or from the end.

Arguments: 
  parentid: parent Ipblock id
  length:   prefix length
  strategy: 
            'first': First available block of size $length (default)
            'last':  Last available block of size $length

 Returns: New Ipblock object

=cut

sub auto_allocate {
    my ($self, $parentid, $length, $strategy) = @_;
    my $parent;
    my $wantaddress;
    $strategy ||= "first";

    unless ( $strategy eq "first" || $strategy eq "last" ){
	$self->error("strategy must be either 'first' or 'last'");	
	return 0;
    }
    unless ( $parent = Ipblock->retrieve($parentid) ){
	$self->error("Cannot retrieve $parentid: $@");
	return 0;
    }    
    # NetAddr::IP's split() method takes too long to split a 
    # /48 into 2^16 /64's (not to blame).
    # TODO: Write a simpler binary tree method to solve this

    if ($parent->version != 4){
	$self->error("auto_allocate: Currently, only IPv4 is allowed");
	return 0;
    }    
    $self->debug(loglevel => 'LOG_DEBUG',
		 message => "auto_allocate: parent: %s/%s, len: %s, strategy: %s" ,
		 args => [$parent->address, $parent->prefix, $length, $strategy]);

    if ($parent->prefix >= $length){
	$self->error("New block's prefix must be longer than parent's");
	return 0;
    }    
    if ( ( $parent->version == 4 && $length == 32 ) || 
	 ( $parent->version == 6 && $length == 128 ) ){
	$wantaddress = 1;
    }
    if ( $wantaddress ){
	# Only under Subnet
	unless ( $parent->status->name eq "Subnet" ){
	$self->error("Address allocations only permitted within 'Subnet' blocks");
	return 0;	    
	}
    }else{ # want a block
	# Only under Container
	unless ( $parent->status->name eq "Container" ){
	$self->error("Block allocations only permitted within 'Container' blocks");
	return 0;	    
	}
    }
    my $parent_nip;
    unless ( $parent_nip = NetAddr::IP->new($parent->address, $parent->prefix) ){
	$self->error("Invalid parent's address: $parent->address/$parent->prefix");
	return 0;
	
    }
    $self->debug(loglevel => 'LOG_DEBUG',
		 message => "auto_allocate: parent net: %s, broadcast: %s" ,
		 args => [$parent_nip->network, $parent_nip->broadcast]);
    
    # Calculate all sub-blocks of length $length and sort them
    my $sort;
    if ($strategy eq "first"){
	$sort = sub { $a->[1] <=> $b->[1] };
    }elsif ($strategy eq "last"){
	$sort = sub { $b->[1] <=> $a->[1] };	    
    }
    my @blocks = 
	map  { $_->[0] }
    sort $sort
	map  { [$_, ($_->numeric)[0]] } $parent_nip->split($length);
    
    # Return first available valid block.
    #
    foreach my $block (@blocks){
	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "auto_allocate: trying %s/%s" ,
		     args => [$block->addr, $block->masklen]);
	# No network and broadcast addrs
	if ( $wantaddress ){
	    if ( $block->addr eq $parent_nip->network->addr ||
		 $block->addr eq $parent_nip->broadcast->addr ){
		next;
	    }
	}
	# Container blocks are considered free
	if (my $ipblock = (Ipblock->search( address => ($block->numeric)[0], 
					    prefix  => $block->masklen,
					    ))[0] ){
	    if ( $ipblock->status->name eq "Container" ){
		return $ipblock;
	    }
	}else{
	    # Doesn't exist, so go ahead
	    my $status = ($wantaddress) ? "Static" : "Subnet";
	    my $newblock;
	    # Inherit parent's 'dns_delegated' flag
	    if ( $newblock = 
		 $self->insertblock(address       => $block->addr, 
				    prefix        => $block->masklen,
				    statusname    => $status,
				    dns_delegated => $parent->dns_delegated,
				    ) ){
		
		$self->debug(loglevel => 'LOG_NOTICE',
			     message => "auto_allocate: returned %s/%s" ,
			     args => [$newblock->address, $newblock->prefix]);
		
		return $newblock;
	    }
	    $self->debug(loglevel => 'LOG_ERR',
			 message => "auto_allocate: Could not insert block: %s/%s: %s" ,
			 args => [$block->addr, $block->masklen, $self->error]);
	    
	}
    }
    $self->error("No /$length blocks available");
    return 0;
}


=head2 build_tree -  Builds the IPv4 or IPv6 space tree

A very fast, simplified digital tree (or trie) that sets
the dependencies of ipblock objects.

Arguments: IP space version (4/6)

=cut

sub build_tree { 
    my ($self, $version) = @_;
    unless ($version == 4 || $version == 6){
	$self->error("Invalid IP version: $version");
	return 0;
    }
    my $size = ($version == 4)? 32 : 128;
    my $trie = {};
    my %parents;
    # Override Class::DBI for speed.
    my $sth = $self->{dbh}->prepare("SELECT id,address,prefix,parent 
                                     FROM Ipblock 
                                     WHERE version = $version 
                                     ORDER BY prefix");	
    $sth->execute;
    
    while (my ($id,$address,$prefix,$parent) = $sth->fetchrow_array){
	my $p = $trie;
	my $bit = $size;
	my $last_p;
	while ($bit > $size - $prefix){
	    $bit--;
	    $last_p = $p->{id} if defined $p->{id};
	    #
	    # If we reach a subnet leaf, all /32s (or /128s) below it
	    # don't need to be inserted.  Purpose is to find parents
	    last if (defined $last_p && $prefix == $size && !(keys %$p));
	    my $r = ($address & 2**$bit)/2**$bit;
	    if (! exists $p->{$r} ){
		$p->{$r} = {};	
	    }
	    $p = $p->{$r};
	    $p->{id} = $id if ($bit == $size - $prefix);
	}    
	# Parent is the last valid node known
	$parents{$id} = $last_p if ($parent != $last_p);
    }
    undef $sth;
    $sth = $self->{dbh}->prepare("UPDATE Ipblock SET parent = ? WHERE id = ?");
    foreach (keys %parents){
	$sth->execute($parents{$_}, $_);
    }
    return 1;
}

=head2 subnet_num_addr - Return the number of usable addresses in a subnet

Arguments:
    Ipblock object
Returns:
    Integer

=cut


sub subnet_num_addr {
    my ($self, $o) = @_;
    my $ip;
    unless ($ip = NetAddr::IP->new($o->address, $o->prefix)){
	$self->error(sprintf("Invalid address: %s/%s", $o->address, $o->prefix));
	return;
    }
    # For some reason, NetAddr::IP counts the network address
    # 
    return $ip->num - 1;
    
}
