#!/usr/bin/perl
#
#  Read relevant info from Netdot and 
#  build Sysmon configuration
#

use lib "<<Make:LIB>>";
use Netdot::Model;
use Netdot::Export;
use strict;
use Getopt::Long;
use Netdot::Util::DNS;

my $dns    = Netdot::Util::DNS->new();
my $export = Netdot::Export->new();

use vars qw( %self $USAGE %hosts %name2ip %ip2name );

&set_defaults();

my $USAGE = <<EOF;
usage: $0 --dir <path> --out <filename> [options]

    --monitor         <hostname> Monitoring system name
    --dir             <path> Path to configuration file
    --out             <filename> Name of configuration file (default: $self{out})
    --queuetime       <seconds> How often an object is queued to be checked. 
                      This defaults to $self{queuetime} seconds after the last test is over
    --maxqueued       <integer> This specifies how many tests may be performed at one time 
                      (default: $self{maxqueued})
    --html            <filename> HTML file to dump current status to (default: $self{html})
    --html_refresh    <seconds> Allows modification of the HTML status page refresh time 
                      (default $self{html_refresh})
    --log_facility    <facility> Syslog facility (default: $self{log_facility})
    --root            <root object> Name of the root node in the hierarchy
    --strip_domain    <domain_name> Strip off domain name from device name
    --debug           Print debugging output
    --help            Display this message
EOF

&setup();
&gather_data();
&build_configs();


##################################################
sub set_defaults {
    %self = ( 
	      dir             => '.',
	      out             => 'sysmon.conf',
	      queuetime       => 30,
	      maxqueued       => 500,
	      html            => '/var/www/html/sysmon/index.html',
	      html_refresh    => 5,
	      log_facility    => 'local2',
	      root            => '',
	      strip_domain    => '',
	      help            => 0,
	      debug           => 0, 
	      );
}

##################################################
sub setup{
    my $result = GetOptions( 
	"monitor=s"        => \$self{monitor},
	"dir=s"            => \$self{dir},
	"out=s"            => \$self{out},
	"queuetime"        => \$self{queuetime},
	"maxqueued"        => \$self{maxqueued},
	"html"             => \$self{html},
	"html_refresh"     => \$self{html_refresh},
	"log_facility"     => \$self{log_facility},
	"root=s"           => \$self{root},
	"strip_domain=s"   => \$self{strip_domain},
	"debug"            => \$self{debug},
	"h"                => \$self{help},
	"help"             => \$self{help},
	);
    
    if( ! $result || $self{help} ) {
	print $USAGE;
	exit 0;
    }
}

##################################################
sub gather_data {
    my $monitor = Device->search(name=>$self{monitor})->first 
	|| die "Cannot find monitor device";
    
    my $device_ips = $export->get_device_ips();

    foreach my $row ( @$device_ips ){
	my ($deviceid, $ipid, $int_monitored, $dev_monitored) = @$row;
	next unless ($int_monitored && $dev_monitored);
	my $ipobj = Ipblock->retrieve($ipid);

	my $hostname;
	if ( my $name = $dns->resolve_ip($ipobj->address) ){
	    $hostname = $name;
	}elsif ( my @arecords = $ipobj->arecords ){
	    $hostname = $arecords[0]->rr->get_label;
	}else{
	    $hostname = $ipobj->address;
	}

	unless ( $hostname && $dns->resolve_name($hostname) ){
	    warn $ipobj->address, " does not resolve symmetrically.  Using IP address\n";
	    $hostname = $ipobj->address;
	}
	if ( exists $name2ip{$hostname} ){
	    warn $hostname, " is not unique.  Using IP address\n";
	    $hostname = $ipobj->address;
	}
	$hostname =~ s/$self{strip_domain}// if $self{strip_domain};
	$hosts{$ipobj->id}{name} = $hostname;
	$ip2name{$ipobj->id}     = $hostname;
	$name2ip{$hostname}      = $ipobj->id;
    }

    # Now that we have everybody in
    # assign parent list
    my $dependencies = $export->get_dependencies($monitor->id);
    foreach my $ipid ( keys %hosts ){
	next unless defined $dependencies->{$ipid};
	if ( my @parentlist = @{$dependencies->{$ipid}} ){
	    my @names;
	    foreach my $parent ( @parentlist ){
		if ( !exists $ip2name{$parent} ){
		    warn "IP $ipid parent $parent not in monitored list."
			." Skipping.\n";
		    next;
		}
		push @names, $ip2name{$parent};
	    }
	    $hosts{$ipid}{parents} = \@names;
	}else{
	    $hosts{$ipid}{parents} = undef;
	}
    }
}

##################################################
sub build_configs {
    
# Open output file for writing
    my $filename = "$self{dir}/$self{out}";
    open (OUT, ">$filename") 
	or die "Can't open $filename $!\n";
    select (OUT);

    print <<EOP;
root \"$self{root}\"\;
config queuetime $self{queuetime}\;
config maxqueued $self{maxqueued}\;
config noheartbeat\;
config logging syslog \"$self{log_facility}\"\;
config statusfile html \"$self{html}\"\;
config html refresh $self{html_refresh};
EOP

    
    foreach my $ipid ( keys %hosts ){
	my $name = $hosts{$ipid}{name};
	
	printf "\n";
	printf "object $name \{\n";
	printf "   ip \"$name\"\;\n";
	printf "   type ping\;\n";
	printf "   desc \"$name\"\;\n";
	
	foreach my $parent ( @{ $hosts{$ipid}{parents} } ){
	    next if ($parent eq "");
	    print "   dep \"$parent\"\;\n";
	}
	
	print "\}\;";
	print "\n";
	
    }
    
    print STDOUT "OK: Sysmon configuration written to $filename\n";
    close(OUT) or warn "$filename did not close nicely";
}
