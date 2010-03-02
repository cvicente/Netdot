#Updates netdot database from version 0.9 to version 1.0
#Author: Parker Coleman

use warnings;
use strict;
use lib "../lib";
use DBUTIL;
use Netdot;
use Netdot::Model;
use Data::Dumper;
my %CONFIG;
$CONFIG{debug}             = 1;
$CONFIG{keep_history}      = 1;
$CONFIG{keep_dependencies} = 0;

foreach my $var ( qw /DB_TYPE DB_HOME DB_HOST DB_PORT DB_DBA DB_DBA_PASSWORD
                  DB_NETDOT_USER DB_NETDOT_PASS DB_DATABASE/ ){
	$CONFIG{$var} = Netdot->config->get($var);
}

#my $dbh = dbconnect($CONFIG{DB_TYPE}, $CONFIG{DB_HOST}, $CONFIG{DB_PORT},
#                        $CONFIG{DB_DBA}, $CONFIG{DB_DBA_PASSWORD}, $CONFIG{DB_DATABASE});

my $dbh = dbconnect($CONFIG{DB_TYPE}, $CONFIG{DB_HOST}, $CONFIG{DB_PORT},
                        $CONFIG{DB_DBA}, $CONFIG{DB_DBA_PASSWORD}, "old_netdot");


$dbh->{AutoCommit} = 1;
$dbh->{RaiseError} = 1;

my $d = $dbh->prepare("SELECT * FROM device");
$d->execute();
my @devices = @{$d->fetchall_arrayref({})};

my $dm = $dbh->prepare("SELECT * FROM devicemodule");
$dm->execute();
my @devicemodules = @{$dm->fetchall_arrayref({})};

my $p = $dbh->prepare("SELECT * FROM product");
$p->execute();
my @products = @{$p->fetchall_arrayref({})};


my $da = $dbh->prepare("SELECT serialnumber FROM device");
$da->execute();
my $d_assets = $da->fetchall_arrayref();
my $dma = $dbh->prepare("SELECT serialnumber FROM devicemodule");
$dma->execute();
my $dm_assets = $dma->fetchall_arrayref();

my @sn = ();
my %sn;

foreach (($d_assets, $dm_assets)){
	foreach(@{$_}){
		my @t = @$_;
		my $k = $t[0];

		if(defined($k)){
	                $k =~ s/^\s+//; #trim leading and trailing whitespace
        	        $k =~ s/\s+$//;

			if($sn{$k}){
				$sn{$k} += 1;
			}
			else{
				$sn{$k} = 1;
			}
		}
	}
}
print Dumper(%sn);
#its easier to just drop the tables we need to change then add them again, rather than 
#putting in a ton of alter statements

