#
# makefile for doc

FILES = TODO ChangeLog MILESTONES README INSTALL

all:
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    install -m $(FMOD) $$file $(PREFIX)/$(DIR)/$$file ; \
	done
	@echo "$(PERL)"
	@echo "Done."

