#!<<Make:PERL>>
#
#
use strict;
use lib "<<Make:LIB>>";
use Netdot::Exporter;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;

my $USAGE = <<EOF;
 usage: $0 -t "<Type1, Type2...>"
    
    Available types:
      Nagios
      Sysmon
      Rancid

EOF
    
my %self;

# handle cmdline args
my $result = GetOptions( 
    "t|types=s"       => \$self{types},
    "h|help"          => \$self{help},
    "d|debug"         => \$self{debug},
    );

if ( !$result ) {
    print $USAGE;
    die "Error: Problem with cmdline args\n";
}
if ( $self{help} ) {
    print $USAGE;
    exit;
}

defined $self{types} || die "Error: Missing required argument: types (-t)\n";

my $logger = Netdot->log->get_logger('Netdot::Exporter');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);

# Notice that $DEBUG is imported from Log::Log4perl
$logger->level($DEBUG) 
    if ( $self{debug} ); 

# Here's the beauty of OO  :-)
foreach my $type ( split ',', $self{types} ){
    $type =~ s/\s+//g;
    my $exporter = Netdot::Exporter->new(type=>$type);
    $exporter->generate_configs();
}
