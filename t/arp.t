use strict;
use warnings;
use Test::More;
use lib "lib";

# these duplicate the regex in Netdot::Model::Device::CLI::CiscoIOS and give
# test cases for types of arp/mac-address-table/neighbor entries we might
# encounter.


# duplicating these because if we call the Netdot functions it connects to a
# database even though we're testing, which is overkill.
my $CISCO_MAC = '\w{4}\.\w{4}\.\w{4}';
my $IPV4 = '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}';
my $HD   = '[0-9A-Fa-f]{1,4}'; # Hexadecimal digits, 2 bytes
my $V6P1 = "(?:$HD:){7}$HD";
my $V6P2 = "(?:$HD(?:\:$HD){0,6})?::(?:$HD(?:\:$HD){0,6})?";
my $IPV6 = "$V6P1|$V6P2"; # Note: Not strictly a valid V6 address


{
my $arp = << 'ARP';
Internet  10.82.250.129           -   0000.0c9f.f002  ARPA GigabitEthernet0/3.2335";
ARP

foreach my $line (split/\n/, $arp) {
    if ( $line =~ /^Internet\s+($IPV4)\s+[-\d]+\s+($CISCO_MAC)\s+ARPA\s+(\S+)/o )
    {
        my $ip    = $1;
        my $mac   = $2;
        my $iname = $3;
        ok($2 eq '0000.0c9f.f002', 'arp match');
    } else {
        ok(0, 'arp match');
        diag("Line doesn't match: $line\n");
    }
}

}

{
my $fdb = << 'FDB';
   128  0022.91a9.6100   dynamic  Yes        255   Gi9/22
*  703  0022.91a9.6100   dynamic  Yes          5   Fa2/13
*   10  0022.91a9.6100   dynamic  Yes   Gi3/9
 901      0022.91a9.6100   dynamic ip,ipx,assigned,other TenGigabitEthernet1/14
Te1/16    0022.91a9.6100   dynamic ip,ipx,assigned,other TenGigabitEthernet1/16
FDB


foreach my $line (split(/\n/, $fdb)) {
    if ( $line =~ /^.*($CISCO_MAC)\s+dynamic\s+.*?(\S+)\s*$/o ) {
        ok($1 eq '0022.91a9.6100','fwt match');
    } else {
        ok(0, 'fwt match');
        diag("Line doesn't match: $line\n");
    }
}

}

{
my $v6nd = << 'ND';
FE80::219:E200:3B7:1920                     0 0019.e2b7.1920  REACH Gi0/2.3
ND

foreach my $line (split(/\n/, $v6nd)) {
    if ( $line =~ /^($IPV6)\s+\d+\s+($CISCO_MAC)\s+\S+\s+(\S+)/o ) {
        ok($2 eq '0019.e2b7.1920','nd match');
    } else {
        ok(0, 'nd match');
        diag("Line doesn't match: $line\n");
    }
}

}

done_testing();
