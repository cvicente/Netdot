package Netdot::IPManager;

=head1 NAME

Netdot::IPManager - IP Address Space Functions for Netdot

=head1 SYNOPSIS

  use Netdot::IPManager

  $ipm = Netdot::IPManager->new();  

=cut

use lib "PREFIX/lib";

use base qw( Netdot );
use Netdot::DBI;
use Netdot::UI;
use NetAddr::IP;
use strict;

#Be sure to return 1
1;

=head1 METHODS

=head2 new - Create a new IPManager object

  $ipm = Netdot::IPManager->new();  

=cut

sub new { 
    my $proto = shift;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new();

    my $DB_TYPE        = $self->{'DB_TYPE'};
    my $DB_DATABASE    = $self->{'DB_DATABASE'};
    my $DB_NETDOT_USER = $self->{'DB_NETDOT_USER'};
    my $DB_NETDOT_PASS = $self->{'DB_NETDOT_PASS'};
    #
    # Some operations require a lot of speed.  We override 
    # Class::DBI to avoid overhead in certain cases
    unless ($self->{dbh} = DBI->connect ("dbi:$DB_TYPE:$DB_DATABASE", 
					 "$DB_NETDOT_USER", 
					 "$DB_NETDOT_PASS")){
	$self->error(sprintf("Can't connect to db: %s\n", $DBI::errstr));
	return 0;
    }
    # Max number of blocks returned by search functions
    $self->{'MAXBLOCKS'} = 200;

    wantarray ? ( $self, '' ) : $self; 
}

=head2 sortblocksbyaddr 

 Sort IPblock objects by ip address

 Arguments: arrayref of Ipblock objects
 Returns: sorted arrayref

=cut

sub sortblocksbyaddr {
    my ( $self, $objects) = @_;
    return 0 unless ( @$objects );
    @{$objects} = 
	map  { $_->[0] }
    sort { $a->[1] <=> $b->[1] }
    map  { [$_->[0], $_->[1]->numeric()] }
    map  { [$_, NetAddr::IP->new($_->address)] } @{$objects};
    return $objects;
}

=head2 sortblocksbyparent

 Sort IPblock objects by parent's ip address
 Arguments: arrayref of Ipblock objects
 Returns: sorted arrayref

=cut

sub sortblocksbyparent {
    my ( $self, $objects) = @_;
    return 0 unless ( @$objects );
    @{$objects} = 
	map  { $_->[0] }
    sort { $a->[1] <=> $b->[1] }
    map  { [$_->[0], $_->[1]->numeric()] }
    map  { [$_, NetAddr::IP->new($_->parent->address)] } @{$objects};
    return $objects;
}

=head2 searchblock -  Search IP Blocks
 Arguments: address and (optional) prefix
 Returns: Ipblock object

=cut

sub searchblock {
    my ($self, $address, $prefix) = @_;
    my ($ip, @ipb);
    unless ($ip = NetAddr::IP->new($address, $prefix)){
	$self->error(sprintf("Invalid address: %s/%s", $address, $prefix));
	return;
    }
    if ($prefix){
	@ipb = Ipblock->search( address => ($ip->numeric)[0], 
				prefix  => $ip->masklen,
				);
    }else{
	@ipb = Ipblock->search( address => ($ip->numeric)[0]);
    }
    if (scalar (@ipb) > $self->{'MAXBLOCKS'}){
	$self->error("Too many entries. Please refine search");
	return;
    }    
    wantarray ? ( @ipb ) : $ipb[0]; 

}

=head2 searchblockslike - Search IP Blocks that match certain address substring

 Arguments: (part of) address
 Returns: Ipblock objects

=cut

sub searchblockslike {
    my ($self, $string) = @_;
    my @ipb;
    my $it = Ipblock->retrieve_all;
    while (my $ipb = $it->next){
	$_ = $ipb->address . $ipb->prefix;
	push @ipb, $ipb if (/$string/);
	if (scalar (@ipb) > $self->{'MAXBLOCKS'}){
	    $self->error("Too many entries. Please refine search");
	    return;
	}
    }
    return ( @ipb ) ? @ipb : "";
}

