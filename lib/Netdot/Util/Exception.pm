package Netdot::Util::Exception;

use base 'Netdot::Util';
use warnings;
use strict;

=head1 NAME

Netdot::Util::Exception

=cut
    
use Exception::Class ( 
    'Netdot::Util::Exception' =>
    { description => 'Generic Netdot Exception',
    },
    'Netdot::Util::Exception::Fatal' =>
    { isa         => 'Netdot::Util::Exception',
      description => 'Fatal Netdot Exception',
    },
    'Netdot::Util::Exception::User' =>
    { isa         => 'Netdot::Util::Exception',
      description => 'User Netdot Exception',
    },
    'Netdot::Util::Exception::REST' =>
    { isa         => 'Netdot::Util::Exception',
      description => 'REST Exception',
      fields      => [ 'code' ],
    },
    );


# $err->as_string() will include the stack trace
Netdot::Util::Exception::Fatal->Trace(1);

# $err->as_string() will not include the stack trace
Netdot::Util::Exception::User->Trace(0);
Netdot::Util::Exception::REST->Trace(0);

# Make sure to return 1
1;

=head1 CLASS METHODS

See Exception::Class

=head1 INSTANCE METHODS

=head2 isa_netdot_exception

Determine if an exception object belongs to a certain subclass in our exception hierarchy

=cut

sub isa_netdot_exception{
    my ($self, $name) = @_;
    return unless defined $self;
    if ( $name ){
	my $class = "Netdot::Util::Exception::$name";
	return $self->isa($class);
    }else{
	return $self->isa('Netdot::Util::Exception');
    }
}

=head2 caught

Returns an exception object if the last thrown exception is of the given class, or a subclass of that class

    See Exception::Class::caught

=cut

sub caught{
    my ($self) = shift;
    return Exception::Class->caught(@_);
}

=head2 description

    Somehow this is needed by POD::Coverage

=cut

=head2 SEE ALSO

Exception::Class

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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

1;
