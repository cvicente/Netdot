include $(SRCROOT)/etc/utility-Makefile

#
# makefile for doc

NDIR = manual

FILES := `find . -type f |egrep -v '\.svn|Makefile' |sed -e 's/\.\///'`

all: dir
	$(substitute)

	for dir in $(NDIR); do \
	  chown $(APACHEUSER):$(APACHEGROUP) $(STAGEDIR)/$(DIR)/$$dir; \
	  chmod 0755 $(STAGEDIR)/$(DIR)/$$dir; \
	done

# This section creates the doc/ subdirs
dir:
	$(mkdirs)
