package Netdot::Model::Asset;

use base 'Netdot::Model';
use warnings;
use strict;

=head1 NAME

Netdot::Model::Asset - Asset class

=head1 SYNOPSIS

my $installed = Asset->get_installed_hash();

=head1 CLASS METHODS
=cut

###########################################################################

=head2 get_installed_hash - Build a hash of installed assets keyed by id

  Arguments: 
    None
  Returns: 
    Hashref with key = asset.id, value = 1

=cut

sub get_installed_hash {
    my ($class) = @_;
    my %installed;
    my $dbh = $class->db_Main();
    # Note: Tried to do this in one query but for some reason it takes forever
    my $rows1 = $dbh->selectall_arrayref('
                       SELECT DISTINCT(asset.id) 
                       FROM   asset, device
                       WHERE  device.asset_id=asset.id');
    
    my $rows2 = $dbh->selectall_arrayref('
                       SELECT DISTINCT(asset.id) 
                       FROM   asset, devicemodule
                       WHERE  devicemodule.asset_id=asset.id');
    
    foreach my $row ( @$rows1, @$rows2 ){
	my $id = $row->[0];
	$installed{$id} = 1;
    }
    return \%installed;
}

###########################################################################

=head2 search_like -  Search for asset objects.  Allow substrings

  Overridden to allow producttype to be searched on

  Arguments: 
    Hash with key/value pairs
  Returns: 
    Array of Asset objects or iterator

=cut

sub search_like{
    my ($class, %argv) = @_;
    $class->isa_class_method('search_like');

    if ( $argv{producttype} ){
        if( $argv{producttype} == 11 ){
	    return $class->search_by_type_unknown($argv{producttype});
	}
        return $class->search_by_type($argv{producttype});
    }else{
        return $class->SUPER::search_like(%argv);
    }
}

__PACKAGE__->set_sql(by_type => qq{
    SELECT a.id
        FROM asset a 
        LEFT JOIN product p ON a.product_id = p.id
        LEFT JOIN producttype t ON p.type = t.id
	WHERE (t.id = ?)
    });

__PACKAGE__->set_sql(by_type_unknown => qq{
    SELECT a.id
        FROM asset a 
        LEFT JOIN product p ON a.product_id = p.id
        LEFT JOIN producttype t ON p.type = t.id
        WHERE t.id = ?
	OR a.product_id = 0
	OR a.product_id IS NULL
    });

__PACKAGE__->set_sql(by_device => qq{
    SELECT a.id
         FROM  asset a, device d, devicemodule m 
        WHERE  d.id = ?
          AND  ( d.asset_id = a.id
          OR   (m.device=d.id AND m.asset_id=a.id) )
    });

__PACKAGE__->set_sql(sn_mf => qq{
    SELECT asset.id 
    FROM   asset, product
    WHERE  asset.serial_number = ?
    AND  asset.product_id=product.id
    AND  product.manufacturer = ?
    });

1;

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
