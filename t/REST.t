use strict;
use Test::More qw(no_plan);
use Test::Exception;

use lib "lib";


BEGIN { use_ok('Netdot::REST'); }

throws_ok { Netdot::REST->new() } qr/Missing required arg/, 
    'constructor throws missing args';





