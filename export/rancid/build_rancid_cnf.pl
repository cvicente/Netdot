#!/usr/bin/perl
#
#  Read relevant info from Netdot and 
#  build RANCID configurations
#

#use lib "<<Make:LIB>>";
use lib "/usr/local/netdot/lib/";
use Netdot::Export;
use Netdot::DBI;
use strict;
use Data::Dumper;
use Getopt::Long;

use vars qw( %self $USAGE %groups $FILE_NAME %EXCLUDE);

&set_defaults();

my $USAGE = <<EOF;
usage: $0 --groups <GROUP> --dir <DIR> [options]

    --dir             <path> Path to configuration file
    --out             <name> Configuration file name (default: $self{out})
    --groups          Criteria to build RANCID groups.  Syntax looks like:

      name=group1;type=type1[,type2...];address=<regular expression>:name=group2...

      Explanations for the fields:

        name      Defines the RANCID group name.  This script will create a directory with the same
                  name and populate a file called $FILE_NAME inside it

        type      Corresponds with Netdot\'s ProductType

        address   Regular expression to apply to IP addresses

    --strip_domain    Strip off domain name
    --exclude_file    File containing rancid definitions of devices that should be skipped (default: $self{exclude_file})
    --debug           Print debugging output
    --help            Display this message

  Example:

    $0 --groups 'name=uo-switches;type=Switch;address=^128\.223.*' --strip_domain .uoregon.edu --exclude_file rancid.exclude

EOF

&setup();
&gather_data();
&build_configs();


##################################################
sub set_defaults {
    %self = ( 
	      dir             => '',
	      out             => 'router.db',
	      groups          => '',
	      strip_domain    => 0,
	      help            => 0,
	      debug           => 0, 

	      # File with Rancid router.db syntax. Will exclude those devices from generated list
	      exclude_file => '',

	      # These devices are known to not work with RANCID
	      exclude_oids    => {
		  '1.3.6.1.4.1.11.2.3.7.11.4'  => '',     # J3177A HP Advancestack Switch 224
		  '1.3.6.1.4.1.11.2.3.7.11.11' => '',     # HP J4093A ProCurve Switch 2424M
		  '1.3.6.1.4.1.11.2.3.7.11.8'  => '',     # HP J4120A ProCurve Switch 1600M
		  '1.3.6.1.4.1.11.2.3.7.11.9'  => '',     # HP ProCurve Switch 4000M
		  '1.3.6.1.4.1.11.2.3.7.11.10' => '',     # HP J4122A ProCurve Switch 2400M
		  '1.3.6.1.4.1.11.2.3.7.11.7'  => '',     # HP J4110A ProCurve Switch 8000M
	      },
	      
	      # Convert these Netdot Manufacturer names into RANCID's known types
	      mfg_conversions => {
		  'Hewlett|HP' => 'hp',
		  'Cisco'      => 'cisco',
		  'Juniper'    => 'juniper',
	      },
	      );
    
}

