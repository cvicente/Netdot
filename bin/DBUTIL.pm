package DBUTIL;
#
# A few subroutines shared by scripts in this directory
# for database initialization and maintenance
#
use strict;
use DBI;
use Data::Dumper;

use vars qw( @ISA @EXPORT $DEBUG );

use Exporter ();
@ISA = qw(Exporter);
@EXPORT = qw( dbconnect processdata dbdisconnect );

# Be verbose by default
$DEBUG = 1;

1;


##################################################
sub dbconnect {
    my ( $db_type, $db_host, $db_port, $db_dba, $db_dba_password, $db_database ) = @_;
    my $dsn = "dbi:$db_type:";
    
    $dsn .= "dbname=$db_database";
    if ($db_host) {
	$dsn .= ";host=$db_host";
    }
    if ($db_port) {
	$dsn .= ";port=$db_port";
    }
    
    print "DEBUG: init: $dsn\n" if $DEBUG;
    
    if( my $dbh = DBI->connect( $dsn, $db_dba, $db_dba_password, {RaiseError => 1} ) ) {
	print "DEBUG: Connected successfully\n" if $DEBUG;
	return $dbh;
    } else {
	print "Unable to connect to $db_type $db_database db:" 
	    . " $DBI::errstr\n"; 
	return 0;
    }
}


##################################################
sub dbdisconnect {
    my ($dbh) = @_; 
    if( $dbh->disconnect ) {
	print "DEBUG: Disconnected successfully\n" if $DEBUG;
	return 1;
    } else {
	warn "Unable to disconnect from DB\n";
	return 0;
    }
}


##################################################
sub processdata {
    my ($dbh, $lines) = @_;
    my $statements = &build_statements($lines);
    my $rows = 0;
    while (my $cmd = shift @$statements ){
	$cmd  =~ /^(.*)$/;
	chomp($cmd);
	print "DEBUG: ($cmd): ";
	$rows = $dbh->do( $cmd );
	print "rows affected: $rows\n" if $DEBUG;
    }
    return 1;
}

##################################################
# Convert lines into complete statements
# $lines must be an arrayref
sub build_statements{
    my ($lines) = @_;
    my @statements;
    my $statement = "";
    foreach my $line ( @$lines ) {
	$statement .= $line;
	if ($line =~ /;\s*$/) {
	    $statement =~ s/;$//g;
	    push @statements, $statement;
	    $statement = "";
	}
    }
    return \@statements;
}
