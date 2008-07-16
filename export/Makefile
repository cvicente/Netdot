include $(SRCROOT)/etc/utility-Makefile

#
# makefile for export/
#
NDIR = docs nagios sysmon rancid

FILES := `find -type f |grep -v .svn |sed -e 's/\.\///'`

all: dir
	$(substitute)
	mv $(PREFIX)/$(DIR)/Makefile.inst $(PREFIX)/$(DIR)/Makefile

# This section creates the lib/Netdot subdirs
dir:
	$(mkdirs)
