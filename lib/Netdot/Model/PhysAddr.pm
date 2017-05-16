package Netdot::Model::PhysAddr;

use base 'Netdot::Model';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::PhysAddr - Physical Address Class

=head1 SYNOPSIS

    my $valid = PhysAddr->validate($str);
    my $p = PhysAddr->insert({address=>$address});
    my $p = PhysAddr->search(address=>'DEADDEADBEEF')->first;

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
	$argv{address} = $class->_format_address_db($argv{address});
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
    PhysAddr->search_like(address=>'DEAD');
=cut

sub search_like {
    my ($self, %argv) = @_;
    
    if ( $argv{address} ){
	if ( $argv{address} =~ /^'(.*)'$/ ){
	    # User wants exact match 
	    # do nothing
	}else{
	    $argv{address} = $self->_format_address_db($argv{address});
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
    PhysAddr->fast_update(\%macs, '2016-08-08 00:00:00');

=cut

sub fast_update {
    my ($class, $macs, $timestamp) = @_;
    $class->isa_class_method('fast_update');
    
    my $start = time;
    $logger->debug(sub{"PhysAddr::fast_update: Updating MAC addresses in DB"});
    
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
		# Probably duplicate. That's OK. Update
		eval {
		    $sth1->execute($timestamp, $address);
		};
		if ( my $e2 = $@ ){
		    # Something else is wrong
		    $logger->error($e2);
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
    Return message buffer (optional)
  Returns:   
    Physical address string in DB format
    Throws user exception if address is invalid
  Examples:
    my $validmac = PhysAddr->validate('DEADDEADBEEF');

=cut

sub validate {
    my ($class, $addr) = @_;

    $class->isa_class_method('validate');

    $class->throw_user("Address undefined")
	unless $addr;

    $addr = $class->_format_address_db($addr);
    my $displ = $class->format_address(address=>$addr);

    if ( $addr !~ /^[0-9A-F]{12}$/ ){
	$class->throw_user("$displ has illegal chars or size");
    }
    elsif ( $addr =~ /^([0-9A-F]{1})/o && $addr =~ /$1{12}/ ){
	# Assume the all-equal-bits address is invalid
	$class->throw_user("$displ looks bogus", $displ);
    }
    elsif ( $addr eq '000000000001' ){
	# Skip Passport 8600 CLIP MAC addresses
	$class->throw_user("$displ is CLIP");
    }
    elsif ( $addr =~ /^00005E00/io ){
	$class->throw_user("$displ is VRRP");
    }
    elsif ( $addr =~ /^00000C07AC/io ){
	$class->throw_user("$displ is HSRP");
    }
    elsif ( hex(substr($addr, 1, 1)) & 1  ){
	$class->throw_user("$displ is multicast");
    }
    elsif ( $addr =~ /^([0-9A-F]{2})/ && $1 =~ /.(1|3|5|7|9|B|D|F)/ ){
	$class->throw_user("$displ is multicast");
    }
    elsif ( scalar(my @list = @{$class->config->get('IGNORE_MAC_PATTERNS')}) ){
	foreach my $ignored ( @list ) {
	    if ( $addr =~ /$ignored/i ) {
		$class->throw_user("$displ matches pattern ($ignored)");
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

################################################################################

=head2 dhcpd_address - Return address with colons and configured caseness

  Arguments: 
    address string
  Returns:   
    Colon-separated string (e.g. 'DE:AD:DE:AD:BE:EF')
  Examples:
    print PhysAddr->dhcpd_address('DEADDEADBEEF');

=cut

sub dhcpd_address {
    my ($class, $addr) = @_;
    $class->isa_class_method('dhcpd_address');
    my $caseness = Netdot->config->get('MAC_DHCPD_FORMAT_CASENESS') || 'upper';
    return $class->format_address(
	address                   => $addr,
	format_caseness           => $caseness,
        format_delimiter_string   => ':',
        format_delimiter_interval => 2,
     );
}

################################################################################

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

################################################################

=head1 INSTANCE METHODS
=cut

################################################################


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
    map { $_->devices } $self->assets;
}

################################################################################

=head2 format_address - Formats the MAC address to specifications.

    This can be either an instance method or class method

    Arguments:
        Hash with the following keys:
          address
          format_caseness
          format_delimiter_string
          format_delimiter_interval

        address is set to the current object's address
        if called as an instance method.
    Returns:
        String (e.g. 'DE:AD:DE:AD:BE:EF')
    Examples:
        # instance method called using default formatting.
        print $physaddr->format_address;
        # DEADDEADBEEF

        # instance method called using lowercase formatting.
        print $physaddr->format_address(
            format_caseness => 'lower',
        );
        # deaddeadbeef

        # instance method called with parameters to yield a Cisco-like format.
        print $physaddr->format_address(
            format_caseness           => 'lower',
            format_delimiter_string   => '.',
            format_delimiter_interval => 4,
        );
        # dead.dead.beef

        # instance method called with parameters to yield a common format.
        print $physaddr->format_address(
            format_caseness           => 'lower',
            format_delimiter_string   => ':',
            format_delimiter_interval => 2,
        );
        # de:ad:de:ad:be:ef

        print PhysAddr->format_address(
            address                   => 'DEADDEADBEEF',
            format_caseness           => 'lower',
            format_delimiter_string   => ':',
            format_delimiter_interval => 2,
        );
        # de:ad:de:ad:be:ef
=cut

sub format_address {
    my ($self, %args) = @_;
    
    # Set some defaults
    my %defaults;
    $defaults{address} = $self->address if ref($self);
    $defaults{format_caseness} = $self->config->get(
	'MAC_DISPLAY_FORMAT_CASENESS') || 'upper';
    $defaults{format_delimiter_string} = $self->config->get(
	'MAC_DISPLAY_FORMAT_DELIMITER_STRING') // '';
    $defaults{format_delimiter_interval} = $self->config->get(
	'MAC_DISPLAY_FORMAT_DELIMITER_INTERVAL') // 0;
    
    # Use defaults if args missing
    foreach my $k (keys %defaults){
	$args{$k} = $defaults{$k} unless exists $args{$k};
    }
    
    foreach my $arg (qw(address format_caseness format_delimiter_string 
                     format_delimiter_interval)){
	$self->throw_user("PhysAddr::format_address: Missing argument: $arg") 
	    unless exists $args{$arg};
    }

    my %valid_intervals = map { $_ => 1 } (0, 1, 2, 3, 4, 6);
    $self->throw_user('Format delimiter interval must be '.
		      'one of 0, 1, 2, 3, 4, or 6')
	unless exists($valid_intervals{$args{format_delimiter_interval}});

    # By default we don't need to insert any delimiters into the address
    my $res = $args{address};
    $res =~ s/[^\da-f]//gi;

    # ...unless the delimiter interval is greater than zero.
    if ($args{format_delimiter_interval} > 0) {
        my $count = 12 / $args{format_delimiter_interval};
        my @groups = unpack("A$args{format_delimiter_interval}" x $count, 
			    $res);
        $res = join $args{format_delimiter_string}, @groups;
    }
    if ($args{format_caseness} eq 'upper') {
        $res = uc $res;
    }elsif ($args{format_caseness} eq 'lower') {
        $res = lc $res;
    }else {
        $self->throw_user('Format caseness must be set to "upper" or "lower".');
    }
    
    return $res;
}

#################################################
# PRIVATE METHODS
#################################################

#################################################
# _format_address_db - Format address for storage
#
#  Arguments: 
#    Address string
#  Returns:   
#    Formatted string
#
sub _format_address_db {
    my ($self, $address) = @_;
    my $retval = $self->format_address(
        address                   => $address,
        format_caseness           => 'upper',
        format_delimiter_interval => 0,
    );
    $logger->debug("PhysAddr::_format_address_db: MAC address ".
                   "($address) formatted for DB storage to: $retval");
    return $retval;
}

#################################################
# _deflate - Modify object before writing
#
#  Arguments: 
#    physical address object
#  Returns:   
#    True if successful
#
sub _obj_deflate {
    my $self = shift;
    my $address = __PACKAGE__->validate(($self->_attrs('address'))[0]);
    $self->_attribute_store(address=>$address);
    return 1;
}

#################################################
# _inflate - Modify object when reading
#
#  Arguments: 
#    physical address object
#  Returns:   
#    True if successful
#
sub _obj_inflate {
    my $self = shift;
    my $address = __PACKAGE__->format_address(
	address=>($self->_attrs('address'))[0]);
    $self->_attribute_store(address=>$address);
    return 1;
}

##################################################################
# Add some triggers
#
__PACKAGE__->add_trigger( deflate_for_create => \&_obj_deflate );
__PACKAGE__->add_trigger( deflate_for_update => \&_obj_deflate );
__PACKAGE__->add_trigger( select             => \&_obj_inflate );

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

=head1 AUTHORS

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
