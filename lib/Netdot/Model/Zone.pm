package Netdot::Model::Zone;

use base 'Netdot::Model';
use warnings;
use strict;
use Netdot::Util::ZoneFile;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

# Some regular expressions
my $IPV4 = Netdot->get_ipv4_regex();
my $IPV6 = Netdot->get_ipv6_regex();

=head1 NAME

Netdot::Model::Zone - DNS Zone Class

=head1 SYNOPSIS

=head1 CLASS METHODS
=cut

############################################################################
=head2 search - Search for Zone objects

    We override the base method to add functionality:

    - Return the most specific domain name. 
    
      If given:

         name=>dns.cs.local.domain

      we will look for a Zone object in this order:

        dns.cs.local.domain (not found)
        cs.local.domain     (not found)
        local.domain        (found)
        return 'local.domain'

    - Search the ZoneAlias table in addition to the Zone table.

  Arguments: 
    Hash with key/value pairs
  Returns: 
    See Class::DBI search
  Examples:
    Zone->search(name=>'some.domain.name')

=cut
sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    @args = %{ $args[0] } if ref $args[0] eq "HASH";
    my $opts = @args % 2 ? pop @args : {}; 
    my %argv = @args;

    if ( exists $argv{id} && $argv{id} =~ /\D+/ ){
	# No use searching for non-digits in id field
	$argv{id} = 0;
    }
    
    if ( $class->SUPER::search(%argv, $opts) ){
	return $class->SUPER::search(%argv, $opts);
    }elsif ( defined $argv{name} ){
	if ( my $alias = ZoneAlias->search(name=>$argv{name})->first ) {
	    return $class->SUPER::search(id=>$alias->zone->id);
	}elsif ( $argv{name} =~ /\./ && $argv{name} !~ /^($IPV4)$/ ){
	    my @sections = split '\.', $argv{name};
	    while ( @sections ){
		$argv{name} = join '.', @sections;
		$logger->debug(sub{ "Zone::search: $argv{name}" });
		if ( $class->SUPER::search(%argv) ){
		    # We call the method again to not mess
		    # with CDBI's wantarray checks
		    $logger->debug(sub{ "Zone::search: found: ", $argv{name} });
		    return $class->SUPER::search(%argv);
		}
		shift @sections;
	    }
	}
    }
    else{
	return $class->SUPER::search(%argv, $opts);
    }
}


#########################################################################
=head2 insert - Insert a new DNS Zone (SOA Record)

    We override the insert method for extra functionality

 Args: 
    name      domain name *(required)
    mname     server name
    rname     mailbox name
    serial    YYYYMMDD+two digit serial number
    refresh   time before the zone should be refreshed
    retry     time before a failed refresh should be retried
    expire    max time before zone no longer authoritative
    minimum   default TTL that should be exported with any RR from this zone

    If not defined, these fields will default to the values specified in the
    config file.
  Returns: 
    Zone object
  Examples:
    Zone->insert( { name=>{'newzone.domain'} } );

=cut
sub insert {
    my ($class, $argv) = @_;
    $class->throw_fatal("Model::Zone::insert: Missing required arguments")
	unless ( $argv->{name} );

    # Some defaults
    my %state = (
	name        => $argv->{name},
	mname       => $argv->{mname}       || 'localhost',
	rname       => $argv->{rname}       || "hostmaster.".$argv->{name},
	refresh     => $argv->{refresh}     || $class->config->get('DEFAULT_DNSREFRESH'),
	retry       => $argv->{retry}       || $class->config->get('DEFAULT_DNSRETRY'),
	expire      => $argv->{expire}      || $class->config->get('DEFAULT_DNSEXPIRE'),
	minimum     => $argv->{minimum}     || $class->config->get('DEFAULT_DNSMINIMUM'),
	active      => $argv->{active}      || 1,
	export_file => $argv->{export_file} || $argv->{name},
	default_ttl => $argv->{default_ttl} || $class->config->get('ZONE_DEFAULT_TTL'),
	);

    my $newzone = $class->SUPER::insert( \%state );

    $newzone->_update_serial();

    return $newzone;
}


