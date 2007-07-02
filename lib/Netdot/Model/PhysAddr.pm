package Netdot::Model::PhysAddr;

use base 'Netdot::Model';
use warnings;
use strict;
use Carp;

use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::PhysAddr - Physical Address Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

################################################################
=head2 update - Update PhysAddr object

    We override the update method for extra functionality

  Arguments: 
    Hashref with PhysAddr fields
  Returns:   
    Updated PhysAddr object
  Examples:

=cut

sub update {
    my ($self, $argv) = @_;
    
    $argv->{last_seen} = $self->timestamp()
	unless exists ( $argv->{last_seen} );

    return $self->SUPER::update( $argv );
}

################################################################
=head2 insert - Insert PhysAddr object

    We override the insert method for extra functionality

  Arguments: 
    Hash ref with PhysAddr fields
  Returns:   
    New PhysAddr object
  Examples:
    PhysAddr->insert(address=>'DEADDEADBEEF');
=cut

sub insert {
    my ($self, $argv) = @_;
    
    $argv->{first_seen} = $self->timestamp();
    $argv->{last_seen}  = $self->timestamp();
    $argv->{static}     = defined($argv->{static}) ?  $argv->{static} : 0;
    return $self->SUPER::insert( $argv );
}

############################################################################
=head2 retrieve_all_hashref - Build a hash with all addresses

    Retrieves all macs from the DB
    and stores them in a hash, indexed by address.
    The value is the PhysAddr id

  Arguments: 
    None
  Returns:   
    Hash reference 
  Examples:
    my $db_macs = PhysAddr->retriev_all_hashref();


