include $(SRCROOT)/etc/utility-Makefile

#
# NetDoT Makefile
#

PERL    =  /usr/bin/perl
PREFIX  =  `cat ../.prefix`
FMOD    = 755
OUI_URL = http://standards-oui.ieee.org/oui/oui.txt

FILES := $(shell ls *.pl) 

################################################################
# End of tweakable section
################################################################
install:
	$(substitute)

installdb: _installdb oui

_installdb:
	$(PERL) initdb initdb

genschema:
	$(PERL) initdb generate

dropdb:
	$(PERL) initdb dropdb

defragdb: _defragdb

_defragdb:
	$(PERL) defragdb

oui:
	rm -f oui.txt
	wget -t 1 -T 10 $(OUI_URL) || cp oui.txt.default oui.txt
	$(PERL) initdb oui
