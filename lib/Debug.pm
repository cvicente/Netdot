#!/usr/local/bin/perl

# NetViewer
# Copyright 2003 Stephen Fromm  stephenf@nero.net
#                     NERO           http://www.nero.net
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but 
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public 
# License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

package Debug;

use strict;
use Data::Dumper;
use Sys::Syslog qw( :DEFAULT setlogsock ) ;

sub DEFAULT_LOGFACILITY { "LOG_DAEMON" }
sub DEFAULT_LOGLEVEL    { "LOG_NOTICE" }
sub DEFAULT_IDENT       { "debug" }
sub DEFAULT_FOREGROUND  { 0 }

my( %logfacility, %loglevel, %lognum ) ;

%logfacility = ( LOG_KERN => "kern",     LOG_USER => "user",
		 LOG_MAIL => "daemon",   LOG_AUTH => "auth",
		 LOG_LPR => "lpr",       LOG_NEWS => "news",
		 LOG_UUCP => "uucp",     LOG_CRON => "cron",
		 LOG_DAEMON => "daemon",
		 LOG_LOCAL0 => "local0", LOG_LOCAL1 => "local1",
		 LOG_LOCAL2 => "local2", LOG_LOCAL3 => "local3",
		 LOG_LOCAL4 => "local4", LOG_LOCAL5 => "local5",
		 LOG_LOCAL6 => "local6", LOG_LOCAL7 => "local7" ) ;
%loglevel    = ( LOG_EMERG => "emerg",      LOG_ALERT => "alert",
		 LOG_CRIT => "crit",        LOG_ERR => "err",
		 LOG_WARNING => "warning",  LOG_NOTICE => "notice",
		 LOG_INFO => "info",        LOG_DEBUG => "debug" ) ;
%lognum      = ( LOG_EMERG => 0,         LOG_ALERT => 1,
		 LOG_CRIT => 2,          LOG_ERR => 3,
		 LOG_WARNING => 4,       LOG_NOTICE => 5,
		 LOG_INFO => 6,          LOG_DEBUG => 7 ) ;

1;

##################################################
sub new {
  my($proto, %argv) = @_ ;
  my $class = ref( $proto ) || $proto;
  my $self = { "loglevel"    => DEFAULT_LOGLEVEL,
	       "logfacility" => DEFAULT_LOGFACILITY,
	       "logident"    => DEFAULT_IDENT,
	       "foreground"  => DEFAULT_FOREGROUND,
	       "_error"      => "" };
  bless( $self, $class );
  foreach ( keys %argv ) {
    if( /^loglevel$/o ) {
      my %rev = reverse %loglevel;
      if( $loglevel{ $argv{$_} } ) {
	$self->{loglevel} = $argv{$_};
      } else {
	my $s = "Debug: Invalid loglevel value ($argv{$_}); " 
	  . "Using $self->{'_loglevel'}";
	$self->{'_error'} = $s;
	warn $s;
      }
    } elsif( /^logfacility$/o ) {
      my %rev = reverse %logfacility;
      if( $logfacility{ $argv{$_} } ) {
	$self->{logfacility} = $argv{$_};
      } else {
	my $s = "Debug: Invalid logfacility value ($argv{$_}); " 
	  . "Using $self->{'_logfacility'}";
	$self->{'_error'} = $s;
	warn $s;
      }
    } elsif( /^foreground$/o ) {
      if( $argv{$_} =~ /^(0|1)$/ ) {
	$self->{'foreground'} = $argv{$_} ;
      } else {
	my $s = "Debug: Invalid value ($argv{$_}); must be 0 or 1";
	$self->{'_error'} = $s;
	warn $s;
      }
    } elsif( /^logident$/o ) {
      $self->{logident} = $argv{$_};
    }
  }
  wantarray ? ( $self, '' ) : $self ;
}

########################################
sub error {
  $_[0]->{'_error'} || '' ;
}

# PRIVATE
sub _clear_error {
  $_[0]->{'_error'} = undef ;
}

