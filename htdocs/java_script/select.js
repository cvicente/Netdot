// functions for new jsrs method

    function jsrsSendquery(tablename, form_field, val ) {
        // alert( "tablename: "+tablename+"; form_field: "+form_field+"; val: "+val );
        jsrsExecute( "../generic/jsrs_netdot.html", jsrsParseresults, "keyword_search", Array(tablename, form_field, val) );
    }

// Use this one when you want no limits imposed on the number of items returned
    function jsrsSendqueryNM(tablename, form_field, val) {
        // alert( "tablename: "+tablename+"; form_field: "+form_field+"; val: "+val );
        jsrsExecute( "../generic/jsrs_netdot.html", jsrsParseresults, "keyword_search", Array(tablename, form_field, val, 'null', '1') );
    }

    function jsrsSendqueryTB(tablename, form_field, val, column) {
	// alert( "tablename: "+tablename+"; form_field: "+form_field+"; Field (Column): "+column+"; val: "+val );
        jsrsExecute( "../generic/jsrs_netdot.html", jsrsParseresults, "keyword_search", Array(tablename, form_field, val, column, '1' ) );
    }

    function jsrsSendqueryCL(form_field, val) {
        // Closet-Floor relationship
        // alert( "Form field: "+form_field.name+"; val:"+val );
        jsrsExecute( "../generic/closet_floor_query.html", jsrsParseresults, "closet_floor_search", Array(form_field.name, val) );
    }

    function jsrsSendqueryBB(form_field, val) {
        //alert( "Form field: "+form_field.name+"; val:"+val );
        jsrsExecute( "../cable_plant/backbone_list_query.html", jsrsParseresults, "backbone_search", Array(form_field.name, val) );
    }

    function jsrsSendqueryRA(tablename, form_field) {
        jsrsExecute( "../generic/jsrs_retrieve_all.html", jsrsParseresults, "retrieve_all", Array(tablename, form_field) );
    }
    
    function jsrsSendqueryRAKW(tablename, form_field, val) {
        jsrsExecute( "../generic/jsrs_retrieve_all_bykw.html", jsrsParseresults, "retrieve_all_bykw", Array(tablename, form_field, val));
    }
    
    function jsrsSendquerySZ(form_field, val) {
        // Subnet-Zone relationship
        // alert( "Form field: "+form_field.name+"; val:"+val );
        jsrsExecute( "../generic/subnet_zone_query.html", jsrsParseresults, "subnet_zone_search", Array(form_field.name, val) );
    }

    function jsrsResetSelection(elementID) {
        document.getElementById(elementID).options.length = 0;
    }

    function jsrsParseresults( returnstring ) {
        // alert(returnstring);
        var data = explode(returnstring, "&");
        var form_elt;
        var thelist;
        
        // assume that form_elt will be the first variable in the return string.
        form_elt = data[0];

        thelist = document.getElementById(form_elt);
        thelist.length = 0;
        var bool = false;
        for(i=1; i<data.length; i++) {
            var elt = explode(data[i],"=");
            if( elt[0] != "" ) {
                var len = thelist.length++;
                var optionObject = new Option(unescape(elt[1]),elt[0])
		if(unescape(elt[1]) == "Refine search."){
		    if(document.getElementById("keywords")){
		        document.getElementById("keywords").type = "text";
		        document.getElementById("button").type = "button";
		        bool = true;
                    }
                }
                thelist.options[len] = optionObject;
            }
        }
        if(!bool){
            document.getElementById("keywords").type = "hidden";
	    document.getElementById("button").type = "hidden";
        }
    }


    function explode(item,delimiter) { 
        tempArray=new Array(1); 
        var Count=0; 
        var tempString=new String(item); 
 
        while (tempString.indexOf(delimiter)>0) { 
            tempArray[Count]=tempString.substr(0,tempString.indexOf(delimiter)); 
            tempString=tempString.substr(tempString.indexOf(delimiter)+1,tempString.length-tempString.indexOf(delimiter)+1); 
            Count=Count+1 
        } 
 
        tempArray[Count]=tempString; 
        return tempArray; 
     } 


// Open a given URL in a new browser window
    function openwindow(url){
	var newwindow;
	var now = new Date();
	// the idea is to open a window with a unique name so that we don't override the contents of an already open window
	newwindow = window.open(url, "window"+now.getMinutes()+now.getSeconds(), "width=800,height=600,scrollbars=yes");
	return newwindow;
    }

// 	Opens a new browser window for new object insertion
//         using edit.html
//
// 	Arguments:
// 	  edit_args:   Arguments in GET format to pass to edit.html
//
// 	EXAMPLE:
// 	<a href="#" onClick="openinsertwindow('table=DeviceContacts&device=<% $o->id %>')">[new]</a>

    function openinsertwindow(edit_args){
	var now = new Date();
	var url = "edit.html?showheader=0&"+edit_args;
	openwindow(url);
   }

//      Opens a new browser window for viewing (e.g. contact)
    var jspopoutstring="";
    function opentextwindow(data_string, format, urlargs) {
	var url = "viewtext.html?format="+format+"&"+urlargs;
	var textwindow = openwindow(url);
	if(format == 'js') textwindow.data_string = data_string;
    }


// this code inserts an element into the select box in the  
// calling page form, and selects the new element if needed  
//  
    function insertOption(id, txt, val, sel) {  
	var myselect = opener.document.getElementById(id);  
	try {
	    var opt = document.createElement('OPTION');  
	    opt.text = txt;  
	    opt.value = val;  
	    if ( sel == 1 ){
		opt.selected = true;
	    }
	    myselect.options.add(opt);
	}
	catch(e) {
	    myselect.options[0].text = txt;
	    myselect.options[0].value = val;
	    if ( sel == 1 ){
		myselect.options[0].selected = true;
	    }
	}
    }  

