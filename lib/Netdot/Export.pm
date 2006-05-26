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
    my @parents;

    # Get InterfaceDep objects
    my @depobjs = $intobj->parents;
    # Get the parent interfaces
    printf ("Looking for valid parents for %s.%s\n", 
	    $intobj->name, $intobj->device->name->name) if $DEBUG;
    foreach my $parent ( map { $_->parent } @depobjs ){
	next unless ( $parent && ref($parent) eq "Interface" );
	# Check if it has any ips (and is managed)
	if ( (my $ip = ($parent->ips)[0]) 
	     && $parent->monitored 
	     && $parent->device->monitored ){
	    printf ("Adding %s.%s as parent of %s.%s\n", 
		    $parent->name, $parent->device->name->name,
		    $intobj->name, $intobj->device->name->name) if $DEBUG;
	    push @parents, $ip;
	}else{
	    printf ("%s.%s is not a valid parent\n", 
		    $parent->name, $parent->device->name->name) if $DEBUG;
	    next unless ( $recursive );
	    # Go recursive
	    my @grparents;
	    if ( @grparents = &get_dependencies(interface=>$parent, recursive=>$recursive) ){
		push @parents, @grparents;
	    }else{
		# Check if Device has other interfaces which have parents
		foreach my $int ( $parent->device->interfaces ){
		    next if $int->id == $parent->id;
		    printf ("Trying %s.%s \n", $parent->device->name->name, $int->name) if $DEBUG;
		    if ( @grparents = &get_dependencies(interface=>$int, recursive=>0) ){
			if ( my $ip = ($int->ips)[0] ){
			    # If this interface itself has an IP address, it should be the parent
			    printf ("Adding %s.%s as parent of %s.%s\n", 
				    $int->device->name->name, $int->name,
				    $intobj->device->name->name, $intobj->name) if $DEBUG;
			    push @parents, $ip; 
			    last;
			}else{
			    push @parents, @grparents; 
			    last;
			}
		    }
		}
	    }
	}
    }
    return @parents if scalar @parents;
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