########################################
sub get_logfacility {
  my $self = shift;
  return $self->{logfacility};
}

########################################
sub set_logfacility {
  my( $self, $arg ) = @_;
  my( %rev ) = reverse %logfacility;
  if( $rev{$arg} ) {
    $self->debug( loglevel => "LOG_INFO", 
		  message => "Debug.set_logfacility: " 
		  . "Setting log facility to $arg" ) ;
    $self->{'logfacility'} = $arg;
    $self->_clear_error ;
    return 1;
  } else {
    $self->debug( loglevel => "LOG_ERR", 
		  message => "Debug.set_logfacility: Unknown facility: $arg" );
    $self->{'_error'} = "set_logfacility: Unknown facility: $arg" ;
    return 0;
  }
}


########################################
sub get_loglevel {
  my $self = shift;
  return $self->{loglevel};
}


########################################
sub set_loglevel {
  my($self, $arg) = @_ ;
  my( %rev ) = reverse %loglevel;
  if( $loglevel{$arg} ) {
    $self->{'loglevel'} = $arg;
    $self->debug( loglevel => "LOG_INFO", 
		  message => "Debug.set_loglevel: " 
		  . "Setting debug level to $arg" );
    $self->_clear_error ;
    return 1;
  } else {
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "Debug.set_loglevel: Unknown loglevel: $arg" ) ;
    $self->{'_error'} = "set_loglevel: Unknown loglevel: $arg" ;
    return 0;
  }
}

########################################
sub set_socket {
  my($self, $arg) = @_ ;
  $self->debug( loglevel => "LOG_INFO", 
		message => "Setting SOCKET for client communications" ) ;
  $self->{_socket} = $arg;
  $self->_clear_error ;
  return 1;
}

sub unset_socket {
  my $self = shift ;
  $self->debug( loglevel => "LOG_INFO", 
		message => "Undefining SOCKET for client communications" ) ;
  undef( $self->{_socket} );
  $self->_clear_error ;
  return 1;
}

######################################################################
# if $FOREGROUND is set, print to STDERR
# otherwise, syslog the message.  
# We take the arguments: 
#             loglevel -- loglevel for this message
#             message  -- message to send to syslog
#  OPTIONAL   ident    -- identity string for syslog
#
sub debug {
  my( $self, %argv ) = @_ ;
  my( $ident, $level, $message, $date, @args );

  if( $argv{message} ) {
    $message = $argv{message} ;
  } else {
    $self->debug( loglevel => "LOG_ERR", 
		  message => "Error: debug() called, but no message: @_" ) ;
    return ;
  }
  if( exists( $argv{args} ) ) {
     @args = @{ $argv{args} };
  }
  $date = localtime( time ) ;
  $level = $argv{loglevel} ;
  unless( $loglevel{$level} ) { 
    $level = "LOG_NOTICE" ;
  }
  $argv{ident} ? 
    ( $ident = $argv{ident} ) : ( $ident = $self->{'logident'} ) ;
  $ident .= "[" . $$ . "]";

  if( $lognum{$level} <= $lognum{ $self->{'loglevel'} } ) {
    if( defined( $self->{_socket} ) ) {
      my $socket = $self->{_socket};
      select( $socket ) ;
      printf $socket "$message\n", @args;
    }
    if( $self->{'foreground'} ) {
      select(STDERR) ;
      printf STDERR "[%s] %s $message\n", $$, $date, @args;
    } else {
      if( Sys::Syslog::_PATH_LOG() && -S Sys::Syslog::_PATH_LOG() ) {
	setlogsock( 'unix' ) ;
	openlog( $ident, 'cons', $logfacility{ $self->{'logfacility'} } );
	syslog( $loglevel{$level}, $message, @args ) ;
	closelog() ;
      } else {
	setlogsock( 'udp' ) ;
	openlog( $ident, 'cons', $logfacility{ $self->{'logfacility'} } );
	syslog( $loglevel{$level}, $message, @args ) ;
	closelog() ;
      }
    }
  }
}
