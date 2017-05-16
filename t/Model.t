use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::Model'); }

my $obj = Site->insert({name=>'test'});
is($obj->name, 'test', 'insert');

my @objs = Site->search_like(name=>'tes');
is($objs[0]->name, 'test', 'search_like');

my $ts = Netdot::Model->timestamp();
like($ts, qr/\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2}/, 'timestamp');

my $date = Netdot::Model->date();
like($date, qr/\d{4}\/\d{2}\/\d{2}/, 'date');

my $meta = Site->meta_data();
isa_ok($meta, 'Netdot::Meta::Table', 'meta_data');

my $result = Netdot::Model->raw_sql("SELECT name FROM site WHERE name='test'");
my @headers = $result->{headers};
is($headers[0]->[0], 'name', 'raw_sql');
my $rows = $result->{rows};
is($rows->[0]->[0], 'test', 'raw_sql');

# Notice we pass an invalid field 'names' to cause the subroutine to fail
# The result must be -1 (See Class::DBI's update method)
my $r = Netdot::Model->do_transaction( sub{ return $obj->update(@_) }, names=>'test' );
is($r, -1, 'do_transaction');

my $ac = Netdot::Model->db_auto_commit(0);
is($ac, '', 'db_auto_commit');

$ac = Netdot::Model->db_auto_commit(1);
is($ac, 1, 'db_auto_commit');

$obj->update({name=>'test2'});

# This doesn't work for some stupid reason
#my %state = $obj->get_state();
#is($state{name}, 'test2', 'get_state'); 

is($obj->get_label, 'test2', 'get_label');

my $res = Netdot::Model->search_all_tables('test2');
ok(exists $res->{'Site'}->{$obj->id}, 'search_all_tables');

my $bl = Ipblock->search(address=>'10.0.0.0')->first;
$res = Netdot::Model->search_all_tables('10.0.0.0');
ok(exists $res->{'Ipblock'}->{$bl->id}, 'search_all_tables_2');

$obj->delete;
isa_ok($obj, 'Class::DBI::Object::Has::Been::Deleted', 'delete');

is(Netdot::Model->sqldate2time('2011-09-13'), 1315872000, 'sqldate2time');
is(Netdot::Model->sqldate2time('2011-09-13 11:59:47'), 1315915187, 'sqldate2time');
