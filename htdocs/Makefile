include $(SRCROOT)/etc/utility-Makefile

#
# makefile for htdocs

NDIR =  cable_plant css generic help img img/graphs java_script management contacts operations reports export user_management user_help masondata/obj masondata/cache rest

FILES := `find . -name "*" | egrep ".*(host.*|handler|\.?html|\.css|\.png|\.gif|\.js|\.ico)$$" | sed -e 's/\.\///'`

all: wipedir dir
	$(substitute)
	ln -s $(PREFIX)/doc/manual/netdot-manual.htm  $(PREFIX)/$(DIR)/help/manual.html

# Wipe out dir before installing
wipedir:
	$(wipedir)

# This section creates the htdocs/ subdirs
dir:
	$(mkdirs)

	@echo "Hacking together mason permissions fix..."
	touch $(PREFIX)/$(DIR)/masondata/obj/.__obj_create_marker
	chown -R $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/$(DIR)/masondata
	chmod 0755 $(PREFIX)/$(DIR)/masondata
# Graphs can be updated dynamically so apache needs +w
	chown $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/$(DIR)/img/graphs
	chmod 0750 $(PREFIX)/$(DIR)/img/graphs

