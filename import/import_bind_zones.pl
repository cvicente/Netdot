#!/usr/bin/perl
#
# Import Bind zonefiles into Netdot
#
use lib "/usr/local/netdot/lib";
use Netdot::Model;
use Net::DNS::ZoneFile::Fast;
use Getopt::Long qw(:config no_ignore_case bundling);
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

    open(FILE, $self{config}) or die "Cannot open $self{config}: $!\n";
    my (%zones, %files);
    my ($zone, $file);
    
    my @lines = <FILE>;
    my $config = join '', @lines;
    
    while ( $config =~ s/zone\s+"([\.-\w]+)"\s*{(.+?)}//s ){
	my $zone = $1;
	next if ($zone eq '.');
	my $block = $2;
	if ( $block =~ /type\s+master/ ){
	    if ( $block =~ /file\s*"(.+)"/ ){
		$file = $1;
		if ( !exists $files{$file} ){
		    $zones{$zone} = $file;
		}
		push @{$files{$file}}, $zone;
	    }
	}
    }
    foreach my $zone ( keys %zones ){
	my $file = $zones{$zone};
	&import_zone("$self{dir}/$file", $zone);
    }

    my %aliases;
    foreach my $file ( %files ){
	if ( scalar @{$files{$file}} > 1 ){
	    my $main_zone = shift @$files{$file};
	    $zones{$main_zone} || die "$main_zone not found in hash\n";
	    foreach my $alias ( @{$files{$file}} ){
		&debug("Adding zone $alias as alias of $main_zone");
		if ( my $zone = Netdot::Model::Zone->search(name=>$main_zone)->first ){
		    Netdot::Model::ZoneAlias->insert({name=>$alias, zone=>$zone});
		}else{
		    warn "Zone $main_zone not found in DB!.  Can't create alias $alias.\n";
		}
	    }
    	}
    }
    

}else{
    die $usage;
}

######################################################################
# Subroutine section
######################################################################
sub import_zone {
    my ($file, $domain) = @_;

    print "Importing zone file: $file\n";
    my $rrs = Net::DNS::ZoneFile::Fast::parse(file=>"$file", origin=>$domain);

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
		    name    => $name,
		    mname   => $rr->mname,
		    rname   => $rr->rname,
		    serial  => $rr->serial,
		    refresh => $rr->refresh,
		    retry   => $rr->retry,
		    expire  => $rr->expire,
		    minimum => $rr->minimum });
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
		$ipb = Netdot::Model::Ipblock->insert({ address => $address,
							status  => 'static' });
	    }
	    my $rraddr;
	    my %args = (rr=>$nrr, ipblock=>$ipb);
	    if ( $self{wipe} || !($rraddr = Netdot::Model::RRADDR->search(%args)->first) ){
		&debug("$domain: Inserting RRADDR $name, $address");
		$args{ttl} = $rr->ttl;
		$rraddr = Netdot::Model::RRADDR->insert(\%args);
	    }
	}elsif ( $rr->type eq 'TXT' ){
	    my $rrtxt;
	    my %args = (rr=>$nrr, txt=>$rr->txtdata);
	    if ( $self{wipe} || !($rrtxt = Netdot::Model::RRTXT->search(%args)->first) ){
		&debug("$domain: Inserting RRTXT $name, ".$rr->txtdata);
		$args{ttl} = $rr->ttl;
		$rrtxt = Netdot::Model::RRTXT->insert(\%args);
	    }
	}elsif ( $rr->type eq 'HINFO' ){
	    my $rrhinfo;
	    my %args = (rr=>$nrr);
	    if ( $self{wipe} || !($rrhinfo = Netdot::Model::RRHINFO->search(%args)->first) ){
		&debug("$domain: Inserting RRHINFO $name, ".$rr->cpu);
		$args{cpu} = $rr->cpu;
		$args{os}  = $rr->os;
		$args{ttl} = $rr->ttl;
		$rrhinfo = Netdot::Model::RRHINFO->insert(\%args);
	    }
	}elsif ( $rr->type eq 'MX' ){
	    my $rrmx;
	    my %args = (rr=>$nrr, exchange=>$rr->exchange);
	    if ( $self{wipe} || !($rrmx = Netdot::Model::RRMX->search(%args)->first) ){
		&debug("$domain: Inserting RRMX $name, ".$rr->exchange);
		$args{preference} = $rr->preference;
		$args{exchange}   = $rr->preference;
		$args{ttl}        = $rr->ttl;
		$rrmx = Netdot::Model::RRMX->insert(\%args);
	    }
	}elsif ( $rr->type eq 'NS' ){
	    my $rrns;
	    my %args = (rr=>$nrr, nsdname=>$rr->nsdname);
	    if ( !($rrns = Netdot::Model::RRNS->search(%args)->first) ){
		&debug("$domain: Inserting RRNS $name, ".$rr->nsdname);
		$args{ttl} = $rr->ttl;
		$rrns = Netdot::Model::RRNS->insert(\%args);
	    }
	}elsif ( $rr->type eq 'CNAME' ){
	    my $rrcname;
	    my %args = (alias=>$nrr, cname=>$rr->cname);
	    if ( $self{wipe} || !($rrcname = Netdot::Model::RRCNAME->search(%args)->first) ){
		&debug("$domain: Inserting RRCNAME $name, ".$rr->cname);
		$args{ttl} = $rr->ttl;
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
		$ipb = Netdot::Model::Ipblock->insert({ address => $ipaddr,
							   status  => 'static' });
	    };
	    
	    my %args = (rr=>$nrr, ptrdname=>$rr->ptrdname, ipblock=>$ipb);
	    if ( $self{wipe} || !($rrptr = Netdot::Model::RRPTR->search(%args)->first) ){
		&debug("$domain: Inserting RRPTR $name, ".$rr->ptrdname);
		$args{ttl} = $rr->ttl;
		$rrptr = Netdot::Model::RRPTR->insert(\%args);
	    }
	}
    }
}

sub debug {
    my ($msg) = @_;
    print $msg, "\n" if $self{debug};
}
