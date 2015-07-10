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
      scopes - Global scope names (optional)
  Returns:
    True if successful
  Examples:
    $dhcpd->generate_configs();
=cut

sub generate_configs {
    my ($self, %argv) = @_;
    
    my @gscopes;
    if ( !defined $argv{scopes} || 
	 (scalar(@{$argv{scopes}}) == 1 && $argv{scopes}->[0] eq "") ){
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
	unless ( $s->active ){
	    $logger->debug(sprintf("Exporter::DHCPD::generate_configs: Scope %s is not ".
				  "active. Skipping.", $s->get_label));
	    next;
	}
	my $content;
	my $do_gen = 0;
	if ( $argv{force} ){
	    $do_gen = 1;
	}else{
	    # Check if there will be a different result
	    $content = $s->as_text();
	    if ( $s->digest && ($self->sha_digest($content) eq $s->digest) ){
		$logger->debug(sprintf("Exporter::DHCPD::generate_configs: %s".
				       " has no pending changes.  Use -f to force.", $s->name);
	    }else{
		$do_gen = 1;
	    }
	}
	if ( $do_gen ){
	    eval {
		Netdot::Model->do_transaction(sub{
		    $s->print_to_file($content);
		    $s->update({digest=>$self->sha_digest($content)});
					      });
	    };
	    $logger->error($@) if $@;
	}
    }
}

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

#Be sure to return 1
1;