=head2 issubnet - Is Ipblock a subnet?

Arguments: Ipblock object
Returns: 0 (is address) or 1 (is subnet)

=cut

sub issubnet {
    my ($self, $o) = @_;
    if ( ($o->version == 4 && $o->prefix < 32) 
	 || ($o->version == 6 && $o->prefix < 128) ){
	return 1; 
    }else{
	return 0;
    }
}

=head2 getsubnetaddr - Get subnet address

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
   address: ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
   prefix:  dotted-quad mask or prefix length
Optional Arguments:
   status: id of IpblockStatus
   interface: id of Interface where IP was found
   manual (bool): inserted manually or automatically
Returns: New Ipblock object

=cut

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
    my %state = ( address   => $ip->addr, 
		  prefix    => $ip->masklen,
		  version   => $ip->version,
		  status    => $status,
		  interface => $args{interface},
		  );
   
    if (! $args{manual} ){
	$state{first_seen} = $ui->timestamp;
	$state{last_seen} = $ui->timestamp;
    }
		  
    if ( my $r = $ui->insert( table => "Ipblock", state => \%state)){
	return (my $o = Ipblock->retrieve($r)) ;
    }else{
	$self->error($ui->error);
	return 0;
    }
}

=head2 updateblock -  Update existing IP block

 Arguments: 
   id: id of existing Ipblock object
   address: ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
   prefix:  dotted-quad mask or prefix length
 Optional Arguments:
   status: id of IpblockStatus
   interface: id of Interface where IP was found
 Returns: Updated Ipblock object

=cut

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
    my $id;
    unless ( $id = $ui->update( object => $ipblock, state => \%state)){
	$self->error($ui->error);
	return 0;
    }
    return Ipblock->retrieve($id);
}

=head2 removeblock -  Remove IP block

 Arguments: 
   address: ipv4 or ipv6 address in almost any notation (see NetAddr::IP)
   prefix:  dotted-quad mask or prefix length
 Returns: true if succeded

=cut

sub removeblock {
    my ($self, %args) = @_;
    my $ipb;
    unless ( exists($args{address}) && exists($args{prefix}) ){
	$self->error("removeblock: Missing required args");
	return 0;	
    }
    unless ($ipb = $self->searchblock($args{address}, $args{prefix})){
	return 0;
    }
    my $ui = Netdot::UI->new();
    unless ($ui->remove(table => 'Ipblock', id => $ipb->id)){
	$self->error(sprintf("removeblock: %s", $ui->error));
	return 0;
    }
    return 1;
}

=head2 auto_allocate -  Auto-Allocate Block (best possible allocation)

 Arguments: parent block and a prefix length, 
 Returns: New Ipblock object
    #
    # NEEDS MORE WORK.  RIGHT NOW RETURNS FIRST AVAILABLE BLOCK
    #	

=cut

sub auto_allocate {
    my ($self, $parentid, $length) = @_;
    my $parent;
    eval {
	$parent = Ipblock->retrieve($parentid)
	};
    if ($@){
	$self->error("Cannot retrieve $parentid: $@");
	return 0;
    }    
    unless ($parent->status->name eq "Allocated"){
	$self->error("Parent block's status needs to be 'Allocated'");
	return 0;
    }    
    if ($parent->prefix > $length){
	$self->error("New block's prefix length must be higher than parent's");
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
		my $newblock = $self->insertblock(address => $subnet->addr, 
						  prefix  => $subnet->masklen, 
						  status  => "Allocated",
						  manual  => 1);
		return $newblock;
	    }
	}
	$self->error("auto_allocate: No blocks of size $length available");
	return 0;
    }
}

=head2 buil_tree -  Builds the IPv4 or IPv6 space tree

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
    my $sth = $self->{dbh}->prepare("UPDATE Ipblock SET parent = ? WHERE id = ?");
    foreach (keys %parents){
	$sth->execute($parents{$_}, $_);
    }
    return 1;
}

