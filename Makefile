
RELEASE=0.1
PKG=Netdot
DST = unstable
ETC = ins.sample.data netdot.relationships netdot.schema
BIN = initacls.mysql initacls.Pg setup-class-dbi.pl mason.pl initdb
HTML = search.html form.html sortresults.html 


######################################################################
help:
	@echo "This makefile will help with making a distribution"
	@echo "In the meantime, it doesn't do much.  :-("
	@echo ""
	@echo "make unstable | stable | dist RELEASE=<release-ver>"
	@echo "RELEASE defaults to $(RELEASE)"
	@echo ""
	@echo "Before making a dist, be sure to make stable"
	@echo ""
	@echo "For testing purposes on tiroloco, run"
	@echo "make test"

unstable: DST = unstable
unstable: dir etc make
stable: DST = stable
stable: dir etc make
test: DST = /home/netdot/public_html
test: testing


######################################################################
# following is for testing files on tiroloco
testing: $(HTML)
	cp $? $(DST)/htdocs


######################################################################
install:
	@echo "Not here yet...."


######################################################################
dist:
	mkdir $(PKG)-$(RELEASE)
	cp -a stable/* $(PKG)-$(RELEASE)
	tar cf dists/$(PKG)-$(RELEASE).tar $(PKG)-$(RELEASE)
	rm -rf $(PKG)-$(RELEASE)

######################################################################
dir: 
	mkdir -p $(DST)/src
	mkdir -p $(DST)/bin
	mkdir -p $(DST)/etc
	mkdir -p $(DST)/cgi
	mkdir -p $(DST)/doc
	mkdir -p $(DST)/contrib


######################################################################
bin: $(BIN)
	cp -f $? $(DST)/bin


######################################################################
etc: $(ETC)
	cp -f $? $(DST)/etc


######################################################################
make:
	cp Makefile.dist $(DST)/Makefile
	cp initdb $(DST)/initdb


# leave a blank
