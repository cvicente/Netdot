#!/usr/bin/perl
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
  use Data::Dumper;
}
# Create ApacheHandler object at startup.
my $ah =
  HTML::Mason::ApacheHandler->new (
    args_method => "CGI",
    comp_root   => "/home/netdot/public_html/htdocs",
    data_dir    => "/home/netdot/public_html/htdocs/masondata",
    error_mode  => 'output',
  );
#
sub handler
{
  my ($r) = @_;
  my $status = $ah->handle_request($r);
  return $status;
}
#
1;
