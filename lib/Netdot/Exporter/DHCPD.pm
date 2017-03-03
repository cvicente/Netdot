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

    $self->hook(
        name => 'before-all-scopes-written',
        data => {
            user => $argv{user},
        },
    );

    my @written_scopes = ();
    foreach my $s ( @gscopes ){
	Netdot::Model->do_transaction(sub{
	    if ( (my @pending = HostAudit->search(scope=>$s->name, pending=>1)) || $argv{force} ){
		# Either there are pending changes or we were told to force
		foreach my $record ( @pending ){
		    # Un-mark audit records as pending
		    $record->update({pending=>0});
		}
		my $path = $s->print_to_file();

                # Only perform "hook" things if we actually wrote out a file...
                if (defined $path) {
                    my %data = (
                        scope_name => $s->name,
                        path       => $path,
                    );

                    my %copy_of_data = %data;

                    # save a copy so we can send the aggregate to a later "hook".
                    push @written_scopes, \%copy_of_data;

                    # add user data in case the hook'ed programs want to use it.
                    $data{user} = $argv{user};

                    $self->hook(
                        name => 'after-scope-written',
                        data => \%data,
                    );
                }
	    }else{
		$logger->debug("Exporter::DHCPD::generate_configs: ".$s->name.
			       ": No pending changes.  Use -f to force.");
	    }
				      });
    }

    my $data = {
        scopes_written => \@written_scopes,
        user           => $argv{user},
    };
    $self->hook(
        name => 'after-all-scopes-written',
        data => $data,
    );
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
