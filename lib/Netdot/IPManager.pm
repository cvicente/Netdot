package Netdot::IPManager;

use lib "PREFIX/lib";

use base qw( Netdot );
use Netdot::DBI;
use Netdot::UI;
use NetAddr::IP;
use strict;

#Be sure to return 1
1;


#####################################################################
# Constructor
# 
#####################################################################
sub new { 
    my $proto = shift;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    wantarray ? ( $self, '' ) : $self; 
}



#####################################################################
# IP to Integer Converter
# Arguments: dotted-quad address
# Returns: Integer
#####################################################################
#sub ip2int {
#    my ($self, $address) = @_;
#    my $ip = NetAddr::IP->new($address);
#    unless ($ip){
#	return 0;
#    }
#    return ($ip->numeric)[0];
#}

#####################################################################
# Sort IPblock objects by ip address
# Arguments: arrayref of Ipblock objects
# Returns: Integer
#####################################################################
sub sortblocks {
    my ( $self, $objects) = @_;
    @{$objects} = 
	map  { $_->[0] }
    sort { $a->[1] <=> $b->[1] }
    map  { [$_->[0], $_->[1]->numeric()] }
    map  { [$_, NetAddr::IP->new($_->address)] } @{$objects};
    return $objects;
}

#####################################################################
# Search IP Block
# Arguments: address and (optional) prefix
# Returns: Ipblock object
#####################################################################
sub searchblock {
    my ($self, $address, $prefix) = @_;
    my $ip;
    unless ($ip = NetAddr::IP->new($address, $prefix)){
	$self->error("Invaild address: $address");
	return 0;
    }
    if ( my $ipb = (Ipblock->search( {address => ($ip->numeric)[0], 
				      prefix  => $ip->masklen} ))[0] ){
	return $ipb;
    }
    $self->error(sprintf("%s/%s not found", $ip->addr, $ip->prefix));
    return 0;
}

#####################################################################
# Is Ipblock a subnet?
# Arguments: IPblock object
# Returns: 0 (is address) or 1 (is subnet)
#####################################################################
sub issubnet {
    my ($self, $o) = @_;
    if ( ($o->version == 4 && $o->prefix < 32) 
	 || ($o->version == 6 && $o->prefix < 128) ){
	return 1; 
    }else{
	return 0;
    }
}

#####################################################################
# Get subnet address
# Arguments: 
#  $address: ipv4 or ipv6 address
#  $prefix:  dotted-quad netmask or prefix length
# Returns: 0 (is address) or 1 (is subnet)
#####################################################################
sub getsubnetaddr {
    my ($self, $address, $prefix) = @_;
    my $ip;
    unless($ip = NetAddr::IP->new($address, $prefix)){
	$self->error("Invalid IP: $address/$prefix");
	return 0;	
    }
    return $ip->network->addr;
    
}

#####################################################################
# Insert a new block
# Required Arguments: 
#   address: ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
#   prefix:  dotted-quad mask or prefix length
# Optional Arguments:
#   status: id of IpblockStatus
#   interface: id of Interface where IP was found
#   manual (bool): inserted manually or automatically
# Returns: New Ipblock object
#####################################################################
sub insertblock {
    my ($self, %args) = @_;
    my $status;
    unless ( exists($args{address}) && exists($args{prefix}) ){
	$self->error("Missing required args 'address and/or 'prefix' ");
	return 0;	
    }
    $args{status}    ||= 0;
    $args{interface} ||= 0; 
    $args{manual}    ||= 0; 
    if ($self->searchblock($args{address}, $args{prefix})){
	$self->error("Block already exists in db");
	return 0;
    }
    my $ip;
    unless($ip = NetAddr::IP->new($args{address}, $args{prefix})){
	$self->error("Invalid IP: $args{address}/$args{prefix}");
	return 0;	
    }
    if ( $ip->within(new NetAddr::IP "127.0.0.0", "255.0.0.0") 
	 || $ip eq '::1' ) {
	$self->error("IP is a loopback: ", $ip->addr, "/", $ip->masklen);
	return 0;	
    }
    unless ($status = (IpblockStatus->search(name => $args{status}))[0]){
	$self->error("Status $args{status} not known");
	return 0;		
    }
    my $ui = Netdot::UI->new();
    my %state = ( address  => $ip->addr, 
		  prefix   => $ip->masklen,
		  version  => $ip->version,
		  status    => $status,
		  interface => $args{interface},
		  );
   
    $state{last_seen} = $ui->timestamp if (! $args{manual} );
		  
    my $r;		  
    if ( $r = $ui->insert( table => "Ipblock", state => \%state)){
	return (my $o = Ipblock->retrieve($r)) ;
    }else{
	$self->error($ui->error);
	return 0;
    }
}
#####################################################################
# Update existing block
# Arguments: 
#   id: id of existing Ipblock object
#   address: ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
#   prefix:  dotted-quad mask or prefix length
# Optional Arguments:
#   status: id of IpblockStatus
#   interface: id of Interface where IP was found
# Returns: New Ipblock object
#####################################################################
sub updateblock {
    my ($self, %args) = @_;
    my ($ipblock, $status);
    unless ( exists($args{id}) && exists($args{address}) && exists($args{prefix}) ){
	$self->error("Missing required args");
	return 0;	
    }
    $args{status}    ||= 0;
    $args{interface} ||= 0; 
    unless ($ipblock = Ipblock->retrieve($args{id})){
	$self->error("Ipblock id $args{id} not in db");
	return 0;
    }
    my $ip;
    unless($ip = NetAddr::IP->new($args{address}, $args{prefix})){
	$self->error("Invalid IP: $args{address}/$args{prefix}");
	return 0;	
    }
    if ( $ip->within(new NetAddr::IP "127.0.0.0", "255.0.0.0") 
	 || $ip eq '::1' ) {
	$self->error("IP is a loopback: $args{address}");
	return 0;	
    }
    my $ui = Netdot::UI->new();
    unless ($status = (IpblockStatus->search(name => $args{status}))[0]){
	$self->error("Status $args{status} not known");
	return 0;		
    }
    my %state = ( address   => $ip->addr, 
		  prefix    => $ip->masklen,
		  version   => $ip->version,
		  status    => $status,
		  interface => $args{interface},
		  last_seen => $ui->timestamp,
		  );
    unless ( $ui->update( object => $ipblock, state => \%state)){
	$self->error($ui->error);
	return 0;
    }
    return 1;
}
#####################################################################
# Remove block
# Arguments: 
#   address: ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
#   prefix:  dotted-quad mask or prefix length
# Returns: true if succeded
#####################################################################
sub removeblock {
    my ($self, %args) = @_;
    my $ipb;
    unless ( exists($args{address}) ){
	$self->error("Missing required args");
	return 0;	
    }
    unless ($ipb = $self->searchblock($args{address})){
	return 0;
    }
    my $ui = Netdot::UI->new();
    unless ($ui->remove(table => 'Ipblock', id => $ipb->id)){
	$self->error(sprintf("removeblock: %s", $ui->error));
	return 0;
    }
    return 1;
}

