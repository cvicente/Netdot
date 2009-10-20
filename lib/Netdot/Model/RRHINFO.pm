package Netdot::Model::RRHINFO;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRHINFO - DNS HINFO record Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

############################################################################
=head2 insert - Insert new RRHINFO object

    We override the base method to:
    - Check if owner is an alias
    - Check if owner has any other HINFO records

  Arguments:
    See schema
  Returns:
    RRHINFO object
  Example:
    my $record = RRHINFO->insert(\%args)

=cut
sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal('Missing required arguments: rr')
	unless ( $argv->{rr} );

    $class->throw_user("Missing required arguments: cpu and/or os")
	unless ( $argv->{cpu} && $argv->{os} );

    my $rr = (ref $argv->{rr})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;

    # TTL needs to be set and converted into integer
    $argv->{ttl} = (defined($argv->{ttl}) && length($argv->{ttl}))? $argv->{ttl} : $rr->zone->default_ttl;
    $argv->{ttl} = $class->ttl_from_text($argv->{ttl});

    # Avoid the "CNAME and other records" error condition
    if ( $rr->cnames ){
	$class->throw_user($rr->name." Cannot add any other record to an alias");
    }
    if ( $rr->ptr_records ){
	$class->throw_user($rr->name.": Cannot add HINFO records when PTR records exist");
    }

    if ( $rr->naptr_records ){
	$class->throw_user($rr->name.": Cannot add HINFO records when NAPTR records exist");
    }

    if ( $rr->srv_records ){
	$class->throw_user($rr->name.": Cannot add HINFO records when SRV records exist");
    }

    # Only one HINFO
    if ( $rr->hinfo_records ){
	$class->throw_user($rr->name.": Cannot add more than one HINFO record");
    }

    return $class->SUPER::insert($argv);
    
}

=head1 INSTANCE METHODS
=cut
############################################################################
=head2 update

    We override the base method to:
     - Validate TTL
    
  Arguments:
    Hash with field/value pairs
  Returns:
    Number of rows updated or -1
  Example:
    $record->update(\%args)

=cut
sub update {
    my($self, $argv) = @_;
    $self->isa_object_method('update');

    if ( defined $argv->{ttl} && length($argv->{ttl}) ){
	$argv->{ttl} = $self->ttl_from_text($argv->{ttl});
    }else{
	delete $argv->{ttl};
    }
    
    return $self->SUPER::update($argv);
}

##################################################################
=head2 as_text

    Returns the text representation of this record

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->as_text();

=cut
sub as_text {
    my $self = shift;
    $self->isa_object_method('as_text');

    return $self->_net_dns->string();
}


##################################################################
# Private methods
##################################################################


##################################################################
sub _net_dns {
    my $self = shift;

    my $ndo = Net::DNS::RR->new(
	name    => $self->rr->get_label,
	ttl     => $self->ttl,
	class   => 'IN',
	type    => 'HINFO',
	cpu     => $self->cpu,
	os      => $self->os,
	);
    
    return $ndo;
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

