   var insertwind;
   function openinsertwindow(table_name, select_id){
      var url = "insertentry.html?table="+table_name+"&select_id="+select_id;
      insertwind = window.open(url, "insertwind", "width=600,height=400,scrollbars=yes");
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
