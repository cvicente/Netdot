package Netdot::Exporter::BIND;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::BIND - Read relevant info from Netdot and build BIND zone files

=head1 SYNOPSIS

    my $bind = Netdot::Exporter->new(type=>'BIND');
    $bind->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Exporter::BIND object
  Examples:
    my $bind = Netdot::Exporter->new(type=>'BIND');
=cut

sub new{
    my ($class, %argv) = @_;
    my $self = {};

    bless $self, $class;
    return $self;
}

############################################################################
=head2 generate_configs - Generate zone files for BIND

  Arguments:
    Hashref with the following keys:
      all    - boolean.  Export all zones.
      zones  - Array ref.  List of zone names to export.
      nopriv - Exclude private data from zone file (TXT and HINFO)
  Returns:
    True if successful
  Examples:
    $bind->generate_configs();
=cut
sub generate_configs {
    my ($self, %argv) = @_;

    my @zones;

    if ( $argv{all} ){
	@zones = Zone->retrieve_all();
    }else{
	if ( !$argv{zones} ){
	    $self->throw_fatal("zones argument is required if 'all' flag is off");
	}
	unless ( ref($argv{zones}) eq 'ARRAY' ){
	    $self->throw_fatal("zones argument must be arrayref!");
	}
	foreach my $name ( @{$argv{zones}} ){
	    if ( Zone->search(name=>$name) ){
		push @zones, Zone->search(name=>$name)->first;
	    }else{
		$self->throw_user("Zone $name not found");
	    }
	}
    }

    foreach my $zone ( @zones ){
	$zone->print_to_file(nopriv=>$argv{nopriv})
	    if $zone->active;
    }
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>
Dongting Yu, C<< <dongting at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

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
