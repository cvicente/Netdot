
# Netdot Makefile
#
PERL = /usr/bin/perl
PREFIX = /usr/local/netdot
NVPREFIX = /usr/local/netviewer
APACHEUSER = apache
APACHEGROUP = apache
usage:
	@echo 
	@echo "usage: make install [ PREFIX=<destination> ]"
	@echo 
	@echo "You can either specify the PREFIX on the command line or "
	@echo "modify the PREFIX value in the Makefile. "
	@echo "It currently defaults to $(PREFIX)"
	@echo 
	@echo "Assuming UID and GID of apache process are: "
	@echo "   APACHEUSER = $(APACHEUSER) "
	@echo "   APACHEGROUP = $(APACHEGROUP) "
	@echo "Please adjust as necessary."
	@echo
	@echo "For the defaults used in database installation, please see"
	@echo "bin/Makefile.  In particular, these variables may be of interest:"
	@echo "     DB_TYPE, DB_HOME, DB_DBA, DB_HOST, "
	@echo "     DB_NETDOT_USER, DB_NETDOT_PASS "
	@echo "Again, please see bin/Makefile for details.  Change at your own risk!"
	@echo 
	@echo "After running make install, you may also want to:"
	@echo "   make dropdb" 
	@echo "   make installdb"

#
# You really don't want to muck with anything below.  
# You're responsible if you do.
#
DMOD = 0775
FMOD = 0644
XMOD = 0744
# If mason ever decides to use different directories in its data_dir there will
# be trouble.
DIR = bin doc htdocs/img htdocs/masondata/obj htdocs/masondata/cache tmp lib etc

.PHONY: tests bin doc htdocs lib etc

install: tests dir doc htdocs lib bin etc
	@echo
	@echo "Netdot is installed. "
	@echo "Please read the available documentation before proceeding"
	@echo "Be sure to check whether you need to run 'make dropdb' or 'make installdb'"
	@echo 

tests:
	@echo
	@echo "Installation directory: $(PREFIX)"
	@echo 
	@echo "Testing for required perl modules...."
	perl -M'DBI 1.46' -e 1
	perl -M'Class::DBI 0.96' -e 1
	perl -MHTML::Mason -e 1
	perl -M'Apache::Session 1.6' -e 1
	perl -MApache::DBI -e 1
	perl -MDBIx::DBSchema -e 1
	perl -MDBIx::DataSource -e 1
	perl -MSNMP -e 1
	perl -MNetAddr::IP -e 1
#	perl -MSiteControl::AccessController -e 1
	perl -I/usr/local/netviewer/lib -M'NetViewer::RRD::SNMP 0.29.6' -e 1
	if [ `whoami` != root ]; then \
	   echo "You're not root; this may fail" ; \
	fi
	echo $(PREFIX) > ./.prefix

dir:
	@echo 
	@echo "Creating necessary directories..."
	for dir in $(DIR); do \
	    if test -d $(PREFIX)/$$dir; then \
	       echo "Skipping dir $(PREFIX)/$$dir; already exists"; \
	    else \
	       mkdir -m $(DMOD) -p $(PREFIX)/$$dir ; \
	    fi ; \
	done
	chown -R $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/htdocs/masondata
	chmod 0750 $(PREFIX)/htdocs/masondata
	chown $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/tmp
	chmod 750 $(PREFIX)/tmp

htdocs:
	cd $@ ;  make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DIR=$@ 

doc:
	cd $@ ;  make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DIR=$@

lib:
	cd $@ ; make all PREFIX=$(PREFIX) NVPREFIX=$(NVPREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) DIR=$@

bin:
	cd $@; make install PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DIR=$@

etc:
	cd $@; make all PREFIX=$(PREFIX) PERL=$(PERL) FMOD=$(FMOD) DMOD=$(DMOD) DIR=$@

dropdb: 
	@echo "WARNING:  This will erase all data in the database!"
	cd bin ; make dropdb FMOD=$(FMOD) 

installdb: 
	echo $(PREFIX) > ./.prefix
	@echo "Preparing to create netdot database"
	cd bin ; make installdb FMOD=$(FMOD) 