#Technically I don't think start transaction is needed at the begenning since 
#autocommit should be set to false, but it couldn't hurt right?
my @statements = (
"DROP TABLE `device`",
"DROP TABLE `devicemodule`",
"ALTER TABLE `product` ADD `mfg_number` varchar(255)",
"CREATE TABLE  `asset` (
  `date_purchased` timestamp NOT NULL DEFAULT '1970-01-01 00:00:01',
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `inventory_number` varchar(255) DEFAULT NULL,
  `maint_contract` int(11) NOT NULL,
  `maint_from` date DEFAULT NULL,
  `maint_until` date DEFAULT NULL,
  `product_id` int(11) DEFAULT NULL,
  `serial_number` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `asset1` (`serial_number`)
) ENGINE=InnoDB;",
"CREATE TABLE `device` (
  `aliases` varchar(255) DEFAULT NULL,
  `asset_id` int(11) NOT NULL,
  `auto_dns` tinyint(1) NOT NULL,
  `bgpid` varchar(64) DEFAULT NULL,
  `bgplocalas` int(11) DEFAULT NULL,
  `canautoupdate` tinyint(1) NOT NULL,
  `collect_arp` tinyint(1) NOT NULL,
  `collect_fwt` tinyint(1) NOT NULL,
  `collect_stp` tinyint(1) NOT NULL,
  `community` varchar(64) DEFAULT NULL,
  `custom_serial` varchar(64) DEFAULT NULL,
  `customer_managed` tinyint(1) NOT NULL,
  `date_installed` timestamp NOT NULL DEFAULT '1970-01-01 00:00:01',
  `down_from` date DEFAULT NULL,
  `down_until` date DEFAULT NULL,
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `info` blob,
  `ipforwarding` tinyint(1) NOT NULL,
  `last_arp` timestamp NOT NULL DEFAULT '1970-01-01 00:00:01',
  `last_fwt` timestamp NOT NULL DEFAULT '1970-01-01 00:00:01',
  `last_updated` timestamp NOT NULL DEFAULT '1970-01-01 00:00:01',
  `layers` varchar(8) DEFAULT NULL,
  `monitor_config` tinyint(1) NOT NULL,
  `monitor_config_group` varchar(64) DEFAULT NULL,
  `monitored` tinyint(1) NOT NULL,
  `monitoring_path_cost` int(11) DEFAULT NULL,
  `monitorstatus` int(11) NOT NULL,
  `name` int(11) NOT NULL,
  `oobname` varchar(255) DEFAULT NULL,
  `oobnumber` varchar(32) DEFAULT NULL,
  `os` varchar(128) DEFAULT NULL,
  `owner` int(11) NOT NULL,
  `physaddr` int(11) NOT NULL,
  `rack` varchar(32) DEFAULT NULL,
  `room` int(11) NOT NULL,
  `site` int(11) NOT NULL,
  `snmp_authkey` varchar(255) DEFAULT NULL,
  `snmp_authprotocol` varchar(32) DEFAULT NULL,
  `snmp_bulk` tinyint(1) NOT NULL,
  `snmp_managed` tinyint(1) NOT NULL,
  `snmp_polling` tinyint(1) NOT NULL,
  `snmp_privkey` varchar(255) DEFAULT NULL,
  `snmp_privprotocol` varchar(32) DEFAULT NULL,
  `snmp_securitylevel` varchar(32) DEFAULT NULL,
  `snmp_securityname` varchar(255) DEFAULT NULL,
  `snmp_target` int(11) NOT NULL,
  `snmp_version` int(11) DEFAULT NULL,
  `stp_enabled` tinyint(1) NOT NULL,
  `stp_mst_digest` varchar(255) DEFAULT NULL,
  `stp_mst_region` varchar(128) DEFAULT NULL,
  `stp_mst_rev` int(11) DEFAULT NULL,
  `stp_type` varchar(128) DEFAULT NULL,
  `sysdescription` varchar(255) DEFAULT NULL,
  `syslocation` varchar(255) DEFAULT NULL,
  `sysname` varchar(255) DEFAULT NULL,
  `used_by` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `device1` (`name`),
  KEY `Device2` (`physaddr`),
  KEY `Device3` (`used_by`),
  KEY `Device4` (`owner`),
  KEY `Device5` (`os`),
  KEY `Device6` (`sysname`),
  KEY `Device7` (`down_from`),
  KEY `Device8` (`down_until`)
) ENGINE=InnoDB;",
"CREATE TABLE  `devicemodule` (
  `asset_id` int(11) NOT NULL,
  `class` varchar(128) DEFAULT NULL,
  `contained_in` int(11) DEFAULT NULL,
  `date_installed` timestamp NOT NULL DEFAULT '1970-01-01 00:00:01',
  `description` varchar(255) DEFAULT NULL,
  `device` int(11) NOT NULL,
  `fru` tinyint(1) NOT NULL,
  `fw_rev` varchar(128) DEFAULT NULL,
  `hw_rev` varchar(128) DEFAULT NULL,
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `last_updated` timestamp NOT NULL DEFAULT '1970-01-01 00:00:01',
  `model` varchar(128) DEFAULT NULL,
  `name` varchar(128) DEFAULT NULL,
  `number` int(11) NOT NULL,
  `pos` int(11) DEFAULT NULL,
  `sw_rev` varchar(128) DEFAULT NULL,
  `type` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `devicemodule1` (`device`,`number`)
) ENGINE=InnoDB;");

