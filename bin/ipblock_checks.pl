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
 usage: $0  -u|--unused  -m|--maxed
           [-m|--send_mail] [-f|--from] | [-t|--to] | [-S|--subject]

    
    -u, --unused       report unused subnets
    -m, --maxed        report maxed-out subnets
    -4, --v4-only      IPv4 subnets only
    -6, --v6-only      IPv6 subnets only
    -s, --send_mail    send output via e-mail
    -f, --from         e-mail From line (default: $self{FROM})
    -S, --subject      e-mail Subject line (default: $self{SUBJECT})
    -t, --to           e-mail To line (default: $self{TO})
    -h, --help         show this message
    
EOF
    
# handle cmdline args
my $result = GetOptions( "u|unused"       => \$self{UNUSED},
			 "m|maxed"        => \$self{MAXED},
			 "4|v4-only"      => \$self{4},
			 "6|v6-only"      => \$self{6},
			 "h|help"         => \$self{HELP},
			 "s|send_mail"    => \$self{EMAIL},
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
unless ( $self{UNUSED} || $self{MAXED} ){
    print $usage;
    die "Missing either -u or -m\n";
}

my %args;
if ( $self{4} ){
    $args{version} = 4;
}elsif ( $self{6} ){
    $args{version} = 6;
}

if ( $self{UNUSED} ){
    my @unused = Ipblock->get_unused_subnets(%args);
    
    if ( @unused ){
	$output = "\nThe following Subnets appear to be unused:\n\n";
	foreach my $subnet ( @unused ){
	    $output .= "  " . $subnet->get_label() . "\n";
	}
    }
}

if ( $self{MAXED} ){
    my $threshold = Netdot->config->get('SUBNET_USAGE_MINPERCENT');
    my @maxed = Ipblock->get_maxed_out_subnets(%args);
    
    if ( @maxed ){
	$output .= "\n\nThe following Subnets are below $threshold% free:\n\n";
	foreach my $pair ( @maxed ){
	    my ($subnet, $percent_free) = @$pair;
	    my $percent_free = sprintf("%.2f", $percent_free);
	    $output .= "  " . $subnet->get_label() . " Avail: " . $percent_free . "%\n";
	}
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
