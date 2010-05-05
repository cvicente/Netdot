include $(SRCROOT)/etc/utility-Makefile

#
# makefile for mibs/


NDIR  := `find . -maxdepth 1 -type d  | sed -e 's/[\.\/]//g' | sed -e 's/svn.*//'`
FILES := `find . -mindepth 2 -maxdepth 2 -type f  | sed -e 's/\.\///' | sed -e 's/\.svn.*//'`

all: wipedir dir

	for file in $(FILES); do\
	  install -m $(FMOD) $$file $(PREFIX)/$(DIR)/$$file;\
	done
	@echo "Done."


# Wipe out dir before installing
wipedir:
	$(wipedir)

# This section creates the mibs/ subdirs
dir:
	$(mkdirs)
