include $(ROOT)/etc/utility-Makefile

#
# makefile for export/
#

#FILES := $(shell ls *.{pm,pl,skel,inst} )
FILES := `find -name "*" | egrep ".*(\.?pm|\.pl|\.skel|\.inst)$$" | sed -e 's/\.\///'`

install:
	$(substitute)
	mv $(PREFIX)/$(DIR)/Makefile.inst $(PREFIX)/$(DIR)/Makefile
