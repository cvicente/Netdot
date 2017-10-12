use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { 
    use_ok('Netdot::Exporter');
}

my @dev_names = ('test1', 'test2', 'test3', 'localhost');
my @sites = ('tsite1', 'tsite2', 'tsite3');

sub cleanup{
    foreach my $name (@dev_names){
	my $d = Device->search(name=>$name)->first;
	$d->delete if $d;
    }
    foreach my $name (@sites){
	my $s = Site->search(name=>$name)->first;
	$s->delete if $s;
    }
}

&cleanup();

# Exporter
my $exporter  = Netdot::Exporter->new();
isa_ok($exporter, 'Netdot::Exporter', 'Constructor');

# Create some test info
my @site_ids;
for my $s (@sites){
    push @site_ids, Site->insert({name=>$s});
}
my $i = 0;
for my $name (@dev_names){
    my $dev = Device->manual_add(host=>$name);
    $dev->update({monitored=>1});
    $dev->update({site=>$site_ids[$i]});
    foreach my $int ($dev->interfaces){
	$int->update({speed=>'100'});
    }
    # Create a "removed" interface to test that we do not
    # get it in the exported data
    Interface->insert({
	device=>$dev,
	name=>'dummy',
	number=>'999',
	doc_status=>'removed'});
    $i++;
}

my $info = $exporter->get_device_info();

my @hdevs = map { $info->{$_} } sort keys %$info;
is($hdevs[0]->{hostname}, "test1.defaultdomain");
is($hdevs[0]->{site_name}, "tsite1");
is($hdevs[1]->{hostname}, "test2.defaultdomain");
is($hdevs[1]->{site_name}, "tsite2");
is($hdevs[2]->{hostname}, "test3.defaultdomain");
is($hdevs[2]->{site_name}, "tsite3");

my @ints = keys %{$hdevs[0]->{interface}};
is(length(@ints), 1);
my $f_int = $ints[0];
is($hdevs[0]->{interface}->{$f_int}->{speed}, 100);

$info = $exporter->get_device_info(site=>'tsite1');
my @ids = (sort keys %$info);
is(scalar(@ids), 1);
is($info->{$ids[0]}->{hostname}, "test1.defaultdomain");


my $nagios = Netdot::Exporter->new(type=>'Nagios');
isa_ok($nagios, 'Netdot::Exporter::Nagios', 'Constructor');
#$nagios->generate_configs();

my $sysmon = Netdot::Exporter->new(type=>'Sysmon');
isa_ok($sysmon, 'Netdot::Exporter::Sysmon', 'Constructor');
#$sysmon->generate_configs();

my $rancid = Netdot::Exporter->new(type=>'Rancid');
isa_ok($rancid, 'Netdot::Exporter::Rancid', 'Constructor');
#$rancid->generate_configs();

&cleanup();
