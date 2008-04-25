include $(SRCROOT)/etc/utility-Makefile

#
# makefile for var/
#
# Note: The RRD definition below assumes a polling period of 1 hour
# You will have to adjust it to reflect your desired polling interval
# as defined in your cron jobs
#
# For reference see: 
#   http://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html
#
POLLSTATSRRD = pollstats.rrd

all: 
	if ! test -r $(PREFIX)/$(DIR)/$(POLLSTATSRRD); then \
	  rrdtool create $(POLLSTATSRRD) -s 3600 \
	  DS:ips:GAUGE:7200:0:4294967296 \
	  DS:macs:GAUGE:7200:0:4294967296 \
	  DS:arp_devs:GAUGE:7200:0:4294967296 \
	  DS:fwt_devs:GAUGE:7200:0:4294967296 \
	  DS:poll_time:GAUGE:7200:0:4294967296 \
	  RRA:AVERAGE:0.5:1:24 \
	  RRA:AVERAGE:0.5:24:365 \
	  RRA:MAX:0.5:24:30 \
	  RRA:MIN:0.5:24:30; \
	  install -m $(FMOD) $(POLLSTATSRRD) $(PREFIX)/$(DIR)/$(POLLSTATSRRD); \
	fi;
