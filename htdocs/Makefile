#
# makefile for htdocs

# At this point the files header.mhtml and section_operations.mhtml have been forgotten, as well
# as operations.html to which section_operations.mhtml refers.

#FILES = index.html browse.html edit.html search.html view.html delete.html search_obj.html form.mhtml sortresults.mhtml header footer.mhtml table.mhtml style.css style-gray.css style-blue.css style-uo.css updatedevice.html device.html deldevice.html ip-ws.html error.mhtml custom edit.mhtml select.js select_query.html section1.mhtml section2.mhtml section_management.mhtml section_cable.mhtml section_reports.mhtml cable_plant.html cable_backbone.html cable_horizontal.html cable_strand.html dynamic_list.js dynamic_list_query.html display_bin.html closet.html interface.html login.html logout.html backbone_list_query.html suggest_backbonename.html floor.html suggest_jackid.html circuit.html get_strand_sequence_list.html strand_backbone_list_query.html display_sequence.mhtml room_site_query.html addservice.html addlink.html ipblock_list.mhtml

# So, since we are basically taking every file in htdocs/ which has an extension, how about
FILES := $(shell ls [^.]*.*) 
# which grabs every file which has an extension (the first negated `.' hides . and ..).

IMG = title.jpg

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

.PHONY: files
files:
	echo $(FILES)

