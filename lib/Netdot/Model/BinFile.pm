package Netdot::Module::BinFile;

use warnings;
use strict;

# Make sure to return 1
1;

=head1 NAME

Netdot:: - 

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use template;

    my $foo = template->new();
    ...

=head1 CLASS METHODS

=head2 method1

  Arguments:

  Returns:

  Examples:

=head1 INSTANCE METHODS

=head2 method2

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


=head2 insertbinfile - inserts a binary file into the DB.

  $ret = $db->insertbinfile(file, filetype);

  inserts binary object into the BinFile table. If filetype is not
  specified it will be (hopefully) determined automatically.

  Returns the id of the newly inserted row, or 0 for failure and error
  should be set.

=cut
sub insertbinfile {
    my ($self, $fh, $filetype) = @_;
    my $extension = $1 if ($fh =~ /\.(\w+)$/);
    my %mimeTypes = ("jpg"=>"image/jpeg", "jpeg"=>"image/jpeg", "gif"=>"image/gif",
                     "png"=>"image/png", "bmp"=>"image/bmp", "tiff"=>"image/tiff",
                     "tif"=>"image/tiff", "pdf"=>"application/pdf");

    if (!exists($mimeTypes{lc($extension)})) {
        $self->error("File type could not be determined: extension \".$extension\" is unknown.");
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

    return $self->insert(table=>"BinFile", state=>\%tmp);
}

=head2 updatebinfile - updates a binary file in the DB.

  $ret = $db->updatebinfile(file, binfile_id);

  updates the the binary object with the specified id.

  Returns positive int on success, or 0 for failure and error
  should be set.

=cut
sub updatebinfile {
    my ($self, $fh, $id) = @_;
    my $extension = $1 if ($fh =~ /\.(\w+)$/);
    my %mimeTypes = ("jpg"=>"image/jpeg", "jpeg"=>"image/jpeg", "gif"=>"image/gif",
                     "png"=>"image/png", "bmp"=>"image/bmp", "tiff"=>"image/tiff",
                     "tif"=>"image/tiff", "pdf"=>"application/pdf");

    if (!exists($mimeTypes{lc($extension)})) {
        $self->error("File type could not be determined for $fh: extension \".$extension\" is unknown.");
        return 0;
    }

    my $obj = BinFile->retrieve($id);
    if (!defined($obj)) {
        $self->error("Could not locate row in BinFile with id $id.");
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

    return $self->update(object=>$obj, state=>\%tmp);
}


1;
