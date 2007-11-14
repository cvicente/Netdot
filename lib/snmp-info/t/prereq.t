#!/usr/local/bin/perl -w
# prereq.t - Test file for prerequesites for SNMP::Info
# $Id: prereq.t,v 1.1 2003/03/06 21:47:37 maxbaker Exp $

use Test::More tests=> 3;

# Check for SNMP Module
my $have_snmp=0;

eval {
    require SNMP;
};

if ($@){
    print STDERR <<'end_snmp';

Net-SNMP not found.  Net-SNMP installs the perl modules
SNMP and SNMP::Session.  As of version 4.2.1 and greater the Perl
modules are no longer distributed on CPAN, as they are specific to different
versions of SNMP. 

Install Net-SNMP from http://net-snmp.sourceforge.net and make sure you run
configure with the --with-perl-modules switch!

Note to Redhat Users:  Redhat, in its infinite wisdom, does not install the 
Perl modules as part of their 8.0 RPMS.  Please uninstall them and install the
newest version by hand.



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
}

print STDERR << "end_mibs";


Make sure you download and install the MIBS needed for SNMP::Info.   
See Man page or perldoc for SNMP::Info.

end_mibs
# vim:syntax=perl
