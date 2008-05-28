package Netdot::Model::Splice;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::Splice

=head1 SYNOPSIS

=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut


##################################################################
=head2 insert
    
    Splice together strand1 and strand2.
    Note: Two Splice objects are created (bi-directional)
    
  Arguments:
    - strand1, strand2: the CableStrand objects to create a splice for.
  Returns: 
    New Splice object
  Examples:
    Splice->insert({strand1=>$strand1, strand2=>$strand2})
    
=cut
sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    
    $class->throw_fatal("Missing required arguments: strand1/strand2")
	unless ( exists $argv->{strand1} && exists $argv->{strand2} );
    
    # Insert inverse first
    $class->SUPER::insert({strand1=>$argv->{strand2}, strand2=>$argv->{strand1}});
    
    return $class->SUPER::insert($argv);
}

=head1 AUTHOR

Kai Waldron
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
