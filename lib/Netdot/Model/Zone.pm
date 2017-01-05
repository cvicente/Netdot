package Netdot::Model::Zone;

use base 'Netdot::Model';
use warnings;
use strict;
use Net::DNS::ZoneFile::Fast;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 NAME

Netdot::Model::Zone

=head1 SYNOPSIS
    
DNS Zone Class
    
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

    my (@result, $result);
    if (wantarray) {
        @result = $class->SUPER::search(%argv, $opts);
    } else {
        $result = $class->SUPER::search(%argv, $opts);
    }

    if (@result || $result) {
	return wantarray ? @result : $result;
    }elsif ( defined $argv{name} ){
	if ( my $alias = ZoneAlias->search(name=>$argv{name})->first ) {
	    return $class->SUPER::search(id => $alias->zone->id, $opts);
	}elsif ( $argv{name} =~ /\./ && !Ipblock->matches_v4($argv{name}) ){
	    my @sections = split '\.', $argv{name};

	    # first try to search for the RFC2317 reverse if it exists
	    if ( $argv{name} =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)\.in-addr\.arpa$/o ) {
		my $address = join('.',($4, $3, $2, $1));
		if ( my $ipb = Ipblock->search(address=>$address)->first ){
		    if ( my $subnet = $ipb->parent ){
			my $subnetaddr = $subnet->address;
			my $prefix = $subnet->prefix;
			my @octs = split('\.', $subnetaddr);
			$argv{name} = $octs[3]."-".$prefix.".$octs[2].$octs[1].$octs[0].in-addr.arpa";
			$logger->debug(sub{ "Zone::search: $argv{name}" });
			if ( $class->SUPER::search(%argv, $opts) ){
			    $logger->debug(sub{ "Zone::search: found: ", $argv{name} });
			    return $class->SUPER::search(%argv, $opts);
			}
		    } 
		}
	    }
	    while ( @sections ){
		$argv{name} = join '.', @sections;
		$logger->debug(sub{ "Zone::search: $argv{name}" });
		if ( $class->SUPER::search(%argv, $opts) ){
		    # We call the method again to not mess
		    # with CDBI's wantarray checks
		    $logger->debug(sub{ "Zone::search: found: ", $argv{name} });
		    return $class->SUPER::search(%argv, $opts);
		}
		shift @sections;
	    }
	}
    }
    return wantarray ? @result : $result;
}

############################################################################

=head2 search_like - Search for Zone objects

    We override the base method to add functionality:

    - Search the ZoneAlias table in addition to the Zone table.

  Arguments: 
    Hash with key/value pairs
  Returns: 
    See Class::DBI search_like
  Examples:
    Zone->search_like(name=>$search)

=cut

sub search_like {
    my ($class, @args) = @_;
    $class->isa_class_method('search_like');

    @args = %{ $args[0] } if ref $args[0] eq "HASH";
    my $opts = @args % 2 ? pop @args : {};
    my %argv = @args;

    my (@result, $result);
    if (wantarray) {
        @result = $class->SUPER::search_like(%argv, $opts);
    } else {
        $result = $class->SUPER::search_like(%argv, $opts);
    }

    if (@result || $result) {
	return wantarray ? @result : $result;
    }elsif ( defined $argv{name} ){
	if ( my $alias = ZoneAlias->search_like(name=>$argv{name})->first ) {
	    return $class->SUPER::search(id => $alias->zone->id, $opts);
        }
    }
    return wantarray ? @result : $result;
}


#########################################################################

