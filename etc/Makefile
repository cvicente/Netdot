#
# makefile for lib


FILES = Default.conf Site.conf categories

all: files

files:
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    install -m $(FMOD) $$file $(PREFIX)/$(DIR)/$$file ; \
        done
	@echo "Done."

