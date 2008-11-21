include $(SRCROOT)/etc/utility-Makefile

#
# makefile for export/
#
NDIR = docs nagios sysmon rancid cacti

FILES := `find -type f --regex !name Makefile |grep -v .svn |sed -e 's/\.\///'`

all: dir
	$(substitute)

	for dir in $(NDIR); do \
	  chown $(APACHEUSER):$(APACHEGROUP) $(PREFIX)/$(DIR)/$$dir; \
	  chmod 0755 $(PREFIX)/$(DIR)/$$dir; \
	done

# This section creates the export/ subdirs
dir:
	$(mkdirs)