=head2 insert - Insert a new DNS Zone (SOA Record)

    We override the insert method for extra functionality.

 Args: 
    name      domain name *(required)
    mname     server name
    rname     mailbox name
    serial    YYYYMMDD+two digit serial number
    refresh   time before the zone should be refreshed
    retry     time before a failed refresh should be retried
    expire    max time before zone no longer authoritative
    minimum   negative caching TTL (RFC 2308)
    template  (optional) Name or ID of another zone to clone from
  Returns: 
    Zone object
  Examples:
    my $zone = Zone->insert({name=>'newzone.domain'});

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->throw_fatal("Model::Zone::insert: Missing required arguments")
	unless ( $argv->{name} );

    my $newzone;
    if ( $argv->{template} ){

	my $tzone = $class->objectify($argv->{template}) || 
	    $class->throw_user("Cannot determine Zone object from template: ".$argv->{template});
	
	my %state = (
	    name        => $argv->{name},
	    export_file => $argv->{export_file} || $argv->{name},
	    active      => $argv->{active}      || 1,
	    );

	# Copy values from template zone
	foreach my $field ( qw(mname rname refresh retry expire minimum default_ttl include) ){
	    $state{$field} = $tzone->$field;
	}
	$newzone = $class->SUPER::insert( \%state );

	# Clone records from template zone
	my $import_txt;
	foreach my $rr ( $tzone->records ){
	    my %rr_state = $rr->get_state();
	    delete $rr_state{id};
	    $rr_state{zone} = $newzone; 
	    my $new_rr = RR->insert(\%rr_state);
	    foreach my $sr ( $rr->sub_records ){
		my %sr_state = $sr->get_state();
		delete $sr_state{id};
		$sr_state{rr} = $new_rr;
		my $rclass = ref($sr);
		$rclass->insert(\%sr_state);
	    }
	}
	
    }else{
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

	$newzone = $class->SUPER::insert( \%state );
    }

    # Create '@' record if not already there
    my $apex = RR->find_or_create({name=>'@', zone=>$newzone});
    
    $newzone->update_serial();

    # Create PTR records if necessary
    $newzone->is_dot_arpa() && $newzone->add_ptrs();

    return $newzone;
}

############################################################################

=head2 - add_ptrs - Given a .arpa zone, add all the missing PTR records

  Args: 
    None
  Returns: 
    True
  Examples:
    $newzone->add_ptrs() if $newzone->is_dot_arpa();

=cut

sub add_ptrs {
    my ($self) = @_;
    $self->isa_object_method('add_ptrs');
    my $class = ref($self);

    if ( !$self->is_dot_arpa ){
	$self->throw_user("I can only update PTRs on a .arpa zone");
    }

    my $block = $class->_dot_arpa_to_ip($self->name);
    if ( my $ipb = Ipblock->search(address=>$block)->first ){
	foreach my $ip ( @{$ipb->get_descendants} ){
	    if ( $ip->is_address && $ip->a_records ){
		foreach my $ar ( $ip->a_records ){
		    $logger->debug("Adding/updating PTR record for ".$ip->address);
		    $ar->update_rrptr();
		}
	    }
	}
    }
    1;
}

############################################################################

=head2 - objectify - Convert to object as needed

  Args: 
    id, name or object
  Returns: 
    Zone object
  Examples:
    my $zone = Zone->objectify($zonestr);

=cut

sub objectify {
    my ($class, $z) = @_;
    $class->isa_class_method('objectify');

    if ( (ref($z) =~ /Zone/) ){
	return $z;
    }elsif ( $z =~ /\D/ ){
	return $class->search(name=>$z)->first;
    }else{
	# Must be an ID
	return $class->retrieve($z);
    }
}


=head1 INSTANCE METHODS
=cut

#########################################################################

=head2 update - Update Zone object

    Override the base method to:
    - Update PTR records if zone name changes
    
  Args: 
    Hashref of zone fields
  Returns: 
    See Netdot::Model::update()
  Examples:
    $zone->update(\%args);

=cut

sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');

    my $update_ptrs = 0;
    if ( $argv->{name} && $argv->{name} ne $self->name ){
	# We want to do this after the zone is updated
	$update_ptrs = 1;
    }

    my @res =  $self->SUPER::update($argv);

    if ( $update_ptrs ){
	foreach my $rr ( $self->records ){
	    $rr->update_ptr();
	}
    }
    return @res;
}


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
    my $text = "; Generated by Netdot -- http://netdot.uoregon.edu\n\n";
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

    my %args = (type=>'SOA');
    my @fields = qw(name mname serial refresh retry expire minimum);
    foreach my $field ( @fields ){
	$self->throw_user($self->get_label. ": Missing required field: '$field' in the SOA record")
	    unless (defined $self->$field && $self->$field ne "");

	$args{$field} = $self->$field;
    }

    # Fix mailbox if needed
    $args{rname} = $self->_encode_rname();
	
    my $soa = Net::DNS::RR->new(%args);
    my $string = $soa->string;

    # Since zone files can represent multiple domains, we want '@' instead of the zone name
    $string =~ s/^(.*)(IN\s+SOA)/\@\t$2/;

    return $string;
}

#########################################################################

=head2 update_serial - Update zone serial number based on configured format

    Netdot will initialize and update the Zone's SOA serial number 
    differently depending on ZONE_SERIAL_FORMAT config option. 
    Valid values are:

    'dateserial'  e.g. 2009050500
    'epoch'       e.g. 1241562763 (Unix epoch)
    'plain'       e.g. 123

  Args: 
    None
  Returns: 
    return value from update method
  Examples:
    $zone->update_serial();

=cut

