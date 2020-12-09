"use strict";

// SUPERTABLE! IT SORTS! IT FILTERS! IT'S THE SUPERTABLE!

// I have created a monster

// I'm so sorry. I didn't know what I was doing.


// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// THE COLUMN EDITOR

class ColumnEditor extends ModalDialogBase {
    /*
        columnDefs: ALL possible columns, their names and IDs and other data.

        defaultColumns: array of (ID, visible) pairs of columns, in the order they're displayed.
        The IDs are not filtered/checked in any way; if you put invalid IDs in there (IDs that
        don't exist in columnDefs), then you get crashes/malfunctions/errors and it'll be your
        own fault.
    */

    constructor(subTitle, columnDefs, defaultColumns)
    {
        super();

        // UI setup
        this.setTitle(I18n.translate("supertable.column_editor.title"), subTitle);

        this.okButton = this.createButton(
            I18n.translate("supertable.column_editor.save"),
            "button-good", "ce-ok", event => this.save(event));
        this.buttons.appendChild(this.okButton);

        this.cancelButton = this.createButton(
            I18n.translate("supertable.column_editor.cancel"),
            "button-danger", "ce-cancel", event => this.cancel(event));
        this.buttons.appendChild(this.cancelButton);

        this.columnDefs = columnDefs;
        this.defaultColumns = defaultColumns;

        // flex container
        let container = document.createElement("div");
        container.className = "columnsContainer";

        // left side, for the table
        let left = document.createElement("div");
        left.className = "columnsLeft";

        // right side, for the buttons
        let right = document.createElement("div");
        right.className = "columnsRight";

        this.upButton = this.createButton(
            I18n.translate("supertable.column_editor.moveUp"),
            null, "ce-up", event => this.clickedUp(event));
        right.appendChild(this.upButton);

        right.appendChild(
            this.createButton(
                I18n.translate("supertable.column_editor.moveDown"),
                null, "ce-down", event => this.clickedDown(event)));

        right.appendChild(
            this.createButton(
                I18n.translate("supertable.column_editor.reset"),
                null, "ce-reset", event => this.clickedReset(event)));

/*
        right.appendChild(
            this.createButton(
                I18n.translate("supertable.column_editor.all"),
                null, "ce-all", event => this.clickedAll(event)));
*/

        // build the column table
        this.table = document.createElement("table");
        this.table.className = "columnTable";

        let thead = document.createElement("thead");
        let tr = document.createElement("tr");

        let thVisible = document.createElement("th");
        thVisible.appendChild(document.createTextNode(I18n.translate("supertable.column_editor.visible")));

        let thName = document.createElement("th");
        thName.appendChild(document.createTextNode(I18n.translate("supertable.column_editor.name")));

        tr.appendChild(thVisible);
        tr.appendChild(thName);

        thead.appendChild(tr);
        this.table.appendChild(thead);

        // assemble the layout
        left.appendChild(this.table);
        container.appendChild(left);
        container.appendChild(right);
        this.body.appendChild(container);

        this.saveCallback = null;
        this.selectedRowIndex = -1;

        this.okDisabled = false;
        this.setOKButtonState();
    }

    // ---------------------------------------------------------------------------------------------
    // Utility

    // Deep copies a columns array. Needed so that we can cancel the dialog
    // without clobbering the original columns array that was passed in.
    duplicateColumns(source)
    {
        let out = [];

        for (let c in source)
            out.push([source[c][0], source[c][1]]);

        return out;
    }

    // Builds the TBODY element containing the columns and their states
    buildColumnTable()
    {
        let tbody = document.createElement("tbody");

        for (let i in this.columns) {
            const colDef = this.columnDefs[this.columns[i][0]];

            // Checkbox column
            let cbTD = document.createElement("td");

            cbTD.classList.add("visibleColumn");
            cbTD.addEventListener("click", event => this.clickedCheckbox(event));

            let cb = document.createElement("input");

            cb.type = "checkbox";

            if (this.columns[i][1])
                cb.checked = true;      // this column is visible

            cbTD.appendChild(cb);

            // Name column
            let nameTD = document.createElement("td");

            nameTD.appendChild(document.createTextNode(colDef["title"]));
            nameTD.classList.add("nameColumn");
            nameTD.addEventListener("click", event => this.clickedName(event));

            // Table row
            let tr = document.createElement("tr");

            if (i == 0)
                tr.classList.add("selectedRow");        // highlight the first row initially

            tr.dataset.id = this.columns[i][0];         // needed when determining the column index

            tr.appendChild(cbTD);
            tr.appendChild(nameTD);

            tbody.appendChild(tr);
        }

        return tbody;
    }

