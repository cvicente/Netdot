#
# makefile for htdocs

FILES = index.html browse.html edit.html search.html view.html delete.html search_obj.html form sortresults.mhtml header footer table style.css style-gray.css style-blue.css style-uo.css device.html device-ws.html ip-ws.html error custom edit_html select.js select_query.html section1 section2 section_management.mhtml section_cable.mhtml cable_plant.html cable_backbone.html cable_horizontal.html cable_strand.html dynamic_list.js dynamic_list_query.html display_bin.html closet.html interface.html login.html logout.html ipblock_list.mhtml backbone_list_query.html suggest_backbonename.html floor.html suggest_jackid.html circuit.html get_strand_sequence_list.html strand_backbone_list_query.html display_sequence.mhtml 

IMG = title.jpg

all:  images
	@echo
	@echo "Preparing and installing $(DIR) files..."
	for file in $(FILES); do \
	    sed -e "s|^use lib .*\$$|use lib \"$(PREFIX)/lib\"; |" \
		-e "s|^\$$PREFIX => .*|\$$PREFIX => \"$(PREFIX)\"|" \
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


