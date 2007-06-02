#!/usr/bin/perl -w

package Netdot::Mason;
use strict;
use HTML::Mason::ApacheHandler;

{ 
    package HTML::Mason::Commands;
    use Data::Dumper;
    use lib "<<Make:LIB>>";
    use Netdot::UI;
#    use Netdot::UI::CablePlant;
    use vars qw ( $ui $dns $cable_manager );
    $ui            = Netdot::UI->new();
#    $cable_manager = Netdot::UI::CablePlant>new();
    $dns           = Netdot::Util::DNS->new();
}
# Create ApacheHandler object at startup.
my $ah =
    HTML::Mason::ApacheHandler->new (
				     args_method => "mod_perl",
				     comp_root   => "<<Make:PREFIX>>/htdocs",
				     data_dir    => "<<Make:PREFIX>>/htdocs/masondata",
				     error_mode  => 'output',
				     );
sub handler
{
    my ($r) = @_;

    # We don't need to handle non-text items
    return -1 if $r->content_type && $r->content_type !~ m|^text/|i;

    return $ah->handle_request($r);
}

1;
