package Netdot::NetdotPermissionFactory;

use Apache2::SiteControl::PermissionManager;
use Apache2::SiteControl::GrantAllRule;
use Netdot::SectionAccessRule;
use Netdot::ObjectAccessRule;

=head2 NAME

Netdot::NetdotPermissionFactory;

=cut

our $manager;

=head1 METHODS

=head2 getPermissionManager

=cut

sub getPermissionManager
{
   return $manager if defined($manager);

   $manager = new Apache2::SiteControl::PermissionManager;
   $manager->addRule(new Apache2::SiteControl::GrantAllRule);
   $manager->addRule(new Netdot::SectionAccessRule);
   $manager->addRule(new Netdot::ObjectAccessRule);

   return $manager;
}

=head1 AUTHORS

Carlos Vicente, Nathan Collins, Aaron Parecki, Peter Boothe.

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

# Make sure to return 1
1;


