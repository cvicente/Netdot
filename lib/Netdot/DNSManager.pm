package Netdot::DNSManager;

use lib "PREFIX/lib";

use base qw( Netdot );
use Netdot::DBI;
use Netdot::UI;
use strict;

#Be sure to return 1
1;


#####################################################################
# Constructor
# 
#####################################################################
sub new { 
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = {};
    bless $self, $class;
    $self = $self->SUPER::new( %argv );
    wantarray ? ( $self, '' ) : $self; 
}
#####################################################################
# Look for RR by name
# Args: name
# Returns: RR object
#####################################################################
sub getrrbyname {
    my ($self, $name) = @_;
    my $rrta = (RRType->search(name => "A"))[0];
    my $rrt4a = (RRType->search(name => "AAAA"))[0];
    my $rr;
    if ( ($rr = (RR->search(name => $name, type => $rrta))[0]) ||
	 ($rr = (RR->search(name => $name, type => $rrt4a))[0]) ){
	return $rr;
    }
    return 0;
}
#####################################################################
# Look for RR by name.  Allow substrings
# Args: (part of) name
# Returns: RR object
#####################################################################
sub getrrbynamelike {
    my ($self, $name) = @_;
    $name = "%" . $name . "%";
    my $rrta = (RRType->search(name => "A"))[0];
    my $rrt4a = (RRType->search(name => "AAAA"))[0];
    my @rrs;
    if ( (@rrs = RR->search_like(name => $name, type => $rrta)) ||
	 (@rrs = RR->search_like(name => $name, type => $rrt4a)) ){
	return \@rrs;
    }
    return 0;
}
#####################################################################
# Lookup Device by DNS name
# Args: name
# Returns: Device object
#####################################################################
sub getdevbyname {
    my ($self, $name) = @_;
    if (my $rr = $self->getrrbyname($name)){
	if (my $dev = (Device->search(name => $rr->id))[0]){
	    return $dev;
	}
    }
    return 0;
}
#####################################################################
# Lookup Device by DNS name.  Allow substrings
# Args: (part of) name
# Returns: Device object(s)
#####################################################################
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
    return 0;
}
#####################################################################
# Lookup Zone by name
# Args: name
# Returns: Zone object
#####################################################################
sub getzonebyname {
    my ($self, $name) = @_;
    if ( my $z = (Zone->search(mname => $name))[0] ){
	return $z;
    }
    return 0;
}

#####################################################################
# Insert a Resource Record
# Args: 
#   name:
#   type:
#   zone:
#   origin:
#   ttl:
#   data:
#   contactlist:
#   active
# Returns: RR object
#####################################################################
sub insertrr {

    my ($self, %argv) = @_;
    my ($type, $zone);
    if (my $rrid = $self->getrrbyname($argv{name})){
	$self->error("RR $argv{name} already exists.");
	return 0;
    }
    unless ( $type = (RRType->search(name => $argv{type}))[0] ){
	$self->error("Unknown RR type");
	return 0;
    }
    unless ( $zone = (Zone->search(mname => $argv{zone}))[0] ){
	$self->error("Unknown DNS Zone");
	return 0;
    }
    my %state = (name        => $argv{name},
		 type        => $type,
		 zone        => $zone,
		 origin      => $argv{origin}      || 0,
		 ttl         => $argv{ttl}         || $zone->minimum,
		 data        => $argv{data}        || 0,
		 contactlist => $argv{contactlist} || 0,
		 active      => $argv{contactlist} || 0,
		 );
    
    my $ui = Netdot::UI->new();
    if (my $newrr = $ui->insert(table => "RR", state => \%state )){
	return RR->retrieve($newrr);
    }
    $self->error($ui->error);
    return 0;
}

#####################################################################
# Insert a DNS Zone (SOA Record)
# Args: 
#   mname:   domain name *(required)
#   rname:   mailbox name
#   serial:  YYYYMMDD+two digit serial number
#   refresh: time before the zone should be refreshed
#   retry:   time before a failed refresh should be retried
#   expire:  max time before zone no longer authoritative
#   minimum: default TTL that should be exported with any RR from this zone
# Returns: Zone object
#####################################################################
sub insertzone {
    my ($self, %argv) = @_;
    unless (exists $argv{mname}){
	$self->error("Missing required argument \'mname\'");
	return 0;
    }
    if ( $self->getzonebyname($argv{mname}) ){
	$self->error("Zone $argv{mname} already exists.");
	return 0;
    }
    my $ui = Netdot::UI->new();
    #apply some defaults if not supplied
    my %state = (mname     => $argv{mname},
		 rname     => $argv{rname}   || "hostmaster.$argv{mname}",
		 serial    => $argv{serial}  || $ui->dateserial . "00",
		 refresh   => $argv{refresh} || $self->{'DEFAULT_DNSREFRESH'},
                 retry     => $argv{retry}   || $self->{'DEFAULT_DNSRETRY'},
                 expire    => $argv{expire}  || $self->{'DEFAULT_DNSEXPIRE'},
                 minimum   => $argv{minimum} || $self->{'DEFAULT_DNSMINIMUM'},
                 active    => $argv{active}  || 1,
		 );
    if (my $z = $ui->insert(table => "Zone", state => \%state )){
	return Zone->retrieve($z);
    }
    $self->error($ui->error);
    return 0;    
}
