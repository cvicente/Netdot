package Netdot::Model::DataCache;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger("Netdot::Model");

=head1 NAME

Netdot::Model::DataCache

=head1 SYNOPSIS

The purpose of this class is only to add triggers for data manipulation,
which are only needed when Postgres is used as the database.

=cut

#################################################
# Add some triggers
#
# Postgresql's fields of type 'bytea' must be encoded prior to storing
#
__PACKAGE__->add_trigger( deflate_for_create => \&_encode_bindata );
__PACKAGE__->add_trigger( deflate_for_update => \&_encode_bindata );
__PACKAGE__->add_trigger( select             => \&_decode_bindata );

#################################################
#
#    Called before insert/update
#
sub _encode_bindata{
    my $self = shift;
    return 1 unless ( $self->config->get('DB_TYPE') eq 'Pg' );
    my $data = ($self->_attrs('data'))[0];
    my $encoded = APR::Base64::encode($data);
    $self->_attribute_store( data => $encoded );
    return 1;
}

#################################################
#
#     Called before select
#
sub _decode_bindata{
    my $self = shift;
    return 1 unless ( $self->config->get('DB_TYPE') eq 'Pg' );
    my $id = $self->id;
    my $dbh = $self->db_Main;
    my $encoded = ($dbh->selectrow_array("SELECT data FROM datacache WHERE id = $id"))[0];
    unless ( $encoded ){
	$logger->error("DataCache::_decode_bindata: No data available from DataCache id $id");
	return 1;
    }
    my $decoded = APR::Base64::decode($encoded);
    unless ( $decoded ){
	$logger->error("DataCache::_decode_bindata: Problem decoding bindata for DataCache id $id");
	return 1;
    }
    $self->_attribute_store( data => $decoded );
    return 1;
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

1;
