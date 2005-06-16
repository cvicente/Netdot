# **************************************************************
# *
# * jsrsServer.pl JavaScript Remote Scripting server include
# *
# * Author: Stephen Carroll [scarroll@virtuosoft.net]
# *         originally adapted from ASP version by
# *         Brent Ashley [jsrs@megahuge.com]
# *
# * The JSRS is distributed under the terms of the GNU 
# * Genral Public License terms and conditions for copying,
# * distribution and modification.
# *
# **************************************************************
use URI::Escape;
use CGI;

$jsrsQuery = CGI::new();
# print "Content-type: text/html\n\n";
sub jsrsDispatch {
	my $validFuncs = $_[0];
	my $func = jsrsBuildFunc($validFuncs);
	if ($func ne ""){
		$retval = eval($func);
        print STDERR "jsrsDispatch returns: ".$func."\n";
		jsrsReturn($retval);
	}else{
		jsrsReturnError("function builds as empty string");
	}
}

sub jsrsReturn {
	my $payload = $_[0];
	print "Content-type: text/html\n\n";
	print "<html><head></head><body onload=\"p=document.layers?parentLayer:window.parent;p.jsrsLoaded('";
	print $jsrsQuery->param("C") . "');\">jsrsPayload:<br>";
	print "<form name=\"jsrs_Form\"><textarea name=\"jsrs_Payload\" id=\"jsrs_Payload\">";
	print jsrsEscape( $payload ) . "</textarea></form></body></html>";
}

sub jsrsEscape {
	my $str = $_[0];
	my $tmp = Replace($str,"&", "&amp;");
	$tmp = Replace($tmp,"/", "\\/");
}

# **************************************************************
# *
# * user functions

sub jsrsReturnError {
	my $str = $_[0];
	my $cleanStr = Replace($str,"'","\\'");
	$cleanStr = "jsrsError: " . Replace($cleanStr, (chr(92) . chr(34)), chr(92) . chr(92) . chr(92) . chr(34));
	print "<html><head></head><body ";
	print "onload=" . chr(34) . "p=document.layers?parentlayer:window.parent;p.jsrsError(\'" . $jsrsQuery->param("C");
	print "','" . uri_unescape($str) . "\');" . chr(34) . ">" . $cleanStr . "</body></html>";
}

sub jsrsBuildFunc {
	my $validFuncs = $_[0];
	my $func = "";
	if ($jsrsQuery->param("F") ne ""){
		$func = $jsrsQuery->param("F");
		# make sure its in the dispatch list
		if (index(uc($validFuncs), uc($func),0)==-1){
			jsrsReturnError($func . " is not a valid function");
		}
		$func = $func . "(";
		my $i = 0;
		while (length($jsrsQuery->param("P" . $i)) != 0){
			$parm = $jsrsQuery->param("P" . $i);
			$parm = substr($parm, 1, length($parm)-2);
			$func = $func . chr(34) . jsrsEvalEscape($parm) . chr(34) . ",";
			$i = $i + 1;
		}
		if (substr($func,length($func)-1,1) eq ","){
			$func = substr($func,0,length($func)-1);
		}
		$func = $func . ")";
		return $func;
	}
}

sub jsrsEvalEscape {
	my $thing = $_[0];
	$tmp = Replace($thing, chr(13), chr(92) . "n");
	$tmp = Replace($tmp, chr(43) . chr(34), chr(92) . chr(34) . chr(34));
	return $tmp;
}

# **************************************************************
# *
# * other compatibility functions

sub Replace {
	my $sSource = $_[0];
	my $sFind = $_[1];
	my $sReplace = $_[2];
	
	my $i = index($sSource, $sFind, 0);
	while ($i != -1) {
		$sOut = substr($sSource, 0, $i);
		$sOut = $sOut . $sReplace;
		$sOut = $sOut . substr($sSource, ($i + length($sFind)), length($sSource));
		$sSource = $sOut;
		$i = index($sSource, $sFind, ($i + length($sReplace)));
	}
	return $sSource;
}
