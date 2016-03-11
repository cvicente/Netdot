use strict;
use Test::More qw(no_plan);
use lib "lib";

BEGIN { 
    use_ok('Netdot::Model::Zone'); 
    use_ok('Netdot::Model::RR'); 
    use_ok('Netdot::Model::RRADDR');
    use_ok('Netdot::Model::RRCNAME');
    use_ok('Netdot::Model::RRHINFO');
    use_ok('Netdot::Model::RRLOC');
    use_ok('Netdot::Model::RRMX');
    use_ok('Netdot::Model::RRNAPTR');
    use_ok('Netdot::Model::RRNS');
    use_ok('Netdot::Model::RRDS');
    use_ok('Netdot::Model::RRPTR');
    use_ok('Netdot::Model::RRSRV');
    use_ok('Netdot::Model::RRTXT');
}

my $name      = 'record';
my $domain    = 'testdomain';
my $domainrev = '168.192.in-addr.arpa';
my $v4address = '192.168.1.10';
my $v6address = 'fec0:1234:5678:9abc:0:0:0:10';

if ( Zone->search(name=>$domain) ){
    Zone->search(name=>$domain)->first->delete();
}
if ( Zone->search(name=>$domainrev) ){
    Zone->search(name=>$domainrev)->first->delete();
}

# Create reverse zone first
my $revzone = Zone->insert({name=>$domainrev});
isa_ok($revzone, 'Netdot::Model::Zone', 'insert_rev_zone');

# RR
my $rr = RR->insert({name=>$name, zone=>$domain});
isa_ok($rr, 'Netdot::Model::RR', 'insert_rr');
is(RR->search(name=>"$name.$domain")->first, $rr, 'search' );
is($rr->get_label, "$name.$domain", 'get_label');

# Labels longer that 63 characters shoud throw a user exception
my $long_name = '1234567890123456789012345678901234567890123456789012345678901234';
eval{
    RR->insert({name=>$long_name, zone=>$domain});
};
my $e = $@;
isa_ok($e, 'Netdot::Util::Exception::User');

# RRADDR
my $rraddr = RR->insert({type=>'A', name=>$name, zone=>$domain, 
			 ttl=>3600, ipblock=>$v4address });
isa_ok($rraddr, 'Netdot::Model::RRADDR', 'insert_rraddr');
is($rraddr->as_text, "$name.$domain.	3600	IN	A	$v4address", 'as_text');

my $rraddr6 = RR->insert({type=>'AAAA', name=>$name, zone=>$domain, ttl=>3600, ipblock=>$v6address});
isa_ok($rraddr6, 'Netdot::Model::RRADDR', 'insert_rraddr6');
is($rraddr6->as_text, "$name.$domain.	3600	IN	AAAA	$v6address", 'as_text');

# RRCNAME
my $rrcname = RR->insert({type=>'CNAME', name=>"alias", zone=>$domain, ttl=>3600, cname=>"$name.$domain"});
isa_ok($rrcname, 'Netdot::Model::RRCNAME', 'insert_cname');
is($rrcname->as_text, "alias.$domain.	3600	IN	CNAME	$name.$domain.", 'as_text');

# RRDS
my $rrds = RR->insert({type=>'DS', name=>$name, zone=>$domain, ttl=>3600, key_tag=>'60485', algorithm=>'5', digest_type=>'1', 
		       digest=>'2BB183AF5F22588179A53B0A98631FAD1A292118'});
isa_ok($rrds, 'Netdot::Model::RRDS', 'insert_ds');
is($rrds->as_text, "record.testdomain.	3600	IN	DS	60485  5  1  2bb183af5f22588179a53b0a98631fad1a292118 ; xepor-cybyp-zulyd-dekom-civip-hovob-pikek-fylop-tekyd-namac-moxex");

# RRHINFO
my $rrhinfo = RR->insert({type=>'HINFO', name=>$name, zone=>$domain, ttl=>3600, cpu=>'Intel', os=>'OSX'});
isa_ok($rrhinfo, 'Netdot::Model::RRHINFO', 'insert_hinfo');
is($rrhinfo->as_text, "$name.$domain.	3600	IN	HINFO	\"Intel\" \"OSX\"", 'as_text');

