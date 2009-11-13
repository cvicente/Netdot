include $(SRCROOT)/etc/utility-Makefile

#
# NetDoT Makefile
#

PERL    =  /usr/bin/perl
PREFIX  =  `cat ../.prefix`
FMOD    = 755
DB_DBA  = default
DB_DBA_PASSWORD = default

FILES := $(shell ls *.pl) 


################################################################
# End of tweakable section
################################################################
install:
	$(substitute)

installdb: _installdb oui

_installdb:
	$(PERL) initdb initdb $(DB_DBA) $(DB_DBA_PASSWORD)

updatedb: _updatedb

_updatedb:
	$(PERL) updatedb 

genschema:
	$(PERL) initdb generate $(DB_DBA) $(DB_DBA_PASSWORD)

dropdb:
	$(PERL) initdb dropdb $(DB_DBA) $(DB_DBA_PASSWORD)

oui:
	rm -f oui.txt
	wget http://standards.ieee.org/regauth/oui/oui.txt
	$(PERL) initdb oui $(DB_DBA) $(DB_DBA_PASSWORD)
