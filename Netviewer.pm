#!/usr/local/bin/perl 

# NetViewer
# Copyright 2001-2003 Stephen Fromm  stephenf@nero.net
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

package Netdot::Netviewer ;

use lib "/home/netdot/public_html/lib";
use strict ;
use Fcntl qw(:DEFAULT :flock) ;
use Sys::Syslog qw( :DEFAULT setlogsock ) ;
use Net::SNMP ;
use Netdot::DBI;
use Data::Dumper;

use vars qw ( @ISA @EXPORT @EXPORT_OK $VERSION 
	      %aliases %labels %dstype %metacat %ifdata %localevars %ifType
	      %hardware %aliasDS ) ;

sub BEGIN { }
sub END { }
sub DESTROY { }

use Exporter ;
@ISA = qw( Exporter ) ;
$VERSION = 20030609 ;

my( $_FOREGROUND, $HOME,  $_LOGLEVEL, $_LOGFACILITY, $SOCKET, $_SYSLOGIDENT,
    %logfacility, %loglevel, %lognum ) ;

$_FOREGROUND = 0 ;
$HOME = "/home/netdot/public_html";

sub DEFAULT_DATADIR     { "$HOME/data" }
sub DEFAULT_IMGDIR      { "$HOME/img" }
sub DEFAULT_RRDBINDIR   { "/usr/local/rrdtool/bin" }
sub DEFAULT_GLOBAL      { "$HOME/etc/netviewer.conf" }
sub DEFAULT_CONF        { "$HOME/etc/collect.conf" }
sub DEFAULT_STORE       { "$HOME/etc/collect.store" }
sub DEFAULT_CAT         { "$HOME/etc/nv.categories" }
sub DEFAULT_TYPES       { "$HOME/etc/nv.ifTypes" }
sub DEFAULT_LOCALE      { "$HOME/etc/locale.conf" }
sub DEFAULT_COLLECT     { "no" }
sub DEFAULT_ALWAYSFETCH { "yes" }
sub DEFAULT_INTERVAL    { 5 }
sub DEFAULT_INTERVAL_S  { 5 }
sub DEFAULT_INTERVAL_L  { 15 }
sub DEFAULT_HCLIMIT     { 10000000 }
sub DEFAULT_CARLIMIT    { 5000000 }
sub DEFAULT_VLANSPEED   { 1000000000 }
sub DEFAULT_UMASK       { 0002 }
sub DEFAULT_XFF         { 0.5 }
sub DEFAULT_TIMEOUT     { 5 }
sub DEFAULT_RETRIES     { 1 }
sub DEFAULT_LOGFACILITY { "LOG_DAEMON" }
sub DEFAULT_LOGLEVEL    { "LOG_NOTICE" }
sub DEFAULT_SNMPVERSION { "SNMPv2c" }
sub DEFAULT_COMMUNITY   { "public" }
sub DEFAULT_SYSLOGIDENT { "netviewerd" }
sub RRDTOOL_DS_LENGTH   { 19 }


# see 'man syslog' and syslog.h for more info

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
#
# must return a 1
#
1;


######################################################################
#====================================================================
#
#  Assorted Getters and Setters  (all public methods)
#
#====================================================================
######################################################################


######################################################################
# a list of the top level trees (locale, device, etc)
sub get_types {
  my $self = shift ;
  my @tmp ; 
  my %targets = %{ $self->{targets} } if( $self->{targets} );
  foreach( keys %targets )
    { push @tmp, $_ if( defined( $_ ) ) ; }
  return @tmp ;
}


######################################################################
# the device tree
sub get_devices { 
  my $self = shift ; 
  my %devices ;
  if( $self->{targets} ) {
    my %t = %{ $self->{targets} };
    %devices = %{ $t{device} } ;
  }
  return %devices ;
}


######################################################################
sub get_device {
  my( $self, $type, $dev ) = @_;
  if( $self->{targets} ) {
    my %t = %{ $self->{targets} };
    if( exists( $t{$type}{$dev} ) ) {
      my %dev = %{ $t{$type}{$dev} };
      return %dev;
    } else {
      return 0;
    }
  }
}


######################################################################
# different categories available (eg. interface, dsx1, etc)
sub get_categories {  return keys %aliases ; }


######################################################################
# the %targets hash  (eg. device -> eugn-noc-sw -> interface -> A1)
sub get_targets { 
  my $self = shift ; 
  my %t = %{ $self->{targets} } if( $self->{targets} );
  return %t ;
}


######################################################################
# mapping of snmpvar name to OID
# eg   sysDescr  -> 1.3.6.1.2.1.1.1.0
sub get_aliases { return %aliases ; }


######################################################################
# an alias for the snmpvar name in %aliases
# this maps to the varname in the rrd file
sub get_aliasDS { return %aliasDS ; }


######################################################################
# metacategory information 
# eg <cat>
#        cftype -> consolidation function
#         descr -> description of category (or particular inst)
#      instance|map|table - how to discover instances
#           key
#     tablesize
#          test
#        exists
#      interval
#        append
#         alias
#           aux
# 
sub get_metacat { return %metacat ; }


######################################################################
# map of ifType to types of data that can be gathered on it
# ifType -> <varname> = 1
sub get_ifdata { return %ifdata ; }


######################################################################
# DS type for a particular var
# eg ifInOctets -> COUNTER
sub get_dstype { return %dstype ; }


######################################################################
sub get_umask { my $self = shift ; return $self->{'_umask'} ; }


######################################################################
# vars to collect in a locale
sub get_localevars { return %localevars ; }


######################################################################
sub string_state {
  my $self = shift ;
  my $data ;
  foreach my $key ( sort keys %{ $self } ) {
    next if( $key eq "targets" ) ;
    $key =~ s/^_// ;
    $data .= sprintf( "%15s %1s\n", $key, $self->{"_$key"} ) ;
  }
  return $data ;
}


######################################################################
# PUBLIC
# return error message (if it exists)
sub error {
  $_[0]->{'_error'} || '' ;
}

# PRIVATE
sub _clear_error {
  $_[0]->{'_error'} = undef ;
}


######################################################################
# PUBLIC  --  but probably deprecated
#
# Returns $status.  Only have two messages I'm interested at present:
#   1  everything went okay
#   2  everything is okay, but I read $CONF in preference to $STORE
#   3  everything is okay, but $CONF && $STORE not read
#   4  the tmp file still exists; I read $CONF.bak
#
sub get_status { 
  my $self = shift ; 
  return $self->{'_status'} ; 
}


######################################################################
#=====================================================================
#
#  PUBLIC
#
#  initialize and setup stuff
#
#=======================================
########################################
sub new {
  my($class, %argv) = @_ ;
  my $self = { #'targets'         => undef,
	      '_datadir'        => DEFAULT_DATADIR,
	      '_imgdir'         => DEFAULT_IMGDIR,
	      '_rrdbindir'      => DEFAULT_RRDBINDIR,
	      '_conf'           => DEFAULT_CONF,
	      '_store'          => DEFAULT_STORE,
	      '_cat'            => DEFAULT_CAT,

	      '_types'          => DEFAULT_TYPES,
	      '_locale'         => DEFAULT_LOCALE,
	      '_defaultcollect' => DEFAULT_COLLECT,
	      '_alwaysfetch'    => DEFAULT_ALWAYSFETCH,
	      '_interval'       => DEFAULT_INTERVAL,
	      '_interval_s'     => DEFAULT_INTERVAL_S,
	      '_interval_l'     => DEFAULT_INTERVAL_L,
	      '_hclimit'        => DEFAULT_HCLIMIT,
	      '_carlimit'       => DEFAULT_CARLIMIT,
	      '_vlanspeed'      => DEFAULT_VLANSPEED,
	      '_umask'          => DEFAULT_UMASK,
	      '_xff'            => DEFAULT_XFF,
	      '_timeout'        => DEFAULT_TIMEOUT,
	      '_retries'        => DEFAULT_RETRIES,
	      '_snmpversion'    => DEFAULT_SNMPVERSION,
	      '_community'      => DEFAULT_COMMUNITY,
	      '_logfacility'    => DEFAULT_LOGFACILITY,
	      '_loglevel'       => DEFAULT_LOGLEVEL,
	      '_syslogident'    => DEFAULT_SYSLOGIDENT,
	      '_version'        => $VERSION,
	      '_status'         => 0,
	      '_foreground'     => 0,
	      '_error'          => '' } ;
  bless $self, $class ;
  $self->_init( %argv ) ;
  #    $_LOGFACILITY = $self->{'_logfacility'} ;
  #    $_LOGLEVEL =$self->{'_loglevel'} ;
  wantarray ? ( $self, '' ) : $self ;
}


######################################################################
#=====================================================================
# PRIVATE
#
# Very simple, actually.  Take in the hash of arguments supplied from
#   outside and set the defaults.  Then, set up necessary hash structures
#   (in this case %aliases and %labels).  Then, if $STORE exists, we
#   read %targets from disk.  If $CONF has been updated since 
#   $targets{mtime}, we re-read $CONF and update $targets{mtime}
#   accordingly.  IF $STORE does not exist, we try to read $CONF.  If
#   $CONF does not exist, we bail (since there's nothing we could do
#   anyways.
# Returns $status.  Only have two messages I'm interested at present:
#   1  everything went okay
#   2  everything is okay, but I read $CONF in preference to $STORE
#   3  everything is okay, but $CONF && $STORE not read
#   4  the tmp file still exists; I read $CONF.bak
#
sub _init {
  my($self, %argv) = @_ ;
  $self->_read_globals() ;
  $self->_set_defaults( %argv ) ;
  $self->_read_aliases() ;
  $self->_read_types() ;
  # $self->_read_collect();
}

sub _read_collect {
  my $self = shift;
  my $status = 3 ;
  my %targets = %{ $self->{targets} } if( $self->{targets} );
  if( -f "$self->{'_conf'}.tmp" ) {
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "init: tmp file still exists; reading .bak" ) ;
    read_conf("$self->{'_conf'}.bak") ;
    unlink( "$self->{'_conf'}.tmp" );
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "init: removing tmp file" ) ;
    $status = 4 ;
  } elsif ( -f $self->{'_store'} ) {
    open( COLLECTION, "< $self->{'_store'}" )
      or die "FAILURE: init: Unable to open $self->{'_store'}: $!" ;
    flock( COLLECTION, LOCK_SH )
      or die "FAILURE: init: Unable to lock $self->{'_store'}: $!";
    %targets = %{ retrieve( $self->{'_store'} ) } ;
    flock( COLLECTION, LOCK_UN ) 
      or $self->debug( loglevel => "LOG_WARNING", 
		       message => "init: Unable to free lock " 
		       . "$self->{'_store'}: $!" ) ;
    close( COLLECTION );
    $status = 1 ;
    $self->{targets} = \%targets ;

    if ( (lstat( $self->{'_conf'} ))[9] > (lstat( $self->{'_store'} ))[9] ) {
      my $err ;
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "init: $self->{'_conf'} is newer than cache");
      if ( ! $self->read_conf( $self->{'_conf'} ) ) {
	$self->debug( loglevel => "LOG_WARNING", 
		      message => "init: error reading $self->{'_conf'};" 
		      . " reading .bak" ) ;
	$self->read_conf( "$self->{'_conf'}.bak" ) ;
      }
      $status = 2 ;
    }
  } else { 
    if ( -f "$self->{'_conf'}" ) { 
      if ( ! $self->read_conf( $self->{'_conf'} ) ) {
	$self->debug( loglevel => "LOG_WARNING",
		      message => "init: " . 
		      "error reading $self->{'_conf'}; reading .bak" ) ;
	$self->read_conf( "$self->{'_conf'}.bak" ) ;
      }
      $status = 2 ;
    } else { 
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "init: $self->{'_store'} and " 
		    . "$self->{'_conf'} " 
		    . "don't exist; have no device definitions to load" );
    }
  }
  $self->{'_status'} = $status ;
}


######################################################################
# PRIVATE
#
# set global values; 
# these can be altered if desired (performed in set_defaults)
# read from Netdot Database
#=======================================
sub _read_globals {
  my $self = shift ;
  foreach my $inst ( Netviewer->retrieve_all() ) {
    my( $n, $v ) = ( $inst->name, $inst->value );
    $self->{"_$n"} = $v;
  }
} # read_globals


######################################################################
# PRIVATE
#
# set default values for certain variables
# cmdline args to init will override defaults in $GLOBAL
#=======================================
sub _set_defaults {
  my ($self, %argv ) = @_ ;
  foreach ( keys %argv ) {
    if ( /^datadir$/io ) { 
      if( -d $argv{$_} ) { 
	$self->{'_datadir'} = $argv{$_} ; 
      } else {
	warn(	"set_defaults: Invalid directory ($argv{$_}); " 
		. "Will try $self->{'_datadir'}");
      }
    }	elsif( /^rrdbindir$/io ) {
      if( -d $argv{$_} ) { 
	$self->{'_rrdbindir'} = $argv{$_} ; 
      } else {
	warn(	"set_defaults: Invalid directory ($argv{$_}); " . 
		"Will try $self->{'_rrdbindir'}");
      }
    } elsif( /^imgdir$/io ) {
      if( -d $argv{$_} ) {
	$self->{'_imgdir'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid directory ($argv{$_}); " 
	      . "Will try $self->{'_imgdir'}" );
      }
    } elsif( /^conf$/io ) {
      if( -f $argv{$_} ) {
	$self->{'_conf'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid conffile ($argv{$_});" 
	      . " Will try $self->{'_conf'}" ) ;
      }
    }	elsif( /^store$/io ) {
      if( -e $argv{$_} ) {
	$self->{'_store'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid store file ($argv{$_}); " 
	      . "Will try $self->{'_store'}" );
      }
    }	elsif( /^aliases$/io ) {
      if( -f $argv{$_} ) {
	$self->{'_cat'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid alias file ($argv{$_}); " 
	      . "Will try $self->{'_cat'}" ) ;
      }
    } elsif( /^types$/io ) { 
      if( -f $argv{$_} ) {
	$self->{'_types'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid ifTypes file ($argv{$_}); " 
	      . "Will try $self->{'_types'}" );
      }
    } elsif( /^locale$/io ) { 
      if( -f $argv{$_} ) {
	$self->{'_locale'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid locale file ($argv{$_}); "
	      . "Will try $self->{'_locale'}" );
      }
    } elsif( /^defaultcollect$/io ) {
      if( $argv{$_} =~ /^(yes|no)$/io ) {
	$self->{'_defaultcollect'} = lc( $argv{$_} ) ;
      } else {
	warn( "set_defaults: " . "Invalid value for DEFAULTCOLLECT;"
	      . " Will try $self->{'_defaultcollect'}" ) ;
      }
    } elsif( /^alwaysfetch$/io ) {
      if( $argv{$_} =~ /^(yes|no)$/io ) {
	$self->{'_alwaysfetch'} = lc( $argv{$_} ) ;
      } else {
	warn( "set_defaults: " . "Invalid value for ALWAYSFETCH;"
	      . " Will try $self->{'_alwaysfetch'}" ) ;
      }
    } elsif( /^interval$/io ) {
      if( $argv{$_} =~ /^\d+$/ ) {
	$self->{'_interval'} = $argv{$_} ;
      } else {
	warn( "set_defaults: Invalid value for interval ($argv{$_});"
	      . " Will try $self->{'_interval'}" );
      }
    } elsif ( /^shortinterval$/io ) {
      if( $argv{$_} =~ /^\d+$/ ) {
	$self->{'_interval_s'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid value for shortinterval " 
	      . "($argv{$_}); Will try $self->{'_interval_s'}" );
      }
    } elsif ( /^longinterval$/io ) {
      if( $argv{$_} =~ /^\d+$/ ) {
	$self->{'_interval_l'} = $argv{$_} ; 
      } else {
	warn( "set_defaults: Invalid value for longinterval " 
	      . "($argv{$_}); Will try $self->{'_interval_l'}" );
      }
    } elsif( /^hclimit$/io ) {
      if( $argv{$_} =~ /^\d+$/o ) {
	$self->{'_hclimit'} = $argv{$_} ;
      } else {
	warn( "NetViewer.set_defaults: Invalid value for "
	      ."hclimit ($argv{$_}); will try $self->{'_hclimit'}" ) ;
      }
    } elsif( /^carlimit$/io ) {
      if( $argv{$_} =~ /^\d+$/o ) {
	$self->{'_carlimit'} = $argv{$_} ;
      } else {
	warn( "NetViewer.set_defaults: Invalid value for "
	      ."carlimit ($argv{$_}); will try $self->{'_carlimit'}" ) ;
      }
    } elsif( /^vlanspeed$/io ) {
      if( $argv{$_} =~ /^\d+$/o ) {
	$self->{'_vlanspeed'} = $argv{$_} ;
      } else {
	warn( "NetViewer.set_defaults: Invalid value for "
	      ."vlanspeed ($argv{$_}); will try $self->{'_vlanspeed'}" ) ;
      }
    } elsif( /^xff$/io ) {
      if( $argv{$_} =~ /^\d+$/o ) {
	$self->{'_xff'} = $argv{$_} ;
      } else {
	warn( "NetViewer.set_defaults: Invalid value for "
	      ."xff ($argv{$_}); will try $self->{'_xff'}" ) ;
      }
    }	elsif( /^umask$/io ) {
      if( $argv{$_} =~ /^\d+$/o ) {
	$self->{'_umask'} = $argv{$_} ;
      } else {
	warn( "set_defaults: Invalid value for UMASK ($argv{$_}); " 
	      . "Will try $self->{'_umask'}" ) ;
      }
    } elsif( /^logfacility$/io ) {
      if( $argv{$_} =~ /^\w+$/ && $logfacility{ $argv{$_} } ) {
	$self->{'_logfacility'} = $argv{$_} ;
      } else {
	warn( "set_defaults: Invalid value for " 
	      . "logfacility ($argv{$_}); Using $self->{'_logfacility'}" ) ;
      }
    } elsif( /^loglevel$/io ) {
      if( $argv{$_} =~ /^\w+$/ ) {
	$self->{'_loglevel'} = $argv{$_} ;
      } else {
	warn( "set_defaults: Invalid value for " 
	      . "loglevel ($argv{$_}); Using $self->{'_loglevel'}" ) ;
      }
    } elsif( /^timeout$/io ) {
      if( $argv{$_} =~ /^[\d\.]+$/o ) {
	$self->{'_timeout'} = $argv{$_} ;
	if( $self->{'_timeout'} < 1 || $self->{'_timeout'} > 60 ) {
	  warn( "set_defaults: TIMEOUT $self->{'_timeout'} " 
		. " variable outside valid range; " 
		. "must be between 1.0 and 60.0" ) ;
	  $self->{'_timeout'} = DEFAULT_TIMEOUT ;
	}
      } else {
	warn( "set_defaults: Invalid value for " 
	      . "timeout ($argv{$_}); using $self->{'_timeout'}" ) ;
      }
    } elsif( /^retries$/io ) {
      if( $argv{$_} =~ /^\d+$/o ) {
	$self->{'_retries'} = $argv{$_} ;
      } else {
	warn( "set_defaults: Invalid value for " 
	      . "retries ($argv{$_}); using $self->{'_retries'}" ) ;
      }
    } elsif( /^snmpversion$/io ) {
      if( $argv{$_} =~ /^\w+$/o ) {
	$self->{'_snmpversion'} = $argv{$_} ;
      } else {
	warn( "set_defaults: Invalid value for " 
	      . "snmpversion ($argv{$_}); using $self->{'_snmpversion'}" );
      }
    } elsif( /^community$/io ) {
      $self->{'_community'} = $argv{$_} ;
    } elsif( /^syslogident$/io ) {
      $self->{'_syslogident'} = $argv{$_} ;
    } elsif( /^foreground$/io ) {
      if( $argv{$_} =~ /^(0|1)$/ ) {
	$_FOREGROUND = $self->{'_foreground'} = $argv{$_} ;
      } else {
	warn( "set_defaults: Invalid value for " 
	      . "foreground ($argv{$_}); Using $self->{'_foreground'} ");
      }
    } else {
      warn( "set_defaults: Invalid argument $_" ) ; 
    }
  }
}


