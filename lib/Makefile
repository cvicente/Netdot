#
# makefile for lib

NDIR = Netdot

FILES = Netdot.pm Debug.pm $(NDIR)/UI.pm  $(NDIR)/odHasMany.pm  $(NDIR)/NetdotPermissionFactory.pm $(NDIR)/IPManager.pm $(NDIR)/DeviceManager.pm $(NDIR)/DNSManager.pm $(NDIR)/CablePlantManager.pm


all: dir files

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

