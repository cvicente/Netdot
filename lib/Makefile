#
# makefile for lib

NDIR = Netdot

FILES = Netdot.pm $(NDIR)/UI.pm $(NDIR)/odHasMany.pm  $(NDIR)/DefaultConfig.pm $(NDIR)/SiteConfig.pm $(NDIR)/Netviewer.pm $(NDIR)/nv.categories $(NDIR)/nv.ifTypes $(NDIR)/NetdotPermissionFactory.pm

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
	    sed -e "s|^use lib .*\$$|use lib \"$(PREFIX)/lib\"; |" \
	        $$file > $$file.tmp ; \
	    install -m $(FMOD) $$file.tmp $(PREFIX)/$(DIR)/$$file ; \
	    rm -f $$file.tmp ; \
        done
	@echo "Done."

