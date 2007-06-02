package Netdot::Util::Math;

1;

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

=head2 powerof2lo

    Returns the next lowest power of 2 from x
    note: hard-coded to work for 32-bit integers,
    	so this won't work with ipv6 addresses.
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

=head2 ceil

	There is no ceiling function built in to perl. 

	Arguments:
		- x: a floating point number
	Returns the smallest integer greater than or equal to x.	
	(Also works for negative numbers, although we don't 
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

