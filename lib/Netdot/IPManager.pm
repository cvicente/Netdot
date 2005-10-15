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
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    
    $self = $self->SUPER::new( %argv );
    
    # Max number of blocks returned by search functions
    $self->{config}->{'MAXSEARCHBLOCKS'} = 200;

    wantarray ? ( $self, '' ) : $self; 
}


=head2 sortblocks - Sort Ipblocks by address

 Arguments: Array of Ipblock objects
 Returns:   Sorted array of Ipblock objects

=cut

sub sortblocks {
    my ($self, @blocks) = @_;
    my %ints;
    foreach my $ipblock ( @blocks ){
	my $int = $self->ip2int($ipblock->address);
	$ints{$int} = $ipblock;
    }
    my @sorted = map { $ints{$_} } sort keys %ints;
    return @sorted;
}


=head2 searchblocks_addr -  Search IP Blocks by address
 Arguments: address and (optional) prefix
 Returns: array of Ipblock objects

=cut

sub searchblocks_addr {
    my ($self, $address, $prefix) = @_;
    my ($ip, @ipb);
    $self->debug(loglevel => 'LOG_DEBUG',
		 message => "searchblock: args: %s, %s" ,
		 args => [$address, $prefix]);
    unless ( $ip = $self->_prevalidate($address, $prefix) ){
	my $msg = sprintf("%s", $self->error);
	$self->error($msg);
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
    @ipb = $self->sortblocks(@ipb);
    wantarray ? ( @ipb ) : $ipb[0]; 

}

=head2 searchblocks_regex - Search IP Blocks that match the specified regular expression


 Arguments: address regular expression
 Returns:   array of Ipblock objects

=cut

sub searchblocks_regex {
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
    @ipb = $self->sortblocks(@ipb);
    wantarray ? ( @ipb ) : $ipb[0]; 

}

=head2 searchblocks_other - Search IP Blocks by Entity, Site, Description and Comments

 Arguments: string or substring
 Returns: array of Ipblock objects

=cut

sub searchblocks_other {
    my ($self, $string) = @_;
    my $crit = "%" . $string . "%";

    my @sites    = Site->search_like  (name => $crit );
    my @ents     = Entity->search_like(name => $crit );
    my %blocks;  # Hash to prevent dups
    map { $blocks{$_} = $_ } Ipblock->search_like(description => $crit);
    map { $blocks{$_} = $_ } Ipblock->search_like(info        => $crit);

    map { push @ents, $_->entity } 
    map { $_->entities } @sites; 

    map { $blocks{$_} = $_ } 
    map { $_->subnets } @ents;
    
    my @ipb = map { $blocks{$_} } keys %blocks;

    if (scalar (@ipb) > $self->{config}->{'MAXSEARCHBLOCKS'}){
	$self->error("Too many entries. Please refine search");
	return;
    }
    @ipb = $self->sortblocks(@ipb);
    wantarray ? ( @ipb ) : $ipb[0]; 

}

=head2 get_covering_block - Get the closest available block that contains a given block

When a block is searched and not found, it is useful to show the closest existing block
that would contain it.  The fastest way to do it is inserting it, building the IP tree,
retrieving the parent, and then removing it.

 Arguments: IP address and prefix 
 Returns:   Ipblock object or 0 if not found

=cut

sub get_covering_block {
    my ($self, $address, $prefix) = @_;
    my ($ip, $parent);
    unless ( $ip = $self->_prevalidate($address, $prefix) ){
	my $msg = sprintf("%s", $self->error);
	$self->error($msg);
	return 0;
    }
    if ( Ipblock->search(address => ($ip->numeric)[0], prefix => $ip->masklen) ){
	my $msg = sprintf("Block %s/%s exists in db.  Using wrong method!", $ip->addr, $ip->masklen);
	$self->error($msg);
	return 0;
    }
    my %state = ( address       => $ip->addr, 
		  prefix        => $ip->masklen,
		  version       => $ip->version );
    
    if ( my $r = $self->insert( table => "Ipblock", state => \%state) ){
	$self->debug(loglevel => 'LOG_DEBUG',
		     message  => "get_covering_block: Temporarily inserted %s/%s",
		     args     => [$ip->addr, $ip->masklen]);

	return 0 unless ( $self->build_tree($ip->version) );

	my $ipblock = Ipblock->retrieve($r);
	if ( ($parent = $ipblock->parent) != 0 ){
	    $self->debug(loglevel => 'LOG_DEBUG',
			 message  => "get_covering_block: Found parent %s/%s",
			 args     => [$parent->address, $parent->prefix]);
	}else{
	    $self->debug(loglevel => 'LOG_DEBUG',
			 message  => "get_covering_block: Found no parent for %s/%s",
			 args     => [$ipblock->address, $ipblock->prefix]);
	    # Have to explicitly set to zero because Class::DBI returns
	    # an empty (though non-null) object
	    $parent = 0;
	}
	unless ( $self->remove( table => "Ipblock", id => $r ) ){
	    my $msg = sprintf("get_covering_block: Could not remove %s/%s: %s!", $ip->addr, $ip->masklen);
	    $self->error($msg);
	    return 0;
	}
	$self->debug(loglevel => 'LOG_DEBUG',
		     message  => "get_covering_block: Removed %s/%s",
		     args     => [$ip->addr, $ip->masklen]);

	return 0 unless ( $self->build_tree($ip->version) );
	return $parent;
    }else{
	my $msg = sprintf("get_covering_block: Could not insert %s/%s: %s!", 
			  $ip->addr, $ip->masklen, $self->error);
	$self->error($msg);
	return 0;
    }
    return 0;
}


=head2 getrootblocks  - Get a list of root blocks

  Args:     IP version [4|6|all]
  Returns:  Array of Ipblock objects, ordered by prefix length
    
=cut

sub getrootblocks {
    my ($self, $version) = @_;
    my @ipb;
    if ( $version =~ /^4|6$/ ){
	@ipb = Ipblock->search(version => $version, parent => 0, {order_by => 'address'});
    }elsif ( $version eq "all" ){
	@ipb = Ipblock->search(parent => 0, {order_by => 'address'});
    }else{
	$self->error("Unknown version: $version");
	return;
    }
    wantarray ? ( @ipb ) : $ipb[0]; 
}

=head2 getchildren - Get all blocks that are children of this block in the IP tree
    
=cut
    
sub getchildren {
    my ($self, $id) = @_;
    my @ipb = Ipblock->search(parent => $id, {order_by => 'address'});
    wantarray ? ( @ipb ) : $ipb[0]; 
}

=head2 getparents - Get parents recursively
    
Arguments: Ipblock object
Returns:   Array of ancestor Ipblock objects, in order

=cut

sub getparents {
    my ($self, $ipblock, @parents) = @_;
    my $par;
    if ( ($par = $ipblock->parent) != 0 ){
	push @parents, $par;
	@parents = $self->getparents($par, @parents);
    }
    wantarray ? ( @parents ) : $parents[0]; 
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

=head2 _prevalidate - Validate block before creating and updating

These checks are related to basic IP addressing rules

  Arguments:
    ip address and prefix
    prefix can be null.  NetAddr::IP will assume it is a host (/32 or /128)
  Returns:
    NetAddr::IP object or 0 if failure

=cut

sub _prevalidate {
    my ($self, $address, $prefix) = @_;
    my $ip;
    unless ( $address ){
	$self->error("_prevaliate: Address arg is required");
	return 0;		
    }
    unless ( $address =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/ ||
	     $address =~ /:/){
	$self->error("Invalid IP: $address");
	return 0;		
    }
    if ( !($ip = NetAddr::IP->new($address, $prefix)) ||
	 $ip->numeric == 0 ){
	my $str = ( $address && $prefix ) ? (join '/', $address, $prefix) : $address;
	$self->error(sprintf("Invalid IP: %s ", $str));
	return 0;	
    }

    # Make sure that what we're inserting is the base address
    # of the block, and not an address within the block
    unless( $ip->network == $ip ){
	$self->error("Invalid IP: $address/$prefix");
	return 0;		
    }
    if ( $ip->within(new NetAddr::IP "127.0.0.0", "255.0.0.0") 
	 || $ip eq '::1' ) {
	$self->error("IP is a loopback");
	return 0;	
    }
    return $ip;
}


=head2 _validate - Validate block when creating and updating

This method assumes the block has already been inserted in the DB (and the
binary tree has been updated).  This facilitates the checks.
These checks are more specific to the way Netdot manages the address space.

  Arguments:
    ARGS    - Hash ref of arguments passed to insertblock/updateblock. 
  Returns:
    True or False
=cut

sub _validate {
    my ($self, $args) = @_;
    my $ipblock;
    unless ( $ipblock = Ipblock->retrieve( $args->{id} ) ){
	$self->error("Cannot retrieve Ipblock id: $args->{id}");
	return 0;
    }
    # Values are what the block is being set to
    # or what it already has
    $args->{statusname}    ||= $ipblock->status->name;
    $args->{dhcp_enabled}  ||= $ipblock->dhcp_enabled;
    $args->{dns_delegated} ||= $ipblock->dns_delegated;
    
    my ($pstatus, $parent);
    if ( ($parent = $ipblock->parent) && $parent->id ){
	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "_validate: %s/%s has parent: %s/%s",
		     args => [$ipblock->address, $ipblock->prefix, 
			      $parent->address, $parent->prefix ]);
	
	$pstatus = $parent->status->name;
	if ( $self->isaddress($ipblock ) ){
	    if ($pstatus eq "Reserved" ){
		$self->error("Address allocations not allowed under Reserved blocks");
		return 0;	    
	    }
	    my ($ip, $pip);
	    if ( ($ip = NetAddr::IP->new($ipblock->address, $ipblock->prefix)) &&
		 ($pip = NetAddr::IP->new($parent->address, $parent->prefix))  ){ 
		if ( $pip->network->broadcast->addr eq $ip->addr ) {
		    my $msg = sprintf("Address is broadcast for %s/%s: ",$parent->address, $parent->prefix);
		    $self->debug(loglevel => 'LOG_NOTICE', message => $msg);
		    $self->error($msg);
		    return 0;	
		}
	    }else{
		$self->debug(loglevel => 'LOG_NOTICE',
			     message => "_validate: %s/%s or %s/%s not valid?",
			     args => [$ipblock->address, $ipblock->prefix,
				      $parent->address, $parent->prefix]);
	    }
	    
	}else{
	    if ($pstatus ne "Container" ){
		$self->error("Block allocations only allowed under Container blocks");
		return 0;	    
	    }	    
	}
    }
    if ( $args->{statusname} eq "Subnet" ){
	foreach my $ch ( $ipblock->children ){
	    unless ( $self->isaddress($ch) || $ch->status->name eq "Container" ){
		my $err = sprintf("%s %s/%s cannot exist within Subnet %s/%s", 
				  $ch->status->name, $ch->address, $ch->prefix, 
				  $ipblock->address, $ipblock->prefix);
		$self->error($err);
		return 0;
	    }
	    if ( $ch->status->name eq "Container" ){
		my ($addr, $prefix) = ($ch->address, $ch->prefix);
		unless ( $self->removeblock( id => $ch->id ) ){
		    return 0;
		}
		$self->debug(loglevel => 'LOG_NOTICE',
			     message => "_validate: Container %s/%s has been removed",
			     args => [$addr, $prefix ]);
	    }
	}
    }elsif ( $args->{statusname} eq "Container" ){
	if ( $args->{dhcp_enabled} ){
		$self->error("Can't enable DHCP in Container blocks");
		return 0;	    
	}
    }elsif ( $args->{statusname} eq "Reserved" ){
	if ( $ipblock->children ){
	    $self->error("Reserved blocks can't contain other blocks");
	    return 0;
	}
	if ( $args->{dhcp_enabled} ){
		$self->error("Can't enable DHCP on Reserved blocks");
		return 0;	    	    
	}
	if ( $args->{dns_delegated} ){
		$self->error("Can't delegate DNS on Reserved blocks");
		return 0;	    	    
	}
    }elsif ( $args->{statusname} eq "Dynamic" ) {
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
    }elsif ( $args->{statusname} eq "Static" ) {
	unless ( $self->isaddress($ipblock) ){
	    $self->error("Only addresses can be set to Static");
	    return 0;	    
	}
    }
    return 1;
}

=head2 insertblock -  Insert a new block

Required Arguments: 
    address       ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
Optional Arguments:
    prefix        dotted-quad mask or prefix length (default is /32 or /128)
    status        id of IpblockStatus - or - 
    statusname    name of IpblockStatus
    entity        Who uses the block
    interface     id of Interface where IP was found
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
    $args{dhcp_enabled}  ||= 0; 
    $args{dns_delegated} ||= 0; 
    $args{entity}        ||= 0; 
    
    # $ip is a NetAddr::IP object;
    my $ip;
    unless ( $ip = $self->_prevalidate($args{address}, $args{prefix}) ){
	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "insertblock: could not validate: %s/%s: %s" ,
		     args => [$args{address}, $args{prefix}, $self->error]);
	return 0;
    }
    if ( Ipblock->search(address => ($ip->numeric)[0], prefix => $ip->masklen) ){
	my $msg = sprintf("Block %s/%s already exists in db", $ip->addr, $ip->masklen);
	$self->error($msg);
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
		  dhcp_enabled  => $args{dhcp_enabled},
		  dns_delegated => $args{dns_delegated},
		  entity        => $args{entity},
		  first_seen    => $self->timestamp,
		  last_seen     => $self->timestamp,
		  );
    
  
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
	unless ( $self->_validate(\%args) ){
	    my $msg = sprintf("insertblock: could not validate: %s/%s: %s", $ip->addr, $ip->masklen, $self->error);
	    $self->debug(loglevel => 'LOG_DEBUG',
			 message => $msg);
	    $self->remove( table => "Ipblock", id => $r );
	    $self->error($msg);
	    return 0;
	}
	my $newblock = Ipblock->retrieve($r);

	# Inherit some of parent's values if it's not an address
	if ( !$self->isaddress($newblock) && ($newblock->parent != 0) ){
	    my %state = ( dns_delegated => $newblock->parent->dns_delegated, 
			  entity        => $newblock->parent->entity );
	    unless ( $self->update( object=> $newblock, state => \%state ) ){
		$self->debug(loglevel => 'LOG_ERR',
			     message => "insertblock: could not inherit parent values!");
	    }
	}
	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "insertblock: inserted %s/%s" ,
		     args => [$newblock->address, $newblock->prefix]);
	# This is a funny hack to avoid the address being shown in numeric.
	# Maybe a Class::DBI issue?  
	undef $newblock;
	$newblock = Ipblock->retrieve($r);
	return $newblock;
    }else{
	return 0;
    }
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
    entity        Who uses the block
    dhcp_enabled  Include in DHCP config
    dns_delegated Create necessary NS records