=head1 INSTANCE METHODS
=cut

#########################################################################
=head2 as_text
    
    Return the text representation (BIND syntax) of the Zone file. 
    This is highly inefficient for large zones.

 Args: 
    none
  Returns: 
    True
  Examples:
    $zone->as_text();

=cut
sub as_text {
    my ($self, $argv) = @_;
    $self->isa_object_method('as_text');
    my $text = "";
    $text = $self->soa_string . "\n";
    foreach my $record ( sort { $a->name cmp $b->name } $self->records ){
	$text .= $record->as_text();
    }

    return $text;
}

############################################################################
=head2 soa_string - Return SOA record as text

 Args: 
    none
  Returns: 
    True
  Examples:
    my $text = $zone->soa_string();

=cut
sub soa_string{
    my $self = shift;
    $self->isa_object_method('soa_string');

    my $soa = Net::DNS::RR->new(
	type        => 'SOA',
	name        => $self->name,
	mname       => $self->mname,
	rname       => $self->rname,
	serial      => $self->serial,
	refresh     => $self->refresh,
	retry       => $self->retry,
	expire      => $self->expire,
	minimum     => $self->minimum,
	);
    return $soa->string;
}

############################################################################
=head2 get_all_records - Get all records for export

   Iterating over each RR and its sub-RRs and calling as_text is too slow
   for large zones.  This method uses direct SQL for faster exports.

  Args: 
    None
  Returns: 
    Hashref
  Examples:
    $zone->get_all_records();

=cut
sub get_all_records {
    my ($self, %argv) = @_;
    $self->isa_object_method('print_to_file');
    
    my $dbh = $self->db_Main;
    my $id = $self->id;
    my $q = "SELECT   rr.name, zone.name, ipblock.version, ipblock.address, rrtxt.txtdata, rrhinfo.cpu, rrhinfo.os,
                      rrptr.ptrdname, rrns.nsdname, rrmx.preference, rrmx.exchange, rrcname.cname, rrloc.id, 
                      rrsrv.id, rrnaptr.id, rr.active,
                      rraddr.ttl, rrtxt.ttl, rrhinfo.ttl, rrns.ttl, rrmx.ttl, rrcname.ttl, rrptr.ttl
             FROM     zone, rr
                      LEFT OUTER JOIN (ipblock, rraddr) ON (rr.id=rraddr.rr AND ipblock.id=rraddr.ipblock)
                      LEFT OUTER JOIN rrptr   ON rr.id=rrptr.rr
                      LEFT OUTER JOIN rrtxt   ON rr.id=rrtxt.rr
                      LEFT OUTER JOIN rrhinfo ON rr.id=rrhinfo.rr
                      LEFT OUTER JOIN rrns    ON rr.id=rrns.rr
                      LEFT OUTER JOIN rrmx    ON rr.id=rrmx.rr
                      LEFT OUTER JOIN rrcname ON rr.id=rrcname.name
                      LEFT OUTER JOIN rrnaptr ON rr.id=rrnaptr.rr
                      LEFT OUTER JOIN rrsrv   ON rr.id=rrsrv.name
                      LEFT OUTER JOIN rrloc   ON rr.id=rrloc.rr
             WHERE    rr.zone=zone.id AND zone.id=$id";

    my $results = $dbh->selectall_arrayref($q);
    my %rec;
    foreach my $r ( @$results ){
	my ( $name, $zone, $ipversion, $ip, $txtdata, $cpu, $os, 
	     $ptrdname, $nsdname, $mxpref, $exchange, $cname, $rrlocid, $rrsrvid, $rrnaptrid, $active,
             $rraddrttl, $rrtxtttl, $rrhinfottl, $rrnsttl, $rrmxttl, $rrcnamettl, $rrptrttl ) = @$r;

	next unless $active;

	# Group them by name (aka 'owner')
	if ( $ip ){
	    if ( $ipversion == 4 ){
		my $address = Ipblock->int2ip($ip, $ipversion);
		$rec{$name}{A}{$address} = $rraddrttl;
	    }elsif ( $ipversion == 6 ){
		my $address = Ipblock->int2ip($ip, $ipversion);
		$rec{$name}{AAAA}{$address} = $rraddrttl;
	    }else{
		$logger->warn("Zone::print_to_file: $ip has unknown version: $ipversion");
	    }
	}
	$rec{$name}{NS}{"$nsdname."}           = $rrnsttl    if ($nsdname);
	$rec{$name}{MX}{"$mxpref $exchange."}  = $rrmxttl    if (defined($mxpref) && $exchange);
	$rec{$name}{CNAME}{"$cname."}          = $rrcnamettl if ($cname);
	$rec{$name}{PTR}{"$ptrdname."}         = $rrptrttl   if ($ptrdname);
	$rec{$name}{TXT}{"\"$txtdata\""}       = $rrtxtttl   if ($txtdata);
	$rec{$name}{HINFO}{"\"$cpu\" \"$os\""} = $rrhinfottl if ($cpu && $os);
	$rec{$name}{LOC}{id}   = $rrlocid   if ($rrlocid);
	$rec{$name}{SRV}{id}   = $rrsrvid   if ($rrsrvid);
	$rec{$name}{NAPTR}{id} = $rrnaptrid if ($rrnaptrid);
    }

    return \%rec;
}


