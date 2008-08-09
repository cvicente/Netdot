use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { 
    use_ok('Netdot::Exporter');
}

my $exporter  = Netdot::Exporter->new();
isa_ok($exporter, 'Netdot::Exporter', 'Constructor');

my $nagios = Netdot::Exporter->new(type=>'Nagios');
isa_ok($nagios, 'Netdot::Exporter::Nagios', 'Constructor');
#$nagios->generate_configs();

my $sysmon = Netdot::Exporter->new(type=>'Sysmon');
isa_ok($sysmon, 'Netdot::Exporter::Sysmon', 'Constructor');
#$sysmon->generate_configs();

my $rancid = Netdot::Exporter->new(type=>'Rancid');
isa_ok($rancid, 'Netdot::Exporter::Rancid', 'Constructor');
#$rancid->generate_configs();