my @removed_device_keys = ('serialnumber', 'product', 'maint_contract', 'maint_from', 'maint_until', 'inventorynumber');
my $current_asset_id = 1;
foreach my $entry_ref (@devices){
	my %e = %$entry_ref;

        my $snkey = $e{'serialnumber'};
 	
	if(defined($snkey)){
		$snkey =~ s/^\s+//; #trim leading and trailing whitespace
	        $snkey =~ s/\s+$//;
	}
	
        if(defined $snkey && $sn{$snkey} && $sn{$snkey} > 1){ #if this serialnumber shows up more than once in the database...
                $e{'serialnumber'} = $e{'serialnumber'}."[".$sn{$snkey}."]"; #append a number to it
                $sn{$snkey} -= 1;
        }

	my (@value_names, @values);
	foreach my $k (keys %e){
                my $wsr = $e{$k};
                if(defined($e{$k})){
                        $wsr =~ s/^\s+//; #trim leading and trailing whitespace
                        $wsr =~ s/\s+$//;
                        $e{$k} =~ s/\"/\\\"/g; #escape any " characters that might be in entry
                }
                if(! defined($e{$k}) || $wsr eq ""){
                        $e{$k} = "NULL";
                }
                else{
                        $e{$k} = "\"".$e{$k}."\"";
                }

		if(! grep(/^$k$/, @removed_device_keys)){
			push(@value_names, $k);
			push(@values, $e{$k} );
		}
	}
	push(@value_names, "asset_id");
	push(@values, $current_asset_id);

	my $val_name_str = "(".join(",",@value_names).") ";
        my $val_str = "(".join(",",@values).")";
	push(@statements, "INSERT INTO device $val_name_str VALUES $val_str");
	
	push(@statements, "INSERT INTO asset VALUES(NULL, $current_asset_id, $e{'inventorynumber'}, $e{'maint_contract'}, $e{'maint_from'}, $e{'maint_until'}, $e{'product'}, $e{'serialnumber'})");
	$current_asset_id += 1;
}
#two or more, use a for....get about it who cares :/
foreach my $entry_ref(@devicemodules){
	my %e = %$entry_ref;

        my $snkey = $e{'serialnumber'};

        if(defined($snkey)){
                $snkey =~ s/^\s+//; #trim leading and trailing whitespace
                $snkey =~ s/\s+$//;
        }

        if(defined $snkey && $sn{$snkey} && $sn{$snkey} > 1){ #if this serialnumber shows up more than once in the database...
                $e{'serialnumber'} = $e{'serialnumber'}."[".$sn{$snkey}."]"; #append a number to it
                $sn{$snkey} -= 1;
        }

	my (@value_names, @values);
	foreach my $k (keys %e){
               	my $wsr = $e{$k};
		if(defined($e{$k})){
			$wsr =~ s/^\s+//; #trim leading and trailing whitespace
			$wsr =~ s/\s+$//;
			$e{$k} =~ s/\"/\\\"/g; #escape any " characters that might be in entry
                }
		if(! defined($e{$k}) || $wsr eq ""){
                        $e{$k} = "NULL";
                }
                else{
                        $e{$k} = "\"".$e{$k}."\"";
                }
                if(! grep(/^$k$/, @removed_device_keys)){
                        push(@value_names, $k);
                        push(@values, $e{$k} );
                }

        }
        push(@value_names, "asset_id");
        push(@values, $current_asset_id);
        my $val_name_str = "(".join(",",@value_names).") ";
        my $val_str = "(".join(",",@values).")";
        push(@statements, "INSERT INTO devicemodule $val_name_str VALUES $val_str");
        push(@statements, "INSERT INTO asset VALUES(NULL, $current_asset_id, $e{'inventorynumber'}, $e{'maint_contract'}, $e{'maint_from'}, $e{'maint_until'}, NULL, $e{'serialnumber'})");
        $current_asset_id += 1;
}

foreach (@statements){
	eval{
		#print "$_ \n";
		$dbh->do($_);
	};
	if($@){
		print "Error detected: $@ \n On statement: $_ \n Attempting to roll back \n";
		exit(1);
	}
}
$dbh->disconnect();
