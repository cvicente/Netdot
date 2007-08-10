package Netdot::Util::Math;

use base 'Netdot::Util';
use warnings;
use strict;

=head1 NAME

Netdot::Util::Math - Various Math utilities

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut
1;

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Util::Math object
  Examples:
    my $math = Netdot::Util::Math->new();
=cut
sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{_logger} = Netdot->log->get_logger('Netdot::Util');
    bless $self, $class;
}

############################################################################
=head2 within

    Checks if a value is between two other values
    Arguments:
        - val: value youre interested in
        - beg: start of range to check
        - end: end of range to check
    Returns true/false whether val is between beg and end, inclusive

=cut
sub within {
    my ($self, $val, $beg, $end) = @_;
    return( $beg <= $val && $val <= $end );
}

############################################################################
=head2 powerof2lo

    Returns the next lowest power of 2 from x
    note: hard-coded to work for 32-bit integers,
    	so this won\'t work with ipv6 addresses.
    Arguments:
        - x: an integer
    Returns a power of 2

=cut
sub powerof2lo {
    my ($self, $x) = @_;
    $x |= $x >> 1;
    $x |= $x >> 2;
    $x |= $x >> 4;
    $x |= $x >> 8;  # the above sets all bits to the right of the
    $x |= $x >> 16; # left-most "1" bit of x to 1. (ex 10011 -> 11111)
	$x  = $x >> 1;  # divide by 2  (ex 1111)
    $x++;           # add one      (ex 10000)
    return $x;
}

############################################################################
=head2 ceil

	There is no ceiling function built in to perl. 

	Arguments:
		- x: a floating point number
	Returns the smallest integer greater than or equal to x.	
	(Also works for negative numbers, although we don\'t 
	really need that here.)

=cut
sub ceil {
    my ($self, $x) = @_;
	return int($x-(int($x)+1)) + int($x) + 1;
}

=head2 floor

	There is no floor function built in to perl.
	int(x) is equivalent to floor(x) for positive numbers,
	which is really all we need floor for here,	so this
	method will not work for negative numbers.

	Arguments:
		- x: a floating point number
	Return the largest integer less than or equal to x.	
=cut
sub floor {
    my ($self, $x) = @_;
	return int($x);
}

=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >> with contributions from Nathan Collins and Aaron Parecki.

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
