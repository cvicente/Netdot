#
# makefile for htdocs

FILES = create.html search.html form.html sortresults.html view.html update.html delete.html search_obj.html header footer main.html browse.html table.html banner style.css footer2 node.html error.html

all:
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    sed -e "s|^use lib .*\$$|use lib \"$(PREFIX)/lib\"; |" \
	        $$file > $$file.tmp ; \
	    install -m $(FMOD) $$file.tmp $(PREFIX)/$(DIR)/$$file ; \
	    rm -f $$file.tmp ; \
	done
	@echo "Done."

