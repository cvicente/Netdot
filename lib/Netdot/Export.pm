#!/usr/bin/perl
#
# Common routines for scripts that export netdot data into text files
#
# 


package Netdot::Export;

use strict;
use Socket;
use Exporter ;
use Data::Dumper;

use vars qw ( @EXPORT @ISA @EXPORT_OK);

@ISA       = qw( Exporter ) ;
@EXPORT    = qw( get_dependencies resolve );
@EXPORT_OK = qw();

my $DEBUG = 0;


1;

sub get_dependencies{
########################################################################
# Recursively look for valid parents
# If the parent(s) don't have ip addresses or are not managed,
# try to keep the tree connected anyways
# Arguments: 
#   interface => scalar: Interface table object
#   recursive => flag. indicates whether recursiveness is wanted
# Returns:
#   array of parent ips
########################################################################
    
    my (%args) = @_;
    my $intobj    = $args{interface} || die "Need to pass interface object";
    my $recursive = (defined $args{recursive}) ? $args{recursive} : 1;
    my %parents;

    # Get InterfaceDep objects
    my @depobjs = $intobj->parents;

    # Get the parent interfaces
    printf ("Looking for valid parents for %s.%s\n", 
	    $intobj->name, $intobj->device->name->name) if $DEBUG;

    my @parents = map { $_->parent } @depobjs;
    foreach my $parent ( @parents ){
	next unless ( $parent && ref($parent) eq "Interface" );

	# Check if it has any ips
	my $ip = ($parent->ips)[0];

	# Skip interface if it has no ip and there are other parents
	if ( !$ip && scalar(@parents) != 1 ){
	    printf ("%s.%s does not have an IP. Skipping...\n", 
		    $parent->name, $parent->device->name->name) if $DEBUG;
	    next;
	}
	# Check if interface and device are monitored
	if ( $parent->monitored  && $parent->device->monitored ){
	    printf ("Adding %s.%s as parent of %s.%s\n", 
		    $parent->name, $parent->device->name->name,
		    $intobj->name, $intobj->device->name->name) if $DEBUG;
	    $parents{$ip} = '';

	}else{
	    printf ("%s.%s is not a valid parent\n", 
		    $parent->name, $parent->device->name->name) if $DEBUG;
	    next unless ( $recursive );

	    # Go recursive
	    my @grparents;
	    if ( @grparents = &get_dependencies(interface=>$parent, recursive=>$recursive) ){
		map { $parents{$_} = '' }  @grparents;

	    }else{
		# No grandparents on that side.
		# Check if parent device has other interfaces which have parents

		foreach my $int ( $parent->device->interfaces ){
		    next if $int->id == $parent->id;
		    printf ("Trying %s.%s \n", $int->name, $parent->device->name->name ) if $DEBUG;

		    if ( @grparents = &get_dependencies(interface=>$int, recursive=>0) ){
			if ( (my $ip = ($int->ips)[0]) && $int->monitored && $int->device->monitored ){
			    # If this interface itself has an IP address, it should be the parent
			    printf ("Adding %s.%s as parent of %s.%s\n", 
				    $int->name, $int->device->name->name, 
				    $intobj->name, $intobj->device->name->name) if $DEBUG;
			    $parents{$ip} = ''; 
			    last;
			}else{
			    map { $parents{$_} = '' }  @grparents;
			    last;
			}
		    }
		}
	    }
	}
    }
    my @ret = keys %parents;
    return @ret if scalar @ret;
    return;
}


sub resolve{
########################################################################
#   Resolve Ip address to name
#
# Arguments: 
#   ip address in dotted-decimal notation (128.223.x.x)
#   or name
# Return values:
#   name or ip address if successful, 0 if error
########################################################################
  
    my $par = shift @_;
    my $ipregex = '(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})';
    if ($par =~ /$ipregex/){
	my $name;
	unless ($name = gethostbyaddr(inet_aton($par), AF_INET)){
	    warn "Can't resolve  $par: $!\n";
	    return 0;
	}
	return $name;
    }else{
	my $ip;
	unless (inet_aton($par) && ($ip = inet_ntoa(inet_aton($par))) ){
	    warn "Can't resolve $par: $!\n";
	    return 0;
	}
	return $ip;
    }
}
