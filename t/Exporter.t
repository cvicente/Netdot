use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { 
    use_ok('Netdot::Exporter');
}

# Exporter
my $exporter  = Netdot::Exporter->new();
isa_ok($exporter, 'Netdot::Exporter', 'Constructor');

