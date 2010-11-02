#!<<Make:PERL>>
#
# Import ISC BIND zonefiles into Netdot
#
use lib "<<Make:LIB>>";
use Netdot::Model;
use Net::DNS::ZoneFile::Fast;
use Getopt::Long qw(:config no_ignore_case bundling);
use BIND::Config::Parser;
use strict;
use Data::Dumper;
use Log::Log4perl::Level;

my %self;
my $usage = <<EOF;
 usage: $0 
    [ -n|domain <name>, -f|file <path> ] (for single zone)
    [ -c|config <path>, -d|dir <path>  ] (for multiple zones)
    [ -g|--debug ] [-h|--help]
    
    -c  --config <path>      Bind config file containing zone definitions
    -d, --dir <path>         Directory where zone files are found

    -n, --domain <name>      Domain or Zone name
    -f, --zonefile <path>    Zone file

    -w, --wipe               Wipe out existing zone data
    -g, --debug              Print debugging output
    -h, --help               Print help
    
EOF
    
# handle cmdline args
my $result = GetOptions( 
    "c|config=s"      => \$self{config},
    "d|dir=s"         => \$self{dir},
    "n|domain=s"      => \$self{domain},
    "f|zonefile=s"    => \$self{zonefile},
    "w|wipe"          => \$self{wipe},
    "h|help"          => \$self{help},
    "g|debug"         => \$self{debug},
    );

if ( $self{help} ) {
    print $usage;
    exit;
}

# Add a log appender 
my $logger = Netdot->log->get_logger('Netdot::Model::DNS');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);
$logger->level($DEBUG) if ( $self{debug} ); # Notice that $DEBUG is imported from Log::Log4perl

my %netdot_zones;
foreach my $z ( Netdot::Model::Zone->retrieve_all ){
    $netdot_zones{$z->name} = $z;
}

if ( $self{domain} && $self{zonefile} ){

    &import_zone($self{zonefile}, $self{domain});

}elsif ( $self{dir} && $self{config} ){

    my %zones_by_name;
    &read_config($self{config}, \%zones_by_name);

    # For domains using the same zone file
    my %zones_by_file;
    while ( my($zone, $file) = each %zones_by_name ){
	push @{$zones_by_file{$file}}, $zone;
    }

    while ( my($file, $zones) = each %zones_by_file ){
	my $zone = shift @$zones;
	&import_zone("$self{dir}/$file", $zone);
	while ( my $alias = shift @$zones ){
	    if ( my $zoneobj = Netdot::Model::Zone->search(name=>$zone)->first ){
		if ( !(Netdot::Model::ZoneAlias->search(name=>$alias, zone=>$zoneobj)->first) ){
		    $logger->debug("Adding zone $alias as alias of $zone");
		    Netdot::Model::ZoneAlias->insert({name=>$alias, zone=>$zoneobj});
		}
	    }else{
		warn "Zone $zone not found in DB!.  Can't create alias $alias.\n";
	    }
	}
    }

}else{
    die $usage;
}



######################################################################
# Subroutine section
######################################################################
sub read_config {
    my ($file, $z) = @_;
    # Create the parser
    my $parser = new BIND::Config::Parser;
    my $zone;

    $parser->set_open_block_handler( 
	sub {
	    my $block = join( " ", @_ );
	    if ( $block =~ /zone\s*"(.*)"/ ){
		$zone = $1;
	    }
	} 
	);
    
    $parser->set_close_block_handler( 
	sub { $zone = "";  } 
	);
    
    $parser->set_statement_handler( 
	sub {
	    my $statement = join( " ", @_ );
	    
	    if ( $statement =~ /type\s+master/ ){
		$z->{$zone} = {};
	    }
	    elsif( $statement =~ /file\s+"(.*)"/ ){
		my $file =  $1;
		if ( exists $z->{$zone} ){
		    $z->{$zone} = $file;
		}
	    }
	} 
	);
    
    # Parse the file
    $parser->parse_file( $file );
    
}


######################################################################
sub import_zone {
    my ($file, $domain) = @_;

    (-e $file && -f $file) || die "File $file does not exist or is not a regular file\n";
    print "Importing zone file: $file\n";

    my $rrs = Net::DNS::ZoneFile::Fast::parse(file=>"$file",origin=>$domain);

    my $nzone;

    foreach my $rr ( @$rrs ){
	if ( $rr->type eq 'SOA' ){
	    my $name = $rr->name;
	    $name =~ s/\.$//;
	    my $do_insert = 1;
	    if ( exists $netdot_zones{$name} ){
		if ( $self{wipe} ){
		    $logger->debug("Wiping out Zone $name from DB");
		    $netdot_zones{$name}->delete();
		}else{
		    $logger->debug( "Zone $name already exists in DB");
		    $nzone = $netdot_zones{$name};
		    $do_insert = 0;
		}
	    }
	    if ( $do_insert ){
		$nzone = Netdot::Model::Zone->insert({
		    name        => $name,
		    mname       => $rr->mname,
		    rname       => $rr->rname,
		    serial      => $rr->serial,
		    refresh     => $rr->refresh,
		    retry       => $rr->retry,
		    expire      => $rr->expire,
		    minimum     => $rr->minimum,
						     });
	    }
	    last;
	}
    }
    
    $nzone->import_records(rrs=>$rrs, overwrite=>$self{wipe});
}
