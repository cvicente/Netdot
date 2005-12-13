#!/usr/bin/perl
#
# Common routines for scripts that export netdot data into text files
#
# 


package NetdotExport;

use strict;
use Socket;
use Exporter ;
use Data::Dumper;

use vars qw ( @EXPORT @ISA @EXPORT_OK);

@ISA       = qw( Exporter ) ;
@EXPORT    = qw(getparents resolve);
@EXPORT_OK = qw();

my $DEBUG = 1;

# We'll strip off our own domain from DNS
# names
my $domain = ".uoregon.edu";


sub getparents{
########################################################################
# Recursively look for valid parents
# If the parent(s) don't have ip addresses or are not managed,
# try to keep the tree connected anyways
# Arguments:  
#   0: scalar: Interface table object
# Returns:
#   array of parent ips
########################################################################
    
    my ($intobj) = @_;
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
	    if ( my @grparents = &getparents($parent) ){
		push @parents, @grparents;
	    }
	}
    }
    return @parents if scalar @parents;
    return undef;
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
	$name =~ s/$domain.*$//i;
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