# RRLOC
my $rrloc = RR->insert({type=>'LOC', name=>'@', zone=>$domain, ttl=>3600, size=>"100", 
			horiz_pre=>"1000000", vert_pre=>"1000", latitude=>"", longitude=>"1704383648", altitude=>"10012200"});
isa_ok($rrloc, 'Netdot::Model::RRLOC', 'insert_loc');
is($rrloc->as_text, "testdomain.	3600	IN	LOC	596 31 23.648 S 123 05 00.000 W 122.00m 1.00m 10000.00m 10.00m", 'as_text');

# RRMX
my $rrmx = RR->insert({type=>'MX', name=>$name, zone=>$domain, ttl=>3600, preference=>10, exchange=>"smtp.example.net"});
isa_ok($rrmx, 'Netdot::Model::RRMX', 'insert_mx');
is($rrmx->as_text, "$name.$domain.	3600	IN	MX	10 smtp.example.net.", 'as_text');

# RRNAPTR
my $rrnaptr = RR->insert({type=>'NAPTR', name=>'@', zone=>$domain, ttl=>3600, order_field=>"100", preference=>"10", flags=>"u", services=>"E2U+sip",
			 regexpr=>'^.*$', replacement=>'sip:information@pbx.example.com'});
isa_ok($rrnaptr, 'Netdot::Model::RRNAPTR', 'insert_naptr');
is($rrnaptr->as_text, 'testdomain.	3600	IN	NAPTR	100 10 "u" "E2U+sip" "^.*$" sip:information\@pbx.example.com.', 'as_text');

# RRNS
my $rrns = RR->insert({type=>'NS', name=>$name, zone=>$domain, ttl=>3600, nsdname=>"ns1.$domain"});
isa_ok($rrns, 'Netdot::Model::RRNS', 'insert_ns');
is($rrns->as_text, "$name.$domain.	3600	IN	NS	ns1.$domain.", 'as_text');

# RRPTR
$rraddr->ipblock->ptr_records->first->delete();
my $rrptr = RR->insert({type=>'PTR', name=>"10.1", ipblock=>$v4address, zone=>$domainrev, ttl=>3600, ptrdname=>"$name.$domain"});
isa_ok($rrptr, 'Netdot::Model::RRPTR', 'insert_ptr');
is($rrptr->as_text, "10.1.168.192.in-addr.arpa.	3600	IN	PTR	$name.$domain.", 'as_text');

# RRSRV
my $rrsrv = RR->insert({type=>'SRV', name=>'_sip._tcp', zone=>$domain, ttl=>3600, priority=>"0", weight=>"5", port=>"5060", target=>"sipserver.$domain", });
isa_ok($rrsrv, 'Netdot::Model::RRSRV', 'insert_srv');
is($rrsrv->as_text, '_sip._tcp.testdomain.	3600	IN	SRV	0 5 5060 sipserver.testdomain.', 'as_text');

# RRTXT
my $rrtxt = RR->insert({type=>'TXT', name=>$name, zone=>$domain, ttl=>3600, txtdata=>'"text record"'});
isa_ok($rrtxt, 'Netdot::Model::RRTXT', 'insert_txt');
is($rrtxt->as_text, "$name.$domain.	3600	IN	TXT	\"text record\"", 'as_text');

my $zone = $rr->zone;

# We should have one of each in this zone (except a PTR)
my $count = $zone->get_record_count;
foreach my $rtype ( keys %$count ){
    next if ( $rtype eq 'ptr' );
    is($count->{$rtype}, 1, $rtype.'_record_count');
}

$rr->add_alias('alias2');
my @cnames = $rr->aliases();
isa_ok($cnames[1], 'Netdot::Model::RRCNAME', 'add_alias');
is($cnames[1]->as_text, "alias2.$domain.	86400	IN	CNAME	$name.$domain.", 'alias_as_text');

# Clean up
$zone->delete;
$revzone->delete;
Ipblock->search(address=>$v4address)->first->delete;
Ipblock->search(address=>$v6address)->first->delete;
