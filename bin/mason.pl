#PERL
#
# A basic, functional Mason handler.
#
package Netdot::Mason;
#
# Next lines only for mod_perl 2   
use Apache2 ();
use Apache::compat ();
use CGI ();

# temp fix for mp2-09... make a dummy Apache->request
require Apache::RequestUtil;
no warnings 'redefine';
my $sub = *Apache::request{CODE};
*Apache::request = sub {
     my $r;
     eval { $r = $sub->('Apache'); };
     # warn $@ if $@;
     return $r;
};

# Bring in Mason with Apache support.
use HTML::Mason::ApacheHandler;
use strict;
#
# List of modules that you want to use within components.
{ 
    package HTML::Mason::Commands;
    use Net::IP;
    use NetAddr::IP;
    use Time::Piece;
    use Data::Dumper;
    use lib "PREFIX/lib";
    use Netdot::UI;
    use Netdot::IPManager;
}
# Create ApacheHandler object at startup.
my $ah =
    HTML::Mason::ApacheHandler->new (
				     args_method => "CGI",
				     comp_root   => "PREFIX/htdocs",
				     data_dir    => "PREFIX/htdocs/masondata",
				     error_mode  => 'output',
				     );
#
sub handler
{
    my ($r) = @_;

    # We don't need to handle non-text items
    return -1 if $r->content_type && $r->content_type !~ m|^text/|i;

    my $status = $ah->handle_request($r);
    return $status;
}
#
1;
