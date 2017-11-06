#!<<Make:PERL>>

# Prune database
#
#
use lib "<<Make:LIB>>";
use Netdot::Model;
use Netdot::Config;
use DBUTIL;
use Getopt::Long qw(:config no_ignore_case bundling);
use Log::Log4perl::Level;
use strict;

# This will be reflected in audit tables, logs, etc.
$ENV{REMOTE_USER} = "netdot";

my %self;
$self{DEBUG}       = 0;
$self{HELP}        = 0;
$self{VERBOSE}     = 0;
$self{NUM_DAYS}    = 365;
$self{ROTATE}      = 0;

my $usage = <<EOF;
 usage: $0  -F, --fwt | -A, --arp | 
            -M, --macs | -I, --ips | -R, --rr | -a, --audit | -t, --hostaudit
          [ -d, --num_days <number> ] [ -r, --rotate ]
          [ -g, --debug ] [-h, --help]
    
    -F, --fwt                      Forwarding Tables
    -A, --arp                      ARP caches
    -M, --macs                     MAC addresses
    -I, --ips                      IP addresses
    -R, --rr                       DNS Resource Records
    -a, --audit                    Audit records
    -t, --hostaudit                Host Audit records
    -i, --interfaces               'Removed' interfaces
    -d, --num_days                 Number of days worth of items to keep (default: $self{NUM_DAYS});
    -r, --rotate                   Rotate forwarding tables and ARP caches (rather than delete records) 
    -p, --pretend                  Show activity without actually deleting anything
    -g, --debug                    Print (lots of) debugging output
    -h, --help                     Print help
    
EOF


# handle cmdline args
my $result = GetOptions(
    "F|fwt"           => \$self{FWT},
    "A|arp"           => \$self{ARP},
    "M|macs"          => \$self{MACS},
    "I|ips"           => \$self{IPS},
    "R|rr"            => \$self{RR},
    "a|audit"         => \$self{AUDIT},
    "t|hostaudit"     => \$self{HOSTAUDIT},
    "i|interfaces"    => \$self{INTERFACES},
    "d|num_days=i"    => \$self{NUM_DAYS},
    "r|rotate"        => \$self{ROTATE},
    "p|pretend"       => \$self{PRETEND},
    "h|help"          => \$self{HELP},
    "g|debug"         => \$self{DEBUG},
    );

if ( $self{HELP} ) {
    print $usage;
    exit;
}

if ( !$result ){
    print $usage;
    die "Error: Problem with cmdline args\n";
}

unless  ( $self{FWT} || $self{ARP} || $self{MACS} || 
	  $self{IPS} || $self{RR} || $self{HOSTAUDIT} || 
          $self{AUDIT} || $self{INTERFACES} ){
    print $usage;
    die "Error: Missing required args\n";
}

# Add a log appender depending on the output type requested
my $logger = Netdot->log->get_logger('Netdot::Model');
my $logscr = Netdot::Util::Log->new_appender('Screen', stderr=>0);
$logger->add_appender($logscr);

# Set logging level to debug
# Notice that $DEBUG is imported from Log::Log4perl
$logger->level($DEBUG) if ( $self{DEBUG} );

# Get DB handle 
my $dbh = Netdot::Model::db_Main();
my $db_type = Netdot->config->get('DB_TYPE');

# date NUM_DAYS ago
my $sqldate = Netdot::Model->sqldate_days_ago($self{NUM_DAYS});
$logger->debug(sprintf("NUM_DAYS(%d) ago was : %s", $self{NUM_DAYS}, $sqldate));

my $start = time;
my %rows_deleted;