############################################################################
=head2 get_record_count
    
  Args: 
    None
  Returns: 
    Hashref with key=record type, value=count
  Examples:
    $zone->get_record_count();

=cut
sub get_record_count {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_record_count');
    my $id = $self->id;
    
    my $q1 = "SELECT COUNT(DISTINCT rrtxt.id), 
             COUNT(DISTINCT rrhinfo.id), COUNT(DISTINCT rrptr.id), 
             COUNT(DISTINCT rrns.id), COUNT(DISTINCT rrmx.id), 
             COUNT(DISTINCT rrcname.id), COUNT(DISTINCT rrloc.id), 
             COUNT(DISTINCT rrsrv.id), COUNT(DISTINCT rrnaptr.id)
             FROM     zone z, rr rr
                      LEFT OUTER JOIN rrptr   ON rr.id=rrptr.rr
                      LEFT OUTER JOIN rrtxt   ON rr.id=rrtxt.rr
                      LEFT OUTER JOIN rrhinfo ON rr.id=rrhinfo.rr
                      LEFT OUTER JOIN rrns    ON rr.id=rrns.rr
                      LEFT OUTER JOIN rrmx    ON rr.id=rrmx.rr
                      LEFT OUTER JOIN rrcname ON rr.id=rrcname.name
                      LEFT OUTER JOIN rrnaptr ON rr.id=rrnaptr.rr
                      LEFT OUTER JOIN rrsrv   ON rr.id=rrsrv.name
                      LEFT OUTER JOIN rrloc   ON rr.id=rrloc.rr
             WHERE    rr.zone=z.id AND z.id=$id";

    my $q2 = "SELECT COUNT(DISTINCT ipv4.id)
             FROM     zone z, rr rr
                      LEFT OUTER JOIN (ipblock ipv4, rraddr) 
                      ON (rr.id=rraddr.rr AND ipv4.id=rraddr.ipblock AND ipv4.version=4)
             WHERE    rr.zone=z.id AND z.id=$id";
    
    my $q3 = "SELECT COUNT(DISTINCT ipv6.id)
             FROM     zone z, rr rr
                      LEFT OUTER JOIN (ipblock ipv6, rraddr) 
                      ON (rr.id=rraddr.rr AND ipv6.id=rraddr.ipblock AND ipv6.version=6)
             WHERE    rr.zone=z.id AND z.id=$id";

    my $dbh = $self->db_Main;
    my $r1  = $dbh->selectall_arrayref($q1);
    my $r2  = $dbh->selectall_arrayref($q2);
    my $r3  = $dbh->selectall_arrayref($q3);
    my %count;
    ($count{txt}, $count{hinfo}, $count{ptr}, $count{ns}, $count{mx}, 
     $count{cname}, $count{loc}, $count{srv}, $count{rrnaptr}) = @{$r1->[0]};

    ($count{a})    = @{$r2->[0]};
    ($count{aaaa}) = @{$r3->[0]};

    return \%count;
}


