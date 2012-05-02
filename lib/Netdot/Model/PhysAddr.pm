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
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    @args = %{ $args[0] } if ref $args[0] eq "HASH";
    my $opts = @args % 2 ? pop @args : {}; 
    my %argv = @args;
    
    if ( $argv{address} ){
	$argv{address} = $class->format_address($argv{address});
    }
    return $class->SUPER::search(%argv, $opts);
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
    hash ref with key = MAC address string
    timestamp
  Returns:   
    True if successul
  Examples:
    PhysAddr->fast_update(\%macs);

=cut
sub fast_update {
    my ($class, $macs, $timestamp) = @_;
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
	    $sth->execute($address, $timestamp, $timestamp);
	}
    }else{    
	# Build SQL queries
	my $sth1 = $dbh->prepare_cached("UPDATE physaddr SET last_seen=? WHERE address=?");	
	    
	my $sth2 = $dbh->prepare_cached("INSERT INTO physaddr (address,first_seen,last_seen,static)
                                         VALUES (?, ?, ?, '0')");	

	# Now walk our list
	foreach my $address ( keys %$macs ){
	    eval {
		$sth2->execute($address, $timestamp, $timestamp);
	    };
	    if ( my $e = $@ ){
		if ( $e =~ /Duplicate/i ){
		    # Update
		    eval {
			$sth1->execute($timestamp, $address);
		    };
		    if ( my $e = $@ ){
			$class->throw_fatal($e);
		    }
		}else{
		    $class->throw_fatal($e);
		}
	    }
	}
    }
    
    my $end = time;
    $logger->debug(sub{ sprintf("PhysAddr::fast_update: Done Updating: %d addresses in %s",
				scalar(keys %$macs), $class->sec2dhms($end-$start)) });
    
    return 1;
}

################################################################
=head2 validate - Format and validate MAC address strings

    Assumes that "000000000000", "111111111111" ... "FFFFFFFFFF" 
    are invalid.  Also invalidates known bogus and Multicast addresses.

  Arguments: 
    Physical address string
  Returns:   
    Physical address string in canonical format, false if invalid
  Examples:
    my $validmac = PhysAddr->validate('DEADDEADBEEF');

=cut
sub validate {
    my ($self, $addr) = @_;
    $self->isa_class_method('validate');

    return unless $addr;
    $addr = $self->format_address($addr);
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

    }elsif ( $addr =~ /^([0-9A-F]{2})/ && $1 =~ /.(1|3|5|7|9|B|D|F)/ ) {
	 # Multicast addresses
	$logger->debug(sub{ "PhysAddr::validate: address is Multicast: $addr" });
	return 0;	

    }elsif ( scalar(my @list = @{$self->config->get('IGNORE_MAC_PATTERNS')} ) ){
	foreach my $ignored ( @list ){
	    if ( $addr =~ /$ignored/i ){
		$logger->debug(sub{"PhysAddr::validate: address matches configured pattern ($ignored): $addr"});
		return 0;	
	    }
	}
    }
	 
    return $addr;
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
=head2 map_all_to_ints - Map all MAC addresses to their interfaces

  Arguments: 
    None
  Returns:   
    Hash ref of hash refs
     key => address
     value => hashref with key => int id, value => mac id
  Examples:
    my $macs_to_ints = PhysAddr->map_all_to_ints();

