package Netdot::IPManager;

use lib "/home/netdot/public_html/lib";

use Netdot::DBI;
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
# return error message
#####################################################################
sub error {
  $_[0]->{'_error'} || '';
}

#####################################################################
# clear error - private method
#####################################################################
sub _clear_error {
  $_[0]->{'_error'} = undef;
}

#####################################################################
# IP to Integer Converter
# Accepts: dotted-quad address
# Returns: Integer
#####################################################################
sub ip2int {
    my ($self, $address) = @_;
    my $ip = NetAddr::IP->new($address);
    unless ($ip){
	$self->{'_error'} = "ip2int: Invalid Address: $address";
	return undef;
    }
    return ($ip->numeric)[0];
}

#####################################################################
# Sort arrayref of IPblock objects by ip address
# Accepts: dotted-quad address
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
# Accepts: address and (optional) prefix
# Returns: Ipblock object
#####################################################################
sub searchblock {
    my ($self, $address, $prefix) = @_;
    my ($ipblock, %params);
    my $intaddr = $self->ip2int($address);
    $params{address} = $intaddr;
    $params{prefix} = $prefix if $prefix;
    return ($ipblock = (Ipblock->search(%params))[0] );
    return undef;
}

#####################################################################
# Is subnet?
# Accepts: IPblock object
# Returns: 0 or 1
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
# Insert a new block
# Returns: New Ipblock object
#####################################################################
sub insertblock {
    my ($self, $address, $prefix, $statusid) = @_;
    $statusid ||= 0;
    if ($self->searchblock($address, $prefix)){
	$self->{'_error'} = "insertblock: Block already exists in db";
	return 0;
    }
    my $ip;
    unless($ip = NetAddr::IP->new($address, $prefix)){
	$self->{'_error'} = "Invalid IP: $address/$prefix";
	return 0;	
    }
    my $ui = Netdot::UI->new();
    my %state = ( address  => $ip->addr, 
		  prefix   => $ip->masklen,
		  status   => $statusid,
		  version  => $ip->version,
		  );
    my $r;
    if ( $r = $ui->insert( table => "Ipblock", state => \%state)){
	return $r ;
    }else{
	$self->{'_error'} = $ui->error;
	return 0;
    }
}

######################################################################
## Auto-Allocate Block
## Accepts: parent block and a prefix length, return best-choice 
##          allocation
## Returns: New Ipbloc object
######################################################################
sub auto_allocate {
    my ($self, $parentid, $length) = @_;
    my $parent;
    unless ($parent = Ipblock->retrieve($parentid)){
	$self->{'_error'} = "auto_allocate: Nonexistent Ipblock object: $parentid";
	return 0;
    }    
    unless ($parent->status->name eq "Allocated"){
	$self->{'_error'} = "auto_allocate: Parent block's status needs to be 'Allocated'";
	return 0;
    }    
    if ($parent->prefix > $length){
	$self->{'_error'} = "auto_allocate: New block's prefix must be longer than parent's";
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
		my $newblock = $self->insertblock($subnet->addr, $subnet->masklen, $status->id);
		return $newblock;
	    }
	}
	$self->{'_error'} = "auto_allocate: No blocks available with specified criteria";
	return 0;
    }
}


######################################################################
## Build Tree
## Traverse IP block tree and set dependencies
## Accepts: IP space version (4/6)
######################################################################
sub build_tree { 
    my ($self, $version) = @_;
    unless ($version == 4 || $version == 6){
	$self->{'_error'} = "build_tree: Invalid IP version: $version";
	return 0;
    }
    # Walk all blocks, starting from the longest prefixes
    # 
    my $it = Ipblock->search(version => $version, { order_by=> 'prefix DESC' } ); 
    unless ($it->count){
	$self->{'_error'} = "build_tree: No version $version blocks found in DB";
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

