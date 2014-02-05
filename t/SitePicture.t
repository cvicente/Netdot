use strict;
use warnings;
use Test::More;
use lib "lib";
use Data::Dumper;
use FindBin;

BEGIN { use_ok('Netdot::Model::Site'); }
BEGIN { use_ok('Netdot::Model::SitePicture'); }

my $site = Site->insert({ name => "t/SitePicture.t" });
ok($site, "site insert");

my $picture_file = "$FindBin::Bin/../htdocs/img/title.png";
ok(-f($picture_file), "picture file exists");

my $picture_data;
{
    local $/;
    if (open my $fh, "<", $picture_file) {
	$picture_data = <$fh>;
    }
}
is(length($picture_data), 8826, "the picture is right");

my $pic = SitePicture->insert({
    site     => $site->id,
    filename => $picture_file,
    bindata  => $picture_data,
});
ok($pic, "picture insert");

is($pic->bindata, $picture_data, "picture object holds correct data");
my $pic_id = $pic->id;
undef $pic;
$pic = SitePicture->retrieve($pic_id);
ok($pic, "picture retrieve");

is($pic->bindata, $picture_data, "retrieved picture object holds correct data");

$site->delete;
isa_ok($site, 'Class::DBI::Object::Has::Been::Deleted', 'cleanup ok');

done_testing;
exit;

# Ipblock
my $subnet = Ipblock->insert({address => '1.1.1.0',
                              prefix => 24,
                              status => 'Subnet'});
my $subnet_id = $subnet->id;
ok(defined $subnet, 'subnet insert');

$subnet->set('description', 'test1');
ok($subnet->update, "update without params returns success");
undef $subnet;
$subnet = Ipblock->retrieve($subnet_id);
is($subnet->description, 'test1', 'update without params');

ok($subnet->update({description => 'test2'}), "update with params returns success");
undef $subnet;
$subnet = Ipblock->retrieve($subnet_id);
is($subnet->description, 'test2', 'update with params');

eval {
    my $vlan = Vlan->insert({name => 'test vlan',
                             vid => 1});
    ok(defined $vlan, "vlan insert");

    $subnet->update({vlan => $vlan});
    is($subnet->vlan, $vlan, 'set vlan to subnet');

    $vlan->delete;
    undef $subnet;
    $subnet = Ipblock->retrieve($subnet_id);
    ok(!$subnet->vlan, 'nullify');
};
fail($@) if $@;

$subnet->delete;

done_testing;