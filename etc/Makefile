include $(SRCROOT)/etc/utility-Makefile

#
# makefile for etc/


FILES = Default.conf netdot_apache2_radius.conf netdot_apache2_ldap.conf netdot_apache2_local.conf netdot_apache24_local.conf netdot.meta

all: 
	$(substitute)
	if ! test -r $(PREFIX)/$(DIR)/Site.conf; then \
	  $(SED) -r $(REPLACEMENT_EXPRESSIONS) Site.conf \
          > Site.conf.tmp;\
          install -m $(FMOD) Site.conf.tmp $(PREFIX)/$(DIR)/Site.conf;\
          rm -rf Site.conf.tmp;\
	fi;