######################################################################
## Auto-Allocate Block
## Arguments: parent block and a prefix length, return best-choice 
##          allocation
## Returns: New Ipblock object
######################################################################
sub auto_allocate {
    my ($self, $parentid, $length) = @_;
    my $parent;
    unless ($parent = Ipblock->retrieve($parentid)){
	$self->error("Nonexistent Ipblock object: $parentid");
	return 0;
    }    
    unless ($parent->status->name eq "Allocated"){
	$self->error("Parent block's status needs to be 'Allocated'");
	return 0;
    }    
    if ($parent->prefix > $length){
	$self->error("New block's prefix must be longer than parent's");
	return 0;
    }    
    if (my $ip = NetAddr::IP->new($parent->address, $parent->prefix)){
	##
	## Find all sub-blocks and sort them
	my @subnets = 
	    map  { $_->[0] }
	    sort { $a->[1] <=> $b->[1] }
	    map  { [$_, ($_->numeric)[0]] } $ip->split($length);
	
	foreach my $subnet (@subnets){
	    if (my $ipblock = $self->searchblock($subnet->addr, $subnet->masklen)){
		if ($ipblock->status->name eq "Allocated"){
		    return $ipblock;
		}
	    }else{
		my $status = (IpblockStatus->search(name => "Allocated"))[0];
		my $newblock = $self->insertblock(address => $subnet->addr, 
						  prefix  => $subnet->masklen, 
						  status  => $status );
		return $newblock;
	    }
	}
	$self->error("auto_allocate: No blocks available with specified criteria");
	return 0;
    }
}


######################################################################
## Build Tree
## Traverse IP block tree and set dependencies
## Arguments: IP space version (4/6)
######################################################################
sub build_tree { 
    my ($self, $version) = @_;
    unless ($version == 4 || $version == 6){
	$self->error("Invalid IP version: $version");
	return 0;
    }
    # Walk all blocks, starting from the longest prefixes
    # 
    my $it = Ipblock->search(version => $version, { order_by=> 'prefix DESC' } ); 
    unless ($it->count){
	$self->error("No version $version blocks found in DB");
	return 0;	
    }
    # Now for each block,
    # walk all blocks of shorter prefixes, decrementing by 1 each time
    # 
    while (my $ipb = $it->next){
	my $pr;
	if ($version == 6 && $ipb->prefix == 128){
	    ## Jump to /64 subnet
	    $pr = 64;
	}else{
	    $pr = $ipb->prefix - 1;
	}
	my $ipad = NetAddr::IP->new($ipb->address, $ipb->prefix);
	my $found = 0;
	while ($pr > 0 && !$found){
	    my $it2 = Ipblock->search(version => $version, prefix => $pr);
	    while (my $ipb2 = $it2->next){
		# 
		# Assign closest parent and stop
		my $ipad2 = NetAddr::IP->new($ipb2->address, $ipb2->prefix);
		if ($ipad->within($ipad2)){
		    $ipb->parent($ipb2->id);
		    $ipb->update;
		    $found = 1;
		    last;
		}
	    }
	    $pr--;
	}		    
    }
    return 1;
}

