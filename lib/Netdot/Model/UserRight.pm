package Netdot::Model::UserRight;

use base 'Netdot::Model';
use warnings;
use strict;

=head1 NAME

Netdot::Model::UserRight - Manipulate UserRight objects

=cut

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 CLASS METHODS
=cut

#########################################################################

=head2 insert - Insert a new UserRight object

    We override the insert method for extra functionality
    - Ignore duplicates
    - Check if 'none' exists for given object and complain.
    - If adding 'none' remove all other rights


  Args: 
    userright table fields
  Returns: 
    UserRight object
  Examples:
    UserRight->insert({person=>$person_id, accessright=>$ar_id });

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->throw_fatal("Model::UserRight::insert: Missing required arguments")
	unless ( $argv->{person} && $argv->{accessright} );

    my $accessright = AccessRight->retrieve(int($argv->{accessright}));
    my $person      = Person->retrieve(int($argv->{person}));
    
    foreach my $r ( $person->access_rights ){
	my $ar = $r->accessright;
	if ( $ar->object_class eq $accessright->object_class &&
	     $ar->object_id eq $accessright->object_id ){
	    # same object
	    if ( $accessright->access eq $ar->access ){
		# Do not try to insert rights if they exist
		return $r;
	    }
	    if ( $accessright->access ne 'none' && $ar->access eq 'none' ){
		$class->throw_user("Cannot add other rights while 'none' right exists");

	    }elsif ( $accessright->access eq 'none' && $ar->access ne 'none' ){
		$logger->debug("UserRight::insert: Removing ".$ar->access." access on ".
			       $ar->object_class." id ".$ar->object_id);
		$ar->delete();
	    }
	}
    }
    return $class->SUPER::insert($argv);
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

#Be sure to return 1
1;
