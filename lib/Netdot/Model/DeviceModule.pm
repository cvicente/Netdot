package Netdot::Model::DeviceModule;

use base 'Netdot::Model';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::DeviceModule - Device Module Class

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut

################################################################
=head2 insert - Insert DeviceModule object

    We override the insert method for extra functionality
      - Automatically assign timestamps

  Arguments: 
    Hash ref with field/value pairs
  Returns:   
    New DeviceModule object
  Examples:
    DeviceModule->insert({number=>1, name=>"blah"});
=cut

sub insert {
    my ($class, $argv) = @_;
    $argv->{date_installed} = $class->timestamp();
    $argv->{last_updated}   = $class->timestamp();
    return $class->SUPER::insert( $argv );
}

=head1 OBJECT METHODS
=cut

################################################################
=head2 update - Update DeviceModule object

    We override the update method for extra functionality
      - Automatically assign timestamps

  Arguments: 
    Hash ref with field/value pairs
  Returns:   
    See Class::DBI::update()
  Examples:
    $module->update({number=>1, name=>"blah"});
=cut

sub update {
    my ($self, $argv) = @_;
    $argv->{last_updated} = $self->timestamp();
    return $self->SUPER::update( $argv );
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 University of Oregon, all rights reserved.

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

#Be sure to return 1
1;

