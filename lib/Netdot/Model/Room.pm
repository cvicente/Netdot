package Netdot::Model::Room;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::Room

=head1 SYNOPSIS

    $room->get_label()

=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut

##################################################################
=head2 get_label - Override get_label method

    Combines room number and site name

  Arguments:
    None
  Returns:
    string
  Examples:
    print $room->get_label();

=cut
sub get_label {
    my $self = shift;
    $self->isa_object_method('get_label');
    if ( int($self->floor) && int($self->floor->site) ){
	return $self->name. " ". $self->floor->site->get_label;
    }else{
	return $self->name;
    }
}
