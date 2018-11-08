package Netdot::Model::RRMX;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

my $MAX_PREFERENCE = 2**16 - 1;

=head1 Netdot::Model::RRMX - DNS MX record Class

=head1 CLASS METHODS
=cut

############################################################################

=head2 insert - Insert new RRMX object

    We override the base method to:
    - Validate TTL
    - Check for conflicting record types
    - Validate preference
    - Validate exchange

  Arguments:
    All RRMX fields plus:
    - validate - (flag) Enable/disable validation (default on)
  Returns:
    RRMX object
  Example:
    my $record = RRMX->insert(\%args)

=cut

sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');

    $class->throw_fatal('Missing required arguments: rr')
	unless ( $argv->{rr} );
    
    $class->throw_user("Missing required argument: preference")
	unless defined $argv->{preference};
    
    $class->throw_user("Missing required argument: exchange")
	unless $argv->{exchange};
    
    my $rr = (ref $argv->{rr})? $argv->{rr} : RR->retrieve($argv->{rr});
    $class->throw_fatal("Invalid rr argument") unless $rr;

    # TTL needs to be set and converted into integer
    $argv->{ttl} = (defined($argv->{ttl}) && length($argv->{ttl}))? $argv->{ttl} : $rr->zone->default_ttl;
    $argv->{ttl} = $class->ttl_from_text($argv->{ttl});

    my $validate = delete $argv->{validate};
    defined $validate or $validate = 1;

    $class->_validate_args($argv) if $validate;

    # Avoid the "CNAME and other records" error condition
    if ( $rr->cnames ){
	$class->throw_user($rr->name.": Cannot add any other record to an alias");
    }
    if ( $rr->ptr_records ){
	$class->throw_user($rr->name.": Cannot add LOC records when PTR records exist");
    }

    if ( $rr->naptr_records ){
	$class->throw_user($rr->name.": Cannot add LOC records when NAPTR records exist");
    }

    if ( $rr->srv_records ){
	$class->throw_user($rr->name.": Cannot add LOC records when SRV records exist");
    }

    return $class->SUPER::insert($argv);
    
}

=head1 INSTANCE METHODS
=cut

############################################################################

=head2 update

    We override the base method to:
     - Validate TTL
     - Validate preference
    
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
    
    $self->_validate_args($argv);

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

# _validate_args - Validate arguments to insert and update
#
#  Args: 
#    hashref
#  Returns: 
#    True, or throws exception if validation fails
#  Examples:
#    $class->_validate_args($argv);
#
sub _validate_args {
    my ($self, $argv) = @_;

    if ( defined $argv->{preference} ){
	$self->throw_user("Invalid preference value: ".$argv->{preference})
	    if ( $argv->{preference} < 0 || $argv->{preference} > $MAX_PREFERENCE );
    }
    if ( defined $argv->{exchange} ){
	# If exchange belongs to a zone we own, and the zone is 
	# active, then make sure that it contains A/AAAA records.
	if ( my $z = (Zone->search(name=>$argv->{exchange}))[0] ){
	    if ( $z->active ){
		my $name = $argv->{exchange};
		my $domain = $z->name;
		$name =~ s/\.$domain$//;
		if ( $name eq $domain ){
		    $name = '@';
		}
		my $mxrr = RR->search(name=>$name, zone=>$z)->first;
		unless ( $mxrr ){
		    $self->throw_user("Exchange ".$argv->{exchange}.
				      " within active zone '$domain', but name '$name' does not exist");
		}
		unless ( $mxrr->a_records ){
		    $self->throw_user("Exchange ".$argv->{exchange}.
				      " has no address (A or AAAA) records");
		}
	    }
	}
    }
}

##################################################################
sub _net_dns {
    my $self = shift;
    
    my $ndo = Net::DNS::RR->new(
	name       => $self->rr->get_label,
	ttl        => $self->ttl,
	class      => 'IN',
	type       => 'MX',
	preference => $self->preference,
	exchange   => $self->exchange,
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

