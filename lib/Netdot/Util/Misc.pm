package Netdot::Util::Misc;

use base 'Netdot::Util';
use warnings;
use strict;
use Socket;

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

1;
