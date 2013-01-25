package Netdot::Krb5;

use strict;
use warnings;
use Authen::Krb5::Simple;
use APR::SockAddr;
use Netdot::AuthLocal;

=head1 NAME

Netdot::Krb5 - Kerberos module for Netdot

=head1 SYNOPSIS

In Apache configuration:
    
=over 4

   PerlSetVar SiteControlMethod Netdot::Krb5

   <Location /netdot/NetdotLogin>
     PerlSetVar NetdotKrb5Realm "system"
     PerlSetVar NetdotKrb5FailToLocal "yes"
   </Location>
    
=back

=head1 DESCRIPTION

    Netdot::Krb5 uses Authen::Krb5::Simple to issue authentication queries.
    It supports failover by querying the Kerberos server(s) first, then the local DB.

=cut

#Be sure to return 1
1;


############################################################################

=head2 check_credentials
    
  Arguments:
    Apache Request Object
    Username
    Password
  Returns:
    True or false
  Examples:
    if ( Netdot::Krb5::check_credentials($r, $user, $pass) {...}

=cut

sub check_credentials {
    my ($r, $username, $password) = @_;
    unless ( $username && $password ){
	$r->log_error("Missing username and/or password");
	return 0;
    }

    my $fail_to_local = ($r->dir_config("NetdotKrb5FailToLocal") eq "yes")? 1 : 0;
    my $realm = $r->dir_config("NetdotKrb5Realm");

    my $krb;
    if ( $realm eq 'system' ){ 
        $krb = Authen::Krb5::Simple->new();
    }else{
	$krb = Authen::Krb5::Simple->new(realm => $realm);
    }

    unless ( $krb ){
	if ( $fail_to_local ){
	    $r->log_error("Netdot::Krb5::check_credentials: Failed to init kerberos. Trying local auth");
	    return Netdot::AuthLocal::check_credentials($r, $username, $password);
	}else{
	    return 0;
	}
    }

    # Authenticate
    if ( $krb->authenticate($username, $password) ) {
	return 1;
    }else{
	$r->log_error("Netdot::Krb5::check_credentials: User $username failed Kerberos authentication: " 
		      . $krb->errstr);
	if ( $fail_to_local ){
	    $r->log_error("Netdot::Krb5::check_credentials: Trying local auth");
	    return Netdot::AuthLocal::check_credentials($r, $username, $password);
	}
    }
    return 0;
}


=head1 SEE ALSO
    
Apache2::SiteControl

=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2013 University of Oregon, all rights reserved.

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



