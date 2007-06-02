include $(ROOT)/etc/utility-Makefile

#
# makefile for lib


NDIR = Netdot Netdot/Manual Netdot/Meta Netdot/Meta/Table Netdot/Model Netdot/Model/Plugins Netdot/UI Netdot/Util

FILES := `find -name "*.pm" | sed -e 's/\.\///'`

all: dir
	$(substitute)

# This section creates the lib/Netdot subdirs
dir:
	for dir in $(NDIR); do \
	    if test -d $(PREFIX)/$(DIR)/$$dir; then \
	       echo "Skipping dir $(PREFIX)/$(DIR)/$$dir; already exists"; \
	    else \
	       mkdir -m $(DMOD) -p $(PREFIX)/$(DIR)/$$dir ; \
	    fi ; \
	done
