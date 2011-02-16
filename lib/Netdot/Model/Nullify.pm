package Class::DBI::Cascade::Nullify;

=head1 NAME

Class::DBI::Cascade::Nullify - Set Foreign keys to null when deleting

=head1 SYNOPSIS

This is a Cascading Delete strategy that will nullify the foreign keys of relatd objects.
See Class::DBI for more information.

=cut

use strict;
use warnings;

use base 'Class::DBI::Cascade::None';

sub cascade {
    my ($self, $obj) = @_;
    map { $_->set($self->{_rel}->args->{foreign_key}, undef); 
	  $_->update;
    } $self->foreign_for($obj);
}

1;
