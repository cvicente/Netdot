include $(SRCROOT)/etc/utility-Makefile

#
# makefile for lib


NDIR = Netdot Netdot/Manual Netdot/Meta Netdot/Meta/Table Netdot/Model Netdot/Model/Plugins Netdot/Model/Device Netdot/UI Netdot/Util Netdot/Exporter

FILES := `find -name "*.pm" | grep -v snmp-info | sed -e 's/\.\///'`

all: wipedir dir
	$(substitute)

# Wipe out dir before installing
wipedir:
	$(wipedir)

# This section creates the lib/Netdot subdirs
dir:
	$(mkdirs)