######################################################################
# PRIVATE
#
# Read $CAT and build necessary structures.
# %aliases is a hash of MIB names to OIDs
# %aliasDS is a hash that translates a MIB name to a RRD DS name
# %dstype is the data source type for a particular OID (GAUGE, COUNTER, ...)
# %metacat contains information about a category --
#   stuff to create an instance or rrd file
# %ifdata is a hash that specifies the types of OIDs to get
#   for a particular type of interface
#=======================================
sub _read_aliases
  {
    my $self = shift ;
    my( $super, $mib, $oid, $last ) ;
    my ( %al, %mc, %alDS ) ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "Entering read_aliases" ) ;
    open( CAT, $self->{'_cat'} )
      or $self->debug( loglevel => "LOG_ERR", 
		       message => "Unable to open $self->{'_cat'}: $!" );
    $self->debug( loglevel => "LOG_INFO",
		  message => "read_aliases: creating mapping vars -> OIDs" );
    while( <CAT> ) {
      next if ( /^\#/ ) ;
      s/\#.*//g ;
      next if( /^\s*$/ ) ;
      if( /^(\w+)\s+$/ ) {
	$super = $1 ; 
      } elsif( /\s*(\w+)\s+(\w+\s+)?(\w+)\s*/ && $super eq "locale" ) {
	##########################################
	# locale sectoin of categories file.  specify the varname and 
	# 'each' (collect each interval of source) or 'single' (collect 
	# once for interval of locale)
	my( $a, $b ) = ( $1, $3 ) ;
	if( $b =~ /^each$/io || $b =~ /^single$/io ) {
	  $localevars{$a}{interval} = lc( $b ) ;
	} else {
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_aliases: " 
			. "invalid argument to locale var: $b\n" ) ;
	}
	if( $2 ) {
	  my $tmp = $2 ;
	  $tmp =~ s/\s+$//g ; $tmp =~ s/^\s+//g ;
	    $localevars{$a}{ds} = $2 ;
	} else {
	  $localevars{$a}{ds} = $a ;
	}
      } elsif( /^\s+rrdCF\s+([\w:]+)\s*/ ) {
	##########################################
	# stuff like 'avg' 'max' 'min'
	$mc{$super}{cftype} = uc( $1 ) ; 
      } elsif( /^\s+descr\s+(.*)\s*$/ ) {
	##########################################
	# description of category (either string, or varname)
	my $tmp = $1 ;
	$tmp =~ s/^\s*//g ; $tmp =~ s/\s*$//g ;
	$mc{$super}{descr} = $tmp ; 
      } elsif( /^\s+instance\s+([\d\.]+|null)\s*$/ ) {
	##########################################
	# specific category type -- you declare inst variable [0-9]+ or null
	$mc{$super}{instance} =  $1 ; 
      } elsif( /^\s+map\s+(\$\w+)\s*$/ ) {
	##########################################
	# another specific category -- walk a table of instances
	$mc{$super}{map} = $1 ;
      } elsif( /^\s+key\s+(\w+)\s*$/ ) {
	##########################################
	# req for 'map'; determines how to name each instance:
	# 'value', 'instance', or <category>
	$mc{$super}{key} = $1 ;
      } elsif( /^\s+table\s+(\$\w+)\s*$/ ) {
	##########################################
	# another specific category: doesn't prediscover instances 
	# under the supposition that instances will move around; it simply does
	# a get_next_request until there are no more
	$mc{$super}{table} = $1 ;
      } elsif( /^\s+tablesize\s+(\d+)\s*$/ ) {
	##########################################
	# req for 'table'; need to declare the size of 'table' -- the maximum 
	# number of instances you expect to discover
	$mc{$super}{tablesize} = $1 ;
      } elsif( /^\s+test\s+(\{.*\})\s*$/ ) {
	##########################################
	# an expression that evaluates to true or false; affects whether 
	# instance is collected; 
	my $v = $1 ;
	$v =~ s/^\s*//g ; $v =~ s/\s*$//g ;
	$v =~ s/^{/{ /g ; $v =~ s/}$/ }/g ;
	$mc{$super}{test}{$v} = 1 ;
      } elsif( /^\s+test\s+.*$/ ) {
	##########################################
	# make sure test expr is correct
	chomp() ;
	$self->debug( loglevel => "LOG_WARNING",
		      message => "read_aliases: test arg not valid; " 
		      . "must be bound by braces {...}: $_" ) ;
      } elsif( /^\s+exists\s+(\$\w+)\s*$/ ) {
	##########################################
	# only for 'instance' cats; tests whether category applies for device
	$mc{$super}{exists} = $1 ;
      } elsif( /^\s+interval\s+(\d+)\s*$/ ) {
	##########################################
	# interval to gather category instances (in minutes)
	$mc{$super}{interval} = $1 ;
      } elsif( /^\s+append\s+([\d\.]+)\s*$/ ) {
	##########################################
	# whether to apply a value to an OID
	$mc{$super}{append} = $1 ;
      } elsif( /^\s+alias\s+(\S+)\s*$/ ) {
	##########################################
	# alias for category name -- only relevant for filenames
	$mc{$super}{alias} = $1 ;
      } elsif( /^\s+aux\s+([\$\w\.]+)\s*$/ ) {
	##########################################
	# whether to gather auxiliary values per instances during builds
	$mc{$super}{aux}{$1} = 1 ;
      } elsif( /\s+(\w+)\s+(\w+\s+)?([\d\.]+)\s+(\w+)?\s*/ ) { 
	##########################################
	# varname  [varname]  OID   [DS type]
	( $mib, $oid ) = ( $1, $3 ) ; 
	$al{$super}{$mib} = $oid ;
	if( $2 ) {
	  my $tmp = $2 ;
	  $tmp =~ s/\s+$//g ; $tmp =~ s/^\s+//g ;
	  $alDS{$super}{$mib} = $tmp ;
	} else {
	  $alDS{$super}{$mib} = $mib ;
	}
	if ( $4 ) {
	  $last = $4 ; 
	}
	$dstype{$mib} = uc( $last ) if ( $last ) ;
      } else {
	##########################################
	# complain about everything else
	$self->debug( loglevel => "LOG_WARNING",
		      message => "read_aliases: don't know how to parse $_" );
      }
    }
    close( CAT ) ;
    #
    # verify %mc (metacat to be)
    while( my($cat,undef) = each(%mc) ) {
      ##########################################
      # make sure the category has an interval
      unless( $mc{$cat}{interval} ) {
	$self->debug( loglevel => "LOG_WARNING",
		      message => "read_aliases: "
		      . "$cat:interval not specified; setting to "
		      . DEFAULT_INTERVAL );
	$mc{$cat}{interval} = DEFAULT_INTERVAL ;
      }
      ##########################################
      # make sure the category specified rrdCF - a consolidation function
      unless( $mc{$cat}{cftype} ) {
	$self->debug( loglevel => "LOG_ERR",
		      message => "read_aliases: $cat must specify rrdCF" ) ;
	undef %mc ;
	last ;
      }
      ##########################################
      # check for 'alias' key
      if( $mc{$cat}{alias} ) {
	unless( $mc{$cat}{alias} =~ /^\"/ ) {
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_aliases: $cat alias doesn't"
			. "begin with a \"." ) ;
	  undef %mc ;
	  last ;
	}
      }
      ##########################################
      # check for 'test' key
      if( $mc{$cat}{test} ) {
	foreach my $v ( split( /\s+/, $mc{$cat}{test} ) ) {
	  if( $v =~ /^\$/ ) {
	    $v =~ s/\.inst$// ;
	    $v =~ s/^\$// ;
	    unless( $al{general}{$v} ) {
	      $self->debug( loglevel => "LOG_ERR", 
			    message => "read_aliases: variable $v must"
			    . "be defined in the general section" );
	      undef %mc ; 
	      last ;
	    }
	  }
	}
      }
      ##########################################
      # check for 'descr' of category
      if( $mc{$cat}{descr} ) {
	unless( $mc{$cat}{descr} =~ /^\"/ || $mc{$cat}{descr} =~ /^\$/ ) {
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_aliases: $cat descr "
			. "$mc{$cat}{descr} doesn't begin with a \$ or \"." ) ;
	  undef %mc ;
	  last ;
	}
	if( $mc{$cat}{descr} =~ /^\$/ ) {
	  my $t = $mc{$cat}{descr} ;
	  $t =~ s/\.inst$// ;
	  $t =~ s/^\$// ;
	  unless( $al{general}{$t} ) {
	    $self->debug( loglevel => "LOG_ERR",
			  message => "read_aliases: $cat descr $t must" 
			  . " be defined in general section" ) ;
	    undef %mc ;
	    last ;
	  }
	}
      }
      ##########################################
      # check for auxiliary variables that need to be checked
      if( $mc{$cat}{aux} ) {
	foreach my $var ( keys %{ $mc{$cat}{aux} } ) {
	  unless( $var =~ /^\$/ ) {
	    undef %mc ;
	    last ;
	  }
	  $var =~ s/\.inst$//g ;
	  $var =~ s/^\$// ;
	  unless( defined( $al{general}{$var} ) ) {
	    debug( loglevel => "LOG_ERR",
		   message => "read_aliases: variable $var must " 
		   . "be defined in the general section" );
	    undef %mc ;
	    last ;
	  }
	}
      }
      ##########################################
      # examine 'map' category type
      if( exists( $mc{$cat}{map} ) ) {
	unless( $mc{$cat}{map} =~ /^\$/ ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: variable must be specified"
			. " for $cat table var" ) ;
	  undef %mc ;
	  last ;
	}
	my $map = $mc{$cat}{map} ;
	$map =~ s/\.inst//g ;
	$map =~ s/^\$// ;
	unless( $al{general}{ $map } ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: variable $map must" 
			. " be defined in the general section" );
	  undef %mc ; 
	  last ;
	}
	##########################################
	# make sure map cat type doesn't have either instance || table
	if( exists( $mc{$cat}{instance} ) || exists( $mc{$cat}{table} ) ) {
	  my $g ;
	  exists( $mc{$cat}{instance} ) ?
	    ( $g = "instance" ) : ( $g = "table" ) ;
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_aliases: Can't have both " 
			. "map and $g defined for $cat" ) ;
	  undef %mc ;
	  last ;
	} 
	##########################################
	# or that 'exists' expression is not used
	if( defined( $mc{$cat}{exists} ) ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: Can't use exists" 
			. " expression with map for $cat" ) ;
	  undef %mc ;
	  last ;
	}
	##########################################
	# check key value (whether value or instance)
	if( $mc{$cat}{key} =~ /^value$/io ) {
	  $mc{$cat}{key} = "value" ;
	} elsif( $mc{$cat}{key} =~ /^instance$/io ) {
	  $mc{$cat}{key} = "instance" ;
	} elsif( $al{ $mc{$cat}{key} } ) {
	  unless( $mc{ $mc{$cat}{key} }{key} =~ /^value$/io 
		  || $mc{ $mc{$cat}{key} }{key} =~ /^instance$/io ) {
	    $self->debug( loglevel => "LOG_ERR",
			  message => "read_aliases: $cat key refers" 
			  . " to another category that refers to " 
			  . "another category...the other category " 
			  . "must have key set to value or instance" ) ;
	    undef %mc ;
	    last ;
	  }
	} else {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: " 
			. "invalid value for $cat:key: $mc{$cat}{key}" ) ;
	  undef %mc ;
	  last ;
	}
      } elsif( exists( $mc{$cat}{instance} ) ) {
	##########################################
	# 'instance' category type
	#
	if( exists( $mc{$cat}{map} ) || exists( $mc{$cat}{table} ) ) {
	  my $g ;
	  exists( $mc{$cat}{map} ) ?
	    ( $g = "map" ) : ( $g = "table" ) ;
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: Can't have both instance " 
			. "and $g defined for $cat" ) ;
	  undef %mc ;
	  last ;
	}
	if( defined( $mc{$cat}{test} ) ) {
	  if( defined( $mc{$cat}{exists} ) ) {
	    $self->debug( loglevel => "LOG_ERR", 
			  message => "read_aliases: Can't have both " 
			  . "test and exists expression in $cat" ) ;
	    undef %mc ;
	    last ;
	  }
	}
      } elsif( exists( $mc{$cat}{table} ) ) {
	##########################################
	# 'table' category type
	#
	unless( $mc{$cat}{table} =~ /^\$/ ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: variable must be specified"
			. " for $cat table var" ) ;
	  undef %mc ;
	  last ;
	}
	if( $mc{$cat}{table} =~ /\.inst$/ ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: can't specify '.inst' with"
			. " category table" ) ; 
	  undef %mc ;
	  last ;
	}
	my $map = $mc{$cat}{table} ;
	$map =~ s/^\$// ;
	unless( $al{general}{ $map } ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: variable $map must" 
			. " be defined in the general section" );
	  undef %mc ; 
	  last ;
	}
	##########################################
	# make sure 'instance' and 'map' not defined
	if( exists( $mc{$cat}{instance} ) || exists( $mc{$cat}{map} ) ) {
	  my $g ;
	  exists( $mc{$cat}{instance} ) ?
	    ( $g = "instance" ) : ( $g = "map" ) ;
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_aliases: Can't have both " 
			. "table and $g defined for $cat" ) ;
	  undef %mc ;
	  last ;
	} 
	##########################################
	# make sure 'exists' not defined
	if( defined( $mc{$cat}{exists} ) ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: Can't use exists" 
			. " expression with table for $cat" ) ;
	  undef %mc ;
	  last ;
	}
	if( defined( $mc{$cat}{aux} ) ) {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: Can't use aux" 
			. " with table category $cat" ) ;
	  undef %mc ;
	  last ;
	} 
	##########################################
	# make sure 'tablesize' defined
	if( exists( $mc{$cat}{tablesize} ) ) {
	  unless( $mc{$cat}{tablesize} =~ /^\d+$/o ) {
	    $self->debug( loglevel => "LOG_ERR",
			  message => "read_aliases: $cat tablesize" 
			  . " must be a digit, which it appears not to be" );
	    undef %mc ;
	    last ;
	  }
	} else {
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_aliases: $cat tablesize " 
			. "must be set for a table definiition" );
	  undef %mc ;
	  last ;
	}
      } else {
	##########################################
	# else category type not defined
	#
	$self->debug( loglevel => "LOG_ERR", 
		      message => "read_aliases: $cat must specify " 
		      . "either map, table, or instance" ) ;
	undef %mc ;
	last ;
      }
    }
    ##########################################
    # verfiy %alDS, look for duplicates or other potential problems
    while( my($super,undef) = each( %alDS ) ) { 
      my %tmp ;
      while( my($var, $val) = each( %{ $alDS{$super} } ) ) {
	$tmp{$val}++ ;
	##########################################
	# check length of var
	if( length( $val ) > RRDTOOL_DS_LENGTH && $super ne "general" ) {
	  $self->debug( loglevel => "LOG_WARNING",
			message => "Warning: length of $val is too long "
			. "for rrdtool ds name" );
	}
	if( exists( $mc{$super}{table} ) ) {
	  my $t = $val . "_" . $mc{$super}{tablesize};
	  if( length( $t ) > RRDTOOL_DS_LENGTH && $super ne "general" ) {
	    $self->debug( loglevel => "LOG_WARNING",
			  message => "Warning: length of $t is too long "
			  . "for rrdtool ds name " 
			  . "(table categories appends an integer" );
	  }
	}
      }
      while( my($var, $val) = each( %tmp ) ) {
	next if( $var eq "ifInOctets" || $var eq "ifOutOctets" 
		 || $var eq "ifInUcastPkts" || "ifOutUcastPkts" ) ;
	if( $val > 1 ) {
	  $self->debug( loglevel => "LOG_WARNING", 
			message => "Warning: $var is defined twice " 
			. "in the category $super; potential conflict" ) ;
	}
      }
    }
    %aliasDS = %alDS ;
    unless( %localevars ) {
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "Warning: no locale variables defined" ) ;
    }
    if( %al && %mc ) {
      ##########################################
      # if we get to this point, we can set %al and %mc to the real thing
      %aliases = %al ;
      %metacat = %mc ;
    } else {
      ##########################################
      # otherwise, something went wrong  :-(
      if( %aliases && %metacat ) {
	$self->debug( loglevel => "LOG_WARNING",
		      message => "read_aliases: problems encountered" 
		      . " while processing $self->{'_cat'}; using config" 
		      . " from last successful read" ) ;
      } else {
	$self->debug( loglevel => "LOG_ERR",
		      message => "read_aliases: problems encountered "
		      . "while processing $self->{'_cat'}; unable to proceed");
	die( "read_aliases: "
	     ."problems encountered while processing $self->{'_cat'}; "
	     ."unable to proceed" ) ;
      }
    }
  }


