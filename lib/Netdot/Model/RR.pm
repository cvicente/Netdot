package Netdot::Model::RR;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::RR - DNS Resource Record Class

=head1 SYNOPSIS

    Objects of this class do not contain actual DNS records.
    Each record type has its own table that references
    this base record.

    RR->search(name=>"some.domain.name")

=head1 CLASS METHODS
=cut

############################################################################
=head2 search - Search Resource Records

    We override the base class to extend functionality:

      - If zone key is not passed, name will be looked up assuming it might
        contain domain info.

  Arguments: 
    Hash with column/value pairs.  
    'name' can be either FQDN or host part of the name
  Returns: 
    RR object or undef
  Examples:
    RR->search(name=>'foo.bar')

=cut
sub search {
    my ($class, %argv) = @_;
    $class->isa_class_method('search');
    $class->throw_fatal('Missing required arguments')
	unless %argv;

    my ($rr, @sections);
    if ( (exists $argv{name}) && ($argv{name} =~ /\./)  && !exists $argv{zone} ){
	if ( my $zone = (Zone->search(mname=>$argv{name}))[0] ){
	    my $mname = $zone->mname;
	    $argv{name} =~ s/\.$mname//;
	    $argv{zone} = $zone->id;
	    return $class->SUPER::search(%argv);
	}else{
	    # Zone not found, just do normal search
	    return $class->SUPER::search(%argv);
	}
    }else{
	return $class->SUPER::search(%argv);
    }
    return;
}

############################################################################
=head2 search_like - Search Resource Records with wildcards

    We override the base class to extend functionality:

      - If zone key is not passed, name will be looked up assuming it might
        contain domain info.

  Arguments: 
    Hash with column/value pairs.  
    'name' can be either FQDN or host part of the name
  Returns: 
    RR object or undef
  Examples:
    RR->search_like(name=>"foo*.bar")

=cut
sub search_like {
    my ($class, %argv) = @_;
    $class->isa_class_method('search_like');
    $class->throw_fatal('Missing required arguments')
	unless %argv;

    my ($rr, @sections);
    if ( (exists $argv{name}) && ($argv{name} =~ /\./)  && !exists $argv{zone} ){
	if ( my $zone = (Zone->search(mname=>$argv{name}))[0] ){
	    my $mname = $zone->mname;
	    $argv{name} =~ s/\.$mname//;
	    $argv{zone} = $zone->id;
	    return $class->SUPER::search_like(%argv);
	}else{
	    # Zone not found, just do normal search
	    return $class->SUPER::search_like(%argv);
	}
    }else{
	return $class->SUPER::search_like(%argv);
    }
    return;
}


############################################################################
=head2 insert - Insert new RR

    We override the common insert method for extra functionality

 Argsuments: 
    name        Unique record identifier (AKA "owner")
    zone        Zone object, id or name. If not defined, will assume 
                'DEFAULT_DNSDOMAIN' from config file
                If defined, will create if necessary.
    The rest of RR table fields

  Returns: 
    New RR object

  Examples:
    my $newrr = RR->insert( { name=> $name } );

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('RR::insert: Missing required parameters: name')
	unless ( defined $argv->{name} );

    # Set default zone if needed
    $argv->{zone} = $class->config->get('DEFAULT_DNSDOMAIN') 
	unless ( defined $argv->{zone} );
    
    # Insert zone if necessary;
    my $zone;
    if ( ref( $zone = $argv->{zone} ) =~ /Zone/
	 || ( $zone = (Zone->search(id    =>$argv->{zone}))[0] )
	 || ( $zone = (Zone->search(mname =>$argv->{zone}))[0] )
	 ){
    }else{
	$zone = Zone->insert({ mname => $argv->{zone} });
	$logger->info(sprintf("Inserted new Zone: %s", $zone->get_label));
    }
    if ( my $rr = $class->search(name=>$argv->{name}, zone=>$zone)->first ){
	$class->throw_user(sprintf("RR::Insert: %s.%s already exists!", $rr->name, $rr->zone->mname));
    }
    # Set some defaults
    my %state = (name        => $argv->{name},
		 zone        => $zone->id,
		 active      => $argv->{active}      || 1,
		 auto_update => $argv->{auto_update} || 1,
		 );
    
    if ( my $newrr = $class->SUPER::insert(\%state) ){
	return $newrr;
    }
    return;
}

=head1 INSTANCE METHODS
=cut

##################################################################
=head2 get_label - Override get_label method

    Returns the full Resource Record name

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->get_label();

=cut
sub get_label {
    my $self = shift;
    return sprintf("%s.%s", $self->name, $self->zone->mname);
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