Returns: 
    Updated Ipblock object
    False if error

=cut

sub updateblock {
    my ($self, %args) = @_;
    unless ( exists $args{id} ){
	$self->error("Missing required args");
	return 0;	
    }
    my $ipblock;
    unless ($ipblock = Ipblock->retrieve($args{id})){
	$self->error("Ipblock id $args{id} not in db");
	return 0;
    }
    # We need at least these two args before proceeding
    # If not passed, use current values
    $args{address} ||= $ipblock->address;
    $args{prefix}  ||= $ipblock->prefix;
    my $ip;
    unless ( $ip = $self->_prevalidate($args{address}, $args{prefix}) ){
	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "updateblock: could not validate: %s/%s: %s" ,
		     args => [$args{address}, $args{prefix}, $self->error]);
	return 0;
    }
    if ( my $tmp = (Ipblock->search(address => ($ip->numeric)[0], 
				   prefix => $ip->masklen))[0] ){
	if ( $tmp->id != $args{id} ){
	    $self->error("Block $args{address}/$args{prefix} already exists in db");
	    return 0;
	}
    }
    # Determine Status.  It can be either a name
    # or a IpblockStatus id
    # 
    my $stobj;
    my $statusid;
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
    my %state;
    foreach my $key ( keys %args ){
	if ( $key eq 'status' || $key eq 'statusname' ){
	    $state{status} = $statusid;
	}else {
	    $state{$key} = $args{$key};
	}
    }
    # Check that we actually have something to change
    my $change = 0;
    foreach my $key (keys %state){
	if ( int($ipblock->$key) ne $state{$key} ){
	    $change = 1;
	    last;
	}
    }
    if ( ! $change ){
	return $ipblock;
    }

    $state{last_seen} = $self->timestamp;

    # We might need to discard changes.
    # Class::DBI's 'discard_changes' method won't work
    # here.  Probably because object is changed in DB
    # (and not in memory) when IP tree is rebuilt.

    my %bak = $self->getobjstate( $ipblock );

    unless ( $self->update( object=>$ipblock, state=>\%state ) ){
	$self->error("Error updating Ipblock object: $@");
	return 0;
    }
    # Rebuild tree
    unless ( $self->build_tree($ip->version) ){
	# Go back to where we were
	unless ( $self->update( object=>$ipblock, state=>\%bak ) ){
	    $self->error("Error discarding changes: $self->error");
	    return 0;
	}
	return 0;
    }
    #####################################################################
    # Now check for rules
    # We do it after updating because it makes things much simpler.  
    # Workarounds welcome.
    #####################################################################
    unless ( $self->_validate(\%args) ){
	$self->debug(loglevel => 'LOG_DEBUG',
		     message => "updateblock: could not validate: %s/%s: %s" ,
		     args => [$ipblock->address, $ipblock->prefix, $self->error]);
	# Go back to where we were
	unless ( $self->update( object=>$ipblock, state=>\%bak ) ){
	    $self->error("Error discarding changes: $self->error");
	    return 0;
	}
	# 
	# Rebuild tree
	unless ( $self->build_tree($ip->version) ){
	    return 0;
	    # Error should be set
	}
	return 0;
	# Error should be set
    }
    return $ipblock;
}