######################################################################
# PRIVATE
#
# read in ifTypes file that has simple translation from number to name
#=======================================
sub _read_types
  {
    my $self = shift ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "Entering read_types: mapping between " 
		  . "ifType num and name" );
    open( TYPE, $self->{'_types'} )
      or $self->debug( loglevel => "LOG_ERR",
		       message => "Unable to open $self->{'_types'}: $!");
    my $super ;
    while( <TYPE> ) { 
      next if ( /^\#/ || /^\s*$/ ) ;
      if( /^(\w+)\s+$/ ) {
	$super = $1 ; 
      } elsif( /(\d+)\s+(\w+)/ ) {
	my( $num, $name ) = ( $1, $2 ) ;
	$ifType{$num} = $name ;
      } elsif( /^\s+(\w+)\s+([\w\s\,]+)\s*/ && $super eq "ifdata" ) {
	my( $if, $tmp ) = ($1, $2 ) ;
	#$if = lc($if) ;
	my @ds = split( /\s*,\s*/, $tmp ) ;
	foreach (@ds) {
	  s/\s+$//g ; s/^\s+//g ; $ifdata{$if}{$_} = 1 ;
	}
      }
    }
    close( TYPE ) ;
    my @ifs = keys %{ $aliases{interface} } ;
    while( my($kind, undef) = each %ifdata ) {
      my $k ;
      foreach $k ( keys %{ $ifdata{$kind} } ) {
	foreach ( @ifs ) { 
	  #next if ( $k =~ /^ifH?C?(In|Out)/ ) ;
	  $ifdata{$kind}{$_} = 1 if ( $_ =~ /^ifH?C?(In|Out)$k$/ ) ;
	}
	delete $ifdata{$kind}{$k} ;
      }
    }
    # $self->debug( loglevel => "LOG_DEBUG", 
    #               message => "Leaving read_types" ) ;
  }


######################################################################
# PUBLIC
#
# read collect.conf ($self->{'_conf'}) and build %targets....
# returns a status code:
#     1 for success
#     0 for error (something faulty with the conf file read)
#=======================================
sub read_conf
  {
    my( $self, $file ) = @_ ;
    my( $device, $interface, $sub, $inside, $key, $linenum, $type, $bad, 
	$close, $err, %targets ) ;
    %targets = %{ $self->{targets} } if( $self->{targets} );
    $err = $bad = $sub = $linenum = $close = 0 ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "Entering read_conf: reading $file" ) ;
    unless( -f $file ) {
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "read_conf: file $file doesn't exist" ) ;
      return 0 ;
    }
    unless( -r $file ) {
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "read_conf: file $file is not readable" ) ;
      return 0 ;
    }
    open( CONF, "$file" )
      or $self->debug( loglevel => "LOG_ERR", 
		       message => "read_conf: Unable to open $file: $!" );
    $self->debug( loglevel => "LOG_INFO",
		  message => "read_conf: file opened; beginning read" );
    while( <CONF> ) {
      $linenum++ ;
      next if ( /^\#/io ) ;
      next if ( /^\s*$/io ) ;

      ################################################

      # Top Level items
      #
      # if device already defined, delete it so new & old config don't conflict

      ################################################
      if( /^\s*device\s+([\w\.\-]+)\s*/io ) {            # device name
	$device = $1 ;
	$type = "device" ;
	$device =~ s/^\s*//g ; $device =~ s/\s*$//g ;
	$bad = 0 ;
	if ( defined( $targets{$type}{$device} ) ) {
	  delete( $targets{$type}{$device} ) ;
	}
      } elsif( /^\s*locale\s+([\w\.\-]+)\s*/io && $sub == 0 ) {
	$device = $1 ;
	$type = "locale" ;
	$device =~ s/^\s*//g ; $device =~ s/\s*$//g ;
	$bad = 0 ;
      } elsif( /^\s*version\s+(\w+)\s+/io ) {            # snmp version
	$targets{$type}{$device}{"version"} = $1 ; 
	$bad = 0 ;
      } elsif( /^\s*sysObjectID\s+([\d\.]+)\s*/io && ! $bad ) { 
	$targets{$type}{$device}{sysObjectID} = $1 ; 
      } elsif( /^\s*autoconfigure\s+([Yy][Ee][Ss]|[Nn][Oo])\s+/io && ! $bad ) {
	$targets{$type}{$device}{"autoconfigure"} = $1 ; 
      }	elsif( /^\s*targetaddress\s+([\w\.\-]+)\s+/io && ! $bad ) { 
	$targets{$type}{$device}{"targetaddress"} = $1 ; 
      }	elsif( /^\s*ifNumber\s+(\d+)\s*/io && ! $bad ) {  # ifNumber
	$targets{$type}{$device}{ifNumber} = $1 ; 
      }	elsif( /^\s*sysLocation\s+(.*)$/io && ! $bad ) {  # sysLocation
	my $ans = $1 ;
	$ans =~ s/^\s*//g ; $ans =~ s/\s*$//g ;
	$targets{$type}{$device}{sysLocation} = $ans ; 
      }	elsif( /^\s*sysName\s+(.*)\s*$/io && ! $bad ) {   # sysName
	my $ans = $1 ;
	$ans =~ s/^\s*//g ; $ans =~ s/\s*$//g ;
	$targets{$type}{$device}{sysName} = $ans ; 
      } elsif( /^\s*timeout\s+([\d\.]+)\s*/io && ! $bad && $type eq "device" ){
	$targets{$type}{$device}{timeout} = $1 ;
      } elsif( /^\s*retries\s+(\d+)\s*/io && ! $bad && $type eq "device" ) {
	$targets{$type}{$device}{retries} = $1 ;
      } elsif( /^\s*sysUpTime\s+(-?[\d\.]+)\s*$/io && ! $bad ) {
	$targets{$type}{$device}{sysUpTime} = $1 ;
      } elsif( /^\s*bgpLocalAs\s+(\d+)\s*$/io && ! $bad ) {
	$targets{$type}{$device}{bgpLocalAs} = $1 ;
      } elsif( /^\s*(sysUpTime\d+)\s+(-?[\d\.]+)\s*$/io && ! $bad ) {
	my ($ans1, $ans2) = ($1, $2) ;
	$ans1 =~ s/^\s*//g ; $ans1 =~ s/\s*$//g ;
	$ans2 =~ s/^\s*//g ; $ans2 =~ s/\s*$//g ;
	$targets{$type}{$device}{$ans1} = $ans2 ; 
      }	elsif( /^\s*community\s+(\w+)\s*/io && ! $bad ) { # community
	my $ans = $1 ;
	$ans =~ s/^\s*//g ; $ans =~ s/\s*$//g ;
	$targets{$type}{$device}{community} = $ans ; 
      }
      ################################################

      # Subsections

      ################################################
      elsif( /^\s*(\w+)\s+([\w\-\/\.: \(\)]+)\s*\{/io && $sub == 0 && ! $bad ){
	$inside = $1 ;
	$key = $2 ;
	$sub = 1 ;
	$key =~ s/^\s*//g ; $key =~ s/\s*$//g ;
	unless( $aliases{$inside} ) {
	  $self->debug( loglevel => "LOG_WARNING", 
			message => "read_conf: Unknown category $inside" ) ;
	}
      } elsif( /^\s*interval\s+(\d+)\s*/io && ! $bad ) {
	my $retort = $1 ;
	if ( $sub == 1 ) { 
	  $targets{$type}{$device}{$inside}{$key}{interval} = $retort; 
	} else {
	  $targets{$type}{$device}{interval} = $retort ; 
	}
      }
      ####################################################

      # Details specific to subsections

      ####################################################
      elsif( /^\s*locale\s+([\w\.\-]+)\s+(\w+)(\s+\S+\s+\S+)?\s*/io 
	     && $sub == 1 && ! $bad ) {
	my( $loc, $invert, $supp ) = ( $1, $2, $3 ) ;

	$invert =~ s/^\s*//g ; $invert =~ s/\s*$//g ;
	$loc =~ s/^\s*//g ; $loc =~ s/\s*$//g ;
	if ( $invert =~ /^normal$/io ) { 
	  $targets{$type}{$device}{$inside}{$key}{locale}{$loc}{invert} = 0 ;
	} elsif( $invert =~ /^invert$/io ) { 
	  $targets{$type}{$device}{$inside}{$key}{locale}{$loc}{invert} = 1 ;
	} else {
	  $targets{$type}{$device}{$inside}{$key}{locale}{$loc}{invert} = 0 ;
	}
	$targets{"locale"}{$loc}{sources}{"$type;$device;$inside;$key"} = 1 ;

	if( $supp ) {
	  $supp =~ s/^\s*//g; $supp =~ s/\s*$//g ;
	  my @args = split( /\s+/, $supp ) ;
	  if( $args[0] =~ /^ignore$/io ) {
	    shift @args ;
	    foreach my $arg ( split( /:/, shift @args ) ) {
	      $targets{$type}{$device}{$inside}{$key}{locale}{$loc}
		{ignore}{$arg} = 1 ;
	    }
	  } else {
	    chomp($_);
	    $self->debug( loglevel => "LOG_ERR",
			  message => "read_conf: faulty configuration " 
			  . "file $file at line $linenum: invalid argument" 
			  . "$args[0] for locales" ) ;
	  }
	}
      }	elsif( /^\s*ccarConfigRate\s+(\d+)\s*/io && $sub == 1 && ! $bad ) {
	$targets{$type}{$device}{$inside}{$key}{ccarConfigRate} = $1 ;
      }	elsif( /^\s*highlight\s+(\d+)\s*/io && $sub == 1 && ! $bad ) {
	$targets{$type}{$device}{$inside}{$key}{highlight} = $1 ; 
      }	elsif( /^\s*mibs\s+([\w\:]+)\s*/io && $sub == 1 && ! $bad ) {
	$targets{$type}{$device}{$inside}{$key}{mibs} = $1 ; 
      }	elsif( /^\s*acl\s+(\d+)\s*/io && $sub == 1 && ! $bad ) { 
	$targets{$type}{$device}{$inside}{$key}{acl} = $1 ; 
      }	elsif( /^\s*highcounter\s+(\d+)\s*/io && $sub == 1 && ! $bad ) { 
	$targets{$type}{$device}{$inside}{$key}{highcounter} = $1 ; 
      } elsif( /^\s*instance\s+([\d\.]+)\s*/io && $sub == 1 && ! $bad ) { 
	$targets{$type}{$device}{$inside}{$key}{instance} = $1 ; 
      }	elsif( /^\s*ipaddress\s+([\d\.]+)\s*/io && ! $bad && 
	       $sub == 1 && $inside eq "interface" ) { 
	$targets{$type}{$device}{$inside}{$key}{ipaddress} = $1 ; 
      }	elsif( /^\s*ifSpeed\s+(\d+)\s*/io && ! $bad && 
	       $sub == 1 && $inside eq "interface" ) { 
	$targets{$type}{$device}{$inside}{$key}{ifSpeed} = $1 ; 
      }	elsif( /^\s*ifType\s+(\w+)\s*/io  && ! $bad && 
	       $sub == 1 && $inside eq "interface" ) { 
	$targets{$type}{$device}{$inside}{$key}{ifType} = $1 ; 
      }
      ##################################################

      # stuff that belongs to 'locale' or 'device'

      #####################################################
      elsif( /^\s*filename\s+([\w\/\._-]+)\s*/io && ! $bad ) { 
	if ( $type eq "device" && $sub == 1 ) { 
	  $targets{$type}{$device}{$inside}{$key}{filename} = $1 ; 
	} elsif( $type eq "locale" && $sub == 0 ) {
	  $targets{$type}{$device}{filename} = $1 ; 
	} else {
	  chomp($_) ;
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_conf: faulty configuration file " 
			. "$file at line $linenum: ($_) ... ignorning " 
			. "section $type $device" ) ;
	  $err = $bad = 1 ;
	}
      }	elsif( /^\s*lockdescr\s+([Yy][Ee][Ss]|[Nn][Oo])\s*/io && ! $bad ) {
	if( $type eq "device" && $sub == 1 ) { 
	  $targets{$type}{$device}{$inside}{$key}{lockdescr} = lc( $1 );
	} elsif( $type eq "locale" && $sub == 0 ) {
	  $targets{$type}{$device}{lockdescr} = lc( $1 ) ; 
	} else {
	  chomp( $_ ) ;
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_conf: faulty configuration file " 
			. "$file at line $linenum: ($_) ... ignorning " 
			. "section $type $device" ) ;
	  $err = $bad = 1 ;
	}
      } elsif( /^\s*descr\s+(.*)\s*$/io  && ! $bad ) { 
	my $z = $1 ;
	$z =~ s/^\s*//g ; $z =~ s/\s*$//g ; 
	if ( $type eq "device" && $sub == 1 ) {
	  $targets{$type}{$device}{$inside}{$key}{descr} = $z ; 
	} elsif( $sub == 0 ) {
	  $targets{$type}{$device}{descr} = $z ; 
	} else {
	  chomp($_) ;
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_conf: faulty configuration file " 
			. "$file at line $linenum: ($_) ... ignorning section"
			. " $type $device" ) ;
	  $err = $bad = 1 ;
	}
      } elsif( /^\s*displaygroup\s+(\S+)\s*/io && ! $bad ) {
	my $z = $1 ;
	if( $type eq "device" && $sub == 1 ) {
	  $targets{$type}{$device}{$inside}{$key}{displaygroup} = $z ;
	} elsif( $sub == 0 ) {
	  $targets{$type}{$device}{displaygroup} = $z ;
	} else {
	  chomp($_);
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_conf: faulty configuration " 
			. "file $file at line $linenum: ($_) ... " 
			. "ignoring section $type $device" ) ;
	  $err = $bad = 1 ;
	}
      } elsif( /^\s*collect\s+([Yy][Ee][Ss]|[Nn][Oo])\s*/io && ! $bad ) {
	my $retort = $1 ;
	if ( $type eq "device" ) {
	  if ( $sub == 1 ) { 
	    $targets{$type}{$device}{$inside}{$key}{collect} = $retort ;
	  } else { 
	    $targets{$type}{$device}{collect} = $retort ; 
	  }
	} elsif( $type eq "locale" ) { 
	  $targets{$type}{$device}{collect} = $retort ; 
	} else {
	  chomp($_) ;
	  $self->debug( loglevel => "LOG_ERR", 
			message => "read_conf: faulty configuration " 
			. "file $file at line $linenum: ($_) ... " 
			. "ignorning section $type $device" ) ;
	  $err = $bad = 1 ;
	}
      }	elsif( /^\s*valid\s+(1|0)\s*/io && ! $bad ) { 
	if ( $type eq "device" && $sub == 1 ) {
	  $targets{$type}{$device}{$inside}{$key}{valid} = $1 ; 
	} elsif( $type eq "locale" && $sub == 0 ) {
	  $targets{$type}{$device}{valid} = $1 ;
	} else {
	  chomp($_) ;
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_conf: faulty configuration file " 
			. "$file at line $linenum: ($_) ... ignorning " 
			. "section $type $device" ) ;
	  $err = $bad = 1 ;
	}
      } elsif( /^\s*interval\s+(\d+)\s*/io && ! $bad ) {
	my $retort = $1 ;
	if ( $sub == 1 ) { 
	  $targets{$type}{$device}{$inside}{$key}{interval} = $retort; 
	} elsif( $sub == 0 && ( $type eq "device" || $type eq "locale" ) ) { 
	  $targets{$type}{$device}{interval} = $retort ; 
	} else {
	  chomp($_) ;
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_conf: faulty configuration " 
			. "file $file at line $linenum:" 
			. " ($_) ... ignorning section $type $device" ) ;
	  $err = $bad = 1 ;
	}
      } elsif( /^\s*step\s+(\d+)\s*/io && ! $bad ) {
	my $retort = $1 ;
	if ( $sub == 1 ) { 
	  $targets{$type}{$device}{$inside}{$key}{step} = $retort; 
	} elsif( $sub == 0 && $type eq "locale" ) { 
	  $targets{$type}{$device}{step} = $retort ; 
	} else {
	  chomp($_) ;
	  $self->debug( loglevel => "LOG_ERR",
			message => "read_conf: faulty configuration " 
			. "file $file at line $linenum: ($_) ... " 
			. "ignorning section $type $device" ) ;
	  $err = $bad = 1 ;
	}
      #####################################################

      #####################################################
      } elsif( /^\s*\}\s*/ ) {         # closes a section
	if ( $sub == 1 ) { 
	  $sub = 0 ; $bad = 0 ;
	} else {
	  $bad = 0 ;
	  if( $type eq "device" ) {
	    unless( $targets{$type}{$device}{community} ) {
	      $targets{$type}{$device}{community} = $self->{'_community'} ;
	      $self->debug( loglevel => "LOG_WARNING", 
			    message => "read_conf: $type:$device: " 
			    . "community not set; setting to " 
			    . "$self->{'_community'}" ) ;
	    }
	    unless ( $targets{$type}{$device}{version} ) {
	      $targets{$type}{$device}{version} = $self->{'_snmpversion'} ;
	      $self->debug( loglevel => "LOG_WARNING", 
			    message => "read_conf: $type:$device: version" 
			    . " not set; setting to $self->{'_snmpversion'}" );
	    }
	    unless ( $targets{$type}{$device}{autoconfigure} ) {
	      $targets{$type}{$device}{autoconfigure} = "yes" ;
	    }
	  }
	  unless ( $targets{$type}{$device}{interval} ) {
	    $targets{$type}{$device}{interval} = $self->{'_interval_s'} ;
	    $self->debug( loglevel => "LOG_WARNING", 
			  message => "read_conf: $type:$device: interval" 
			  . " not set; setting to $self->{'_interval_s'}" ) ;
	  }
	  unless ( $targets{$type}{$device}{collect} ) {
	    $targets{$type}{$device}{collect} = $self->{'_defaultcollect'} ;
	    $self->debug( loglevel => "LOG_WARNING", 
			  message => "read_conf: $type:$device: collect" 
			  . " not set; setting to no");
	  }
	}
      } else { 
	chomp($_) ;
	$self->debug( loglevel => "LOG_ERR", 
		      message => "read_conf: faulty configuration file $file "
		      . "at line $linenum: ($_) ... ignorning section" 
		      . " $type $device" );
	$err = 1 ;
	if( $sub > 0 ) {
	  $bad = 1 ; 
	} else {
	  $bad = 0 ;
	}
      }
    } # while
    close( CONF ) ;
    $self->{targets} = \%targets ;
    #$self->debug( loglevel => "LOG_DEBUG",
    #		  message => "Leaving read_conf" ) ;
    $err ? ( return 0 ) : ( return 1 ) ;
  }


