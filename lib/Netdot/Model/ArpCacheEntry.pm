package Netdot::Model::ArpCacheEntry;

use base 'Netdot::Model';
use warnings;
use strict;
use DBI qw(:sql_types);

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

# Make sure to return 1
1;

=head1 NAME 

Netdot::Model::ArpCacheEntry

=head1 SYNOPSIS

ARP Cache Entry class

=head1 CLASS METHODS
=cut

##################################################################

=head2 fast_insert - Faster inserts for specific cases

    This method will traverse a list of hashes containing ARP cache
    info.  Meant to be used by processes that insert/update large amounts of 
    objects.  We use direct SQL commands for improved speed.

  Arguments: 
    Array ref containing these keys:
    list = Arrayref of hash refs with following keys:
           arpcache  - id of ArpCache table record
           interface - id of Interface
           ipaddr    - ip address in numeric format
           version   - IP version
           physaddr  - string with mac address
  Returns:   
    True if successul
  Examples:
    ArpCacheEntry->fast_insert(list=>\@list);

=cut

sub fast_insert{
    my ($class, %argv) = @_;
    $class->isa_class_method('fast_insert');
    my $list = $argv{list} || $class->throw_fatal("Missing list arg");
    
    # Build SQL query
    my $dbh = $class->db_Main;
    my $sth = $dbh->prepare_cached("INSERT INTO arpcacheentry 
                                    (arpcache,interface,ipaddr,physaddr)
                                    VALUES (?, ?, 
                                    (SELECT id FROM ipblock WHERE address=? AND PREFIX=? AND version=?), 
                                    (SELECT id FROM physaddr WHERE address=?))");	
    # Now walk our list and insert
    foreach my $r ( @$list ){
	my $plen = ($r->{version} == 6)? 128 : 32;
	$sth->bind_param(1, $r->{arpcache});
	$sth->bind_param(2, $r->{interface});
	if ( $class->config->get('DB_TYPE') eq 'mysql' ){
	    # Workaround for http://bugs.mysql.com/bug.php?id=60213
	    # See another example in Ipblock::search()
	    $sth->bind_param(3, "".$r->{ipaddr}, SQL_INTEGER);
	}else{
	    $sth->bind_param(3, $r->{ipaddr});
	}
	$sth->bind_param(4, $plen);
	$sth->bind_param(5, $r->{version});
	$sth->bind_param(6, $r->{physaddr});
	$sth->execute();
    }
    
    return 1;
}


=head1 INSTANCE METHODS
=cut

=head2 search_by_ip - Retrieve all entries corresponding to given IP

    Returns list ordered by ArpCache timestamp.  Relies on SQL for 
    sorting timestamp values efficiently.

  Arguments: 
    Ipblock id
  Returns:   
    Array of ArpCacheEntry objects
  Examples:
    ArpCacheEntry->->search_by_ip($ip->id)

=cut

__PACKAGE__->set_sql(by_ip => qq{
    SELECT arpcacheentry.id, arpcacheentry.physaddr
	FROM arpcacheentry, arpcache, ipblock
	WHERE arpcacheentry.arpcache=arpcache.id AND
	arpcacheentry.ipaddr=ipblock.id AND
	ipblock.id = ?
	ORDER BY arpcache.tstamp DESC
    });


=head2 search_interface - Retrieve all entries for given interface and timestamp

  Arguments: 
    Interface id
    ArpCache timestamp
  Returns:   
    Array of ArpCacheEntry objects
  Examples:
    ArpCacheEntry->->search_interface($int->id, $tstamp)

=cut

__PACKAGE__->set_sql(interface => qq{
SELECT arpe.id
FROM   interface i, arpcache arp, arpcacheentry arpe
 WHERE arpe.interface=i.id 
   AND arpe.arpcache=arp.id 
   AND i.id=? 
   AND arp.tstamp=?
});

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

