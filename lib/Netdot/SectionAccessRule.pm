package Netdot::SectionAccessRule;

use Apache2::SiteControl::Rule;
@ISA = qw(Apache2::SiteControl::Rule);
use strict;
use Netdot::Model;

=head1 NAME

Apache2::SiteControl::SectionAccessRule

=cut

=head2 DESCRIPTION

    This rule is going to be used in a system that automatically grants
    permission for everything (via the GrantAllRule). So this rule will
    only worry about what to deny, and the grants method can return whatever.

=cut

my $logger = Netdot->log->get_logger("Netdot::UI");

=head1 METHODS

=head2 grants

=cut

sub grants()
{
   return 0;
}

=head2 denies

=cut

sub denies(){
    my ($this, $user, $action, $resource) = @_;

    my $user_type = $user->getAttribute('USER_TYPE');
    my $username  = $user->getUsername();
    $resource ||= '(n/a)';
    $logger->debug("Netdot::SectionAccessRule::denies: Requesting $action $resource ".
		   "on behalf of $username ($user_type)");

    # Deny access to UI sections only available to Admins and Operators
    if ( $action eq "access_section" && ($user_type ne "Admin" && $user_type ne "Operator") ){
	$logger->debug("Netdot::SectionAccessRule::denies: Denying $action for $username ($user_type)");
	return 1;
    }

    # Deny access to UI sections only available to Admins
    if ( $action eq "access_admin_section" && ($user_type ne "Admin") ){
	$logger->debug("Netdot::SectionAccessRule::denies: Denying $action for $username ($user_type)");
	return 1;
    }
    
    return 0;
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


