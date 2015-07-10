package Netdot;

use strict;
use warnings;

use Netdot::Meta;
use Netdot::Config;
use Netdot::Util::Log;
use Netdot::Util::Exception;
use Netdot::Util::DNS;
use Carp;
use RRDs;
use Data::Dumper;
use Digest::SHA qw(sha256_base64);

# Some useful patterns used througout
my $IPV4 = '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}';
my $IPV4CIDR = '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?:\/\d{1,2})?$';
my $HD   = '[0-9A-Fa-f]{1,4}'; # Hexadecimal digits, 2 bytes
my $V6P1 = "(?:$HD:){7}$HD";
my $V6P2 = "(?:$HD(?:\:$HD){0,6})?::(?:$HD(?:\:$HD){0,6})?";
my $IPV6 = "$V6P1|$V6P2"; # Note: Not strictly a valid V6 address
my $HOCT = '[0-9A-Fa-f]{2}';
my $MAC  = "$HOCT\[.:-\]?$HOCT\[.:-\]?$HOCT\[.:-\]?$HOCT\[.:-\]?$HOCT\[.:-\]?$HOCT";
    
my $class = {};
$class->{_config} = Netdot::Config->new();
$class->{_meta}   = Netdot::Meta->new();
$class->{_log}    = Netdot::Util::Log->new(config => $class->{_config}->get('LOG_OPTIONS'));
$class->{_dns}    = Netdot::Util::DNS->new();

# Memory cache data
$class->{_cache_data} = {};

# Be sure to return 1
1;

=head1 NAME

Netdot - Network Documentation Tool

=head1 VERSION

Version 1.1.0

=cut

our $VERSION = "1.1.0";

=head1 SYNOPSIS

This module groups common functions used by Netdot\'s classes.
    
=head1 METHODS

############################################################################

=head2 meta - Get Netdot::Meta object

=cut

sub meta   { return $class->{_meta}  }

############################################################################

=head2 config - Get Netdot::Config object
=cut

sub config { return $class->{_config} }

############################################################################

=head2 log - Get Netdot::Util::Log object
=cut

sub log { return $class->{_log} }

############################################################################

=head2 dns - Get Netdot::Util::DNS object
=cut

sub dns { return $class->{_dns} }

############################################################################

=head2 throw_user - Throw a user exception
=cut

sub throw_user {
    my ($self, $msg) = @_;
    my $logger = $class->{_log}->get_logger('Netdot');
    $logger->error($msg);
    return Netdot::Util::Exception::User->throw(message=>$msg);
}

############################################################################

=head2 throw_fatal - Throw a fatal exception
=cut

sub throw_fatal {
    my ($self, $msg) = @_;
    my $logger = $class->{_log}->get_logger('Netdot');
    $logger->fatal($msg);
    return Netdot::Util::Exception::Fatal->throw(message=>$msg);
}

############################################################################

=head2 throw_rest - Throw a REST exception
=cut

sub throw_rest {
    my ($self, %argv) = @_;
    my $logger = $class->{_log}->get_logger('Netdot');
    $logger->error($argv{msg});
    return Netdot::Util::Exception::REST->throw(code=>$argv{code}, message=>$argv{msg});
}

############################################################################

=head2 isa_class_method - Make sure that method is being called as class
=cut

sub isa_class_method {
    my ($class, $method) = @_;
    if ( my $classname = ref($class) ){
	__PACKAGE__->throw_fatal("Invalid object method call to ".$classname."::".$method);
    }
    return 1;
}

############################################################################

=head2 isa_object_method - Make sure that method is being called as object
=cut

sub isa_object_method {
    my ($self, $method) = @_;
    __PACKAGE__->throw_fatal("Invalid class method call to ".$self."::".$method)
	unless ref($self);
    return 1;
}

############################################################################

=head2 isa_netdot_exception - Test if exception is a Netdot exception
=cut

sub isa_netdot_exception {
    my $self = shift;
    return Netdot::Util::Exception->isa_netdot_exception(@_);
}

############################################################################

=head2 Dump - Show a data structure using Data::Dumper
=cut

sub Dump { return Dumper(@_) };

############################################################################

=head2 get_ipv4_regex - Return IPv4 regular expression
=cut

sub get_ipv4_regex { return $IPV4 }

############################################################################

=head2 get_ipv6_regex - Return IPv6 regular expression
=cut

sub get_ipv6_regex { return $IPV6 }

############################################################################

=head2 get_mac_regex - Return Ethernet MAC regular expression
=cut

sub get_mac_regex { return $MAC }

######################################################################

=head2 ttl_from_text - Convert string DNS record TTL into integer value
	
  Arguments: 
    DNS record TTL string
  Returns:
    integer
  Example:
    $ttl = Netdot->ttl_from_text($ttl_string)
=cut

