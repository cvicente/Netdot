#
# makefile for import/
#

FILES := $(shell ls *.{pm,pl,skel,inst} )

install:
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    sed -e "s|^use lib .*\$$|use lib \"$(PREFIX)/lib\"; |" \
		-e "s|^my.*\$$PREFIX.*;.*|my \$$PREFIX = \"$(PREFIX)\"; |" \
	        $$file > $$file.tmp ; \
	    install -m $(FMOD) $$file.tmp $(PREFIX)/$(DIR)/$$file ; \
	    rm -f $$file.tmp ; \
	done
	mv $(PREFIX)/$(DIR)/Makefile.inst $(PREFIX)/$(DIR)/Makefile
	@echo "Done."
