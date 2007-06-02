package Netdot::Model::ArpCacheEntry;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

# Make sure to return 1
1;

=head1 NAME

Netdot::Model::ArpCacheEntry - 

=head1 SYNOPSIS

Arp Cache Entry class


=head1 CLASS METHODS
=cut

##################################################################
=head2 fast_insert - Faster inserts for specific cases

    This method will traverse a list of hashes containing ARP cache
    info.  Meant to be used by processes that insert/update large amounts of 
    objects.  We use direct SQL commands for improved speed.

  Arguments: 
    Array ref containing hash refs with following keys:
    arpcache  - id of ArpCache table record
    interface - id of Interface
    ipaddr    - string with ip address
    physaddr  - string with mac address
   
  Returns:   
    True if successul
  Examples:
    ArpCacheEntry->fast_insert(list=>\@list);

=cut
sub fast_insert{
    my ($class, %argv) = @_;
    $class->isa_class_method('fast_insert');

    my $list    = $argv{list};
    my $db_macs = PhysAddr->retrieve_all_hashref();
    my $db_ips  = Ipblock->retrieve_all_hashref();

    my $dbh = $class->db_Main;

    # Build SQL query
    my $sth;
    eval {
	$sth = $dbh->prepare_cached("INSERT INTO ArpCacheEntry 
                                     (arpcache,interface,ipaddr,physaddr)
                                     VALUES (?, ?, ?, ?)
                                    ");	
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    
    # Now walk our list and insert
    eval{
	foreach my $r ( @$list ){
	    if ( exists $db_macs->{$r->{physaddr}} && exists $db_ips->{$r->{ipaddr}} ){
		$sth->execute($r->{arpcache}, 
			      $r->{interface},
			      $db_ips->{$r->{ipaddr}},
			      $db_macs->{$r->{physaddr}},
			      );
	    }else{
		$logger->error(sprintf("Netdot::Model::ArpCacheEntry: Error inserting: Missing MAC: %s or IP: %s", 
				    $r->{physaddr}, $r->{ipaddr}));
	    }
	}
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    
    return 1;
}


=head1 INSTANCE METHODS

=cut

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

