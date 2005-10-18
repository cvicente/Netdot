// Calls select_query.html in new window
// This will create a hidden form
// then copy the matched objects in our <select> option list
// Args: 
//   * field: form <select> element name we want to populate with options
//   * val:   the search criteria
//   * tablename
   var wind;
   function sendquery(field, val, tablename, formname){
      var url = "select_query.html?table="+tablename+"&crit="+val+"&field="+field.name;
      if (formname)
        url += "&form_name=" + formname;

      wind = window.open(url, "tmp", "width=1,height=1");
   }
   function getlist(field, form_name){
      var len = wind.document.forms[0].length;

      if (!form_name)
        form_name = "netdotform";

      document.forms[form_name][field].options.length = 0;     
      for (var i = 0; i < len; i++){
        document.forms[form_name][field].options[i] = new Option();
        document.forms[form_name][field].options[i].value = wind.document.forms[0].elements[i].name;
        document.forms[form_name][field].options[i].text  = wind.document.forms[0].elements[i].value;
      } 
      wind.close();
   }

// functions for new jsrs method

    function jsrsSendquery(field, val, tablename) {
        //alert( "Field: "+field.name+"; val:"+val+"; tablename: "+tablename );
        jsrsExecute( "jsrs_netdot.html", jsrsParseresults, "keyword_search", Array(tablename, field.name, val) );
    }

    function jsrsSendqueryTB(form_field, val, tablename, column) {
        //alert( "Field (Column): "+column+"; val:"+val+"; tablename: "+tablename+" form_field: "+form_field.name );
        jsrsExecute( "jsrs_singletable.html", jsrsParseresults, "keyword_search", Array(tablename, column, val, form_field.name) );
    }

    function jsrsSendqueryBB(field, val) {
        jsrsExecute( "backbone_list_query.html", jsrsParseresults, "backbone_search", Array(field.name, val) );
    }

    function jsrsParseresults( returnstring ) {
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
