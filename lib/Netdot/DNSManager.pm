package Netdot::DNSManager;

=head1 NAME

Netdot::DNSManager - DNS-related Functions for Netdot

=head1 SYNOPSIS

  use Netdot::DNS

  $dns = Netdot::DNS->new();  

=cut

use lib "PREFIX/lib";

use base qw( Netdot );
use Socket;
use strict;

#Be sure to return 1
1;

=head1 METHODS

=head2 new - Create a new DNSManager object

=cut

sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new( %argv );
    wantarray ? ( $self, '' ) : $self; 
}

=head2 getrrbyname - Search Resource Records by name

 Args: name
 Returns: RR object

=cut

sub getrrbyname {
    my ($self, $name) = @_;
    my $rr;
    if ( $rr = (RR->search(name => $name))[0] ){
	return $rr;
    }
    return 0;
}

=head2 getrrbynamelike - Search RRs by name. Allow substrings

 Args: (part of) name
 Returns: array of RR objects

=cut

sub getrrbynamelike {
    my ($self, $name) = @_;
    $name = "%" . $name . "%";
    my @rrs;
    if ( @rrs = RR->search_like(name => $name) ){
	return \@rrs;
    }
    return;
}

=head2 getdevbyname - Lookup Device by DNS name

 Args: name
 Returns: Device object

=cut

sub getdevbyname {
    my ($self, $name) = @_;
    if (my $rr = $self->getrrbyname($name)){
	if (my $dev = (Device->search(name => $rr->id))[0]){
	    return $dev;
	}
    }
    return 0;
}

=head2 getdevbynamelike -  Lookup Device by DNS name.  Allow substrings

 Args: (part of) name
 Returns: Device object(s)

=cut

sub getdevbynamelike {
    my ($self, $name) = @_;
    if (my $rrs = $self->getrrbynamelike($name)){
	my @devs;
	foreach my $rr (@$rrs){
	    if (my $dev = (Device->search(name => $rr->id))[0]){
		push @devs, $dev;
	    }
	}
	return \@devs;
    }
    return;
}


=head2 getzonebyname -  Lookup Zone by name

 Args: name
 Returns: Zone object

=cut

sub getzonebyname {
    my ($self, $name) = @_;
    if ( my $z = (Zone->search(mname => $name))[0] ){
	return $z;
    }
    return 0;
}

=head2 insert_rr - Insert a base Resource Record

Note:  This object does not contain actual DNS records.
       Each record type has its own table that references
       this base record.

 Args: 
  name:        Unique record identifier (AKA "owner")
  zone:        SOA record
  origin:      optional origin prefix
  contactlist: ContactList object
  active:      If not active, it is somehow reserved
    
Returns: RR object

=cut

sub insert_rr {

    my ($self, %argv) = @_;
    my ($type, $zone);
    if ( $argv{zone} ){
	unless ( $self->getzonebyname($argv{zone}) ){
	    $self->error(sprintf("Unknown DNS Zone: %s", $argv{zone}));
	    return 0;
	}
    }else{
	$argv{zone} = $self->{config}->{'DEFAULT_DNSDOMAIN'};
    }
    # Insert zone if necessary;
    unless ( $zone = $self->getzonebyname($argv{zone})){
	unless ($zone = $self->insert_zone(mname => $argv{zone})){
	    return 0;
	    # error should be set
	}
    }
    if (my $rrid = $self->getrrbyname($argv{name})){
	$self->error(sprintf("Record %s already exists.", $argv{name}));
	return 0;
    }
    my %state = (name        => $argv{name},
		 zone        => $zone->id,
		 origin      => $argv{origin}      || "",
		 contactlist => $argv{contactlist} || 0,
		 active      => $argv{active}      || 1,
		 );
    
    if (my $newrr = $self->insert(table => "RR", state => \%state )){
	return RR->retrieve($newrr);
    }
    return 0;
}

