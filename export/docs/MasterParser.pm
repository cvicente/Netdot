
# Exports a sub-routine that parses the master.cnf file
# and returns a hash of hashes with the data.
# Useful in scripts that need an updated 
# list of devices in the Netdot database, without
# having to access the database directly
#
package MasterParser;
use strict;
use Exporter;
use Data::Dumper;

use vars qw ( @EXPORT @ISA );

@ISA       = qw( Exporter ) ;
@EXPORT    = qw( parse );

sub parse{
    my $file = shift;
    open (FH, "$file") or die "Can't open input file $file: $!\n";

    my %tree;
    my ( $network, $building );
    
    while ( <FH> ){
	next if /^#/;
	next unless /\w+/;
	chomp;
	s/^\s*//;               # no leading white
	s/\s*$//;               # no trailing white
	next unless length;     # anything left?
	my @fields = split /\s+/, $_;
	
	# Build tree
	if ($fields[0] eq 'network'){
	    $network = $fields[1];
	}elsif ($fields[0] eq 'building'){
	    $building = $fields[1];
	}elsif($fields[0] eq 'prefix'){
	    $tree{$network}{prefix}{$fields[1]} = '';
	}else{
	    $tree{$network}{building}{$building}{$fields[0]}{$fields[1]}{ip}        = $fields[2];
	    $tree{$network}{building}{$building}{$fields[0]}{$fields[1]}{community} = $fields[3];
	    $tree{$network}{building}{$building}{$fields[0]}{$fields[1]}{parents}   = $fields[4];
	}

    }
    close(FH);

    return %tree;
}
