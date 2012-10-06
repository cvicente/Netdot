package Netdot::Mason;
use strict;
use HTML::Mason::ApacheHandler;

=head1 NAME

Netdot::Mason

=cut

=head1 DESCRIPTION

    HTML::Mason setup for Netdot

=cut

{ 
    package HTML::Mason::Commands;
    use Data::Dumper;
    use lib "<<Make:LIB>>";
    use Netdot::UI;
    use vars qw ( $ui $cable_manager );
    $ui = Netdot::UI->new();
}

# Create ApacheHandler object at startup.
my $ah =
    HTML::Mason::ApacheHandler->new (
				     args_method => "mod_perl",
				     comp_root   => "<<Make:PREFIX>>/htdocs",
				     data_dir    => "<<Make:PREFIX>>/htdocs/masondata",
				     error_mode  => 'output',
				     );

# Do not die for certain Perl warnings
$ah->interp->ignore_warnings_expr("(?i-xsm:Subroutine .*redefined|as parentheses is deprecated)");

=head1 METHODS

=head2 handler

=cut

sub handler
{
    my ($r) = @_;

    # As instructed by Ima::DBI's documentation
    $r->push_handlers(PerlCleanupHandler => sub {
	if ( Netdot::Model->db_auto_commit == 0 ){
	    Netdot::Model->dbi_rollback();
	    Netdot::Model->db_auto_commit(1);
	}
		      });
    
    # We don't need to handle non-text items
    return -1 if $r->content_type && $r->content_type !~ m|^text/|i;

    return $ah->handle_request($r);

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

