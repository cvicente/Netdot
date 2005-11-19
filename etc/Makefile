#
# makefile for lib


FILES = Default.conf categories netdot_apache2_radius.conf
all: files

files:
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    sed -e "s|<<Make:PREFIX>>|$(PREFIX)|g" \
	        $$file > $$file.tmp ; \
	    install -m $(FMOD) $$file.tmp $(PREFIX)/$(DIR)/$$file ; \
	    rm -f $$file.tmp ; \
        done
	@echo "Done."

