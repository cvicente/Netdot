package Netdot::Module::BinFile;

use warnings;
use strict;

# Make sure to return 1
1;

=head1 NAME

Netdot::Module::BinFile

=head1 SYNOPSIS

=head1 CLASS METHODS

#############################################################################
=head2 insert - Inserts a binary file into the DB.

  Inserts binary object into the BinFile table. If filetype is not
  specified it will be (hopefully) determined automatically.

  Arguments:
    file
    filetype
  Returns:
    See Class::DBI
  Examples:
  $ret = BinFile->insert(file, filetype);

=cut
sub insert {
    my ($self, $fh, $filetype) = @_;
    my $extension = $1 if ($fh =~ /\.(\w+)$/);
    my %mimeTypes = ("jpg" => "image/jpeg", "jpeg" => "image/jpeg", "gif" => "image/gif",
                     "png" => "image/png",  "bmp"  => "image/bmp", "tiff" => "image/tiff",
                     "tif" => "image/tiff", "pdf"  => "application/pdf");

    if (!exists($mimeTypes{lc($extension)})) {
        $self->error("File type could not be determined: extension \".$extension\" is unknown.");
        return 0;
    }

    my $mimetype = $mimeTypes{lc($extension)};
    my $data;
    while (<$fh>) {
        $data .= $_;
    }

    my %tmp = (bindata  => $data,
	       filename => $fh,
	       filetype => $mimetype,
	       filesize => -s $fh,
	       );

    return $self->SUPER::insert(\%tmp);
}

=head1 INSTANCE METHODS
=cut

#############################################################################
=head2 update - Updates a binary file in the DB.

  Arguments:
    file
  Returns:
    See Class::DBI
  Examples:
    $ret = BinFile->update(file);

=cut
sub update {
    my ($self, $fh) = @_;
    my $extension = $1 if ($fh =~ /\.(\w+)$/);
    my %mimeTypes = ("jpg"=>"image/jpeg", "jpeg"=>"image/jpeg", "gif"=>"image/gif",
                     "png"=>"image/png", "bmp"=>"image/bmp", "tiff"=>"image/tiff",
                     "tif"=>"image/tiff", "pdf"=>"application/pdf");

    if (!exists($mimeTypes{lc($extension)})) {
        $self->error("File type could not be determined for $fh: extension \".$extension\" is unknown.");
        return 0;
    }

    my $mimetype = $mimeTypes{lc($extension)};
    my $data;
    while (<$fh>) {
        $data .= $_;
    }

    my %tmp;
    $tmp{bindata} = $data;
    $tmp{filename} = $fh;
    $tmp{filetype} = $mimetype;
    $tmp{filesize} = -s $fh;

    return $self->SUPER::update(\%tmp);
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

1;
