# SNMP::Info -  Makefile.PL
# $Id: Makefile.PL,v 1.5 2003/08/14 18:24:56 maxbaker Exp $

use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'               => 'SNMP::Info',
    'VERSION_FROM'       => 'Info.pm',
    'PREREQ_PM'          => {
                                'Math::BigInt' => 0
                                # SNMP not available on CPAN . 
                                # Install with net-snmp.sourceforge.net
                                # 'SNMP' => '4'
                            },
    ($] >= 5.005 ?    
          (ABSTRACT_FROM => 'Info.pm', 
           AUTHOR        => 'Max Baker <max@warped.org>')
                 : () 
    ),
    'PMLIBDIRS'          => ['Info','$(BASEEXT)'],
             );

sub MY::postamble { "
.PHONY: readme
readme: README
README: Info.pm
	pod2text -l Info.pm > README" }