sub update_serial {
    my ($self, $argv) = @_;
    $self->isa_object_method('update_serial');

    my $serial = $self->serial;

    my $format = Netdot->config->get('ZONE_SERIAL_FORMAT') || 'dateserial';

    if ( $format eq 'dateserial' ){
	# If current serial is from today, increment
	# the counter.  Otherwise, use today's date and 00.
	my $date   = $self->_dateserial();
	if ( $serial =~ /$date(\d{2})/ ){
	    my $counter = $1;
	    if ( $counter < 99 ){
		# we can't let the number have three digits because 
		# it would be higher than 2^32-1
		my $inc = sprintf("%02d", $counter+1);
		$serial = $date . $inc;
	    }else{
		$logger->warn("Zone::update_serial: zone ".$self->get_label ." serial reached max counter per day!");
		return;
	    }
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
    $self->isa_object_method('get_all_records');
    
    my $dbh = $self->db_Main;
    my $id = $self->id;
    my $order_by = ($self->is_dot_arpa)? 'pip.address,rr.name' : 'rr.name';
    my $q = "SELECT   rr.name, zone.name, aip.version, aip.address, rrtxt.txtdata, rrhinfo.cpu, rrhinfo.os,
                      rrptr.ptrdname, rrns.nsdname, rrmx.preference, rrmx.exchange, rrcname.cname, rrloc.id, 
                      rrsrv.id, rrnaptr.id, rrds.algorithm, rrds.key_tag, rrds.digest_type, rrds.digest, rr.active,
                      rraddr.ttl, rrtxt.ttl, rrhinfo.ttl, rrns.ttl, rrds.ttl, rrmx.ttl, rrcname.ttl, rrptr.ttl
             FROM     zone, rr
                      LEFT OUTER JOIN (ipblock aip CROSS JOIN rraddr) ON (rr.id=rraddr.rr AND aip.id=rraddr.ipblock)
                      LEFT OUTER JOIN (ipblock pip CROSS JOIN rrptr)  ON (rr.id=rrptr.rr  AND pip.id=rrptr.ipblock)
                      LEFT OUTER JOIN rrtxt   ON rr.id=rrtxt.rr
                      LEFT OUTER JOIN rrhinfo ON rr.id=rrhinfo.rr
                      LEFT OUTER JOIN rrns    ON rr.id=rrns.rr
                      LEFT OUTER JOIN rrds    ON rr.id=rrds.rr
                      LEFT OUTER JOIN rrmx    ON rr.id=rrmx.rr
                      LEFT OUTER JOIN rrcname ON rr.id=rrcname.rr
                      LEFT OUTER JOIN rrnaptr ON rr.id=rrnaptr.rr
                      LEFT OUTER JOIN rrsrv   ON rr.id=rrsrv.rr
                      LEFT OUTER JOIN rrloc   ON rr.id=rrloc.rr
             WHERE    rr.zone=zone.id AND zone.id=$id
	     ORDER BY $order_by";

    my $results = $dbh->selectall_arrayref($q);
    my %rec;
    my $count = 0;
    foreach my $r ( @$results ){
	my ( $name, $zone, $ipversion, $ip, $txtdata, $cpu, $os, 
	     $ptrdname, $nsdname, $mxpref, $exchange, $cname, $rrlocid, $rrsrvid, $rrnaptrid, 
	     $dsalgorithm, $dskeytag, $dsdigesttype, $dsdigest, $active,
             $rraddrttl, $rrtxtttl, $rrhinfottl, $rrnsttl, $rrdsttl, $rrmxttl, $rrcnamettl, $rrptrttl ) = @$r;

	next unless $active;
	$count++;
	$rec{$name}{order} = $count;

	if ( $ip ){
	    if ( $ipversion == 4 ){
		my $address = Ipblock->int2ip($ip, $ipversion);
		$rec{$name}{A}{$address} = $rraddrttl;
	    }elsif ( $ipversion == 6 ){
		my $address = Ipblock->int2ip($ip, $ipversion);
		$rec{$name}{AAAA}{$address} = $rraddrttl;
	    }else{
		$logger->error("Zone::print_to_file: $ip has unknown version: $ipversion");
		next;
	    }
	}
	$rec{$name}{NS}{"$nsdname"}            = $rrnsttl    if ($nsdname);
	$rec{$name}{DS}{"$dskeytag $dsalgorithm $dsdigesttype $dsdigest"}
	                                       = $rrdsttl    if ($dskeytag && $dsalgorithm && 
								 $dsdigesttype && $dsdigest);
	$rec{$name}{MX}{"$mxpref $exchange"}   = $rrmxttl    if (defined($mxpref) && $exchange);
	$rec{$name}{CNAME}{"$cname"}           = $rrcnamettl if ($cname);
	$rec{$name}{PTR}{"$ptrdname"}          = $rrptrttl   if ($ptrdname);
	$rec{$name}{TXT}{"\"$txtdata\""}       = $rrtxtttl   if ($txtdata);
	$rec{$name}{HINFO}{"\"$cpu\" \"$os\""} = $rrhinfottl if ($cpu && $os);
	$rec{$name}{LOC}{id}{$rrlocid}         = $rrlocid    if ($rrlocid);
	$rec{$name}{SRV}{id}{$rrsrvid}         = $rrsrvid    if ($rrsrvid);
	$rec{$name}{NAPTR}{id}{$rrnaptrid}     = $rrnaptrid  if ($rrnaptrid);

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
             COUNT(DISTINCT rrhinfo.id), COUNT(DISTINCT rrptr.id), COUNT(DISTINCT rrns.id), 
             COUNT(DISTINCT rrds.id), COUNT(DISTINCT rrmx.id),  COUNT(DISTINCT rrcname.id), 
             COUNT(DISTINCT rrloc.id), COUNT(DISTINCT rrsrv.id), COUNT(DISTINCT rrnaptr.id)
             FROM     zone z, rr rr
                      LEFT OUTER JOIN rrptr   ON rr.id=rrptr.rr
                      LEFT OUTER JOIN rrtxt   ON rr.id=rrtxt.rr
                      LEFT OUTER JOIN rrhinfo ON rr.id=rrhinfo.rr
                      LEFT OUTER JOIN rrns    ON rr.id=rrns.rr
                      LEFT OUTER JOIN rrds    ON rr.id=rrds.rr
                      LEFT OUTER JOIN rrmx    ON rr.id=rrmx.rr
                      LEFT OUTER JOIN rrcname ON rr.id=rrcname.rr
                      LEFT OUTER JOIN rrnaptr ON rr.id=rrnaptr.rr
                      LEFT OUTER JOIN rrsrv   ON rr.id=rrsrv.rr
                      LEFT OUTER JOIN rrloc   ON rr.id=rrloc.rr
             WHERE    rr.zone=z.id AND z.id=$id";

    my $q2 = "SELECT COUNT(DISTINCT ipv4.id)
             FROM     zone z, rr rr
                      LEFT OUTER JOIN (ipblock ipv4 CROSS JOIN rraddr) 
                      ON (rr.id=rraddr.rr AND ipv4.id=rraddr.ipblock AND ipv4.version=4)
             WHERE    rr.zone=z.id AND z.id=$id";
    
    my $q3 = "SELECT COUNT(DISTINCT ipv6.id)
             FROM     zone z, rr rr
                      LEFT OUTER JOIN (ipblock ipv6 CROSS JOIN rraddr) 
                      ON (rr.id=rraddr.rr AND ipv6.id=rraddr.ipblock AND ipv6.version=6)
             WHERE    rr.zone=z.id AND z.id=$id";

    my $dbh = $self->db_Main;
    my $r1  = $dbh->selectall_arrayref($q1);
    my $r2  = $dbh->selectall_arrayref($q2);
    my $r3  = $dbh->selectall_arrayref($q3);
    my %count;
    ($count{txt}, $count{hinfo}, $count{ptr}, $count{ns}, $count{ds}, $count{mx}, 
     $count{cname}, $count{loc}, $count{srv}, $count{rrnaptr}) = @{$r1->[0]};

    ($count{a})    = @{$r2->[0]};
    ($count{aaaa}) = @{$r3->[0]};

    return \%count;
}


############################################################################

=head2 import_records - Import records into zone
    
  Args: 
    rrs         -  Arrayref containing Net:DNS::RR objects (required unless text is passed)
    text        -  Text containing records (BIND format) (required unless rrs is passed)
    overwrite   -  Overwrite any existing records
    update_ptrs -  When inserting a A/AAAA record, insert/update the corresponding PTR
  Returns: 
    Nothing
  Examples:
    $zone->import_records(text=>$text);

=cut

sub import_records {
    my ($self, %argv) = @_;
    $self->isa_object_method('import_records');
    
    unless ( $argv{text} || $argv{rrs} ){
	$self->throw_fatal('Missing required arguments: text or rrs');
    }
    
    my $domain = $self->name;
    my $rrs;

    if ( $argv{text } ){
	eval {
	    my $zone_content = $argv{text};
	    $zone_content =~ s/\r\n/\n/g;
	    $rrs = Net::DNS::ZoneFile::Fast::parse(text=>$zone_content, origin=>$domain);
	};
	if ( my $e = $@ ){
	    $self->throw_user("Error parsing Zone data: $e")
	}
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
    
    my %new_ips;

    foreach my $rr ( @$rrs ){
	my $name = $rr->name;
	if ( $name eq $domain || $name eq "$domain." ){
	    $name = '@';
	}else {
	    if ( $name =~ /\.$domain/ ){
		$name =~ s/\.$domain\.?//;
	    }else{
		$logger->debug("Zone $domain: Ignoring out of zone data: $name");
		next;
	    }
	}

	my $nrr;
	my $ttl = $rr->ttl || $self->default_ttl;
	if ( exists $nrrs{$name} ){
	    $logger->debug("$domain: RR $name already exists in DB");
	    $nrr = $nrrs{$name};
	    if ( $argv{overwrite} ){
		$logger->debug("$domain: $name: Overwriting current records");
		$nrr->delete unless ref($nrr) eq "Class::DBI::Object::Has::Been::Deleted";
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
	    if ( $ipb = Ipblock->search(address=>$address)->first ){
		$ipb->update({status=>'Static'}) 
		    if ( !$ipb->status || $ipb->status->name eq 'Discovered') ;
	    }else{
		$logger->debug("$domain: Inserting Ipblock $address");
		$ipb = Ipblock->insert({ address        => $address,
					 status         => 'Static',
					 no_update_tree => 1});
		$new_ips{$ipb->version}++;
	    }
	    my $rraddr;
	    my %args = (rr=>$nrr, ipblock=>$ipb);
	    if ( $argv{overwrite} || !($rraddr = RRADDR->search(%args)->first) ){
		$args{ttl} = $ttl;
		$args{update_ptr} = $argv{update_ptrs};
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
		# Validation may fail if A/AAAA recors for exchange do not exist when MX
		# record is created. Disable when importing.
		$args{validate}   = 0; 
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
	}elsif ( $rr->type eq 'DS' ){
	    my $rrds;
	    if ( !($rrds = RRDS->search(rr=>$nrr, key_tag=>$rr->keytag)->first) ){
		$logger->debug("$domain: Inserting RRDS $name, ".$rr->keytag);
		$rrds = RRDS->insert(rr=>$nrr, ttl=>$ttl, algorithm=>$rr->algorithm, key_tag=>$rr->keytag, 
				     digest_type=>$rr->digtype, digest=>$rr->digest);
	    }
	}elsif ( $rr->type eq 'CNAME' ){
	    my $rrcname;
	    my %args = (rr=>$nrr, cname=>$rr->cname);
	    if ( $argv{overwrite} || !($rrcname = RRCNAME->search(%args)->first) ){
		$args{ttl} = $ttl;
		$logger->debug("$domain: Inserting RRCNAME $name, ".$rr->cname.", ttl: $ttl");
		$rrcname = RRCNAME->insert(\%args);
	    }
	}elsif ( $rr->type eq 'PTR' ){
	    my $rrptr;

	    my $ipaddr = $self->_dot_arpa_to_ip("$name.$domain");
	    
	    $logger->debug("$domain: Inserting Ipblock $ipaddr");

	    my $ipb;
	    if ( $ipb = Ipblock->search(address=>$ipaddr)->first ){
		$ipb->update({status=>'Static'})
		    if ( !$ipb->status || $ipb->status->name eq 'Discovered') ;
	    }else{
		$ipb = Ipblock->insert({ address        => $ipaddr,
					 status         => 'Static',
					 no_update_tree => 1 });
		$new_ips{$ipb->version}++;
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
	    my %args = (rr       => $nrr,
			port     => $rr->port,
			target   => $rr->target,
		);
	    if ( $argv{overwrite} || !($rrsrv = RRSRV->search(%args)->first) ){
		$args{priority} = $rr->priority,
		$args{weight}   = $rr->weight,
		$args{ttl}      = $ttl;
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

    if ( %new_ips ){
	# Update IP space hierarchy
	Ipblock->build_tree(4) if exists $new_ips{4};
	Ipblock->build_tree(6) if exists $new_ips{6};
    }

    1;
}

############################################################################

=head2 get_hosts - Retrieve a list of hosts in a given subnet or in all subnets.  

    For forward zones, the rows contain:
    rr.id, rr.name, ip.id, ip.address, ip.version, pysaddr.id, physaddr.address

    For reverse (.arpa) zones, the rows contain:
    rr.id, rr.name, ip.id, ip.address, ip.version, rrptr.ptrdname

  Args: 
    ipblock object or ID (optional)
  Returns: 
    Arrayref of arrayrefs
  Examples:
    $zone->get_hosts_in_ipblock();

=cut

sub get_hosts {
    my ($self, $ipblock) = @_;
    $self->isa_object_method('get_hosts');

    my $id = $self->id;
    my $q;
    if ( $self->is_dot_arpa ){
	$q = "SELECT          rr.id, rr.name, 
                              ip.id, ip.address, ip.version, 
                              rrptr.ptrdname, zone.name, zone.id
              FROM            zone, rr
              LEFT OUTER JOIN (ipblock AS ip CROSS JOIN rrptr) ON (rr.id=rrptr.rr AND ip.id=rrptr.ipblock)
              LEFT OUTER JOIN ipblock AS subnet ON ip.parent=subnet.id
              WHERE           rr.zone=zone.id AND zone.id=$id";

    }else{
	$q = "SELECT          rr.id, rr.name, 
                              ip.id, ip.address, ip.version, 
                              physaddr.id, physaddr.address, zone.name, zone.id
              FROM            zone, rr
              LEFT OUTER JOIN (ipblock AS ip CROSS JOIN rraddr)  ON (rr.id=rraddr.rr AND ip.id=rraddr.ipblock)
              LEFT OUTER JOIN ipblock AS subnet ON ip.parent=subnet.id
              LEFT OUTER JOIN (physaddr CROSS JOIN dhcpscope) ON (dhcpscope.ipblock=ip.id AND dhcpscope.physaddr=physaddr.id)
              WHERE           rr.zone=zone.id AND zone.id=$id";

    }
    
    if ( $ipblock ){
	$q .=  " AND subnet.id=$ipblock";
    }
    $q .= ' ORDER BY rr.name';
	
    my $dbh  = $self->db_Main;
    my $rows = $dbh->selectall_arrayref($q);
    return $rows;
}

############################################################################

=head2 - is_dot_arpa - Check if zone is in-addr.arpa or ip6.arpa

  Args: 
    None
  Returns: 
    0 or 1
  Examples:
    if ( $zone->is_dot_arpa() ) { }

=cut

sub is_dot_arpa {
    my ($self) = @_;
    $self->isa_object_method('is_dot_arpa');
    return 1 if ( $self->name =~ /\.arpa$/ );
    return 0;
}

############################################################################
#
# Private Methods
#
############################################################################


############################################################################
#_dot_arpa_to_ip - Convert a .arpa string into an IPv4 or IPv6 address
#
#  Arguments: 
#    .arpa string (*.in-addr.arpa or *.ip6.arpa)
#  Returns: 
#    IP or block address in CIDR format
#  Examples:
#    my $cidr = Zone->_dot_arpa_to_ip("4.3.2.1.in-addr.arpa");
#    $cidr == 1.2.3.4/32
#

sub _dot_arpa_to_ip {
    my ($class, $ipaddr) = @_;

    my $version;
    if ( $ipaddr =~ s/(.*)\.in-addr.arpa$/$1/ ){
	$version = 4;
    }elsif ( $ipaddr =~ s/(.*)\.ip6.arpa$/$1/ ){
	$version = 6;
    }

    # Transform RFC2317 format to real IP
    $ipaddr =~ s/\d+-\d+\.(\d+\.\d+\.\d+)/$1/g;

    my $plen; # prefix length
    if ( $version == 4 ){
	my @octets = (reverse split '\.', $ipaddr);
	$ipaddr = join '.', @octets;
	$plen = scalar(@octets) * 8;
	if ( $plen == 24 ){
	    $ipaddr .= '.0';
	}elsif ( $plen == 16 ){
	    $ipaddr .= '.0.0';
	}elsif ( $plen == 8 ){
	    $ipaddr .= '.0.0.0';
	}
    }elsif ( $version == 6 ){
	my @n = reverse split '\.', $ipaddr;
	$plen = scalar(@n) * 4; # each nibble is 4 bits
	my @g; my $m;
	for (my $i=1; $i<=scalar(@n); $i++){
	    $m .= $n[$i-1];
	    if ( $i % 4 == 0 ){
		push @g, $m;
		$m = "";
	    }
	}
	$ipaddr = join ':', @g;
	if ( $plen < 128 ){
	    $ipaddr .= '::';  # or it won't validate
	}
    }
    if ( Ipblock->validate($ipaddr, $plen) ){
	return ("$ipaddr/$plen");
    }else{
	$class->throw_user(sprintf("Invalid IP address: %s/%d", $ipaddr, $plen));
    }
}

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

############################################################################
# _encode_rname
# 
#  Make sure rname uses '.' instead of '@' as a separator
#
#  Arguments: 
#    None
#  Returns: 
#    String
#  Examples:
#    $zone->_encode_rname($rname)
#

sub _encode_rname {
    my ($self) = @_;
    return $self->rname unless ($self->rname =~ /\@/); # already encoded
    
    my ($first,$last) = split(/\@/, $self->rname, 2);
    $first =~ s/\./\\./;
    return $first . '.' . $last;
}


=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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

