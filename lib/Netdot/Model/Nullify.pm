package Class::DBI::Cascade::Nullify;

=head1 NAME

Class::DBI::Cascade::Nullify - Set Foreign keys to null when deleting

=head1 SYNOPSIS

This is a Cascading Delete strategy that will nullify the foreign keys 
of relatd objects/ See Class::DBI for more information.

=cut

use strict;
use warnings;

use base 'Class::DBI::Cascade::None';

=head2 cascade

=cut 

sub cascade {
    my ($self, $obj) = @_;
    map { $_->set($self->{_rel}->args->{foreign_key}, undef); 
	  $_->update;
    } $self->foreign_for($obj);
}

=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >> with contributions from Nathan Collins and Aaron Parecki.

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
