package Netdot::Model::Circuit;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::Circuit

=head1 INSTANCE METHODS
=cut

###################################################################################

=head2 search_by_keyword - Search Circuits by keywords

    Relevant fields include: CID, SiteLink name, Site names, SiteLink Entity

  Arguments: 
    string or substring
  Returns: 
    array of Circuit objects
  Examples:
    
=cut

sub search_by_keyword {
    my ($class, $string) = @_;
    my $crit = "%" . $string . "%";
    my (@sites, @slinks, @ent);
    my %c;  # Hash to prevent dups

    map { $c{$_} = $_ } Circuit->search_like(cid => $crit);
    @sites  = Site->search_like(name => $crit);
    @slinks = SiteLink->search_like(name => $crit);
    @ent    = Entity->search_like(name => $crit);

    map { push @slinks, $_->farlinks  } @sites;
    map { push @slinks, $_->nearlinks } @sites;
    map { push @slinks, $_->links     } @ent;
    map { $c{$_} = $_ } map { $_->circuits }  @slinks;

    my @c = map { $c{$_} } keys %c;

    wantarray ? ( @c ) : $c[0]; 

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
