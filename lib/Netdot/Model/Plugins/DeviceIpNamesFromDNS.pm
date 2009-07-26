package Netdot::Model::Plugins::DeviceIpNamesFromDNS;

use base 'Netdot::Model';
use Netdot::Util::DNS;
use warnings;
use strict;

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Plugin object
  Examples:
    
=cut
sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    bless $self, $class;
}

############################################################################
# Return the current DNS name for this IP.
# If IP does not resolve, return IP address.
#
sub get_name {
    my ($self, $ip) = @_;

    my $name;
    unless ( $name =  Netdot->dns->resolve_ip($ip) ){
	$name = $ip->address;
    }
    return $name;    
}

