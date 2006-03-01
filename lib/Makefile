include $(ROOT)/etc/utility-Makefile

#
# makefile for lib


NDIR = Netdot

FILES = Netdot.pm Debug.pm jsrsServer.pl $(NDIR)/Meta.pm $(NDIR)/Mason.pm $(NDIR)/UI.pm  $(NDIR)/Nullify.pm  $(NDIR)/NetdotPermissionFactory.pm $(NDIR)/IPManager.pm $(NDIR)/DeviceManager.pm $(NDIR)/DNSManager.pm $(NDIR)/CablePlantManager.pm $(NDIR)/SiteControlLoginWrapper.pm GraphVizClassDBI.pm Operations.pm


all: dir
	$(substitute)

# This section creates the lib/Netdot subdir
dir:
	for dir in $(NDIR); do \
	    if test -d $(PREFIX)/$(DIR)/$$dir; then \
	       echo "Skipping dir $(PREFIX)/$(DIR)/$$dir; already exists"; \
	    else \
	       mkdir -m $(DMOD) -p $(PREFIX)/$(DIR)/$$dir ; \
	    fi ; \
	done
