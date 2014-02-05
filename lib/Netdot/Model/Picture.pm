package Netdot::Model::Picture;

use base 'Netdot::Model';
use warnings;
use strict;
use APR::Base64;

=head1 NAME

Netdot::Module::Picture

=cut

my %MIMETYPES = (
    "jpg" => "image/jpeg", "jpeg" => "image/jpeg", "gif" => "image/gif",
    "png" => "image/png",  "bmp"  => "image/bmp", "tiff" => "image/tiff",
    "tif" => "image/tiff", "pdf"  => "application/pdf");

my $logger = Netdot->log->get_logger("Netdot::Model");

=head1 CLASS METHODS

#############################################################################

=head2 insert - Inserts a picture into the DB.

  If filetype is not specified it will be (hopefully) determined automatically.

  Arguments:
    Key value pairs
  Returns:
    New Picture object
  Examples:
    $newobj = Picture->insert({filename=>'filename.ext'});

=cut

sub insert {
    my ($self, $argv) = @_;
    ( defined $argv->{filename} && defined $argv->{bindata} ) ||
	$self->throw_fatal("Missing required arguments: filename, bindata");
    
    # Grab extension
    my $extension = $1 if ( $argv->{filename} =~ /\.(\w+)$/ );
    
    # Determine filetype
    if ( !exists $argv->{filetype} && defined $extension ){
	# Try to guess type from extension
	$extension = lc($extension);
	$argv->{filetype} = $MIMETYPES{$extension} ||
	    $self->throw_user("File type could not be determined: extension \".$extension\" is unknown.");
    }else{
	$self->throw_user("File type could not be determined.");
    }
    $argv->{filesize} ||= length($argv->{bindata});
    return $self->SUPER::insert($argv);
}

#################################################
# Handle PostgreSQL's bytea types correctly. 
#

if (__PACKAGE__->config->get('DB_TYPE') eq 'Pg') {
    require DBD::Pg;
    __PACKAGE__->data_type(bindata => { pg_type => &DBD::Pg::PG_BYTEA });
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