############################################################################
=head2 import_records - Import records into zone
    
  Args: 
    rrs       -  Arrayref containing Net:DNS::RR objects (required unless text is passed)
    text      -  Text containing records (BIND format) (required unless rrs is passed)
    overwrite -  Overwrite any existing records
  Returns: 
    Nothing
  Examples:
    $zone->import_records(text=>$text);

=cut
sub import_records {
    my ($self, %argv) = @_;
    
    unless ( $argv{text} || $argv{rrs} ){
	$self->throw_fatal('Missing required arguments: text or rrs');
    }
    
    my $domain = $self->name;
    my ($rrs, $default_ttl);

    if ( $argv{text } ){
	($rrs, $default_ttl) = Netdot::Util::ZoneFile::parse(text=>$argv{text}, origin=>$domain);
    }else{
	$self->throw_fatal("rrs parameter must be arrayref")
	    unless ( ref($argv{rrs}) eq 'ARRAY' );
	$rrs = $argv{rrs};
    }

    $self->throw_user("No records to work with")
	unless scalar @$rrs;
    
    # Keep all current records in hash for faster lookups
    my %nrrs;
    foreach my $r ( $self->records ){
	$nrrs{$r->name} = $r;
    }
    
    my $new_ips = 0;

    foreach my $rr ( @$rrs ){
	my $name = $rr->name;
	if ( $name eq $domain ){
	    $name = '@';
	}else {
	    if ( $name =~ /\.$domain/ ){
		$name =~ s/\.$domain\.?//;
	    }else{
		debug("Zone $domain: Ignoring out of zone data: $name");
		next;
	    }
	}

	my $nrr;
	my $ttl = $rr->ttl;
	if ( exists $nrrs{$name} ){
	    $logger->debug("$domain: RR $name already exists in DB");
	    $nrr = $nrrs{$name};
	    if ( $argv{overwrite} ){
		$logger->debug("$domain: $name: Overwriting current records");
		$nrr->delete;
		delete $nrrs{$name};
	    }
	}

	if ( !exists $nrrs{$name} ){
	    if ( !($nrr = RR->search(name=>$name, zone=>$self)->first ) ){
		$logger->debug("$domain: Inserting RR $name");
		$nrr = RR->insert({name=>$name, zone=>$self});
	    }
	    $nrrs{$name} = $nrr;
	}

	if ( $rr->type eq 'A' || $rr->type eq 'AAAA' ){
	    my $address = $rr->address;
	    my $ipb;
	    if ( !($ipb = Ipblock->search(address=>$address)->first) ){
		$logger->debug("$domain: Inserting Ipblock $address");
		$ipb = Ipblock->insert({ address        => $address,
					 status         => 'static',
					 no_update_tree => 1});
	    }
	    my $rraddr;
	    my %args = (rr=>$nrr, ipblock=>$ipb);
	    if ( $argv{overwrite} || !($rraddr = RRADDR->search(%args)->first) ){
		$args{ttl} = $ttl;
		$logger->debug("$domain: Inserting RRADDR $name, $address, ttl: $ttl");
		$rraddr = RRADDR->insert(\%args);
	    }
	}elsif ( $rr->type eq 'TXT' ){
	    my $rrtxt;
	    my %args = (rr=>$nrr, txtdata=>$rr->txtdata);
	    if ( $argv{overwrite} || !($rrtxt = RRTXT->search(%args)->first) ){
		$args{ttl} = $ttl;
		$logger->debug("$domain: Inserting RRTXT $name, ".$rr->txtdata);
		$rrtxt = RRTXT->insert(\%args);
	    }
	}elsif ( $rr->type eq 'HINFO' ){
	    my $rrhinfo;
	    my %args = (rr=>$nrr);
	    if ( $argv{overwrite} || !($rrhinfo = RRHINFO->search(%args)->first) ){
		$args{cpu} = $rr->cpu;
		$args{os}  = $rr->os;
		$args{ttl} = $ttl;
		$logger->debug("$domain: Inserting RRHINFO $name, $args{cpu}, $args{os}, ttl: $ttl");
		$rrhinfo = RRHINFO->insert(\%args);
	    }
	}elsif ( $rr->type eq 'MX' ){
	    my $rrmx;
	    my %args = (rr=>$nrr, exchange=>$rr->exchange);
	    if ( $argv{overwrite} || !($rrmx = RRMX->search(%args)->first) ){
		$args{preference} = $rr->preference;
		$args{exchange}   = $rr->exchange;
		$args{ttl}        = $ttl;
		$logger->debug("$domain: Inserting RRMX $name, ".$rr->exchange.", ttl: $ttl");
		$rrmx = RRMX->insert(\%args);
	    }
	}elsif ( $rr->type eq 'NS' ){
	    my $rrns;
	    my %args = (rr=>$nrr, nsdname=>$rr->nsdname);
	    if ( !($rrns = RRNS->search(%args)->first) ){
		$logger->debug("$domain: Inserting RRNS $name, ".$rr->nsdname);
		$args{ttl} = $ttl;
		$rrns = RRNS->insert(\%args);
	    }
	}elsif ( $rr->type eq 'CNAME' ){
	    my $rrcname;
	    my %args = (name=>$nrr, cname=>$rr->cname);
	    if ( $argv{overwrite} || !($rrcname = RRCNAME->search(%args)->first) ){
		$args{ttl} = $ttl;
		$logger->debug("$domain: Inserting RRCNAME $name, ".$rr->cname.", ttl: $ttl");
		$rrcname = RRCNAME->insert(\%args);
	    }
	}elsif ( $rr->type eq 'PTR' ){
	    my $rrptr;
	    my $prefix = $domain;
	    my $ipversion;
	    if ( $prefix =~ s/(.*)\.in-addr.arpa/$1/ ){
		$ipversion = 4;
	    }elsif ( $prefix =~ s/(.*)\.ip6.arpa/$1/ ){
		$ipversion = 6;
	    }elsif ( $prefix =~ s/(.*)\.ip6.int/$1/ ){
		$ipversion = 6;
	    }
	    
	    my $ipaddr = "$name.$prefix";
	    
	    if ( $ipversion eq '4' ){
		$ipaddr = join '.', (reverse split '\.', $ipaddr);
	    }elsif ( $ipversion eq '6' ){
		my @n = reverse split '\.', $ipaddr;
		my @g; my $m;
		for (my $i=1; $i<=scalar(@n); $i++){
		    $m .= $n[$i-1];
		    if ( $i % 4 == 0 ){
			push @g, $m;
			$m = "";
		    }
		}
		$ipaddr = join ':', @g;		
	    }
	    
	    $logger->debug("$domain: Inserting Ipblock $ipaddr");
	    my $ipb;
	    if ( !($ipb = Ipblock->search(address=>$ipaddr)->first) ){
		$ipb = Ipblock->insert({ address        => $ipaddr,
					 status         => 'Static',
					 no_update_tree => 1 });
		$new_ips++;
	    }
	    my %args = (rr=>$nrr, ptrdname=>$rr->ptrdname, ipblock=>$ipb);
	    if ( $argv{overwrite} || !($rrptr = RRPTR->search(%args)->first) ){
		$logger->debug("$domain: Inserting RRPTR $name, ".$rr->ptrdname.", ttl: $ttl");
		$args{ttl} = $ttl;
		$rrptr = RRPTR->insert(\%args);
	    }
	}elsif ( $rr->type eq 'NAPTR' ){
	    my $rrnaptr;
	    my %args = (rr=>$nrr, services=>$rr->service);
	    if ( $argv{overwrite} || !($rrnaptr = RRNAPTR->search(%args)->first) ){
		$args{order_field} = $rr->order;
		$args{preference}  = $rr->preference;
		$args{flags}       = $rr->flags;
		$args{services}    = $rr->service;
		$args{regexpr}     = $rr->regexp;
		$args{replacement} = $rr->replacement;
		$args{ttl} = $ttl;
		$logger->debug("$domain: Inserting RRNAPTR $name, $args{services}, $args{regexpr}, ttl: $ttl");
		$rrnaptr = RRNAPTR->insert(\%args);
	    }
	}elsif ( $rr->type eq 'SRV' ){
	    my $rrsrv;
	    my %args = (rr=>$nrr);
	    if ( $argv{overwrite} || !($rrsrv = RRSRV->search(%args)->first) ){
		$args{priority} = $rr->priority;
		$args{weight}   = $rr->weight;
		$args{port}     = $rr->port;
		$args{target}   = $rr->target;
		$args{ttl} = $ttl;
		$logger->debug("$domain: Inserting RRSRV $name, $args{port}, $args{target}, ttl: $ttl");
		$rrsrv = RRSRV->insert(\%args);
	    }
	}elsif ( $rr->type eq 'LOC' ){
	    my $rrloc;
	    my %args = (rr=>$nrr);
	    if ( $argv{overwrite} || !($rrloc = RRLOC->search(%args)->first) ){
		$args{ttl}       = $ttl;
		$args{size}      = $rr->size;
		$args{horiz_pre} = $rr->horiz_pre;
		$args{vert_pre}  = $rr->vert_pre;
		$args{latitude}  = $rr->latitude;
		$args{longitude} = $rr->longitude;
		$args{altitude}  = $rr->altitude;
		$logger->debug("$domain: Inserting RRLOC $name");
		$rrloc = RRLOC->insert(\%args);
	    }
	}else{
	    $logger->warn("Type ". $rr->type. " not currently supported.\n")
		unless ( $rr->type eq 'SOA' );
	}
    }

    if ( $new_ips ){
	# Update IP space hierarchy
	Ipblock->build_tree(4);
	Ipblock->build_tree(6);
    }

    1;
}

