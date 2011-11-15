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
include("netdot_to_cacti_config.php");
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
    default:
      echo "ERROR: Invalid Argument: ($arg)\n\n";
      display_help();
      exit(1);
    }
  }

/* Build some data structures */
$hostTemplates    = getHostTemplates();
$hostDescriptions = getHostsByDescription();
$addresses        = getAddresses();
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
/* Query Netdot and build multi-dimensional array */

$netdot_db = NewADOConnection($netdot_db_type);
$netdot_db->Connect($netdot_db_server, $netdot_db_user, $netdot_db_pass, $netdot_db_database);
if (!$netdot_db) {
  echo "Connect failed\n";
  exit(1);
 }

$q = $netdot_db->Execute("
                SELECT     rr.name, zone.name, ipblock.address, site.name, p.name, p.sysobjectid, pt.name, 
                           d.id, d.snmp_managed, d.snmp_polling, d.community, d.snmp_version, e.name, m.name 
                FROM      rr, zone, producttype pt, device d
                LEFT JOIN (site) ON (d.site=site.id)
                LEFT JOIN (ipblock) ON (d.snmp_target=ipblock.id)
                LEFT JOIN (entity e) ON (d.used_by=e.id),
                           product p
                LEFT JOIN (entity m) ON (p.manufacturer=m.id)
                WHERE      d.name=rr.id
                  AND      rr.zone=zone.id
                  AND      d.product=p.id
                  AND      p.type=pt.id
                ORDER BY   rr.name;
");

if (!$q) {
  print "DB Error: ".$netdot_db->ErrorMsg();
  exit (1);
 }

while ($row = $q->FetchRow()) {
  list($name, $domain, $iaddress, $site, $product, $sysobjectid, $ptype, 
       $netdot_id, $managed, $enabled, $community, $version, $used_by, $mfg) = $row; 

  if (!$managed) {
    continue;
  }
  $host = $name . "." . $domain;
  if ($iaddress){
    $address = long2ip($iaddress);
  }else{
    $address = $host;
  }
  # Strip domain name from host name
  $host = preg_replace("/(.*)\.$strip_domain/", "$1", $host);

  if ( $group_source == 'used_by' ){
    $group = $used_by;
  }elseif ( $group_source == 'site' ){
    $group = $site;
  }
  if (!$group){
    $group = 'unknown';
  }
  $group = preg_replace('/\s+/', '_', $group);
  if (!$mfg){
    $mfg = 'unknown';
  }
  if (!$ptype){
    $ptype = 'unknown';
  }
  if (!$version){
    $version = 2;
  }
  if (!$community){
    $community = "public";
  }
  $disabled = ($enabled)? 0 : 1;
  
  // Try to assign a template
  $template_id = "";
  
  if (isset($oid_to_host_template)){
    foreach ($oid_to_host_template as $pattern => $t_id){
      if ( preg_match($pattern, $sysobjectid) ){
	$template_id = $t_id;
	debug("$host: Assinging template $t_id");
	break;
      }else{
	debug("$host: $product does not match $pattern");
      }
    }
  }
  if ($template_id == "" && isset($product_to_host_template)){
    foreach ($product_to_host_template as $pattern => $t_id){
      if ( preg_match($pattern, $product) ){
	$template_id = $t_id;
	debug("$host: Assinging template $t_id");
	break;
      }else{
	debug("$host: $product does not match $pattern");
      }
    }
  }
  if ($template_id == "" && isset($mfg_to_host_template)){
    foreach ($mfg_to_host_template as $pattern => $t_id){
      if ( preg_match($pattern, $mfg) ){
	$template_id = $t_id;
	debug("$host: Assinging template $t_id");
	break;
      }else{
	debug("$host: $mfg does not match $pattern");
      }
    }
  }
  if ($template_id == ""){
    $template_id = 1;
  }

  $community = trim($community);

  $groups[$group][$host]["netdot_id"]   = $netdot_id;
  $groups[$group][$host]["ip"]          = $address;
  $groups[$group][$host]["template_id"] = $template_id;
  $groups[$group][$host]["disable"]     = $disable;
  $groups[$group][$host]["snmp_ver"]    = $version;
  $groups[$group][$host]["community"]   = $community;

 }

/* ----------------------------------------------------------------------------------------------------- */

/* Make sure we have a netdot tree */
$treeId = db_fetch_cell("SELECT id FROM graph_tree WHERE name = 'Netdot'");
if ($treeId) {
  debug("Netdot tree already exists - id: ($treeId)");
 }else{
  $treeOpts = array();
  $treeOpts["id"]        = 0; # Zero means create a new one rather than save over an existing one
  $treeOpts["name"]      = "Netdot";
  $treeOpts["sort_type"] = $sortMethods["alpha"];
  $treeId = sql_save($treeOpts, "graph_tree");
  sort_tree(SORT_TYPE_TREE, $treeId, $treeOpts["sort_type"]);
  echo "Created Netdot Tree - id: $treeId\n";
 }

/* Store all header and host nodes for faster lookups */
$hostNodes   = array();
$headerNodes = array();
$treeNodes   = db_fetch_assoc("SELECT id, title, host_id FROM graph_tree_items WHERE graph_tree_id=$treeId");
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
    debug("$group: Header already exists - id: ($headerId)");
    unset($headerNodes[$group]);
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
      debug("Device with netdot_id $netdot_id found: ($description), id: ($hostId)");
    }elseif (isset($hostDescriptions[$description])) {
      $hostId = $hostDescriptions[$description];
      debug("Device $description found: ($hostId)");
      
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
      debug("$description: Updating device id $hostId ($description) template \"" . $hostTemplates[$template_id] . "\" using SNMP v$snmp_ver with community \"$community\"");
    }else{

      /* Do not bother creating device if it is disabled */
      if ($disable == "on"){
	continue;
      }
      
      echo "$description: Adding device ($description) template \"" . $hostTemplates[$template_id] . "\" using SNMP v$snmp_ver with community \"$community\"\n";
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
      debug("$description: device saved: $hostId");
    }

    /* ----------------------------------------------------------------------------------------------------- */
    /* Add node to tree */

    $nodeId = 0;

    if (isset($hostNodes[$hostId])){
      $nodeId = $hostNodes[$hostId];
      unset($hostNodes[$hostId]);
    }
    if ($nodeId){
      debug("$description: host node already exists - id: ($nodeId)");
      /* Make sure that it is under the right header, has the right hostId, etc */
      api_tree_item_save($nodeId, $treeId, $nodeTypes["host"], $headerId, '', 0, 0, $hostId, $hostGroupStyle, 1, false);
    }else{
      $nodeId = api_tree_item_save(0, $treeId, $nodeTypes["host"], $headerId, '', 0, 0, $hostId, $hostGroupStyle, 1, false);
      echo "$description: Added host node: $nodeId\n";
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
    /* Re-index */

    /* determine data queries to rerun */
    $data_queries = db_fetch_assoc("SELECT host_id, snmp_query_id FROM host_snmp_query WHERE host_id='$hostId'");
    debug("$description: There are '" . sizeof($data_queries) . "' data queries to run");
    
    foreach ($data_queries as $data_query) {
      run_data_query($data_query["host_id"], $data_query["snmp_query_id"]);
    }


    /* ----------------------------------------------------------------------------------------------------- */
    /* Add Graphs */

    $dsGraphsCreated = 0;
    
    foreach($dsGraphs as $HostTemplateId => $GraphGroup){
      if ($HostTemplateId != "any") {
	if ($template_id != $HostTemplateId){
	  continue;
	}
      }
      foreach($GraphGroup as $descr => $GraphAttr){
	$GraphAttr["hostTemplateId"] = $template_id;
	$GraphAttr["hostId"]         = $hostId;
	$GraphAttr["description"]    = $description;
	debug("$description: Creating ds graphs: $descr");
	$dsGraphsCreated = create_ds_graphs($GraphAttr);
	if ( $dsGraphsCreated ){
	  echo "$description: Graphs created: $dsGraphsCreated\n";
	}
      }
    }

    foreach($cgGraphs as $HostTemplateId => $Attr){
      if ($HostTemplateId != "any") {
	if ($template_id != $HostTemplateId){
	  continue;
	}
      }
      foreach($Attr as $descr => $val){
	$GraphAttr["GraphTemplateId"] = $val;
	$GraphAttr["hostId"]          = $hostId;
	$GraphAttr["description"]     = $description;
	debug("$description: Creating cg graph: $descr (template: $val)");
	$cgGraphCreated = create_cg_graph($GraphAttr);
      }
    }
  }
}

