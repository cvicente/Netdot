// Calls select_query.html in new window
// This will create a hidden form
// then copy the matched objects in our <select> option list
// Args: 
//   * field: the column name we're searching
//   * val:   the search criteria
//   * tablename
   var wind;
   function sendquery(field, val, tablename){
      var url = "select_query.html?table="+tablename+"&crit="+val+"&field="+field.name;
      wind = window.open(url, "tmp", "width=1,height=1");
   }
   function getlist(field){
      var len = wind.document.forms[0].length;
      document.netdotform[field].options.length = 0;     
      for (var i = 0; i < len; i++){
        document.netdotform[field].options[i] = new Option();
        document.netdotform[field].options[i].value = wind.document.forms[0].elements[i].name;
        document.netdotform[field].options[i].text  = wind.document.forms[0].elements[i].value;
      } 
      wind.close();
   }
