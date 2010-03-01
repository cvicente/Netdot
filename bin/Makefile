include $(SRCROOT)/etc/utility-Makefile

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

installdb: _installdb oui

_installdb:
	$(PERL) initdb initdb

updatedb: _updatedb _fix_history_indexes

_updatedb:
	$(PERL) updatedb 

_fix_history_indexes:
	$(PERL) fix_history_indexes

genschema:
	$(PERL) initdb generate

dropdb:
	$(PERL) initdb dropdb

oui:
	rm -f oui.txt
	wget http://standards.ieee.org/regauth/oui/oui.txt
	$(PERL) initdb oui
