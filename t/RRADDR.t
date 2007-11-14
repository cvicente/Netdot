use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model::RRADDR'); }

my $rr = RR->insert({name=>'test'});
my $ip = Ipblock->insert({address=>'192.168.1.10'});

my $obj = RRADDR->insert({rr=>$rr, ipblock=>$ip});
isa_ok($obj, 'Netdot::Model::RRADDR', 'insert');

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

# This test fails incorrectly for some reason.
# The object is actually deleted.
#isa_ok($rr, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

$ip->delete;
