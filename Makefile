
RELEASE=0.1
PKG=Netdot
DST = unstable
ETC = netdot.schema
DOC = TODO ChangeLog MILESTONES README INSTALL
BIN = initacls.mysql initacls.Pg setup-class-dbi mason.pl initdb ins.sample.data insert-metadata updatenodes.pl
HTML = create.html search.html form.html sortresults.html view.html update.html delete.html search_obj.html header footer main.html browse.html table.html banner style.css footer2 node.html error.html
NETVIEWER = Netviewer.pm nv.categories nv.ifTypes
LIB = Netviewer.pm nv.categories nv.ifTypes GUI.pm

######################################################################
help:
	@echo "This makefile will help with making a distribution"
	@echo ""
	@echo "make unstable | stable | dist RELEASE=<release-ver>"
	@echo "RELEASE defaults to $(RELEASE)"
	@echo ""
	@echo "Before making a dist, be sure to make stable"
	@echo ""
	@echo "For testing purposes on tiroloco, run"
	@echo "make test"

unstable: DST = unstable
unstable: dir bin etc html lib doc make
stable: DST = stable
stable: dir bin etc html lib doc make
test: DST = /home/netdot/public_html
test: testing nvtest


######################################################################
# following is for testing files on tiroloco
testing:
	cp $(HTML) $(DST)/htdocs
	cp -f $(DOC) $(DST)/doc


######################################################################
# netviewer testing
.PHONY: nvtest
nvtest: DST = /home/netdot/public_html
nvtest: 
	cp -f $(NETVIEWER) $(DST)/lib/Netdot



######################################################################
install:
	@echo "Not here...."


######################################################################
dist:
	mkdir $(PKG)-$(RELEASE)
	cp -a stable/* $(PKG)-$(RELEASE)
	tar cf dists/$(PKG)-$(RELEASE).tar $(PKG)-$(RELEASE)
	rm -rf $(PKG)-$(RELEASE)

######################################################################
dir: 
	mkdir -p $(DST)/bin
	mkdir -p $(DST)/doc
	mkdir -p $(DST)/etc
	mkdir -p $(DST)/htdocs
	mkdir -p $(DST)/lib


######################################################################
bin: $(BIN)
	cp -f $? $(DST)/bin

######################################################################
doc: $(DOC)
	cp -f $? $(DST)/doc

######################################################################
etc: $(ETC)
	cp -f $? $(DST)/etc

######################################################################
html: $(HTML)
	cp -f $? $(DST)/htdocs

######################################################################
lib: $(LIB)
	cp -f $? $(DST)/lib

######################################################################
make:
	cp -f Makefile.db $(DST)/bin/Makefile
	sed -e "s|FILES = .*|FILES = $(HTML)|" Makefile.htdocs > $(DST)/htdocs/Makefile
	sed -e "s|FILES = .*|FILES = $(DOC)|" Makefile.doc > $(DST)/doc/Makefile
	sed -e "s|FILES = .*|FILES = $(LIB)|" Makefile.lib > $(DST)/lib/Makefile
	cp -f Makefile.dist $(DST)/Makefile




# leave a blank