######################################################################
# PUBLIC
#
# Meant to be last thing called.  It writes out a new conf file
#   if the last one is not older than $targets{mtime}.  It then
#   stores %targets on disk.  $targets{mtime} represents the last
#   time %targets was synced with $CONF.  If mtime of $CONF is more
#   recent than $targets{mtime}, it is not safe to write out a new
#   $CONF.  Consequently, we'll reread it next time init() is run.
#=======================================
sub finalize
  {
    my $self = shift ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "Entering finalize" ) ;
    $self->write_confFiles() ;
    return 1 ;
  }

sub write_confFiles {
  ; # do nothing
}

######################################################################
# PUBLIC
sub _write_confFiles
  {
    my $self = shift ;
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "write_confFiles: creating backup");
    rename( $self->{'_conf'}, "$self->{'_conf'}.bak" ) ;
    $self->debug( loglevel => "LOG_DEBUG", 
		  message => "write_confFiles: unlinked $self->{'_conf'};" 
		  . " preparing sysopen" ) ;
    $self->debug( loglevel => "LOG_DEBUG", 
		  message => "write_confFiles: sysopening and" 
		  . " truncating to 0 $self->{'_conf'}.tmp" );
    unlink( "$self->{'_conf'}.tmp", $self->{'_conf'} ) ;
    sysopen( CONF, "$self->{'_conf'}.tmp", O_WRONLY|O_CREAT, 0664 ) 
      or $self->debug( loglevel => "LOG_ERR", 
		       message => "FAILURE: write_confFiles: Unable to" 
		       . " open $self->{'_conf'}.tmp: $!" );
    truncate( CONF, 0 ) ;
    flock( CONF, LOCK_EX ) 
      or $self->debug( loglevel => "LOG_ERR",
		       message => "FAILURE: write_confFiles: Unable to " 
		       . "lock $self->{'_conf'}: $!" );
    while( my($t, undef) = each( %targets ) ) {
      next if ( $t eq "mtime" ) ;
      foreach my $d ( sort keys %{ $targets{$t} } ) {
	$self->debug( loglevel => "LOG_DEBUG", 
		      message => "write_confFiles: writing config for $t:$d" );
	if( defined( $d ) && defined( $t ) ) {
	  print CONF $self->string_config( $t, $d ) ; 
	}
      }
    }
    $self->_write_store() ;
    truncate( CONF, tell(CONF) ) ;
    flock( CONF, LOCK_UN ) 
      or $self->debug( loglevel => "LOG_ERR", 
		       message => "write_confFiles: Unable to free lock " 
		       . "$self->{'_conf'}: $!" ) ;
    close( CONF ) ;
    unless( rename( "$self->{'_conf'}.tmp", $self->{'_conf'} ) ) {
      $self->debug( loglevel => "LOG_DEBUG", 
		    message => "write_confFiles: " 
		    . "unable to move tmp file to collect.conf" );
    }
    # temp...(maybe)
    chmod 0664, $self->{'_conf'}, $self->{'_store'} ;
    # /temp
    return 1;
  }


######################################################################
# PRIVATE
sub _write_store
  {
    my $self = shift ;
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ; 
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "write_store: sysopening & locking" 
		  . " $self->{'_store'}" ) ;
    sysopen( COLLECTION, "$self->{'_store'}", O_WRONLY|O_CREAT, 0664 ) 
      or $self->debug( loglevel => "LOG_ERR",
		       message => "FAILURE: write_store: Unable to open "
		       . "$self->{'_store'}: $!" ) ;
    flock( COLLECTION, LOCK_EX) 
      or $self->debug( loglevel => "LOG_ERR",
		       message => "FAILURE: write_store: Unable to lock" 
		       . " $self->{'_store'}: $!" );
    $self->debug( loglevel => "LOG_INFO",
		  message => "write_store: writing $self->{'_store'}" ) ;
    nstore_fd( \%targets, *COLLECTION) 
      or $self->debug( loglevel => "LOG_ERR",
		       message => "FAILURE: write_store: can't store hash" );
    truncate( COLLECTION, tell(COLLECTION) ) ;
    flock( COLLECTION, LOCK_UN ) 
      or $self->debug( loglevel => "LOG_WARNING",
		       message => "write_store: Unable to free lock" 
		       . " $self->{'_store'}: $!" ) ;
    close( COLLECTION );
  }


######################################################################
# PUBLIC
#
# takes in two arguments, $type and $device to key into $targets
#   and then prints out the relevant information for that $device.
#=======================================
sub string_config
  {
    my( $self, $type, $device ) = @_ ;
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "string_config: handling $type $device" );
    unless( exists( $targets{$type}{$device} ) ) {
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "string_config: can't find $type:$device" );
      return ; 
    }
    unless( defined( $type ) && defined( $device ) ) {
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "string_config: $type:device look empty" ) ;
      return;
    }
    my( $keyA, $keyB, $keyC, $config, @others ) ;

    $config = "$type $device { \n" ;
    foreach $keyA ( sort keys %{ $targets{$type}{$device} } ) {
      #
      # reject locale stuff we don't want to 'print'
      #      next if ( $type eq "locale" && 
      #		( $keyA eq "sources" || $keyA eq "dstotal" ||
      #		  $keyA eq "dscount" || $keyA eq "lastvalues" ||
      #		  $keyA eq "values" ) ) ;
      if ( $aliases{$keyA} &&
	   $targets{$type}{$device}{$keyA} !~ /(yes|no)/io ) { 
	push @others, $keyA ;
      }	else { 
	#next if ( $keyA =~ /^sysUpTime/io ) ;
	next unless( $keyA eq "autoconfigure" || $keyA eq "collect" 
		     || $keyA eq "community" || $keyA eq "descr" 
		     || $keyA eq "targetaddress" || $keyA eq "interval"
		     || $keyA eq "timeout" || $keyA eq "retries"
		     || $keyA eq "version" || $keyA eq "sysUpTime" 
		     || $keyA eq "filename" || $keyA eq "displaygroup"
		     || $keyA eq "valid" || $keyA eq "step" ) ;
	if ( $targets{$type}{$device}{$keyA} =~ /\n/ ) { 
	  $targets{$type}{$device}{$keyA} =~ tr/\n// ; 
	  $targets{$type}{$device}{$keyA} =~ s/\s*$//g ;
	}
	$config .= "   $keyA $targets{$type}{$device}{$keyA} \n" ; 
      }
    }
    if ( @others ) {
      foreach $keyA ( @others ) {
	# this will get each interface/car/bgpPeer/etc
	foreach $keyB ( sort keys %{ $targets{$type}{$device}{$keyA} } ) { 
	  if ( defined( $keyB ) ) {
	    $config .= "   $keyA $keyB {  \n" ;
	    foreach $keyC 
	      ( sort keys %{$targets{$type}{$device}{$keyA}{$keyB}} ) {
		next unless( $keyC eq "collect" || $keyC eq "descr" 
			     || $keyC eq "filename" || $keyC eq "instance"
			     || $keyC eq "interval" || $keyC eq "lockdescr"
		     # || $keyC eq "ifSpeed" || $keyC eq "ccarConfigRate"
 			     || $keyC eq "valid" ||$keyC eq "ipaddress"
			     || $keyC eq "locale" || $keyC eq "displaygroup" 
			     || $keyC eq "step" ) ;
		#
		# reject device stuff we don't want to print
		#next if ( $keyC eq "lastvalues" || $keyC eq "mibs" 
		#	  || $keyC eq "acl" || $keyC eq "highcounter" 
		#	  || $keyC eq "ifType" ) ;
		if ( $targets{$type}{$device}{$keyA}{$keyB}{$keyC} =~ /\n/ ) { 
		  $targets{$type}{$device}{$keyA}{$keyB}{$keyC} =~ tr/\n// ; 
		  $targets{$type}{$device}{$keyA}{$keyB}{$keyC} =~ s/\s*$//g ;
		}
		if ( $keyC eq "locale" ) {
		  my $keyD ;
		  foreach $keyD 
		    ( sort keys
		      %{ $targets{$type}{$device}{$keyA}{$keyB}{locale} } ) {
		      if( $targets{$type}{$device}{$keyA}{$keyB}{locale}
			  {$keyD}{invert} ) {
			$config .= "       $keyC $keyD invert\n" ;
		      } else {
			$config .= "       $keyC $keyD normal\n" ;
		      }
		    }
		} else {
		  $config .=  "       $keyC " . 
		    "$targets{$type}{$device}{$keyA}{$keyB}{$keyC}\n" ;
		}
	      }
	    $config .= "    } \n" ;
	  }
	}
      }
    }
    $config .= "}\n" ;
    return $config ;
  }


######################################################################
# PRIVATE
sub _get_filename
  {
    my( $self, $type, $dev, $cat, $inst ) = @_ ;
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "Entering get_filename" ) ;
    if( $type eq "device" ) {
      return $targets{$type}{$dev}{$cat}{$inst}{filename} ;
    } elsif( $type eq "locale" ) {
      return $targets{$type}{$dev}{filename} ;
    } else {
      return "" ;
    }
  }


##########################################################################
#=========================================================================
#
#  Assorted methods to munge %targets hash
#    whether set, reset, delete, whatever
#
#=========================================================================
##########################################################################


######################################################################
# PRIVATE
#
# set filename for a particular rrd instance (meant for device tree elements)
#
sub _set_dev_filename {
  my( $self, $type, $dev, $cat, $inst ) = @_ ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  my( $filename, $c, $k ) ;
  if( $type eq "device" ) {
    if( defined( $metacat{$cat}{alias} ) ) {
      $c = $metacat{$cat}{alias} ;
      $c =~ s/\"//g ;
    } else {
      $c = $cat ;
    }
    $k = $inst;
    if( $cat eq "interface" ) {
      if( defined( $targets{$type}{$dev}{$cat}{$inst}{ipaddress} )
	  && ( scalar
	       ( keys %{ $targets{$type}{$dev}{$cat}{$inst}{ipAdEntIfIndex} } )
	       < 2 ) ) {
	$k = $targets{$type}{$dev}{$cat}{$inst}{ipaddress} ;
      }
    }
  }
  defined( $inst ) ? 
    ( $filename = "$dev.$c.$k.rrd" ) : ( $filename = "$dev.$c.rrd" );

  $filename =~ tr/\/:/./ ;
  $filename =~ tr/ ()!@$%^&*[]{}\|+=?<>:;\'\"\#/_/ ;
  $filename =~ s/__+/_/g ;
  $filename = "$dev/$filename" ;
  # check to see if filename exists/in use and carp if so
  foreach my $t ( keys %{ $targets{$type}{$dev}{$cat} } ) {
    next if( $t eq $inst ) ;
    if( $targets{$type}{$dev}{$cat}{$t}{filename} eq $filename ) {
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "Warning: $type:$dev:$cat:inst may" 
		    . " have same filename as $t ($filename)" ) ;
    }
  }
  return $filename ;
}


