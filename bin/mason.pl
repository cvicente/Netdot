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

# Bring in Mason with Apache support.
use HTML::Mason::ApacheHandler;
use strict;
#
# List of modules that you want to use within components.
{ 
    package HTML::Mason::Commands;
    use NetAddr::IP;
    use Data::Dumper;
    use lib "PREFIX/lib";
    use Netdot::DBI;
    use Netdot::GUI;
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
