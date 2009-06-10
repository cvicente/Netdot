package Netdot::AuthLocal;
use strict;
use warnings;

sub check_credentials {
    my ($r, $username, $password) = @_;
    
    unless ( $r && $username && $password ){
	$r->log_error("Netdot::AuthLocal::check_credentials: Missing required arguments");
	return 0;
    }
    
    my $user;
    unless ( $user = Person->search(username=>$username)->first ){
	$r->log_error("Netdot::AuthLocal::check_credentials: $username not found in DB");
	return 0;
    }

    unless ( $user->verify_passwd($password) ){
	$r->log_error("Netdot::AuthLocal::check_credentials: $username: Bad password");
	return 0;
    }
	
    return 1;
}

#Be sure to return 1
1;

__END__

=head1 NAME

Netdot::AuthenLocal - Local authentication module for Netdot via Apache2::SiteControl


=head1 SYNOPSIS

In Apache configuration:
    
=over 4

   PerlSetVar SiteControlMethod Netdot::AuthLocal
    
=back

=head1 DESCRIPTION


=head1 SEE ALSO

Apache2::SiteControl

=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

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


