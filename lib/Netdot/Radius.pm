package Netdot::Radius;

use strict;
use warnings;
use Authen::Radius;
use APR::SockAddr;
use Netdot::AuthLocal;

=head1 NAME

Netdot::RADIUS - RADIUS module for Netdot

=head1 SYNOPSIS

In Apache configuration:
    
=over 4

   PerlSetVar SiteControlMethod Netdot::RADIUS

   <Location /netdot/NetdotLogin>
       PerlSetVar NetdotRadiusHost "localhost"
       PerlSetVar NetdotRadiusSecret "testing123"
       PerlSetVar NetdotRadiusHost2 "otherhost"
       PerlSetVar NetdotRadiusSecret2 "testing123"
       PerlSetVar NetdotRadiusTimeOut "5"
       PerlSetVar NetdotRadiusFailToLocal "yes"
   </Location>
    
=back

=head1 DESCRIPTION

    Netdot::Radius uses Authen::Radius to issue authentication and authorization queries
    for Netdot.  It supports failover by querying one Radius server first, then the second.
    It also returns any available Netdot-specific attributes for a given user.

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
    if ( Netdot::Radius::check_credentials($r, $user, $pass) {...}

=cut
sub check_credentials {
    my ($r, $username, $password) = @_;
    unless ( $username && $password ){
	$r->log_error("Missing username and/or password");
	return 0;
    }

    my $fail_to_local = ($r->dir_config("NetdotRadiusFailToLocal") eq "yes")? 1 : 0;

    my $radius;
    unless ( $radius = Netdot::Radius::_connect($r) ){
	if ( $fail_to_local ){
	    $r->log_error("Netdot::Radius::check_credentials: Trying local auth");
	    return Netdot::AuthLocal::check_credentials($r, $username, $password);
	}else{
	    return 0;
	}
    }

    # Get my IP address to pass as the Source IP and NAS IP Address
    my $c = $r->connection;
    my $sockaddr = $c->local_addr if defined($c);
    my $nas_ip_address = $sockaddr->ip_get if defined($sockaddr);

    
    if ( $radius->check_pwd($username, $password, $nas_ip_address) ) {
	return 1;
    }else{
	$r->log_error("Netdot::Radius::check_credentials: User $username failed Radius authentication: " 
		      . $radius->strerror);
	if ( $fail_to_local ){
	    $r->log_error("Netdot::Radius::check_credentials: Trying local auth");
	    return Netdot::AuthLocal::check_credentials($r, $username, $password);
	}
    }
    return 0;
}

############################################################################
# _connect - Connect to an available Radius server
#
#   Arguments:
#     Apache Request Object
#   Returns:
#     Authen::Radius object
#   Examples:
#     my $radius = Netdot::Radius::connect($r);
#
#
sub _connect {
    my ($r) = @_;
    
    my $host     = $r->dir_config("NetdotRadiusHost")    || "localhost";
    my $host2    = $r->dir_config("NetdotRadiusHost2");
    my $secret   = $r->dir_config("NetdotRadiusSecret")  || "unknown";
    my $secret2  = $r->dir_config("NetdotRadiusSecret2") || "unknown";
    my $timeout  = $r->dir_config("NetdotRadiusTimeOut") || "5";
    my $radius;
    
    $r->log_error("WARNING: Shared secret is not set. Use RadiusSiteControlSecret in httpd.conf") 
	if $secret eq "unknown";
    
    $radius = new Authen::Radius(Host=>$host, Secret=>$secret, TimeOut=>$timeout);
    if ( !$radius ) {
	$r->log_error("Could not contact radius server: $host.");
	if ( $host2 ){
	    # Try second Radius server
	    $radius = new Authen::Radius(Host=>$host2, Secret => $secret2);
	    if ( !$radius ) {
		$r->log_error("Could not contact radius server: $host2");
		return 0;
	    }
	}else{
	    return 0;
	}  
    }
    return $radius;
}

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



