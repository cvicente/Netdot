#!<<Make:PERL>>
#
# Ipblock checks
#
use lib "<<Make:LIB>>";
use Netdot::Model;
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;

my %self;

$self{FROM}    = Netdot->config->get('ADMINEMAIL');
$self{TO}      = Netdot->config->get('NOCEMAIL');
$self{SUBJECT} = 'Netdot IP Checks';
my $output;

my $usage = <<EOF;
 usage: $0  -u |--unused
           [-m|--send_mail] [-f|--from] | [-t|--to] | [-S|--subject]

    
    -u, --unused       report unused subnets
    -4, --v4-only      IPv4 subnets only
    -6, --v6-only      IPv6 subnets only
    -m, --send_mail    send output via e-mail
    -f, --from         e-mail From line (default: $self{FROM})
    -S, --subject      e-mail Subject line (default: $self{SUBJECT})
    -t, --to           e-mail To line (default: $self{TO})
    -h, --help         show this message
    
EOF
    
# handle cmdline args
my $result = GetOptions( "u|unused"       => \$self{UNUSED},
			 "4|v4-only"      => \$self{4},
			 "6|v6-only"      => \$self{6},
			 "h|help"         => \$self{HELP},
			 "m|send_mail"    => \$self{EMAIL},
			 "f|from:s"       => \$self{FROM},
			 "t|to:s"         => \$self{TO},
			 "S|subject:s"    => \$self{SUBJECT},
			 );

if( ! $result ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if( $self{HELP} ) {
    print $usage;
    exit;
}
unless ( $self{UNUSED} ){
    print $usage;
}
###############################################################################

my @unused = Ipblock->get_unused_subnets();
if ( @unused ){
    $output = "\nThe following Subnets appear to be unused:\n\n";
    foreach my $subnet ( @unused ){
	if ( $self{4} && $subnet->version ne "4" ){
	    next;
	}
	$output .= "  " . $subnet->get_label() . "\n";
    }
}

if ( $self{EMAIL} && $output ){
    Netdot->send_mail(from    => $self{FROM},
		      to      => $self{TO},
		      subject => $self{SUBJECT}, 
		      body    => $output,
	);
}else{
    print STDOUT $output, "\n" if $output;
}
