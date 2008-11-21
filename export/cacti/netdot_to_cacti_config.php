<?php
/* Netdot database connection information */

$netdot_db_type     = 'mysql';
$netdot_db_database = 'netdot';
$netdot_db_user     = 'netdot_user';
$netdot_db_pass     = 'netdot_pass';
$netdot_db_server   = 'localhost';
$netdot_db_port     = '';

/* This will remove the given domain name from the host name */
$strip_domain = 'localdomain';
$group_source = 'used_by';

/* Make sure this matches the template values in your Cacti setup */
$templates = array('None'                       => 0,
		   'Generic SNMP-enabled Host'  => 1,
		   'ucd/net SNMP Host'          => 3,
		   'Karlnet Wireless Bridge'    => 4,
		   'Cisco Router'               => 5,
		   'Netware 4/5 Server'         => 6,
		   'Windows 2000/XP Host'       => 7,
		   'Local Linux Machine'        => 8,
		   );

/* parameter defaults */
$debug         = 0;
$no_graphs     = 0;

/* device defaults */
$template_id          = 0;
$community            = "public";
$snmp_ver             = 1;
$disable              = 0;
$snmp_auth_protocol   = "MD5";
$snmp_priv_passphrase = "";
$snmp_priv_protocol   = "DES";
$snmp_username        = "";
$snmp_password        = "";
$snmp_context         = "";
$snmp_port            = 161;
$snmp_timeout         = 500;
$avail                = 2;
$ping_method          = 3;
$ping_port            = 23;
$ping_timeout         = 500;
$ping_retries         = 2;
$max_oids             = 10;

$sortMethods    = array('manual' => 1, 'alpha' => 2, 'natural' => 3, 'numeric' => 4);
$nodeTypes      = array('header' => 1, 'graph' => 2, 'host' => 3);
$hostGroupStyle = 2;    /* 1 = Graph Template,  2 = Data Query Index */

/* 
    $dsGraphs is a data structure containing the necessary information to build ds graphs
    See the documentation on Cacti's CLI commands for more detailed explanations
*/

/* ---------------------------------------------------------------------------------- */
/* SNMP - Interface Statistics */
$dsGraphs["Interfaces"]["snmpQueryId"] = 1;

// Select a subset of the interfaces. Not setting these will create graphs for *all* interfaces
// $dsGraphs["Interfaces"]["snmpField"] = 'ifOperStatus';
// $dsGraphs["Interfaces"]["snmpValue"] = 'Up';

// query_type_id => template_id
$dsGraphs["Interfaces"]["queryTypeIds"] = array(2  => 22,  # In/Out Errors/Discarded Packets
						3  => 24,  # In/Out Non-Unicast Packets
						4  => 23,  # In/Out Unicast Packets
						13 => 2,   # In/Out Bits
						);


?>