if ( $self{MACS} ){
    ###########################################################################################
    # Delete MAC addresses that don't belong to devices (static flag is off)
    # Note: This will also delete FWTableEntry, ArpCacheEntry objects, DhcpScopes, etc.
    my @macs = PhysAddr->search_where(static=>0, last_seen=>{ '<', $sqldate } );
    foreach my $mac ( @macs ){
	$logger->debug(sprintf("Deleting PhysAddr %s", $mac->address));
	unless ( $self{PRETEND} ){
	    $mac->delete;
	    $rows_deleted{physaddr}++;
	}
    }
}
if ( $self{IPS} ){
    ###########################################################################################
    # Delete 'Discovered' IP addresses
    # Note: This will also delete A/AAAA records, ArpCache entries, DhcpScopes, etc.
    my $q = $dbh->prepare("SELECT ipblock.id 
                           FROM   ipblock, ipblockstatus
                           WHERE  ipblockstatus.name='Discovered'
                             AND  ipblock.status=ipblockstatus.id
                             AND  ipblock.last_seen < ?");
    $q->execute($sqldate);
    while ( my $id = $q->fetchrow_array() ) {
	if ( my $ip = Ipblock->retrieve($id) ){
	    $logger->debug(sprintf("Deleting IP %s", $ip->address));
	    unless ( $self{PRETEND} ){
		$ip->delete() ;
		$rows_deleted{ipblock}++;
	    }
	}
    }
}

if ( $self{RR} ){
    my $today = Netdot::Model->sqldate_today();
    $logger->debug("Deleting resource records expiring today or before today ($today)");
    my @where = (-and => [expiration => {'<=', $today},
			  expiration => {'<>', '0000-00-00'},
			  expiration => {'<>', '1970-01-01'},
			  expiration => {'<>', '1970-01-02'}]
	);

    my @rrs = RR->search_where(@where);

    unless ( $self{PRETEND} ){
	foreach my $rr ( @rrs ){
	    $logger->debug("Deleting RR: ".$rr->get_label);
	    $rr->delete();
	}
    }

    $rows_deleted{rr} = scalar(@rrs);
}

if ( $self{HOSTAUDIT} ){
    my $r;
    $logger->debug("Deleting hostaudit records");
    $r = $dbh->do("DELETE FROM hostaudit WHERE tstamp < '$sqldate'")
	unless $self{PRETEND};
    $rows_deleted{hostaudit} = $r;
}

if ( $self{AUDIT} ){
    my $r;
    $logger->debug("Deleting audit records");
    $r = $dbh->do("DELETE FROM audit WHERE tstamp < '$sqldate'")
	unless $self{PRETEND};
    $rows_deleted{audit} = $r;
}

if ( $self{INTERFACES} ){
    my $r;
    $logger->debug("Deleting all interfaces with 'removed' doc status");
    my $count = 0;
    unless ( $self{PRETEND} ){
	foreach my $i (Interface->search('doc_status'=>'removed')){
	    $i->delete();
	    $count++
	}
    }
    $rows_deleted{interfaces} = $count;
}

if ( $self{FWT} ){
    if ( $self{ROTATE} ){
	if ( $db_type ne 'mysql' ){
	    die "Rotate function only implemented in mysql for now";
	}
	unless ( $self{PRETEND} ){
	    &rotate_tables('fwtableentry', 'fwtable');
	}
    }else{
	###########################################################################################
	# Delete FWTables (also deletes FwtableEntry records)
	$logger->info("Deleting Forwarding Tables older than $sqldate");
	my @fwts = FWTable->search_where(tstamp=>{ '<', $sqldate });
	foreach my $fwt ( @fwts ){
	    $logger->debug("Deleting FWTable id ". $fwt->id);
	    unless ( $self{PRETEND} ){
		$fwt->delete;
		$rows_deleted{fwtable}++;
	    }
	}
	$logger->debug("Freeing deleted space in fwtableentry");
	&optimize_table('fwtableentry') unless $self{PRETEND};
    }
}

if ( $self{ARP} ){
    if ( $self{ROTATE} ){
	if ( $db_type ne 'mysql' ){
	    die "Rotate function only implemented in mysql for now";
	}
	unless ( $self{PRETEND} ){
	    &rotate_tables('arpcacheentry', 'arpcache');
	}
    }else{
	###########################################################################################
	# Delete ArpCaches
	# Note: This will also delete ArpCacheEntry objects.
	$logger->info("Deleting ARP Caches older than $sqldate");

	my @arps = ArpCache->search_where(tstamp=>{ '<', $sqldate });
	foreach my $arp ( @arps ){
	    $logger->debug("Deleting ArpCache id ". $arp->id);
	    unless ( $self{PRETEND} ){
		$arp->delete;
		$rows_deleted{arpcache}++;
	    }
	}
	$logger->debug("Freeing deleted space in arpcacheentry");
	&optimize_table('arpcacheentry') unless $self{PRETEND};
    }
}

foreach my $table ( keys %rows_deleted ){
    if ( $rows_deleted{$table} ){
	$logger->info(sprintf("A total of %d %s records deleted", 
			      $rows_deleted{$table}, $table));
	# now optimize the table to free up the space from the deleted records
	$logger->debug("Freeing deleted space in $table");
	&optimize_table($table) unless $self{PRETEND};
    }
}
$logger->info(sprintf("$0 total runtime: %s\n", Netdot->sec2dhms(time-$start)));



###########################################################################################
# Subroutines
###########################################################################################

# postgresql and mysql have different commands for cleaning up 
# their tables after a large amount of deletes
sub optimize_table{
    my ($table) = @_;

    if ( $db_type eq 'mysql' ){
        $dbh->do("OPTIMIZE TABLE $table");
    }elsif( $db_type eq 'Pg' ){
        $dbh->do("VACUUM $table");
    }else{
        $logger->warn("Could not optimize table $table. Database $db_type not supported");
    }

    return;
}

# Get table definition (mysql only)
sub get_table_def {
    my $table = shift;
    my $q = $dbh->selectall_arrayref("SHOW CREATE TABLE $table");
    my $def = $q->[0]->[1];
    $def =~ s/AUTO_INCREMENT=[0-9]+/AUTO_INCREMENT=1/;
    $def =~ s/CREATE TABLE `(.*)`/CREATE TABLE `$table`/;
    return $def;
}

sub rotate_tables{
    my (@tables) = @_;

    die "Missing table names" unless scalar @tables;

    # We need DBA privileges here
    my $db_host = Netdot->config->get('DB_HOST');
    my $db_port = Netdot->config->get('DB_PORT');
    my $db_user = Netdot->config->get('DB_DBA');
    my $db_pass = Netdot->config->get('DB_DBA_PASSWORD');
    my $db_db   = Netdot->config->get('DB_DATABASE');

    my $dbh = &dbconnect($db_type, $db_host, $db_port, $db_user, $db_pass, $db_db) 
	|| die ("Cannot connect to database as root");

    $dbh->{AutoCommit} = 0; # make sure autocommit is off so we use transactions
    $dbh->{RaiseError} = 1; # make sure we hear about any problems

    my $timestamp = time;

    my %defs;
    my @statements;
    foreach my $table ( @tables ){
	$defs{$table} = &get_table_def($table);
	push @statements, ("DROP TABLE $table");
    }
    # Re-create the original tables in reverse order
    # to avoid integrity errors
    foreach my $table ( reverse @tables ){
	push @statements, $defs{$table};
    }
    eval {
	foreach my $st ( @statements ){
	    $logger->debug($st);
	    $dbh->do($st);
	}
    };

    my $table_list = join ', ', @tables;
    if ( my $e = $@ ){
	$dbh->rollback;
	die "Error rotating tables $table_list. Changes not commited: $e\n";
    }
    $dbh->commit;
    $logger->info("Tables $table_list rotated successfully");
    # We can turn autocommit back on since the rest of the transactions are basically atomic
    $dbh->{AutoCommit} = 1; 

    &dbdisconnect($dbh);
    return 1;
}


=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

