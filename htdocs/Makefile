#
# makefile for htdocs

FILES = index.html browse.html edit.html search.html view.html delete.html search_obj.html form sortresults header footer table banner style.css style-gray.css style-blue.css style-uo.css device.html device-ws.html error custom edit_html select.js 
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


