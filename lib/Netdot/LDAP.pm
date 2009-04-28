package Netdot::LDAP;
use strict;
use warnings;
use Net::LDAP;

sub check_credentials {
    my ($r, $username, $password) = @_;
    
    unless ( $r && $username && $password ){
	$r->log_error("Netdot::LDAP::check_credentials: Missing required arguments");
	return 0;
    }
    
    my $server = $r->dir_config("LDAPSiteControlServer");
    unless ( $server ){
	$r->log_error("WARNING: LDAP server is not set. Set LDAPSiteControlServer in httpd.conf");
	$server = "ldaps://localhost";
    }
    
    my $user_dn = $r->dir_config("LDAPSiteControlUserDN");
    unless ( $user_dn ){
	$r->log_error("ERROR: DN is not set. Use LDAPSiteControlUserDN in httpd.conf");
	return 0;
    }

    $user_dn =~ s/<username>/$username/;
    
    my $base_dn = $r->dir_config("LDAPSiteControlSearchBase");
    if ( $base_dn ){
	$user_dn .= ",$base_dn";
    }

    my $version = $r->dir_config("LDAPSiteControlVersion") || 3;
    my %args = (version=>$version, verify=>'none');
    my $cafile = $r->dir_config("LDAPSiteControlCACert");
    if ( $cafile ){
	$args{cafile} = $cafile;
	$args{verify} = 'require';
    }
    my $ldap = Net::LDAP->new($server, %args);
    if ( !$ldap ) {
	$r->log_error("Could not contact LDAP server $server: $@");
	return 0;
    }

    my $auth = $ldap->bind($user_dn, password=>$password);
    if ( $auth->code ) {
	$r->log_error("User $username failed authentication: " . $auth->error);
	return 0;
    }
    return 1;
}

#Be sure to return 1
1;

__END__

=head1 NAME

Netdot::LDAP - LDAP authentication module for Netdot via Apache2::SiteControl


=head1 SYNOPSIS

In Apache configuration:
    
=over 4

   PerlSetVar SiteControlMethod Netdot::LDAP

   <Location /netdot/NetdotLogin>
      PerlSetVar LDAPSiteControlServer "ldaps://server.local.domain:636"
      PerlSetVar LDAPSiteControlUserDN "uid=<username>"
      PerlSetVar LDAPSiteControlSearchBase "ou=people,dc=domain,dc=local"
      PerlSetVar LDAPSiteControlVersion "3"
      PerlSetVar LDAPSiteControlCACert "/usr/local/ssl/certs/cacert.pem"
   </Location>
    
=back

=head1 DESCRIPTION


Netdot::LDAP uses Net::LDAPS to do the actual authentication of login attempts 
for the SiteControl system.  It performs user authentication against an LDAP 
server over TLS by attempting to bind directly with the username and password 
as entered by the Netdot user.
    
The following variables can be set in httpd.conf:

LDAPSiteControlServer
    e.g. ldaps://server.local.domain:[port]
    
LDAPSiteControlUserDN         
    e.g. uid=<username>.  
    The string "<username>" is replaced with the username supplied at the login prompt
    
LDAPSiteControlSearchBase 
    Optional. Will be appended to UserDN.
    e.g. "ou=people,dc=domain,dc=local"

LDAPSiteControlCACert
    Optional.  If set, the module will require verification of the server's certificate.
    e.g. "/usr/local/ssl/certs/cacert.pem"

LDAPSiteControlVersion
    Optional.  Defaults to "3".

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