##################################################
sub setup{
    
    my $result = GetOptions( 
			     "dir=s"            => \$self{dir},
			     "out=s"            => \$self{out},
			     "groups=s"         => \$self{groups},
			     "exclude_file=s"   => \$self{exclude_file},
			     "strip_domain=s"   => \$self{strip_domain},
			     "debug"            => \$self{debug},
			     "h"                => \$self{help},
			     "help"             => \$self{help},
			     );
    
    if( ! $result || $self{help} ) {
	print $USAGE;
	exit 0;
    }
    
    unless ( $self{groups} && $self{dir} ) {
	print "ERROR: Missing required arguments\n";
	die $USAGE;
    }
    
    foreach my $group ( split /:/, $self{groups} ){
	my @pairs = split /;/, $group;
	die "Invalid group definition: $group\n" unless @pairs;
	my $namepair = shift @pairs;
	unless ( $namepair =~ /^name=(.*)/ ){
	    die "First key must be 'name='";
	}
	my $name = $1;
	foreach my $pair ( @pairs ){
	    my ($key, $val) = split /=/, $pair;
	    unless ( $key =~ /type|address/ ){  # We might add more later
		die "Unrecognized key: $key";
	    }
	    # Store all other values as arrays
	    my @list = split /,/, $val;
	    $val = \@list;
	    $groups{$name}{criteria}{$key} = $val;
	}
    }
    
    print Dumper(%groups) if $self{debug};

    if ( -e "$self{dir}/$self{exclude_file}" ){
	# Grab list of devices to exclude
	my $file = "$self{dir}/$self{exclude_file}";
	open(EXCLUDE, $file) or die "Cannot open $file: $!\n";
	foreach (<EXCLUDE>){
	    next if ( /^#/ );
	    if ( /^.*:.*:.*/ ){
		my $dev = (split /:/, $_ )[0];
		$EXCLUDE{$dev} = '';
	    }
	}
	close(EXCLUDE) or warn "$file did not close nicely\n";
	    print Dumper(%EXCLUDE) if $self{debug};
    }


}
sub gather_data{
    
    foreach my $group ( keys %groups ){
	foreach my $type ( @{$groups{$group}{criteria}{type}} ){
	    foreach my $product_type ( ProductType->search(name=>$type) ){
		
		foreach my $product ( $product_type->products ){
		    
		    unless ( $product->manufacturer ){
			print "Product ". $product->name ." does not have manufacturer set\n" if $self{debug};
			next;
		    }
		    # We might want to add more later (See RANCID documentation)
		    my $mfg = &convert_mfg($product->manufacturer->name);
		    
		    # Exclude if RANCID does not support this product
		    my $oid = $product->sysobjectid;
		    if ( exists $self{exclude_oids}->{$oid} ){
			print "Product ". $product->name ." not supported\n" if $self{debug};
			next;
		    }
		    
		    foreach my $device ( $product->devices ){
			# Exclude if no name defined
			my $name;
			next unless ( $device->name && ($name = $device->name->name) );
			
			# Exclude if Device is not monitored or snmp_managed
			# (add check for monitor_config here)
			next unless ( $device->monitored && $device->snmp_managed );
			
			# Get IP address
			my ($ar, $ip);
			unless ( ($ar = ($device->name->arecords)[0]) && ($ip = $ar->ipblock) ){
			    print "$name: Device does not have an IP address associated with its name\n" 
				if $self{debug};
			    next;
			}
			my $address = $ip->address;
			
			# Ignore if address does not match given regexes
			if ( exists $groups{$group}{criteria}{address} ){
			    my @regs = @{$groups{$group}{criteria}{address}};
			    my $expression = join '|', @regs;
			    unless (  $address =~ /$expression/ ){
				print "$name: Address $address does not match /$expression/\n" 
				    if $self{debug};
				next;
			    }
			}

			# Get name from DNS
			my $hostname = &resolve($address);
			$hostname    =~ s/$self{strip_domain}// if $self{strip_domain};

			# Ignore if in exclude file
			if ( exists $EXCLUDE{$hostname} ){
			    print "$hostname: was in exclude list\n" if $self{debug};
			    next;
			}

			$groups{$group}{devices}{$hostname}{mfg} = $mfg;

		    }
		}
	    }
	}
	print Dumper($groups{$group}) if $self{debug};
	print "Group $group has ", scalar( keys %{$groups{$group}{devices}} ), " devices\n" if $self{debug};
    }
}


sub build_configs{
    foreach my $group ( keys %groups ){
	my $dir_path  = "$self{dir}/$group";
	unless ( -d $dir_path ){
	    system("mkdir -p $dir_path") 
		&& die "Can't make dir $dir_path: $!";
	}
	my $file_path = "$dir_path/$self{out}";
	open (OUT, ">$file_path")
	    or die "Can't open $file_path: $!\n";
	select (OUT);

	print "#\t-- Generated by $0 on ", scalar localtime,  "--\n" ;

	foreach my $device ( sort keys %{$groups{$group}{devices}} ){
	    my $mfg = $groups{$group}{devices}{$device}{mfg};
	    print $device, ":$mfg:up\n";
	}
	close(OUT) or warn "$file_path did not close nicely\n";
	select(STDOUT);
	print "OK. Rancid configuration for: '$group' written to: '$dir_path'\n";
    }

}

sub convert_mfg {
    my $name = shift;
    foreach my $reg ( keys %{$self{mfg_conversions}} ){
	if ( $name =~ /$reg/ ){
	    return $self{mfg_conversions}{$reg};
	}
    }
}
