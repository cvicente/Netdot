# THIS IS USED BY utility-Makefile.
# Specify where the toplevel make file was called so that that
# recursively called makefiles have a point of reference for relative
# paths.  Is there a built in way to do this?
SRCROOT := $(shell pwd)

# Netdot Makefile
#
PERL        ?= /usr/bin/perl
PREFIX      ?= /usr/local/netdot
STAGEDIR    ?= $(PREFIX)
APACHEUSER  ?= apache
APACHEGROUP ?= apache
MAKE        ?= make
SED         ?= sed
usage:
	@echo 
	@echo "usage: make install|installdb|upgrade [ PARAMETER=value ]"
	@echo 
	@echo "You can either specify parameter values on the command"
	@echo "line or you can modify them in the Makefile."
	@echo 
	@echo "Current defaults are:"
	@echo 
	@echo "   PERL          = $(PERL)"
	@echo "   PREFIX        = $(PREFIX)"
	@echo "   STAGEDIR      = $(STAGEDIR)"
	@echo "   APACHEUSER    = $(APACHEUSER)"
	@echo "   APACHEGROUP   = $(APACHEGROUP)"
	@echo "   MAKE          = $(MAKE)"
	@echo "   SED           = $(SED)"
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
DMOD ?= 0775
FMOD ?= 0644
XMOD ?= 0744

# This adds all previously defined variables to the shell environment
# which makes them available in children makefiles
export

# If mason ever decides to use different directories in its data_dir there will
# be trouble.
DIR = bin doc htdocs tmp tmp/sessions /tmp/sessions/locks lib etc var import export

.PHONY: bin doc htdocs lib etc var upgrade

install: dir doc htdocs lib var bin etc _import _export
	@echo
	@echo "Netdot is installed. "
	@echo "Please read the available documentation before proceeding."

upgrade:
	cd $@; $(MAKE) all DIR=$@

testdeps:
	@echo "Testing for required Perl modules"
	$(PERL) bin/perldeps.pl test

installdeps:
	@echo "Installing required Perl modules"
	$(PERL) bin/perldeps.pl install

apt-install:
	@echo "Installing required APT packages"
	$(PERL) bin/perldeps.pl apt-install

rpm-install:
	@echo "Installing required RPM packages"
	$(PERL) bin/perldeps.pl rpm-install

dir:
	@echo 
	@echo "Creating necessary directories..."
	echo $(PREFIX) > ./.prefix
	for dir in $(DIR); do \
	    if test -d $(STAGEDIR)/$$dir; then \
	       echo "Skipping dir $(STAGEDIR)/$$dir; already exists"; \
	    else \
	       mkdir -m $(DMOD) -p $(STAGEDIR)/$$dir ; \
	    fi ; \
	done
	chown -R $(APACHEUSER):$(APACHEGROUP) $(STAGEDIR)/tmp
	chmod 750 $(STAGEDIR)/tmp

htdocs:
	cd $@ ; $(MAKE) all DIR=$@ 

doc:
	cd $@ ; $(MAKE) all DIR=$@

lib:
	cd $@ ; $(MAKE) all DIR=$@

var:
	cd $@ ; $(MAKE) all DIR=$@

bin:
	cd $@; $(MAKE) install DIR=$@

etc:
	cd $@; $(MAKE) all DIR=$@

_import:
	@echo "Going into $@..."
	cd import ; $(MAKE) install DIR=import

_export:
	@echo "Going into $@..."
	cd export ; $(MAKE) all DIR=export
dropdb: 
	@echo "WARNING:  This will erase all data in the database!"
	cd bin ; $(MAKE) dropdb

genschema: 
	@echo "Generating Database Schema"
	cd bin ; $(MAKE) genschema

installdb: 
	echo $(PREFIX) > ./.prefix
	@echo "Preparing to create netdot database"
	cd bin ; $(MAKE) installdb

defragdb: 
	@echo "Defragmenting the Database"
	cd bin ; $(MAKE) defragdb

oui:
	cd bin ; $(MAKE) oui
