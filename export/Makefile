include $(SRCROOT)/etc/utility-Makefile

#
# makefile for export/
#
NDIR = nagios sysmon

FILES := `find -type f |grep -v .svn |sed -e 's/\.\///'`

install:
	$(substitute)
	mv $(PREFIX)/$(DIR)/Makefile.inst $(PREFIX)/$(DIR)/Makefile
