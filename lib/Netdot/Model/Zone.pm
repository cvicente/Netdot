package Netdot::Model::Zone;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

# Some regular expressions
my $IPV4        = Netdot->get_ipv4_regex();
my $IPV6        = Netdot->get_ipv6_regex();

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

         mname=>dns.cs.local.domain

      we will look for a Zone object in this order:

        dns.cs.local.domain (not found)
        cs.local.domain     (not found)
        local.domain        (found)
        return 'local.domain'

  Arguments: 
    Hash with key/value pairs
  Returns: 
    See Class::DBI search
  Examples:
    Zone->search(mname=>'some.domain.name')

=cut
sub search {
    my ($class, %argv) = @_;
    $class->isa_class_method('search');

    if ( exists $argv{id} && $argv{id} =~ /\D+/ ){
	# No use searching for non-digits in id field
	$argv{id} = 0;
    } 
    if ( $class->SUPER::search(%argv) ){
	return $class->SUPER::search(%argv);
    }elsif ( defined $argv{mname} && $argv{mname} =~ /\./ && $argv{mname} !~ /^($IPV4)$/ ){
	my @sections = split '\.', $argv{mname};
	while ( @sections ){
	    $argv{mname} = join '.', @sections;
	    $logger->debug(sub{ "Zone::search: $argv{mname}" });
	    if ( $class->SUPER::search(%argv) ){
		# We call the method again to not mess
		# with CDBI's wantarray checks
		$logger->debug(sub{ "Zone::search: found: ", $argv{mname} });
		return $class->SUPER::search(%argv);
	    }
	    shift @sections;
	}
    }else{
	return $class->SUPER::search(%argv);
    }
}


#########################################################################
=head2 insert - Insert a new DNS Zone (SOA Record)

    We override the insert method for extra functionality

 Args: 
    mname     domain name *(required)
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
    Zone->insert( { mname=>{'newzone.tld'} } );

=cut
sub insert {
    my ($class, $argv) = @_;
    $class->throw_fatal("Model::Zone::insert: Missing required arguments")
	unless ( $argv->{mname} );

    # Some defaults
    my %state = (mname     => $argv->{mname},
		 rname     => $argv->{rname}   || "hostmaster.".$argv->{mname},
		 serial    => $argv->{serial}  || $class->_dateserial . "00",
		 refresh   => $argv->{refresh} || $class->config->get('DEFAULT_DNSREFRESH'),
                 retry     => $argv->{retry}   || $class->config->get('DEFAULT_DNSRETRY'),
                 expire    => $argv->{expire}  || $class->config->get('DEFAULT_DNSEXPIRE'),
                 minimum   => $argv->{minimum} || $class->config->get('DEFAULT_DNSMINIMUM'),
                 active    => $argv->{active}  || 1,
		 reverse   => $argv->{reverse} || 0,
		 );

    my $newzone = $class->SUPER::insert( \%state );
    
    # We want all the existing RR's to fall under this new zone when appropriate
    my $mname = $newzone->mname;
    if ( my @rrs = RR->retrieve_all() ){
	foreach my $rr ( @rrs ){
	    my $fqdn = $rr->get_label;
	    if ( $fqdn =~ /\.$mname$/ ){
		my $newname = $fqdn;
		$newname =~ s/\.$mname$//;
		$rr->update({name=>$newname, zone=>$newzone});
	    }
	}
    }

    return $newzone;
}


=head1 INSTANCE METHODS
=cut

#########################################################################
=head2 update

    We override the base method for extra functionality:
    - Automatically assign the serial number if not provided

 Args: 
    Hashref with key/value pairs
  Returns: 
    Zone object
  Examples:
    Zone->update( { mname=>{'some.other.name'} } );

=cut
sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');
    
    my $date = $self->_dateserial();
    my $serial = $self->serial;
    
    # If current serial is from today, increment
    # the counter.  Otherwise, use today's date and 00.
    if ( $serial =~ /$date(\d{2})/ ){
	my $inc = sprintf("%02d", $1+1);
	$serial = $date . $inc;
    }else{
	$serial = $date . '00';
    }
    
    $argv->{serial} ||= $serial;

    return $self->SUPER::update($argv);
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

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 University of Oregon, all rights reserved.

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