######################################################################
# set SOCKET
sub set_socket {
  my($self, $arg) = @_ ;
  $self->debug( loglevel => "LOG_INFO", 
		message => "Setting SOCKET for client communications" ) ;
  $SOCKET = $arg ;
  $self->_clear_error ;
  return 1;
}
sub unset_socket {
  my $self = shift ;
  $self->debug( loglevel => "LOG_INFO", 
		message => "Undefining SOCKET for client communications" ) ;
  undef $SOCKET ;
  $self->_clear_error ;
  return 1;
}


######################################################################
# set debug level -- this level and above will be logged
sub set_loglevel {
  my($self, $arg) = @_ ;
  my( %levelgol ) = reverse %loglevel;
  if( $loglevel{$arg} ) {
    $self->debug( loglevel => "LOG_INFO", 
		  message => "set_debuglevel: " 
		  . "Setting debug level to $self->{'_loglevel'}" ) ;
    $self->{'_loglevel'} = $arg;
    $self->_clear_error ;
    return 1;
  } else {
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "set_debuglevel: Unknown debug level: $arg" ) ;
    $self->{'_error'} = "set_debuglevel: Unknown debug level: $arg" ;
    return 0;
  }
}


######################################################################
#
# These methods determine what kinds of things we can gather
# on a specific interface.  If we don't have 'lastvalues', then
# we enter the if block and determine what things can be gathered
# based on the type of interface and whether I can gather
# HighCounter info.  If we do have 'lastvalues', we go to the else
# block and use the last OIDs used.
#
#

######################################################################
# PUBLIC
#
# get the name that goes into the RRD as the DS
sub get_ds
  {
    my ( $self, $type, $dev, $cat, $inst ) = @_ ;
    return $self->_get_vards( $type, $dev, $cat, $inst, "ds" ) ;
  }

######################################################################
# PUBLIC
#
# get the name we use internally and for snmp get requests
sub get_mibs
  {
    my ( $self, $type, $dev, $cat, $inst ) = @_ ;
    return $self->_get_vards( $type, $dev, $cat, $inst, "mib" ) ;
  }

######################################################################
# PRIVATE
#
sub _get_vards
  {
    my ( $self, $type, $dev, $cat, $inst, $vards ) = @_ ;
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    $self->debug( loglevel => "LOG_DEBUG", 
		  message => "get_vards: handling $type:$dev:$cat:$inst" ) ;
    my ( @mibs, @keys ) ;
    ##############################################
    # sanity check; bail if tests fail
    if( $type eq "device" ) {
      unless ( exists( $targets{$type}{$dev}{$cat}{$inst} ) ) {
	$self->debug( loglevel => "LOG_WARNING", 
		      message => "get_vards: unable to find" 
		      . " $type:$dev:$cat:$inst" );
	return ;
      }
    } elsif( $type eq "locale" ) {
      unless ( exists( $targets{$type}{$dev} ) ) {
	$self->debug( loglevel => "LOG_WARNING",
		      message => "get_vards: unable to find $type:$dev" );
	return ;
      }
    }
    if( $type eq "device" ) {
      ############################################
      # if a device ....
      if ( $cat eq "interface" ) {
	##########################################
	# if an interface, we need to do a couple additional checks
	#   check for highcounter
	#   check ifType
	my($session, $error) = $self->open_snmp_session( $type, $dev ) ;
	my( $hc, $ifType, %m, %results ) ;
	##########################################
	# check to see if highcounter is set
	#   if not, get ifSpeed value
	unless( exists( $targets{$type}{$dev}{$cat}{$inst}{highcounter} ) ) {
	  ########################################
	  # if not, set ifSpeed (if not already set)
	  unless( exists( $targets{$type}{$dev}{$cat}{$inst}{ifSpeed} ) ) {
	    %results = $self->get_snmp_values
	      ( type => $type, dev => $dev, cat => $cat, inst => $inst,
		session => $session,
		instance => $targets{$type}{$dev}{$cat}{$inst}{instance},
		oids => [ $aliases{general}{ifSpeed} ] ) ;
	    unless( ! defined( $results{ $aliases{general}{ifSpeed} } ) 
		    || $results{ $aliases{general}{ifSpeed} } 
		    =~ /noSuchObject/io 
		    || $results{ $aliases{general}{ifSpeed} } 
		    =~ /noSuchInstance/io ) {
	      $targets{$type}{$dev}{$cat}{$inst}{ifSpeed} =
		$results{ $aliases{general}{ifSpeed} } ;
	    }
	  }
	  ########################################
	  # check to see if ifType is set
	  unless( exists( $targets{$type}{$dev}{$cat}{$inst}{ifType} ) ) {
	    %results = $self->get_snmp_values
	      ( type => $type, dev => $dev, cat => $cat, inst => $inst,
		session => $session,
		instance => $targets{$type}{$dev}{$cat}{$inst}{instance},
		oids => [ $aliases{general}{ifType} ] ) ;
	    $targets{$type}{$dev}{$cat}{$inst}{ifType} 
	      = $ifType{ $results{ $aliases{general}{ifType} } } 
		|| $results{$aliases{general}{ifType}} ;
	  }
	  ########################################
	  # now go set highcounter
	  $targets{$type}{$dev}{$cat}{$inst}{highcounter} =
	    $self->_set_highcounter
	      ( $targets{$type}{$dev}{$cat}{$inst}{ifSpeed},
		$targets{$type}{$dev}{$cat}{$inst}{ifType}, 
		$targets{$type}{$dev}{version} ) ;
	}
	if ( $targets{$type}{$dev}{$cat}{$inst}{highcounter} == 1 ) { 
	  $hc = 1 ; 
	} else { 
	  $hc = 0 ; 
	}
	##########################################
	# ifType helps us determine between frameRelay & propPointtoPointSerial
	#   so that we can tell what DSes to collect
	$ifType = $targets{$type}{$dev}{$cat}{$inst}{ifType} ;
	if( $ifType eq "frameRelay" || $ifType == 32 ) {
	  my $response ;
	  ########################################
	  # if ifType is frameRelay && we have that instance
	  if( defined( $targets{$type}{$dev}{"frameRelay"}{$inst} ) ) {
	    ######################################
	    # see if it is a frame relay sub interface
	    if( defined( $targets{$type}{$dev}{"frameRelay"}{$inst}
			 {cfrExtCircuitSubifIndex} ) ) {
	      $response = $targets{$type}{$dev}{frameRelay}{$inst}
		{cfrExtCircuitSubifIndex} ;
	    } else {
	      # ##################################
	      # if not cached, go get the value (for sub interface)
	      %results = $self->get_snmp_values
		( type => $type, dev => $dev, cat => $cat, inst => $inst,
		  session => $session,
		  instance => $targets{$type}{$dev}{$cat}{$inst}{instance},
		  oids => [ $aliases{general}{cfrExtCircuitSubifIndex} ] ) ;
	      if( defined
		  ( $results{ $aliases{general}{cfrExtCircuitSubifIndex} } ) ){
		$response = $targets{$type}{$dev}{frameRelay}{$inst}
		  {cfrExtCircuitSubifIndex} 
		    = $results{ $aliases{general}{cfrExtCircuitSubifIndex} } ;
	      } else {
		$response = 0 ;
	      }
	    }
	  } else {
	    $response = 0 ;
	  }
	  ########################################
	  # if it's really a framerelay, collect those stats; otherwise pppS
	  if( $response ) {
	    %m = %{ $ifdata{frameRelay} } ;
	  } else {
	    %m = %{ $ifdata{propPointtoPointSerial} } ;
	  }
	} else {
	  if( $ifdata{$ifType} ) {
	    %m = %{ $ifdata{$ifType} } ;
	  } else {
	    %m = %{ $ifdata{default} } ;
	  }
	}
	##########################################
	# substitute HC if necessary for interface
	if( $hc ) {
	  foreach my $var ( ( "ifInOctets", "ifOutOctets", 
			      "ifInUcastPkts", "ifOutUcastPkts" ) ) {
	    delete( $m{$var} ) ;
	  }
	} else {
	  foreach my $var ( ( "ifHCInOctets", "ifHCOutOctets", 
			      "ifHCInUcastPkts", "ifHCOutUcastPkts" ) ) {
	    delete( $m{$var} ) ;
	  }
	}
	##########################################
	# now we set what kinds of values they want: 'mib' or 'ds'
	if( $vards eq "mib" ) {
	  @mibs = keys %m ;
	} elsif( $vards eq "ds" ) {
	  map { push @mibs, $aliasDS{$cat}{$_} } keys %m ;
	} else {
	  @mibs = keys %m ;
	}
	$self->close_snmp_session( $session ) ;
      } else {
	##########################################
	# set the kinds of values they want: 'mib' or 'ds'
	if( $vards eq "mib" ) {
	  @mibs = keys %{ $aliases{$cat} } ;
	} elsif( $vards eq "ds" ) {
	  map { push @mibs, $aliasDS{$cat}{$_} } keys %{ $aliases{$cat} } ;
	} else {
	  @mibs = keys %{ $aliases{$cat} } ;
	}
      }
    } elsif( $type eq "locale" ) {
      ############################################
      # if a locale ....
      unless( defined( $targets{$type}{$dev}{dstotal} ) ) {
	$self->build_locale( $type, $dev ) ; 
      }
      @mibs = keys %{ $targets{$type}{$dev}{dstotal} } ;
    } else {
      ############################################
      # otherwise, we don't care/check ....
      $self->debug( loglevel => "LOG_WARNING",
		    message => "get_vards: Unknown type $type" ) ;
    }
    return @mibs ;
  }


#========================================
# PUBLIC
#
# if $FOREGROUND is set, print to STDERR
# otherwise, syslog the message.  
# We take the arguments: 
#             loglevel -- loglevel for this message
#             message  -- message to send to syslog
#  OPTIONAL   ident    -- identity string for syslog
#
#========================================
sub debug {
  my( $self, %argv ) = @_ ;
  my( $ident, $level, $message, $date ) ;

  if( $argv{message} ) {
    $message = $argv{message} ;
  } else {
    $self->debug( loglevel => "LOG_ERR", 
		  message => "Error: debug() called, but no message: @_" ) ;
    return ;
  }
  $level = $argv{loglevel} ;
  $argv{ident} ? 
    ( $ident = $argv{ident} ) : ( $ident = $self->{'_syslogident'} ) ;

  $date = localtime( time ) ;
  unless( $loglevel{$level} ) { 
    $level = "LOG_NOTICE" ;
  }
  if ( $lognum{$level} <= $lognum{ $self->{'_loglevel'} } ) {
    if( defined( $SOCKET ) ) {
      select( $SOCKET ) ;
      print $SOCKET "$message\n" ;
    }
    if ( $self->{'_foreground'} ) {
      select(STDERR) ;
      warn "$date $message" ;
    } else {
      if( Sys::Syslog::_PATH_LOG() && -e Sys::Syslog::_PATH_LOG() ) {
	setlogsock( 'unix' ) ;
	openlog( $ident, 'cons', $logfacility{ $self->{'_logfacility'} } );
	syslog( $loglevel{$level}, "$message" ) ;
	closelog() ;
      } else {
	setlogsock( 'inet' ) ;
	openlog( $ident, 'cons', $logfacility{ $self->{'_logfacility'} } );
	syslog( $loglevel{$level}, "$message" ) ;
	closelog() ;
      }
    }
  }
}


#######################################
# PUBLIC
#
# opens an snmp session to some device
# should be called as object method
# req. args: type and device
# returns the session object and error string (if it exists)
#
sub open_snmp_session 
  {
    my( $self, $type, $device ) = @_ ;
    my( $host, $comstr, $version, $timeout, $retries, $session, 
	$error, $translate ) ;
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    $host = $targets{$type}{$device}{targetaddress} || $device ;
    $comstr = $targets{$type}{$device}{community} || $self->{'_community'} ;
    $version = $targets{$type}{$device}{version} || $self->{'_snmpversion'} ;
    $timeout = $targets{$type}{$device}{timeout} || $self->{'_timeout'} ;
    $retries = defined( $targets{$type}{$device}{retries} )
      || $self->{'_retries'} ;
    $translate = 0 ;
    $self->debug( loglevel => "LOG_DEBUG", 
		  message => "open_snmp_session: creating session to "
		  . "$type:$device");
    ($session, $error) = Net::SNMP->session( Hostname  => $host,
					     Community => $comstr,
					     Port      => 161,
					     Version   => $version,
					     Timeout   => $timeout,
					     Retries   => $retries ) ;
    return ( $session, $error ) ;
  }


########################################
# PUBLIC
#
# call as object method
# req. arg: Net::SNMP session object
# returns nothing
#
sub close_snmp_session
  {
    my( $self, $session ) = @_ ;
    $session->close ;
  }


########################################
# PUBLIC
#
# call as object method
# arguments:
#           session - session object (returned from open_snmp_session
#           type    - which type
#           dev     - device|locale name
#           cat     - category
#           inst    - name of this category instance
#           vars    - an array of snmp var names to get values for
#           oids    - an array of OIDs to get values for
#           instance - snmp instance value
#
sub get_snmp_values
  {
    my( $self, %argv ) = @_ ;
    my( $response, $string, %results ) ;
    my( $session, $type, $dev, $cat, $inst, $instance, @vars, @oids );
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    $session = $argv{session} ;
    $type = $argv{type} ;
    $dev = $argv{dev} ;
    $cat = $argv{cat} ;
    $inst = $argv{inst} ;
    $instance = $argv{instance} ;
    unless( defined( $session ) && defined( $type ) && defined( $dev ) ) {
      $self->debug( loglevel => "LOG_ERR",
		    message => "get_snmp_values: required vars not defined" ) ;
      $self->{'_error'} = "get_snmp_values: required vars not defined" ;
      undef %results ;
      return %results ;
    }
    if( $argv{vars} ) {
      @vars = @{ $argv{vars} } ;
      unless( $type eq "device" ) {
	return 0 ;
      }
      map {
	defined( $instance ) ?
	  ( push @oids, "$aliases{$cat}{$_}.$instance" ) :
	    ( push @oids, "$aliases{$cat}{$_}" ) } @vars ;
      for( my($i)=0; $i < scalar(@vars); $i++ ) {
	$vars[$i] = $aliasDS{$cat}{ $vars[$i] } ;
      }
    } elsif( $argv{oids} ) {
      @oids = @{ $argv{oids} } ;
      @vars = @oids ;
      if( defined( $instance ) ) {
	for(my($i)=0; $i < scalar( @oids ); $i++ ) {
	  $oids[$i] .= ".$instance" ;
	}
      }
      unless( $type eq "device" ) {
	print "  HELLO \n";
	print "$type:$dev:$cat:$inst \n";
	return 0 ;
      }

    } else {
      $self->{'_error'} = "Error: get_snmp_values: no oids or vars defined" ;
      $self->debug( loglevel => "LOG_ERR",
		    message => "Error: get_snmp_values: no oids or vars "
		    . "defined; no snmp values to get" ) ;
      undef %results ;
      return %results ;
    }
    $string = "$type;$dev" ;
    $results{time} = time() ;
    if( defined( $response = $session->get_request( @oids ) ) ) { 
      $self->debug( loglevel => "LOG_DEBUG", 
		    message => "get_snmp_values: " 
		    . "$type:$dev:$cat:$inst got data" ) ;
      for( my($i)=0; $i < scalar( @oids ) ; $i++ ) {
	$self->debug( loglevel => "LOG_DEBUG",
		      message => "get_snmp_values: $type:$dev:$cat:$inst "
		      . "$vars[$i] $response->{ $oids[$i] }" ) ;
	# print "  $vars[$i] $oids[$i] $response->{ $oids[$i] } \n" ;
	$results{ $vars[$i] } = $response->{ $oids[$i] } ;
      }
    } else { 
      $self->debug( loglevel => "LOG_WARNING",
		    message => "get_snmp_values: $type:$dev:$cat:$inst: " 
		    . "no response " . $session->error );
      for( my($i)=0; $i < scalar( @oids ) ; $i++ ) {
	# $results{ $vars[$i] } = "U" ;
	undef( $results{ $vars[$i] } ) ;
      }
    }
    return %results ;
  }