=cut
sub retrieve_all_hashref {
    my ($class) = @_;
    $class->isa_class_method('retrieve_all_hashref');

    # Build the search-all-macs SQL query
    $logger->debug("PhysAddr::retrieve_all_hashref: Retrieving all MACs...");
    my ($mac_aref, %db_macs, $sth);

    my $dbh = $class->db_Main;
    eval {
	$sth = $dbh->prepare_cached("SELECT id,address FROM physaddr");	
	$sth->execute();
	$mac_aref = $sth->fetchall_arrayref;
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    # Build a hash of mac addresses.
    foreach my $row ( @$mac_aref ){
	my ($id, $address) = @$row;
	$db_macs{$address} = $id;
    }
    $logger->debug("PhysAddr::retrieve_all_hashref: ...done");

    return \%db_macs;
}

##################################################################
=head2 fast_update - Faster updates for specific cases

    This method will traverse a list of hashes containing a MAC address
    and a timestamp.  If a record does not exist with that address,
    it is created and both timestamps ('first_seen' and 'last_seen') are 
    instantiated.
    If the address already exists, only the 'last_seen' timestamp is
    updated.

    Meant to be used by processes that insert/update large amounts of 
    objects.  We use direct SQL commands for improved speed.

  Arguments: 
    hash ref consisting of:
    key       - String containing MAC address
    value     - timestamp
  Returns:   
    True if successul
  Examples:
    PhysAddr->fast_update(\%macs);

=cut
sub fast_update {
    my ($class, $macs) = @_;
    $class->isa_class_method('fast_update');
    
    my $start = time;
    $logger->debug("PhysAddr::fast_update: Updating MAC addresses in DB");
    
    my $db_macs = $class->retrieve_all_hashref;
    
    my $dbh = $class->db_Main;
    my $sth;
    
    # Build SQL queries
    my ($sth1, $sth2);
    eval {
	$sth1 = $dbh->prepare_cached("UPDATE physaddr SET last_seen=?
                                     WHERE id=?
                                    ");	
	
	
	$sth2 = $dbh->prepare_cached("INSERT INTO physaddr (address, first_seen, last_seen)
                                     VALUES (?, ?, ?)
                                    ");	
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    
    # Now walk our list and do the right thing
    eval{
	foreach my $address ( keys %$macs ){
	    my $timestamp = $macs->{$address};
	    if ( exists $db_macs->{$address} ){
		$sth1->execute($timestamp, $db_macs->{$address});
	    }else{
		$sth2->execute($address, $timestamp, $timestamp);
	    }
	}
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    
    my $end = time;
    $logger->debug(sprintf("PhysAddr::fast_update: Done Updating: %d addresses in %d secs",
			   scalar(keys %$macs), ($end-$start)));
    
    return 1;
}

################################################################
=head2 validate - Perform validation of MAC address strings

    String must look like "DEADDEADBEEF".
    Assumes that "000000000000", "111111111111" ... "FFFFFFFFFF" 
    are invalid.  Also invalidates known bogus and Multicast addresses.

  Arguments: 
    physical address (string)
  Returns:   
    True if valid, False if invalid
  Examples:
    PhysAddr->validate('DEADDEADBEEF');

=cut
sub validate {
    my ($self, $addr) = @_;

    return unless $addr;

    if ( $addr !~ /^[0-9A-F]{12}$/ ){
	# Format must be DEADDEADBEEF
	$logger->debug("PhysAddr::validate: Bad format: $addr");
	return 0;

    }elsif ( $addr =~ /^([0-9A-F]{1})/ && $addr =~ /$1{12}/ ) {
	# Assume the all-equal-bits address is invalid
	$logger->debug("PhysAddr::validate: Bogus address: $addr");
	return 0;

    }elsif ( $addr eq '000000000001' ) {
	 # Skip Passport 8600 CLIP MAC addresses
	$logger->debug("PhysAddr::validate: CLIP: $addr");
	return 0;

    }elsif ( $addr =~ /^00005E00/i ) {
	 # Skip VRRP addresses
	$logger->debug("PhysAddr::validate: VRRP: $addr");
	return 0;

    }elsif ( $addr =~ /^00000C07AC/i ) {
	 # Skip VRRP addresses
	$logger->debug("PhysAddr::validate: HSRP: $addr");
	return 0;

    }elsif ( $addr =~ /^([0-9A-F]{2})/  && $1 =~ /.(1|3|5|7|9|B|D|F)/ ) {
	 # Multicast addresses
	$logger->debug("PhysAddr::validate: address is Multicast: $addr");
	return 0;	
    }
	 
    return 1;
}

#################################################################
=head2 from_interfaces - Get addresses that belong to interfaces


  Arguments: 
    None
  Returns:   
    Hash ref keyed by address
  Examples:
    my $intmacs = PhysAddr->from_interfaces();

=cut
sub from_interfaces {
    my ($class) = @_;
    $class->isa_class_method('from_interfaces');

    # Build the SQL query
    $logger->debug("PhysAddr::from_interfaces: Retrieving all Interface MACs...");
    my ($mac_aref, %int_macs, $sth);

    my $dbh = $class->db_Main;
    eval {
	$sth = $dbh->prepare_cached("SELECT p.id,p.address 
                                     FROM physaddr p, interface i 
                                     WHERE i.physaddr=p.id");	
	$sth->execute();
	$mac_aref = $sth->fetchall_arrayref;
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    # Build a hash of mac addresses.
    foreach my $row ( @$mac_aref ){
	my ($id, $address) = @$row;
	$int_macs{$address} = $id;
    }
    $logger->debug("Physaddr::from_interfaces: ...done");

    return \%int_macs;
    
}


#################################################
=head2 canonicalize - Remove all non-numeric characters from address 

    Called just before inserting.
    Search methods will also need to convert to this format prior to searching.

  Arguments: 
    physical address object
  Returns:   
    True if successful
  Examples:

=cut    
sub canonicalize {
    my $self = shift;
    my $address = ($self->_attrs('address'))[0];
    $address =~ s/[:\.\-]//g;
    $address = uc($address);
    unless ( $self->validate( $address ) ){
	$self->throw_user("Invalid Address: $address");	
    }
    $self->_attribute_store( address => $address );
}

#################################################
# Add some triggers

__PACKAGE__->add_trigger( deflate_for_create => \&canonicalize );
__PACKAGE__->add_trigger( deflate_for_update => \&canonicalize );



# PRIVATE METHODS


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
