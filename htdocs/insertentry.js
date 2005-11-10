/*
	Opens a new browser window for new object insertion
        using edit.html (via insertentry.html)

	Arguments:
	  edit_args:   Arguments in GET format to pass to edit.html

	EXAMPLE:
	<a href="#" onClick="openinsertwindow('table=DeviceContacts&device=<% $o->id %>')">[new]</a>

*/
   var insertwind;
   function openinsertwindow(edit_args){
      var url = "insertentry.html?"+edit_args;
      insertwind = window.open(url, "insertwind", "width=600,height=400,scrollbars=yes");
   }
