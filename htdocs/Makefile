#
# makefile for htdocs

FILES := $(shell ls autohandler dhandler *.{{m,}html,css,js}) 

IMG = title.png

all:  images
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    sed -e "s|^use lib .*\$$|use lib \"$(PREFIX)/lib\"; |" \
		-e "s|^my.*\$$PREFIX.*;.*|my \$$PREFIX = \"$(PREFIX)\"; |" \
	        -e "s|^my.*\$$TMP.*;.*|my \$$TMP = \"$(PREFIX)/tmp\"; |" \
	        $$file > $$file.tmp ; \
	    install -m $(FMOD) $$file.tmp $(PREFIX)/$(DIR)/$$file ; \
	    rm -f $$file.tmp ; \
	done
	@echo "Done."

images:
	@echo
	@echo "Installing image files...."
	cd img ; \
	for img in $(IMG); do \
	    install -m $(FMOD) $$img $(PREFIX)/$(DIR)/img/$$img ; \
	done
	@echo "Done."

#.PHONY: files
#files:
#	echo $(FILES)

