/* DynamicList()
 * ----------------------------------------------------------------------------
 * Constructor. 
*/
function DynamicList(form, self, db_field, db_table, parent)
{
    if (arguments.length < 5)
        alert("DynamicList() expects 5 arguments.");

    this.m_form = form;
    this.m_formObject = null;
    this.m_self = self;
    this.m_dbField = db_field;
    this.m_dbTable = db_table;
    this.m_wind = null;
    this.m_parent = parent;

    // store additional args as dependencies
    this.m_deps = new Array();
    for (i = 5; i < arguments.length; ++i)
    {
        this.m_deps.push(arguments[i]);
    }
}

/* doIt()
 * ----------------------------------------------------------------------------
 * TODO: Support multiple selection lists and eliminate the use of a temporary
 *       popup window - use a hidden frame instead.
*/
DynamicList.prototype.doIt = function()
{
    var doc_form = this.getListForm();
    var parent = doc_form[this.m_parent];
    var selectedIdx = parent.selectedIndex;
    var values = new String();

    // If our selected index is not set, nothing is selected so
    // we try and grab every potential value from our selection list.
    if (selectedIdx == -1 || !parent.options[selectedIdx].value)
    {
        for (i = 0; i < parent.options.length; ++i)
            values += parent.options[i].value + " ";
    }
    else
        values += parent.options[selectedIdx].value;

    // at this point we have a list of values that we seem to care about
    // so we open up a temp window to query the DB. 
    var url = "dynamic_list_query.html?table=" + this.m_dbTable;
    url += "&val=" + values;
    url += "&search_field=" + this.m_dbField + "&field=" + this.m_self;
    url += "&self=" + this.m_self;
    this.m_wind = window.open(url, "tmp" + this.m_self, "width=1,height=1");
    this.m_wind.blur();
}

/* populate()
 * ----------------------------------------------------------------------------
 * This function is not called until the post to the temporary popup window
 * (via doIt()) has completed and has invoked LIST_CALLBACK. Necessary because
 * JS will not block until a get or post request has completed.
*/
DynamicList.prototype.populate = function(data)
{
    var doc_form = this.getListForm();
    var control = doc_form[this.m_self];
    control.options.length = 0;

    control.options[0] = new Option();
    control.options[0].value = null;
    control.options[0].text = "----------";
    control.options[0].selected = true;
    
    for (var i = 0, j = 1; i < data.length; ++i, ++j)
    {
        control.options[j] = new Option();
        control.options[j].value = data[i][0];
        control.options[j].text  = data[i][1];
    }
    
    this.m_wind.close();

    // process any dependencies
    for (i = 0; i < this.m_deps.length; ++i)
        if (this.m_deps[i])
            this.m_deps[i].doIt();
}

/* getListForm()
 * ---------------------------------------------------------------------------
*/
DynamicList.prototype.getListForm = function()
{
    if (this.m_formObject)
        return this.m_formObject;
        
    // get form object based upon name
    for (i = 0; i < document.forms.length; ++i)
    {
        if (document.forms[i].name == this.m_form)
        {
            this.m_formObject = document.forms[i];
            return this.m_formObject;
        }
    }
}

/* getName()
 * ----------------------------------------------------------------------------
*/
DynamicList.prototype.getName = function()
{
    return this.m_self;
}

/* toString()
 * ----------------------------------------------------------------------------
*/
DynamicList.prototype.toString = function()
{
    var s = new String();
    s += "name = " + this.m_self + ", ";
    s += "form = " + this.m_form + ", ";
    s += "parent = " + this.m_parent + ", ";
    s += "dependencies = " + this.m_deps + ", ";
    s += "table = " + this.m_dbTable + ", ";
    s += "column = " + this.m_dbField;
    
    return s;
}
// DynamicList


/* ListManager()
 * ----------------------------------------------------------------------------
 * Constructor.
*/
function ListManager()
{
    this.m_lists = new Array();
}

/* addList()
 * ----------------------------------------------------------------------------
 *
*/
ListManager.prototype.addList = function(list)
{
    for (i = 0; i < arguments.length; ++i)
        this.m_lists.push(arguments[i]);
}

/* removeList()
 * ----------------------------------------------------------------------------
 *
*/
ListManager.prototype.removeList = function(list)
{
    if (list)
    {
        for (i = 0; i < this.m_lists.length; ++i)
            if (this.m_lists[i] == list)
                this.m_lists[i] = null;
    }
}

/* getListByName()
 * ----------------------------------------------------------------------------
 *
*/
ListManager.prototype.getListByName = function(list_name)
{
    if (list_name)
    {
        for (i = 0; i < this.m_lists.length; ++i)
            if (this.m_lists[i].getName() == list_name)
                return this.m_lists[i];
    }

    return null;
}
// ListManager


// global instance of ListManager and callback function.
var LIST_MANAGER = new ListManager();

function LIST_CALLBACK(caller, data)
{
    var list = LIST_MANAGER.getListByName(caller);
    if (list)
        list.populate(data);
}
