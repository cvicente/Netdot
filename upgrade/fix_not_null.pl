# Fixes previously incorrect (too-lax) NOT NULL constraints

use warnings;
use strict;
use lib "../lib";
use DBUTIL;
use Netdot;
use Netdot::Model;
use Netdot::Meta;
use Data::Dumper;

my %CONFIG;
$CONFIG{debug} = 1;
$CONFIG{CONFIG_DIR} = "../etc";
$CONFIG{SCHEMA_FILE}  = "$CONFIG{CONFIG_DIR}/netdot.meta";
$CONFIG{DEFAULT_DATA} = "$CONFIG{CONFIG_DIR}/default_data";

my $netdot_config = Netdot::Config->new(config_dir => $CONFIG{CONFIG_DIR});
my $db_type = $netdot_config->get('DB_TYPE');
my $file;
if (  $db_type eq "mysql" ) {
    $file = 'fix_not_null_mysql.sql';
}elsif ( $db_type eq "Pg" ) {
    $file = 'fix_not_null_Pg.sql';
}else{
    die "Incorrect DB_TYPE: $db_type\n";
}
my $dbh = &dbconnect();

open(FILE, $file) or die "Can't open $file: $!\n";
my @statements = <FILE>;
eval {
    &processdata(\@statements);
};
if ( my $e = $@ ){
    print "Applying constraints failed: $e\n".
	"You might want to fix your data and apply these constraints again like this:\n".
	" cd upgrade/\n".
	" perl $0\n";
}else{
    print "\nNew 'NOT NULL' constraints applied successfully!\n";
}

