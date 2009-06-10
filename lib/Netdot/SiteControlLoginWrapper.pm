package Netdot::SiteControlLoginWrapper;
use base qw(Apache2::SiteControl);

use Apache2::Request;	# To get at POST args.
use strict;

=head1 NAME

Netdot::SiteControlLoginWrapper

=head1 SYNOPSIS

In the apache configuration:

  NetdotTemporarySessionExpires +5m

  <Location login-target>
    SetHandler perl-script
    PerlHandler Netdot::SiteControlLoginWrapper->login

    other-sitecontrol-or-apache-stuff
  </Location>

=head1 METHODS

=cut

# Make sure to return true
1;

=head2 login - Wraps Apache2::SiteControl::login

Tweaks the environment to overcome deficiencies in the
AuthCookie/SiteControl API.  Specifically it sets the expire time on
the session cookie at runtime.

There are two kinds of cookies now.  Permanent and tempory.  The
permanent ones last a *long* time.  The temporary ones last the amount
of time specified by the NetdotTemporarySessionExpires variable in the
apache conf.  The syntax for that variable is the same as that used by
Apache2::AuthCookie.

The temporary cookie is the default.  The permanent cookie is used if
there is an attribute called ``permanent_session'' in the post data
submitted to the login-target.  See login.html for an example.

=cut

sub login {
    my ($self, $r) = @_;

    my $req = Apache2::Request->new($r);

    # AuthCookie uses the value of NetdotExpires, as set in the apache
    # conf, to determine how long the session cookie should be valid.

    if ($req->param('permanent_session')) {
	$r->dir_config->set('NetdotExpires', '+10y');	# 10 years is pretty permanent for a cookie.
    } else {
	my $interval = $r->dir_config('NetdotTemporarySessionExpires');

	my $debug = $r->dir_config("AuthCookieDebug") || 0;
	if ($debug) {
	    $r->server->log_error("No value set for NetdotTemporarySessionExpires in apache conf"
			     . " so AuthCookie's default will be used")
		unless $interval;
	}
	$r->dir_config->set('NetdotExpires', $interval);
    }

    # Let SiteControl do its thing.
    $self->SUPER::login($r);

}
