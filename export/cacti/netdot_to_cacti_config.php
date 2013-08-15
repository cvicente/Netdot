<?php
/* Netdot database connection information */

$netdot_db_type     = 'mysql';
$netdot_db_database = 'netdot';
$netdot_db_user     = 'netdot_user';
$netdot_db_pass     = 'netdot_pass';
$netdot_db_server   = 'localhost';
$netdot_db_port     = '';

/* This will remove the given domain name from the host names */
$strip_domain = 'localdomain';
$group_source = 'used_by';


/* 
 Define various patterns for Host Template assignments.
 The hash values must match exactly the output from
 php -q add_device.php --list-host-templates
*/

/* Match Product's sysobjectid field */

// (Maches HP Procurve switches)
//$oid_to_host_template = array('/1\.3\.6\.1\.4\.1\.11\.2\.3\.7\.11/' => '9',
//			      );

/* Match Product name */
$product_to_host_template = array('/windows/i'  => '7',
				  '/net-snmp/i' => '3',
				  );

/* Match Manufacturer name */
$mfg_to_host_template = array('/cisco/i' => '5');

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
$device_threads       = 1;

$sortMethods    = array('manual' => 1, 'alpha' => 2, 'natural' => 3, 'numeric' => 4);
$nodeTypes      = array('header' => 1, 'graph' => 2, 'host' => 3);
$hostGroupStyle = 2;    /* 1 = Graph Template,  2 = Data Query Index */

/* 
 $dsGraphs is a data structure containing the necessary information to build 'ds' type graphs
 See the documentation on Cacti's CLI commands for more detailed explanations, specifically:

   php -q add_device.php --list-host-templates
   php -q add_graphs.php --list-snmp-queries
   php -q add_graphs.php --list-graph-templates
   or: 
   select * from snmp_query_graph;
   select * from graph_templates;
 
 Syntax:
 $dsGraphs["<HostTemplateID>|any>"]["snmpQueryId"]  = <SNMP Query ID>
 $dsGraphs["<HostTemplateID>|any>"]["queryTypeIds"] = array(<query_type_id> => <template_id>)
 $dsGraphs["any"]["snmpCriteria"] = <SQL criteria>

*/

/* ---------------------------------------------------------------------------------- */
/* SNMP - Interface Statistics 
*/


$dsGraphs["any"]["64-bit Interface Statistics"]["snmpQueryId"]  = 1;
$dsGraphs["any"]["64-bit Interface Statistics"]["snmpCriteria"] = "field_name='ifHighSpeed' ";
$dsGraphs["any"]["64-bit Interface Statistics"]["queryTypeIds"] = array(2  => 22,  // In/Out Errors/Discarded Packets
									3  => 24,  // In/Out Non-Unicast Packets
									4  => 23,  // In/Out Unicast Packets
									14 => 2,   // In/Out Bits (64-bit Counters)
									);

// Here, the plan is that if the above criteria isn't met, then these graphs will be created instead
// Tests so far indicate that both types of graphs will not be created for the same host
$dsGraphs["any"]["Interface Statistics"]["snmpQueryId"] = 1;
$dsGraphs["any"]["Interface Statistics"]["snmpCriteria"] = "field_name='ifSpeed'";
$dsGraphs["any"]["Interface Statistics"]["queryTypeIds"] = array(2  => 22,  // In/Out Errors/Discarded Packets
								 3  => 24,  // In/Out Non-Unicast Packets
								 4  => 23,  // In/Out Unicast Packets
								 13 => 2,   // In/Out Bits
								 );

// Ignore interfaces matching these patterns in their names
// Notice that we use the '%' wildcard for SQL
$ignoreIntsLike = array('lo%', 'ipfw%', 'usbus%', 'plip%', 'dwdm%', '127.0.0.%');

/* Host MIB Mounted Partitions Stats */
$dsGraphs["3"]["Mounted Partitions"]["snmpQueryId"]  = 8;
$dsGraphs["3"]["Mounted Partitions"]["snmpCriteria"] = "field_name='hrStorageIndex'";
$dsGraphs["3"]["Mounted Partitions"]["queryTypeIds"] = array(18 => 26); // Host MIB - Available Disk Space

/* Cisco EnvMon Temperature */
$dsGraphs["5"]["EnvMon Temp"]["snmpQueryId"]  = 10;
$dsGraphs["5"]["EnvMon Temp"]["snmpCriteria"] = "field_name='TempStatusDescr'";
$dsGraphs["5"]["EnvMon Temp"]["queryTypeIds"] = array(23 => 40);

/* ---------------------------------------------------------------------------------- */
/* 
    $cgGraphs is a data structure containing the necessary information to build 'cg' type graphs.
    See the documentation on Cacti's CLI commands for more detailed explanations, specifically:

        php -q add_graphs.php --list-graph-templates

    Syntax:
    $cgGraphs["<Host Template ID>"]["<Description>"] = <Graph Template ID>
        <Host Template ID> := ID or keyword "any"
	<Description>      := Text description (this is arbitrary)
*/

/* Ping latency for every node */
$cgGraphs["any"]["Unix - Ping Latency"] = 7;

/* ucd/net specific graphs */
$cgGraphs["3"]["ucd/net - CPU"]  = 4;
$cgGraphs["3"]["ucd/net - Load"] = 11;
$cgGraphs["3"]["ucd/net - Mem"]  = 13;

/* Cisco CPU Usage*/
$cgGraphs["5"]["Cisco - CPU Usage"] = 18;
$cgGraphs["5"]["Cisco - Mem Usage"] = 43;

/* HP Procurve CPU, Memory and MAC address count */
//$cgGraphs["9"]["Procurve MAC Count"] = 37;
//$cgGraphs["9"]["Procurve MEM Usage"] = 38;
//$cgGraphs["9"]["Procurve CPU Usage"] = 39;

?>
