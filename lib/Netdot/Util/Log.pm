package Netdot::Util::Log;

use base 'Netdot::Util';
use warnings;
use strict;
use Carp;
use Log::Log4perl;

1;

=head1 NAME

Netdot::Util::Log

=head1 SYNOPSIS

    my $log = Netdot::Util::Log->new(config=>$config_file);
    my $log->get_logger("Netdot::Class");
    $logger->warn("Warn message");

=head1 CLASS METHODS
=cut

############################################################################

=head2 new - Class constructor

  Arguments:
    Arrayref with the following keys:
      config -  string containing config info
  Returns:
    Netdot::Util::Log object
  Examples:
    my $log = Netdot::Util::Log->new(config=>$config_file);


=cut

sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $config = $argv{config} or croak "Log.pm constructor needs config parameter";
    Log::Log4perl->init_once(\$config);
    bless $self, $class;
}

=head1 INSTANCE METHODS

=cut

############################################################################

=head2 get_logger - Return logger object

  Arguments:
    logger name string
  Returns:
    logger object
  Examples:
    $log->get_logger("Netdot::Class");

=cut

sub get_logger{
    my ($self, $name) = @_;
    croak "Need to pass logger name" unless $name;
    return Log::Log4perl->get_logger( $name );
}

############################################################################

=head2 new_appender

  Arguments:
    type - string with Log::Log4perl Appender class name
    args - hash with appender arguments
  Returns:
    appender object
  Examples:
    my $logstr = Netdot::Util::Log->new_appender('String', 'logstr');

=cut

sub new_appender{
    my ($self, $type, %args) = @_;

    my $AppenderClass = "Log::Log4perl::Appender::$type";
    my $appender = Log::Log4perl::Appender->new($AppenderClass,	%args);

    return $appender;
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

