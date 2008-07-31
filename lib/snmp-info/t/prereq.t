#!/usr/local/bin/perl -w
# prereq.t - Test file for prerequesites for SNMP::Info
# $Id: prereq.t,v 1.2 2008/07/19 03:03:53 jeneric Exp $

use strict;
use warnings;
use Test::More tests=> 3;

# Check for SNMP Module
my $have_snmp=0;

eval {
    require SNMP;
};

if ($@){
    print STDERR <<'end_snmp';

Net-SNMP not found.  Net-SNMP installs the perl modules SNMP and
SNMP::Session.

Versions 4.2.1 to 5.3 the Perl modules are not distributed on CPAN, you must
install from the distribution. 

Install Net-SNMP from http://net-snmp.sourceforge.net and make sure you run
configure with the --with-perl-modules switch!

Note to Redhat Users:  Redhat, in its infinite wisdom, does not install the 
Perl modules as part of their 8.0 RPMS.  Please uninstall them and install the
newest version by hand.

Versions 5.3.1 and higher are once again available from CPAN.

end_snmp
    ok(0,'Net-SNMP not installed, or missing Perl modules.');
} else {
    $have_snmp=1;
    ok(1,'Net-SNMP installed');
}

# Check for version
SKIP: {
    skip('SNMP not installed, no further testing',2) unless $have_snmp;

    my $VERSION = $SNMP::VERSION;
    ok(defined $VERSION ? 1 : 1, "found version for SNMP");

    my ($ver_maj,$ver_min,$ver_rev) = split(/\./,$VERSION);

    ok ($ver_maj >= 4, 'Net-SNMP ver 4 or higher');
    
    if ($ver_maj == 4 and $ver_min == 2 and $ver_rev == 0){
        print STDERR << "end_420";

SNMP module version 4.2.0 found.  Please triple check that you have
version 4.2.0 of Net-SNMP installed, and that you did not accidently install
the SNMP module found on CPAN.  All newer versions are bundled with 
Net-SNMP, and are not available on CPAN.  Please find them at 
http://net-snmp.sourceforge.net .  Make sure you run configure with the 
--with-perl-modules switch.

end_420
    }
 
    if( $ver_maj == 5 and $ver_min == 0 and $ver_rev == 1 ){
        print STDERR << "end_501";


Perl module of Net-SNMP 5.0.1 is buggy. Please upgrade.


end_501
    }
 
    if(( $ver_maj == 5 and $ver_min == 3 and $ver_rev == 1 ) or
      ( $ver_maj == 5 and $ver_min == 2 and $ver_rev == 3 )) {
        print STDERR << "end_bulkwalk";


Perl module of Net-SNMP Versions 5.3.1 and 5.2.3 have issues with bulkwalk,
turn off bulkwalk. Please upgrade.

end_bulkwalk
    } 
}

print STDERR << "end_mibs";


Make sure you download and install the MIBS needed for SNMP::Info.   
See Man page or perldoc for SNMP::Info.

end_mibs
# vim:syntax=perl
