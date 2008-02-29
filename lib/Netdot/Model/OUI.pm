package Netdot::Model::OUI;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::OUI - Organizational Unique Identifier (OUI) Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut
############################################################################
=head2 retrieve_all_hashref - Build a hash with key=OUI, value=vendor

  Arguments: 
    None
  Returns:   
    Hash reference 
  Examples:
    my $uois = OUI->retriev_all_hashref();


=cut
sub retrieve_all_hashref {
    my ($class) = @_;
    $class->isa_class_method('retrieve_all_hashref');

    # Build the search-all-macs SQL query
    my ($aref, %oui, $sth);

    my $dbh = $class->db_Main;
    eval {
	$sth = $dbh->prepare_cached("SELECT oui,vendor FROM oui");	
	$sth->execute();
	$aref = $sth->fetchall_arrayref;
    };
    if ( my $e = $@ ){
	$class->throw_fatal($e);
    }
    # Build a hash
    foreach my $row ( @$aref ){
	my ($oui, $vendor) = @$row;
	$oui{$oui} = $vendor;
    }
    return \%oui;
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

#Be sure to return 1
1;
