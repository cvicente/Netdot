#
# makefile for htdocs

FILES = create.html search.html form sortresults view.html update.html delete.html search_obj.html header footer index.html browse.html table banner style.css footer2 device.html error edit.html
IMG = title.jpg

all:  images
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    sed -e "s|^use lib .*\$$|use lib \"$(PREFIX)/lib\"; |" \
	        -e "s|^.TMP *=> *.*\$$|\$$TMP => \"$(PREFIX)/tmp\" |" \
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


