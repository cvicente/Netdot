package Netdot::Model::Zone;

use base 'Netdot::Model';
use warnings;
use strict;

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
	serial      => $argv->{serial}      || $class->_dateserial . "00",
	refresh     => $argv->{refresh}     || $class->config->get('DEFAULT_DNSREFRESH'),
	retry       => $argv->{retry}       || $class->config->get('DEFAULT_DNSRETRY'),
	expire      => $argv->{expire}      || $class->config->get('DEFAULT_DNSEXPIRE'),
	minimum     => $argv->{minimum}     || $class->config->get('DEFAULT_DNSMINIMUM'),
	active      => $argv->{active}      || 1,
	export_file => $argv->{export_file} || $argv->{name},
	default_ttl => $argv->{default_ttl} || $class->config->get('ZONE_DEFAULT_TTL'),
	);

    my $newzone = $class->SUPER::insert( \%state );
    
    return $newzone;
}


=head1 INSTANCE METHODS
=cut

#########################################################################
=head2 as_text
    
    Return the text representation of the Zone file. 
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
=head2 print_to_file -  Print the zone file as text

 Args: 
    Hashref with following key/value pairs:
        nopriv  - Flag.  Exclude private data (TXT and HINFO)
  Returns: 
    True
  Examples:
    $zone->print_to_file();

=cut
sub print_to_file{
    my ($self, %argv) = @_;
    $self->isa_object_method('print_to_file');
    
    my $dir = Netdot->config->get('BIND_EXPORT_DIR') 
	|| $self->throw_user('BIND_EXPORT_DIR not defined in config file!');
    
    my $filename = $self->export_file;
    unless ( $filename ){
	$logger->warn('Export filename not defined for this zone: '. $self->name.' Using zone name.');
	$filename = $self->name;
    }
    my $path = "$dir/$filename";
    my $fh = Netdot::Exporter->open_and_lock($path);
    $self->_update_serial();

    # Print the default TTL
    print $fh '$TTL '.$self->default_ttl."\n" if (defined $self->default_ttl);

    # Print the SOA record
    print $fh $self->soa_string . "\n";

    # Unfortunately, iterating over each RR and getting its as_text is too slow
    # for large zones, so we do this crazy query

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
	unless ( $argv{nopriv} ){
	    $rec{$name}{TXT}{"\"$txtdata\""}       = $rrtxtttl   if ($txtdata);
	    $rec{$name}{HINFO}{"\"$cpu\" \"$os\""} = $rrhinfottl if ($cpu && $os);
	}
	$rec{$name}{LOC}{id}   = $rrlocid   if ($rrlocid);
	$rec{$name}{SRV}{id}   = $rrsrvid   if ($rrsrvid);
	$rec{$name}{NAPTR}{id} = $rrnaptrid if ($rrnaptrid);
    }

    foreach my $name ( sort {$a cmp $b} keys %rec ){
	foreach my $type ( qw/A AAAA TXT HINFO NS MX CNAME PTR NAPTR SRV LOC/ ){
	    if ( defined $rec{$name}{$type} ){
		# Special cases.  These are relatively rare and hard to print.
		if ( $type =~ /(LOC|SRV|NAPTR)/ ){
		    my $rrclass = 'RR'.$type;
		    my $id = $rec{$name}{$type}{id};
		    my $rr = $rrclass->retrieve($id);
		    print $fh $rr->as_text, "\n";
		}else{ 
		    foreach my $data ( keys %{$rec{$name}{$type}} ){
			my $ttl = $rec{$name}{$type}{$data};
			if ( !defined $ttl || $ttl !~ /\d+/ ){
			    $logger->debug("$name $type: TTL not defined or invalid. Using Zone default");
			    $ttl = $self->default_ttl;
			}
			print $fh "$name\t$ttl\tIN\t$type\t$data\n";
		    }
		}
	    }
	}
    }
    close($fh);
    $logger->info("Zone ".$self->name." written to file: $path");
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
    
    my $date   = $self->_dateserial();
    my $serial = $self->serial;
    
    # If current serial is from today, increment
    # the counter.  Otherwise, use today's date and 00.
    if ( $serial =~ /$date(\d{2})/ ){
	my $inc = sprintf("%02d", $1+1);
	$serial = $date . $inc;
    }else{
	$serial = $date . '00';
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

