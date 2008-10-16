#!/usr/bin/php -q
<?php
/*
    Configure Cacti using Netdot information
    This script uses Cacti's API libraries and information from Netdot to add and update
    hosts, graphs and trees.
*/

/* do NOT run this script through a web browser */
if (!isset($_SERVER["argv"][0]) || isset($_SERVER['REQUEST_METHOD'])  || isset($_SERVER['REMOTE_ADDR'])) {
  die("<br><strong>This script is only meant to run at the command line.</strong>");
 }

/* We are not talking to the browser */
$no_http_headers = true;

include(dirname(__FILE__)."/../include/global.php");
include_once($config["base_path"]."/lib/api_automation_tools.php");
include_once($config["base_path"]."/lib/utility.php");
include_once($config["base_path"]."/lib/sort.php");
include_once($config["base_path"]."/lib/template.php");
include_once($config["base_path"]."/lib/api_data_source.php");
include_once($config["base_path"]."/lib/api_graph.php");
include_once($config["base_path"]."/lib/snmp.php");
include_once($config["base_path"]."/lib/data_query.php");
include_once($config["base_path"]."/lib/api_device.php");
include_once($config["base_path"].'/lib/tree.php');

/* process calling arguments */
$parms = $_SERVER["argv"];
array_shift($parms);

if (sizeof($parms)) {
  
  /* parameter defaults */
  $debug         = 0;
  $no_graphs     = 0;
  
  /* device defaults */
  $description          = "";
  $ip                   = "";
  $template_id          = 0;
  $community            = "public";
  $snmp_ver             = 1;
  $disable              = 0;
  $notes                = "";
  $snmp_username        = "";
  $snmp_password        = "";
  $snmp_auth_protocol   = "MD5";
  $snmp_priv_passphrase = "";
  $snmp_priv_protocol   = "DES";
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
  $hostGroupStyle = 1;    /* 1 = Graph Template,  2 = Data Query Index */
  
  foreach($parms as $parameter) {
    @list($arg, $value) = @explode("=", $parameter);
    
    switch ($arg) {
    case "-h":
      display_help();
      exit(1);
      break;
    case "--help":
      display_help();
      exit(1);
      break;
    case "-d":
      $debug = TRUE;
      break;
    case "--debug":
      $debug = TRUE;
      break;
    case "--no-graphs":
      $no_graphs = TRUE;
      break;
    case "--file":
      $file = trim($value);
      break;
    default:
      echo "ERROR: Invalid Argument: ($arg)\n\n";
      display_help();
      exit(1);
    }
  }
 }else{
  display_help();
  exit(0);
 }

/* Build some data structures */
$hostTemplates    = getHostTemplates();
$hostDescriptions = getHostsByDescription();
$addresses        = getAddresses();
$hostIds          = getHosts();
$graphTemplates   = getGraphTemplates();
$snmpQueries      = getSNMPQueries();

/* We store the Netdot id in the notes field, which makes sure we keep all the device
 information even if the hostname and/or IP change */

$hostsByNetdotId = array();
$hq = db_fetch_assoc("SELECT id, notes FROM host WHERE notes LIKE '%netdot_id%'");
foreach ($hq as $row){
  if ( preg_match('/netdot_id:(\d+)/', $row["notes"], $matches) ){
    $nid = $matches[1];
    $hostsByNetdotId[$nid] = $row["id"];
  }
}

/* ----------------------------------------------------------------------------------------------------- */
/* Open file and build multi-dimensional array */
$lines = file($file);
foreach ($lines as $line) {
  @list($netdot_id, $description, $ip, $template_id, $group, $disable, $snmp_ver, $community) = @explode(";", $line);
  $community = trim($community);
  $groups[$group][$description]["netdot_id"]   = $netdot_id;
  $groups[$group][$description]["ip"]          = $ip;
  $groups[$group][$description]["template_id"] = $template_id;
  $groups[$group][$description]["disable"]     = $disable;
  $groups[$group][$description]["snmp_ver"]    = $snmp_ver;
  $groups[$group][$description]["community"]   = $community;
}

/* Make sure we have a netdot tree */
$treeId = db_fetch_cell("SELECT id FROM graph_tree WHERE name = 'Netdot'");
if ($treeId) {
  if ($debug){
    echo "DEBUG: Netdot tree already exists - id: ($treeId)\n";
  }
 }else{
  $treeOpts = array();
  $treeOpts["id"]        = 0; # Zero means create a new one rather than save over an existing one
  $treeOpts["name"]      = "Netdot";
  $treeOpts["sort_type"] = $sortMethods["alpha"];
  $treeId = sql_save($treeOpts, "graph_tree");
  sort_tree(SORT_TYPE_TREE, $treeId, $treeOpts["sort_type"]);
  echo "Created Netdot Tree - id: ($treeId)\n";
 }

