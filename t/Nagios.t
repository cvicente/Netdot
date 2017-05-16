use strict;
use Test::More qw(no_plan);
use Test::File::Contents;
use lib "lib";

my $TMP = '/tmp';
my $FILE = 'test_nagios.cfg';

my $dev = Device->manual_add('host'=>'localhost');

BEGIN { 
    use_ok('Netdot::Exporter');
}

my $obj  = Netdot::Exporter->new(
    'type'=>'Nagios',
    'NAGIOS_DIR' => $TMP,
    'NAGIOS_FILE' => $FILE,
);
isa_ok($obj, 'Netdot::Exporter::Nagios', 'Constructor');

# Check generated file
$obj->generate_configs();
my $fname = "$TMP/$FILE";
ok(-e $fname, "Test file created");
file_contents_like $fname, 'localhost', 'hostname';
file_contents_like $fname, 'define host', 'host definition';
file_contents_like $fname, 'define service', 'service definition';

unlink($fname);

$dev->delete();
