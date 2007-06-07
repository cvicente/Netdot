include $(ROOT)/etc/utility-Makefile

#
# NetDoT Makefile
#

PERL    =  /usr/bin/perl
PREFIX  =  `cat ../.prefix`
FMOD    = 755

FILES := $(shell ls *.pl) 


################################################################
# End of tweakable section
################################################################
install:
	$(substitute)

installdb:
	$(PERL) initdb initdb

updatedb:
	$(PERL) updatedb

genschema:
	$(PERL) initdb  generate

dropdb: 
	$(PERL) initdb dropdb
