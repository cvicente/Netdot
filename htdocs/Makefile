include $(ROOT)/etc/utility-Makefile

#
# makefile for htdocs

NDIR =  cable_plant css generic help img img/graphs java_script management operations reports masondata/obj masondata/cache

FILES := `find -name "*" | egrep ".*(handler|\.?html|\.css|\.png|\.js)$$" | sed -e 's/\.\///'`

all: dir
	$(substitute)

# This section creates the htdocs/ subdirs
dir:
	for dir in $(NDIR); do \
	    if test -d $(PREFIX)/$(DIR)/$$dir; then \
	       echo "Skipping dir $(PREFIX)/$(DIR)/$$dir; already exists"; \
	    else \
	       mkdir -m $(DMOD) -p $(PREFIX)/$(DIR)/$$dir ; \
	    fi ; \
	done
	@echo "Hacking together mason permissions fix..."
	touch $(PREFIX)/$(DIR)/masondata/obj/.__obj_create_marker
	chown -R $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/$(DIR)/masondata
	chmod 0750 $(PREFIX)/$(DIR)/masondata
# Graphs can be updated dynamically so apache needs +w
	chown $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/$(DIR)/img/graphs
	chmod 0750 $(PREFIX)/$(DIR)/img/graphs