=head2 removeblock -  Remove IP block

  Arguments: 
    id        id of Ipblock object - or -
    address   ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
    prefix    dotted-quad mask or prefix length
    recursive Remove blocks recursively (default is false)
  Returns:
    True or False

=cut

sub removeblock {
    my ($self, %args) = @_;
    my $id;
    my $o;
    my $rec = $args{recursive} || 0;
    my $stack = $args{stack}   || 0;

    unless ( $args{id} || ( $args{address} && $args{prefix} ) ){
	$self->error("removeblock: Missing required args");
	return 0;	
    }
    if ( $args{id} ){
	$id = $args{id};
	unless ( $o = Ipblock->retrieve($id) ){
	    $self->error("removeblock: Ipblock id $id does not exist");
	    return 0
	    }
    }else{
	unless ($o = $self->searchblock($args{address}, $args{prefix})){
	    return 0;
	}
	$id = $o->id;
    }
    my $version = $o->version;

    if ( $rec ){
	foreach my $ch ( $o->children ){
	    unless ( $self->removeblock(id => $ch->id, recursive => 1, stack=>$stack+1) ){
		return 0;
	    }
	}
    }

    $self->debug(loglevel => 'LOG_DEBUG',
		 message => "removeblock: removing: %s/%s" ,
		 args => [$o->address, $o->prefix]);

    unless ($self->remove(table => 'Ipblock', id => $id)){
	$self->error(sprintf("removeblock: %s", $self->error));
	return 0;
    }
    # We check if this is the first call in the stack
    # to avoid rebuilding the tree unnecessarily
    if ( $stack == 0 ){
	unless ( $self->build_tree($version) ){
	    return 0;
	    # Error should be set
	}
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
    my $wantaddress = 0;
    $strategy ||= "first";

    unless ( $strategy =~ /^first|last$/ ){
	$self->error("strategy must be either 'first' or 'last'");	
	return 0;
    }
    unless ( $parent = Ipblock->retrieve($parentid) ){
	$self->error("Cannot retrieve Ipblock id $parentid: $@");
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
    
    # IPv6 addresses don't fit in ints.
    use bigint;

    # Given an address 

    # b1...bn/n 

    # where bi is the ith bit, n is the mask length, and v is the
    # total number of bits (e.g. 128 for IPv6) we want to find a free
    # block of the form

    # b_1..b_n x_{n+1}..x_m/m

    # where m is $length.  So, we need to try all combinations of bits
    # x_{n+1}...x_m.  There are 2^(m - n) combinations of m - n bits.
    # We will iterate over them via addition.  The increment must be
    # shifted so that it corresponds to the lowest bit in the x bits,
    # i.e. the bit labled x_m, which the is v - m + 1st bit from from
    # the right and so corresponds to the number 1 << (v - m).
    my $increment = 2**($parent_nip->bits - $length);
    my $min_ip    = $parent_nip;
    my $total_ips = 2**($length - $parent_nip->masklen);
    my $max_ip    = $min_ip + ($total_ips - 1)*$increment; # -1 since we start with the first address.
    my $start_ip  = $min_ip;
    if ($strategy eq "last") {
	$start_ip   = $max_ip;
	$increment *= -1;
    }

    # Will still be painfully slow if we iterate over a bunch of ips,
    # e.g. if given /n someone allocates an /n+1 and then an /n+k with
    # the same strategy then the attempt to allocate the /n+k will
    # iterate over all 2^(k-1) /n+k s which correspond to the /n+1.
    # To get around this we need to look at the children which exist
    # before proceding blindly.
    for ( my $i = 0; $i < $total_ips; ++$i ) {
	my $block = NetAddr::IP->new ( ($start_ip + $i*$increment)->addr, $length );

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
	    my %state = (address       => $block->addr, 
			 prefix        => $block->masklen,
			 statusname    => $status);

	    if ( $newblock = $self->insertblock(%state) ){
		
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
    my $sth;
    eval {
	$sth = $self->{dbh}->prepare("SELECT id,address,prefix,parent 
                                     FROM Ipblock 
                                     WHERE version = $version 
                                     ORDER BY prefix");	
	$sth->execute;
    };
    if ($@){
	$self->error("$@");
	return 0;
    }
    
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
    eval {
	$sth = $self->{dbh}->prepare("UPDATE Ipblock SET parent = ? WHERE id = ?");
	foreach (keys %parents){
	    $sth->execute($parents{$_}, $_);
	}
    };
    if ($@){
	$self->error("$@");
	return 0;
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