########################################
# PUBLIC
#
# call as object method
# arguments:
#           session - session object (returned from open_snmp_session
#           type    - which type
#           dev     - device|locale name
#           cat     - category
#           var     - snmp var name to get table of values for
#
sub get_next_snmp_values
  {
    my( $self, %argv ) = @_ ;
    my( $response, $string ) ;
    my( $session, $type, $dev, $cat, $inst, $var, $oid, %results );
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    $session = $argv{session} ;
    $type = $argv{type} ;
    $dev = $argv{dev} ;
    $cat = $argv{cat} ;
    $var = $argv{var} ;
    $oid = $aliases{$cat}{$var} ;
    $inst = "0" ;
    $oid = "$oid.$inst" ;
    unless( defined( $session ) && defined( $type ) && defined( $dev ) ) {
      $self->debug( loglevel => "LOG_ERR",
		    message => "get_next_snmp_values: required vars not" 
		    . " defined" ) ;
      $self->{'_error'} = "get_next_snmp_values: required vars not defined" ;
      undef %results ;
      return %results ;
    }
    $self->debug( loglevel => "LOG_DEBUG", 
		  message => "get_next_snmp_values: $type:$dev: " 
		  . "getting $var" );
    while ( $oid =~ /^$aliases{$cat}{$var}\./ ) {

      if ( defined( $response = $session->get_next_request( $oid ) ) ) {
	my @keys  = keys %{ $response } ;
	$_ = $keys[0] ;
	my $val = $response->{$_} ;
	$oid = $_ ;
	( $inst ) = /^$aliases{$cat}{$var}\.(.*)$/ ;
	$oid =~ s/\.$inst$//g ;
	if( defined( $val ) && defined( $inst )  ) {
	  $results{$inst} = $val ;
	  $self->debug( loglevel => "LOG_INFO",
			message => "get_next_snmp_values: $type:$dev:$cat " 
			. "found $inst -> $val" ) ;
	} elsif( $inst ) {
	  $self->debug( loglevel => "LOG_INFO",
			message => "get_next_snmp_values: $type:$dev:$cat " 
			. " found $inst" ) ;
	  $results{$inst} = "";
	} else {
	  $oid = "abc" ;
	}
      } else {
	$oid = "abc" ;
      }
      $oid = "$oid.$inst" ;
    }
    return %results ;
  }


#============================================================
#
# PUBLIC
#
# check for a possible reset.  First, current sysUpTime must be
# greater than the last stored sysUpTime for this device's interval.
# Second, it must be *at least* bigger by a third.
# upTimes are measured to hundredths of a second.
#=============================================================
sub detect_rollover
  {
    my( $self, %argv ) = @_ ;
    my( $response, $string, %results ) ;
    my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
    my $type = $argv{type} ;
    my $dev = $argv{dev} ;
    my $cat = $argv{cat} ;
    my $inst = $argv{inst} ;
    my $uptime = $argv{uptime} ;

    if( $uptime >= 0 
	&& $uptime > $targets{$type}{$dev}{"sysUpTime$self->{'_interval'}"}
	&& ( $uptime - $targets{$type}{$dev}{"sysUpTime$self->{'_interval'}"} )
	>= ( $self->{'_interval'} / 3 * 60 * 100 ) ) {
      return 0 ;
    } else {
      if( $uptime < 0 ) {
	$self->debug( loglevel => "LOG_WARNING", 
		      message => "handle_rollover: " 
		      . "$type:$dev:$cat:$inst appears unreachable" );
      } elsif( $uptime 
	       < $targets{$type}{$dev}{"sysUpTime$self->{'_interval'}"} ) {
	$self->debug( loglevel => "LOG_WARNING",
		      message => "handle_rollover: $type:$dev:$cat " 
		      . "premature wrap? " . $uptime . " (was " 
		      . $targets{$type}{$dev}{"sysUpTime$self->{'_interval'}"}
		      . ")" );
      } else { 
	$self->debug( loglevel => "LOG_WARNING",
		      message => "handle_rollover: $type:$dev:$cat "
		      . "not enough time between updates: " . $uptime 
		      . " (was " 
		      . $targets{$type}{$dev}{"sysUpTime$self->{'_interval'}"}
		      . ")" );
      }
      return 1 ;
    }
  }



######################################################################
#====================================================================
#
#  Build stuff
#  build up necessary info regarding device so as to get data from it
#
#====================================================================
######################################################################



######################################################################
# Get config information for a particular device 
# Must supply $type (usually 'device'), device name in %targets
#
sub build_config {
  my( $self, $type, $device ) = @_ ;
  my ( $host, $num, $session, $error, $skipped );
#	 $version, $comstr, $timeout, $retries, $skipped,
#	 @frstuff, @oids, %data ) ;
  $self->debug( loglevel => "LOG_INFO",
		message => "build_config: handling $type:$device" ) ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  $skipped = 0 ;
  unless( exists( $targets{$type}{$device} ) ) {
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "build_config: $type:$device not defined");
    $targets{$type}{$device}{autoconfigure} = "yes" ;
    $targets{$type}{$device}{version} = $self->{'_snmpversion'} ;
    $targets{$type}{$device}{community} = $self->{'_community'} ;
    $targets{$type}{$device}{collect} = $self->{'_defaultcollect'} ;
    $self->{targets} = \%targets ;
  }
  unless( exists( $targets{$type}{$device}{interval} ) ) {
    $targets{$type}{$device}{interval} = $self->{'_interval_s'} ;
  }
  unless( exists( $targets{$type}{$device}{autoconfigure} ) ) {
    if( $type eq "device" ) {
      $targets{$type}{$device}{autoconfigure} = "yes" ;
    }
  }
  #
  # since we're rebuilding %targets, 
  # mark all previous collections as 'invalid', 
  # i.e. old and possibly no longer valid
  #
  $self->debug( loglevel => "LOG_DEBUG",
		message => "build_config: setting everything to valid=0" );
  if ( -e $self->{'_store'} && $type eq "device" 
       && $targets{$type}{$device}{autoconfigure} eq "yes" ) {
    foreach my $cat ( keys %aliases ) { 
      if ( exists( $targets{$type}{$device}{$cat} )
	   && $targets{$type}{$device}{$cat} ne "yes" ) {
	foreach ( keys %{ $targets{$type}{$device}{$cat} } ) { 
	  $targets{$type}{$device}{$cat}{$_}{valid} = 0 ; 
	}
      }
    }
  }
  if ( $type eq "device" && 
       $targets{$type}{$device}{autoconfigure} eq "yes" ) {
    ($session, $error) = $self->open_snmp_session( $type, $device ) ;
    if ( defined( $session ) ) {
      $self->_get_sysinfo( $type, $device, $session ) ;
      if( $targets{$type}{$device}{sysUpTime} >= 0 ) {
	$self->_get_info( $type, $device, $session ) ;
      } else {
	$self->debug( loglevel => "LOG_WARNING", 
		      message => "build_config: $type:$device: " 
		      . "no response to sysUpTime...Skipping" ) ;
	$skipped = 1 ;
      }
      $self->close_snmp_session( $session ) ;
    } else {
      $self->debug( loglevel => "LOG_ERR", 
		    message => "build_config: " 
		    . "$type:$device: could not establish session: $error" );
      $skipped = 1;
    }
  } elsif( $type eq "locale" ) {
    $self->build_locale( $type, $device ) ;
  } elsif( $type eq "device" ) {
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "build_config: $type:$device:autoconfigure" 
		  . " set to no; skipping" ) ;
    $skipped = 1;
  } else {
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "build_config: unknown type $type" ) ;
    $skipped = 1 ;
  }
  if( $targets{$type}{$device}{autoconfigure} eq "yes" && ! $skipped ) {
    foreach my $cat ( keys %aliases ) {
      if( exists( $targets{$type}{$device}{$cat} ) ) {
	foreach( keys %{ $targets{$type}{$device}{$cat} } ) {
	  if ( $targets{$type}{$device}{$cat}{$_}{valid} == 0 ) {
	    unless( $targets{$type}{$device}{$cat}{$_}{collect} == "no" ){
	      $self->debug( loglevel => "LOG_WARNING",
			    message => "build_config: $type:$device:$cat:$_:"
			    . " setting collect = no (valid=0)" ) ;
	    }
	    $targets{$type}{$device}{$cat}{$_}{collect} = "no" ;
	    $self->debug( loglevel => "LOG_WARNING", 
			  message => "build_config: $type:$device:$cat:$_ " 
			  . "doesn't appear to be collectible (valid = 0)" );
	  }
	}
      }
    }
  }
  return 1;
}


######################################################################
# PRIVATE method
# get sysinfo   generic system info 
#
sub _get_sysinfo {
  my( $self, $type, $dev, $session ) = @_ ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  $self->debug( loglevel => "LOG_INFO",
		message => "get_sysinfo: handling $type:$dev" ) ;
  unless( exists( $targets{$type}{$dev}{targetaddress} ) ) {	
    $targets{$type}{$dev}{targetaddress} = $dev ; 
  }
  unless( exists( $targets{$type}{$dev}{descr} ) ) {
    $targets{$type}{$dev}{descr} = $dev ;
  }
  unless( defined( $targets{$type}{$dev}{community} ) ) {
    $targets{$type}{$dev}{community} = $self->{'_community'} ;
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "_get_sysinfo: $type:$dev: community not " 
		  . "defined; setting to $self->{'_community'}");
  }
  $self->debug( loglevel => "LOG_DEBUG", 
		message => "get_sysinfo: getting sysDescr sysObjectID " 
		. "sysName sysLocation sysUpTime" ) ;
  my(@oids) = ( $aliases{general}{sysDescr},
		$aliases{general}{sysObjectID},
		$aliases{general}{sysName}, 
		$aliases{general}{sysLocation},
		$aliases{general}{dot1dBaseBridgeAddress} );

  my %res = $self->get_snmp_values( type => $type, dev => $dev, 
				    oids => \@oids, session => $session ) ;

  my $sysloc =  $res{$oids[3]};
  $sysloc =~ tr/\n// ;
  $sysloc =~ s/\s+/ /g ;
  my $sysdescr = $res{$oids[0]};
  $sysdescr =~ tr/\n// ;
  $sysdescr =~ s/\s+/ /g;

  # Not sure if these are needed.....
  $targets{$type}{$dev}{"sysDescr"} = $sysdescr;
  $targets{$type}{$dev}{"sysObjectID"} = $res{ $oids[1] };
  $targets{$type}{$dev}{"sysName"} = $res{ $oids[2] };
  $targets{$type}{$dev}{"sysLocation"} = $sysloc ;
  $targets{$type}{$dev}{"sysUpTime"} = $self->get_sysUpTime( $type, $dev ) ;
  $targets{$type}{$dev}{"dot1dBaseBridgeAddress"} = $res{ $oids[4] };
}


######################################################################
# PRIVATE method
# go through all categories defined in etc/categories 
# and check which apply for a given device (and flesh out as necessary)
#
sub _get_info {
  my( $self, $type, $dev, $session ) = @_ ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  my ( $oid, $response, $err ) ;
  #while( my($cat,undef) = each( %aliases ) ) {
  foreach my $cat ( sort keys %aliases ) {
    next if ( $cat eq "general" ) ;
    $self->debug( loglevel => "LOG_INFO",
		  message => "get_info: $type:$dev testing for $cat" ) ;
    if( $metacat{$cat}{map} ) {
      #
      # if we need to walk a 'map' table
      #
      $self->_get_info_map( type => $type, dev => $dev, 
			    cat => $cat, session => $session) ;
    } elsif ( defined( $metacat{$cat}{instance} ) ) {
      #
      # if we don't have to walk a map table, but have a specific instance
      #
      $self->_get_info_instance( type => $type, dev => $dev, 
				 cat => $cat, session => $session) ;
    } elsif( exists( $metacat{$cat}{table} ) ) {
      # 
      # a table entry 
      #
      $self->_get_info_table( type => $type, dev => $dev, 
			      cat => $cat, session => $session) ;
    } else {
      $self->debug( loglevel => "LOG_WARNING", 
		    message => "_get_info: invalid category $cat: " 
		    . "doesn't specify 'map' or 'instance'" );
      next ;
    }
  }
}


######################################################################
# PRIVATE
# test for some condition; returns 1 for failure; 0 for false
#
sub _run_info_test {
  my( $self, %argv ) = @_ ;
  my( $type, $dev, $cat, $session, $inst, $instance ) ;
  my( @far, $fail ) ;
  $type = $argv{type} ;
  $dev = $argv{dev} ;
  $cat = $argv{cat} ;
  $inst = $argv{inst} ;
  $instance = $argv{instance} ;
  $session = $argv{session} ;
  $fail = 0 ;

  foreach my $test ( keys %{ $metacat{$cat}{test} } ) {
    my $err = 0 ;
    my @far = split( /\s+/, $test ) ;
    for( my($i)=0; $i < scalar( @far ); $i++ ) {
      if( $far[$i] =~ /^\$\w+/ ) {
	$far[$i] =~ s/^\$// ;
	if( $far[$i] =~ /^\w+\.inst$/ ) {
	  $far[$i] =~ s/\.inst$//g ;
	}
      }
      if( $aliases{general}{ $far[$i] } ) {
	my $o = "$aliases{general}{ $far[$i] }" ;
	my %res = $self->get_snmp_values( type => $type, dev => $dev,
					  cat => $cat, inst => $inst,
					  instance =>  $instance,
					  oids => [ $o ], 
					  session => $session );
	if( $res{$o} =~ /noSuchObject/io || $res{$o} =~ /noSuchInstance/io
	    || $res{$o} =~ /^\s*$/ || ! defined( $res{$o} ) ) {
	  $far[$i] = 0;
	} else {
	  $far[$i] = $res{$o} ;
	}
      }
    }
    $test = join( " ", @far ) ;
    $self->debug( loglevel => "LOG_DEBUG",
		  message => "run_info_test: $type:$dev:$cat:$inst " 
		  . "test expr $test" ) ;
    if( ! $err ) {
      unless( eval( $test ) ) {
	$fail = 1;
      }
    }
  }
  return $fail ;
}


