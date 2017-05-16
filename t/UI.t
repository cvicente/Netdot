use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { use_ok('Netdot::UI'); }

my $ui = Netdot::UI->new();
my ($table, $col, $value) = ('Device', 'os', 'blah');

my %info = $ui->form_to_db($table . '__NEW1__name' => 'test');
isa_ok(\%info, 'HASH');
my $id = (keys %{$info{$table}{id}})[0];
my $o = $table->retrieve($id);
isa_ok($o, 'Netdot::Model::Device');

$ui->form_to_db($table . '__' . $id . '__os' => $value);

my %tmp = $ui->form_field(object=>$o, column=>$col, edit=>1 );
is($tmp{label}, "<a class=\"hand\" onClick=\"window.open('descr.html?table=Device&col=os&showheader=0', 'Help', 'width=600,height=200');\">OS</a>:", "form_field");
like($tmp{value}, "/input type=\"text\" name=\"Device__(\\d+)__os\" value=\"$value\"/", "form_field");

# TODO select_lookup
# TODO select_multiple

my $radio = $ui->radio_group_boolean(object=>$o, column=>"monitored", edit=>1, returnAsVar=>1);
like($radio, '/<nobr>Yes<input type="radio" name="Device__(\\d+)__monitored" value="1" >/', 'radio_group_boolean');

my $text = $ui->text_field(object=>$o, column=>"os", edit=>1, returnAsVar=>1);
like($text, "/<input type=\"text\" name=\"Device__(\\d+)__os\" value=\"blah\" >/", 'text_field');

my $textarea = $ui->text_area(object=>$o, column=>"info", edit=>1, returnAsVar=>1);
like($textarea, "/<textarea name=\"Device__(\\d+)__info\".*></textarea>/", 'text_area');

my $pb =  $ui->percent_bar(percent=>'50');
is($pb, '<div class="progress_bar" title="50%"><div class="progress_used" style="width:50%"></div></div>', 'percent_bar');

my $pb2 = $ui->percent_bar2(title1=>"Address Usage: ", title2=>"Subnet Usage: ", 
			    percent1=>'50', percent2=>'50');
is($pb2, '<div class="progress_bar2"><div class="progress_used2_n" style="width:50%" title="Address Usage: 50%"></div><div class="progress_used2_s" style="width:50%" title="Subnet Usage: 50%"></div></div>', 'percent_bar2');

my $cm = $ui->color_mix(color1=>'ff00cc', color2=>'cc00ff', blend=>0.5);
is($cm, 'e500e5', 'color_mix');

my $fp = $ui->friendly_percent(value=>'50',total=>'100');
is($fp, '50%', 'friendly_percent');

my $fs = $ui->format_size(1048576, 2);
is($fs, '1 MB', 'format_size');

# TODO:  add_to_fields

my $r = $ui->select_query(table=>'EntityType', terms=>['Department']);
is((values %$r)[0]->name, 'Department', 'select_query');

undef %info;
%info = $ui->form_to_db($table . '__' . $id . '__DELETE' => 'null');
is($info{$table}{id}{$id}{action}, 'DELETED', 'form_to_db');