/* Store all header and host nodes for faster lookups */
$hostNodes   = array();
$headerNodes = array();
$treeNodes = db_fetch_assoc("SELECT id, title, host_id FROM graph_tree_items WHERE graph_tree_id=$treeId");
foreach ($treeNodes as $row){
  if ($row["host_id"] != 0){
    $hostNodes[$row["host_id"]] = $row["id"];
  }elseif($row["title"] != ""){
    $headerNodes[$row["title"]] = $row["id"];
  }
}

/* ----------------------------------------------------------------------------------------------------- */

foreach ($groups as $group => $hosts){
  
  /* Make sure we have a header for this group */
  if (isset($headerNodes[$group])){
    $headerId = $headerNodes[$group];
    unset($headerNodes[$group]);
  }
  if ($headerId){
    if ($debug){
      echo "$group: Header already exists - id: ($headerId)\n";
    }
  }else{
    $headerId = api_tree_item_save(0, $treeId, $nodeTypes["header"], $treeId, $group, 0, 0, 0, $hostGroupStyle, 1, false);
    echo "$group: Added Header id: ($headerId)\n";
  }

  foreach ($hosts as $description => $attr){
    $netdot_id   = $attr["netdot_id"];
    $ip          = $attr["ip"];
    $template_id = $attr["template_id"];
    $disable     = $attr["disable"];
    $snmp_ver    = $attr["snmp_ver"];
    $community   = $attr["community"];
    
    $hostId = 0;
    
    /* Check if Device exists */

    if (isset($hostsByNetdotId[$netdot_id])) {
      $hostId = $hostsByNetdotId[$netdot_id];
      if ($debug){
	echo "DEBUG: Device with netdot_id $netdot_id found: ($description), id: ($hostId)\n";
      }
    }elseif (isset($hostDescriptions[$description])) {
      $hostId = $hostDescriptions[$description];
      if ($debug){
	echo "DEBUG: Device $description found: ($hostId)\n";
      }

    }elseif (isset($addresses[$ip])) {
      /* Another device has this ip */
      echo "ERROR: This IP already exists in the database ($ip) device-id: (" . $addresses[$ip] . ")\n";
      continue;
    }
    
    /* Validate template_id */
    if (!isset($hostTemplates[$template_id])) {
      echo "ERROR: Unknown template id ($template_id)\n";
      exit(1);
    }

    /* validate snmp version */
    if ($snmp_ver != "1" && $snmp_ver != "2" && $snmp_ver != "3") {
      echo "ERROR: Invalid snmp version ($snmp_ver)\n";
      exit(1);
    }

    /* validate the disable state */
    if ($disable != 1 && $disable != 0) {
      echo "ERROR: Invalid enable flag: $disable\n";
      exit(1);
    }
    if ($disable == 0) {
      $disable = "";
    }else{
      $disable = "on";
    }
    
    $notes = "netdot_id:" . $netdot_id;

    /* ----------------------------------------------------------------------------------------------------- */
    /* Add or Update Device */

    if ($hostId){
      if ($debug){
	echo "DEBUG: $description: Updating device id $hostId ($ip) template \"" . $hostTemplates[$template_id] . "\" using SNMP v$snmp_ver with community \"$community\"\n";
      }
    }else{
      echo "$description: Adding device ($ip) template \"" . $hostTemplates[$template_id] . "\" using SNMP v$snmp_ver with community \"$community\"\n";
    }
    $hostId = api_device_save($hostId, $template_id, $description, $ip,
			      $community, $snmp_ver, $snmp_username, $snmp_password,
			      $snmp_port, $snmp_timeout, $disable, $avail, $ping_method,
			      $ping_port, $ping_timeout, $ping_retries, $notes,
			      $snmp_auth_protocol, $snmp_priv_passphrase,
			      $snmp_priv_protocol, $snmp_context, $max_oids);
  
    if (is_error_message()) {
      echo "ERROR: $description: Failed device save\n";
      exit(1);
    }else {
      if ($debug){
	echo "DEBUG: $description: device saved: ($hostId)\n";
      }
    }

    /* ----------------------------------------------------------------------------------------------------- */
    /* Add node to tree */

    if (isset($hostNodes[$hostId])){
      $nodeId = $hostNodes[$hostId];
      unset($hostNodes[$hostId]);
    }
    if ($nodeId){
      if ($debug){
	echo "DEBUG: $description: host node already exists - id: ($nodeId)\n";
      }
      /* Make sure that it is under the right header, has the right hostId, etc */
      api_tree_item_save($nodeId, $treeId, $nodeTypes["host"], $headerId, '', 0, 0, $hostId, $hostGroupStyle, 1, false);
    }else{
      $nodeId = api_tree_item_save(0, $treeId, $nodeTypes["host"], $headerId, '', 0, 0, $hostId, $hostGroupStyle, 1, false);
      echo "$description: Added host node - id: ($nodeId)\n";
    }

    /* Skip creating graphs if told to */
    if ($no_graphs){
      continue;
    }
  
    /* Do not bother creating graphs if device is disabled */
    if ($disable == "on"){
      continue;
    }

    /* ----------------------------------------------------------------------------------------------------- */
    /* Add Graphs */

    /* Interface stats */
    
    $dsGraph["hostId"]        = $hostId;
    $dsGraph["snmpQueryId"]   = 1;              # SNMP - Interface Statistics
    $dsGraph["snmpField"]     = "ifOperStatus";
    $dsGraph["snmpValue"]     = 'Up';
    
    /* query_type_id => template_id */
    $dsGraph["queryTypeIds"] = array(2  => 22,  # In/Out Errors/Discarded Packets
				     3  => 24,  # In/Out Non-Unicast Packets
				     4  => 23,  # In/Out Unicast Packets
				     13 => 2,   # In/Out Bits
				     );
    create_ds_graphs($dsGraph);
  }

}

