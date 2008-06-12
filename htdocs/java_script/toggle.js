function toggleLayer(whichLayer) {
    if (document.getElementById) {
	// this is the way the standards work
	var style2 = document.getElementById(whichLayer).style;
	style2.display = style2.display=='none'?'block':'none';
    } else if (document.all) {
	// this is the way old msie versions work
	var style2 = document.all[whichLayer].style;
	style2.display = style2.display=='none'?'block':'none';
    } else if (document.layers) {
	// this is the way nn4 works
	var style2 = document.layers[whichLayer].style;
	style2.display = style2.display=='none'?'block':'none';
    }
    return style2.display;
}
function toggleTasks() {
    var display;
    display = toggleLayer('tasks');
    document.getElementById('tasks_link').innerHTML = (display=='none'?'[show]':'[hide]');
    jsrsExecute( "user_pref.html", emptyfunction, "set_value", Array('SHOW_TASKS', (display=='none'?'hide':'show')) );
}
function emptyfunction() {
    // do nothing
    // this function is called by the jsrs code after toggleTasks is called.
    // if this function doesn't exist, we get "context pool full" errors if
    // toggleTasks is called too many times in a row.
}
