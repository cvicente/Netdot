# 
# Generate various text files and copy them to their
# corresponding locations
#
DIR = /usr/local/netdot/export
DEVICES = $(DIR)/devices.pl
CONTACTS = $(DIR)/contacts.pl
MASTER = $(DIR)/master-cnf.pl
CIRCUITS = $(DIR)/circuits.pl
NAGIOS = $(DIR)/build_nagios_cnf.pl
SYSMON = $(DIR)/build_sysmon_cnf.pl
DOCSHOST = ns
NAGIOSHOST = nms
SYSMONHOST = ns
DOCSDIR = /usr/ns/doc
SYSMONDIR = /usr/ns/doc
NAGIOSDIR = /usr/local/nagios/etc
NAGIOSFILES = hosts.cfg apan.cfg
DOCSFILES = 10baseThubs.txt consoles.txt building-contacts.txt circuits.txt dsl.txt firewalls.txt ip-phones.txt netmon/master.cnf pdus.txt routers.txt servers.txt shapers.txt switches.txt wireless.txt 

usage:
	@echo
	@echo "usage: (short method):"
	@echo 
	@echo "make all"
	@echo "make install"
	@echo 
	@echo "(more specific):"
	@echo 
	@echo "make <target>"
	@echo 
	@echo "where <target> may be one of:"
	@echo
	@echo "docs:           generate all the documentation-related text files"
	@echo "nagios:         generate Nagios config file(s)"
	@echo "sysmon:         generate Sysmon config file(s)"
	@echo ""
	@echo "install-docs:   copy documentation files in their respective places"
	@echo "install-nagios: copy nagios config files in appropiate machine and"
	@echo "                reload the daemon"
	@echo "install-sysmon: copy sysmon config files in appropiate machine and"
	@echo "                reload the daemon"

all:	backup docs nagios sysmon

docs:	devices contacts circuits master

install: install-docs install-nagios install-sysmon

backup:
	for i in $(DOCSFILES) $(NAGIOSFILES) $(SYSMONFILES); do \
	  if [ -f "$$i" ]; then \
	    cp -f $(DIR)/$$i $(DIR)/$$i.bak ; \
	  fi \
	done

devices:
	@echo
	@echo "Generating files about devices";
	$(DEVICES)

contacts:
	@echo
	@echo "Generating files about contacts";
	$(CONTACTS)

master:
	@echo
	@echo "Generating master.cnf";
	$(MASTER)

circuits:
	@echo
	@echo "Generating circuits.txt";
	$(CIRCUITS)

nagios:
	@echo
	@echo "Generating Nagios configs";
	$(NAGIOS)

sysmon:
	@echo
	@echo "Generating Sysmon config";
	$(SYSMON)

install-docs:
	@echo
	@echo "Sending docs to $(DOCSHOST)";
	for i in $(DOCSFILES); do \
	  scp $(DIR)/$$i root@$(DOCSHOST):$(DOCSDIR)/$$i ; \
	done

install-sysmon:
	@echo
	@echo "Sending sysmon config to $(SYSMONHOST)";
	for i in $(SYSMONFILES); do \
	  scp $(DIR)/$$i root@$(SYSMONHOST):$(SYSMONDIR)/$$i ; \
	done
	@echo
	@echo "Reloading sysmond on $(SYSMONHOST)";
	ssh -x root@$(SYSMONHOST) /etc/init.d/sysmon reload &

install-nagios:
	@echo
	@echo "Sending Nagios config files to $(NAGIOSHOST)"; 
	for i in $(NAGIOSFILES); do \
	  scp $(DIR)/$$i root@$(NAGIOSHOST):$(NAGIOSDIR)/$$i ; \
	done
	@echo
	@echo "Creating RRD files on $(NAGIOSHOST)";
	ssh -x root@$(NAGIOSHOST) /usr/local/nagios/apan/setup-rrd.pl
	@echo
	@echo "Reloading Nagios on $(NAGIOSHOST)";
	ssh -x root@$(NAGIOSHOST) /sbin/service nagios reload &

