package Netdot::Model::Site;

use base 'Netdot::Model';
use warnings;
use strict;

# Make sure to return 1
1;

=head1 NAME

Netdot::Module::Site

=head1 SYNOPSIS

See Netdot::Model::Site

=head1 CLASS METHODS
=cut

=head2 with_backbones

=cut

__PACKAGE__->set_sql(with_backbones => qq{
SELECT   site.id 
FROM     site, closet, backbonecable 
WHERE    (backbonecable.start_closet=closet.id OR backbonecable.end_closet=closet.id) 
  AND    closet.site=site.id 
GROUP BY site.id, site.name    
ORDER BY site.name
});

__PACKAGE__->set_sql(with_closets => qq{
SELECT   site.id 
FROM     site, closet
WHERE    closet.site=site.id 
GROUP BY site.id, site.name    
ORDER BY site.name
});

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright University of Oregon, all rights reserved.

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
