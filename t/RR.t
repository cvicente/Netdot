use strict;
use Test::More qw(no_plan);
use Test::Exception;
use lib "lib";

BEGIN { 
    my @classes = qw/Zone RR RRADDR RRCNAME RRHINFO RRLOC RRMX RRNAPTR 
                 RRNS RRDS RRPTR RRSRV RRTXT/;
    foreach my $class (@classes){
	use_ok("Netdot::Model::$class");
    }
}

my $name      = 'record';
my $domain    = 'testdomain';
my $domainrev = '168.192.in-addr.arpa';
my $v4address = '192.168.1.10';
my $v6address = 'fec0:1234:5678:9abc::10';
my $mailaddr  = '192.168.1.99';

sub cleanup{
    foreach my $val (($domain, $domainrev)){
	if ( my $obj = Zone->search(name=>$val)->first ){
	    $obj->delete();
	}
    }
    foreach my $val (($v4address, $v6address, $mailaddr)){
	if ( my $obj = Ipblock->search(address=>$val)->first ){
	    $obj->delete();
	}
    }
}

&cleanup();

# Create reverse zone first
my $revzone = Zone->insert({name=>$domainrev});
isa_ok($revzone, 'Netdot::Model::Zone', 'insert_rev_zone');

# Insert the RR. This creates the zone as well
my $rr = RR->insert({name=>$name, zone=>$domain});
isa_ok($rr, 'Netdot::Model::RR', 'insert_rr');

# There are several ways to find the rr,zone combination using search()
my $zid = Zone->search(name=>$domain)->first->id;
is(RR->search(name=>$name, zone=>$zid)->first, $rr, 'search_domain_as_id');
is(RR->search(name=>$name, zone=>$domain)->first, $rr, 'search_domain_as_name');
is(RR->search(name=>"$name.$domain")->first, $rr, 'search_as_fqdn' );
is($rr->get_label, "$name.$domain", 'get_label');

# Labels longer that 63 characters should throw a user exception
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
like($rrds->as_text, '/^record\.testdomain\.\s+3600\s+IN\s+DS\s+\(\s*60485\s+5\s+1\s+2bb183af5f22588179a53b0a98631fad1a292118/', 'rrds_as_text');

# RRHINFO
my $rrhinfo = RR->insert({type=>'HINFO', name=>$name, zone=>$domain, ttl=>3600, cpu=>'Intel', os=>'OSX'});
isa_ok($rrhinfo, 'Netdot::Model::RRHINFO', 'insert_hinfo');
is($rrhinfo->as_text, "$name.$domain.	3600	IN	HINFO	Intel OSX", 'as_text');

# RRLOC
my $rrloc = RR->insert({type=>'LOC', name=>'@', zone=>$domain, ttl=>3600, size=>"100", 
			horiz_pre=>"1000", vert_pre=>"1000", latitude=>"44.046", longitude=>"123.078", altitude=>"10"});
isa_ok($rrloc, 'Netdot::Model::RRLOC', 'insert_loc');
is($rrloc->as_text, "testdomain.	3600	IN	LOC	44 0 0 N  123 0 0 E  10m 100m 1000m 1000m", 'as_text');

# RRMX
my $rrmx = RR->insert({type=>'MX', name=>$name, zone=>$domain, ttl=>3600, preference=>10, exchange=>"smtp.example.net"});
isa_ok($rrmx, 'Netdot::Model::RRMX', 'insert_mx');
is($rrmx->as_text, "$name.$domain.	3600	IN	MX	10 smtp.example.net.", 'as_text');

# When exchage points to an A record in Netdot

throws_ok {
    RR->insert({type=>'MX', name=>$name, zone=>$domain,
		ttl=>3600, preference=>10, exchange=>"mail.$domain"});
} qr/does not exist/, 'fails if exchange within local zone does not exist';

my $mail_rr = RR->insert({type=>'A', name=>'mail', zone=>$domain,
			  ttl=>3600, ipblock=>$mailaddr });
my $rrmx2 = RR->insert({type=>'MX', name=>$name, zone=>$domain,
			ttl=>3600, preference=>20, exchange=>"mail.$domain"});
isa_ok($rrmx2, 'Netdot::Model::RRMX', 'insert_mx2');

# Issue #130
$mail_rr->delete();
is(RR->search(name=>$name, zone=>$domain)->first, $rraddr->rr,
   'Deleting MX host does not delete RR that references it');

is(RRMX->search(exchange=>"mail.$domain"), 0, 'MX pointing to deleted host gets deleted');

# RRNAPTR
my $rrnaptr = RR->insert({type=>'NAPTR', name=>'@', zone=>$domain, ttl=>3600, order_field=>"100", preference=>"10", flags=>"u", services=>"E2U+sip",
			 regexpr=>'^.*$', replacement=>'sip:information@pbx.example.com'});
isa_ok($rrnaptr, 'Netdot::Model::RRNAPTR', 'insert_naptr');
like($rrnaptr->as_text, '/^testdomain\.\s+3600\s+IN\s+NAPTR\s+\( 100 10 u E2U\+sip/', 'as_text');

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

&cleanup();
