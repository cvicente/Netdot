#!<<Make:PERL>>
#
# Import ISC BIND zonefiles into Netdot
#
use lib "<<Make:LIB>>";
use Netdot::Model;
use Netdot::Util::ZoneFile;
use Getopt::Long qw(:config no_ignore_case bundling);
use BIND::Config::Parser;
use strict;
use Data::Dumper;

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
	    &debug("Adding zone $alias as alias of $zone");
	    if ( my $zoneobj = Netdot::Model::Zone->search(name=>$zone)->first ){
		Netdot::Model::ZoneAlias->insert({name=>$alias, zone=>$zoneobj});
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

    my ($rrs, $default_ttl) = Netdot::Util::ZoneFile::parse(file=>"$file",origin=>$domain);

    my $nzone;

    foreach my $rr ( @$rrs ){
	if ( $rr->type eq 'SOA' ){
	    my $name = $rr->name;
	    $name =~ s/\.$//;
	    my $do_insert = 1;
	    if ( exists $netdot_zones{$name} ){
		if ( $self{wipe} ){
		    &debug("Wiping out Zone $name from DB");
		    $netdot_zones{$name}->delete();
		}else{
		    &debug( "Zone $name already exists in DB");
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
		    default_ttl => $default_ttl,
						     });
	    }
	    last;
	}
    }

    my %nrrs;
    foreach my $r ( $nzone->records ){
	$nrrs{$r->name} = $r;
    }
    
    foreach my $rr ( @$rrs ){
	my $name = $rr->name;
	if ( $name eq $domain ){
	    $name = '@';
	}else {
	    if ( $name =~ /\.$domain/ ){
		$name =~ s/\.$domain\.?//;
	    }else{
		debug("Zone $domain: Ignoring out of zone data: $name");
		next;
	    }
	}

	my $nrr;
	my $ttl = $rr->ttl;
	if ( exists $nrrs{$name} ){
	    debug("$domain: RR $name already exists in DB");
	    $nrr = $nrrs{$name};
	}else{
	    &debug("$domain: Inserting RR $name");
	    $nrr = Netdot::Model::RR->insert({name=>$name, zone=>$nzone});
	    $nrrs{$name} = $nrr;
	}

	if ( $rr->type eq 'A' || $rr->type eq 'AAAA' ){
	    my $address = $rr->address;
	    my $ipb;
	    if ( !($ipb = Netdot::Model::Ipblock->search(address=>$address)->first) ){
		&debug("$domain: Inserting Ipblock $address");
		$ipb = Netdot::Model::Ipblock->insert({ address        => $address,
							status         => 'static',
							no_update_tree => 1});
	    }
	    my $rraddr;
	    my %args = (rr=>$nrr, ipblock=>$ipb);
	    if ( $self{wipe} || !($rraddr = Netdot::Model::RRADDR->search(%args)->first) ){
		$args{ttl} = $ttl;
		&debug("$domain: Inserting RRADDR $name, $address, ttl: $ttl");
		$rraddr = Netdot::Model::RRADDR->insert(\%args);
	    }
	}elsif ( $rr->type eq 'TXT' ){
	    my $rrtxt;
	    my %args = (rr=>$nrr, txtdata=>$rr->txtdata);
	    if ( $self{wipe} || !($rrtxt = Netdot::Model::RRTXT->search(%args)->first) ){
		$args{ttl} = $ttl;
		&debug("$domain: Inserting RRTXT $name, ".$rr->txtdata);
		$rrtxt = Netdot::Model::RRTXT->insert(\%args);
	    }
	}elsif ( $rr->type eq 'HINFO' ){
	    my $rrhinfo;
	    my %args = (rr=>$nrr);
	    if ( $self{wipe} || !($rrhinfo = Netdot::Model::RRHINFO->search(%args)->first) ){
		$args{cpu} = $rr->cpu;
		$args{os}  = $rr->os;
		$args{ttl} = $ttl;
		&debug("$domain: Inserting RRHINFO $name, $args{cpu}, $args{os}, ttl: $ttl");
		$rrhinfo = Netdot::Model::RRHINFO->insert(\%args);
	    }
	}elsif ( $rr->type eq 'MX' ){
	    my $rrmx;
	    my %args = (rr=>$nrr, exchange=>$rr->exchange);
	    if ( $self{wipe} || !($rrmx = Netdot::Model::RRMX->search(%args)->first) ){
		$args{preference} = $rr->preference;
		$args{exchange}   = $rr->exchange;
		$args{ttl}        = $ttl;
		&debug("$domain: Inserting RRMX $name, ".$rr->exchange.", ttl: $ttl");
		$rrmx = Netdot::Model::RRMX->insert(\%args);
	    }
	}elsif ( $rr->type eq 'NS' ){
	    my $rrns;
	    my %args = (rr=>$nrr, nsdname=>$rr->nsdname);
	    if ( !($rrns = Netdot::Model::RRNS->search(%args)->first) ){
		&debug("$domain: Inserting RRNS $name, ".$rr->nsdname);
		$args{ttl} = $ttl;
		$rrns = Netdot::Model::RRNS->insert(\%args);
	    }
	}elsif ( $rr->type eq 'CNAME' ){
	    my $rrcname;
	    my %args = (name=>$nrr, cname=>$rr->cname);
	    if ( $self{wipe} || !($rrcname = Netdot::Model::RRCNAME->search(%args)->first) ){
		$args{ttl} = $ttl;
		&debug("$domain: Inserting RRCNAME $name, ".$rr->cname.", ttl: $ttl");
		$rrcname = Netdot::Model::RRCNAME->insert(\%args);
	    }
	}elsif ( $rr->type eq 'PTR' ){
	    my $rrptr;
	    my $prefix = $domain;
	    my $ipversion;
	    if ( $prefix =~ s/(.*)\.in-addr.arpa/$1/ ){
		$ipversion = 4;
	    }elsif ( $prefix =~ s/(.*)\.ip6.arpa/$1/ ){
		$ipversion = 6;
	    }elsif ( $prefix =~ s/(.*)\.ip6.int/$1/ ){
		$ipversion = 6;
	    }
	    
	    my $ipaddr = "$name.$prefix";
	    
	    if ( $ipversion eq '4' ){
		$ipaddr = join '.', (reverse split '\.', $ipaddr);
	    }elsif ( $ipversion eq '6' ){
		my @n = reverse split '\.', $ipaddr;
		my @g; my $m;
		for (my $i=1; $i<=scalar(@n); $i++){
		    $m .= $n[$i-1];
		    if ( $i % 4 == 0 ){
			push @g, $m;
			$m = "";
		    }
		}
		$ipaddr = join ':', @g;		
	    }
	    
	    &debug("$domain: Inserting Ipblock $ipaddr");
	    my $ipb;
	    if ( !($ipb = Netdot::Model::Ipblock->search(address=>$ipaddr)->first) ){
		$ipb = Netdot::Model::Ipblock->insert({ address        => $ipaddr,
							status         => 'Static',
							no_update_tree => 1 });
	    }
	    my %args = (rr=>$nrr, ptrdname=>$rr->ptrdname, ipblock=>$ipb);
	    if ( $self{wipe} || !($rrptr = Netdot::Model::RRPTR->search(%args)->first) ){
		&debug("$domain: Inserting RRPTR $name, ".$rr->ptrdname.", ttl: $ttl");
		$args{ttl} = $ttl;
		$rrptr = Netdot::Model::RRPTR->insert(\%args);
	    }
	}elsif ( $rr->type eq 'NAPTR' ){
	    my $rrnaptr;
	    my %args = (rr=>$nrr, services=>$rr->service);
	    if ( $self{wipe} || !($rrnaptr = Netdot::Model::RRNAPTR->search(%args)->first) ){
		$args{order_field} = $rr->order;
		$args{preference}  = $rr->preference;
		$args{flags}       = $rr->flags;
		$args{services}    = $rr->service;
		$args{regexpr}     = $rr->regexp;
		$args{replacement} = $rr->replacement;
		$args{ttl} = $ttl;
		&debug("$domain: Inserting RRNAPTR $name, $args{services}, $args{regexpr}, ttl: $ttl");
		$rrnaptr = Netdot::Model::RRNAPTR->insert(\%args);
	    }
	}elsif ( $rr->type eq 'SRV' ){
	    my $rrsrv;
	    my %args = (rr=>$nrr);
	    if ( $self{wipe} || !($rrsrv = Netdot::Model::RRSRV->search(%args)->first) ){
		$args{priority} = $rr->priority;
		$args{weight}   = $rr->weight;
		$args{port}     = $rr->port;
		$args{target}   = $rr->target;
		$args{ttl} = $ttl;
		&debug("$domain: Inserting RRSRV $name, $args{port}, $args{target}, ttl: $ttl");
		$rrsrv = Netdot::Model::RRSRV->insert(\%args);
	    }
	}elsif ( $rr->type eq 'LOC' ){
	    my $rrloc;
	    my %args = (rr=>$nrr);
	    if ( $self{wipe} || !($rrloc = Netdot::Model::RRLOC->search(%args)->first) ){
		$args{ttl}       = $ttl;
		$args{size}      = $rr->size;
		$args{horiz_pre} = $rr->horiz_pre;
		$args{vert_pre}  = $rr->vert_pre;
		$args{latitude}  = $rr->latitude;
		$args{longitude} = $rr->longitude;
		$args{altitude}  = $rr->altitude;
		&debug("$domain: Inserting RRLOC $name");
		$rrloc = Netdot::Model::RRLOC->insert(\%args);
	    }
	}else{
	    warn "Type ". $rr->type. " not currently supported.\n"
		unless ( $rr->type eq 'SOA' );
	}
    }
    
    # Update IP space hierarchy
    Ipblock->build_tree(4);
    Ipblock->build_tree(6);
}

sub debug {
    my ($msg) = @_;
    print $msg, "\n" if $self{debug};
}
