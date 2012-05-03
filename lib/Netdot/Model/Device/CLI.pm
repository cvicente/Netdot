package Netdot::Model::Device::CLI;

use base 'Netdot::Model::Device';
use warnings;
use strict;
use Net::Appliance::Session;

my $logger = Netdot->log->get_logger('Netdot::Model::Device');

=head1 NAME

Netdot::Model::Device::CLI - Base class for classes dealing with Device CLI interaction

=head1 SYNOPSIS

Provides common functions for CLI access

=head1 CLASS METHODS
=cut

=head1 INSTANCE METHODS
=cut


############################################################################
# Get CLI login credentials from config file
#
# Arguments: 
#   host
# Returns:
#   hashref
#
sub _get_credentials {
    my ($self, %argv) = @_;

    my $config_item = 'DEVICE_CLI_CREDENTIALS';
    my $host = $argv{host};
    my $cli_cred_conf = Netdot->config->get($config_item);
    unless ( ref($cli_cred_conf) eq 'ARRAY' ){
	$self->throw_user("Device::CLI::_get_credentials: config $config_item must be an array reference.");
    }
    unless ( @$cli_cred_conf ){
	$self->throw_user("Device::CLI::_get_credentials: config $config_item is empty");
    }

    my $match = 0;
    foreach my $cred ( @$cli_cred_conf ){
	my $pattern = $cred->{pattern};
	if ( $host =~ /$pattern/ ){
	    $match = 1;
	    my %args;
	    $args{login}      = $cred->{login};
	    $args{password}   = $cred->{password};
	    $args{privileged} = $cred->{privileged};
	    $args{transport}  = $cred->{transport} || 'SSH';
	    $args{timeout}    = $cred->{timeout}   || '30';
	    return \%args;
	}
    }   
    if ( !$match ){
	$self->throw_user("Device::CLI::_get_credentials: $host did not match any patterns in configured credentials.")
    }
}

############################################################################
# Issue CLI command
#
# Arguments:
#   Hash with the following keys:
#   login
#   password
#   privileged
#   transport
#   timeout
#   host 
#   personality
#   cmd
# Returns:
#   array
#
sub _cli_cmd {
    my ($self, %argv) = @_;
    my ($login, $password, $privileged, $transport, $timeout, $host, $personality, $cmd) = 
	@argv{'login', 'password', 'privileged', 'transport', 'timeout', 'host', 'personality', 'cmd'};
    
    $self->throw_user("Device::CLI::_cli_cmd: $host: Missing required parameters: login, password, cmd")
	unless ( $login && $password && $cmd );
    
    $personality ||= 'ios';

    my %sess_args = (
	host              => $host,
	transport         => $transport,
	personality       => $personality,
	connect_options   => {
	    shkc => 0,
	    opts => [
		'-o', "ConnectTimeout=$timeout",
		'-o', 'CheckHostIP=no',
		],
	},
	);

    # this is broken for some reason. Need to debug
    # $sess_args{privileged_paging} = 1 if ($personality eq 'pixos');
    # when fixed, remove terminal pager commands below

    my @output;
    eval {
	$logger->debug(sub{"$host: issuing CLI command: '$cmd' over $transport"});
	my $s = Net::Appliance::Session->new(\%sess_args);

	$s->nci->transport->ors("\r\n") if ($personality eq 'foundry');                                        

#       Uncomment this to debug session exchanges	
#	$s->set_global_log_at('debug');
	
	$s->connect({username  => $login, 
		     password  => $password,
		    });
	
	$s->begin_privileged({password=>$privileged}) if ( $privileged );
	$s->cmd('terminal pager 0') if ( $personality eq 'pixos' );
	@output = $s->cmd($cmd, {timeout=>$timeout});
	$s->cmd('terminal pager 36') if ( $personality eq 'pixos' );
	$s->end_privileged if ( $privileged );
	$s->close;
    };
    if ( my $e = $@ ){
	$self->throw_user("Device::CLI::_get_arp_from_cli: $host: $e");
    }
    return @output;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 University of Oregon, all rights reserved.

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

