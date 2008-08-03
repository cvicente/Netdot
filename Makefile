# THIS IS USED BY utility-Makefile.
# Specify where the toplevel make file was called so that that
# recursively called makefiles have a point of reference for relative
# paths.  Is there a built in way to do this?
export SRCROOT := $(shell pwd)

# Netdot Makefile
#
PERL = /usr/bin/perl
PREFIX = /usr/local/netdot
APACHEUSER = apache
APACHEGROUP = apache
usage:
	@echo 
	@echo "usage: make install|installdb|upgrade [ PARAMETER=value ]"
	@echo 
	@echo "You can either specify parameter values on the command"
	@echo "line or you can modify them in the Makefile."
	@echo 
	@echo "Current defaults are:"
	@echo 
	@echo "   PERL          = $(PERL) "
	@echo "   PREFIX        = $(PREFIX) "
	@echo "   APACHEUSER    = $(APACHEUSER) "
	@echo "   APACHEGROUP   = $(APACHEGROUP) "
	@echo 
	@echo "For the defaults used in database installation/upgrade, please see "	
	@echo "bin/Makefile.  In particular, these variables may be of interest: "
	@echo 
	@echo "   DB_TYPE "
	@echo "   DB_HOME "
	@echo "   DB_DBA "
	@echo "   DB_HOST "
	@echo "   DB_NETDOT_USER "
	@echo "   DB_NETDOT_PASS "
	@echo
	@echo "Please adjust as necessary, but at your own risk!"
	@echo

#
# You really don't want to muck with anything below.  
# You're responsible if you do.
#
DMOD = 0775
FMOD = 0644
XMOD = 0744
# If mason ever decides to use different directories in its data_dir there will
# be trouble.
DIR = bin doc htdocs tmp tmp/sessions /tmp/sessions/locks lib etc var import export mibs

.PHONY: bin doc htdocs lib etc var

install: dir doc htdocs lib var _mibs bin etc _import _export
	@echo
	@echo "Netdot is installed. "
	@echo "Please read the available documentation before proceeding."
	@echo "If you are installing Netdot for the first time, you need to"
	@echo "  'make installdb'"

upgrade: updatedb
	@echo
	@echo "Netdot has been upgraded. Now you should:"
	@echo 
	@echo "  1) 'make install'"
	@echo "  2) Stop and start Apache"
	@echo 

updatedb:
	@echo
	@echo "Upgrading schema and data..."
	cd bin ; make updatedb FMOD=$(FMOD) 

testdeps:
	@echo "Testing for required Perl modules"
	$(PERL) bin/perldeps.pl test

installdeps:
	@echo "Installing required Perl modules"
	$(PERL) bin/perldeps.pl install

test:
	prove -r

dir:
	@echo 
	@echo "Creating necessary directories..."
	echo $(PREFIX) > ./.prefix
	for dir in $(DIR); do \
	    if test -d $(PREFIX)/$$dir; then \
	       echo "Skipping dir $(PREFIX)/$$dir; already exists"; \
	    else \
	       mkdir -m $(DMOD) -p $(PREFIX)/$$dir ; \
	    fi ; \
	done
	chown -R $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/tmp
	chmod 750 $(PREFIX)/tmp

htdocs:
	cd $@ ; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) \
	APACHEUSER=$(APACHEUSER) APACHEGROUP=$(APACHEGROUP) DIR=$@ 

doc:
	cd $@ ; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DIR=$@

lib:
	cd $@ ; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) DIR=$@

var:
	cd $@ ; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) DIR=$@

_mibs:
	cd mibs ; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) DIR=mibs

bin:
	cd $@; make install PREFIX=$(PREFIX) PERL=$(PERL) DIR=$@

etc:
	cd $@; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) DIR=$@

_import:
	@echo "Going into $@..."
	cd import ; make install PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DIR=import

_export:
	@echo "Going into $@..."
	cd export ; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) DIR=export

dropdb: 
	@echo "WARNING:  This will erase all data in the database!"
	cd bin ; make dropdb FMOD=$(FMOD) 

genschema: 
	@echo "Generating Database Schema"
	cd bin ; make genschema FMOD=$(FMOD) 

installdb: 
	echo $(PREFIX) > ./.prefix
	@echo "Preparing to create netdot database"
	cd bin ; make installdb FMOD=$(FMOD) 

oui:
	cd bin ; make oui

snmp_info:
	@echo
	@echo "Building and installing SNMP::Info"
	cd lib/snmp-info ; perl Makefile.PL ; make ; make install
	@echo
