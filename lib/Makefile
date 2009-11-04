include $(SRCROOT)/etc/utility-Makefile

#
# makefile for lib


NDIR = Netdot Netdot/Manual Netdot/Meta Netdot/Meta/Table Netdot/Model Netdot/Model/Plugins Netdot/Model/Device Netdot/UI Netdot/Util Netdot/Exporter

FILES := `find -name "*.pm" | grep -v snmp-info | sed -e 's/\.\///'`

PATCHED := $(shell ls ../lib/patched_modules)

all: wipedir dir
	$(substitute)

# Wipe out dir before installing
wipedir:
	$(wipedir)

# This section creates the lib/Netdot subdirs
dir:
	$(mkdirs)

patcheddeps:
	@echo "Installing patched Perl modules"
	cd patched_modules
	for dir in $(PATCHED); do\
            cd $$dir/;\
	    perl Makefile.PL;\
	    make test;\
	    make install;\
	    cd ../../;\
	done

