package Netdot::Model::RRSRV;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRSRV - DNS SRV record Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

############################################################################
=head2 insert - Insert new RRSRV object

    We override the base method to:
    - Check for conflicting record types
    - Validate TTL
    

  Arguments:
    See schema
  Returns:
    RRSRV object
  Example:
    my $record = RRSRV->insert(\%args)

=cut
sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal('Missing required arguments: rr')
	unless ( $argv->{rr} );

    foreach my $field ( qw/port priority target weight/ ){
	$class->throw_user("Missing required argument: $field")
	    unless (defined $argv->{$field});
    }

    my $rr = (ref $argv->{rr})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;

    # TTL needs to be set and converted into integer
    $argv->{ttl} = (defined($argv->{ttl}) && length($argv->{ttl}))? $argv->{ttl} : $rr->zone->default_ttl;
    $argv->{ttl} = $class->ttl_from_text($argv->{ttl});


    # Make sure name is valid
    unless ( $rr->name =~ /^_\w+\._\w+/ ){
	$class->throw_user("Owner name must be of the form _Service._Proto");
    }

    # Avoid the "CNAME and other records" error condition
    if ( $rr->cnames ){
	$class->throw_user("Cannot add any other record to an alias");
    }
    if ( $rr->ptr_records ){
	$class->throw_user($rr->name.": Cannot add SRV records when PTR records exist");
    }
    if ( $rr->naptr_records ){
	$class->throw_user($rr->name.": Cannot add SRV records when NAPTR records exist");
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

    if ( defined $argv->{ttl} ){
	$argv->{ttl} = $self->ttl_from_text($argv->{ttl});
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
	name        => $self->rr->get_label,
	ttl         => $self->ttl,
	class       => 'IN',
	type        => 'SRV',
	priority    => $self->priority,
	weight      => $self->weight,
	port        => $self->port,
	target      => $self->target,
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

