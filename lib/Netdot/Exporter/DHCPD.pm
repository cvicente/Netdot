package Netdot::Exporter::DHCPD;

use base 'Netdot::Exporter';
use warnings;
use strict;
use Data::Dumper;

my $logger = Netdot->log->get_logger('Netdot::Exporter');

=head1 NAME

Netdot::Exporter::DHCPD - Read relevant info from Netdot and build ISC DHCPD config file

=head1 SYNOPSIS

    my $dhcpd = Netdot::Exporter->new(type=>'DHCPD');
    $dhcpd->generate_configs()

=head1 CLASS METHODS
=cut

############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Exporter::DHCPD object
  Examples:
    my $bind = Netdot::Exporter->new(type=>'DHCPD');
=cut

sub new{
    my ($class, %argv) = @_;
    my $self = {};

    bless $self, $class;
    return $self;
}

############################################################################
=head2 generate_configs - Generate config file for DHCPD

  Arguments:
    Hash with the following keys:
      scopes - Global scope names or 'all'
      
  Returns:
    True if successful
  Examples:
    $dhcpd->generate_configs();
=cut
sub generate_configs {
    my ($self, %argv) = @_;
    
    my @gscopes;
    if ( !defined $argv{scopes} ){
	@gscopes = DhcpScope->search(type=>'global');
    }else{
	foreach my $scope_name ( @{$argv{scopes}} ){
	    if ( my $gscope = DhcpScope->search(type=>'global', name=>$scope_name)->first ){
		push @gscopes, $gscope;
	    }else{
		$self->throw_user("Global Scope $scope_name not found");
	    }
	}
    }
    foreach my $s ( @gscopes ){
	if ( $s->audit_records() || $argv{force} ){
	    $s->print_to_file();

	    # Flush audit records
	    map { $_->delete } $s->audit_records;
	}else{
	    $logger->debug("Exporter::DHCPD::generate_configs: ".$s->name.": No pending changes.  Use -f to force.");
	}

    }
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

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
