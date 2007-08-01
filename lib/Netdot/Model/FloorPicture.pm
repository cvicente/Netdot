package Netdot::Model::FloorPicture;

use base 'Netdot::Model::Picture';
use warnings;
use strict;

# Make sure to return 1
1;

=head1 NAME

Netdot::Module::FloorPicture

=head1 SYNOPSIS

See Netdot::Model::Picture

=head1 CLASS METHODS
=cut

sub insert {
    my ($self, $argv) = @_;
     defined $argv->{floor}  ||
	$self->throw_fatal("Missing required arguments: floor");
    
    return $self->SUPER::insert($argv);
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
