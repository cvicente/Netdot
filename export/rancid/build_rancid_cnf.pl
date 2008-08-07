#!/usr/bin/perl
#
#  Read relevant info from Netdot and 
#  build RANCID configurations
#
use lib "<<Make:LIB>>";

use Netdot::Export;
use Netdot::Model;
use strict;
use Data::Dumper;
use Getopt::Long;

use vars qw( %self $USAGE );

&set_defaults();

my $USAGE = <<EOF;
usage: $0 --groups <GROUP> --dir <DIR> [options]

    --dir             <path> Path to configuration file
    --out             <name> Configuration file name (default: $self{out})
    --debug           Print debugging output
    --help            Display this message

EOF

&setup();
my $data = &gather_data();
&build_configs($data);


##################################################
sub set_defaults {
    %self = ( 
	dir             => '',
	out             => 'router.db',
	help            => 0,
	debug           => 0, 
	
	# Convert these Netdot Manufacturer names into RANCID's known types
	# See RANCID documentation for list of available device types
	mfg_conversions => {
	    'cisco'      => 'cisco',
	    'enterasys'  => 'enterasys',
	    'extreme'    => 'extreme',
	    'force10'    => 'force10',
	    'foundry'    => 'foundry',
	    'Hewlett|HP' => 'hp',
	    'juniper'    => 'juniper',
	    'netscreen'  => 'netscreen',
	},
	);
}

##################################################
sub setup{
    
    my $result = GetOptions( 
	"dir=s"            => \$self{dir},
	"out=s"            => \$self{out},
	"debug"            => \$self{debug},
	"h"                => \$self{help},
	"help"             => \$self{help},
	);
    
    if( ! $result || $self{help} ) {
	print $USAGE;
	exit 0;
    }
    
    unless ( $self{dir} ) {
	print "ERROR: Missing required arguments\n";
	die $USAGE;
    }
}

sub gather_data{
    
    my $dbh = Netdot::Model->db_Main();
    my $query = $dbh->selectall_arrayref("
                SELECT     rr.name, zone.mname, p.name, p.sysobjectid, e.name,
                           d.monitor_config, d.monitor_config_group
                 FROM      device d, rr, zone, product p, entity e
                WHERE      d.name=rr.id
                  AND      rr.zone=zone.id
                  AND      d.product=p.id
                  AND      p.manufacturer=e.id
         ");
    
    my $exclude = Netdot->config->get('DEV_MONITOR_CONFIG_EXCLUDE') || {};
    
    my %groups;
    foreach my $row ( @$query ){
	my ($rrname, $zone, $product, $oid, $type, $vendor,
	    $monitor, $group) = @$row;  
	
	my $name = $rrname . "." . $zone;
	unless ( $monitor ){
	    &debug("$name configured to not monitor config");
	    next;
	}
	if ( exists $exclude->{$oid} ){
	    my $descr = $exclude->{$oid};
	    &debug("$name: $descr ($oid) excluded in configuration");
	    next;
	}
	
	my $mfg = &convert_mfg($vendor);
	unless ( $mfg ) {
	    &debug("$vendor has no RANCID device_type mapping");
	    next;
	}
	$groups{$group}{$name}{mfg} = $mfg;
    }
    return \%groups;
}


sub build_configs{
    my ($groups) = @_;
    foreach my $group ( keys %$groups ){
	my $dir_path  = "$self{dir}/$group";
	unless ( -d $dir_path ){
	    system("mkdir -p $dir_path") 
		&& die "Can't make dir $dir_path: $!";
	}
	my $file_path = "$dir_path/$self{out}";
	open (OUT, ">$file_path")
	    or die "Can't open $file_path: $!\n";
	select (OUT);

	foreach my $device ( sort keys %{$groups->{$group}} ){
	    my $mfg = $groups->{$group}{$device}{mfg};
	    print $device, ":$mfg:up\n";
	}
	close(OUT) or warn "$file_path did not close nicely\n";
	select(STDOUT);
	print "OK. Rancid configuration for: '$group' written to: '$dir_path'\n";
    }

}

sub convert_mfg {
    my $name = shift;
    foreach my $key ( keys %{$self{mfg_conversions}} ){
	if ( $name =~ /$key/i ){
	    return $self{mfg_conversions}{$key};
	}
    }
}

sub debug {
    print @_, "\n" if $self{debug};
}
