package DBUTIL;
#
# A few subroutines shared by scripts
# for database initialization and maintenance
#
use strict;
use DBI;
use Netdot::Meta::SQLT;
use Data::Dumper;
use Netdot::Config;
$|=1; #unbuffer output.

my %CONFIG;

$CONFIG{DEBUG}        = 1;
$CONFIG{PROMPT}       = 1; 
$CONFIG{CONFIG_DIR}   = '../etc';
$CONFIG{SCHEMA_FILE}  = "$CONFIG{CONFIG_DIR}/netdot.meta";
$CONFIG{DEFAULT_DATA} = "$CONFIG{CONFIG_DIR}/default_data";

my $netdot_config = Netdot::Config->new(config_dir => $CONFIG{CONFIG_DIR});

foreach my $var ( qw /DB_TYPE DB_HOME DB_HOST DB_PORT DB_DBA DB_DBA_PASSWORD 
		  DB_NETDOT_USER DB_NETDOT_PASS DB_DATABASE/ ){
    $CONFIG{$var} = $netdot_config->get($var);
}

$CONFIG{BINDIR} = "$CONFIG{DB_HOME}/bin";

use vars qw( @ISA @EXPORT $dbh );

use Exporter ();
@ISA = qw(Exporter);
@EXPORT = qw( dbconnect dbdisconnect processdata build_statements init_db drop_db
generate_schema_from_metadata generate_schema_file insert_schema create_db _yesno
initacls_mysql initacls_pg insert_default_data insert_oui db_query );

##################################################
sub build_dsn { 
    my (%argv) = @_;

    # Give preference to given args, then use config
    my %db_args;
    foreach ( qw(DB_TYPE DB_DATABASE DB_HOST DB_PORT) ){
	$db_args{$_} = $argv{$_} || $CONFIG{$_};
    }
    my $dsn = "dbi:$db_args{DB_TYPE}:";
    $dsn .= "dbname=$db_args{DB_DATABASE}";
    $dsn .= ";host=$db_args{DB_HOST}" if ($db_args{DB_HOST});
    $dsn .= ";port=$db_args{DB_PORT}" if ($db_args{DB_PORT});
    return $dsn;
}

##################################################
sub dbconnect {
    my (%argv) = @_;

    # Give preference to given args, then use config
    my %db_args;
    foreach ( qw(DB_TYPE DB_DATABASE DB_HOST DB_PORT DB_DBA DB_DBA_PASSWORD) ){
	$db_args{$_} = $argv{$_} || $CONFIG{$_};
    }

    my $dsn = &build_dsn(DB_TYPE => $db_args{DB_TYPE}, DB_DATABASE =>$db_args{DB_DATABASE}, 
			 DB_HOST => $db_args{DB_HOST}, DB_PORT     =>$db_args{DB_PORT});
    
    print "DEBUG: init: $dsn\n" if $CONFIG{DEBUG};
    
    if( $dbh = DBI->connect( $dsn, $db_args{DB_DBA}, $db_args{DB_DBA_PASSWORD}) ) {
	$dbh->{AutoCommit} = 1;
	$dbh->{RaiseError} = 1;
	print "DEBUG: Connected successfully\n" if $CONFIG{DEBUG};
	return $dbh;
    } else {
	die "Unable to connect to $db_args{DB_TYPE} $db_args{DB_DATABASE} db:" 
	    . " $DBI::errstr\n"; 
    }
}


##################################################
sub dbdisconnect {
    if( $dbh->disconnect ) {
	print "DEBUG: Disconnected successfully\n" if $CONFIG{DEBUG};
	return 1;
    } else {
	warn "Unable to disconnect from DB\n";
	return 0;
    }
}


##################################################
# This does it all at once, in the right order
sub init_db {
    if ( $CONFIG{DB_TYPE} eq "mysql" ){
	&create_db();
	&initacls_mysql();
	&generate_schema_file();
	&insert_schema();
	
    }elsif ( $CONFIG{DB_TYPE} eq "Pg" ){
	&create_db();
	&generate_schema_file();
	&insert_schema();
	&initacls_pg();
    }else{
	die '$CONFIG{DB_TYPE} invalid: '.$CONFIG{DB_TYPE} ;
    }
    &insert_default_data();
    print "Database initialized successfully\n";
}