    // Enable/disable the OK button. At least one column must be visible.
    setOKButtonState()
    {
        let haveAtLeastOne = false;

        for (let c in this.columns) {
            if (this.columns[c][1]) {
                haveAtLeastOne = true;
                break;
            }
        }

        if (haveAtLeastOne) {
            this.okButton.classList.remove("disabled");
            this.okDisabled = false;
        } else {
            this.okButton.classList.add("disabled");
            this.okDisabled = true;
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Click event handlers

    // Set/clear the column checkbox
    clickedCheckbox(e)
    {
        const colId = e.target.parentNode.dataset.id;
        let index = -1;

        // find the column in the array
        for (let c in this.columns) {
            if (this.columns[c][0] == colId) {
                index = c;
                break;
            }
        }

        if (index == -1) {
            console.error(`ColumnEditor::clickedCheckbox(): unknown column ID "${colId}"`);
            return;
        }

        // invert state and update
        this.columns[index][1] = !this.columns[index][1];
        e.target.children[0].checked = this.columns[index][1];

        this.setOKButtonState();
    }

    // Select a row on the table
    clickedName(e)
    {
        let clickedRow = e.target.parentNode;

        for (let i = 1; i < this.table.rows.length; i++) {
            let thisRow = this.table.rows[i];

            if (thisRow.dataset.id == clickedRow.dataset.id) {
                thisRow.classList.add("selectedRow");
                this.selectedRowIndex = i - 1;
            } else thisRow.classList.remove("selectedRow");
        }
    }

    swapRows(a, b)
    {
        let t = this.columns[b];

        this.columns[b] = this.columns[a];
        this.columns[a] = t;
    }

    // Move the selected row up if possible
    clickedUp(e)
    {
        if (this.selectedRowIndex == -1)
            return;

        let row = this.table.rows[this.selectedRowIndex + 1],
            prev = row.previousElementSibling;

        if (prev) {
            // have a previous row, this row can be moved upwards
            let parent = row.parentNode;
            parent.insertBefore(row, prev);

            this.swapRows(this.selectedRowIndex, this.selectedRowIndex - 1);
            this.selectedRowIndex--;
        }
    }

    // Move the selected row down if possible
    clickedDown(e)
    {
        if (this.selectedRowIndex == -1)
            return;

        let row = this.table.rows[this.selectedRowIndex + 1],
            next = row.nextElementSibling;

        if (next) {
            // have a next row, this row can be moved downwards
            let parent = row.parentNode;
            parent.insertBefore(next, row);

            this.swapRows(this.selectedRowIndex, this.selectedRowIndex + 1);
            this.selectedRowIndex++;
        }
    }

    // Reset the column settings to defaults
    clickedReset(e)
    {
        this.columns = this.duplicateColumns(this.defaultColumns);

        let newBody = this.buildColumnTable(this.columns);

        this.table.tBodies[0].remove();
        this.table.appendChild(newBody);

        this.selectedRowIndex = 0;

        this.setOKButtonState();
    }

    // Check all columns!
    clickedAll(e)
    {
        // TODO: implement this
    }

    // ---------------------------------------------------------------------------------------------

    show(currentColumns, saveCallback)
    {
        this.columns = this.duplicateColumns(currentColumns);

        this.selectedRowIndex = 0;

        // (Re)build the column array for the current data
        let tbody = this.buildColumnTable();

        if (this.table.tBodies.length > 0)
            this.table.tBodies[0].remove();

        this.table.appendChild(tbody);

        // Setup state
        this.setOKButtonState();
        this.saveCallback = saveCallback;

        // And go!
        document.body.appendChild(this.backdrop);
    }

    save(e)
    {
        if (this.okDisabled)
            return;

        this.saveCallback(this.columns);
        this.close();
    }

    cancel(e)
    {
        this.close();
    }
};

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// UTILITY

// Creates a new HTML element and sets is attributes
function newElem(params)
{
    let e = document.createElement(params["tag"]);

    if ("id" in params && params["id"] !== undefined)
        e.id = params["id"];

    if ("classes" in params && params["classes"] !== undefined)
        e.className = params["classes"].join(" ");

    if ("content" in params && params["content"] !== undefined)
        e.innerHTML = params["content"];

    if ("contentText" in params && params["contentText"] !== undefined)
        e.innerText = params["contentText"];

    if ("innerText" in params && params["innerText"] !== undefined)
        e.appendChild(document.createTextNode(params["innerText"]));

    return e;
}

// Creates an <option> element under a <select> element
function createOption(selector, title, id, valid)
{
    let option = document.createElement("option");

    option.appendChild(document.createTextNode(title));

    if (id)
        option.dataset.id = id;

    if (!valid)
        option.className = "disabledOption";

    selector.appendChild(option);
}

function pad(number)
{
    return (number < 10) ? "0" + number : number;
}

// Scaler for converting between JavaScript dates and unixtimes
const JAVASCRIPT_TIME_GRANULARITY = 1000;

function convertTimestamp(unixtime)
{
    if (unixtime < 0)
        return "";

    // Assume "too old" timestamps are invalid
    // 2000-01-01 00:00:00 UTC
    if (unixtime < 946684800)
        return "(INVALID)";

    try {
        // I'm not sure if this can throw errors
        const d = new Date(unixtime * JAVASCRIPT_TIME_GRANULARITY);

        // why is there no strftime() in JavaScript?
        return d.getFullYear() + "-" +
            pad(d.getMonth() + 1) + "-" +
            pad(d.getDate()) + " " +
            pad(d.getHours()) + ":" +
            pad(d.getMinutes()) + ":" +
            pad(d.getSeconds());
    } catch (e) {
        console.log(e);
        return "(ERROR)";
    }
}

function convertTimestampDateOnly(unixtime)
{
    if (unixtime < 0)
        return "";

    // Assume "too old" timestamps are invalid
    // 2000-01-01 00:00:00 UTC
    if (unixtime < 946684800)
        return "(INVALID)";

    try {
        // I'm not sure if this can throw errors
        const d = new Date(unixtime * JAVASCRIPT_TIME_GRANULARITY);

        // why is there no strftime() in JavaScript?
        return d.getFullYear() + "-" +
            pad(d.getMonth() + 1) + "-" +
            pad(d.getDate());
    } catch (e) {
        console.log(e);
        return "(ERROR)";
    }
}

function isInteger(s)
{
    return /^\d+$/.test(s);
}

function isFloat(s)
{
    // Not a very good test, but I don't know what else to do
    return !isNaN(parseFloat(s));
}

// For some reason I can't reliably do this in server end
function escapeHTML(s)
{
    if (typeof(s) != "string")
        return s;

    return s.replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
}

function doSingleNetworkPost(url, itemData)
{
    return fetch(url, {
        method: "POST",
        mode: "cors",
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify(itemData)
    }).then(function(response) {
        if (!response.ok)
            throw response;

        return response.json();
    }).catch((error) => {
        console.error(error);
        // TODO: untranslated error string!
        return { success: false, message: "Network connection error!" };
    });
}

// All mass operations are just chained promises, so we need some way
// to quickly return from an item processing function when nothing
// needs to (or cannot) be done. These two convenience functions can be
// used to return OK/failed states without having to remember the
// convoluted Promise syntax.
function itemProcessingOK(message=null)
{
    return new Promise(function(resolve, reject) {
        resolve({ success: true, message: message });
    });
}

function itemProcessingFailed(message=null)
{
    // we don't actually reject the promise itself, we just set the
    // 'success' flag, because it's all we care about
    return new Promise(function(resolve, reject) {
        resolve({ success: false, message: message });
    });
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// THE SUPERTABLE

// -------------------------------------------------------------------------------------------------
// DEFINITIONS

// Main table flags. These enable/disable major features that are not otherwise available.
const TABLE_FLAG_USERS = 0x01,              // this is a users table
      TABLE_FLAG_GROUPS = 0x02,             // this is a groups table
      TABLE_FLAG_DEVICES = 0x04,            // this is a devices table
      TABLE_FLAG_ORGANISATION_DEVICES = 0x08,   // devices table for the whole organisation
      TABLE_FLAG_PRIMUS_THINGS = 0x10,      // do Primus integration things
      TABLE_FLAG_ENABLE_SELECTION = 0x20;   // enable per-row checkboxes for selecting multiple items

// The current sorting order for each sortable column
const SORT_ORDER_NONE = 0,          // not sorted by this column
      SORT_ORDER_ASCENDING = 1,     // A -> Z, 0 -> 9, etc.
      SORT_ORDER_DESCENDING = 2;    // Z -> A, 9 -> 0, etc.

// Row flags
const ROW_FLAG_SELECTED = 0x01,             // this row is currently selected
      ROW_FLAG_FILTERED = 0x02,             // this row is not currently visible in the table
      ROW_FLAG_PROCESSED = 0x04,            // this row has been already processed in the current mass operation
      ROW_FLAG_PROCESSING_OK = 0x08,        // processing of this item succeeded
      ROW_FLAG_PROCESSING_FAIL = 0x10;      // processing of this item failed

// Column flags. Affects mainly how the raw data is processed before it is actually interpreted.
const COLUMN_FLAG_SORTABLE = 0x01,  // this column can be sorted
      COLUMN_FLAG_SPLIT = 0x02,     // the value is an array that must displayed on multiple rows in the cell
      COLUMN_FLAG_SPLIT_BY_NEWLINES = 0x04; // convert \n's into <br>'s (strips out \r's)

// Column data types. Do NOT use zero here, because... JavaScript's "types".
const COLUMN_TYPE_STRING = 1,
      COLUMN_TYPE_INTEGER = 2,
      COLUMN_TYPE_FLOAT = 3,
      COLUMN_TYPE_UNIXTIME = 4,             // same as integer, but will be displayed in human-readable format
      COLUMN_TYPE_BOOLEAN = 5;

// Column data subtypes, for enabling highly context-specific things that would be
// otherwise very hard to do. Again, no zeroes here.
const COLUMN_SUBTYPE_USER_USERNAME = 1,
      COLUMN_SUBTYPE_USER_ROLES = 2,
      COLUMN_SUBTYPE_GROUP_NAME = 3,
      COLUMN_SUBTYPE_GROUP_TYPE = 4,
      COLUMN_SUBTYPE_DEVICE_HOSTNAME = 5,
      COLUMN_SUBTYPE_DEVICE_BATTERY_CAPACITY = 6,
      COLUMN_SUBTYPE_DEVICE_BATTERY_VOLTAGE = 7,
      COLUMN_SUBTYPE_DEVICE_WARRANTY_DATE = 8,
      COLUMN_SUBTYPE_DEVICE_SUPPORT_URL = 9,
      COLUMN_SUBTYPE_DEVICE_PRIMARY_USER = 10;

// Filter operator codes. Just say no to zeroes.
const OPERATOR_EQUAL = 1,
      OPERATOR_NOT_EQUAL = 2,
      OPERATOR_LESS_THAN = 3,
      OPERATOR_LESS_OR_EQUAL = 4,
      OPERATOR_GREATER_THAN = 5,
      OPERATOR_GREATER_OR_EQUAL = 6;

// Available filter operators
const OPERATOR_TYPES = {
    equ: {
        // Always a regexp for string columns
        title: "=",
        operator: OPERATOR_EQUAL,
        available: [COLUMN_TYPE_STRING, COLUMN_TYPE_INTEGER, COLUMN_TYPE_FLOAT, COLUMN_TYPE_BOOLEAN, COLUMN_TYPE_UNIXTIME],
    },

    neq: {
        // Always a regexp for string columns
        title: "≠",
        operator: OPERATOR_NOT_EQUAL,
        available: [COLUMN_TYPE_STRING, COLUMN_TYPE_INTEGER, COLUMN_TYPE_FLOAT, COLUMN_TYPE_BOOLEAN, COLUMN_TYPE_UNIXTIME],
    },

    lt: {
        title: "<",
        operator: OPERATOR_LESS_THAN,
        available: [COLUMN_TYPE_INTEGER, COLUMN_TYPE_FLOAT, COLUMN_TYPE_UNIXTIME],
    },

    lte: {
        title: "≤",
        operator: OPERATOR_LESS_OR_EQUAL,
        available: [COLUMN_TYPE_INTEGER, COLUMN_TYPE_FLOAT, COLUMN_TYPE_UNIXTIME],
    },

    gt: {
        title: ">",
        operator: OPERATOR_GREATER_THAN,
        available: [COLUMN_TYPE_INTEGER, COLUMN_TYPE_FLOAT, COLUMN_TYPE_UNIXTIME],
    },

    gte: {
        title: "≥",
        operator: OPERATOR_GREATER_OR_EQUAL,
        available: [COLUMN_TYPE_INTEGER, COLUMN_TYPE_FLOAT, COLUMN_TYPE_UNIXTIME],
    },
};

// -------------------------------------------------------------------------------------------------
// Supertable filter editor

// Base filter term editor class. You MUST inherit new filters from this!
class FilterBase {
    constructor(container, parentClass)
    {
        this.valid = false;
        this.changed = false;
        this.parentClass = parentClass;
    }

    notifyParent()
    {
        // tell the parent (ie. the filter editor) to update itself
        this.parentClass.filterTermWasChanged();
    }

    onInput(e)
    {
    }

    hasBeenChanged()
    {
        return this.changed;
    }

    isValid()
    {
        return this.valid;
    }

    // used when saving filters, we must save the actual "raw" value, not the cleaned-up value
    getSaveValue()
    {
        return null;
    }

    // get the value we can actually use when doing filtering
    getFilterValue()
    {
        return null;
    }

    copy()
    {
        return null;
    }

    paste(s)
    {
    }
};

// A string filter
class FilterString extends FilterBase {
    constructor(container, parentClass, initial)
    {
        super(container, parentClass);

        this.input = document.createElement("input");
        this.input.type = "search";
        this.input.classList.add("single");
        this.input.placeholder = I18n.translate("supertable.control.filter.placeholder_string");
        this.input.title = I18n.translate("supertable.control.filter.placeholder_string");
        this.input.setAttribute("maxlength", "30");
        this.input.addEventListener("input", event => this.onInput(event));

        // restore filter settings
        if (initial) {
            this.input.value = initial.trim();
            this.changed = true;
        }

        container.appendChild(this.input);

        this.validate();
    }

    validate()
    {
        const v = this.input.value.trim();

        if (v.length == 0)
            this.valid = false;
        else {
            // is it a valid regexp?
            try {
                new RegExp(v, "iu");
                this.valid = true;
            } catch (e) {
                this.valid = false;
            }
        }
    }

    onInput(event)
    {
        this.changed = true;
        this.validate();
        this.notifyParent();
    }

    getSaveValue()
    {
        return this.input.value;
    }

    getFilterValue()
    {
        // This won't get called if validate() fails this, so the regexp should always be valid
        return new RegExp(this.input.value, "iu");
    }
};

// An integer filter
class FilterInteger extends FilterBase {
    constructor(container, parentClass, initial)
    {
        super(container, parentClass);

        // the HTML "numeric" input box is so primitive it cannot be really used here
        this.input = document.createElement("input");
        this.input.type = "search";
        this.input.classList.add("single");
        this.input.placeholder = I18n.translate("supertable.control.filter.placeholder_integer");
        this.input.title = I18n.translate("supertable.control.filter.placeholder_integer");
        this.input.setAttribute("maxlength", "10");
        this.input.addEventListener("input", event => this.onInput(event));

        // restore filter settings
        if (initial) {
            this.input.value = initial;
            this.changed = true;
        }

        container.appendChild(this.input);

        this.validate();
    }

    validate()
    {
        const v = this.input.value.trim();

        if (v.length == 0)
            this.valid = false;
        else this.valid = isInteger(v);
    }

    onInput(event)
    {
        this.changed = true;
        this.validate();
        this.notifyParent();
    }

    getSaveValue()
    {
        return this.input.value ? parseInt(this.input.value.trim(), 10) : null;
    }

    getFilterValue()
    {
        return parseInt(this.input.value.trim(), 10);
    }
};

// A float filter
class FilterFloat extends FilterBase {
    constructor(container, parentClass, initial)
    {
        super(container, parentClass);

        this.input = document.createElement("input");
        this.input.type = "search";
        this.input.classList.add("single");
        this.input.placeholder = I18n.translate("supertable.control.filter.placeholder_float");
        this.input.title = I18n.translate("supertable.control.filter.placeholder_float");
        this.input.setAttribute("maxlength", "15");
        this.input.addEventListener("input", event => this.onInput(event));

        // restore filter settings
        if (initial) {
            this.input.value = initial;
            this.changed = true;
        }

        container.appendChild(this.input);

        this.validate();
    }

    validate()
    {
        const v = this.input.value.trim();

        if (v.length == 0)
            this.valid = false;
        else this.valid = isFloat(v);
    }

    onInput(event)
    {
        this.changed = true;
        this.validate();
        this.notifyParent();
    }

    getSaveValue()
    {
        return this.input.value ? this.getFilterValue() : null;
    }

    getFilterValue()
    {
        const cleaned = this.input.value.trim().replace(/,/g, '.');
        const parsed = parseFloat(cleaned);

        //console.log(`FilterFloat::getFilterValue(): raw=|${cleaned}| x=|${parsed}|`);
        return parsed;
    }
};

// A boolean filter
class FilterBoolean extends FilterBase {
    constructor(container, parentClass, initial)
    {
        super(container, parentClass);

        let wrapper = document.createElement("div");
        wrapper.classList.add("boolean");

        // apparently the only way to attach a label to a checkbox is via unique ID,
        // so generate a unique ID... bleh
        const id = `filterBooleanId-${Math.floor(Math.random() * 65536.0)}`;

        this.input = document.createElement("input");

        this.input.type = "checkbox";
        this.input.id = id;
        this.input.checked = true;
        this.input.addEventListener("input", event => this.onInput(event));

        let label = document.createElement("label");
        label.appendChild(document.createTextNode(I18n.translate("supertable.control.filter.title_boolean")));
        label.setAttribute("for", id);

        wrapper.appendChild(this.input);
        wrapper.appendChild(label);

        // restore filter settings
        if (initial) {
            this.input.checked = initial;
            this.changed = true;
        }

        container.appendChild(wrapper);

        // we're always valid
        this.valid = true;
    }

    onInput(e)
    {
        this.changed = true;
        this.notifyParent();
    }

    getSaveValue()
    {
        return this.input.checked;
    }

    getFilterValue()
    {
        return this.input.checked;
    }
};

// A unixtime filter
class FilterUnixtime extends FilterBase {
    constructor(container, parentClass, initial)
    {
        super(container, parentClass);

        // prefill the year selector, as it is the only field that's actually required
        const year = new Date().getFullYear().toString();

        // HTML has date and time input elements, but they're so useless
        // we have to create our own. Even this what we create is better
        // then the built-in editors!
        let wrapper = document.createElement("div");

        this.yearInput = this.createInput(
            I18n.translate("supertable.control.filter.placeholder_unixtime_year"), 4, "year", year);

        this.monthInput = this.createInput(
            I18n.translate("supertable.control.filter.placeholder_unixtime_month"), 2, "month", null);

        this.dayInput = this.createInput(
            I18n.translate("supertable.control.filter.placeholder_unixtime_day"), 2, "day", null);

        this.hourInput = this.createInput(
            I18n.translate("supertable.control.filter.placeholder_unixtime_hour"), 2, "hour", null);

        this.minuteInput = this.createInput(
            I18n.translate("supertable.control.filter.placeholder_unixtime_minute"), 2, "minute", null);

        wrapper.appendChild(this.yearInput);
        wrapper.appendChild(this.monthInput);
        wrapper.appendChild(this.dayInput);
        wrapper.appendChild(this.hourInput);
        wrapper.appendChild(this.minuteInput);

        // restore filter settings
        if (initial) {
            if (Array.isArray(initial)) {
                if (initial[0])
                    this.yearInput.value = initial[0].toString();

                if (initial[1])
                    this.monthInput.value = initial[1].toString();

                if (initial[2])
                    this.dayInput.value = initial[2].toString();

                if (initial[3])
                    this.hourInput.value = initial[3].toString();

                if (initial[4])
                    this.minuteInput.value = initial[4].toString();
            } else {
                // assume it's a relative date
                let relative = new Date();

                relative /= JAVASCRIPT_TIME_GRANULARITY;
                relative += initial;
                relative *= JAVASCRIPT_TIME_GRANULARITY;

                relative = new Date(relative);

                console.log(`FilterUnixtime::ctor(): relative time, delta="${initial}", actual="${relative}"`);

                this.yearInput.value = relative.getFullYear().toString();
                this.monthInput.value = (relative.getMonth() + 1).toString();
                this.dayInput.value = relative.getDate().toString();
                this.hourInput.value = relative.getHours().toString();
                this.minuteInput.value = relative.getMinutes().toString();
            }

            this.changed = true;
        }

        container.appendChild(wrapper);

        this.value = null;

        // the validation logic of this filter is complex enough we need special handling for it
        this.validate();
    }

    createInput(placeholder, maxLength, clazz, initial)
    {
        let e = document.createElement("input");

        e.placeholder = placeholder;
        e.setAttribute("maxlength", maxLength);
        e.className = clazz;
        e.value = initial;
        e.addEventListener("input", event => this.onInput(event));

        return e;
    }

    validate()
    {
        // assume we're initially valid
        this.valid = true;

        let year = this.yearInput.value.trim(),
            month = this.monthInput.value.trim(),
            day = this.dayInput.value.trim(),
            hour = this.hourInput.value.trim(),
            minute = this.minuteInput.value.trim();

        // this is the only required field, others are optional
        if (year.length == 0)
            this.valid = false;
        else if (!isInteger(year))
            this.valid = false;

        // validate or use defaults for the others
        let hadMonth = false,
            hadDay = false,
            hadHour = false,
            hadMinute = false;

        if (month.length == 0)
            month = "1";
        else if (!isInteger(month))
            this.valid = false;
        else hadMonth = true;

        if (day.length == 0)
            day = "1";
        else if (!isInteger(day))
            this.valid = false;
        else hadDay = true;

        if (hour.length == 0)
            hour = "0";
        else if (!isInteger(hour))
            this.valid = false;
        else hadHour = true;

        if (minute.length == 0)
            minute = "0";
        else if (!isInteger(minute))
            this.valid = false;
        else hadMinute = true;

        if (this.valid) {
            try {
                // I don't know if these can throw exceptions. Better safe than sorry?
                year = parseInt(year, 10);
                month = parseInt(month, 10);
                day = parseInt(day, 10);
                hour = parseInt(hour, 10);
                minute = parseInt(minute, 10);
            } catch (e) {
                console.error(e);
                this.valid = false;
            }
        }

        // reject outright invalid dates (impose a "valid year" range)
        if (this.valid && (
                year < 2000 || year > 2050 ||
                month > 12 ||
                day > 31 ||
                hour < 0 || hour > 23 ||
                minute < 0 || minute > 59)
            ) {
            this.valid = false;
        }

        // if you specify the day, you must also specify the month
        if (this.valid && !hadMonth && hadDay)
            this.valid = false;

        if (this.valid && hadMonth && month < 1)
            this.valid = false;

        if (this.valid && hadDay && day < 1)
            this.valid = false;

        if (this.valid && !hadHour && hadMinute)
            this.valid = false;

        // validate the day if specified
        if (this.valid && hadDay && hadMonth && day > 0) {
            // days in month
            let dim = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

            // leap year February adjust
            if (year % 400 == 0 || (year % 100 != 0 && year % 4 == 0))
                dim[1] = 29;

            if (day > dim[month - 1]) {
                console.log(`dim check fail (month=${month}-1) day=${day} dim=${dim[month-1]}`);
                this.valid = false;
            }
        }

        if (this.valid) {
            // convert the date to unixtime because we know all the values already
            try {
                const d = new Date(year, month - 1, day, hour, minute, 0, 0);

                this.value = d.getTime() / JAVASCRIPT_TIME_GRANULARITY;
            } catch (e) {
                console.error(e);
                this.valid = false;
            }
        }
    }

    onInput(event)
    {
        this.changed = true;
        this.validate();
        this.notifyParent();
    }

    getSaveValue()
    {
        function converted(v)
        {
            // The input element values are strings, convert them back to integers if possible
            // TODO: what if this throws an exception?
            return v ? parseInt(v.trim(), 10) : null;
        }

        return [
            converted(this.yearInput.value),
            converted(this.monthInput.value),
            converted(this.dayInput.value),
            converted(this.hourInput.value),
            converted(this.minuteInput.value)
        ];
    }

    getFilterValue()
    {
        // already converted to unixtime in the input handler, due to its complexity
        return this.value;
    }
};

class FilterEditor {
    constructor(parentClass, container, columnDefs, initialColumn)
    {
        this.parentClass = parentClass;
        this.container = container;
        this.columnDefs = columnDefs;
        this.initialColumn = initialColumn;

        // Unfortunately we need a unique ID for each term row
        this.nextRowId = 0;

        // Filter editor objects, indexed by their row IDs (see nextRowID)
        this.editors = {};

        // Current filters. Must be... uh, filtered... before they can be used.
        this.rawFilters = [];

        // Actual usable filters
        this.usableFilters = [];

        // True if we can send the parent class change messages about changed filters
        this.canNotifyParent = true;
    }

    // Is the specified filter operator available for this type of column?
    isOperatorAvailableForType(available, type)
    {
        for (let i in available)
            if (available[i] == type)
                return true;

        return false;
    }

    fillOperatorBox(box, columnId, initialOperator)
    {
        if (!(columnId in this.columnDefs))
            throw `fillOperatorBox(): column ID "${columnId}" not found in column definitions!`;

        // remove old operators (this function is used to re-fill the operator box if the
        // column selection changes)
        while (box.options.length > 0)
            box.remove(0);

        const type = this.columnDefs[columnId].type;

        for (let i in OPERATOR_TYPES) {
            const operator = OPERATOR_TYPES[i];

            // Is this match operator available for this column type?
            // (ie. strings don't have a "less than" operator available)
            if (!this.isOperatorAvailableForType(operator.available, type))
                continue;

            let option = document.createElement("option");

            option.text = operator.title;
            option.dataset.operator = i;        // makes it easier to retrieve the type later

            if (operator.operator == initialOperator) {
                // "for this column type, this operator is the best by default"
                option.selected = true;
            }

            box.appendChild(option);
        }
    }

    // Filter editor class factory. Use "initial" to specify the initial settings, can be null.
    createTermEditor(type, container, initial)
    {
        switch (type) {
            case COLUMN_TYPE_STRING:
                return new FilterString(container, this, initial);

            case COLUMN_TYPE_INTEGER:
                return new FilterInteger(container, this, initial);

            case COLUMN_TYPE_FLOAT:
                return new FilterFloat(container, this, initial);

            case COLUMN_TYPE_BOOLEAN:
                return new FilterBoolean(container, this, initial);

            case COLUMN_TYPE_UNIXTIME:
                return new FilterUnixtime(container, this, initial);

            default:
                throw `createTermEditor(): unknown column type ${type}`;
        }
    }

    createTermRowBox(initial)
    {
        // The outer container box
        let outer = document.createElement("div");
        outer.className = "filter";
        outer.dataset.id = this.nextRowId.toString();       // needed when removing rows

        // Inner child containers
        let control = document.createElement("div"),
            term = document.createElement("div"),
            buttons = document.createElement("div");

        control.className = "control";
        term.className = "term";
        buttons.className = "buttons";

        // The active checkbox and it's label (the event listener must be added to the checkbox,
        // otherwise it can fire multiple times)
        let active = document.createElement("input");
        active.type = "checkbox";
        active.className = "active";
        active.title = I18n.translate("supertable.control.filter.title_active");
        active.addEventListener("click", event => this.onActiveClick(event));

        if (initial && initial[0])
            active.checked = true;

        control.appendChild(active);

        // Column names
        let column = document.createElement("select"),
            colType = null;

        for (let cid in this.columnDefs) {
            let option = document.createElement("option");

            option.dataset.cid = cid;       // makes it easier to retrieve the column ID later
            option.dataset.key = this.columnDefs[cid].key;
            option.text = this.columnDefs[cid].title;

            // select the initial operator, either from the saved settings or from the column settings
            if (initial) {
                if (initial[1] == cid) {
                    option.selected = true;
                    colType = this.columnDefs[cid].type;
                }
            } else {
                if (cid == this.initialColumn) {
                    option.selected = true;
                    colType = this.columnDefs[cid].type;
                }
            }

            column.appendChild(option);
        }

        if (colType === null) {
            // no initial column was selected, use the first defined
            const firstId = Object.keys(this.columnDefs)[0];
            const first = this.columnDefs[firstId];

            colType = first.type;
            column.selectedIndex = 0;

            console.warn(`FilterEditor::createTermRowBox(): no valid initial column was specified, using the first available ("${firstId}")`);

            // FIXME: If "initial" is not null specified, then it probably contains
            // an invalid column name too and the operator selector below will fail!
        }

        column.title = I18n.translate("supertable.control.filter.title_column");
        column.addEventListener("change", event => this.onColumnChanged(event));
        control.appendChild(column);

        // Match operator
        // FIXME: What happens if "initial" is valid, but the operator it specifies
        // is not valid for the column type? Need to take the possibilty of an
        // invalid column ID into account too.
        let operator = document.createElement("select");
        this.fillOperatorBox(operator,
                             initial ? initial[1] : this.initialColumn,
                             initial ? initial[2] : this.columnDefs[this.initialColumn].defaultOperator);
        operator.title = I18n.translate("supertable.control.filter.title_operator");
        operator.addEventListener("change", event => this.onOperatorChanged(event));
        control.appendChild(operator);

        // The filter term input editor
        let editor = this.createTermEditor(colType, term, initial ? initial[3] : null);
        outer.dataset.termType = colType;

        // Add/remove buttons (span elements actually, too many styles fight for links)
        let add = document.createElement("span");
        add.classList.add("add");
        add.textContent = "+";
        add.addEventListener("click", event => this.onAddFilterClick(event));
        add.title = I18n.translate("supertable.control.filter.title_button_add");
        buttons.appendChild(add);

        let remove = document.createElement("span");
        remove.classList.add("remove");
        remove.textContent = "×";
        remove.addEventListener("click", event => this.onRemoveFilterClick(event));
        remove.title = I18n.translate("supertable.control.filter.title_button_remove");
        buttons.appendChild(remove);

        outer.appendChild(control);
        outer.appendChild(term);
        outer.appendChild(buttons);

        return [outer, editor];
    }

    onActiveClick(e)
    {
        this.validateAndConvert();
    }

    onColumnChanged(e)
    {
        let item = e.target,
            row = item.parentNode.parentNode;   // escape the "control" div

        const columnId = item.selectedOptions[0].dataset.cid;

        // Refill the operator box
        this.fillOperatorBox(row.children[0].children[2],
                             columnId,
                             this.columnDefs[columnId].defaultOperator);

        // Create a new term editor if the column type (string/int/etc.) changes
        const currentTermType = row.dataset.termType,
              newTermType = this.columnDefs[columnId].type

        if (currentTermType != newTermType) {
            const rowId = row.dataset.id;
            let parent = row.children[1];

            // I'd love to just replace the child node, but I can't get it to work
            // TODO: Fix this
            parent.removeChild(parent.children[0]);

            this.editors[rowId] = this.createTermEditor(newTermType, parent);

            row.dataset.termType = newTermType;

            // A fresh start, so to speak
            row.children[1].classList.remove("invalid");
        }

        this.validateAndConvert();
    }

    onOperatorChanged(e)
    {
        this.validateAndConvert();
    }

    // Called from the child classes
    filterTermWasChanged()
    {
        this.validateAndConvert();
    }

    // Append a filter row
    onAddFilterClick(e)
    {
        this.addTermRow(null);
        this.validateAndConvert();
        this.updateButtons();
    }

    // Remove a filter row
    onRemoveFilterClick(e)
    {
        const id = e.target.parentNode.parentNode.dataset.id;

        console.log(`FilterEditor::onRemoveFilterClick(): removing a row, ID=${id}`);

        if (!(id in this.editors))
            throw `Row ${id} not in this.editors!`;

        delete this.editors[id];

        this.container.removeChild(e.target.parentNode.parentNode);

        // If the last filter row was removed, instantly create a new empty filter.
        // This way the user can quickly remove all filters (ie. "reset" them).
        if (this.container.children.length == 0) {
            console.log("FilterEditor::onRemoveFilterClick(): last term row removed, resetting");
            this.addTermRow(null);
        }

        this.validateAndConvert();
        this.updateButtons();
    }

    // Updates the add/remove button visibilities in term boxes
    updateButtons()
    {
        const numTerms = this.container.children.length

        for (let i = 0; i < numTerms; i++) {
            let buttons = this.container.children[i].children[2].children;

            // the "add" button is only visible on the last item
            if (i < numTerms - 1)
                buttons[0].style.visibility = "hidden";
            else buttons[0].style.visibility = "visible";
        }
    }

    // Validates each filter term and builds the internal array of usable filters
    // that others can request and use
    validateAndConvert()
    {
        const numTerms = this.container.children.length;

        // Extract new raw filters from the term editors
        this.rawFilters = [];

        for (let i = 0; i < numTerms; i++) {
            let row = this.container.children[i];
            const id = row.dataset.id;

            let valid = true,
                active = false;

            // Is the filter valid?
            if (!this.editors[id].isValid()) {
                row.children[0].children[0].disabled = true;
                valid = false;

                if (this.editors[id].hasBeenChanged()) {
                    // Don't flag terms invalid if they haven't been edited.
                    // They aren't active yet anyway.
                    row.children[1].classList.add("invalid");
                }
            } else {
                row.children[0].children[0].disabled = false;
                row.children[1].classList.remove("invalid");
            }

            // Is the filter enabled?
            if (row.children[0].children[0].checked)
                active = true;

            // We have a valid and active filter, store it. NOTE: MUST USE THE JSON COLUMN
            // KEYS FOR THE COLUMN, not column definition IDs!
            const jsonColumnKey = row.children[0].children[1].selectedOptions[0].dataset.key;
            const operator = row.children[0].children[2].selectedOptions[0].dataset.operator;

            this.rawFilters.push({
                valid: valid,
                active: active,
                key: jsonColumnKey,
                operator: OPERATOR_TYPES[operator].operator,
                save: this.editors[id].getSaveValue(),
                filter: this.editors[id].getFilterValue(),
            });
        }

        //console.log(this.rawFilters);

        // Convert the raw filters into something that can be actually used: remove inactive
        // and invalid terms and convert the structure into a fixed 2D array.
        let newUsableFilters = [];

        for (let i = 0; i < this.rawFilters.length; i++) {
            const filter = this.rawFilters[i];

            if (filter.valid && filter.active) {
                newUsableFilters.push([
                    filter.key,
                    filter.operator,
                    filter.filter,
                ]);
            }
        }

        //console.log(newUsableFilters);

        // Have the usable (ie. "actual") filters changed?
        let changed = false;

        if (newUsableFilters.length == this.usableFilters.length) {
            // Compare filters element-by-element. Must use .toString(), because, for example,
            // two Regexps cannot be compared with != directly in JavaScript.
            for (let i = 0; i < newUsableFilters.length && !changed; i++)
                for (let j = 0; j < 3 && !changed; j++)
                    if (newUsableFilters[i][j].toString() != this.usableFilters[i][j].toString())
                        changed = true;
        } else {
            // array lengths have changed, so there must be changes in filters
            changed = true;
        }

        if (this.canNotifyParent) {
            // We must actually save all raw filter changes. Otherwise inactive filters
            // would disappear on page reloads, for example.
            this.parentClass.rawFiltersChanged();
        }

        if (!changed) {
            console.log("FilterEditor::validateAndConvert(): no changes in filters");
            return;
        }

        this.usableFilters = newUsableFilters;

        // notify the parent class about *actual* filter changes
        if (this.canNotifyParent)
            this.parentClass.usableFiltersChanged();
    }

    // Adds a new term at the end of the list
    addTermRow(initial)
    {
        console.log(`FilterEditor::addTermRow(): creating a new term, ID=${this.nextRowId}, initial=${initial}`);

        let [termRow, editor] = this.createTermRowBox(initial);

        this.editors[this.nextRowId] = editor;
        this.container.appendChild(termRow);

        this.nextRowId++;
    }

    getUsableFilters()
    {
        return [...this.usableFilters];
    }

    saveRawFilters()
    {
/*
        //console.log(this.rawFilters.map(v => [v.active, v.key, v.operator, v.save]));
        console.log(this.rawFilters.map(obj => {
            //var r = {};
            //r[
            console.log(obj);
            return { active: obj.active, key: obj.key, op: obj.operator, save: obj.save};
        }));
*/

        return {
            version: 1,

            // not all values are needed
            raw: this.rawFilters.map(v => [v.active, v.key, v.operator, v.save]),
        };
    }

    // This wants the "raw" filters
    loadRawFilters(filters)
    {
        // the parent already knows about these filters
        this.canNotifyParent = false;

        // remove old filters, if any
        while (this.container.children.length > 0)
            this.container.removeChild(this.container.firstChild);

        this.editors = {};

        this.nextRowId = 0;     // we can reset this now

        // setup new filters
        if (filters && filters["raw"] && filters["raw"].length > 0) {
            for (let i in filters["raw"])
                this.addTermRow(filters["raw"][i]);
        } else {
            // no filters to restore, start from scratch
            this.addTermRow(null);
        }

        this.validateAndConvert();
        this.updateButtons();

        this.canNotifyParent = true;
    }

    // loads filters from the "simplified" preset format
    loadPresetFilter(preset)
    {
        this.loadRawFilters({ version: 1, raw: preset ? preset.filters : null });
    }
};

// -------------------------------------------------------------------------------------------------

// Base class for all mass operation handlers. You MUST inherit from this class
// if you want to create a new mass operation
class MassOperationBase {
    constructor(parent, container)
    {
        this.parent = parent;
        this.container = container;
    }

    haveValidSettings()
    {
        // Valid by default, since by default there are no settings
        return true;
    }

    isSingleShot()
    {
        // By default, we process the rows one at a time.
        // But it's possible to create mass operations that
        // process all selected rows in one call.
        return false;
    }

    updateStatus()
    {
        // Nothing to be done by default
    }

    processAllItems(items)
    {
        // Fails by default. Override this method to provide actual processing.
        return itemProcessingFailed();
    }

    processOneItem(item)
    {
        // Fails by default. Override this method to provide actual processing.
        return itemProcessingFailed();
    }
};

// TODO: convert all "enums" above to this format
const MultiSelectOp = Object.freeze({
    SELECT_VISIBLE: 1,
    SELECT_ALL: 2,
    DESELECT_VISIBLE: 3,
    DESELECT_NONVISIBLE: 4,
    DESELECT_ALL: 5,
    INVERT_VISIBLE: 6,
    DESELECT_PROCESSED_OK: 7,
});

class SuperTable {
    constructor(params)
    {
        this.id = params.id;
        this.container = params.container;
        this.csrf = document.querySelector("meta[name='csrf-token']").content;    // for AJAX calls

        this.settings = {
            flags: params.flags || 0,
            url: params.url || null,
            localstoreKey: params.localstoreKey || null,
            organisation: params.organisationName || "unknown",
            school: params.schoolName || "unknown",
            itemName: params.itemName || "",
            columnEditorSubtitle: params.columnEditorSubtitle || null,
            permitUserDeletion: params.permitUserDeletion || false,
            synchronisedDeletions: params.synchronisedDeletions || [],
        };

        if (this.settings.url === undefined || this.settings.url === null)
            throw "SuperTable::ctor(): missing AJAX URL";

        // Filtering
        this.filtering = {
            // filtering enabled?
            enabled: false,

            // global reverse match?
            reverse: false,

            // filter presets
            presets: params.filterPresets || [],

            // The current filters, if any
            filters: [],
        };

        // Sorting
        this.sorting = {
            // initial sort column
            column: null,

            // initial sort order
            order: SORT_ORDER_NONE,
        };

        // Columns
        this.columns = {
            // column definitions (types, flags, etc.)
            definitions: params.columnDefs || {},

            // the default columns, used when the user clicks "Reset" in the column editor
            defaultColumns: params.defaultColumns || [],

            // the default column that's initially selected when creating new filters
            defaultFilterColumn: params.defaultFilterColumn || null,

            // all columns that are currently usable, in the order they should be in the table
            columns: [],
        };

        if (this.columns.definitions === undefined || Object.keys(this.columns.definitions).length == 0)
            throw "SuperTable::ctor(): missing column definitions";

        // Deal with mass operations
        if (this.settings.flags & TABLE_FLAG_ENABLE_SELECTION) {
            if (!("massOperations" in params) || params["massOperations"].length == 0)
                throw "SuperTable::ctor(): TABLE_FLAG_ENABLE_SELECTION is set, but no mass operators were specified in SuperTable params";

            this.massOperations = params["massOperations"];
            this.currentMassOperation = null;
        }

        // UI element handles
        this.ui = {
            controlBox: null,           // the control box above the table
                columnsButton: null,
                reloadButton: null,
                status: null,
                count: null,
                filteringEnabled: null,
                filteringReverse: null,
                filteringPresets: null,
                filterEditor: null,     // the filter editor UI
            table: null,                // the table itself
        };

        /*
            (Almost) raw JSON for the data that's currently displayed in the table.

            The format is:

            [
                [ index, puavoId1, ROW_FLAG_*, row message, { raw item data copied from the JSON } ],
                [ index, puavoId2, ROW_FLAG_*, row message, { raw item data copied from the JSON } ],
                ...
            ]

            When new data is fetched from the server, it is merged with the current data,
            ie. row flags and messages are copied over for matching items. Deleted items
            are immediately removed. puavoId's are copied from the raw JSON data. Indexes
            point back to the original array; they're needed so that we can find the
            original row even when the item has gone through filtering and sorting.
        */
        this.currentData = null;

        // Saved columns version number
        this.columnsVersion = 1;

        // -----------------------------------------------------------------------------------------
        // Remove invalid column IDs from the list of wanted columns

        for (let columnKey in params["currentColumns"]) {
            const col = params["currentColumns"][columnKey];

            if (col[0] in this.columns.definitions)
                this.columns.columns.push(col);
            else console.warn(`SuperTable::ctor(): invalid column ID "${col[0]}", column skipped`);
        }

        if (this.columns.columns.length == 0)
            throw "SuperTable::ctor(): no available column definitions (all filtered out?)";

        // -----------------------------------------------------------------------------------------
        // Initial sorting

        if (params["initialSort"]) {
            // Have initial sort column and order
            let columnId = params["initialSort"]["column"],
                order = params["initialSort"]["order"];

            // is the column ID valid?
            let found = false;

            for (let i in this.columns.columns) {
                if (this.columns.columns[i][0] == columnId) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                console.warn(`SuperTable::ctor(): the initial sort column "${columnId}" does not exist, reverting to unsorted state`);
                columnId = null;
            } else {
                // the initial column exists, but is it sortable?
                const def = this.columns.definitions[columnId];

                if (def.flags & COLUMN_FLAG_SORTABLE) {
                    // validate the sort order
                    if (order != SORT_ORDER_ASCENDING && order != SORT_ORDER_DESCENDING) {
                        console.warn(`SuperTable::ctor(): the initial sort order "${order}" is not valid, defaulting to ascending`);
                        order = SORT_ORDER_ASCENDING;
                    }
                } else {
                    console.warn(`SuperTable::ctor(): the initial sort column "${columnId}" is not a sortable column, reverting to unsorted state`);
                    columnId = null;
                }
            }

            this.sorting.column = columnId;
            this.sorting.order = order;
        }

        // -----------------------------------------------------------------------------------------
        // Build the UI

        this.buildUI();
        this.restoreSettings();
        this.setupUIEventHandling();
        this.updateControlBoxStatus();

        // -----------------------------------------------------------------------------------------
        // Set up the collator object that we use to compare two strings when sorting

        this.collator = Intl.Collator(
            params.sortLocale || "fi-FI", {
                usage: "sort",              // sorting, not searching
                sensitivity: "accent",
                ignorePunctuation: true,
                numeric: true,              // this one I like the most
            }
        );

        // -----------------------------------------------------------------------------------------
        // Do the initial update

        this.setGoodStatus(I18n.translate("supertable.control.fetching"));

        this.filtering.filters = this.ui.filterEditor.getUsableFilters();

        this.getData();
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // SAVE/RESTORE SETTINGS

    // Restore settings from localstore
    restoreSettings()
    {
        if (!this.settings.localstoreKey)
            return;

        // If there are settings, parse them
        const settings = localStorage.getItem(this.settings.localstoreKey);

        if (!settings) {
            console.log(`SuperTable::restoreSettings(): no settings for "${this.settings.localstoreKey}", using (and saving) defaults`);

            // save initial settings
            this.saveSettings();

            // since there were no settings to restore, load a default (inactive) filter
            this.ui.filterEditor.loadRawFilters(null);

            return;
        }

        let parsed = null;

        try {
            parsed = JSON.parse(settings);
        } catch (e) {
            console.error(`SuperTable::restoreSettings(): could not parse settings from localstore item "${this.settings.localstoreKey}":`);
            console.error(settings);
            console.error(e);
            console.error(`SuperTable::restoreSettings(): settings for this table have been reset`);
            return;
        }

        // TODO: This needs to be rewritten. Not all possible cases are handled.

        //console.log(parsed);

        // We can't just copy the settings. Column definitions, etc. might have changed.

        let newColumns = [];

        if (parsed["columns"] && parsed["columns"]["version"] == this.columnsVersion) {
            const savedColumns = parsed["columns"];

            if (savedColumns["columns"] && savedColumns["columns"].length > 1) {
                for (let c in savedColumns["columns"]) {
                    const col = savedColumns["columns"][c];

                    if (col[0] in this.columns.definitions)
                        newColumns.push(col);
                    else {
                        // strip out removed column
                        console.log(`SuperTable::restoreSettings(): column "${col[0]}" no longer exists, removing`);
                    }
                }
            }
        }

        let newSorting = {
            // use the initial settings
            column: this.sorting.column,
            order: this.sorting.order,
        };

        if (parsed["sorting"]) {
            const savedSorting = parsed["sorting"];

            if (savedSorting["column"] in this.columns.definitions) {
                newSorting.column = savedSorting["column"];

                // restore the sort direction only if we can also restore the column
                if (savedSorting["order"] !== null) {
                    if (savedSorting["order"] == SORT_ORDER_ASCENDING ||
                        savedSorting["order"] == SORT_ORDER_DESCENDING) {
                        newSorting.order = savedSorting["order"];
                    } else console.log(`restoreSettings(): ignoring invalid sort order "${savedSorting["order"]}"`);
                }
            } else console.log(`restoreSettings(): sort column "${savedSorting["sort"]}" does not exist`);

            // If the initial/restored sort order does not exist in the visible columns, reset it
            let found = false;

            for (let c in newColumns) {
                const col = newColumns[c];

                if (col[0] == newSorting.column && col[1] == true) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                // restore the initial column and hope it is visible/usable
                console.log(`The restored sort column is NOT in the visible columns`);
                newSorting.column = this.sorting.column;
            }

            //console.log(newColumns);
            //console.log(newOrder);
        }

        this.columns.columns = newColumns;
        this.sorting = newSorting;

        // copy filters, but don't apply them as the filter editor doesn't exist yet
        if (parsed["filtering"]) {
            if (parsed["filtering"]["enabled"]) {
                this.filtering.enabled = true;
                this.ui.filteringEnabled.checked = true;
            }

            if (parsed["filtering"]["reverse"]) {
                this.filtering.reverse = true;
                this.ui.filteringReverse.checked = true;
            }

            this.ui.filterEditor.loadRawFilters(parsed["filtering"]["terms"]);
        }
    }

    // Save settings to localstore
    saveSettings()
    {
        if (!this.settings.localstoreKey)
            return;

        const settings = {
            filtering: {
                enabled: this.filtering.enabled,
                reverse: this.filtering.reverse,
                terms: this.ui.filterEditor ? this.ui.filterEditor.saveRawFilters() : null,
            },

            sorting: {
                column: this.sorting.column,
                order: this.sorting.order,
            },

            columns: {
                version: this.columnsVersion,
                columns: this.columns.columns,
            },
        };

        localStorage.setItem(this.settings.localstoreKey, JSON.stringify(settings));
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // UI CONSTRUCTION/UTILITY

    buildUI()
    {
        // TODO: Use HTML <template> elements for these?

        // -----------------------------------------------------------------------------------------
        // Setup master table controls

        let controls = newElem({ tag: "div", classes: ["tableToolbox"] });

        let cc = newElem({ tag: "section", classes: ["controls"] });

        // Column editor button
        this.ui.columnsButton = newElem({ tag: "a", id: `editColumnsButton-${this.id}`, classes: ["btn"] });
        this.ui.columnsButton.textContent = I18n.translate("supertable.control.select_columns");
        this.ui.columnsButton.title = I18n.translate("supertable.control.select_columns_title");
        cc.appendChild(this.ui.columnsButton);

        // The CSV download button
        this.ui.csvButton = newElem({ tag: "a", id: `csvButton-${this.id}`, classes: ["btn"] });
        this.ui.csvButton.textContent = I18n.translate("supertable.control.download_csv");
        this.ui.csvButton.title = I18n.translate("supertable.control.download_csv_title");
        cc.appendChild(this.ui.csvButton);

        // Table reload button
        this.ui.refreshButton = newElem({ tag: "a", id: `reloadTable-${this.id}`, classes: ["btn"] });
        this.ui.refreshButton.textContent = I18n.translate("supertable.control.reload");
        this.ui.refreshButton.title = I18n.translate("supertable.control.reload_title");
        cc.appendChild(this.ui.refreshButton);

        // Statistics
        this.ui.count = newElem({ tag: "p", classes: ["stats"] });
        cc.appendChild(this.ui.count);

        // Status messages
        this.ui.status = newElem({ tag: "p", id: "statusMessage-" + this.id, classes: ["status"] });
        cc.appendChild(this.ui.status);

        controls.appendChild(newElem({ tag: "header", content: I18n.translate("supertable.control.title") }));
        controls.appendChild(cc);

        // -----------------------------------------------------------------------------------------
        // Setup the filter editor

        // This contains the master filter checkboxes and the preset selector
        let filterHeader = newElem({ tag: "header", classes: ["filterControl"] });

        // enabled checkbox and label
        this.ui.filteringEnabled = newElem({ tag: "input", id: `enableFilter-${this.id}` });
        this.ui.filteringEnabled.type = "checkbox";

        let enabledLabel = newElem({ tag: "label", classes: ["filteringEnabled"] });
        enabledLabel.appendChild(document.createTextNode(I18n.translate("supertable.control.filtering_main_enabled")));
        enabledLabel.setAttribute("for", this.ui.filteringEnabled.id);
        enabledLabel.title = I18n.translate("supertable.control.filtering_main_enabled_title");

        // must wrap these elements in dummy DIVs, otherwise vertical alignments won't work
        let aa = newElem({ tag: "div" });
        aa.appendChild(this.ui.filteringEnabled);
        aa.appendChild(enabledLabel);
        filterHeader.appendChild(aa);

        // reverse checkbox and label
        this.ui.filteringReverse = newElem({ tag: "input", id: `invertFilter-${this.id}` });
        this.ui.filteringReverse.type = "checkbox";

        let reverseLabel = newElem({ tag: "label" });
        reverseLabel.appendChild(document.createTextNode(I18n.translate("supertable.control.filtering_main_reverse")));
        reverseLabel.setAttribute("for", this.ui.filteringReverse.id);
        reverseLabel.title = I18n.translate("supertable.control.filtering_main_reverse_title");

        let bb = newElem({ tag: "div" });
        bb.appendChild(this.ui.filteringReverse);
        bb.appendChild(reverseLabel);
        filterHeader.appendChild(bb);

        // filter presets selector and label
        if (this.filtering.presets.length > 0) {
            let presetLabel = newElem({ tag: "label" });
            presetLabel.appendChild(document.createTextNode(I18n.translate("supertable.control.filtering_presets")));

            this.ui.filteringPresets = newElem({ tag: "select", id: `presetSelector-${this.id}` });
            this.ui.filteringPresets.title = I18n.translate("supertable.control.filtering_presets_title");

            presetLabel.setAttribute("for", this.ui.filteringPresets.id);

            createOption(this.ui.filteringPresets,
                         I18n.translate("supertable.control.select_placeholder"),
                         null, false);

            createOption(this.ui.filteringPresets,
                         I18n.translate("supertable.control.filtering_reset"),
                         null, true);

            for (let i in this.filtering.presets) {
                const preset = this.filtering.presets[i];

                if (preset.title && preset.id)
                    createOption(this.ui.filteringPresets, preset.title, i, true);
            }

            this.ui.filteringPresets.selectedIndex = 0;

            let cc = newElem({ tag: "div" });

            cc.appendChild(presetLabel);
            cc.appendChild(this.ui.filteringPresets);
            filterHeader.appendChild(cc);
        }

        // Container for the filter editor
        let filterList = newElem({ tag: "section", id: `filterList-${this.id}`, classes: ["filterList"] });

        // This class maintains the filter term rows
        this.ui.filterEditor = new FilterEditor(
            this,
            filterList,
            this.columns.definitions,
            this.columns.defaultFilterColumn  // the default column that's initially selected on filter term rows
        );

        // this contains everything related to filters
        let filters = newElem({ tag: "div", classes: ["tableToolbox", "filters"] });
        filters.appendChild(filterHeader);
        filters.appendChild(filterList);

        // -----------------------------------------------------------------------------------------
        // Multiselection / mass edit tools (if enabled)

        let massOperationsContainer = null;

        if (this.settings.flags & TABLE_FLAG_ENABLE_SELECTION) {
            // -------------------------------------------------------------------------------------
            // Controls

            this.ui.massOperationSelector = newElem({ tag: "select" });

            createOption(
                this.ui.massOperationSelector, I18n.translate("supertable.control.select_placeholder"),
                null, false);

            for (let id in this.massOperations) {
                createOption(this.ui.massOperationSelector,
                             this.massOperations[id].title,
                             id,
                             true);
            }

            // the "proceed" button, always initially disabled
            this.ui.massOperationProceedButton = newElem({ tag: "button", });
            this.ui.massOperationProceedButton.appendChild(
                document.createTextNode(I18n.translate("supertable.control.mass_op.proceed")));
            this.ui.massOperationProceedButton.disabled = true;

            // the progress bar
            this.ui.massOperationProgressBar = newElem({ tag: "progress" });
            this.ui.massOperationProgressBar.setAttribute("max", "0");
            this.ui.massOperationProgressBar.setAttribute("value", "0");
            this.ui.massOperationProgressCount = newElem({ tag: "p", classes: ["progressCount"] });

            let controlBox = newElem({ tag: "div", classes: ["selector"] });

            controlBox.appendChild(newElem({
                tag: "p",
                innerText: I18n.translate("supertable.control.mass_op.select_operation")
            }));

            controlBox.appendChild(this.ui.massOperationSelector);
            controlBox.appendChild(this.ui.massOperationProceedButton);
            controlBox.appendChild(this.ui.massOperationProgressBar);
            controlBox.appendChild(this.ui.massOperationProgressCount);

            // -------------------------------------------------------------------------------------
            // Operator settings container

            this.ui.massOperationSettings = newElem({ tag: "div", classes: ["settings"] });
            this.ui.massOperationSettings.style.display = "none";

            // -------------------------------------------------------------------------------------
            // Status and warning messages

            this.ui.massOperationStatus = newElem({ tag: "p", classes: ["status"] });

            // the warning that's displayed if the current filter hides something you've selected
            let filterHideWarning = newElem({
                tag: "div",
                id: "filterHideWarning",
                classes: ["hiddenWarning"],
                content: I18n.translate("supertable.control.mass_op.hidden_warning")
            });

            filterHideWarning.style.display = "none";
            this.haveHiddenSelectedRows = false;

            // -------------------------------------------------------------------------------------
            // Build the mass operations box

            let content = newElem({
                tag: "section",
                classes: ["massOperation"],
            });

            content.appendChild(controlBox);
            content.appendChild(this.ui.massOperationSettings);
            this.createMultiselectMenu(content);
            content.appendChild(this.ui.massOperationStatus);
            content.appendChild(filterHideWarning);

            massOperationsContainer = newElem({
                tag: "div",
                classes: ["tableToolbox"],
            });

            massOperationsContainer.appendChild(newElem({
                tag: "header",
                contentText: I18n.translate("supertable.control.mass_op.title")
            }));

            massOperationsContainer.appendChild(content);

            // What row was previously clicked on?
            this.previouslyClickedRow = null;
        }

        // -----------------------------------------------------------------------------------------
        // Assemble the final layout

        this.ui.controlBox = newElem({
            tag: "div",
            id: "tableControl-" + this.id,
            classes: ["tableControls"],
        });

        this.ui.controlBox.appendChild(controls);
        this.ui.controlBox.appendChild(filters);

        if (massOperationsContainer)
            this.ui.controlBox.appendChild(massOperationsContainer);

        this.container.appendChild(this.ui.controlBox);

        this.ui.table = newElem({ tag: "div" });
        this.container.appendChild(this.ui.table);
    }

    // Set the control box event callbacks. Cannot be done in buildUI() because we will
    // set checkboxes and such and that would cause events to fire.
    setupUIEventHandling()
    {
        this.ui.columnsButton.addEventListener("click", event => this.editColumnsClicked(event));
        this.ui.csvButton.addEventListener("click", event => this.downloadCSVClicked(event));
        this.ui.refreshButton.addEventListener("click", event => this.refreshClicked(event));
        this.ui.filteringEnabled.addEventListener("click", event => this.filteringEnabledClicked(event));
        this.ui.filteringReverse.addEventListener("click", event => this.filteringReverseClicked(event));

        if (this.ui.filteringPresets)
            this.ui.filteringPresets.addEventListener("change", event => this.filteringPresetChanged(event));

        if (this.ui.massOperationSelector)
            this.ui.massOperationSelector.addEventListener("change", event => this.massOperationChanged(event));

        if (this.ui.massOperationProceedButton)
            this.ui.massOperationProceedButton.addEventListener("click", event => this.doMassOperation(event));
    }

    disableTable()
    {
        this.ui.table.classList.add("disabledTable");
    }

    enableTable()
    {
        this.ui.table.classList.remove("disabledTable");
    }

    updateControlBoxStatus()
    {
        let numColumns = 0;

        for (let i in this.columns.columns)
            if (this.columns.columns[i][1])
                numColumns++;

        this.ui.columnsButton.textContent =
            `${I18n.translate("supertable.control.select_columns")} (${numColumns}/${Object.keys(this.columns.definitions).length})`;
    }

    clearStatus()
    {
        this.ui.status.textContent = "";
    }

    setGoodStatus(message)
    {
        this.ui.status.textContent = "[" + message + "]";
        this.ui.status.classList.add("good");
        this.ui.status.classList.remove("failed");
    }

    setFailStatus(message)
    {
        this.ui.status.textContent = "[" + message + "]";
        this.ui.status.classList.remove("good");
        this.ui.status.classList.add("failed");
    }

    // Enable/disable filtering checkbox
    filteringEnabledClicked(e)
    {
        this.filtering.enabled = this.ui.filteringEnabled.checked;

        this.filtering.filters = this.ui.filterEditor.getUsableFilters();

        this.saveSettings();

        this.disableTable();
        this.updateTable();
        this.enableTable();
    }

    // Reverse filtering checkbox
    filteringReverseClicked(e)
    {
        this.filtering.reverse = this.ui.filteringReverse.checked;
        this.filtering.filters = this.ui.filterEditor.getUsableFilters();

        this.saveSettings();

        if (this.filtering.enabled) {
            this.disableTable();
            this.updateTable();
            this.enableTable();
        }
    }

    // Change the filtering preset
    filteringPresetChanged(e)
    {
        const presetIndex = e.target.selectedOptions[0].dataset.id;

        if (presetIndex == null) {
            // no index -> reset
            this.ui.filterEditor.loadPresetFilter(null);
        } else {
            this.ui.filterEditor.loadPresetFilter(this.filtering.presets[presetIndex]);
        }

        this.filtering.filters = this.ui.filterEditor.getUsableFilters();

        this.saveSettings();

        if (this.filtering.enabled) {
            this.disableTable();
            this.updateTable();
            this.enableTable();
        }
    }

    // Called from the filter editor, to save the raw filter settings even if they haven't changed
    rawFiltersChanged()
    {
        this.saveSettings();
    }

    // Called from the filter editor, to indicate that filters have changed
    usableFiltersChanged()
    {
        this.filtering.filters = this.ui.filterEditor.getUsableFilters();

        if (this.filtering.enabled) {
            this.disableTable();
            this.updateTable();
            this.enableTable();
        }
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // AJAX CALLS

    getData()
    {
        var us = this;
        const t0 = performance.now();

        // TODO: I'm fairly sure this could be implemented using fetch(). It has no
        // timeout and error handling must be completely rewritten, but eh.
        $.get({
            url: this.settings.url,
            dataType: "text",   // we'll parse the returned JSON ourselves thank you very much
            async: true,
            timeout: 10000,     // this is dangerous! some places have lots of data and can take a long time to process a request!

            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": this.csrf,
            },

            beforeSend: function(jq, settings) {
                us.ui.refreshButton.disabled = true;
                us.setGoodStatus(I18n.translate("supertable.control.fetching"));
                us.disableTable();
            },

            fail: function(data) {
                us.ui.refreshButton.disabled = false;
                us.setFailStatus(I18n.translate("supertable.control.failed"));
                us.enableTable();
            },

            complete: function(data) {
                us.ui.refreshButton.disabled = false;

                let rawNewData = null,
                    error = false;

                if (data.readyState == 0 && data.statusText == "error") {
                    // Is the server up?
                    us.setFailStatus(I18n.translate("supertable.control.network_error"));
                    error = true;
                } else if (data.readyState == 0 && data.statusText == "timeout") {
                    // The server's not responding fast enough
                    us.setFailStatus(I18n.translate("supertable.control.timeout"));
                    error = true;
                } else if (data.status == 200) {
                    // Parse the received JSON
                    try {
                        rawNewData = JSON.parse(data.responseText);
                    } catch (e) {
                        us.setFailStatus(I18n.translate("supertable.control.json_fail"));
                        console.log(e);
                        console.log(data.responseText);
                        error = true;
                    }
                } else {
                    // Something else failed
                    us.setFailStatus(I18n.translate("supertable.control.server_error") + data.status);
                    error = true;
                }

                if (!error) {
                    const t1 = performance.now();
                    console.log(`SuperTable::getData(): took ${t1 - t0} ms to get data from the server`);

                    us.clearStatus();

                    // Merge the new server data with the old data. Assume everything that
                    // comes back from the server contains the unique PuavoID of the item
                    // in question. Use these IDs as row keys.
                    let newData = [];

                    // puavoid -> item lookup table for the existing data
                    let oldData = {};

                    for (let i in us.currentData)
                        oldData[us.currentData[i][1]] = us.currentData[i];

                    for (let i in rawNewData) {
                        const id = parseInt(rawNewData[i].id, 10);
                        let old = null;

                        if (id in oldData)
                            old = oldData[id];

                        const index = parseInt(i, 10);

                        if (old) {
                            // copy flags and the status message from the old data
                            newData.push([ index, id, old[2], old[3], {...rawNewData[i]} ]);
                            //console.log(`Item ${id} already exists, merging`);
                        } else {
                            // new entry
                            newData.push([ index, id, 0, null, {...rawNewData[i]} ]);
                            //console.log(`Item ${id} is new`);
                        }
                    }

                    us.currentData = [...newData];
                    //us.currentData = [...newData];      // make a deep copy

                    const t2 = performance.now();
                    console.log(`SuperTable::getData(): took ${t2 - t1} ms to merge the datasets`);

                    us.updateTable();

                    if (us.settings.flags & TABLE_FLAG_ENABLE_SELECTION)
                        us.updateMassOperationStatus();
                }

                us.enableTable();
            },
        });
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // CALLBACKS

    // Show the column editor and apply changes
    editColumnsClicked(e)
    {
        e.preventDefault();

        let us = this;

        new ColumnEditor(this.settings.columnEditorSubtitle,
                         this.columns.definitions, this.columns.defaultColumns)
                         .show(this.columns.columns, function(newColumns) {

            // Did anything change?
            let changed = false;

            for (let i = 0; i < us.columns.columns.length; i++) {
                const currCol = us.columns.columns[i];

                if (currCol[0] != newColumns[i][0] || currCol[1] != newColumns[i][1]) {
                    changed = true;
                    break;
                }
            }

            if (!changed) {
                console.log("SuperTable::editColumns(): no changes were made to columns");
                return;
            }

            us.columns.columns = [...newColumns];

            // The columns have changed. Is the current sort column still visible?
            const currentOrder = us.sorting.column;
            let found = false;

            for (let i in newColumns) {
                if (newColumns[i][0] == currentOrder && newColumns[i][1]) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                // It's not, revert the table back to unsorted state
                if (us.sorting.column)
                    console.log("SuperTable::editColumns(): the current sort column is no longer visible");

                // TODO: Select some other column instead? Need to check if other sortable
                // columns even exist.
                us.sorting.column = null;
                us.sorting.order = SORT_ORDER_NONE;
            }

            us.updateTable();
            us.updateControlBoxStatus();
            us.saveSettings();
        });
    }

    // Download the current table contents as CSV
    // TODO: display a dialog for choosing export settings
    // (all rows / only visible rows, all columns / only visible columns,
    // possibly other formats than CSV, etc.)
    downloadCSVClicked(e)
    {
        e.preventDefault();

        try {
            // Convert the data from "objects" to plain arrays. Otherwise the output will be
            // just "[object Object]" garbage, because that's what JavaScript does.
            let out = "";

            // Figure out the visible columns and build the CSV header row
            let visible = [];
            let headerRow = [];

            for (let i in this.columns.columns) {
                const c = this.columns.columns[i];

                if (c[1]) {           // only visible columns
                    visible.push(c[0]);
                    headerRow.push(`"${this.columns.definitions[c[0]].key}"`);
                }
            }

            out += headerRow.join(",") + "\n";

            // There's no copy of the data that's been filtered but not sorted, so filter it
            let newData = null,
                hiddenIDs = null;

            if (!this.filtering.enabled) {
                newData = [...this.currentData];
                hiddenIDs = new Set();
            } else {
                [newData, hiddenIDs] = this.filterData(
                    this.filtering.filters,
                    this.filtering.reverse,
                    this.columns.definitions,
                    [...this.currentData]);
            }

            // Copy the visible columns, in order, from each row. Convert contents to strings.
            for (let i in newData) {
                const srcRow = newData[i][4];
                let dstRow = new Array(visible.length);

                for (let j in visible) {
                    const value = srcRow[visible[j]];
                    let converted = null;

                    if (value === undefined || value === null)
                        converted = "";
                    else {
                        const type = this.columns.definitions[visible[j]].type;
                        const subType = this.columns.definitions[visible[j]].subType || null;

                        // Do type-specific data conversions
                        switch (type) {
                            case COLUMN_TYPE_STRING:
                            case COLUMN_TYPE_INTEGER:
                            case COLUMN_TYPE_FLOAT:
                            default:
                                converted = value;
                                break;

                            case COLUMN_TYPE_BOOLEAN:
                                converted = value ? "true" : "false";
                                break;

                            case COLUMN_TYPE_UNIXTIME:
                                converted = convertTimestamp(value);
                                break;
                        }

                        // If this subtype has its own type conversions,
                        // apply them and overwrite the value set above
                        if (subType) {
                            switch (subType) {
                                case COLUMN_SUBTYPE_DEVICE_PRIMARY_USER:
                                    // [Object object] isn't very useful
                                    converted = value["title"];
                                    break;

                                default:
                                    break;
                            }
                        }
                    }

                    // always quote all values, even if empty
                    dstRow[j] = `"${converted}"`;
                }

                out += dstRow.join(",") + "\n";
            }

            const timestamp = I18n.strftime(new Date(), "%Y-%m-%d-%H-%M-%S");

            // Build a blob object (it must be an array for some reason), then trigger a download.
            // Download code stolen from StackOverflow.
            // @@@FIXME: For some reason, this clears the browser console?
            const b = new Blob([out], { type: "text/csv" });

            let a = window.document.createElement("a");
            a.href = window.URL.createObjectURL(b);

            if (this.settings.flags & TABLE_FLAG_ORGANISATION_DEVICES) {
                // the whole organisation
                a.download = `${this.settings.organisation}_devices_${timestamp}.csv`;
            } else {
                // a single school
                a.download = `${this.settings.organisation}_${this.settings.school}_${this.id}_${timestamp}.csv`;
            }

            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
        } catch (e) {
            console.log(e);
            alert("CSV generation error:\n\n" + e + "\n\nSee the browser console for details.");
        }
    }

    // Reload the table contents without reloading the whole page
    refreshClicked(e)
    {
        e.preventDefault();
        this.getData();
    }

    // A sort header was clicked, re-sort the table
    clickedColumnHeader(e)
    {
        const columnId = e.target.dataset.columnId;

        if (this.sorting.column == columnId) {
            // Same column, just change the order
            if (this.sorting.order == SORT_ORDER_ASCENDING)
                this.sorting.order = SORT_ORDER_DESCENDING;
            else this.sorting.order = SORT_ORDER_ASCENDING;
        } else {
            // Change the column
            this.sorting.column = columnId;
            this.sorting.order = SORT_ORDER_ASCENDING;  // the default order
        }

        this.updateTable();

        // save the new sort settings
        this.saveSettings();
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // MULTISELECTION AND MASS OPERATIONS

    // Creates the mass operation UI when the operation type changes
    massOperationChanged(event)
    {
        let selector = this.ui.massOperationSelector;
        const id = selector.childNodes[selector.selectedIndex].dataset.id;
        const operation = this.massOperations[id];

        let newSettings = null;

        // If the selected mass operation as a UI, create it
        if (operation.hasSettings)
            newSettings = document.createElement("div");

        // Instantiate the class that can do the mass operation
        let newOperation = new operation.clazz(this, newSettings);

        let settings = this.ui.massOperationSettings;

        // Replace the old UI with the new UI and figure out the container visibility
        if (settings.firstChild) {
            if (newSettings) {
                // replace
                settings.firstChild.remove();
                settings.appendChild(newSettings);
            } else {
                // hide
                settings.style.display = "none";
                settings.firstChild.remove();
            }
        } else {
            if (newSettings) {
                // show
                settings.appendChild(newSettings);
                settings.style.display = "block";
            }
        }

        this.currentMassOperation = newOperation;
        this.massOperationChildStatus = null;
        this.updateMassOperationStatus();
    }

    // Updates the selection status/counter display if multiselection is enabled
    updateMassOperationStatus()
    {
        let selected = 0,
            ok = 0,
            failed = 0,
            hiddenSelected = false;

        for (var i in this.currentData) {
            const flags = this.currentData[i][2];

            if (flags & ROW_FLAG_SELECTED) {
                selected++;

                if (flags & ROW_FLAG_FILTERED)
                    hiddenSelected = true;
            }

            if (flags & ROW_FLAG_PROCESSED) {
                if (flags & ROW_FLAG_PROCESSING_OK)
                    ok++;

                if (flags & ROW_FLAG_PROCESSING_FAIL)
                    failed++;
            }
        }

        let parts = Array();

        //if (this.currentData.length > 0 && (selected > 0 || ok > 0 || failed > 0))
        //    parts.push(`<span class="total">Yhteensä ${this.currentData.length} riviä</span>`);

        //if (selected > 0)
        parts.push(
            `<span class="selected">${selected}/${this.currentData.length} ${I18n.translate("supertable.control.mass_op.status.selected")}</span>`);

        if (ok > 0)
            parts.push(`<span class="ok">${ok} ${I18n.translate("supertable.control.mass_op.status.ok")}</span>`);

        if (failed > 0)
            parts.push(`<span class="failed">${failed} ${I18n.translate("supertable.control.mass_op.status.failed")}</span>`);

        if (parts.length == 0)
            this.ui.massOperationStatus.style.display = "none";
        else {
            this.ui.massOperationStatus.style.display = "block";
            this.ui.massOperationStatus.innerHTML = parts.join(", ");
        }

        // Enable or disable the "proceed" button
        let enabled = false;

        if (this.currentData.length > 0) {
            if (selected > 0) {
                if (this.currentMassOperation) {
                    enabled = true;

                    if (!this.currentMassOperation.haveValidSettings())
                        enabled = false;
                }
            }
        }

        this.ui.massOperationProceedButton.disabled = !enabled;

        // Warn user about selected rows that aren't currently visible
        document.getElementById("filterHideWarning").style.display = hiddenSelected ? "block" : "none";
        this.haveHiddenSelectedRows = hiddenSelected;
    }

    // Called from the mass operation settings child object, to signal that
    // something in it has changed that (potentially) needs our attention
    massOperationSettingsChanged()
    {
        const validNow = this.currentMassOperation.haveValidSettings();

        // cache the status, to avoid calling updateMassOperationStatus() on every keypress
        if (validNow != this.massOperationChildStatus) {
            this.massOperationChildStatus = validNow;
            this.updateMassOperationStatus();
        }
    }

    selectTableRow(tr)
    {
        tr.children[0].classList.add("selected");
        tr.classList.add("selectedRow");
    }

    deselectTableRow(tr)
    {
        tr.children[0].classList.remove("selected");
        tr.classList.remove("selectedRow");
        tr.classList.remove("processingSuccessfull");
        tr.classList.remove("processingFailed");
    }

    clearPreviousRow()
    {
        if (this.previouslyClickedRow) {
            this.previouslyClickedRow.parentNode.classList.remove("previousRow");
            this.previouslyClickedRow = null;
        }
    }

    // Set/unset a single checkbox
    rowCheckboxClicked(e)
    {
        let target = e.target;

        e.preventDefault();

        if (e.shiftKey && this.previouslyClickedRow != null && this.previouslyClickedRow != target) {
            // Range selection between the previously clicked row and this row

            // Select or deselect the items?
            const state = this.currentData[parseInt(this.previouslyClickedRow.dataset.rowKey, 10)][2] & ROW_FLAG_SELECTED;

            // The visible table rows don't necessarily map linearly onto the original data rows.
            // Figure out which table rows are between the two clicked rows, ending inclusive.
            let allRows = this.ui.table.children[0].children[1].rows;
            let startRowIndex = -1,
                endRowIndex = -1;

            for (let i in allRows) {
                let row = allRows[i];

                if (allRows[i] == this.previouslyClickedRow.parentNode)
                    startRowIndex = parseInt(i, 10);    // sigh

                if (allRows[i] == target.parentNode)
                    endRowIndex = parseInt(i, 10);      // double sigh
            }

            if (startRowIndex == -1 || endRowIndex == -1) {
                window.alert("Can't determine startRowIndex or endRowIndex");
                return;
            }

            if (startRowIndex > endRowIndex)
                [startRowIndex, endRowIndex] = [endRowIndex, startRowIndex];

            console.log(`SuperTable::rowCheckboxClicked(): range selection from ${startRowIndex} to ${endRowIndex}, state is ${state}`);

            // Then process the rows in order. They're all visible.
            for (let i = startRowIndex; i <= endRowIndex; i++) {
                const origIndex = parseInt(allRows[i].children[0].dataset.rowKey, 10);

                let item = this.currentData[origIndex];
                const selected = item[2] & ROW_FLAG_SELECTED;

                if (selected == state)
                    continue;

                if (state) {
                    item[2] |= ROW_FLAG_SELECTED;
                    this.selectTableRow(allRows[i]);
                } else {
                    item[2] &= ~(ROW_FLAG_SELECTED | ROW_FLAG_PROCESSED | ROW_FLAG_PROCESSING_OK | ROW_FLAG_PROCESSING_FAIL);
                    this.deselectTableRow(allRows[i]);
                }
            }
        } else {
            // Just one row
            let item = this.currentData[parseInt(target.dataset.rowKey, 10)];

            if (item[2] & ROW_FLAG_SELECTED) {
                // deselect
                item[2] &= ~(ROW_FLAG_SELECTED | ROW_FLAG_PROCESSED | ROW_FLAG_PROCESSING_OK | ROW_FLAG_PROCESSING_FAIL);
                this.deselectTableRow(target.parentNode);
            } else {
                // select
                item[2] |= ROW_FLAG_SELECTED;
                this.selectTableRow(target.parentNode);
            }
        }

        // Keep track of the previously clicked row
        if (this.previouslyClickedRow)
            this.previouslyClickedRow.parentNode.classList.remove("previousRow");

        this.previouslyClickedRow = target;
        this.previouslyClickedRow.parentNode.classList.add("previousRow");

        this.updateMassOperationStatus();
    }

    doMassOperation(event)
    {
        if (this.haveHiddenSelectedRows) {
            if (!window.confirm(I18n.translate("supertable.control.mass_op.filtered_confirm")))
                return;
        } else {
            if (!window.confirm(I18n.translate("supertable.control.mass_op.confirm")))
                return;
        }

        /*
        Problem 1:
            If the items are not processed in the order they currently are in the
            table, it looks stupid, as the progress "jumps" around seemingly randomly,
            as the underlying items are not in the same order they appear.

        Solution 1:
            Iterate over the table and process items in the order they appear.

        Problem 2:
            Filters exist. Some of the selected rows can be invisible. If we simply
            go through the table in order, these rows are not processed.

        Solution 2:
            Process visible items first, in order, then the other items, in whatever
            order they are (they aren't visible).
        */


        function beginOperation(ctx, numItems)
        {
            // Disable as much of the UI as possible, to prevent user from messing things up
            ctx.ui.filteringEnabled.disabled = true;
            ctx.ui.filteringReverse.disabled = true;

            if (ctx.ui.filteringPresets)
                ctx.ui.filteringPresets.disabled = true;

            ctx.ui.massOperationSelector.disabled = true;
            ctx.ui.massOperationProceedButton.disabled = true;

            ctx.ui.massOperationProgressBar.style.visibility = "visible";
            ctx.ui.massOperationProgressBar.setAttribute("max", numItems);
            ctx.ui.massOperationProgressBar.setAttribute("value", 0);
        }

        function endOperation(ctx)
        {
            //ctx.ui.massOperationProgressBar.style.visibility = "hidden";
            //ctx.ui.massOperationProgressCount.innerHTML = "";

            // Re-enable the UI
            ctx.ui.filteringEnabled.disabled = false;
            ctx.ui.filteringReverse.disabled = false;

            if (ctx.ui.filteringPresets)
                ctx.ui.filteringPresets.disabled = false;

            ctx.ui.massOperationSelector.disabled = false;
            ctx.ui.massOperationProceedButton.disabled = false;
            ctx.updateMassOperationStatus();
        }

        function updateProgress(ctx, count, current)
        {
            ctx.ui.massOperationProgressBar.setAttribute("value", current);
            ctx.ui.massOperationProgressCount.innerHTML = `${current}/${count}`;
        }

        function updateItemFlagsAndRow(item_wrapper, result)
        {
            let item = item_wrapper.item;
            let tableRow = item_wrapper.row;

            let flags = item[2];

            flags &= ~(ROW_FLAG_PROCESSING_OK | ROW_FLAG_PROCESSING_FAIL);

            if (result.success)
                flags |= ROW_FLAG_PROCESSING_OK;
            else {
                flags |= ROW_FLAG_PROCESSING_FAIL;
                item[3] = result.message;  // the error message returned from the server
            }

            flags |= ROW_FLAG_PROCESSED;
            item[2] = flags;

            if (tableRow) {
                // Update visible row styles directly and immediately,
                // without rebuilding the whole table
                if (result.success) {
                    tableRow.classList.add("processingSuccessfull");
                    tableRow.classList.remove("processingFailed");
                    tableRow.title = "";
                } else {
                    tableRow.classList.remove("processingSuccessfull");
                    tableRow.classList.add("processingFailed");
                    tableRow.title = result.message;
                }
            }
        }

        this.clearPreviousRow();

        // Prepare the data
        let numSelected = 0,
            currentItem = 0;

        for (let i in this.currentData) {
            if (this.currentData[i][2] & ROW_FLAG_SELECTED)
                numSelected++;

            // We have two loops, use the processed flag to prevent
            // items from being processed multiple times
            this.currentData[i][2] &= ~ROW_FLAG_PROCESSED;
        }

        let itemsToBeProcessed = [],
            rawItemsToBeProcessed = [];

        // Visible rows first, in the order they're on the screen
        let allRows = this.ui.table.children[0].children[1].rows;

        for (let i = 0; i < allRows.length; i++) {
            const rowKey = parseInt(allRows[i].children[0].dataset.rowKey, 10);
            let item = this.currentData[rowKey];

            if (!(item[2] & ROW_FLAG_SELECTED))
                continue;

            item[2] |= ROW_FLAG_PROCESSED;
            itemsToBeProcessed.push({ item: item, row: allRows[i] });

            if (this.currentMassOperation.isSingleShot())
                rawItemsToBeProcessed.push(item[4]);
        }

        // Then invisible (filtered) rows, in whatever order they appear
        for (let i in this.currentData) {
            let item = this.currentData[i];

            if (!(item[2] & ROW_FLAG_SELECTED))
                continue;

            // Already did this item in the above loop
            if (item[2] & ROW_FLAG_PROCESSED)
                continue;

            itemsToBeProcessed.push({ item: item, row: null });
        }

        let us = this;

        beginOperation(us, itemsToBeProcessed.length);
        updateProgress(us, itemsToBeProcessed.length, 1);

        // Use a Promise object to chain multiple other Promises. This loop
        // will exit before the first Promise is resolved.
        var sequence = Promise.resolve();

        if (us.currentMassOperation.isSingleShot()) {
            sequence = sequence.then(function() {
                // Do everything in one call
                return us.currentMassOperation.processAllItems(rawItemsToBeProcessed);
            }).then(function(result) {
                // Update all rows at once and finish the operation
                for (let i = 0; i < itemsToBeProcessed.length; i++)
                    updateItemFlagsAndRow(itemsToBeProcessed[i], result);

                updateProgress(us, itemsToBeProcessed.length, itemsToBeProcessed.length);
                endOperation(us, itemsToBeProcessed.length);
            });
        } else {
            for (let i = 0; i < itemsToBeProcessed.length; i++) {
                sequence = sequence.then(function() {
                    // "Schedule" an operation. This can cause a network request.
                    return us.currentMassOperation.processItem(itemsToBeProcessed[i].item[4]);
                }).then(function(result) {
                    // Display the results (update the table and progress counters)
                    updateItemFlagsAndRow(itemsToBeProcessed[i], result);

                    if (i >= itemsToBeProcessed.length - 1) {
                        // that was the last item
                        // TODO: This should be replaceable with Promise.all().
                        updateProgress(us, itemsToBeProcessed.length, i + 1);
                        endOperation(us, itemsToBeProcessed.length);
                    } else {
                        // still ongoing
                        updateProgress(us, itemsToBeProcessed.length, i + 1);
                    }
                });
            }
        }
    }

    // Called from the checkbox column popup menu
    multiselectOperation(event, operation)
    {
        event.preventDefault();

        let didSomething = false;

        this.clearPreviousRow();

        if (operation == MultiSelectOp.SELECT_VISIBLE ||
            operation == MultiSelectOp.DESELECT_VISIBLE ||
            operation == MultiSelectOp.INVERT_VISIBLE) {
            // These operate on currently visible rows
            let rows = this.ui.table.children[0].children[1].rows;

            for (let i = 0; i < rows.length; i++) {
                let col = rows[i].children[0];

                if (col.dataset.rowKey === undefined) {
                    // happens on empty tables
                    continue;
                }

                // find the original item
                let item = this.currentData[parseInt(col.dataset.rowKey, 10)];

                // combine two different states into one
                const isSelected = (item[2] & ROW_FLAG_SELECTED) ? true : false;
                let select = false;

                if (operation == MultiSelectOp.SELECT_VISIBLE) {
                    if (isSelected)
                        continue;

                    select = true;
                } else if (operation == MultiSelectOp.DESELECT_VISIBLE) {
                    if (!isSelected)
                        continue;

                    select = false;
                } else if (operation == MultiSelectOp.INVERT_VISIBLE) {
                    if (isSelected)
                        select = false;
                    else select = true;
                }

                if (select) {
                    this.selectTableRow(col.parentNode);
                    item[2] |= ROW_FLAG_SELECTED;
                    didSomething = true;
                } else {
                    this.deselectTableRow(col.parentNode);
                    item[2] &= ~(ROW_FLAG_SELECTED | ROW_FLAG_PROCESSED | ROW_FLAG_PROCESSING_OK | ROW_FLAG_PROCESSING_FAIL);
                    didSomething = true;
                }
            }
        } else if (operation == MultiSelectOp.SELECT_ALL ||
                   operation == MultiSelectOp.DESELECT_ALL ||
                   operation == MultiSelectOp.DESELECT_PROCESSED_OK) {
            // These operate on all rows, visible or not

            // First collect handles to visible rows, so we can update them immediately
            let visibleRows = {};

            let rows = this.ui.table.children[0].children[1].rows;

            for (let i = 0; i < rows.length; i++) {
                let col = rows[i].children[0];

                if (col.dataset.rowKey === undefined) {
                    // happens on empty tables
                    continue;
                }

                visibleRows[parseInt(col.dataset.rowKey, 10)] = rows[i];
            }

            for (let i in this.currentData) {
                let item = this.currentData[i];
                const isSelected = (item[2] & ROW_FLAG_SELECTED) ? true : false;
                let select = false;

                if (operation == MultiSelectOp.SELECT_ALL) {
                    if (isSelected)
                        continue;

                    select = true;
                } else if (operation == MultiSelectOp.DESELECT_ALL) {
                    if (!isSelected)
                        continue;

                    select = false;
                } else if (operation == MultiSelectOp.DESELECT_PROCESSED_OK) {
                    if (!isSelected)
                        continue;

                    if (!(item[2] & ROW_FLAG_PROCESSED))
                        continue;

                    if (item[2] & ROW_FLAG_PROCESSING_FAIL)
                        continue;
                }

                if (select) {
                    item[2] |= ROW_FLAG_SELECTED;
                    didSomething = true;

                    if (i in visibleRows)
                        this.selectTableRow(visibleRows[i]);
                } else {
                    item[2] &= ~(ROW_FLAG_SELECTED | ROW_FLAG_PROCESSED | ROW_FLAG_PROCESSING_OK | ROW_FLAG_PROCESSING_FAIL);
                    didSomething = true;

                    if (i in visibleRows)
                        this.deselectTableRow(visibleRows[i]);
                }
            }
        } else if (operation == MultiSelectOp.DESELECT_NONVISIBLE) {
            // This operates on non-visible rows, no need to update table styles

            // First collect handles to visible rows, so we can ignore them
            let visibleRows = new Set();

            let rows = this.ui.table.children[0].children[1].rows;

            for (let i = 0; i < rows.length; i++) {
                let col = rows[i].children[0];
                visibleRows.add(parseInt(col.dataset.rowKey, 10));
            }

            for (let i in this.currentData) {
                let item = this.currentData[i];

                if (!(item[2] & ROW_FLAG_SELECTED))
                    continue;

                if (visibleRows.has(item[0]))
                    continue;

                item[2] &= ~(ROW_FLAG_SELECTED | ROW_FLAG_PROCESSED | ROW_FLAG_PROCESSING_OK | ROW_FLAG_PROCESSING_FAIL);
                didSomething = true;
            }
        }

        if (didSomething)
            this.updateMassOperationStatus();
    }

    // Creates the multiselection operation menu
    createMultiselectMenu(parent)
    {
        let col = newElem({ tag: "div", classes: ["massSelectMenu"] });

        col.innerHTML =
`<span></span>
<ul>
    <li><a id="multisel_sel_visible">${I18n.translate("supertable.control.mass_op.select_all_visible")}</a></li>
    <li><a id="multisel_desel_visible">${I18n.translate("supertable.control.mass_op.deselect_all_visible")}</a></li>
    <li><a id="multisel_inv_visible">${I18n.translate("supertable.control.mass_op.invert_visible")}</a></li>
    <li class="sep"></li>
    <li><a id="multisel_desel_ok">${I18n.translate("supertable.control.mass_op.deselect_successfull")}</a></li>
    <li class="sep"></li>
    <li><a id="multisel_sel_all">${I18n.translate("supertable.control.mass_op.select_all")}</a></li>
    <li><a id="multisel_desel_all">${I18n.translate("supertable.control.mass_op.deselect_all")}</a></li>
    <li><a id="multisel_desel_nonvisible">${I18n.translate("supertable.control.mass_op.deselect_invisible")}</a></li>
</ul>`;

        col.querySelector("#multisel_sel_visible")
            .addEventListener("click", event => this.multiselectOperation(event, MultiSelectOp.SELECT_VISIBLE));

        col.querySelector("#multisel_sel_all")
            .addEventListener("click", event => this.multiselectOperation(event, MultiSelectOp.SELECT_ALL));

        col.querySelector("#multisel_desel_visible")
            .addEventListener("click", event => this.multiselectOperation(event, MultiSelectOp.DESELECT_VISIBLE));

        col.querySelector("#multisel_desel_nonvisible")
            .addEventListener("click", event => this.multiselectOperation(event, MultiSelectOp.DESELECT_NONVISIBLE));

        col.querySelector("#multisel_desel_all")
            .addEventListener("click", event => this.multiselectOperation(event, MultiSelectOp.DESELECT_ALL));

        col.querySelector("#multisel_inv_visible")
            .addEventListener("click", event => this.multiselectOperation(event, MultiSelectOp.INVERT_VISIBLE));

        col.querySelector("#multisel_desel_ok")
            .addEventListener("click", event => this.multiselectOperation(event, MultiSelectOp.DESELECT_PROCESSED_OK));

        parent.appendChild(col);
    }

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------
    // DATA PROCESSING

    // Filter, sort and rebuild the table. Called from many places.
    updateTable()
    {
        try {
            const t0 = performance.now();

            let newData = null,
                hiddenIDs = null;

            if (this.settings.flags & TABLE_FLAG_ENABLE_SELECTION) {
                // Always reset the previous row marker
                this.previouslyClickedRow = null;
            }

            // Filter
            if (!this.filtering.enabled) {
                newData = [...this.currentData];
                hiddenIDs = new Set();
            } else {
                [newData, hiddenIDs] = this.filterData(
                    this.filtering.filters,
                    this.filtering.reverse,
                    this.columns.definitions,
                    [...this.currentData]);
            }

            // Apply hidden flags to rows
            for (let i in this.currentData) {
                let item = this.currentData[i];

                if (hiddenIDs.has(item[1]))
                    item[2] |= ROW_FLAG_FILTERED;
                else item[2] &= ~ROW_FLAG_FILTERED;
            }

            const t1 = performance.now();

            // Sort
            if (this.sorting.column == null || this.sorting.order == SORT_ORDER_NONE)
                console.log("SuperTable::updateTable(): sorting is disabled");
            else {
                const def = this.columns.definitions[this.sorting.column];

                newData = this.sortData(
                        def.key,                // which JSON field
                        def.type,               // what type the field is
                        def.subType || null,    // possible field subtype
                        this.sorting.order,     // which order
                        newData);
            }

            const t2 = performance.now();

            // Rebuild
            let newTable = this.buildTable(this.columns.definitions,
                                           this.columns.columns,        // visible columns
                                           this.sorting,                // sorting options
                                           newData);

            const t3 = performance.now();

            // DOM replace
            this.ui.table.innerHTML = "";
            this.ui.table.appendChild(newTable);

            const t4 = performance.now();
            console.log(`SuperTable::updateTable(): filtering ${t1 - t0} ms, sorting ${t2 - t1} ms, table rebuilding ${t3 - t2} ms, DOM replace ${t4 - t3} ms; total ${t4 - t0} ms`);

            // Update the row counter display
            this.ui.count.textContent =
                I18n.translate("supertable.control.status").
                    replace("${itemName}", this.settings.itemName).
                    replace("${total}", this.currentData.length).
                    replace("${visible}", newData.length).
                    replace("${filtered}", this.currentData.length - newData.length);

            if (this.settings.flags & TABLE_FLAG_ENABLE_SELECTION) {
                this.clearPreviousRow();
                this.updateMassOperationStatus();
            }
        } catch (e) {
            // Don't let errors destroy the current table. Instead, tell the user about them
            // and log details on the console.
            console.log(e);
            this.setFailStatus("Table update failed, an exception was thrown. See the browser console for details.");
        }
    }

    // Apply filters, if any, to the data
    filterData(filters, reverse, columnDefs, data)
    {
        let hiddenIDs = new Set();

        if (filters.length == 0)
            return [data, hiddenIDs];

        // copy column types, so we can do type-specific comparisons if necessary
        let types = new Array(filters.length),
            subTypes = new Array(filters.length);

        for (let i in filters) {
            types[i] = columnDefs[filters[i][0]].type;
            subTypes[i] = columnDefs[filters[i][0]].subType || null;
        }

        data = data.filter(function(item) {
            let rowMatched = true;   // each row is visible by default

            for (let i in filters) {
                const f = filters[i];
                let filterMatched = false;

                let value = item[4][f[0]];

                if (types[i] == COLUMN_TYPE_STRING)
                    if (value === undefined || value === null)
                        value = "";

                if (subTypes[i]) {
                    switch (subTypes[i]) {
                        case COLUMN_SUBTYPE_DEVICE_PRIMARY_USER:
                            // don't compare against [Object object]
                            value = value['title'] || "";
                            break;
                    }
                }

                // Compare using the selected operator
                switch (f[1]) {
                    case OPERATOR_EQUAL:
                        if (types[i] == COLUMN_TYPE_STRING)
                            filterMatched = f[2].test(value);
                        else filterMatched = (value === f[2]);

                        break;

                    case OPERATOR_NOT_EQUAL:
                        if (types[i] == COLUMN_TYPE_STRING)
                            filterMatched = !f[2].test(value);
                        else filterMatched = (value !== f[2]);

                        break;

                    case OPERATOR_LESS_THAN:
                        if (types[i] == COLUMN_TYPE_UNIXTIME)
                            if (value === undefined || value === null)
                                value = 999999999999;

                        filterMatched = (value < f[2]);
                        break;

                    case OPERATOR_LESS_OR_EQUAL:
                        if (types[i] == COLUMN_TYPE_UNIXTIME)
                            if (value === undefined || value === null)
                                value = 999999999999;

                        filterMatched = (value <= f[2]);
                        break;

                    case OPERATOR_GREATER_THAN:
                        if (types[i] == COLUMN_TYPE_UNIXTIME)
                            if (value === undefined || value === null)
                                value = -999999999999;

                        filterMatched = (value > f[2]);
                        break;

                    case OPERATOR_GREATER_OR_EQUAL:
                        if (types[i] == COLUMN_TYPE_UNIXTIME)
                            if (value === undefined || value === null)
                                value = -999999999999;

                        filterMatched = (value >= f[2]);
                        break;

                    default:
                        throw `filterData(): unknown filter operator ${f[1]}`;
                }

                if (filterMatched == false) {
                    // stop processing this row on the first mismatch
                    rowMatched = false;
                    break;
                }

            }

            // final verdict for this row (must be the opposite of the "reverse match" setting)
            const visible = (rowMatched != reverse);

            if (!visible)
                hiddenIDs.add(item[1]);

            return visible;
        });

        return [data, hiddenIDs];
    }

    // Sorts the data. "key" is the key used to dig up comparable items from
    // the JSON.
    sortData(key, type, subType, order, data)
    {
        // This shouldn't happen, but let's handle it
        if (order == SORT_ORDER_NONE)
            return data;

        // If we're sorting in descending order, invert sort comparison results so
        // we'll sort in revese order. Now we don't have to call Array.reverse()
        // after sorting.
        let direction = (order == SORT_ORDER_ASCENDING) ? 1 : -1;

        // Unixtimes are a special case: because they're constantly growing, they get sorted
        // in the wrong way, ie. the bigger something is, the newer it is. Therefore, invert
        // unixtime sort orders.
        if (type == COLUMN_TYPE_UNIXTIME)
            direction *= -1;

        let out = data;

        switch (type) {
            case COLUMN_TYPE_STRING:
            default:
                if (subType && subType == COLUMN_SUBTYPE_DEVICE_PRIMARY_USER) {
                    out.sort((a, b) => {
                        // This is getting hideous. I want to rewrite this
                        // garbage from ground up.
                        const aa = a[4][key] ? a[4][key]["title"] : "",
                              bb = b[4][key] ? b[4][key]["title"] : "";

                        return this.collator.compare(aa, bb) * direction;
                    });
                } else {
                    out.sort((a, b) => {
                        return this.collator.compare(a[4][key] || "", b[4][key] || "") * direction;
                    });
                }

            break;

            case COLUMN_TYPE_INTEGER:
            case COLUMN_TYPE_FLOAT:
            case COLUMN_TYPE_BOOLEAN:       // argh
            case COLUMN_TYPE_UNIXTIME:
                out.sort((a, b) => {
                    const i1 = a[4][key] || 0,
                          i2 = b[4][key] || 0;

                    if (i1 < i2)
                        return -1 * direction;
                    else if (i1 > i2)
                        return 1 * direction;

                    return 0;
                });

                break;
        }

        return out;
    }

    // (Re)builds the table using the specified JSON. You have to pass in column definitions
    // and column data, because this method is called from a callback and, as usual in JavaScript,
    // variable scoping is completely random and WE CAN'T SEE THE CLASS INSTANCE WE'RE IN.
    buildTable(columnDefs, columns, sorting, tableContents)
    {
        const haveData = tableContents.length > 0;

        const enableSelection = (this.settings.flags & TABLE_FLAG_ENABLE_SELECTION) ? true : false;

        // -----------------------------------------------------------------------------------------
        // Create the header row with clickable sort headers and other bells and whistles

        // The "thead" class hides the header row on mobile layouts
        let header = newElem({ tag: "tr", classes: ["thead"] });

        let numColumns = 0;

        if (enableSelection && haveData) {
            // The special menu for quick multiselection operations
            //this.createMultiselectMenu(header);
            header.appendChild(newElem({ tag: "th" }));
        }

        for (let columnKey in columns) {
            const column = columns[columnKey];

            if (!column[1]) {
                // this column is not visible
                continue;
            }

            const columnId = column[0];
            const def = columnDefs[columnId];
            let th = null;

            if (def.flags & COLUMN_FLAG_SORTABLE) {
                /*
                This column is sortable. Build this structure inside the TH element:

                    <div>
                        <span class="name">(COLUMN TITLE)</span>
                        <span class="arrow"></span>
                    </div>

                The DIV is a flexbox container. It is used to always align the sort order arrow
                to the right edge, even when the column is so narrow the title takes up multiple
                rows.
                */
                let div = newElem({ tag: "div" }),
                    name = newElem({ tag: "span", content: def["title"] }),
                    arrow = newElem({ tag: "span", classes: ["arrow"] });

                div.appendChild(name);
                div.appendChild(arrow);

                // figure out the sort order and type for this column
                let classes = ["sortHeader"];

                if (sorting.column == columnId) {
                    // sorted by this column
                    if (sorting.order == SORT_ORDER_ASCENDING)
                        classes.push("orderAscending");
                    else classes.push("orderDescending");
                } else {
                    // not sorted by this column
                    classes.push("orderNone");
                }

                switch (def.type) {
                    case COLUMN_TYPE_STRING:
                    default:
                        classes.push("typeString");
                        break;

                    case COLUMN_TYPE_INTEGER:
                    case COLUMN_TYPE_FLOAT:
                    case COLUMN_TYPE_BOOLEAN:           // ewww
                    case COLUMN_TYPE_UNIXTIME:
                        classes.push("typeNumeric");
                        break;
                }

                th = newElem({ tag: "th", classes: classes });
                th.appendChild(div);

                // setup event handling
                th.dataset.columnId = columnId;
                th.addEventListener("click", event => this.clickedColumnHeader(event));
            } else {
                // Normal unsortable column
                th = newElem({ tag: "th", content: def["title"] });
            }

            header.appendChild(th);
            numColumns++;
        }

        // Append the actions column. It always exists and it cannot be sorted.
        header.appendChild(newElem({ tag: "th", content: I18n.translate("supertable.actions.title") }));

        // -----------------------------------------------------------------------------------------
        // Create the data rows

        // Only show the selected columns and in the order they are. A separate TBODY element is
        // created so that CSS selectors work properly.
        let body = newElem({ tag: "tbody" });

        for (let rowKey in tableContents) {
            const rowIndex = tableContents[rowKey][0];
            const rowID = tableContents[rowKey][1];
            const rowFlags = tableContents[rowKey][2];
            const rowMessage = tableContents[rowKey][3];
            const rowData = tableContents[rowKey][4];

            let tr = newElem({ tag: "tr" });

            // The row processing status message
            if (enableSelection && rowMessage)
                tr.title = rowMessage;

            // Create the selection checkbox, and retain existing row states across table rebuilds
            if (enableSelection) {
                let classes = ["checkbox"];

                const selected = (rowFlags & ROW_FLAG_SELECTED) ? true : false,
                      ok = (rowFlags & ROW_FLAG_PROCESSING_OK) ? true : false,
                      failed = (rowFlags & ROW_FLAG_PROCESSING_FAIL) ? true : false;

                if (selected) {
                    if (ok) {
                        classes.push("selected");
                        tr.classList.add("processingSuccessfull");
                    } else if (failed) {
                        classes.push("selected");
                        tr.classList.add("processingFailed");
                    } else {
                        classes.push("selected");
                        tr.classList.add("selectedRow");
                    }
                }

                let cb = newElem({ tag: "td", classes: classes });

                cb.dataset.rowKey = rowIndex;
                cb.appendChild(newElem({ tag: "span" }));
                cb.addEventListener("click", event => this.rowCheckboxClicked(event));
                tr.appendChild(cb);
            }

            // Create visible columns, in order
            for (let columnKey in columns) {
                const column = columns[columnKey];

                if (!column[1]) {
                    // this column is not visible
                    continue;
                }

                const def = columnDefs[column[0]];
                const subType = def["subType"] || 0;
                let td = null;

                const link = rowData["link"] || "";

                // Column definitions lists the key for each column that is used to
                // extract the column's contents from the JSON
                let contents = rowData[def["key"]];

                // Apply type-specific transformations to the data
                if (contents) {
                    if (def.flags & COLUMN_FLAG_SPLIT) {
                        // escape HTML, then join the array with forced linebreaks
                        contents = contents
                            .map(i => escapeHTML(i))
                            .join("<br>");
                    } else if (def.flags & COLUMN_FLAG_SPLIT_BY_NEWLINES) {
                        // convert \n's into actual newlines (and remove \r's)
                        // and escape HTML
                        contents = contents
                            .replace("\r", "")
                            .split("\n")
                            .map(i => escapeHTML(i))
                            .join("<br>");
                    } else {
                        // escape HTML
                        contents = escapeHTML(contents);
                    }

                    if (def.type == COLUMN_TYPE_UNIXTIME) {
                        // convert Unixtime to a human-readable localtime stamp
                        contents = convertTimestamp(contents);
                    }

                    if (def.type == COLUMN_TYPE_BOOLEAN) {
                        if (contents == true)
                            contents = "<span class=\"boolean\">✔<span>";
                    }

                    // Subtypes are primarily used to create clickable
                    // "show" links.
                    switch (subType) {
                        case COLUMN_SUBTYPE_USER_USERNAME: {
                            if (rowData["locked"])
                                contents = `<a href="${link}">${contents}</a> <i class="icon-lock"></i>`;
                            else contents = `<a href="${link}">${contents}</a>`;
                            break;
                        }

                        case COLUMN_SUBTYPE_USER_ROLES: {
                            // Split and display owners/admins separately
                            contents = contents
                                .map(i => escapeHTML(i))
                                .join("<br>");

                            let admins = [];

                            if (rowData.owner && rowData.owner === true)
                                admins.push(I18n.translate("supertable.misc.user_is_owner"));

                            if (rowData.admin && rowData.admin === true)
                                admins.push(I18n.translate("supertable.misc.user_is_admin"));

                            if (admins.length > 0)
                                contents = `<span class="adminUsers">${admins.join("<br>")}</span><br>` + contents;

                            break;
                        }

                        case COLUMN_SUBTYPE_GROUP_NAME:
                            contents = `<a href="${link}">${contents}</a> (${rowData["members"]})`;
                            break;

                        case COLUMN_SUBTYPE_DEVICE_HOSTNAME:
                            contents = `<a href="${link}">${contents}</a>`;
                            break;

                        case COLUMN_SUBTYPE_DEVICE_BATTERY_CAPACITY:
                            contents = `${contents}%`;
                            break;

                        case COLUMN_SUBTYPE_DEVICE_BATTERY_VOLTAGE:
                            contents = `${contents}V`;
                            break;

                        case COLUMN_SUBTYPE_DEVICE_WARRANTY_DATE:
                            contents = convertTimestampDateOnly(rowData[def["key"]]);
                            break;

                        case COLUMN_SUBTYPE_DEVICE_SUPPORT_URL:
                            contents = `<a href="${rowData['purchase_url']}">${rowData['purchase_url']}</a>`;
                            break;

                        case COLUMN_SUBTYPE_DEVICE_PRIMARY_USER: {
                            const user = rowData['user'];

                            contents = `<a href="${user['link']}">${user['title']}</a>`;
                            break;
                        }

                        default:
                            break;
                    }
                } else {
                    // Do type-specific processing for missing entries, if anything
                    switch (subType) {
                        case COLUMN_SUBTYPE_GROUP_TYPE:
                            contents = `<span class="missingData">${I18n.translate("supertable.misc.unset_group_type")}</span>`;
                            break;

                        default:
                            break;
                    }
                }

                td = newElem({ tag: "td", content: contents });

                td.dataset.title = def["title"];        // for mobile display

                // Highlight the sort column
                if (sorting.column == column[0])
                    td.classList.add("selectedColumn");

                tr.appendChild(td);
            }

            // Create the special actions column
            let actionsColumn = newElem({ tag: "td" });

            let editButton = newElem({ tag: "a", classes: ["btn"] });
            editButton.href = rowData["link"] + "/edit";
            editButton.innerHTML = "<i class=\"icon-pencil\"></i> " + I18n.translate("supertable.actions.edit");
            actionsColumn.appendChild(editButton);

            let deleteEnabled = true;

            if (!this.settings.permitUserDeletion) {
                // user deletion explicitly disabled in settings
                deleteEnabled = false;
            }

            if (this.settings.flags & TABLE_FLAG_USERS) {
                // don't display the delete button for users who cannot be deleted
                if (rowData["dnd"])
                    deleteEnabled = false;
            }

            if (deleteEnabled) {
                // let RoR JS helpers deal with the confirmation question
                let deleteButton = newElem({ tag: "a", classes: ["btn", "btn-danger"] });

                let message = "";

                if ((rowData.owner && rowData.owner === true) || (rowData.admin && rowData.admin === true)) {
                    // an admin/owner user
                    message = I18n.translate("supertable.actions.remove_confirm_admin");
                } else {
                    // a normal user
                    message = I18n.translate("supertable.actions.remove_confirm");
                }

                if (this.settings.synchronisedDeletions.length > 0) {
                    // Extra warning about deletion synchronisations
                    message += "\n\n";
                    message += I18n.translate("supertable.actions.remove_synchronisations");
                    message = message.replace("${systems}", this.settings.synchronisedDeletions.join(", "));
                }

                deleteButton.dataset.confirm = message;
                deleteButton.dataset.method = "delete";
                deleteButton.href = rowData["link"];
                deleteButton.rel = "nofollow";
                deleteButton.innerHTML = "<i class=\"icon-trash\"></i> " +
                                         I18n.translate("supertable.actions.remove");

                actionsColumn.appendChild(deleteButton);
            }

            if (this.settings.flags & TABLE_FLAG_USERS) {
                // highlight rows of users who are marked for later deletion
                if (rowData["rrt"])
                    tr.classList.add("deleted");
            }

            tr.appendChild(actionsColumn);

            body.appendChild(tr);
        }

        // Completely empty table?
        if (!haveData) {
            let td = newElem({ tag: "td" });
            td.setAttribute("colspan", (numColumns + 1).toString());
            td.appendChild(document.createTextNode(I18n.translate("supertable.empty")));

            let tr = newElem({ tag: "tr", classes: ["empty"] });
            tr.appendChild(td);

            body.appendChild(tr);
        }

        // -----------------------------------------------------------------------------------------
        // Assemble the final table

        let table = newElem({ tag: "table", classes: ["list", "superTable"] });

        table.appendChild(header);
        table.appendChild(body);

        return table;
    }
};