=head2 insert_a_rr - Insert an address (A/AAAA)  Resource Record

Args: 
  rr:          Base resource record (optional, see below)
  ip:          Ipblock object (required)
  ttl:         Time To Live (optional)
  
If 'rr' not suplied:
  name:        Unique record identifier (required)
  zone:        SOA record
  origin:      optional origin prefix
  contactlist: ContactList object
  active:      If not active, it is somehow reserved

Returns: RRADDR object

=cut

sub insert_a_rr{

    my ($self, %argv) = @_;
    my ($rr, $ip);
    unless ( $ip = $argv{ip} ){
	$self->error("Missing required args");
	return 0;
    }
    unless ( $rr = $argv{rr} ){
	unless ($rr = $self->insert_rr(name        => $argv{name}, 
				       zone        => $argv{zone},
				       origin      => $argv{origin},
				       contactlist => $argv{contactlist},
				       active      => $argv{active} )){
	    return 0;
	    # error should be set
	}
    }
    my %state = (rr       => $rr,
		 ipblock  => $ip,
		 ttl      => $argv{ttl} || $rr->zone->minimum,
		 );
    
    if (my $newrr = $self->insert(table => "RRADDR", state => \%state )){
	return RRADDR->retrieve($newrr);
    }
    return 0;
}

=head2 insert_zone - Insert a DNS Zone (SOA Record)

Args: 
   mname:   domain name *(required)
   rname:   mailbox name
   serial:  YYYYMMDD+two digit serial number
   refresh: time before the zone should be refreshed
   retry:   time before a failed refresh should be retried
   expire:  max time before zone no longer authoritative
   minimum: default TTL that should be exported with any RR from this zone

Returns: Zone object

=cut


sub insert_zone {
    my ($self, %argv) = @_;
    unless (exists $argv{mname}){
	$self->error("Missing required argument \'mname\'");
	return 0;
    }
    if ( $self->getzonebyname($argv{mname}) ){
	$self->error("Zone $argv{mname} already exists.");
	return 0;
    }
    #apply some defaults if not supplied
    my %state = (mname     => $argv{mname},
		 rname     => $argv{rname}   || "hostmaster.$argv{mname}",
		 serial    => $argv{serial}  || $self->dateserial . "00",
		 refresh   => $argv{refresh} || $self->{config}->{'DEFAULT_DNSREFRESH'},
                 retry     => $argv{retry}   || $self->{config}->{'DEFAULT_DNSRETRY'},
                 expire    => $argv{expire}  || $self->{config}->{'DEFAULT_DNSEXPIRE'},
                 minimum   => $argv{minimum} || $self->{config}->{'DEFAULT_DNSMINIMUM'},
                 active    => $argv{active}  || 1,
		 );
    if (my $z = $self->insert(table => "Zone", state => \%state )){
	return Zone->retrieve($z);
    }
    return 0;    
}

=head2 resolve_name - Resolve name to ip adress

=cut 

sub resolve_name {
    my ($self, $name) = @_;
    my @addresses;
    unless ( @addresses = gethostbyname($name) ){
	$self->error("Can't resolve $name");
	return;
    }
    @addresses = map { inet_ntoa($_) } @addresses[4 .. $#addresses];

    return @addresses;
}

=head2 resolve_ip - Resolve ip (v4 or v6) adress to name

=cut 

sub resolve_ip {
    my ($self, $ip) = @_;
    my $name;
    my $v4 = '(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})';
    if ( $ip =~ /$v4/ ){
	unless ($name = gethostbyaddr(inet_aton($ip), AF_INET)){
	$self->error("Can't resolve $ip");
	    return 0;
	}
    }else{
	# TODO: add v6 here (maybe using Socket6 module)
	return 0;
    }
    # Strip off our own domain if necessary
    $name =~ s/\.$self->{config}->{'DEFAULT_DNSDOMAIN'}//i;
    return $name;
}
