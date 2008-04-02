package Netdot::Model::PhysAddr;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::PhysAddr - Physical Address Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

################################################################
=head2 search - Search PhysAddr objects

    Formats address before searching

  Arguments: 
    Hash ref with PhysAddr fields
  Returns:   
    PhysAddr object(s) or undef
  Examples:
    PhysAddr->search(address=>'DEADDEADBEEF');
=cut

sub search {
    my $self = shift;
    my $args = ref $_[0] eq "HASH" ? shift : {@_};
    
    if ( $args->{address} ){
	$args->{address} = $self->format_address($args->{address});
    }
    return $self->SUPER::search($args);
}


################################################################
=head2 search_like - Search PhysAddr objects

    Formats address before searching

  Arguments: 
    Hash ref with PhysAddr fields
  Returns:   
    PhysAddr object(s) or undef
  Examples:
    PhysAddr->search(address=>'DEADDEADBEEF');
=cut

sub search_like {
    my ($self, %argv) = @_;
    
    if ( $argv{address} ){
	if ( $argv{address} =~ /^'(.*)'$/ ){
	    # User wants exact match 
	    # do nothing
	}else{
	    $argv{address} = $self->format_address($argv{address});
	}
    }
    return $self->SUPER::search_like(%argv);
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
    $logger->debug(sub{ "PhysAddr::retrieve_all_hashref: Retrieving all MACs..." });
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
    $logger->debug(sub{ "PhysAddr::retrieve_all_hashref: ...done" });

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
    $logger->debug(sub{ "PhysAddr::fast_update: Updating MAC addresses in DB" });
    
    my $dbh = $class->db_Main;
    if ( $class->config->get('DB_TYPE') eq 'mysql' ){
	# Take advantage of MySQL's "ON DUPLICATE KEY UPDATE" 
	my $sth = $dbh->prepare_cached("INSERT INTO physaddr (address,first_seen,last_seen,static)
                                     VALUES (?, ?, ?, '0')
                                     ON DUPLICATE KEY UPDATE last_seen=VALUES(last_seen);");	
	foreach my $address ( keys %$macs ){
	    my $timestamp = $macs->{$address};
	    eval {
		$sth->execute($address, $timestamp, $timestamp);
	    };
	    if ( my $e = $@ ){
		if ( $e =~ /Duplicate/ ){
		    # Since we're parallelizing, an address
		    # might get inserted after we get our list.
		    # Just go on.
		    next;
		}else{
		    $class->throw_fatal($e);
		}
	    }
	}
    }else{    
	my $db_macs = $class->retrieve_all_hashref;
	# Build SQL queries
	my $sth1 = $dbh->prepare_cached("UPDATE physaddr SET last_seen=?
                                         WHERE id=?");	
	    
	my $sth2 = $dbh->prepare_cached("INSERT INTO physaddr (address, first_seen, last_seen, static)
                                         VALUES (?, ?, ?, '0')");	

	# Now walk our list and do the right thing
	foreach my $address ( keys %$macs ){
	    my $timestamp = $macs->{$address};
	    if ( !exists $db_macs->{$address} ){
		# Insert
		eval {
		    $sth2->execute($address, $timestamp, $timestamp);
		};
		if ( my $e = $@ ){
		    if ( $e =~ /Duplicate/ ){
			# Since we're parallelizing, an address
			# might get inserted after we get our list.
			# Just go on.
			next;
		    }else{
			$class->throw_fatal($e);
		    }
		}
	    }else{
		# Update
		eval {
		    $sth1->execute($timestamp, $db_macs->{$address});
		};
		if ( my $e = $@ ){
		    $class->throw_fatal($e);
		}
	    }
	}
    }
    
    my $end = time;
    $logger->debug(sub{ sprintf("PhysAddr::fast_update: Done Updating: %d addresses in %d secs",
				scalar(keys %$macs), ($end-$start)) });
    
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
    $self->isa_class_method('validate');

    return unless $addr;

    if ( $addr !~ /^[0-9A-F]{12}$/ ){
	# Format must be DEADDEADBEEF
	$logger->debug(sub{ "PhysAddr::validate: Bad format: $addr" });
	return 0;

    }elsif ( $addr =~ /^([0-9A-F]{1})/ && $addr =~ /$1{12}/ ) {
	# Assume the all-equal-bits address is invalid
	$logger->debug(sub{ "PhysAddr::validate: Bogus address: $addr" });
	return 0;

    }elsif ( $addr eq '000000000001' ) {
	 # Skip Passport 8600 CLIP MAC addresses
	$logger->debug(sub{ "PhysAddr::validate: CLIP: $addr" });
	return 0;

    }elsif ( $addr =~ /^00005E00/i ) {
	 # Skip VRRP addresses
	$logger->debug(sub{ "PhysAddr::validate: VRRP: $addr" });
	return 0;

    }elsif ( $addr =~ /^00000C07AC/i ) {
	 # Skip VRRP addresses
	$logger->debug(sub{ "PhysAddr::validate: HSRP: $addr" });
	return 0;

    }elsif ( $addr =~ /^([0-9A-F]{2})/  && $1 =~ /.(1|3|5|7|9|B|D|F)/ ) {
	 # Multicast addresses
	$logger->debug(sub{ "PhysAddr::validate: address is Multicast: $addr" });
	return 0;	
    }
	 
    return 1;
}

#################################################################
=head2 from_interfaces - Get addresses that belong to interfaces


  Arguments: 
    None
  Returns:   
    Hash ref key=address, value=id
  Examples:
    my $intmacs = PhysAddr->from_interfaces();

=cut
sub from_interfaces {
    my ($class) = @_;
    $class->isa_class_method('from_interfaces');

    # Build the SQL query
    $logger->debug(sub{ "PhysAddr::from_interfaces: Retrieving all Interface MACs..." });
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
    $logger->debug(sub{ "Physaddr::from_interfaces: ...done" });

    return \%int_macs;
    
}

#################################################################
=head2 from_interfaces - Get addresses that are devices' base MACs

  Arguments: 
    None
  Returns:   
    Hash ref key=address, value=id
  Examples:
    my $intmacs = PhysAddr->from_devices();

=cut
sub from_devices {
    my ($class) = @_;
    $class->isa_class_method('from_devices');

    # Build the SQL query
    $logger->debug(sub{ "PhysAddr::from_devices: Retrieving all Device MACs..." });
    my ($mac_aref, %dev_macs);

    my $dbh = $class->db_Main;
    eval {
	my $sth = $dbh->prepare_cached("SELECT p.id,p.address 
                                        FROM physaddr p, device d
                                        WHERE d.physaddr=p.id");
	$sth->execute();
	$mac_aref = $sth->fetchall_arrayref;
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    # Build a hash of mac addresses.
    foreach my $row ( @$mac_aref ){
	my ($id, $address) = @$row;
	$dev_macs{$address} = $id;
    }
    $logger->debug(sub{ "Physaddr::from_devices: ...done" });
    return \%dev_macs;
    
}

#################################################################
=head2 infrastructure - Get all infrastructure MACs

  Arguments: 
    None
  Returns:   
    Hash ref key=address, value=id
  Examples:
    my $intmacs = PhysAddr->infrastructure();

=cut
sub infrastructure {
    my ($class) = @_;
    $class->isa_class_method('infrastructure');
    
    my $int_macs = $class->from_interfaces();
    my $dev_macs = $class->from_devices();
    my %inf_macs = %{$int_macs};
    foreach my $address ( keys %$dev_macs ){
	$inf_macs{$address} = $dev_macs->{$address};
    }
    return \%inf_macs;
}

################################################################
=head2 vendor_count - Count MACs by vendor
    
  Arguments:
    type  -  [infrastructure|node|all]
  Returns:
    Array with:
       - Hash ref keyed by oui, value is count
       - Total of given type 
  Examples:
    my %count = PhysAddr->vendor_count();

=cut
sub vendor_count{
    my ($self, $type) = @_;
    $self->isa_class_method('vendor_count');
    $type ||= 'all';
    my (%res, $macs);
    if ( $type eq 'infrastructure' ){
	$macs = $self->infrastructure();
    }elsif ( $type eq 'node' ){
	my $infra = $self->infrastructure();
	my $all   = $self->retrieve_all_hashref();
	foreach my $address ( keys %$all ){
	    if ( !exists $infra->{$address} ){
		$macs->{$address} = $all->{$address};
	    }
	}
    }elsif ( $type eq 'all' ){
	$macs = $self->retrieve_all_hashref();
    }
    my $total = 0;
    my $OUI = OUI->retrieve_all_hashref;
    foreach my $address ( keys %$macs ){
	my $oui = $self->_oui_from_address($address);
	my $vendor = $OUI->{$oui} || "Unknown";
	$res{$oui}{vendor} = $vendor;
	$res{$oui}{total}++;
	$total++;
    }
    return (\%res, $total);
}

=head1 INSTANCE METHODS
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
=head2 colon_address - Return address with octets separated by colons

  Arguments: 
    None
  Returns:   
    String (e.g. 'DE:AD:DE:AD:BE:EF')
  Examples:
    print $physaddr->colon_address;

=cut
sub colon_address {
    my ($self) = @_;
    $self->isa_object_method('colon_address');
    my $addr = $self->address;
    my @octets  = unpack("A1" x 6, $addr);
    return join ':', @octets;
}

################################################################
=head2 oui - Return Organizationally Unique Identifier for a given PhysAddr object

  Arguments: 
    None
  Returns:   
    String (e.g. '00022F')
  Examples:
    print $physaddr->oui;

=cut
sub oui {
    my ($self) = @_;
    $self->isa_object_method('oui');
    return $self->_oui_from_address($self->address);
}

################################################################
=head2 vendor - Return OUI vendor name

  Arguments: 
    None
  Returns:   
    String (e.g. 'Cisco Systems')
  Examples:
    print $physaddr->vendor;

=cut
sub vendor {
    my ($self) = @_;
    $self->isa_object_method('vendor');
    my $ouistr = $self->oui;
    my $oui = OUI->search(oui=>$ouistr)->first;
    return $oui->vendor if defined $oui;
    return "Unknown";
}

################################################################
=head2 find_edge_port - Find edge port where this MAC is located

    The idea is to get all non-neighboring device ports 
    whose latest forwarding tables included this address. 
    If topology status is complete, this would ideally be only one
    port.  If we get more than one, select the one whose forwarding
    table had the least entries.

  Arguments: 
    None
  Returns:   
    Interface id
  Examples:
    print $physaddr->find_edge_port;

=cut
sub find_edge_port {
    my ($self) = @_;
    $self->isa_object_method('find_edge_port');
    my ($sth, $sth2, $rows, $rows2);
    eval {
	my $dbh = $self->db_Main();
	$sth = $dbh->prepare_cached('SELECT i.id, ft.id, MAX(ft.tstamp) 
                                         FROM interface i, fwtableentry fte, fwtable ft 
                                         WHERE fte.physaddr=? AND fte.interface=i.id AND fte.fwtable=ft.id AND i.neighbor=0 
                                         GROUP BY i.id');
	
	$sth2 = $dbh->prepare_cached('SELECT COUNT(i.id) 
                                          FROM interface i, fwtable ft, fwtableentry fte 
                                          WHERE fte.fwtable=ft.id AND fte.interface=i.id AND ft.id=? AND fte.interface=?');
	
	$sth->execute($self->id);
	$rows = $sth->fetchall_arrayref;
    };
    if ( my $e = $@ ){
	$self->throw_fatal($e);
    }
    
    if ( scalar @$rows > 1 ){
	my @results;
	foreach my $row ( @$rows ){
	    my ($iid, $ftid, $tstamp) = @$row;
	    eval{
		$sth2->execute($ftid, $iid);
		$rows2 = $sth2->fetchall_arrayref;
	    };
	    if ( my $e = $@ ){
		$self->throw_fatal($e);
	    }
	    foreach my $row2 ( @$rows2 ){
		my ($count) = @$row2;
		push @results, [$count, $iid];
	    }
	}
	@results = sort { $a->[0] <=> $b->[0] } @results;
	my $result = $results[0];
	return $result->[1];
    }else{
	return $rows->[0]->[0];
    }
}


################################################################
=head2 get_last_n_fte - Get last N forwarding table entries

  Arguments: 
    limit  - Return N last entries (default: 10)
  Returns:   
    Array ref of Interface ids and timestamps
  Examples:
    print $physaddr->get_last_n_fte(10);

=cut
sub get_last_n_fte {
    my ($self, $limit) = @_;
    $self->isa_object_method('get_last_n_fte');
	
    my $dbh = $self->db_Main();
    my $sth;
    my $q = "SELECT i.id, ft.tstamp 
             FROM physaddr p, interface i, fwtableentry fte, fwtable ft 
             WHERE p.id=? AND fte.physaddr=p.id AND fte.interface=i.id 
                   AND fte.fwtable=ft.id 
             ORDER BY ft.tstamp DESC LIMIT $limit";
    eval {
	$sth = $dbh->prepare($q);
	$sth->execute($self->id);
    };
    if ( my $e = $@ ){
	$self->throw_fatal($e);
    }
    return $sth->fetchall_arrayref;
}

################################################################
=head2 get_last_n_arp - Get last N forwarding table entries

  Arguments: 
    limit  - Return N last entries (default: 10)
  Returns:   
    Array ref of Interface ids and timestamps
  Examples:
    print $physaddr->get_last_n_arp(10);

=cut
sub get_last_n_arp {
    my ($self, $limit) = @_;
    $self->isa_object_method('get_last_n_arp');
	
    my $dbh = $self->db_Main();
    my $sth;
    my $q = "SELECT i.id, ip.id, arp.tstamp
             FROM physaddr p, interface i, arpcacheentry arpe, arpcache arp, ipblock ip
             WHERE p.id=? AND arpe.physaddr=p.id AND arpe.interface=i.id 
                   AND arpe.ipaddr=ip.id AND arpe.arpcache=arp.id 
             ORDER BY arp.tstamp DESC LIMIT $limit";
    eval {
	$sth = $dbh->prepare($q);
	$sth->execute($self->id);
    };
    if ( my $e = $@ ){
	$self->throw_fatal($e);
    }
    return $sth->fetchall_arrayref;
}

#################################################
# Add some triggers

__PACKAGE__->add_trigger( deflate_for_create => \&_canonicalize );
__PACKAGE__->add_trigger( deflate_for_update => \&_canonicalize );


#################################################
# PRIVATE METHODS
#################################################

#################################################
# _canonicalize - Convert MAC address to canonical form
#
#    - Formats address
#    - Calls validate function
#
#  Arguments: 
#    physical address object
#  Returns:   
#    True if successful
#
sub _canonicalize {
    my $self = shift;
    my $class = ref($self) || $self;
    my $address = ($self->_attrs('address'))[0];
    $address = $self->format_address($address);
    unless ( $class->validate( $address ) ){
	$self->throw_user("Invalid Address: $address");	
    }
    $self->_attribute_store( address => $address );
}


#################################################
# format_address - Format MAC address
#    - Removes usual separators
#    - Converts to all uppercase
#
sub format_address {
    my ($self, $address) = @_;
    $address =~ s/[:\-\.]//g;
    $address = uc($address);
    return $address;
}

################################################################
# Extract first 6 characters from MAC address 
#
sub _oui_from_address {
    my ($self, $addr) = @_;
    return substr($addr, 0, 6);
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