=cut
sub map_all_to_ints {
    my ($class) = @_;
    $class->isa_class_method('map_all_to_ints');

    # Build the SQL query
    $logger->debug(sub{ "PhysAddr::map_all_to_ints: Retrieving all Interface MACs..." });

    my $dbh = $class->db_Main;
    my $sth = $dbh->prepare_cached("SELECT p.id, p.address, i.id 
                                      FROM physaddr p, interface i 
                                     WHERE i.physaddr=p.id");	
    $sth->execute();
    my $mac_aref = $sth->fetchall_arrayref;

    # Build the hash
    my %map;
    foreach my $row ( @$mac_aref ){
	my ($mid, $address, $iid) = @$row;
	$map{$address}{$iid} = $mid;
    }
    $logger->debug(sub{ "Physaddr::map_all_to_ints: ...done" });

    return \%map;
    
}

#################################################################
=head2 from_devices - Get addresses that are devices' base MACs

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
                                        FROM   physaddr p, device d, asset a
                                        WHERE  a.physaddr=p.id 
                                           AND d.asset_id=a.id");
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

################################################################
=head2 - is_broad_multi - Check for broadcast/multicast bit

    IEEE 802.3 specifies that the lowest order bit in the first
    octet designates an address as broadcast/multicast.
    
  Arguments:
    As an object method, none.
    As a class method, the address is required.
  Returns:
    True or false
  Examples:
     PhysAddr->is_broad_multi($address)
    or 
     $physaddr->is_broad_multi();
=cut
sub is_broad_multi {
    my ($class, $address) = @_;
    my $self;
    if ( $self = ref($class) ){
	$address = $self->address;
    }else{
	$class->throw_fatal("PhysAddr::is_broad_multi: Need an address to continue")
	    unless $address;
    }
    my $dec = hex(substr($address, 1, 1));
    return 1 if ( $dec & 1 );
    return 0
}

=head1 INSTANCE METHODS
=cut

################################################################
=head2 colon_address - Return address with octets separated by colons

    This can be either an instance method or class method

  Arguments: 
    None if called as instance method
    address string if called as class method
  Returns:   
    String (e.g. 'DE:AD:DE:AD:BE:EF')
  Examples:
    print $physaddr->colon_address;
    print PhysAddr->colon_address('DEADDEADBEEF');

=cut
sub colon_address {
    my ($self, $address) = @_;
    my $class = ref($self);
    my $addr;
    if ( $class ){
	$addr = $self->address;
    }else{
	$addr = $address || 
	    $self->throw_fatal("PhysAddr::colon_address: Missing address string");
    }
    my @octets  = unpack("A2" x 6, $addr);
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
    None if called as an object method
    MAC Address if called as class method
  Returns:   
    String (e.g. 'Cisco Systems')
  Examples:
    print $physaddr->vendor;
    print PhysAddr->vendor('DEADEADBEEF');

=cut
sub vendor {
    my ($self, $address) = @_;
    my $class = ref($self) || $self;
    my $ouistr;
    if ( ref($self) ){
	# Being called as an object method
	$ouistr = $self->oui;
    }else{
	$class->throw_fatal("PhysAddr::vendor: Missing address") 
	    unless ( defined $address );
	$ouistr =  $class->_oui_from_address($address);
    }
    return $self->_get_vendor_from_oui($ouistr);
}

################################################################
=head2 find_edge_port - Find edge port where this MAC is located

    The idea is to get all device ports whose latest forwarding 
    tables included this address. 
    If we get more than one, select the one whose forwarding
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
    my $dbh = $self->db_Main();
    $sth = $dbh->prepare_cached('SELECT   DISTINCT(i.id), ft.id
                                 FROM     interface i, fwtableentry fte, fwtable ft 
                                 WHERE    fte.physaddr=? 
                                   AND    fte.interface=i.id 
                                   AND    fte.fwtable=ft.id
                                   AND    ft.tstamp=?
                                   AND    i.neighbor IS NULL');
    
	$sth->execute($self->id, $self->last_seen);
	$rows = $sth->fetchall_arrayref;

    if ( scalar @$rows > 1 ){
	my @results;
	$sth2 = $dbh->prepare_cached('SELECT COUNT(i.id) 
                                      FROM   interface i, fwtable ft, fwtableentry fte 
                                      WHERE  fte.fwtable=ft.id 
                                        AND  fte.interface=i.id 
                                        AND  ft.id=? 
                                        AND  fte.interface=?');
	
	foreach my $row ( @$rows ){
	    my ($iid, $ftid) = @$row;
	    $sth2->execute($ftid, $iid);
	    $rows2 = $sth2->fetchall_arrayref;
	    
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
    Array ref of timestamps and Interface IDs
  Examples:
    print $physaddr->get_last_n_fte(10);

=cut
sub get_last_n_fte {
    my ($self, $limit) = @_;
    $self->isa_object_method('get_last_n_fte');
    my $id = $self->id;
    my $dbh = $self->db_Main();
    my $q1 = "SELECT   ft.tstamp 
              FROM     physaddr p, interface i, fwtableentry fte, fwtable ft 
              WHERE    p.id=$id 
                AND    fte.physaddr=p.id 
                AND    fte.interface=i.id 
                AND    fte.fwtable=ft.id 
              GROUP BY ft.tstamp 
              ORDER BY ft.tstamp DESC
              LIMIT $limit";

    my @tstamps = @{ $dbh->selectall_arrayref($q1) };
    return unless @tstamps;
    my $tstamps = join ',', map { "'$_'" } map { $_->[0] } @tstamps;

    my $q2 = "SELECT   ft.tstamp, i.id
              FROM     physaddr p, interface i, fwtableentry fte, fwtable ft 
              WHERE    p.id=$id 
                AND    fte.physaddr=p.id 
                AND    fte.interface=i.id 
                AND    fte.fwtable=ft.id 
                AND    ft.tstamp IN($tstamps) 
              ORDER BY ft.tstamp DESC";
    
    return $dbh->selectall_arrayref($q2);
}

################################################################
=head2 get_last_n_arp - Get last N ARP entries

  Arguments: 
    limit  - Return N last entries (default: 10)
  Returns:   
    Array ref of timestamps and Interface IDs
  Examples:
    print $physaddr->get_last_n_arp(10);

=cut
sub get_last_n_arp {
    my ($self, $limit) = @_;
    $self->isa_object_method('get_last_n_arp');
	
    my $dbh = $self->db_Main();
    my $id = $self->id;
    my $q1 = "SELECT   arp.tstamp
              FROM     physaddr p, interface i, arpcacheentry arpe, arpcache arp, ipblock ip
              WHERE    p.id=$id AND arpe.physaddr=p.id AND arpe.interface=i.id 
                AND    arpe.ipaddr=ip.id AND arpe.arpcache=arp.id 
              GROUP BY arp.tstamp 
              ORDER BY arp.tstamp DESC
              LIMIT $limit";

    my @tstamps = @{ $dbh->selectall_arrayref($q1) };
    return unless @tstamps;
    my $tstamps = join ',', map { "'$_'" } map { $_->[0] } @tstamps;

    my $q2 = "SELECT   i.id, ip.id, arp.tstamp
              FROM     physaddr p, interface i, arpcacheentry arpe, arpcache arp, ipblock ip
              WHERE    p.id=$id 
                AND    arpe.physaddr=p.id 
                AND    arpe.interface=i.id 
                AND    arpe.ipaddr=ip.id 
                AND    arpe.arpcache=arp.id 
                AND    arp.tstamp IN($tstamps)
              ORDER BY arp.tstamp DESC";

    return $dbh->selectall_arrayref($q2);
}

################################################################
=head2 devices - Return devices whose base mac is this one

  Arguments: None
  Returns:   Array of Device objects
  Examples:
    my @devs = $physaddr->devices;

=cut
sub devices { 
    my ($self) = @_;
    map { $_->devices if ($_->devices) } $self->assets;
}

################################################################
=head2 search_interface_macs

  Arguments: 
    Interface id
    Timestamp
  Returns:   
    Array of PhysAddr objects
  Examples:
    my @macs = PhysAddr->search_interface_macs($iid, $tstamp)

=cut
__PACKAGE__->set_sql(interface_macs => qq{
SELECT p.id
FROM     physaddr p, interface i, fwtable ft, fwtableentry fte 
WHERE    fte.interface=i.id 
  AND    fte.fwtable=ft.id 
  AND    fte.physaddr=p.id 
  AND    i.id=? 
  AND    ft.tstamp=?
ORDER BY p.address    });

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
    $self->throw_user("Missing address") 
	unless $address;	
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
    $self->throw_user("Missing address")
	unless $address;
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

################################################################
# Get Vendor information given an OUI string
sub _get_vendor_from_oui {
    my ($class, $ouistr) = @_;
    my $oui = OUI->search(oui=>$ouistr)->first;
    return $oui->vendor if defined $oui;
    return "Unknown";    
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
