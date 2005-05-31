   var insertwind;
   function openinsertwindow(table_name, select_id){
      var url = "insertentry.html?table="+table_name+"&select_id="+select_id;
      insertwind = window.open(url, "insertwind", "width=600,height=400,scrollbars=yes");
   }
