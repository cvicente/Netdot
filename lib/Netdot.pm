package Netdot;

use lib "PREFIX/lib";
use Debug;

#Be sure to return 1
1;

########################################

=head1 NAME

Netdot - Network Documentation Tool

=head1 SYNOPSIS

=cut

=head1 METHODS
=cut


sub _read_defaults {
    my $self = shift;
    my @files = qw( PREFIX/etc/Default.conf PREFIX/etc/Site.conf);
    foreach my $file (@files){
	open (IN, $file) 
	    or die "Netdot.pm: Could not open file $file for reading: $!";
	while (<IN>){
	    next if (/^\#/);
	    s/^(.*)\#.*$/$1/;  # Discard anything after the #
	    my ($name, $value) = /^(\w+)\s+(.*)$/;
	    $value =~ s/^\s*(.*)\s*/$1/;
	    $self->{$name} = $value;
	}
	close (IN);
    }
}

=head2 new

=cut

sub new {
   my ($proto, %argv) = @_;
   my $class = ref( $proto ) || $proto;
   my $self = {};
   bless $self, $class;

   $self->_read_defaults;

   $self->{'_logfacility'} = $argv{'logfacility'} || $self->{'DEFAULT_LOGFACILITY'},
   $self->{'_loglevel'}    = $argv{'loglevel'}    || $self->{'DEFAULT_LOGLEVEL'},
   $self->{'_logident'}    = $argv{'logident'}    || $self->{'DEFAULT_SYSLOGIDENT'},   
   $self->{'_foreground'}  = $argv{'foreground'}  || 0,   
   
   $self->{debug} = Debug->new(logfacility => $self->{'_logfacility'}, 
			       loglevel => $self->{'_loglevel'},	  
			       logident => $self->{'_logident'},
			       foreground => $self->{'_foreground'},
			       );

   wantarray ? ( $self, '' ) : $self;
}


######################################################################
# STUFF for Debug.pm
######################################################################

=head2 set_loglevel - set Netdot's loglevel

   $netdot->set_loglevel( "loglevel" );

Debug messages at loglevel $loglevel or above are sent to syslog; they are
otherwise dropped.  You can use this method to change NetViewer's loglevel.
The argument is expected in the form "LOG_INFO" or "LOG_EMERG" and so on.  See
the man page for syslog for further examples.

=cut

sub set_loglevel {
  my $self = shift;
  return $self->{debug}->set_loglevel( @_ );
}

=head2 debug - send a debug message

 $netdot->debug( message => "trouble at the old mill" );

This is a frontend to the debug method in Debug.pm.

=cut

sub debug {
  my $self = shift;
  return $self->{debug}->debug( @_ );
}



######################################################################
# stuff for error messages/strings
######################################################################


=head2 error - set/return an error message.
    
    $netdot->error("Run for your lives!");

or
    
    print $netdot->error . "\n";

=cut


sub error {
    my $self = shift;
    if (@_) { $self->{'_error'} = shift }
    return $self->{'_error'};
}



