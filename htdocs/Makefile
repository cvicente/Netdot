include $(SRCROOT)/etc/utility-Makefile

#
# makefile for htdocs

NDIR =  cable_plant css generic help img img/graphs java_script management contacts operations reports export user_management user_help masondata/obj masondata/cache rest

FILES := `find . -name "*" | egrep ".*(rest\/.*|handler|\.?html|\.css|\.png|\.gif|\.js|\.ico)$$" | sed -e 's/\.\///'`

all: wipedir dir
	$(substitute)
	ln -s $(STAGEDIR)/doc/manual/netdot-manual.htm  $(STAGEDIR)/$(DIR)/help/manual.html

# Wipe out dir before installing
wipedir:
	$(wipedir)

# This section creates the htdocs/ subdirs
dir:
	$(mkdirs)

	@echo "Hacking together mason permissions fix..."
	touch $(STAGEDIR)/$(DIR)/masondata/obj/.__obj_create_marker
	chown -R $(APACHEUSER):$(APACHEGROUP) $(STAGEDIR)/$(DIR)/masondata
	chmod 0755 $(STAGEDIR)/$(DIR)/masondata
# Graphs can be updated dynamically so apache needs +w
	chown $(APACHEUSER):$(APACHEGROUP) $(STAGEDIR)/$(DIR)/img/graphs
	chmod 0750 $(STAGEDIR)/$(DIR)/img/graphs

