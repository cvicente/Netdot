# Module makefile for SNMP::Info (using ExtUtils::MakeMaker)
# $Id: Makefile.PL,v 1.7 2008/07/20 03:46:08 jeneric Exp $

require 5.006;

use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'SNMP::Info',
    AUTHOR        => 'Eric A. Miller <emiller@cpan.org>',
    VERSION_FROM  => 'Info.pm',
    ABSTRACT_FROM => 'Info.pm',
    PREREQ_PM     => {
        'Test::More'   => 0,
        'Math::BigInt' => 0,
        'SNMP'         => 0,
    },
    PMLIBDIRS => [ 'Info', '$(BASEEXT)' ],
    dist      => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean     => { FILES    => 'SNMP-Info-*' },
    realclean => { FILES    => 'Makefile.old' },
    (     ( ExtUtils::MakeMaker->VERSION() lt '6.25' ) ? ( 'PL_FILES' => {} )
        : ()
    ),
    (   ( ExtUtils::MakeMaker->VERSION() gt '6.30' ) ? ( 'LICENSE' => 'bsd' )
        : ()
    ),

);

sub MY::postamble {
    "
.PHONY: readme
readme: README
README: Info.pm
	pod2text -l Info.pm > README";
}