##################################################
sub drop_db {
    
    my $dsn = &build_dsn();

    if ( $CONFIG{PROMPT} ) {
	print <<END;
	
About to drop $CONFIG{DB_TYPE} database $CONFIG{DB_DATABASE}.
WARNING: This will erase all data in $CONFIG{DB_DATABASE}.
END
        exit unless _yesno();
    }
    
    my $dbh;

    print "\nDropping $CONFIG{DB_TYPE} database $CONFIG{DB_DATABASE}.\n";
    if ($CONFIG{DB_TYPE} eq "mysql") {
        $dbh = DBI->connect("dbi:mysql:mysql;host=$CONFIG{DB_HOST};port=$CONFIG{DB_PORT}", 
			    $CONFIG{DB_DBA}, $CONFIG{DB_DBA_PASSWORD}) or die $DBI::errstr;
    }elsif ($CONFIG{DB_TYPE} eq "Pg") {
        $dbh = DBI->connect("dbi:Pg:dbname=postgres;host=$CONFIG{DB_HOST};port=$CONFIG{DB_PORT}", 
			    $CONFIG{DB_DBA}, $CONFIG{DB_DBA_PASSWORD}) or die $DBI::errstr;
    }else {
	die "Unrecognized DB_TYPE: $CONFIG{DB_TYPE}\n";
    }
    $dbh->do("DROP DATABASE $CONFIG{DB_DATABASE};") or die $DBI::errstr;
}


##################################################
sub generate_schema_from_metadata {

    # SQLT uses slightly different names for the db types
    my $dbtype;
    $dbtype = 'MySQL' if ( $CONFIG{DB_TYPE} eq 'mysql');
    $dbtype = 'PostgreSQL' if ( $CONFIG{DB_TYPE} eq 'Pg');

    my $meta_file = "$CONFIG{CONFIG_DIR}/$CONFIG{SCHEMA_FILE}";
    my $sqlt   = Netdot::Meta::SQLT->new(meta_file=>$meta_file);
    my $schema = $sqlt->sql_schema($dbtype);
    my @schema = grep /[^\n]/, split /\n/, $schema;
    
    return (@schema);
}

##################################################
sub generate_schema_file {
    my @schema = &generate_schema_from_metadata();
    print "Generating schema for $CONFIG{DB_TYPE}...";
    
    my $file = "$CONFIG{CONFIG_DIR}/schema.$CONFIG{DB_TYPE}";

    system('mv', "$file", "$file.bak") if ( -f $file );

    open(SCHEMA, ">$file");
    foreach ( @schema ) {
	print SCHEMA "$_\n";
    }
    close(SCHEMA);
    print "done.\n";
}


##################################################
sub insert_schema {
    my @schema;
    print "\nCreating database schema.\n";
    my $file = "$CONFIG{CONFIG_DIR}/schema.$CONFIG{DB_TYPE}";

    if ( -f $file){
	open (SCHEMA, "<$file");
	foreach (<SCHEMA>) {
	    push @schema, $_;
	}	
    }else {
	@schema = &generate_schema_from_metadata();
    }
    
    &db_query(\@schema);
    print "Schema inserted sucessfully\n";
}


##################################################
#
sub create_db {
    my $dsn = &build_dsn();
    print "\nCreating $CONFIG{DB_TYPE} database $CONFIG{DB_DATABASE}.\n";
    if ($CONFIG{DB_TYPE} eq "mysql") {
        my $dbh = DBI->connect("dbi:mysql:mysql;host=$CONFIG{DB_HOST};port=$CONFIG{DB_PORT}", 
            $CONFIG{DB_DBA}, $CONFIG{DB_DBA_PASSWORD})
                or die $DBI::errstr;
        $dbh->do("CREATE DATABASE $CONFIG{DB_DATABASE} CHARACTER SET = utf8;")
            or die $DBI::errstr;
    } elsif ($CONFIG{DB_TYPE} eq "Pg") {
        my $dbh = DBI->connect("dbi:Pg:dbname=postgres;host=$CONFIG{DB_HOST};port=$CONFIG{DB_PORT}", 
            $CONFIG{DB_DBA}, $CONFIG{DB_DBA_PASSWORD})
                or die $DBI::errstr;
        $dbh->do("CREATE DATABASE $CONFIG{DB_DATABASE} WITH ENCODING = 'UTF8';")
            or die $DBI::errstr;
    }
}


##################################################
#
sub _yesno {
    print "Proceed [y/N]:";
    my $x = scalar(<STDIN>);
    $x =~ /^y/i;
}

##################################################
#
sub initacls_mysql {
    print "Setting up privileges for MySQL.\n";
    my @acl;
    push @acl, "DELETE FROM user WHERE user LIKE '$CONFIG{DB_NETDOT_USER}';";
    push @acl, "DELETE FROM db WHERE db LIKE '$CONFIG{DB_DATABASE}';";
    push @acl, "GRANT SELECT,INSERT,CREATE,INDEX,UPDATE,DELETE ON $CONFIG{DB_DATABASE}.* TO $CONFIG{DB_NETDOT_USER}\@$CONFIG{DB_HOST} IDENTIFIED BY '$CONFIG{DB_NETDOT_PASS}';";
 
   &db_query(\@acl, 'mysql');
    system ("$CONFIG{BINDIR}/mysqladmin --host=$CONFIG{DB_HOST} --port=$CONFIG{DB_PORT} --user=$CONFIG{DB_DBA} -p$CONFIG{DB_DBA_PASSWORD} reload");
    
}