######################################################################
# PRIVATE method
# build map info
#
sub _get_info_map {
  my( $self, %argv ) = @_ ;
  my( $type, $dev, $cat, $session ) ;
  $type = $argv{type} ;
  $dev = $argv{dev} ;
  $cat = $argv{cat} ;
  $session = $argv{session} ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  my( $inst, %ips, $map, $key, $oid, $response, $err, %aux ) ;
  $inst = "0" ;
  $map = $metacat{$cat}{map} ;
  $map =~ s/^\$// ;
  $key = $aliases{general}{$map} ;
  $oid = "$aliases{general}{$map}.$inst" ;
  #
  # get all the ipaddresses for this device; wish the mib was 
  # implemented differently.  :-P
  if( $cat eq "interface" ) {
    my $o = "$aliases{general}{ipAdEntIfIndex}.0" ;
    my $oo = "$aliases{general}{ipAdEntNetMask}" ;
    $self->debug( loglevel => "LOG_DEBUG", 
		  message => "get_info_map: getting ipAdEntIfIndex" ) ;
    my %res = $self->get_next_snmp_values( session => $session, 
					   type => $type,
					   dev => $dev, cat => "general", 
					   var => "ipAdEntIfIndex" ) ;
    my %virt = $self->get_next_snmp_values( session => $session,
					    type => $type,
					    dev => $dev, cat => "general",
					    var => "cHsrpGrpVirtualIpAddr" );
    %virt = reverse %virt;
    foreach my $r ( keys %res ) {
      my %res2 = $self->get_snmp_values( type => $type, dev => $dev,
					 cat => $cat, session => $session,
					 instance => $r, oids => [ "$oo" ] );
      if( ! exists( $virt{ $res{$r} } ) ) {
	$ips{ $r }{ $res{$r} } = $res2{"$oo"};
      }
    }
  }
  my %results = $self->get_next_snmp_values( type => $type, dev => $dev,
					     cat => "general", var => $map,
					     session => $session ) ;
  while( my($inst, $val) = each( %results ) ) {
    #
    # skip those things that have a valid instance, but no value
    next if( ! defined( $val ) ) ;
    #
    # grab any other relevant auxiliary snmp vars
    if( $metacat{$cat}{aux} ) {
      %aux = $self->_grab_aux_info( $type, $dev, $cat, $inst, $session );
    }
    #
    # if an interface, set the ipaddress for this instance
    if( $cat eq "interface" ) {
      if( defined( $ips{$inst} ) ) {
	$aux{ipAdEntIfIndex} = \%{ $ips{$inst} } ;
      }
    }
    #
    # grab descr
    $aux{descr} = $self->_grab_descr( $session, $type, $dev, $cat, $inst ) ;
    #
    # if this instance needs to pass a test, take care of it
    if( $metacat{$cat}{test} ) {
      my $fail = $self->_run_info_test( type => $type, dev => $dev, 
					cat => $cat, inst => $val,
					instance => $inst,
					session => $session ) ;
      if( $fail ) {
	next ;
      }
    }
    #
    # set up various details now....
    if( $metacat{$cat}{key} eq "instance" ) {
      $self->_set_info_defaults( $type, $dev, $cat, $inst, $inst, %aux );
    } elsif( $metacat{$cat}{key} eq "value" ) {
      $self->_set_info_defaults( $type, $dev, $cat, $val, $inst, %aux );
    } elsif( $aliases{ $metacat{$cat}{key} } ) {
      my $c = $metacat{$cat}{key} ;
      if( $metacat{$c}{map} ) {
	my $mapA = $metacat{ $c }{map} ;
	$mapA =~ s/^\$// ;
	my $A = $aliases{general}{$mapA} ;
	if( $metacat{ $metacat{$cat}{key} }{key} eq "instance" ) {
	  $self->_set_info_defaults( $type, $dev, $cat, $inst, $inst, %aux );
	} elsif( $metacat{ $metacat{$cat}{key} }{key} eq "value" ){
	  my %res = $self->get_snmp_values( type => $type, dev => $dev,
					    instance => $inst, cat => $cat,
					    session => $session,
					    oids => [$A] ) ;
	  if( defined( $res{$A} ) ) {
	    $self->_set_info_defaults
	      ( $type, $dev, $cat, $res{"$A"}, $inst, %aux ) ;
	  } else {
	    $self->debug( loglevel => "LOG_WARNING", 
			  message => "get_info_map: $type:$dev:$cat: "
			  . "no response to $metacat{$c}{map} query: "
			  . $session->error ) ;
	  }
	}
      } else {
	$self->_set_info_defaults( $type, $dev, $cat, $inst, 
				   $metacat{$c}{instance}, %aux );
      }
    } else {
      # neither instance, value, or <cat> specified for key
      # shouldn't happen, but just in case
      $self->_set_info_defaults( $type, $dev, $cat, $inst, $inst, %aux );
    }
  }
}


######################################################################
# PRIVATE method
# build single instance info
#
sub _get_info_instance {
  my( $self, %argv ) = @_ ;
  my( $type, $dev, $cat, $session ) ;
  $type = $argv{type} ;
  $dev = $argv{dev} ;
  $cat = $argv{cat} ;
  $session = $argv{session} ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  my( $inst, %aux, $oid, $response, $fail ) ;
  if( $metacat{$cat}{instance} ne "null" ) {
    $inst = $metacat{$cat}{instance} ;
  } else {
    undef $inst ;
  }
  $fail = 0 ;
  #
  # if need to pass a test, take care of it
  if( $metacat{$cat}{test} ) {
    $fail = $self->_run_info_test( type => $type, dev => $dev, 
				   cat => $cat, inst => $inst,
				   instance => $inst,
				   session => $session) ;
  } elsif( $metacat{$cat}{exists} ) {
    my $var = $metacat{$cat}{exists} ;
    my $j = 0 ;
    $var =~ s/^\$// ;
    if( $var =~ /^\w+\.inst$/ ) {
      $var =~ s/\.inst$//g ;
      $j++ ;
    }
    my $o = $aliases{general}{$var} ;
    if( $j && defined( $inst ) ) {
      $o .= ".$inst" ;
      }
    $self->debug( loglevel => "LOG_WARNING",
		  message => "get_info_instance: $type:$dev:$cat testing " 
		  . "for $var" );
    my %res = $self->get_snmp_values( type => $type, dev => $dev,
				      cat => $cat, inst => $inst,
				      instance => $inst, oids => [ $o ],
				      session => $session ) ;
    if( $res{$o} =~ /noSuchInstance/io || $res{$o} =~ /noSuchObject/io ) {
      $fail = 1 ;
    } elsif( ! defined( $res{$o} ) ) {
      $fail = 1 ;
    }
  }  else {
    my @keys = keys %{ $aliases{$cat} } ;
    # try just one snmp var and see if it works....
    $oid = $aliases{$cat}{$keys[0]} ;
    if( defined( $inst ) ) {
      $oid .= ".$inst" ;
    }
    my %res = $self->get_snmp_values( type => $type, dev => $dev,
				      cat => $cat, inst => $inst,
				      instance => $inst, oids => [ $oid ],
				      session => $session ) ;
    if( $res{$oid} =~ /noSuchObject/io || $res{$oid} =~ /noSuchInstance/io 
	|| ! defined( $res{$oid} ) ) {
      $fail = 1 ;
    } else {
      ; # do nothing
    }
  }
  if ( ! $fail ) {
    if( $metacat{$cat}{aux} ) {
      %aux = $self->_grab_aux_info( $type, $dev, $cat, $inst, $session );
    }
    $aux{descr} = $self->_grab_descr( $session, $type, $dev, $cat, $inst ) ;
    $self->_set_info_defaults
      ( $type, $dev, $cat, "0", $metacat{$cat}{instance}, %aux );
  }
}


######################################################################
# PRIVATE method
# build single instance info
#
# take the OID we are given and see if we get a response
# if we do, great; otherwise skip
#
sub _get_info_table {
  my( $self, %argv ) = @_ ;
  my( $type, $dev, $cat, $session ) ;
  $type = $argv{type} ;
  $dev = $argv{dev} ;
  $cat = $argv{cat} ;
  $session = $argv{session} ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  my( $inst, $table, $key, $oid, $count, %aux ) ;
  $count = $inst = "0" ;
  $table = $metacat{$cat}{table} ;
  $table =~ s/^\$// ;
  $key = $aliases{general}{$table} ;
  $oid = "$aliases{general}{$table}.$inst" ;
  my %results = $self->get_next_snmp_values( type => $type, dev => $dev,
					     cat => "general", var => $table,
					     session => $session ) ;
  if( scalar( keys %results ) ) {
    $self->debug( loglevel => "LOG_INFO",
		  message => "get_info_table: $type:$dev:$cat " 
		  . scalar( keys %results ) . " instances" ) ;
    $aux{mib} = $table;
    $aux{descr} = $self->_grab_descr( $session, $type, $dev, $cat ) ;
    $self->_set_info_defaults( $type, $dev, $cat, "0", "0", %aux ) ;
  }
}


######################################################################
# PRIVATE
# grab description for this instance
#
sub _grab_descr {
  my( $self, $session, $type, $dev, $cat, $inst ) = @_ ;
  my $descr ;
  #
  # if I have to fetch a value for descr, do it here
  if( $metacat{$cat}{descr} ) {
    $descr = $metacat{$cat}{descr} ;
    if( $descr =~ /^\$/ ) {
      $descr =~ s/^\$// ;
      if( $descr =~ /\.inst$/ ) {
	$descr =~ s/\.inst$//g ;
      }
      if( $aliases{general}{$descr} ) {
	my $o = $aliases{general}{$descr} ;
	my %res ;
	if( $metacat{$cat}{descr} =~ /^\$\w+\.inst$/ ) {
	  %res = $self->get_snmp_values( type => $type, dev => $dev,
					 cat => $cat, instance => $inst,
					 oids => [$o], session => $session );
	} else {
	  %res = $self->get_snmp_values( type => $type, dev => $dev,
					 cat => $cat, oids => [$o],
					 session => $session );
	}
	if( $res{$o} =~ /noSuchObject/io || $res{$o} =~ /noSuchInstance/io
	      || $res{$o} =~ /^\s*$/o || ! defined( $res{$o} ) ) {
	  $descr = "-" ;
	} else {
	  $descr = $res{$o} ;
	}
      } else {
	my $var = $metacat{$cat}{descr} ;
	$self->debug( loglevel => "LOG_WARNING",
		      message => "grab_descr: $cat descr $var undefined");
      }
    } else {
      $descr =~ s/\"//g ;
      ; # do nothing; it's just a string
    } 
  } else {
    $descr = "-"; 
  }
  return $descr ;
}


######################################################################
# PRIVATE method
# okay, get auxiliary info needed for this instance
#
sub _grab_aux_info {
  my( $self, $type, $dev, $cat, $inst, $session ) = @_ ;
  my( $response, %aux ) ;
  if( $metacat{$cat}{aux} ) {
    foreach my $var ( keys %{ $metacat{$cat}{aux} } ) {
      my $j = 0 ;
      $var =~ s/^\$// ;
      if( $var =~ /^\w+\.inst$/ ) {
	$var =~ s/\.inst$//g ;
	$j++ ;
      }
      my $o = $aliases{general}{$var} ;
      if( $j ) {
	$o .= ".$inst" ;
      }
      my %res = $self->get_snmp_values( type => $type, dev => $dev,
					cat => $cat, 
					session => $session, oids => [$o] );
      if( $res{$o} =~ /noSuchObject/io || $res{$o} =~ /noSuchInstance/io
	  || $res{$o} =~ /^\s*$/o || ! defined( $res{$o} ) ) {
	; # do nothing
      } else {
	$aux{$var} = $res{$o} ;
      }
    }
  }
  return %aux ;
}


######################################################################
# PRIVATE method
# okay, we've been given the parameters, 
#  figure out the final details here and set it up
#
sub _set_info_defaults {
  my( $self, $type, $dev, $cat, $key, $inst, %aux ) = @_ ;
  my $diff = 0 ; # incase this is a new instance
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
#  if( $cat eq "interface" 
#      && ( $key =~ /Loopback/io || $key =~ /Null/io  || $key =~ /^T1/io ) ) {
#    return ;
#  }
  if( defined( $metacat{$cat}{append} ) ) {
    $inst .= "$metacat{$cat}{append}" ;
  }
  unless( $targets{$type}{$dev}{$cat}{$key} ) {
    $diff = 1 ;
    $self->debug( loglevel => "LOG_NOTICE", 
		  message => "_set_info_defaults: "
		  . "$type:$dev:$cat:$key new/changed instance $inst" ) ;
  }
  unless( $inst eq "null" ) {
    $targets{$type}{$dev}{$cat}{$key}{instance} = $inst ;
  }
  $targets{$type}{$dev}{$cat}{$key}{valid} = 1 ;

  if( ! exists( $aux{ipAdEntIfIndex} ) ) {
    delete( $targets{$type}{$dev}{$cat}{$key}{ipaddress} ) ;
    delete( $targets{$type}{$dev}{$cat}{$key}{ipAdEntIfIndex} ) ;
    $diff = 1 ; # changed instance
  }

  if( %aux ) {
    while( my($u, $v) = each( %aux ) ) {
      next if ( $u eq "descr" ) ;
      if( $u =~ /^ifType$/io ) {
	$v = $ifType{$v} || $v ;
      } elsif( $u =~ /^ipAdEntIfIndex$/io && $cat eq "interface" ) {
	
	if( exists( $targets{$type}{$dev}{$cat}{$key}{ipaddress} ) ) {
	  unless( $v->{ $targets{$type}{$dev}{$cat}{$key}{ipaddress} } ) {
	    $diff = 1 ;
	    $targets{$type}{$dev}{$cat}{$key}{ipaddress} 
	      = (sort keys %{ $v } )[0] ;
	  }
	} else {
	  $diff = 1 ;
	  $targets{$type}{$dev}{$cat}{$key}{ipaddress} 
	    = (sort keys %{ $v } )[0] ;
	}
      } elsif( $u =~ /^ccarConfigRate$/io && $cat eq "car" ) {
	my $max = $v * 2 ;
	unless( $targets{$type}{$dev}{$cat}{$key}{ccarConfigRate} == $max ) {
	  ; #$self->tune_DS( type => $type, dev => $dev, 
	    #		  cat => $cat, inst => $key, max => $max ) ;
	}
      } elsif( $u =~ /^ifSpeed$/io && $cat eq "interface" ) {
	unless( $targets{$type}{$dev}{$cat}{$key}{ifSpeed} == $v ) { 
	  ; # $self->tune_DS( type => $type, dev => $dev, 
	    #		  cat => $cat, inst => $key, max => $v ) ;
	}
	# deal with highcounter crap
	unless( defined( $targets{$type}{$dev}{$cat}{$key}{highcounter} ) ) {
	  $targets{$type}{$dev}{$cat}{$key}{highcounter} = 
	    $self->_set_highcounter( $v, $ifType{$aux{ifType}}, 
				     $targets{$type}{$dev}{version} ) ;
	}
      } elsif( $u =~ /^ifAdminStatus$/io && $cat eq "interface" ) {
	# 1 == up; 2 == down
	if( $targets{$type}{$dev}{$cat}{$key}{ifAdminStatus} eq "up"
	    && $targets{$type}{$dev}{$cat}{$key}{collect} eq "yes" 
	    && $v == 2 ) {
	  $self->debug( loglevel => "LOG_WARNING",
			message => "_set_info_defaults: $type:$dev:$cat:$_: "
			. " setting collect = no (ifAdminStatus = down)" ) ;
	  $targets{$type}{$dev}{$cat}{$key}{collect} = "no" ;
	} elsif( $targets{$type}{$dev}{$cat}{$key}{ifAdminStatus} eq "down"
		 && $targets{$type}{$dev}{$cat}{$key}{collect} eq "no" 
		 && $v == 1 ) {
	  $self->debug( loglevel => "LOG_WARNING",
			message => "_set_info_defaults: $type:$dev:$cat:$_: "
			. " setting collect = yes " 
			. "(ifAdminStatus was down, now up)" ) ;
	  $targets{$type}{$dev}{$cat}{$key}{collect} = "no" ;
	}
	( $v == 1 ) ? ( $v = "up" ) : ( $v = "down" ) ;
      }
      $targets{$type}{$dev}{$cat}{$key}{$u} = $v ;
    }
  }
  # values admin can change...we setup defaults
  unless( defined($targets{$type}{$dev}{$cat}{$key}{collect}) ) {
    $targets{$type}{$dev}{$cat}{$key}{collect} = "yes" ;
  }
  unless( defined($targets{$type}{$dev}{$cat}{$key}{interval}) ) {
    $targets{$type}{$dev}{$cat}{$key}{interval} = $metacat{$cat}{interval} ;
  }
  unless( $targets{$type}{$dev}{$cat}{$key}{lockdescr} eq "yes" ) {
    if( $aux{descr} ) {
      $targets{$type}{$dev}{$cat}{$key}{descr} = $aux{descr} ;
    } else {
      my $j = $metacat{$cat}{descr} ;
      $j =~ s/\"//g ;
      $targets{$type}{$dev}{$cat}{$key}{descr} = $j ;
    }
      $targets{$type}{$dev}{$cat}{$key}{lockdescr} = "no" ;
    }
  if( $cat eq "interface" ) {
    unless( defined( $targets{$type}{$dev}{$cat}{$key}{mibs} ) ) {
      $targets{$type}{$dev}{$cat}{$key}{mibs} =
	join( ':', $self->get_mibs($type, $dev, $cat, $key ));
    }
  }
  if( $diff || ! exists( $targets{$type}{$dev}{$cat}{$key}{filename} ) ) {
    $targets{$type}{$dev}{$cat}{$key}{filename} = 
	$self->_set_dev_filename( $type, $dev, $cat, $key ) ;
  }
}


######################################################################
# PRIVATE method
# set stupid highcounter crap since nothing's consistent
#
sub _set_highcounter {
  my( $self, $speed, $type, $version ) = @_ ;
  my $hc = 0 ;
  if ( $version !~ /^SNMPv1$/io ) {
    if ( $speed > $self->{'_hclimit'} ) {
      $hc = 1 ;
    } elsif ( $speed == 0 && $type eq "propVirtual" ) {
      $hc = 1;
    } else {
      $hc = 0;
    }
  } else {
    $hc = 0 ;
  }
  return $hc ;
}