/* ----------------------------------------------------------------------------------------------------- */
/* Clean up stale groups and nodes in the tree */

foreach($hostNodes as $oldNode){
  debug("Deleting old tree node: $oldNode");
  db_execute("DELETE FROM graph_tree_items WHERE id=$oldNode");
}
foreach($headerNodes as $oldHeader){
  debug("Deleting old tree header: $oldHeader");
  db_execute("DELETE FROM graph_tree_items WHERE id=$oldHeader");
}


/* ----------------------------------------------------------------------------------------------------- */
// Subroutines
/* ----------------------------------------------------------------------------------------------------- */

/* ----------------------------------------------------------------------------------------------------- */
/* Create 'ds' graphs  
   'ds' graphs are for data-source based graphs (interface stats etc.)
*/

function create_ds_graphs($args) {

  $hostId          = $args["hostId"];
  $hostTemplateId  = $args["hostTemplateId"];
  $description     = $args["description"];
  $queryTypeIds    = $args["queryTypeIds"];
  $snmpQueryId     = $args["snmpQueryId"];

  if (!isset($hostId) || !isset($description) || !isset($queryTypeIds) || !isset($snmpQueryId)){
    echo "ERROR: create_ds_graph: Missing required arguments\n";
    exit(1);
  }

   /* Check if host has associated data query */
   $host_data_query = "SELECT snmp_query_id
                       FROM   host_snmp_query
                       WHERE  host_id='$hostId'
                          AND snmp_query_id='$snmpQueryId'";
   
   $snmpQuery = db_fetch_cell($host_data_query);
   
   if (!$snmpQuery) {
     // The query is not yet int the database.  Insert it 
     debug("Inserting missing host_snmp_query");
     $insertQuery = "REPLACE INTO host_snmp_query (host_id,snmp_query_id,reindex_method) 
                            VALUES ($hostId,$snmpQueryId,2)";
     $r = db_execute($insertQuery);
     if (!$r){
       echo "ERROR: DB operation failed for $insertQuery\n";
       return 0;
     }
     
     // recache snmp data 
     debug("Running Data query for new query id: $snmpQueryId");
     run_data_query($hostId, $snmpQueryId);
   }
   
   $snmpQueryArray = array();
   $snmpQueryArray["snmp_query_id"] = $snmpQueryId;
   $snmpQueryArray["snmp_index_on"] = get_best_data_query_index_type($hostId, $snmpQueryId);
   
   $indexes_query = "SELECT snmp_index
                     FROM   host_snmp_cache
                     WHERE  host_id='$hostId'
                        AND snmp_query_id='$snmpQueryId'";

   if (isset($args["snmpCriteria"]) && $args["snmpCriteria"] != ""){
     $indexes_query .= " AND ". $args["snmpCriteria"];
   }
   
   $snmpIndexes = db_fetch_assoc($indexes_query);
   
   if (sizeof($snmpIndexes)) {
    $graphsCreated = 0;
    $graphs = db_fetch_assoc("SELECT id, snmp_index, graph_template_id
                              FROM   graph_local
                              WHERE  host_id=$hostId
                                AND  snmp_query_id=$snmpQueryId");
    
    foreach ($graphs as $row){
      $graphsBySnmpIndex[$row["snmp_index"]][$row["graph_template_id"]] = $row["id"];
    }

    foreach ($queryTypeIds as $queryTypeId => $templateId) {
      $snmpQueryArray["snmp_query_graph_id"] = $queryTypeId;

      foreach ($snmpIndexes as $row) {
	$snmpIndex = $row["snmp_index"];
	if ( isset($graphsBySnmpIndex[$snmpIndex][$templateId]) ){
	  $graphId = $graphsBySnmpIndex[$snmpIndex][$templateId];
	  debug("$description: Graph already exists: ($graphId)");
	  continue;
	}
	$snmpQueryArray["snmp_index"] = $snmpIndex;
	$empty = array();
	$returnArray = create_complete_graph_from_template($templateId, $hostId, $snmpQueryArray, $empty);
	echo "$description: Added Graph id: " . $returnArray["local_graph_id"] . "\n";
	$graphsCreated++;
      }
    }
    if($graphsCreated > 0){
      push_out_host($hostId,0);
      return $graphsCreated;
    }
    
   }else{
     debug("$description: No rows in query: $indexes_query");
   }
}
 
/* ----------------------------------------------------------------------------------------------------- */
/* Create 'cg' graphs  
   'cg' graphs are for things like CPU temp/fan speed, etc
*/
function create_cg_graph($args) {
  
  $hostId       = $args["hostId"];
  $description  = $args["description"];
  $templateId   = $args["GraphTemplateId"];
  
  $values["cg"] = array(); // Not doing anything with this for now
  
  if (!isset($hostId) || !isset($description) || !isset($templateId)){
    echo "ERROR: create_cg_graph: Missing required arguments\n";
    exit(1);
  }
  
  $existsAlready = db_fetch_cell("SELECT id 
                                  FROM   graph_local 
                                  WHERE  graph_template_id=$templateId 
                                     AND host_id=$hostId");
   
  if (isset($existsAlready) && $existsAlready > 0) {
    debug("$description: Graph already exists: ($existsAlready)");
    return 0;
  }else{
    $returnArray = create_complete_graph_from_template($templateId, $hostId, "", $values["cg"]);
    echo "$description: Added Graph id: " . $returnArray["local_graph_id"] . "\n";
    push_out_host($hostId,0);
    return 1;
  }
}

function debug($message) {
  global $debug;
  if ($debug) {
    print("DEBUG: " . $message . "\n");
  }
}

function display_help() {
  echo "\n netdot_to_cacti.php - Part of the Netdot package (http://netdot.uoregon.edu)\n\n";
  echo "Command line utility to add and update devices, graphs and trees in Cacti, based on Netdot information\n\n";
  echo "Locate this script in your cacti directory (e.g. /var/www/cacti/) and run periodically via cron\n";
  echo "\n";
  echo "usage: netdot_to_cacti.php [--no-graphs] [-d|--debug] [-h|-help]\n";
  echo "\n";
  echo "Optional:\n";
  echo "    --no-graphs    Do not add graphs, only update devices and tree\n";
  echo "    -d|--debug     Enable debugging output\n";
  echo "    -h|--help      Display help and exit\n";

}

?>