##################################################
# Generate the ACLs for PostgreSQL
# We don't have wildcards like in MySQL ;-(
# so we have to look in the schema file first
# 
# TODO: Test this.  It might be unnecessary
#
sub initacls_pg {

    my $schema = "$CONFIG{CONFIG_DIR}/schema.Pg";
    my @acl;

    push @acl, "
DROP USER IF EXISTS $CONFIG{DB_NETDOT_USER};
CREATE USER $CONFIG{DB_NETDOT_USER} WITH PASSWORD '$CONFIG{DB_NETDOT_PASS}' NOCREATEDB NOCREATEUSER;
";

    print "Now building ACL's for postgres\n";
    
    open (SCHEMA, $schema)
	or die "Couldn't open $schema: $!\n";
    
    while (<SCHEMA>){
	if ( /CREATE TABLE "(\w+)"/ ){
	    push @acl, "GRANT SELECT, INSERT, UPDATE, DELETE ON $1 TO $CONFIG{DB_NETDOT_USER};\n";
	    push @acl, "GRANT SELECT, INSERT, UPDATE, DELETE ON $1_id_seq to $CONFIG{DB_NETDOT_USER};\n";
	}
    }

    &db_query(\@acl);
}

##################################################
#
sub insert_default_data{
    my @data;
    my $file = "$CONFIG{CONFIG_DIR}/$CONFIG{DEFAULT_DATA}";
    if ( -f $file) {
	print "Inserting default data\n";
	open (DEFAULT, "<$file") or die "Can't open $file: $!";
	foreach (<DEFAULT>) {
	    next unless ( /\w+/ );
	    if ( /INSERT INTO (\w+)/ ){
		my $t = $1;
		$t = lc($t);
		s/INSERT INTO \w+/INSERT INTO $t/;
	    }
	    push @data, $_;
	}	
    }else{
	die "Can't find $file";
    }
    &db_query(\@data);
}

##################################################
#
sub insert_oui{
    my $oui_file = "oui.txt";
    unless ( -r $oui_file ){
        print "  $oui_file not found! Using default file in package.\n";
	$oui_file = "oui.txt.default";
    }
    unless ( -r $oui_file ){
        print "  $oui_file not found!\n";
        die "Please run ''make oui'' to download oui.txt.\n";
    }
    my @data;
    print "Removing old contents of oui table in database.\n";
    push @data, "DELETE FROM oui WHERE true;";
    &db_query(\@data);

    my %oui;
    open (OUI, "<:encoding(iso-8859-1)","$oui_file") or die "Can't open $oui_file: $!\n";
    while (my $line = <OUI>){
        chomp $line;
        if ($line =~ /^([0-9A-F]{6})\s+\(base 16\)\s+(.*)\s*$/i){
            $oui{$1} = $2;
        }
    }
    close (OUI);

    @data = (); 
    $oui_file = "/tmp/oui.txt";
    open (OUI, ">:encoding(iso-8859-1)",$oui_file) or die "Can't open $oui_file: $!\n";
    foreach my $oui ( keys %oui ){
        my $vendor = $oui{$oui};
        $vendor =~ s/\'/''/g;
        $oui = uc($oui);
        print "$oui : $vendor\n" if $CONFIG{DEBUG};
        print OUI "$oui\t$vendor\n";
    }   
    close(OUI);

    if (lc($CONFIG{DB_TYPE}) eq 'mysql') {
        push @data, "LOAD DATA LOCAL INFILE '$oui_file' INTO TABLE oui (oui, vendor);";
    } elsif (lc($CONFIG{DB_TYPE}) eq 'postgres') {
        push @data, "COPY oui(oui, vendor) FROM '$oui_file';"
    }   
    &db_query(\@data);
    unlink($oui_file);
    my $oui_count = scalar keys %oui;
    print "Inserted $oui_count entries from oui.txt\n";

}

##################################################
# Convert lines into complete statements if needed
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

##################################################
sub processdata {
    my ($lines) = @_;
    $lines = &build_statements($lines);
    my $rows = 0;
    while (my $cmd = shift @$lines ){
	$cmd  =~ /^(.*)$/;
	chomp($cmd);
	print "DEBUG: ($cmd): " if $CONFIG{DEBUG};
	$rows = $dbh->do( $cmd );
	print "rows affected: $rows\n" if $CONFIG{DEBUG};
    }
    return 1;
}

##################################################
# Connect, issue queries and disconnect all at once
#
# Arguments
#   $query - arrayref of SQL statements
# Returns
#   nothing
#
sub db_query{
    my ($query, $db) = @_;
    $db ||= $CONFIG{DB_DATABASE};
    if ( &dbconnect(DB_DATABASE=>$db) ){
	die "Error with db query" unless &processdata($query);
	&dbdisconnect();
    }
}

# Return true
1;