######################################################################
# build up info for all locales
#
sub build_alllocales {
  my( $self, $type ) = @_ ;
  my $cnt ;
  $type = "locale" ; # temporary
  $self->debug( loglevel => "LOG_DEBUG", 
		message => "Entering build_alllocales: $type" );
  my %targets = %{ $self->{targets} } if( $self->{targets} );
  unless( $type eq "locale" ) {
    $self->debug( loglevel => "LOG_WARNING",
		  message => "build_alllocales: unable to continue: " 
		  . "type != locale" ) ;
    $self->{'_error'} = "build_alllocales: type != locale";
    return 0;
  }
  $self->debug( loglevel => "LOG_DEBUG", 
		message => "build_alllocales: " 
		. "removing sources and dstotals");
  foreach ( keys %{ $targets{$type} } ) {
    delete( $targets{$type}{$_}{sources} ) ;
    delete( $targets{$type}{$_}{dstotal} ) ;
  }

  $self->debug( loglevel => "LOG_DEBUG", 
		message => "build_alllocales: building sources");
  my($t) = "device" ;
  while( my($dev,undef) = each(%{ $targets{$t} } ) ) {
    while( my($cat,undef) = each( %{ $targets{$t}{$dev} } ) ) {
      next unless( $aliases{$cat} ) ;
      next if ( $targets{$t}{$dev}{$cat} eq "yes" ) ;
      while( my($inst,undef) = each( %{ $targets{$t}{$dev}{$cat} } ) ) {
	if ( $targets{$t}{$dev}{$cat}{$inst}{"locale"} ) {
	  while(my($loc,undef) 
		= each ( %{$targets{$t}{$dev}{$cat}{$inst}{"locale"} } ) ) {
	    foreach( [ $t, $dev, $cat, $inst ] ) {
	      s/^\s*//g ; s/\s*$//g ;
	    }
	    $self->debug( loglevel => "LOG_INFO", 
			  message => "build_alllocales: " 
			  . "adding source $t;$dev;$cat;$inst to $loc");
	    $targets{$type}{$loc}{"sources"}{"$t;$dev;$cat;$inst"} = 1 ;
	  }
	}
      }
    }
  }
  $self->_clear_error ;
  while( my($loc, undef) = each( %{ $targets{$type} } ) ) {
    $self->_build_locale_info( $type, $loc ) ;
  }
  return 1;
}


######################################################################
# build info for a specific locale
#
sub build_locale {
  my( $self, $type, $locale ) = @_ ;
  my $cnt = 0 ;
  $self->debug( loglevel => "LOG_DEBUG",
		message => "Entering build_locale: $type:$locale" );
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  unless( $type eq "locale" ) {
    $self->debug( loglevel => "LOG_WARNING",  
		  message => "build_locale: type != locale" ) ;
    $self->{'_error'} = "build_locale: type != locale";
    return 0;
  }
  # clear out possible cruft....
  $self->debug( loglevel => "LOG_DEBUG", 
		message => "build_locale: removing sources and dstotals" );
  delete( $targets{$type}{$locale}{sources} ) ;
  delete( $targets{$type}{$locale}{dstotal} ) ;
  #
  # find all sources for this locale
  my($t) = "device" ;
  while( my($dev,undef) = each(%{ $targets{$t} } ) ) {
    while( my($cat,undef) = each( %{ $targets{$t}{$dev} } ) ) {
      next unless( $aliases{$cat} ) ;
      next if ( $targets{$t}{$dev}{$cat} eq "yes" ) ;
      while( my($inst,undef) = each( %{ $targets{$t}{$dev}{$cat} } ) ) {
	if ( $targets{$t}{$dev}{$cat}{$inst}{"locale"} ) {
	  while( my($loc,undef) 
		 = each( %{$targets{$t}{$dev}{$cat}{$inst}{"locale"} } ) ) {
	    foreach( [ $t, $dev, $cat, $inst ] ) {
	      s/^\s*//g ; s/\s*$//g ;
	    }
	    if ( $loc eq $locale ) {
	      $self->debug( loglevel => "LOG_INFO",  
			    message => "build_locale: " 
			    . "adding source $t;$dev;$cat;$inst to $loc");
	      $targets{$type}{$loc}{"sources"}{"$t;$dev;$cat;$inst"} = 1 ;
	    }
	  }
	}
      }
    }
  }
  unless( exists( $targets{$type}{$locale} ) ) {
    $self->debug( loglevel => "LOG_WARNING", 
		  message => "build_locale: unable to find $type:$locale" );
    $self->{'_error'} = "_build_locale_info: unable to find $type:$locale" ;
    return 0;
  }
  $self->_clear_error ;
  $self->_build_locale_info( $type, $locale ) ;
  return 1;
}


######################################################################
# PRIVATE method -- stay out
# this sets up all the details for a given locale
#
sub _build_locale_info {
  my( $self, $type, $locale ) = @_ ;
  my $cnt = 0 ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  $targets{$type}{$locale}{valid} = 1 ;
  unless( defined( $targets{$type}{$locale}{collect} ) ) {
    $targets{$type}{$locale}{collect} = "yes" ;
  }
  unless( defined( $targets{$type}{$locale}{filename} ) ) {
    $targets{$type}{$locale}{filename} = "locales/locale-$locale.rrd" ;
  }
  unless( defined( $targets{$type}{$locale}{descr} ) ) {
    $targets{$type}{$locale}{descr} = "Locale $locale" ;
  }
  ##############################################
  # set the interval; this has to be as large as the instance with 
  # the largest step value
  $self->debug( loglevel => "LOG_INFO", 
		message => "_build_locale_info: $type:$locale: " 
		. "setting interval" );
  while( my($src,undef) = each( %{ $targets{$type}{$locale}{sources} } ) ) {
    my($t, $d, $c, $i) = split( /;/, $src ) ;
    my $dstep ;
    if( defined( $targets{$t}{$d}{$c}{$i}{step} ) ) {
      $dstep = $targets{$t}{$d}{$c}{$i}{step} ;
    } else {
      if ( $targets{$t}{$d}{$c}{$i}{interval} % 5 == 0 ) {
	$dstep = $targets{$t}{$d}{$c}{$i}{interval} ;
      }
      else {
	$dstep = 5 ;
      }
    }
    # if dstep is greater than current interval, update interval
    if( $dstep > $targets{$type}{$locale}{interval} ) {
      $targets{$type}{$locale}{interval} = $dstep ;
    }
  }
  ##############################################
  # go through each source and build up the dstotal table
  #  the amount of times a specific variable should be collected over
  #  the locale's interval
  $self->debug( loglevel => "LOG_INFO", 
		message => "_build_locale_info: $type:$locale: " 
		. "building dstotals" );
  while( my($src,undef) = each( %{ $targets{$type}{$locale}{sources} } ) ) {
    my( %vars, $int ) ;
    my($t, $d, $c, $i) = split( /;/, $src ) ;
    ############################################
    # determine # times a DS is to be collected from this source over
    #   the locale's interval
    # the '5' in the next line is temporary ...
    # until every instance has 'step'
    if( defined( $targets{$t}{$d}{$c}{$i}{step} ) ) {
      $int = $targets{$t}{$d}{$c}{$i}{step} ;
    } else {
      if( $targets{$t}{$d}{$c}{$i}{interval} % 5 == 0 ) {
	$int = $targets{$t}{$d}{$c}{$i}{interval} ;
      }
      else {
	$int = 5 ;
      }
    }
    ############################################
    # get the floor
    $int = sprintf( "%d", $targets{$type}{$locale}{interval} / $int ) ;
    if( $c eq "interface" ) {
      unless( exists( $targets{$t}{$d}{$c}{$i}{mibs} ) ) {
	$targets{$t}{$d}{$c}{$i}{mibs} 
	  = join( ':', $self->get_mibs($t,$d,$c,$i) ) ;
      }
      foreach( split( /:/, $targets{$t}{$d}{$c}{$i}{mibs} ) ) {
	$vars{$_} = 1 ;
      }
    } else {
      foreach my $ds ( $self->get_mibs($t,$d,$c,$i) ) {
	$vars{$ds} = 1 ;
      }
    }
    ############################################
    # okay, now build up dstotals...
    foreach ( keys %localevars ) {
      next if( $targets{$t}{$d}{$c}{$i}{locale}{$locale}{ignore}{$_} ) ;
      if( defined( $_ ) && exists( $vars{$_} ) ) {
	if( $targets{$t}{$d}{$c}{$i}{locale}{$locale}{invert} ) {
	  if( /In[A-Z]/ ) {
	    s/In/Out/g ;
	  } elsif( /Out[A-Z]/ ) {
	    s/Out/In/g ;
	  }
	}
	if( $localevars{$_}{interval} eq "each" ) {
	  $targets{$type}{$locale}{dstotal}{$_} += $int ;
	  # $targets{$t}{$d}{$c}{$i}{locale}{$locale}{dstotal} = $int;
	} elsif( $localevars{$_}{interval} eq "single" ) {
	  $targets{$type}{$locale}{dstotal}{$_} += 1 ;
	  # $targets{$t}{$d}{$c}{$i}{locale}{$locale}{dstotal} = 1;
	} else {
	  $targets{$type}{$locale}{dstotal}{$_} += $int ;
	  # $targets{$t}{$d}{$c}{$i}{locale}{$locale}{dstotal} = 1;
	}
      }
    }
  }
}


sub get_sysUpTime {
  my( $self, $type, $device ) = @_ ;
  my $time ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  unless( exists( $targets{$type}{$device} ) && $type eq "device" ) { 
    $self->debug( loglevel => "LOG_ERR", 
		  message => "FAILURE: get_sysUpTime: $type:$device " 
		  . "does not exist" ) ;
    $self->{'_error'} = "get_sysUpTime: $type:$device does not exist" ;
    return 0 ;
  }
  $time = $self->_sysUpTime( $type, $device ) ;
  $self->debug( loglevel => "LOG_DEBUG",
		message => " ---> time $time " ) ;
  $self->_clear_error ;
  return $time ;
}


sub set_sysUpTime {
  my( $self, $type, $device ) = @_ ;
  my $time ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  unless( exists( $targets{$type}{$device} ) && $type eq "device" ) { 
    $self->debug( loglevel => "LOG_ERR", 
		  message => "FAILURE: set_sysUpTime: $type:$device " 
		  . "does not exist" ) ;
    $self->{'_error'} = "set_sysUpTime: $type:$device does not exist" ;
    return 0 ;
  }
  $time = $self->_sysUpTime( $type, $device ) ;
  $targets{$type}{ $device }{ "sysUpTime$self->{'_interval'}" } = $time ;
  $targets{$type}{ $device }{ "sysUpTime" } = $time ;
  $self->_clear_error ;
  return 1;
}


#=======================================
# PRIVATE method
#
# does the work for both get_sysUpTime and set_sysUpTime
#=======================================
sub _sysUpTime {
  my( $self, $type, $device ) = @_ ;
  my( $host, $session, $error, $response, $timeout, $retries, 
      $comstr, $version, $time ) ;
  my %targets = %{ $self->{targets} } if( $self->{targets} ) ;
  
  $self->debug( loglevel => "LOG_DEBUG", 
		message => "_sysUpTime: creating session to $type:$device");
  ($session, $error) = $self->open_snmp_session( $type, $device ) ;
  $self->debug( loglevel => "LOG_DEBUG",
		message => " ---> $aliases{general}{sysUpTime}" ) ;
  if ( defined( $session ) ) {
    $session->translate( 0 ) ;
    my %res = $self->get_snmp_values( type => $type, dev => $device,
				      oids => [$aliases{general}{sysUpTime}],
				      session => $session ) ;
    if( defined( $res{ $aliases{general}{sysUpTime} } ) ) {
      if( $targets{$type}{$device}{retries} == 0 ) {
	$self->debug( loglevel => "LOG_WARNING", 
		      message => "_sysUpTime: $type:$device: " 
		      . "setting retries to $self->{'_retries'}" ) ;
	$targets{$type}{$device}{retries} = $self->{'_retries'} ;
	}
      $time = $res{ $aliases{general}{sysUpTime} } ;
    } else {
      $self->debug( loglevel => "LOG_ERR", 
		    message => "FAILURE: _sysUpTime: " 
		    . "Unable to get sysUpTime from $type:$device" ) ;
      unless( $targets{$type}{$device}{retries} == 0 ) {
	$self->debug( loglevel => "LOG_WARNING", 
		      message => "NetViewer._sysUpTime: " 
		      . "$type:$device: setting retries to 0" ) ;
	$targets{$type}{$device}{retries} = 0 ;
      }
      $time = -1 ;
    }
    $self->close_snmp_session( $session ) ;
  } else {
    $self->debug( loglevel => "LOG_ERR", 
		  message => "FAILURE: _sysUpTime: " 
		  . "Unable to get session with $type:$device: $error" ) ;
  }
  return $time ;
}







##########################################################################
# $Log: Netviewer.pm,v $
# Revision 1.7  2003/07/03 22:44:05  netdot
# commenting out skip over loopback and other reserved IFs.
#
# Revision 1.6  2003/06/12 23:27:23  netdot
# added get_device; fixed grab_aux_info; other stuff....
#
# Revision 1.5  2003/06/12 00:51:39  netdot
# changes to get_sysinfo
#
# Revision 1.4  2003/06/11 22:44:10  netdot
# more work to migrate
#
# Revision 1.3  2003/06/11 00:10:25  netdot
# modified read_globals; still working on schema
#
# Revision 1.2  2003/06/10 00:10:54  netdot
# forked from NetViewer (see VERSION for when).  trimming out
# unnecessary functions and will move config stuff into DB.
#
# Revision 1.1  2003/06/09 23:37:55  netdot
# Initial revision
#


__DATA__

##########################################################################
#=========================================================================
# POD formatted documentation for perl module NetViewer.pm
# get values from a device and load into an RRD
#=========================================================================
##########################################################################

=head1 NAME

NetViewer - Tool For Managing Network Information

=head1 SYNOPSIS

NetViewer is a tool for gathering data from network devices and
storing the data using RRDTool.  It provides ways to maintain data
regarding the devices you collect data on, present the data in a graph
(via RRDTool's graph command), verify the data before presenting it to
RRDTool, and consolidate and aggregate the data in ways that go beyond
just interfaces on a device.  You can also configure it to preserve
state information to be used by other applications.  This library
provides the necessary support that other applications can hook into.
NetViewer maintains an in-memory data structure that contains this
state information.  Technically, it is a hash of hashses.
Conceptually, it is a tree-like data structure.  This hash is called
%targets and I will occasionally refer to it in the documentation
below.

As this project is under development, documentation is still missing in
parts.  This documentation is meant to fill the gap regarding the
available functions when using this library.

=head1 METHODS

Most methods associated with a NetViewer object take very similar arguments.
There are also a few class methods that do not need to be called in the
context of a NetViewer object.  If you are not familiar with Perl objects, 
the general style for calling a method is:

    $object->method( arg1, arg2, arg3 ) ;

=head2 new - create a new NetViewer object

  $nv = NetViewer->new( 
		 ['datadir'        => $datadir,]
		 ['imgdir'         => $imgdir,]
		 ['rrdbindir'      => $rrdbindir,]
		 ['global'         => $global,]
		 ['conf'           => $conf,]
		 ['store'          => $store,]
		 ['cat'            => $cat,]
		 ['types'          => $types,]
		 ['locale'         => $locale,]
		 ['defaultcollect' => $collect,]
		 ['alwaysfetch'    => $alwaysfetch,]
		 ['interval'       => $interval,]
		 ['hclimit'        => $hclimit,]
		 ['carlimit'       => $carlimit,]
		 ['vlanspeed'      => $vlanspeed,]
		 ['umask'          => $umask,]
		 ['xff'            => $xff,]
		 ['timeout'        => $timeout,]
		 ['retries'        => $retries,]
		 ['snmpversion'    => $snmpversion,]
		 ['community'      => $community,]
		 ['foreground'     => $foreground,]
                 ['logfacility'    => $logfacility,]
                 ['loglevel'       => $loglevel] 
                ) ;

This is the constructor for NetViewer objects.  As you see, it takes a number 
of arguments.  Much of this can be set in netviewer.conf.  The first few 
variables tell NetViewer where to expect certain files.  All arguments are 
optional; the defaults are provided when the corresponding arguments are 
supplied.

