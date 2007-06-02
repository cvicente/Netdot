package Netdot::Util::Misc;

######################################################################
# Miscellaneous methods
######################################################################

=head2 empty_space
	
	Returns empty space
	
	Arguments:
		none
=cut
sub empty_space {
	my ($self, $x) = @_;
	return " ";
}


=head2 send_mail

    Sends mail to desired destination.  
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
    my ($to, $from, $subject, $body) = 	
	($args{to}, $args{from}, $args{subject}, $args{body});
 
    my $SENDMAIL = $self->{config}->{'SENDMAIL'};

    $to    ||= $self->{config}->{'NOCEMAIL'};
    $from  ||= $self->{config}->{'ADMINEMAIL'};

    if ( !open(SENDMAIL, "|$SENDMAIL -oi -t") ){
        $self->error("send_mail: Can't fork for $SENDMAIL: $!");
        return 0;
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
