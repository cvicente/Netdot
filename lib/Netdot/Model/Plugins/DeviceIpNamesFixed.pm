package Netdot::Model::Plugins::DeviceIpNamesFixed;

use base 'Netdot::Model';
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
=head2 new - Class constructor

  Arguments:
    Ipblock object
  Returns:
    Name String 
  Examples:
    $plugin->get_name($ip);

=cut
sub get_name {
    my ($self, $ip) = @_;
    
    return $ip->interface->device->short_name;
}