sub ttl_from_text {
    my ($self, $t) = @_;

    $t = $self->rem_lt_sp($t);

    my $MAXIMUM_TTL = 0x7fffffff;
    my $res = 0;
    if ( $t =~ /^\d+$/ ){
	$res = $t;
    }elsif ( $t =~ /^(?:\d+[WDHMS])+$/i ){
	my %ttl;
	$ttl{W} ||= 0;
	$ttl{D} ||= 0;
	$ttl{H} ||= 0;
	$ttl{M} ||= 0;
	$ttl{S} ||= 0;
	while ($t =~ /(\d+)([WDHMS])/gi) {
	    $ttl{uc($2)} += $1;
	}
	$res = $ttl{S} + 60*($ttl{M} + 60*($ttl{H} + 24*($ttl{D} + 7*$ttl{W})));
    }else{
	$self->throw_user("Bad TTL format: '$t'");
    }
    
    if ($res < 0 || $res > $MAXIMUM_TTL) {
	$self->throw_user("Bad TTL value: $res.  TTL must be within 0 and $MAXIMUM_TTL");
    }
    return $res;
}

######################################################################

=head2 sec2dhms - Translate seconds into days, minutes, hours, seconds
	
   Arguments: 
     Integer (seconds)
   Returns:
    String like "0:0:41:40"
   Example:
    print Netdot->sec2dhms($seconds);
=cut   

sub sec2dhms {
    my ($self, $seconds) = @_;
    my @parts = gmtime($seconds);
    my @l;
    push @l, sprintf("%d days",  $parts[7]) if ( $parts[7] ); 
    push @l, sprintf("%d hours", $parts[2]) if ( $parts[2] ); 
    push @l, sprintf("%d min",   $parts[1]) if ( $parts[1] ); 
    push @l, sprintf("%d sec",   $parts[0]);
    my $string = join ', ', @l;
    return $string;
}

######################################################################

=head2 send_mail - Send mail to desired destination

    Useful to e-mail output from automatic processes

    Arguments (hash):
    - to      : destination email (defaults to NOCEMAIL from config file)
    - from    : orignin email (defaults to ADMINEMAIL from config file)
    - subject : subject of message
    - body    : body of message

    Returns true/false for success/failure

=cut

sub send_mail {
    my ($self, %args) = @_;
    my ($to, $from, $subject, $body) = 	@args{'to', 'from', 'subject', 'body'};
    
    my $SENDMAIL = $self->config->get('SENDMAIL');
    
    $to    ||= $self->config->get('NOCEMAIL');
    $from  ||= $self->config->get('ADMINEMAIL');
    
    if ( !open(SENDMAIL, "|$SENDMAIL -oi -t") ){
        $self->throw_fatal("send_mail: Can't fork for $SENDMAIL: $!");
    }

    print SENDMAIL <<EOF;
From: $from
To: $to
Subject: $subject
    
$body
    
EOF

close(SENDMAIL);
    return 1;

}

######################################################################

=head2 rem_lt_sp - Remove leading and trailing space from string
	
   Arguments: 
    string
   Returns:
    string
   Example:
    $str = $self->rem_lt_sp($str);
=cut   

sub rem_lt_sp {
    my ($self, $str) = @_;
    return unless $str;
    my $old = $str;
    $str =~ s/^\s+//o;
    $str =~ s/\s+$//o;
    return $str;
}

######################################################################

=head2 is_ascii - Determine if value is ascii only

    If value has non-ascii characters, returns 0
	
   Arguments: 
    string
   Returns:
    1 or 0
   Example:
    if $self->is_ascii($str);
=cut   

sub is_ascii {
    my ($self, $v) = @_;
    return unless $v;
    return 0 if ( $v =~ /[^[:ascii:]]/o );
    return 1;
}

######################################################################

=head2 sha_digest - SHA-256 base64-encoded digest of given string
	
   Arguments: 
    string
   Returns:
    digest string
   Example:
    my $sha = Netdot->sha_digest($string);
=cut   

sub sha_digest {
    my ($self, $str) = @_;
    return sha256_base64($str)
}


############################################################################

=head2 cache - Get or set memory data cache

    Values time out after $_cache_timeout seconds

  Arguments:
    cache key    unique key to identify the data
    cache data   Required for set
    timeout      defaults to 60 seconds
  Returns:
    cache data or undef if timed out
  Examples:
    my $graph = $self->_cache('graph');
    $self->_cache('graph', $data);

=cut

sub cache {
    my ($self, $key, $data, $timeout) = @_;

    $self->throw_fatal("Missing required argument: key")
	unless $key;

    $timeout ||= 60;

    if ( defined $data ){
	$class->{_cache_data}{$key}{data} = $data;
	$class->{_cache_data}{$key}{time} = time;
    }
    if ( exists $class->{_cache_data}{$key}{time} && 
	 (time - $class->{_cache_data}{$key}{time} > $timeout) ){
	return;
    }else{
	return $class->{_cache_data}{$key}{data};
    }
}


=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 BUGS

Please report any bugs or feature requests to
C<netdot-devel at ns.uoregon.edu>, or through the web interface at
L<http://netdot.uoregon.edu>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Netdot

You can also use the mailing lists:

=over 

=item L<netdot-users|https://osl.uoregon.edu/mailman/listinfo/netdot-users>

=item L<netdot-devel|https://osl.uoregon.edu/mailman/listinfo/netdot-devel>

=back

=head1 ACKNOWLEDGEMENTS

The Network & Telecom Services group at the University of Oregon and 
multiple other contributors.

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
