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
    this.m_parent = parent;
    this.m_wind = null;
    this.m_queryURL = "dynamic_list_query.html";

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
    // we try and grab every potential value from our parent list.
    if ((selectedIdx == -1) || (parent.options[selectedIdx].value == -1))
    {
        for (i = 0; i < parent.options.length; ++i)
            values += parent.options[i].value + " ";
    }
    else
        values += parent.options[selectedIdx].value;

    // at this point we have a list of values that we seem to care about
    // so we open up a temp window to query the DB. 
    var url = this.m_queryURL + "?table=" + this.m_dbTable;
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
    this.m_wind.close();

    var doc_form = this.getListForm();
    var options = doc_form[this.m_self].options;
    var i = 0, j = 0;
    options.length = 0;
    options.length = data.length;

    if (data.length > 1)
    {
        options[0] = new Option();
        options[0].value = -1;
        options[0].text = "----------";
        options[0].selected = true;
        j = 1;
    }

    for (; i < data.length; ++i, ++j)
        options[j] = data[i];

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

/* setQueryURL()
 * ----------------------------------------------------------------------------
 * The default query URL (dynamic_list_query.html) will work for most
 * purposes. However, occasionally you will have to use a customized
 * query to generate your results. You can define your own query URL here.
 * Note that the query string will be the same as that passed to
 * dynamic_list_query.html, it is the results that are customized. Your
 * custom page must call LIST_CALLBACK(), see dynamic_list_query.html for
 * an example.
 *
*/
DynamicList.prototype.setQueryURL = function(url)
{
    if (url)
        this.m_queryURL = url;
}

/* getQueryURL()
 * ----------------------------------------------------------------------------
*/
DynamicList.prototype.getQueryURL = function()
{
    return this.m_queryURL;
}

/* setParent()
 * ----------------------------------------------------------------------------
*/
DynamicList.prototype.setParent = function(parent)
{
    this.m_parent = parent;
}

/* getParent()
 * ----------------------------------------------------------------------------
*/
DynamicList.prototype.getParent = function()
{
    return this.m_parent;
}

/* setDBField()
 * ----------------------------------------------------------------------------
*/
DynamicList.prototype.setDBField = function(db_field)
{
    this.m_dbField = db_field;
}

/* getDBField()
 * ----------------------------------------------------------------------------
*/
DynamicList.prototype.getDBField = function()
{
    return this.m_dbField;
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
    s += "column = " + this.m_dbField + ", ";
    s += "query URL = " + this.m_queryURL;
    
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
