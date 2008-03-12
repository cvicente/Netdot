include $(SRCROOT)/etc/utility-Makefile

#
# makefile for etc/


FILES = Default.conf netdot_apache2_radius.conf netdot.meta
all: 
	$(substitute)
	if ! test -r Site.conf; then \
	  install -m $(FMOD) Site.conf $(PREFIX)/$(DIR)/Site.conf; \
	fi;
