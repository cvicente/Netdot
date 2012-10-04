package Netdot::Model::RRCNAME;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 Netdot::Model::RRCNAME - DNS CNAME record Class

=head1 CLASS METHODS
=cut

############################################################################

=head2 insert - Insert new RRCNAME object

    We override the base method to:
    - Validate TTL
    - Check for conflicting record types

  Arguments:
    rr
    cname
    ttl
  Returns:
    RRCNAME object
  Example:
    my $record = RRCNAME->insert(\%args)

=cut

sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal('Missing required arguments: rr')
	unless ( $argv->{rr} );

    $class->throw_user("Missing required argument: cname")
	unless $argv->{cname};

    my $rr = (ref $argv->{rr})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;

    # TTL needs to be set and converted into integer
    $argv->{ttl} = (defined($argv->{ttl}) && length($argv->{ttl}))? $argv->{ttl} : $rr->zone->default_ttl;
    $argv->{ttl} = $class->ttl_from_text($argv->{ttl});

    my %linksfrom = RR->meta_data->get_links_from;
    foreach my $i ( keys %linksfrom ){
	if ( $rr->$i ){
	    $class->throw_user("Cannot add CNAME records when other records exist");
	}
    }

    my $newcname = $class->SUPER::insert($argv);
    
    # If the record we're pointing to is in this zone, and it doesn't exist
    # insert it.
    unless ( RR->search(name=>$newcname->cname)->first ){
	my $zone = $rr->zone;
	my $zone_name = $zone->name;
	if ( $newcname->cname =~ /\.$zone_name$/ ){
	    my $owner = $newcname->cname;
	    $owner =~ s/\.$zone_name$//;
	    RR->insert({name=>$owner, zone=>$zone});
	}
    }
    
    return $newcname;
    
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


############################################################################

=head2 delete - Delete object
    
    We override the delete method for extra functionality:
    - When removing a RRCNAME object, the RR (name)
    associated with it needs to be deleted too.

  Arguments:
    None
  Returns:
    True if successful. 
  Example:
    $rrcname->delete;

=cut

sub delete {
    my $self = shift;
    $self->isa_object_method('delete');
    my $rr = $self->rr;
    $self->SUPER::delete();
    $rr->delete();

    return 1;
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
	type    => 'CNAME',
	cname   => $self->cname,
	);
    
    return $ndo;
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

