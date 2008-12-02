// functions for new jsrs method

    function jsrsSendquery(tablename, form_field, val ) {
	// alert( "tablename: "+tablename+"; form_field: "+form_field+" val: "+val );
        // got rid of form_field.name because of 'name' conflict with js; now form_field is a string, and we use form_field directly as opposed to form_field.name. The 3 other jsrsSendquery{TB|RM|BB} below methods are unchanged/unaffected.
        jsrsExecute( "../generic/jsrs_netdot.html", jsrsParseresults, "keyword_search", Array(tablename, form_field, val) );
    }

    function jsrsSendqueryTB(tablename, form_field, val, column) {
	// alert( "tablename: "+tablename+"; form_field: "+form_field.name+"; Field (Column): "+column+"; val: "+val );
        jsrsExecute( "../generic/jsrs_netdot.html", jsrsParseresults, "keyword_search", Array(tablename, form_field.name, val, column ) );
    }

    function jsrsSendqueryRM(form_field, val) {
        //alert( "Form field: "+form_field.name+"; val:"+val );
        jsrsExecute( "../generic/room_site_query.html", jsrsParseresults, "room_site_search", Array(form_field.name, val) );
    }

    function jsrsSendqueryBB(form_field, val) {
        //alert( "Form field: "+form_field.name+"; val:"+val );
        jsrsExecute( "../cable_plant/backbone_list_query.html", jsrsParseresults, "backbone_search", Array(form_field.name, val) );
    }

    function jsrsResetSelection(elementID) {
        document.getElementById(elementID).options.length = 0;
    }

    function jsrsParseresults( returnstring ) {
        //alert(returnstring);
        var data = explode(returnstring, "&");
        var form_elt;
        var thelist;

        // assume that form_elt will be the first variable in the return string.
        form_elt = data[0];

        thelist = document.getElementById(form_elt);
        thelist.length = 0;

        for(i=1; i<data.length; i++) {
            var elt = explode(data[i],"=");
            if( elt[0] != "" ) {
                var len = thelist.length++;
                var optionObject = new Option(unescape(elt[1]),elt[0])
                thelist.options[len] = optionObject;
            }
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

// 	Opens a new browser window for new object insertion
//         using edit.html
//
// 	Arguments:
// 	  edit_args:   Arguments in GET format to pass to edit.html
//
// 	EXAMPLE:
// 	<a href="#" onClick="openinsertwindow('table=DeviceContacts&device=<% $o->id %>')">[new]</a>

    function openinsertwindow(edit_args){
       var insertwind;
       var now = new Date();
       var url = "edit.html?showheader=0&"+edit_args;
       // the idea is to open a window with a unique name so that we don't override the contents of an already open window
       insertwind = window.open(url, "insertwind"+now.getMinutes()+now.getSeconds(), "width=600,height=400,scrollbars=yes");
   }

//      Opens a new browser window for viewing (e.g. contact)
function opentextwindow(data_string, format, urlargs) {
	var textwindow;
	var now = new Date();
	var url = "viewtext.html?format="+format+"&"+urlargs;
	textwindow = window.open(url, "textwind"+now.getMinutes()+now.getSeconds(), "width=600,height=400,scrollbars=yes");
	if(format == 'js') textwindow.data_string = data_string;
    }

// this code inserts an element into the select box in the  
// calling page form, and selects the new element if needed  
//  
    function insertOption(id, text, value, sel) {  
	var select_box = opener.document.getElementById(id);  
	var elOptNew = document.createElement('option');  
	elOptNew.text = text;  
	elOptNew.value = value;  
	try {  
	    select_box.add(elOptNew, null); // standards compliant; does not work in IE  
	    }  
	catch(ex) {  
	    select_box.add(elOptNew); // IE only  
	    }  
	if (sel == 1){  
	    select_box.selectedIndex = select_box.length-1;  
	}  
    }  


