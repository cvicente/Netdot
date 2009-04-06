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
         [ -z|--zones <zone1,zone2...> ]
         [ -n|--nopriv ]
    
    Available types:  Nagios, Sysmon, Rancid, BIND

    BIND exporter Options:
       zones  - Comma-separated list of zone names, or the word 'all'
       nopriv - Exclude private data from zone file (TXT and HINFO)

EOF
    
my %self;

# handle cmdline args
my $result = GetOptions( 
    "t|types=s"       => \$self{types},
    "z|zones=s"       => \$self{zones},
    "n|nopriv"        => \$self{nopriv},
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

foreach my $type ( split ',', $self{types} ){
    $type =~ s/\s+//g;
    my $exporter = Netdot::Exporter->new(type=>$type);
    if ( $type eq 'BIND' ){
	unless ( $self{zones} ){
	    print $USAGE;
	    die "Missing required argument 'zones' for BIND export";
	}
	my @zones = split ',', $self{zones};
	if ( scalar(@zones) == 1 && $zones[0] eq 'all' ){
	    $exporter->generate_configs(all=>1);
	}else{
	    $exporter->generate_configs(zones=>\@zones, nopriv=>$self{nopriv});
	}
    }else{
	$exporter->generate_configs();
    }
}
