include $(ROOT)/etc/utility-Makefile

#
# makefile for htdocs

FILES := $(shell ls autohandler dhandler *.{{m,}html,css,js}) 

IMG = title.png

all:  images
	$(substitute)

images:
	@echo
	@echo "Installing image files...."
	cd img ; \
	for img in $(IMG); do \
	    install -m $(FMOD) $$img $(PREFIX)/$(DIR)/img/$$img ; \
	done
	@echo "Done."
