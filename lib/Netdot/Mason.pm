#!/usr/bin/perl

package Netdot::Mason;
use strict;
use HTML::Mason::ApacheHandler;

{ 
    package HTML::Mason::Commands;
    use NetAddr::IP;
    use Data::Dumper;
    use lib "<<Make:LIB>>";
    use Netdot::DBI;
    use Netdot::UI;
    use Netdot::IPManager;
    use Netdot::DeviceManager;
    use Netdot::DNSManager;
    use Netdot::CablePlantManager;
    use vars qw ( $ui $dm $dns $ipm $cable_manager );
    $ui            = Netdot::UI->new();
    $dm            = Netdot::DeviceManager->new();
    $dns           = Netdot::DNSManager->new();
    $ipm           = Netdot::IPManager->new();
    $cable_manager = Netdot::CablePlantManager->new();
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
