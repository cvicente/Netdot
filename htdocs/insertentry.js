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
      var now = new Date();
      var url = "insertentry.html?"+edit_args;
      // the idea is to open a window with a unique name so that we don't override the contents of an already open window
      insertwind = window.open(url, "insertwind"+now.getMinutes()+now.getSeconds(), "width=600,height=400,scrollbars=yes");
   }