############################################################################
#
# Private Methods
#
############################################################################

############################################################################
#_dateserial - Get date in 'DNS zone serial' format
#  e.g. 20070409
#
#  Arguments: 
#    None
#  Returns: 
#    String
#  Examples:
#    $serial = Zone->_dateserial();
#
sub _dateserial {
    my $class  = shift;
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year,
        $wday, $yday, $isdst) = localtime;
    my $date = sprintf("%04d%02d%02d", $year+1900, $month+1, $day_of_month);
    return $date;
}

#########################################################################
# _update_serial
#
#  Args: 
#     None
#   Returns: 
#     Zone object
#   Examples:
#     Zone->_update_serial();
#
# 
sub _update_serial {
    my ($self, $argv) = @_;
    $self->isa_object_method('_update_serial');

    my $serial = $self->serial;

    my $format = Netdot->config->get('ZONE_SERIAL_FORMAT') || 'dateserial';

    if ( $format eq 'dateserial' ){
	# If current serial is from today, increment
	# the counter.  Otherwise, use today's date and 00.
	my $date   = $self->_dateserial();
	if ( $serial =~ /$date(\d{2})/ ){
	    my $inc = sprintf("%02d", $1+1);
	    $serial = $date . $inc;
	}else{
	    $serial = $date . '00';
	}
    }elsif ( $format eq 'epoch' ){
	$serial = time;

    }elsif ( $format eq 'plain' ){
	$serial++;
    }else{
	$self->throw_fatal("Unrecognized value for ZONE_SERIAL_FORMAT in config file");
    }
    
    return $self->update({serial=>$serial});
}



############################################################################
# _fix_child_names
# 
#  We want all the matching RR's to fall under this new zone when appropriate
#
#  Arguments: 
#    None
#  Returns: 
#    String
#  Examples:
#    $zone->_fix_child_names
#

sub _fix_child_names{
    my ($self) = @_;
    my $name = $self->name;
    if ( my @rrs = RR->retrieve_all() ){
	foreach my $rr ( @rrs ){
	    my $fqdn = $rr->get_label;
	    if ( $fqdn =~ /\.$name$/ ){
		my $newname = $fqdn;
		$newname =~ s/\.$name$//;
		$rr->update({name=>$newname, zone=>$self});
	    }
	}
    }
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

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

#Be sure to return 1
1;

