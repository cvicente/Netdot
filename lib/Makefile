#
# makefile for lib

NDIR = Netdot

FILES = Netdot.pm Debug.pm jsrsServer.pl $(NDIR)/Mason.pm $(NDIR)/UI.pm  $(NDIR)/Nullify.pm  $(NDIR)/NetdotPermissionFactory.pm $(NDIR)/IPManager.pm $(NDIR)/DeviceManager.pm $(NDIR)/DNSManager.pm $(NDIR)/CablePlantManager.pm $(NDIR)/SiteControlLoginWrapper.pm GraphVizClassDBI.pm


all: dir files

# This section creates the lib/Netdot subdir
dir:
	for dir in $(NDIR); do \
	    if test -d $(PREFIX)/$(DIR)/$$dir; then \
	       echo "Skipping dir $(PREFIX)/$(DIR)/$$dir; already exists"; \
	    else \
	       mkdir -m $(DMOD) -p $(PREFIX)/$(DIR)/$$dir ; \
	    fi ; \
	done

files:
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    sed -e "s|^use lib \"NVPREFIX/lib\".*\$$|use lib \"$(NVPREFIX)/lib\"; |" \
	        -e "s|PREFIX|$(PREFIX)|g" \
	        $$file > $$file.tmp ; \
	    install -m $(FMOD) $$file.tmp $(PREFIX)/$(DIR)/$$file ; \
	    rm -f $$file.tmp ; \
        done
	@echo "Done."

