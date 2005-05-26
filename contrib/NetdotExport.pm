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

my $DEBUG = 0;

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
    foreach my $parent ( map { $_->parent } @depobjs ){
	# Check if it has any ips (and is managed)
	if ( (my $ip = ($parent->ips)[0]) 
	     && $parent->monitored 
	     && $parent->device->monitored ){
	    push @parents, $ip;
	}else{
	    print "Recursively seeking valid parents for ", $parent->name, ".", $parent->device->name, "\n" if $DEBUG;
	    foreach my $grparent ( map {$_->parent} $parent->parents ){
		print "Getting parents for ", $grparent->name, ".",  $grparent->device->name, "\n" if $DEBUG;
		push @parents, &getparents($grparent);
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
