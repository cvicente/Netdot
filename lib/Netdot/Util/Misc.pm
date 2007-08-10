package Netdot::Util::Misc;

use base 'Netdot::Util';
use warnings;
use strict;
use Socket;

1;
=head1 NAME

Netdot::Util::Misc - Miscellaneous utilities

=head1 SYNOPSIS


=head1 CLASS METHODS
=cut


############################################################################
=head2 new - Class constructor

  Arguments:
    None
  Returns:
    Netdot::Util::Misc object
  Examples:
    my $misc = Netdot::Util::Misc->new();
=cut
sub new{
    my ($proto, %argv) = @_;
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{_logger} = Netdot->log->get_logger('Netdot::Util');
    bless $self, $class;
}

######################################################################
=head2 empty_space - Returns empty space
	
  Arguments:
    none

=cut
sub empty_space {
	my ($self, $x) = @_;
	return " ";
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
    
    my $SENDMAIL = Netdot->config->get('SENDMAIL');
    
    $to    ||= Netdot->config->get('NOCEMAIL');
    $from  ||= Netdot->config->get('ADMINEMAIL');
    
    if ( !open(SENDMAIL, "|$SENDMAIL -oi -t") ){
        Netdot->throw_fatal("send_mail: Can't fork for $SENDMAIL: $!");
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

=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >> with contributions from Nathan Collins and Aaron Parecki.

=head1 COPYRIGHT & LICENSE

Copyright 2006 University of Oregon, all rights reserved.

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

