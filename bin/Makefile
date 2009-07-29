include $(SRCROOT)/etc/utility-Makefile

#
# NetDoT Makefile
#

PERL    =  /usr/bin/perl
PREFIX  =  `cat ../.prefix`
FMOD    = 755

FILES := $(shell ls *.pl) 

DB_NETDOT_USER=(default: netdot_user)
DB_NETDOT_PASS=(default: netdot_pass)

################################################################
# End of tweakable section
################################################################
install:
	$(substitute)

installdb: _installdb oui

_installdb:
	$(PERL) initdb initdb

updatedb: _updatedb

_updatedb:
	$(PERL) updatedb 

genschema:
	$(PERL) initdb generate

dropdb:
	$(PERL) initdb dropdb

oui:
	rm -f oui.txt
	wget http://standards.ieee.org/regauth/oui/oui.txt
	$(PERL) initdb oui
