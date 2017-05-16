use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::Product'); }

my $obj = Product->insert({name=>'test', 
			   sysobjectid=>'123',
			   manufacturer=>1});

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

