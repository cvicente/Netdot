#
# NetDoT Makefile
#

PERL    =  `which perl`
PREFIX  =  `cat ../.prefix`

FILES = mason.pl updatenodes.pl

#################################################################
# Database setup
#################################################################

#
# DB_TYPE defines what sort of database NetDoT trys to talk to
# "mysql" is known to work.
# "Pg" is known to work

DB_TYPE =  mysql

# DB_HOME is where the Database's commandline tools live.  $DB_HOME/bin
# should contain the binaries themselves, e.g. if "which mysql" gives
# "/usr/local/mysql/bin/mysql", $DB_HOME should be "/usr/local/mysql"

DB_HOME = /usr

# Set DB_DBA to the name of a DB user with permission to create new databases 
# Set DB_DBA_PASSWORD to that user's password (if you don't, you'll be prompted
# later)

# For mysql, you probably want 'root'
# For Pg, you probably want 'postgres' 

DB_DBA          =  root
DB_DBA_PASSWORD =       
 
#
# Set this to the Fully Qualified Domain Name of your database server.
# If the database is local, rather than on a remote host, using "localhost" 
# will greatly enhance performance.

DB_HOST =  localhost

# If you're not running your database server on its default port, 
# specifiy the port the database server is running on below.
# It's generally safe to leave this blank 

DB_PORT = 

#
# Set this to the canonical name of the interface NetDoT will be talking to the 
# database on.  If you said that the DB_HOST above was "localhost," this 
# should be too. This value will be used to grant NetDoT access to the database.
# If you want to access the NetDoT database from multiple hosts, you'll need
# to grant those database rights by hand.
#

DB_NETDOT_HOST =  localhost

# set this to the name you want to give to the NetDoT database in 
# your database server. 

DB_DATABASE =  netdot

# Set this to the name of the netdot database user

DB_NETDOT_USER =  netdot_user

# Set this to the password used by the NetDoT database user
# *** Change This Before Installation***

DB_NETDOT_PASS =  netdot_pass


################################################################
# End of tweakable section
################################################################

install: initialize.$(DB_TYPE) insert.metadata insert.sample.data setup.class.dbi files

initialize.Pg: createdb genschema initdb.dba acls

initialize.mysql: createdb acls initdb.user

acls:
	./initacls.$(DB_TYPE) '$(DB_HOME)' '$(DB_HOST)' '$(DB_PORT)' '$(DB_DBA)' '$(DB_DBA_PASSWORD)' '$(DB_DATABASE)'\
		'$(DB_NETDOT_PASS)' '$(DB_NETDOT_HOST)' '$(DB_NETDOT_USER)' 

genschema:
	$(PERL) initdb  '$(DB_TYPE)' '$(DB_HOME)' '$(DB_HOST)' '$(DB_PORT)' '$(DB_DBA)' '$(DB_DATABASE)' generate

dropdb: 
	$(PERL) initdb '$(DB_TYPE)' '$(DB_HOME)' '$(DB_HOST)' '$(DB_PORT)' '$(DB_DBA)' '$(DB_DATABASE)' drop

createdb: 
	$(PERL) initdb '$(DB_TYPE)' '$(DB_HOME)' '$(DB_HOST)' '$(DB_PORT)' '$(DB_DBA)' '$(DB_DATABASE)' create

initdb.dba:
	$(PERL) initdb '$(DB_TYPE)' '$(DB_HOME)' '$(DB_HOST)' '$(DB_PORT)' '$(DB_DBA)' '$(DB_DATABASE)' insert

initdb.user:
	$(PERL) initdb '$(DB_TYPE)' '$(DB_HOME)' '$(DB_HOST)' '$(DB_PORT)' '$(DB_NETDOT_USER)' '$(DB_DATABASE)' insert

insert.metadata:
	$(PERL) insert-metadata '$(DB_HOME)' '$(DB_DATABASE)' '$(DB_DBA)'

insert.sample.data:
	$(PERL) ins.sample.data '$(DB_HOME)' '$(DB_DATABASE)' '$(DB_DBA)'

setup.class.dbi:
	$(PERL) setup-class-dbi '$(DB_TYPE)' '$(DB_DATABASE)' '$(DB_NETDOT_USER)' '$(DB_NETDOT_PASS)'  
	install -m $(FMOD) DBI.pm $(PREFIX)/lib/Netdot/DBI.pm

files:
	for file in $(FILES); do \
	    install -m $(FMOD) $$file $(PREFIX)/bin ; \
	done



