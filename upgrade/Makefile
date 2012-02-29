#
# upgrade Makefile
#

PERL    ?=  /usr/bin/perl
PREFIX  ?=  `cat ../.prefix`

all: db tasks
	@echo
	@echo "Netdot has been upgraded. Now you should:"
	@echo 
	@echo "  1) 'make install'"
	@echo "  2) Stop and start Apache"
	@echo 

db:
	@echo
	@echo "Upgrading schema and data..."
	$(PERL) pre_updatedb # Remove after 1.0
	$(PERL) updatedb 

tasks:
	@echo	
	@echo "Performing various upgrade tasks"
	$(PERL) upgrade-tasks $(PREFIX)