/* ----------------------------------------------------------------------------------------------------- */
/* Clean up stale groups and nodes in the tree */

foreach($hostNodes as $oldNode){
  if ($debug){
    echo "DEBUG: Deleting old tree node: $oldNode";
  } 
  db_execute("DELETE FROM graph_tree_items WHERE id=$oldNode");
}
foreach($headerNodes as $oldHeader){
  if ($debug){
    echo "DEBUG: Deleting old tree header: $oldHeader";
  } 
  db_execute("DELETE FROM graph_tree_items WHERE id=$oldHeader");
}


/* ----------------------------------------------------------------------------------------------------- */
// Subroutines
/* ----------------------------------------------------------------------------------------------------- */
function create_ds_graphs($args) {
  global $hostIds, $debug;

  $hostId       = $args["hostId"];
  $queryTypeIds = $args["queryTypeIds"];

  $snmpQueryArray = array();
  $snmpQueryArray["snmp_query_id"] = $args["snmpQueryId"];
  $snmpQueryArray["snmp_index_on"] = get_best_data_query_index_type($hostId, $args["snmpQueryId"]);

  $snmpIndexes = db_fetch_assoc("SELECT snmp_index
                                 FROM   host_snmp_cache
                                 WHERE  host_id=" . $hostId . "
                                    AND snmp_query_id=" . $args["snmpQueryId"] . "
                                    AND field_name='" . $args["snmpField"] . "'
                                    AND field_value='" . $args["snmpValue"] . "'");
  
  
  if (sizeof($snmpIndexes)) {
    $graphsCreated = 0;
    $graphs = db_fetch_assoc("SELECT id, snmp_index, graph_template_id
                              FROM   graph_local
                              WHERE  host_id=$hostId
                                AND  snmp_query_id='" . $args["snmpQueryId"] . "'");
    
    foreach ($graphs as $row){
      $graphsBySnmpIndex[$row["snmp_index"]][$row["graph_template_id"]] = $row["id"];
    }

    foreach ($queryTypeIds as $queryTypeId => $templateId) {
      $snmpQueryArray["snmp_query_graph_id"] = $queryTypeId;

      foreach ($snmpIndexes as $row) {
	$snmpIndex = $row["snmp_index"];
	if ( isset($graphsBySnmpIndex[$snmpIndex][$templateId]) ){
	  $graphId = $graphsBySnmpIndex[$snmpIndex][$templateId];
	  if ($debug){
	    echo "DEBUG: " . $hostIds[$hostId]["description"] . ": Graph already exists: ($graphId)\n";
	  }
	  continue;
	}
	$empty = array();
	$returnArray = create_complete_graph_from_template($templateId, $hostId, $snmpQueryArray, $empty);
	echo $hostIds[$hostId]["description"] . ": Added Graph id: (" . $returnArray["local_graph_id"] . ")\n";
	$graphsCreated++;
      }
    }
    if($graphsCreated > 0){
      push_out_host($hostId,0);
    }

  }else{
    echo "WARN: Could not find snmp-field " . $args["snmpField"] . " (" . $args["snmpValue"] . ") for host-id " . $hostId . " (" . $hostIds[$hostId]["description"] . ")\n";
  }
}


function display_help() {
  echo "\n netdot_to_cacti.php - Part of the Netdot package (http://netdot.uoregon.edu)\n\n";
  echo "Command line utility to add and update devices, graphs and trees in Cacti, based on Netdot information\n\n";
  echo "Locate this script in your cacti directory (e.g. /var/www/cacti/) and run periodically via cron\n";
  echo "\n";
  echo "usage: netdot_to_cacti.php --file=<filename> [--no-graphs] [-d|--debug] [-h|-help]\n";
  echo "Required:\n";
  echo "    --file         File name with Netdot information\n";
  echo "                   The file should contain a semi-colon separated list of fields:\n";
  echo "                   netdot_id;description;ip;template_id;group;disable;snmp_ver;community)\n";
  echo "\n";
  echo "Optional:\n";
  echo "    --no-graphs    Do not add graphs, only update devices and tree\n";
  echo "    -d|--debug     Enable debugging output\n";
  echo "    -h|--help      Display help and exit\n";

}

?>
