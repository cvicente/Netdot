#
# makefile for lib


FILES = Default.conf categories netdot_apache2_radius.conf
all: files

files:
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    install -m $(FMOD) $$file $(PREFIX)/$(DIR)/$$file ; \
        done
	@echo "Done."

