"use strict;"

/*
SuperTable 2: The 2nd Edition
It's still a monster, but it's more structured now

Version 2.5.6
*/

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MAIN DEFINES

// Main table flags
const TableFlag = {
    ENABLE_COLUMN_EDITING: 0x01,
    ENABLE_FILTERING: 0x02,
    ENABLE_SELECTION: 0x04,
    ENABLE_PAGINATION: 0x08,
    DISABLE_EXPORT: 0x10,           // disables CSV export (enabled by default)
    DISABLE_VIEW_SAVING: 0x20,      // disables JSON/URL view saving (enabled by default)
    DISABLE_TOOLS: 0x40,            // completely hide the "Tools" tab
};

// Column data types. Affects filtering and sorting.
const ColumnType = {
    BOOL: 1,
    NUMERIC: 2,     // int/float
    UNIXTIME: 3,    // internally an integer, but displayed as YYYY-MM-DD HH:MM:SS
    STRING: 4,
};

// Column flags
const ColumnFlag = {
    // This column can NOT be sorted. All columns are sortable by default, but you can use this
    // flag to invert that
    NOT_SORTABLE: 0x01,

    // The column values are actually arrays of zero or more values instead of just one
    // Only works with strings!
    ARRAY: 0x02,

    // Call a user-defined callback function to get the actual displayable value
    USER_TRANSFORM: 0x04,

    // Add a custom CSS class name to the column TD (specify it with "cssClass" value)
    CUSTOM_CSS: 0x08,

    // Normally, when a column header is clicked, it is sorted in ascending order. By setting
    // this flag, you make the descending order the default for that column. Some columns
    // contain values (like RAM size) that make more sense when sorted that way by default.
    DESCENDING_DEFAULT: 0x10,

    // ----------------------------------------------------------------------------------------------
    // Filter parser flags

    // Expand B/K/M/G/T size specifiers when parsing the filter. Useful with hard disk and
    // RAM sizes.
    F_STORAGE: 0x20,

    // This column can be NULL, ie. the !! operator is useful here. Used only in the Filter
    // Editor to display warnings about useless !! comparisons.
    F_NULLABLE: 0x40,
};

// Column sort ordering
const SortOrder = {
    NONE: "none",
    ASCENDING: "asc",
    DESCENDING: "desc"
};

// Mass selection row operation
const RowSelectOp = {
    SELECT_ALL: 1,
    DESELECT_ALL: 2,
    DESELECT_SUCCESSFULL: 3,
};

// Pagination defaults
const ROWS_PER_PAGE_PRESETS = [
    [-1, "∞"],
    [5, "5"],
    [10, "10"],
    [25, "25"],
    [50, "50"],
    [100, "100"],
    [200, "200"],
    [250, "250"],
    [500, "500"],
    [1000, "1000"],
    [2000, "2000"],
    [5000, "5000"],
];

const DEFAULT_ROWS_PER_PAGE = 250;

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// UTILITY

// A shorter to type alias
function _tr(id, params={}) { return I18n.translate(id, params); }

function escapeHTML(s)
{
    if (typeof(s) != "string")
        return s;

    // I wonder how safe/reliable this is?
    return s.replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
}

function pad(number)
{
    return (number < 10) ? "0" + number : number;
}

function padDateTime(d)
{
    // I miss sprintf()
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
           `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

// Scaler for converting between JavaScript dates and unixtimes
const JAVASCRIPT_TIME_GRANULARITY = 1000;

function convertTimestamp(unixtime)
{
    // Assume "too old" timestamps are invalid
    // 2000-01-01 00:00:00 UTC
    if (unixtime < 946684800)
        return [false, "(INVALID)"];

    try {
        // I'm not sure if this can throw errors
        return [true, padDateTime(new Date(unixtime * JAVASCRIPT_TIME_GRANULARITY))];
    } catch (e) {
        console.log(e);
        return [false, "(ERROR)"];
    }
}

function convertTimestampDateOnly(unixtime)
{
    if (unixtime < 0)
        return "";

    // Assume "too old" timestamps are invalid
    // 2000-01-01 00:00:00 UTC
    if (unixtime < 946684800)
        return [false, "(INVALID)"];

    try {
        // I'm not sure what kind of errors this can throw and when
        const d = new Date(unixtime * JAVASCRIPT_TIME_GRANULARITY);

        // why is there no strftime() in JavaScript?
        return [true, d.getFullYear() + "-" +
            pad(d.getMonth() + 1) + "-" +
            pad(d.getDate())];
    } catch (e) {
        console.log(e);
        return [false, "(ERROR)"];
    }
}

// JavaScript has a built-in Set type and it has... no common set operators defined for it.
// Nope. Nothing. Nada. Zilch. Zero. Do it yourself. Sigh.
function setUnion(a, b)
{
    let c = new Set(a);

    for (const i of b)
        c.add(i);

    return c;
}

// Creates a new HTML element and sets is attributes
function create(tag, params)
{
    let e = document.createElement(tag);

    if ("id" in params && params.id !== undefined)
        e.id = params.id;

    if ("cls" in params && params.cls !== undefined) {
        if (Array.isArray(params.cls))
            e.className = params.cls.join(" ");
        else e.className = params.cls;
    }

    if ("html" in params && params.html !== undefined)
        e.innerHTML = params.html;

    if ("text" in params && params.text !== undefined)
        e.innerText = params.text;

    if ("textnode" in params && params.textnode !== undefined)
        e.appendChild(document.createTextNode(params.textnode));

    return e;
}

function destroy(e)
{
    if (e)
        e.remove();
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PROCESSING

// After the data has been transformed, each row column is made up of multiple elements.
// These are the indexes to those elements.
const INDEX_EXISTS = 0,
      INDEX_DISPLAYABLE = 1,
      INDEX_FILTERABLE = 2,
      INDEX_SORTABLE = 3;

// Default values for different column types. Used to substitute missing values for sorting.
const DEFAULT_VALUES = {
    [ColumnType.BOOL]: false,
    [ColumnType.NUMERIC]: 0,
    [ColumnType.UNIXTIME]: 0,
    [ColumnType.STRING]: ""
};

function _transformValue(userTransforms, raw, key, coldef, defVal)
{
    if (coldef.flags & ColumnFlag.USER_TRANSFORM) {
        // Apply a user-defined transformation. We assume the user function can deal
        // with null and undefined values.
        if (key in userTransforms)
            return userTransforms[key](raw);
        else {
            return [
                `<span class="data-error">User transform function "${key}" is missing!</span>`,
                defVal
            ];
        }
    }

    if (raw[key] === null) {
        // This entry exists, but it's NULL. Use the default value so that sorting works.
        return [defVal, defVal];
    }

    // Apply a built-in transformation
    let value = raw[key];

    switch (coldef.type) {
        case ColumnType.BOOL:
            value = (value === true) ? "✔" : "";
            break;

        case ColumnType.NUMERIC:
            if (value === null || value == undefined)
                value = 0;

            break;

        case ColumnType.UNIXTIME:
            [_, value] = convertTimestamp(value);
            break;

        default:
            break;
    }

    let displayable = null,
        sortable = null;

    // FIXME: Array values only works with strings
    if (coldef.flags & ColumnFlag.ARRAY) {
        displayable = value.map(i => escapeHTML(i)).join("<br>");
        sortable = value.join();
    } else {
        displayable = escapeHTML(value);
        sortable = raw[key];
    }

    return [displayable, sortable];
};

// Apply some transformations to the raw data received from the server. For example,
// convert timestamps into user's local time, turn booleans into checkmarks, and so on.
// The data we generate here is purely presentational, intended for humans; it's never
// fed back into the database.
function transformRawData(columnDefinitions, userTransforms, rawData)
{
    const columnKeys = Object.keys(columnDefinitions);

    let out = [];

    for (const raw of rawData) {
        // Puavo ID and school ID are both *always* required. No exceptions.
        if (!("id" in raw) || !("school_id" in raw))
            continue;

        let cleaned = {};

        // This is not a column, so it must be copied manually. PuavoID is a column, so it
        // is handled automatically.
        cleaned.school_id = raw.school_id;

        // Process every column, even if it's not visible
        for (const key of columnKeys) {
            const coldef = columnDefinitions[key],
                  defVal = DEFAULT_VALUES[coldef.type];

            let clean = [false, null, null, null];

            if (key in raw) {
                // The transformation function can return two or three values; the third is
                // an optional filterable value. If it's omitted, we use the plain raw value.
                const [d, s, f] = _transformValue(userTransforms, raw, key, coldef, defVal);

                clean[INDEX_EXISTS] = true;
                clean[INDEX_DISPLAYABLE] = d;
                clean[INDEX_SORTABLE] = s;
                clean[INDEX_FILTERABLE] = (f === undefined) ? raw[key] : f;
            } else {
                clean[INDEX_EXISTS] = false;
                clean[INDEX_DISPLAYABLE] = null;
                clean[INDEX_SORTABLE] = defVal;
                clean[INDEX_FILTERABLE] = undefined;    // the filter system can deal with this

                if (coldef.missing) {
                    // Retrieve custom default values, if specified
                    if (coldef.missing.display !== undefined)
                        clean[INDEX_DISPLAYABLE] = coldef.missing.display;

                    if (coldef.missing.sort !== undefined)
                        clean[INDEX_SORTABLE] = coldef.missing.sort;

                    if (coldef.missing.filter !== undefined)
                        clean[INDEX_FILTERABLE] = coldef.missing.filter;
                }
            }

            cleaned[key] = clean;
        }

        out.push(cleaned);
    }

    return out;
}

// Applies zero or more filters to the data
function filterData(columnDefinitions, data, filters, reverse)
{
    const numComparisons = filters.comparisons.length;

    let filtered = data.filter(function(row) {
        // Evaluate comparisons for this row
        let results = [];

        for (const cmp of filters.comparisons)
            results.push(compareRowValue(row[cmp.column][INDEX_FILTERABLE], cmp));

        // Then run the RPN filter program
        return evaluateFilter(filters.program, results) != reverse;
    });

    return filtered;
}

// Sorts the data by the specified column and order
function sortData(columnDefinitions, sortBy, collator, data)
{
    const direction = (sortBy.dir == SortOrder.ASCENDING) ? 1 : -1,
          key = columnDefinitions[sortBy.column].key;

    let out = [...data];

    switch (columnDefinitions[sortBy.column].type) {
        case ColumnType.BOOL:                   // not the best choice
        case ColumnType.NUMERIC:
        case ColumnType.UNIXTIME:
            out.sort((a, b) => {
                const n1 = a[key][INDEX_SORTABLE],
                      n2 = b[key][INDEX_SORTABLE];

                if (n1 < n2)
                    return -1 * direction;
                else if (n1 > n2)
                    return 1 * direction;

                return a.id - b.id;         // stabilize the sort
            });

            break;

        case ColumnType.STRING:
        default:
            out.sort((a, b) => {
                const r = collator.compare(a[key][INDEX_SORTABLE], b[key][INDEX_SORTABLE]) * direction;

                if (r === 0)
                    return a.id - b.id;     // stabilize the sort

                return r;
            });

            break;
    }

    return out;
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MASS OPERATIONS

const MassOperationFlags = {
    HAVE_SETTINGS: 0x01,        // this operation has adjustable settings
    SINGLESHOT: 0x02,           // this operation processes all items in one call, not one-by-one
};

// Base class for all user-derived mass operations
class MassOperation {
    constructor(parent, container)
    {
        this.parent = parent;
        this.container = container;
    }

    // Construct the interface, if anything
    buildInterface()
    {
    }

    // Validate the current parameters, if any. Return true to signal that the operation
    // can proceed, false if not.
    canProceed()
    {
        return true;
    }

    // Called just before the mass operation begins. Disable the UI, etc.
    start()
    {
    }

    // Called after the mass operation is done. Do clean-ups, etc. here.
    finish()
    {
    }

    // Process a single item (a hash) and return success/failed status
    processItem(item)
    {
        return itemProcessedStatus(true);
    }

    // Process all items at once, and return success/failed status
    processAllItems(items)
    {
        return itemProcessedStatus(true);
    }
};

// Sends a single AJAX POST message
function doPOST(url, itemData)
{
    // The (table) development environment does not have CSRF tokens, but
    // development and production Puavo environments have. Support both.
    const csrf = document.querySelector("meta[name='csrf-token']");

    return fetch(url, {
        method: "POST",
        mode: "cors",
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "X-CSRF-Token": "sfhsdfkhdsfdsf", //csrf ? csrf.content : "",
        },
        body: JSON.stringify(itemData)
    }).then(function(response) {
        if (!response.ok)
            throw response;

        return response.json();
    }).catch((error) => {
        console.error(error);

        return {
            success: false,
            message: _tr('network_connection_error'),
        };
    });
}

// Mass operations are basically just a bunch of chained promises that are executed in sequence.
// Use this convenience function to construct and return response Promises.
function itemProcessedStatus(success, message=null)
{
    // We don't actually reject the Promise itself, we just set the 'success' flag,
    // because it's the return value and the only thing we actually care about.
    return new Promise(function(resolve, reject) {
        resolve({ success: success, message: message });
    });
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// THE SUPERTABLE

class SuperTable {

constructor(container, settings)
{
    this.id = settings.id;
    this.container = container;

    // ----------------------------------------------------------------------------------------------
    // Validate the parameters. These will explode loudly and completely prevent the table
    // from even appearing. That's intentional. These should be caught in development/testing.

    if (this.container === null || this.container === undefined) {
        console.error("The container DIV element is null or undefined");
        window.alert("The table container DIV is null or undefined. The table cannot be displayed.\n\n" +
                     "Please contact Opinsys support.");
        return;
    }

    if (settings.columnDefinitions === undefined ||
        settings.columnDefinitions === null ||
        typeof(settings.columnDefinitions) != "object" ||
        Object.keys(settings.columnDefinitions).length == 0) {

        console.error("The settings.columnDefinitions parameter missing/empty, or it isn't an " +
                      "associative array");

        this.container.innerHTML =
            `<p class="error">There are no column definitions at all. The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    if (settings.columnTitles === undefined ||
        settings.columnTitles === null ||
        typeof(settings.columnTitles) != "object" ||
        Object.keys(settings.columnTitles).length == 0) {

        console.error("The settings.columnTitles parameter missing/empty, or it isn't an associative array");

        this.container.innerHTML =
            `<p class="error">Column titles have not been specified. The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    if (settings.defaultColumns === undefined ||
        settings.defaultColumns === null ||
        !Array.isArray(settings.defaultColumns) ||
        settings.defaultColumns.length == 0) {

        console.error("The settings.defaultColumn parameter missing/empty, or it isn't an array");

        this.container.innerHTML =
            `<p class="error">Default columns have not been defined. The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    if (settings.defaultSorting === undefined ||
        settings.defaultSorting === null ||
        typeof(settings.defaultSorting) != "object" ||
        settings.defaultSorting.length == 0) {

        console.error("The settings.defaultSorting parameter missing/empty, or it isn't an associative array");

        this.container.innerHTML =
            `<p class="error">The default sorting has not been defined or it is invalid. The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    // Ensure we have at least one data source
    if ((settings.staticData === undefined || settings.staticData === null) &&
        (settings.dynamicData === undefined || settings.dynamicData === null)) {

        console.error("staticData and dynamicData are both indefined/NULL");

        this.container.innerHTML =
            `<p class="error">No data source has been defined (missing both <code>staticData</code> and <code>dynamicData</code>). ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    // The default columns parameter MUST be correct at all times
    for (const c of settings.defaultColumns) {
        if (!(c in settings.columnDefinitions)) {
            console.error(`Default column "${c}" is not in the column definitions`);

            this.container.innerHTML =
                `<p class="error">Invalid/unknown default column "${c}". The table cannot be displayed. ` +
                `Please contact Opinsys support.</p>`;

            return;
        }
    }

    // The default sorting column and direction must be valid
    if (!(settings.defaultSorting.column in settings.columnDefinitions)) {
        const c = settings.defaultSorting.column;

        console.error(`The default sorting column "${c}" is not in the column definitions`);

        this.container.innerHTML =
            `<p class="error">Invalid/unknown default sorting column "${c}". The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    if (settings.defaultSorting.dir != SortOrder.ASCENDING && settings.defaultSorting.dir != SortOrder.DESCENDING) {
        this.container.innerHTML =
            `<p class="error">Invalid/unknown default sorting direction. The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;
    }

    // ----------------------------------------------------------------------------------------------
    // Setup

    // Current table/network data
    this.data = {
        errorCode: null,
        transformed: null,
        current: null,
        selectedItems: new Set(),
        successItems: new Set(),
        failedItems: new Set(),
    };

    this.headerDrag = {     // table column header dragging state
        active: false,
        canSort: false,
        element: null,
        startingMousePos: null,
        startIndex: null,
        endIndex: null,
        cellPositions: null,
        offset: null,
    };

    // Header drag callback functions. "bind()" is needed to get around some weird
    // JS scoping garbage I don't understand.
    this.onHeaderMouseDown = this.onHeaderMouseDown.bind(this);
    this.onHeaderMouseUp = this.onHeaderMouseUp.bind(this);
    this.onHeaderMouseMove = this.onHeaderMouseMove.bind(this);

    // Direct handles to various user interface elements. Cleaner than using
    // querySelector() everywhere.
    this.ui = {
        filters: {
            enabled: null,
            reverse: null,
            editor: null,       // a child class that implements the filter editor
        },

        mass: {
            proceed: null,
            progress: null,
            counter: null,
        },

        // The pagination controls DIV
        paging: null,

        // The previously clicked table row. Can be null.
        previousRow: null,
    };

    // Current mass operation data
    this.massOperation = {
        index: -1,          // index to the settings.massOperations[] array
        handler: null,      // the user-supplied handler class that actually does the mass operation
        singleShot: false,  // true if the operation processes all rows at once
    };

    // Used when sorting the table contents. The locale defines language-specific
    // sorting rules.
    this.collator = new Intl.Collator(
        settings.locale,
        {
            usage: "sort",
            sensitivity: "accent",
            ignorePunctuation: true,
            numeric: true,                  // I really like this one
        }
    );

    // State
    this.updating = false;
    this.processing = false;
    this.doneAtLeastOneOperation = false;
    this.unsavedColumns = false;

    // ----------------------------------------------------------------------------------------------
    // Load settings

    this.settings = {
        flags: settings.flags || 0,
        locale: settings.locale || "en-US",
        csvPrefix: settings.csvPrefix || "unknown",
        dynamicData: settings.dynamicData,      // URL where to get data dynamically
        userTransforms: typeof(settings.userTransforms) == "object" ? settings.userTransforms : {},
        actionsCallback: typeof(settings.actions) == "function" ? settings.actions : null,
        openCallback: typeof(settings.openCallback) == "function" ? settings.openCallback : null,

        temporaryMode: false,
        currentTab: "tools",

        columns: {
            definitions: settings.columnDefinitions,
            titles: settings.columnTitles,
            order: settings.columnOrder || [],
            defaults: [...settings.defaultColumns],
            current: [...settings.defaultColumns],      // overridden if saved settings exist
            defaultSorting: settings.defaultSorting,
        },

        sorting: {...settings.defaultSorting},          // overridden if saved settings exist

        filters: {
            enabled: false,
            reverse: false,
            advanced: false,
            presets: settings.filterPresets || [[], []],
            defaults: settings.defaultFilter || [[], []],
            filters: null,                              // overridden if saved settings exist
            string: null,                               // ditto
            program: null,                              // the current (compiled) filter program
        },

        paging: {
            rowsPerPage: DEFAULT_ROWS_PER_PAGE,         // -1 = no paging, ie. "show all at once"
        },

        massOperations: Array.isArray(settings.massOperations) ? settings.massOperations : [],

        massSelects: Array.isArray(settings.massSelects) ? settings.massSelects : [],
    };

    // Pagination state
    this.paging = {
        numPages: 0,
        currentPage: 0,
        firstRowIndex: 0,     // used to compute table row numbers during selections and mass operations
        lastRowIndex: 0,
    };

    // There's no point in permitting row selection if there are no mass tools
    if (this.settings.flags & TableFlag.ENABLE_SELECTION && this.settings.massOperations.length == 0)
        this.settings.flags &= ~TableFlag.ENABLE_SELECTION;

    // Load stored settings (LocalStore or passed in the URL)
    this.loadSettings();

    // Validate the current sorting column and ensure it is in the currently visible columns
    let found = false;

    for (const c of this.settings.columns.current) {
        if (c == this.settings.sorting.column) {
            found = true;
            break;
        }
    }

    if (!found) {
        // FIXME: What happens if the first column has ColumnFlag.NOT_SORTABLE flag?
        // FIXME: What happens if there are no sortable columns at all?
        console.warn(`The initial sorting column "${this.settings.sorting.column}" isn't visible, ` +
                     `using the first available ("${this.settings.columns.current[0]}")`);
        this.settings.sorting.column = this.settings.columns.current[0];
    }

    // ----------------------------------------------------------------------------------------------
    // Build the user interface

    this.buildUI();

    // ----------------------------------------------------------------------------------------------
    // Setup filtering. Can't do this earlier, because the filter editor object won't
    // exist before buildUI() is finished.

    if (this.settings.flags & TableFlag.ENABLE_FILTERING) {
        let saved = this.settings.filters.string;

        if (typeof(saved) != "string" || saved == "")
            saved = settings.initialFilter;

        this.ui.filters.editor.setFilters(this.settings.filters.filters);
        this.ui.filters.editor.setFilterString(saved);

        // Can't call setFilter() here, because it attempts to update the table...
        // and we don't have any table data yet!
        this.settings.filters.program = this.ui.filters.editor.getFilterProgram();
    }

    // ----------------------------------------------------------------------------------------------
    // Do the initial data fetch and table update

    this.saveSettings();
    this.enableUI(false);

    if (settings.staticData) {
        // Static data
        this.beginTableUpdate();

        this.data.transformed = transformRawData(
            this.settings.columns.definitions,
            this.settings.userTransforms,
            settings.staticData
        );

        this.updating = false;
        this.updateTable();
        this.enableUI(true);
    } else {
        // Dynamic data
        this.fetchDataAndUpdate();
    }
}

// Loads stored settings from LocalStore, if they exist
loadSettings()
{
    let stored = localStorage.getItem(`table-${this.id}-settings`);

    if (stored === null)
        stored = "{}";

    try {
        stored = JSON.parse(stored);
    } catch (e) {
        console.error("loadInitialSettings(): could not load stored settings:");
        console.error(e);
        return false;
    }

    if (!(this.settings.flags & TableFlag.DISABLE_VIEW_SAVING)) {
/*
        TODO: Make this work

        // Any settings passed in the URL?
        const url = new URL(window.location);

        if (url.search && url.searchParams) {
            let something = false;

            // Overwriting the loaded settings with the URL settings does concern me somewhat
            // (because the URL can be manipulated by the user), but the settings loaded *does*
            // validate the settings quite thoroughly. But still...
            stored = {};

            for (const [key, value] of url.searchParams.entries()) {
                stored[key] = value;
                something = true;
            }

            // Un-stringify booleans
            if ("filter_enabled" in stored)
                stored.filter_enabled = (stored.filter_enabled === "true");

            if ("filter_reverse" in stored)
                stored.filter_reverse = (stored.filter_reverse === "true");

            console.log("Resting settings from the URL:");
            console.log(stored);

            if (something) {
                console.log("Entering temporary mode");
                this.temporaryMode = true;
            }
        }
*/
    }

    this.loadSettingsObject(stored);
}

// Saves the current settings to LocalStore
saveSettings()
{
    this.updateSettingsExport();

    if (this.flags & TableFlag.DISABLE_VIEW_SAVING && this.temporaryMode)
        return;

    localStorage.setItem(`table-${this.id}-settings`, JSON.stringify(this.getSettingsObject()));
}

// Loads settings from an object that was (hopefully) constructed by deserializing JSON.
// Some items are processed multiple times for backwards compatibility.
loadSettingsObject(stored)
{
    // Restore the current tab
    let valid = ["tools"];

    if (this.settings.flags & TableFlag.ENABLE_COLUMN_EDITING)
        valid.push("columns");

    if (this.settings.flags & TableFlag.ENABLE_FILTERING)
        valid.push("filters");

    if (this.settings.flags & TableFlag.ENABLE_SELECTION)
        valid.push("mass");

    this.settings.currentTab = new Set(valid).has(stored.tab) ? stored.tab : "tools";

    // Restore currently visible columns and their order
    let columns = null;

    if ("columns" in stored) {
        if (Array.isArray(stored.columns))
            columns = stored.columns;
        else if (typeof(stored.columns) == "string")
            columns = stored.columns.split(",").map(i => i.trim()).filter((e) => { return e != ""; });
    }

    if (columns !== null) {
        // Remove invalid and duplicate columns from the array. They could be columns that
        // once existed but have been deleted since. Or someone edited the saved settings
        // and put garbage in there. Or something else happened. Weed them out.
        let valid = [],
            seen = new Set();

        for (const c of columns) {
            // Remove duplicates while we're at it
            if (seen.has(c))
                continue;

            seen.add(c);

            if (c in this.settings.columns.definitions)
                valid.push(c);
        }

        // There must always be at least one visible column
        if (valid.length > 0)
            this.settings.columns.current = valid;
    }

    // Restore sorting and sorting direction
    if ("sorting" in stored) {
        // Restore these only if they're valid
        if (stored.sorting.column in this.settings.columns.definitions)
            this.settings.sorting.column = stored.sorting.column;
        else console.warn(`The stored sorting column "${stored.sorting.column}" isn't valid, using default`);

        if (stored.sorting.dir == SortOrder.ASCENDING || stored.sorting.dir == SortOrder.DESCENDING)
            this.settings.sorting.dir = stored.sorting.dir;
    } else if ("sort_by" in stored) {
        // TODO: Support multiple sorting columns. The format supports them,
        // but we currently use only the first.
        let sortBy = stored.sort_by.split(";")[0];

        if (sortBy != "") {
            const [by, dir] = sortBy.split(",");

            if (by in this.settings.columns.definitions)
                this.settings.sorting.column = by;
            else console.warn(`The stored sorting column "${by}" isn't valid, using default`);

            if (dir == SortOrder.ASCENDING || dir == SortOrder.DESCENDING)
                this.settings.sorting.dir = dir;
        }
    }

    // Restore filter settings
    if ("filtersEnabled" in stored && typeof(stored.filtersEnabled) == "boolean")
        this.settings.filters.enabled = stored.filtersEnabled;
    else if ("filter" in stored && typeof(stored.filter) == "boolean")
        this.settings.filters.enabled = stored.filter;

    if ("filtersReverse" in stored && typeof(stored.filtersReverse) == "boolean")
        this.settings.filters.reverse = stored.filtersReverse;
    else if ("reverse" in stored && typeof(stored.reverse) == "boolean")
        this.settings.filters.reverse = stored.reverse;

    if ("advanced" in stored && typeof(stored.advanced) == "boolean")
        this.settings.filters.advanced = stored.advanced;

    let tryToLoadOldFilters = false;

    if ("filters" in stored && typeof(stored.filters) == "string") {
        try {
            this.settings.filters.filters = JSON.parse(stored.filters);
        } catch (e) {
            // Okay
            this.settings.filters.filters = null;
            tryToLoadOldFilters = true;
        }
    } else tryToLoadOldFilters = true;

    if (tryToLoadOldFilters) {
        // If there were no new saved filters, but the old format filters are still present,
        // try to convert them. This is done only once and if it fails, too bad.
        // This code will be removed later.
        console.log("Attempting to load old filters, if present");

        let old = localStorage.getItem(`table-${this.id}-filters`);

        if (old !== null && old !== "") {
            console.log("Old filters present:");
            console.log(old);

            try {
                const OPERATOR_CONVERSION = {
                    "equ": "=",
                    "neq": "!=",
                    "lt": "<",
                    "lte": "<=",
                    "gt": ">",
                    "gte": ">="
                };

                let converted = [];

                for (const f of JSON.parse(old)) {
                    if ("active" in f && "column" in f && "operator" in f && "value" in f && f.operator in OPERATOR_CONVERSION) {
                        const v = Array.isArray(f.value) ? f.value[0] : f.value;
                        converted.push([f.active ? 1 :0, f.column, OPERATOR_CONVERSION[f.operator], v]);
                    }
                }

                console.log("Conversion results:");
                console.log(converted);

                if (converted.length > 0)
                    this.settings.filters.filters = [...converted];

                // Purge the old filters, they're no longer needed
                localStorage.removeItem(`table-${this.id}-filters`);
            } catch (e) {
                console.error("Failed to convert the old filters:");
                console.error(e);
            }
        }
    }

    if ("filters_string" in stored && typeof(stored.filters_string) == "string")
        this.settings.filters.string = stored.filters_string;

    // Restore pagination settings
    if ("rows_per_page" in stored && typeof(stored.rows_per_page) == "number") {
        let found = false;

        // Validate the stored setting. Only allow predefined values.
        for (const r of ROWS_PER_PAGE_PRESETS) {
            if (r[0] == stored.rows_per_page) {
                this.settings.paging.rowsPerPage = stored.rows_per_page;
                found = true;
                break;
            }
        }

        if (!found)
            this.settings.paging.rowsPerPage = DEFAULT_ROWS_PER_PAGE;
    }

    return true;
}

// Constructs an object that contains all the current settings. If 'full' is false, then
// some "non-essential" items are omitted from it (used in settings JSON import/export).
getSettingsObject(full=true)
{
    let filters = null;

    if (Array.isArray(this.settings.filters.filters))
        filters = JSON.stringify(this.settings.filters.filters, null, "");

    let settings = {
        tab: this.settings.currentTab,
        columns: this.settings.columns.current.join(","),
        sort_by: `${this.settings.sorting.column},${this.settings.sorting.dir}`,
        filter: this.settings.filters.enabled,
        reverse: this.settings.filters.reverse,
        advanced: this.settings.filters.advanced,
        filters: filters,
        filters_string: typeof(this.settings.filters.string) == "string" ? this.settings.filters.string : "",
        rows_per_page: this.settings.paging.rowsPerPage,
    };

    if (!full) {
        // Not needed in the JSON settings import/export, because you'll always be on
        // the "Tools" tab to use the import/export.
        delete settings["tab"];
    }

    return settings;
}

updateSettingsExport()
{
    if (!this.container)
        return;

    if (this.settings.flags & TableFlag.DISABLE_VIEW_SAVING)
        return;

    const settings = this.getSettingsObject(false);

    let jsonBox = this.container.querySelector("div.stTab#tab-tools textarea#tools-saved-json");
    //    urlBox = this.container.querySelector("div.stTab#tab-tools input#tools-saved-url"),
    //    urlLink = this.container.querySelector("div.stTab#tab-tools a#tools-saved-link");

    if (jsonBox)
        jsonBox.value = JSON.stringify(settings, null, "  ");

/*
    if (urlBox && urlLink) {
        const params = new URLSearchParams(settings);

        // Must use URL() to access the origin, otherwise the URLs can get "nested" if you open
        // multiple successive filter links.
        const url = `${new URL(document.URL).href}?${params.toString()}`;

        urlBox.value = url;
        urlLink.href = url;
    }
*/
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// USER INTERFACE

// Builds the tab bar button and the tab container
__buildTab(tabID, title, isSelected)
{
    let tab = create("li", { id: `${this.id}-tabbar-${tabID}`, text: title }),
        cont = create("div", { id: `tab-${tabID}`, cls: "stTab" });

    tab.dataset.id = tabID;
    cont.dataset.id = tabID;

    if (isSelected)
        tab.classList.add("selected");
    else tab.classList.add("unselected", "disabled");

    if (!isSelected)
        cont.classList.add("hidden");

    return [tab, cont];
}

__buildToolsTab(tabBar, frag)
{
    let [tab, container] =
        this.__buildTab("tools", _tr('tabs.tools.title'), this.settings.currentTab == "tools");

    let html = "";

    html = `<div class="flex flex-rows flex-gap-10px">`;

    if (this.settings.dynamicData) {
        // We have dynamic data source, so permit live reloads
        html +=
`<div class="flex flex-cols flex-gap-10px">
<button id="btnReload" disabled>${_tr("tabs.tools.reload")}</button>
</div>`;
    }

    if (!(this.settings.flags & TableFlag.DISABLE_EXPORT)) {
        html +=
`<details>
<summary>${_tr("tabs.tools.export.title")}</summary>
<div class="padding-10px flex flex-vcenter flex-columns flex-gap-10px">
<button id="btnCSV" disabled>${_tr("tabs.tools.export.as_csv")}</button>
<button id="btnJSON" disabled>${_tr("tabs.tools.export.as_json")}</button>
<span><input type="checkbox" id="${this.id}-only-visible-rows" checked><label for="${this.id}-only-visible-rows" title="${_tr("tabs.tools.export.only_visible_rows_help")}">${_tr("tabs.tools.export.only_visible_rows")}</label></span>
<span><input type="checkbox" id="${this.id}-only-visible-cols" checked><label for="${this.id}-only-visible-cols" title="${_tr("tabs.tools.export.only_visible_cols_help")}">${_tr("tabs.tools.export.only_visible_cols")}</label></span>
</div>
</details>
`;
    }

    if (!(this.settings.flags & TableFlag.DISABLE_VIEW_SAVING)) {
        html +=
`<details>
<summary>${_tr("tabs.tools.store.title")}</summary>
<div class="padding-10px">
<p class="margin-0">${_tr("tabs.tools.store.json_explanation")}</p>
<textarea id="tools-saved-json" class="margin-bottom-5px width-100p" rows="8" spellcheck="false"></textarea><br>
<button id="btnLoadJSON" title="${_tr('tabs.tools.store.json_load_help')}">${_tr("tabs.tools.store.json_load")}</button>
</div>
</details>`;
    }

    html += "</div>";

    container.innerHTML = html;

    if (this.settings.dynamicData) {
        // Static data cannot be reloaded on-the-fly
        container.querySelector(`button#btnReload`).addEventListener("click", () => this.fetchDataAndUpdate());
    }

    //container.querySelector(`button#btnExitTempMode`).addEventListener("click", () => this.exitTemporaryMode());

    if (!(this.settings.flags & TableFlag.DISABLE_EXPORT)) {
        container.querySelector(`button#btnCSV`).addEventListener("click", () => this.exportTable("csv"));
        container.querySelector(`button#btnJSON`).addEventListener("click", () => this.exportTable("json"));
    }

    if (!(this.settings.flags & TableFlag.DISABLE_VIEW_SAVING)) {
        container.querySelector(`button#btnLoadJSON`).addEventListener("click", () => this.loadSettingsJSON());
        //container.querySelector(`button#btnCopyURL`).addEventListener("click", () => this.copySettingsURL());
    }

    tabBar.appendChild(tab);
    frag.appendChild(container);
}

__buildColumnsTab(tabBar, frag)
{
    let [tab, container] =
        this.__buildTab("columns", _tr('tabs.columns.title'), this.settings.currentTab == "columns");

    let html =
`<p class="margin-0 padding-0">${_tr('tabs.columns.help')}</p>
<div class="flex flex-columns margin-top-5px margin-bottom-5px flex-gap-10px">
<p class="columnStats margin-0 padding-0 margin-top-5px margin-bottom-5px"></p>
<input type="search" placeholder="${_tr('tabs.columns.search')}" spellcheck="false"></input>
</div>
<div class="flex flex-columns flex-gap-5px">
<div class="flex flex-rows flex-no-wrap colList">`;

    // Sort the columns alphabetically by their localized names
    const columnNames =
        Object.keys(this.settings.columns.definitions)
        .map((key) => [key, this.settings.columns.titles[key]])
        .sort((a, b) => { return a[1].localeCompare(b[1]) });

    const current = new Set(this.settings.columns.current);

    for (const c of columnNames) {
        const def = this.settings.columns.definitions[c[0]];
        let cls = ["column", "disabled"];   // initially everything is disabled

        if (current.has(c[0]))
            cls.push("selected");

        html += `<div data-column="${c[0]}" class="${cls.join(' ')}">`;

        if (current.has(c[0]))
            html += `<input type="checkbox" checked></input>`;
        else html += `<input type="checkbox"></input>`;

        html += `${c[1]} (<span class="columnName">${c[0]}</span>)</div>`;
    }

    html +=
`</div><div>
<div class="flex flex-rows flex-gap-5px" id="columnButtons">
<button id="save" disabled>${_tr('tabs.columns.save')}</button>
<button id="reset" disabled>${_tr('tabs.columns.defaults')}</button>
<button id="selectAll" disabled>${_tr('tabs.columns.all')}</button>
<button id="deselectAll" disabled>${_tr('tabs.columns.none')}</button>
<button id="sort" disabled>${_tr('tabs.columns.sort')}</button>
</div></div>`;

    container.innerHTML = html;

    for (let i of container.querySelectorAll(`.colList .column`))
        i.addEventListener("click", (e) => this.toggleColumn(e.target));

    container.querySelector(`input[type="search"]`).addEventListener("input", (e) => this.filterColumnList(e));
    container.querySelector("button#save").addEventListener("click", () => this.saveColumns());
    container.querySelector("button#reset").addEventListener("click", () => this.resetColumns());
    container.querySelector("button#selectAll").addEventListener("click", () => this.allColumns(true));
    container.querySelector("button#deselectAll").addEventListener("click", () => this.allColumns(false));
    container.querySelector("button#sort").addEventListener("click", () => this.resetColumnOrder());

    tabBar.appendChild(tab);
    frag.appendChild(container);
}

__buildFilteringTab(tabBar, frag)
{
    let [tab, container] =
        this.__buildTab("filters",
            _tr('tabs.filtering.title') + (this.settings.filters.enabled ? " [ON]" : " [OFF]"),
        this.settings.currentTab == "filters");

    container.classList.add("filters");

    let html = "";

    html += `<div class="flex flex-vcenter flex-columns flex-gap-10px">`

    html += `<span><input type="checkbox" id="st-filters-enabled-${this.id}" disabled>` +
            `<label for="st-filters-enabled-${this.id}">${_tr('tabs.filtering.enabled')}` +
            `</label></span>`;

    html += `<span><input type="checkbox" id="st-filters-reverse-${this.id}" disabled>` +
            `<label for="st-filters-reverse-${this.id}">${_tr('tabs.filtering.reverse')}` +
            `</label></span>`;

    html += `<span><input type="checkbox" id="st-filters-advanced-${this.id}">` +
            `<label for="st-filters-advanced-${this.id}">${_tr("tabs.filtering.advanced")}` +
            `</label></span>`;

    html += `</div><div class="stFilters margin-top-10px"></div>`;

    container.innerHTML = html;

    this.ui.filters.enabled = container.querySelector(`input#st-filters-enabled-${this.id}`);
    this.ui.filters.reverse = container.querySelector(`input#st-filters-reverse-${this.id}`);
    this.ui.filters.advanced = container.querySelector(`input#st-filters-advanced-${this.id}`);

    this.ui.filters.enabled.addEventListener("click", () => this.toggleFiltersEnabled());
    this.ui.filters.reverse.addEventListener("click", () => this.toggleFiltersReverse());
    this.ui.filters.advanced.addEventListener("click", () => this.toggleFiltersAdvanced());

    // Restore settings
    this.ui.filters.enabled.checked = this.settings.filters.enabled;
    this.ui.filters.reverse.checked = this.settings.filters.reverse;
    this.ui.filters.advanced.checked = this.settings.filters.advanced;

    // Construct the filter editor
    this.ui.filters.editor = new FilterEditor(this,
                                              container.querySelector("div.stFilters"),
                                              this.settings.columns.definitions,
                                              this.settings.columns.titles,
                                              this.settings.filters.presets,
                                              this.settings.filters.defaults,
                                              this.settings.filters.advanced);

    tabBar.appendChild(tab);
    frag.appendChild(container);
}

__buildMassToolsTab(tabBar, frag)
{
    let [tab, container] =
        this.__buildTab("mass", _tr('tabs.mass.title'), this.settings.currentTab == "mass");

    container.classList.add("stMass");

    let html = "";

    html +=
`<div class="flex flex-rows flex-gap-10px">
<details><summary>${_tr('tabs.mass.mass_row_select_title')}</summary>
<div id="massRowTools">
<div class="flex flex-columns flex-gap-10px margin-top-10px">
<fieldset><legend>${_tr('tabs.mass.mass_row_whole_table')}</legend>
<div class="mainButtons flex flex-rows flex-gap-5px">
<button id="all">${_tr('tabs.mass.mass_row_select_all')}</button>
<button id="none">${_tr('tabs.mass.mass_row_deselect_all')}</button>
<button id="invert">${_tr('tabs.mass.mass_row_invert_selection')}</button>
<button id="successfull">${_tr('tabs.mass.mass_row_deselect_successfull')}</button>
</div></fieldset>`;

    // Mass row selection by ID/name/etc.
    if (this.settings.massSelects.length > 0) {
        html +=
`<fieldset><legend>${_tr('tabs.mass.mass_row_specific_rows')}</legend>
<p class="margin-0 padding-0">${_tr('tabs.mass.mass_row_help')}</p>
<div class="flex flex-columns flex-gap-5px margin-top-5px">
<div id="massRowSelectSource" contentEditable="true" spellcheck="false"></div>
<div class="flex flex-rows flex-gap-5px">
<span><label for="massRowSelectType">${_tr('tabs.mass.mass_row_type')}</label><select id="massRowSelectType" class="margin-left-5px">`;

        for (const m of this.settings.massSelects)
            html += `<option data-id="${m[0]}">${m[1]}</option>`;

        html +=
`</select></span>
<button id="massRowSelect" class="margin-top-5px">${_tr('tabs.mass.mass_row_select')}</button>
<button id="massRowDeselect">${_tr('tabs.mass.mass_row_deselect')}</button>
<div id="massRowSelectStatus">&nbsp;</div>
</div></div>`;
    }

    html +=
`</fieldset></div></details>
<fieldset><legend>${_tr('tabs.mass.operation_title')}</legend>
<div id="controls" class="flex flex-columns flex-gap-10px flex-nowrap flex-vcenter">
<select class="operation" disabled>`;

    html += `<option data-id="" hidden disabled selected value>${_tr('selected')}</option>`;

    for (const m of this.settings.massOperations)
        html += `<option data-id="${m.id}">${m.title}</option>`;

    html +=
`</select>
<button>${_tr('tabs.mass.proceed')}</button>
<progress class="hidden"></progress>
<span class="hidden counter"></span>
</div></fieldset>`;

    // This is where the mass operation child UI is placed in
    html +=
`<fieldset id="settings" class="hidden"><legend>${_tr('tabs.mass.settings_title')}</legend>
<div class="margin-0 padding-0" id="ui"></div></fieldset>`;

    html += "</div>";

    container.classList.add("mass");

    container.innerHTML = html;

    container.querySelector("#all")
        .addEventListener("click", () => this.massSelectAllRows(RowSelectOp.SELECT_ALL));
    container.querySelector("#none")
        .addEventListener("click", () => this.massSelectAllRows(RowSelectOp.DESELECT_ALL));
    container.querySelector("#successfull")
        .addEventListener("click", () => this.massSelectAllRows(RowSelectOp.DESELECT_SUCCESSFULL));
    container.querySelector("#invert")
        .addEventListener("click", () => this.massSelectAllRows(RowSelectOp.INVERT));

    this.ui.mass.proceed = container.querySelector("div#controls > button");
    this.ui.mass.progress = container.querySelector("div#controls > progress");
    this.ui.mass.counter = container.querySelector("div#controls > span.counter");

    if (this.settings.massSelects.length > 0) {
        container.querySelector("div#massRowSelectSource").addEventListener("paste", (e) => this.massSelectFilterPaste(e));
        container.querySelector("button#massRowSelect").addEventListener("click", () => this.massSelectSpecificRows(true));
        container.querySelector("button#massRowDeselect").addEventListener("click", () => this.massSelectSpecificRows(false));
    }

    container.querySelector("div#controls > select").addEventListener("change", (e) =>
        this.switchMassOperation(e));

    this.ui.mass.proceed.addEventListener("click", () => this.doMassOperation());

    tabBar.appendChild(tab);
    frag.appendChild(container);
}

__buildPaginationControls()
{
    let html = "";

    html +=
`<div class="flex flex-rows flex-gap-5px">
<div class="flex flex-columns flex-gap-5px flex-vcenter">
<label for="rowsPerPage">${_tr('paging.rows_per_page')}</label>
<select id="rowsPerPage" title="${_tr('paging.rows_per_page_title')}" disabled>`

    // settings.paging.rowsPerPage has been validated already
    for (const r of ROWS_PER_PAGE_PRESETS) {
        html += `<option data-rows="${r[0]}" ${r[0] == this.settings.paging.rowsPerPage ? "selected" : ""}>`;
        html += r[1];
        html += `</option>`;
    }

    html +=
`</select>
<button id="first" class="margin-left-10px" title="${_tr('paging.first_title')}" disabled>&lt;&lt;</button>
<button id="prev" title="${_tr('paging.prev_title')}" disabled>&lt;</button>
<span id="pageCounter" class="font-monospace">-/-</span>
<button id="next" title="${_tr('paging.next_title')}" disabled>&gt;</button>
<button id="last" title="${_tr('paging.last_title')}" disabled>&gt;&gt;</button></div>
<select id="page" title="${_tr('paging.jump_to_page_title')}" class="" disabled><option>-</option></select>
</div>`;

    let container = create("div", { id: "stPaging", cls: "stPaging" })

    container.innerHTML = html;

    // Event handling
    container.querySelector("select#rowsPerPage").addEventListener("change", () => this.onRowsPerPageChanged());
    container.querySelector("button#first").addEventListener("click", () => this.onPageDelta(-999999));
    container.querySelector("button#prev").addEventListener("click", () => this.onPageDelta(-1));
    container.querySelector("button#next").addEventListener("click", () => this.onPageDelta(+1));
    container.querySelector("button#last").addEventListener("click", () => this.onPageDelta(+999999));
    container.querySelector("select#page").addEventListener("change", () => this.onJumpToPage());

    this.ui.paging = container;
}

buildUI()
{
    // Can't assume the container DIV already has the required styles
    this.container.classList.add("superTable", "flex", "flex-rows", "flex-gap-10px");

/*
    // Temporary mode warning message
    let temporary = create("div", { cls: ["hidden", "not-visible"], id: "stTemporaryMode", html: _tr("temporary_mode") });

    if (this.temporaryMode)
        temporary.classList.remove("hidden", "not-visible");
*/

    // Wrapper for the tabs
    let controls = create("div", { cls: "stControls" });

    // Build the tab bar and the child dialogs
    let tabBar = create("ul", { cls: "stTabBar" });

    controls.appendChild(tabBar);

    if (!(this.settings.flags & TableFlag.DISABLE_TOOLS))
        this.__buildToolsTab(tabBar, controls);

    if (this.settings.flags & TableFlag.ENABLE_COLUMN_EDITING)
        this.__buildColumnsTab(tabBar, controls);

    if (this.settings.flags & TableFlag.ENABLE_FILTERING)
        this.__buildFilteringTab(tabBar, controls);

    if (this.settings.flags & TableFlag.ENABLE_SELECTION)
        this.__buildMassToolsTab(tabBar, controls);

    if (this.settings.flags & TableFlag.ENABLE_PAGINATION)
        this.__buildPaginationControls();

    // Assemble the full layout
    let upper = create("div", { cls: "stUpper" });

    upper.appendChild(controls);

    let statusOuter = create("div", {cls: "stStatusOuter"});

    let status = create("div", { cls: "stStatus" });

    statusOuter.appendChild(status);

    if (this.settings.flags & TableFlag.ENABLE_PAGINATION)
        statusOuter.appendChild(this.ui.paging);

//    this.container.appendChild(temporary);
    this.container.appendChild(upper);
    this.container.appendChild(statusOuter);
    this.container.appendChild(create("div", { cls: ["stError", "hidden"]}));
    this.container.appendChild(create("div", { cls: "stTableWrapper" }));

    // Setup tab switching
    for (let tab of this.container.querySelectorAll(".stTabBar li"))
        tab.addEventListener("click", (e) => this.switchTab(e.target.dataset.id));
}

switchTab(tab)
{
    if (this.updating || this.processing)
        return;

    if (this.settings.currentTab == tab)
        return;

    // Swap the active tab in the tab bar
    for (let t of this.container.querySelectorAll(".stTabBar > li")) {
        if (t.classList.contains("disabled"))
            continue;

        if (t.dataset.id == tab) {
            t.classList.add("selected");
            t.classList.remove("unselected");
        } else {
            t.classList.remove("selected");
            t.classList.add("unselected");
        }
    }

    // Swap the visible tab child
    for (let tabChild of this.container.querySelectorAll("div.stTab")) {
        if (tabChild.dataset.id == tab)
            tabChild.classList.remove("hidden");
        else tabChild.classList.add("hidden");
    }

    this.settings.currentTab = tab;
    this.saveSettings();
}

// Updates the "status bar" numbers (total rows, selected rows, etc.) and
// some selection-dependent button states
updateUI()
{
    let totalRows = 0,
        visibleRows = 0;

    try { totalRows = this.data.transformed.length; } catch (e) {}
    try { visibleRows = this.data.current.length; } catch (e) {}

    let parts = [];

    parts.push(`<div>${totalRows} ${_tr('status.total_rows')}`);
    parts.push(`${visibleRows} ${_tr('status.visible_rows')}`);
    parts.push(`${totalRows - visibleRows} ${_tr('status.filtered_rows')}`);

    if (this.settings.flags & TableFlag.ENABLE_SELECTION) {
        parts.push(`<br>${this.data.selectedItems.size} ${_tr('status.selected_rows')}`);

        if (this.processing || this.doneAtLeastOneOperation) {
            parts.push(`(<span class=\"success\">${this.data.successItems.size} ${_tr('status.successfull_rows')}</span>`);
            parts.push(`<span class=\"fail\">${this.data.failedItems.size} ${_tr('status.failed_rows')}</span>)`);
        }

        if (this.processing || this.updating || this.massOperation.index == -1)
            this.ui.mass.proceed.disabled = true;
        else this.ui.mass.proceed.disabled = (this.data.selectedItems.size == 0);
    }

    this.setStatus(parts.join(", "));
}

// Enable/disable UI elements. Called during updates, mass operations, etc. to
// prevent the user from initiating multiple overlapping/interfering actions.
enableUI(isEnabled)
{
    //this.container.querySelector(`div.stTab#tab-tools button#btnExitTempMode`).disabled = !isEnabled || !this.temporaryMode;

    if (!(this.settings.flags & TableFlag.DISABLE_TOOLS)) {
        if (this.settings.dynamicData)
            this.container.querySelector(`div.stTab#tab-tools button#btnReload`).disabled = !isEnabled;

        if (!(this.settings.flags & TableFlag.DISABLE_EXPORT)) {
            this.container.querySelector(`div.stTab#tab-tools button#btnCSV`).disabled = !isEnabled;
            this.container.querySelector(`div.stTab#tab-tools button#btnJSON`).disabled = !isEnabled;
        }

        if (!(this.settings.flags & TableFlag.DISABLE_VIEW_SAVING)) {
            this.container.querySelector(`div.stTab#tab-tools textarea#tools-saved-json`).disabled = !isEnabled;
            this.container.querySelector(`div.stTab#tab-tools button#btnLoadJSON`).disabled = !isEnabled;
            //this.container.querySelector(`div.stTab#tab-tools button#btnCopyURL`).disabled = !isEnabled;
        }
    }

    if (this.settings.flags & TableFlag.ENABLE_COLUMN_EDITING)
        this.enableOrDisableColumnEditor(isEnabled);

    if (this.settings.flags & TableFlag.ENABLE_PAGINATION)
        this.enablePaginationControls(isEnabled);

    if (this.settings.flags & TableFlag.ENABLE_FILTERING) {
        this.ui.filters.enabled.disabled = !isEnabled;
        this.ui.filters.reverse.disabled = !isEnabled;
        this.ui.filters.advanced.disabled = !isEnabled;
        this.ui.filters.editor.enableOrDisable(isEnabled);
    }

    if (this.settings.flags & TableFlag.ENABLE_SELECTION) {
        this.container.querySelector("div#controls select").disabled = !isEnabled;
        this.ui.mass.proceed.disabled = !isEnabled;

        for (let b of this.container.querySelectorAll("div#massRowTools button"))
            b.disabled = !isEnabled;

        this.ui.mass.proceed.disabled = !isEnabled && this.data.selectedItems.size == 0;
    }

    if (!isEnabled) {
        for (let t of this.container.querySelectorAll(".stTabBar > li"))
            if (!t.classList.contains("selected"))
                t.classList.add("disabled");
    } else {
        for (let t of this.container.querySelectorAll(".stTabBar > li"))
            t.classList.remove("disabled");
    }
}

// Sets and shows the error message
setError(html)
{
    let e = this.container.querySelector("div.stError");

    e.innerHTML = `${html}. ${_tr('see_console_for_details')}`;
    e.classList.remove("hidden");
}

resetError()
{
    let e = this.container.querySelector("div.stError");

    e.innerHTML = "";
    e.classList.add("hidden");
}

setStatus(html)
{
    this.container.querySelector("div.stStatus").innerHTML = html;
}

// Retrieves the actual table rows
getTableRows()
{
    return this.container ? this.container.querySelectorAll("table.stTable tbody tr") : [];
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// PAGINATION

calculatePagination()
{
    if (!this.ui.paging)
        return;

    if (this.data.current === null || this.data.current === undefined || this.data.current.length == 0) {
        this.paging.numPages = 0;
        this.paging.currentPage = 0;
        return;
    }

    if (this.data.current.length <= this.settings.paging.rowsPerPage) {
        this.paging.numPages = 1;
        this.paging.currentPage = 0;
        return;
    }

    this.paging.numPages = (this.settings.paging.rowsPerPage == -1) ? 1 :
        Math.ceil(this.data.current.length / this.settings.paging.rowsPerPage);

    this.paging.currentPage =
        Math.min(Math.max(this.paging.currentPage, 0), this.paging.numPages - 1);
}

updatePageCounter()
{
    if (!this.ui.paging)
        return;

    let elem = this.ui.paging.querySelector("span#pageCounter");

    if (this.paging.numPages == 0)
        elem.innerHTML = `-/-`;
    else {
        const width = ("" + this.paging.numPages).length;

        elem.innerHTML = `${this.paging.currentPage + 1}`.padStart(width, "\u00a0") + "/" +
                         `${this.paging.numPages}`;
    }
}

onRowsPerPageChanged()
{
    const selector = this.ui.paging.querySelector("select#rowsPerPage");

    const numRows = parseInt(selector.options[selector.selectedIndex].dataset.rows, 10);

    this.settings.paging.rowsPerPage = numRows;
    this.saveSettings();

    const old = this.paging.numPages;

    this.calculatePagination();
    this.enablePaginationControls(true);
    this.updatePaginationPageSelector();

    if (old != this.paging.numPages && this.data.current && this.data.current.length > 0)
        this.buildTable();
}

onPageDelta(delta)
{
    const old = this.paging.currentPage;

    this.paging.currentPage += delta;
    this.calculatePagination();

    if (this.paging.currentPage == old)
        return;

    this.ui.paging.querySelector("select#page").selectedIndex = this.paging.currentPage;
    this.updatePageCounter();
    this.enablePaginationControls(true);

    if (this.data.current && this.data.current.length > 0)
        this.buildTable();
}

onJumpToPage()
{
    const selector = this.ui.paging.querySelector("select#page");
    const pageNum = parseInt(selector.options[selector.selectedIndex].dataset.page, 10);

    this.paging.currentPage = pageNum;
    this.updatePageCounter();
    this.enablePaginationControls(true);
    this.buildTable();
}

enablePaginationControls(state)
{
    if (!this.ui.paging)
        return;

    this.ui.paging.querySelector("select#rowsPerPage").disabled = !state;
    this.ui.paging.querySelector("button#first").disabled = !(state && this.paging.currentPage > 0);
    this.ui.paging.querySelector("button#prev").disabled = !(state && this.paging.currentPage > 0);
    this.ui.paging.querySelector("button#next").disabled = !(state && this.paging.currentPage < this.paging.numPages - 1);
    this.ui.paging.querySelector("button#last").disabled = !(state && this.paging.currentPage < this.paging.numPages - 1);
    this.ui.paging.querySelector("select#page").disabled = !(state && this.paging.numPages > 1);
}

updatePaginationPageSelector()
{
    if (!this.ui.paging)
        return;

    console.log(`updatePaginationPageSelector(): numpages=${this.paging.numPages}, currpage=${this.paging.currentPage}`);

    this.updatePageCounter();

    if (this.paging.numPages == 0) {
        this.ui.paging.querySelector("select#page").innerHTML = ``;
        return;
    }

    const col = this.settings.sorting.column;

    // Assume string columns can contain HTML, but numeric columns won't. The values are
    // HTML-escaped when displayed, but that means HTML tags can slip through and it looks
    // really ugly.
    const index = (this.settings.columns.definitions[col].type == ColumnType.STRING) ?
        INDEX_FILTERABLE : INDEX_DISPLAYABLE;

    // Maximum length of an entry we'll display
    const MAX_LENGTH = 70;

    const limitLength = (str) => {
        return (str.length > MAX_LENGTH) ? str.substring(0, MAX_LENGTH) + "…" : str;
    };

    let html = "";

    if (this.settings.paging.rowsPerPage == -1) {
        // Everything on one giant page
        let first = this.data.current[0],
            last = this.data.current[this.data.current.length - 1];

        first = limitLength(first[col][INDEX_EXISTS] ? first[col][index] : "-");
        last = limitLength(last[col][INDEX_EXISTS] ? last[col][index] : "-");

        html += `<option selected}>1: ${escapeHTML(first)} → ${escapeHTML(last)}</option>`;
    } else {
        for (let page = 0; page < this.paging.numPages; page++) {
            const start = page * this.settings.paging.rowsPerPage;
            const end = Math.min((page + 1) * this.settings.paging.rowsPerPage, this.data.current.length);

            let first = this.data.current[start],
                last = this.data.current[end - 1];

            first = limitLength(first[col][INDEX_EXISTS] ? first[col][index] : "-");
            last = limitLength(last[col][INDEX_EXISTS] ? last[col][index] : "-");

            html += `<option ${page == this.paging.currentPage ? "selected" : ""} ` +
                    `data-page="${page}">${page + 1}: ${escapeHTML(first)} → ${escapeHTML(last)}</option>`;
        }
    }

    this.ui.paging.querySelector("select#page").innerHTML = html;
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// TOOLS

// Download table contents. Format must be "csv" or "json".
exportTable(format)
{
    try {
        const visibleRows = this.container.querySelector(`#${this.id}-only-visible-rows`).checked,
              visibleCols = this.container.querySelector(`#${this.id}-only-visible-cols`).checked;
        const source = visibleRows ? this.data.current : this.data.transformed;
        let output = [];

        const columns = visibleCols ?
            this.settings.columns.current :
            Object.keys(this.settings.columns.definitions);

        let headers = [...columns];

        // Optional export alias names
        for (let i = 0; i < headers.length; i++) {
            const def = this.settings.columns.definitions[headers[i]];

            if (def.export_name)
                headers[i] = def.export_name;
        }

        let mimetype, extension;

        if (format == "csv") {
            // CSV export

            // Header first
            output.push(headers.join(";"));

            for (const row of source) {
                let out = [];

                for (const col of columns)
                    out.push(col in row ? row[col][INDEX_FILTERABLE] : "");

                output.push(out.join(";"));
            }

            output = output.join("\n");
            mimetype = "text/csv";
            extension = "csv";
        } else {
            // JSON export
            for (const row of source) {
                let out = {};

                for (let i = 0; i < columns.length; i++)
                    if (columns[i] in row)
                        out[headers[i]] = row[columns[i]][INDEX_FILTERABLE];

                output.push(out);
            }

            output = JSON.stringify(output);
            mimetype = "application/json";
            extension = "json";
        }

        // Build a blob object (it must be an array for some reason), then trigger a download.
        // Download code stolen from StackOverflow.
        const b = new Blob([output], { type: mimetype });
        let a = window.document.createElement("a");

        a.href = window.URL.createObjectURL(b);
        a.download = `${this.settings.csvPrefix}-${I18n.strftime(new Date(), "%Y-%m-%d-%H-%M-%S")}.${extension}`;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    } catch (e) {
        console.log(e);
        window.alert(`${_tr('export_file_generation_error')}\n\n${e}\n\n${_tr('see_console_for_details')}`);
    }
}

/*
exitTemporaryMode()
{
    if (!window.confirm("Oletko varma? Vanhat asetuksesi korvataan osoiterivillä annetuilla asetuksilla!"))
        return;

    console.log("Leaving the temporary mode");

    this.temporaryMode = false;
    this.container.querySelector("div#stTemporaryMode").classList.add("hidden", "not-visible");
    //this.container.querySelector("button#btnExitTempMode").disabled = true;

    // Remove the parameters from the address without reloading the page
    let url = new URL(window.location);

    for (const key of new Set(url.searchParams.keys()))
        url.searchParams.delete(key);

    history.replaceState(null, null, url);

    // Make the temporary settings permanent
    this.saveSettings();
}
*/

loadSettingsJSON()
{
    const value = this.container.querySelector(`div.stTab#tab-tools textarea#tools-saved-json`).value;
    let json = null;

    try {
        json = JSON.parse(value);
    } catch (e) {
        window.alert(`${_tr("invalid_json")}:\n\n${e.message}`);
        return;
    }

    this.loadSettingsObject(json);

    this.ui.filters.editor.setFilters(this.settings.filters.filters);
    this.ui.filters.editor.setFilterString(this.settings.filters.string);
    this.ui.filters.editor.toggleMode(this.settings.filters.advanced);
    this.ui.filters.enabled.checked = this.settings.filters.enabled;
    this.ui.filters.reverse.checked = this.settings.filters.reverse;
    this.ui.filters.advanced.checked = this.settings.filters.advanced;
    this.settings.filters.program = this.ui.filters.editor.getFilterProgram();

    this.calculatePagination();
    this.updatePaginationPageSelector();
    this.updateTable();
}

copySettingsURL()
{
    const url = this.container.querySelector(`div.stTab#tab-tools input#tools-saved-url`).value;

    navigator.clipboard.writeText(url)
        .then(function(){}, function(err) {
            console.log(err);
            window.alert("URL copying failed :-(");
        });
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// VISIBLE COLUMN EDITING

// Column reordering by header dragging is located later in this file

getColumnList(selected)
{
    const path = "div#tab-columns div.colList > div";

    return this.container.querySelectorAll(selected ? path + ".selected" : path);
}

// Check/uncheck the column on the list
toggleColumn(target)
{
    if (this.processing || this.updating)
        return;

    if (target.classList.contains("disabled"))
        return;

    if (target.classList.contains("selected")) {
        target.classList.remove("selected");
        target.childNodes[0].checked = false;
    } else {
        target.classList.add("selected");
        target.childNodes[0].checked = true;
    }

    this.unsavedColumns = true;
    this.updateColumnEditor();
}

saveColumns()
{
    if (this.processing || this.updating)
        return;

    // Make a list of new visible columns
    let newVisible = new Set();

    for (let c of this.getColumnList(true))
        if (c.classList.contains("selected"))
            newVisible.add(c.dataset.column);

    // Keep the existing columns in whatever order they were, but remove
    // hidden columns
    let newColumns = [];

    for (const col of this.settings.columns.current) {
        if (newVisible.has(col)) {
            newColumns.push(col);
            newVisible.delete(col);
        }
    }

    // Then tuck the new columns at the end of the array
    for (const col of newVisible)
        newColumns.push(col);

    this.settings.columns.current = newColumns;

    // Is the current sorting column still visible? If not, find another column to sort by.
    let sortVisible = false,
        defaultVisible = false;

    for (const col of newColumns) {
        if (this.settings.sorting.column == col)
            sortVisible = true;

        if (this.settings.columns.defaultSorting.column == col)
            defaultVisible = true;
    }

    if (!sortVisible) {
        if (defaultVisible) {
            // The default column is visible, so use it
            this.settings.sorting.column = this.settings.columns.defaultSorting.column;
        } else {
            // Pick the first column we have and use it
            // FIXME: What happens if the first column has ColumnFlag.NOT_SORTABLE flag?
            // FIXME: What happens if there are no sortable columns at all?
            this.settings.sorting.column = newColumns[0];
        }
    }

    this.unsavedColumns = false;
    this.updateColumnEditor();
    this.saveSettings();
    this.updateTable();
}

resetColumns()
{
    if (this.processing || this.updating)
        return;

    const initial = new Set(this.settings.columns.defaults);

    for (let c of this.getColumnList(false)) {
        if (initial.has(c.dataset.column)) {
            c.classList.add("selected");
            c.firstChild.checked = true;
        } else {
            c.classList.remove("selected");
            c.firstChild.checked = false;
        }
    }

    this.unsavedColumns = true;
    this.updateColumnEditor();
}

allColumns(select)
{
    if (this.processing || this.updating)
        return;

    let changed = false;

    for (let c of this.getColumnList(false)) {
        if (c.classList.contains("hidden"))
            continue;

        if (select)
            c.classList.add("selected");
        else c.classList.remove("selected");

        if (c.firstChild.checked != select) {
            c.firstChild.checked = select;
            changed = true;
        }
    }

    if (changed) {
        this.unsavedColumns = true;
        this.updateColumnEditor();
    }
}

resetColumnOrder()
{
    const current = new Set(this.settings.columns.current);
    let nc = [];

    for (const c of this.settings.columns.order)
        if (current.has(c))
            nc.push(c);

    this.settings.columns.current = nc;
    this.saveSettings();
    this.updateTable();
}

updateColumnEditor()
{
    const numSelected = this.getColumnList(true).length;
    let saveButton = this.container.querySelector("div#tab-columns div#columnButtons button#save")

    if (numSelected == 0)
        saveButton.disabled = true;
    else saveButton.disabled = !this.unsavedColumns;

    const totalColumns = Object.keys(this.settings.columns.definitions).length;

    this.container.querySelector("div.stTab#tab-columns p.columnStats").innerHTML =
        `${_tr('tabs.columns.selected')} ${numSelected}/${totalColumns} ${_tr('tabs.columns.total')}:`;
}

enableOrDisableColumnEditor(isEnabled)
{
    for (let c of this.getColumnList(false)) {
        if (isEnabled)
            c.classList.remove("disabled");
        else c.classList.add("disabled");

        c.firstChild.disabled = !isEnabled;
    }

    for (let button of this.container.querySelectorAll("div#tab-columns div#columnButtons button"))
        button.disabled = !isEnabled;

    this.updateColumnEditor();
}

filterColumnList(e)
{
    const filter = e.target.value.trim().toLowerCase();

    // The list is not rebuilt when searching, we just change item visibilities.
    // This way, searching for something else does not undo previous changes
    // if they weren't saved yet.
    for (let c of this.getColumnList()) {
        const title = this.settings.columns.titles[c.dataset.column];

        if (filter && title.toLowerCase().indexOf(filter) == -1)
            c.classList.add("hidden");
        else c.classList.remove("hidden");
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// FILTERS

// Called from the filter editor whenever a change to the filters have been made
saveFilters()
{
    this.settings.filters.filters = this.ui.filters.editor.getFilters();
    this.settings.filters.string = this.ui.filters.editor.getFilterString();
    this.saveSettings();
}

// Called when a filtering settings have changed enough to force the table to be updated
updateFiltering()
{
    this.settings.filters.program = this.ui.filters.editor.getFilterProgram();
    this.doneAtLeastOneOperation = false;

    if (this.settings.filters.enabled) {
        this.clearRowSelections();
        this.updateTable();
    }
}

toggleFiltersEnabled()
{
    if (this.updating || this.processing)
        return;

    this.settings.filters.enabled = this.ui.filters.enabled.checked;

    this.container.querySelector(`li#${this.id}-tabbar-filters`).innerText =
        _tr('tabs.filtering.title') + (this.settings.filters.enabled ? " [ON]" : " [OFF]");

    this.doneAtLeastOneOperation = false;
    this.saveSettings();
    this.clearRowSelections();
    this.updateTable();
}

toggleFiltersReverse()
{
    if (this.updating || this.processing)
        return;

    this.settings.filters.reverse = this.ui.filters.reverse.checked;
    this.saveSettings();

    if (this.settings.filters.enabled) {
        this.doneAtLeastOneOperation = false;
        this.clearRowSelections();
        this.updateTable();
    }
}

toggleFiltersAdvanced()
{
    if (this.updating || this.processing)
        return;

    this.settings.filters.advanced = this.ui.filters.advanced.checked;
    this.saveSettings();

    this.ui.filters.editor.toggleMode(this.settings.filters.advanced);

    if (this.settings.filters.enabled) {
        this.doneAtLeastOneOperation = false;
        this.clearRowSelections();
        this.updateTable();
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MASS OPERATIONS AND ROW SELECTIONS

// Mass select or deselect table rows
massSelectAllRows(operation)
{
    if (this.updating || this.processing || !this.data.current || this.data.current.length == 0)
        return;

    if (this.ui.previousRow) {
        this.ui.previousRow.classList.remove("previousRow");
        this.ui.previousRow = null;
    }

    // Update internal state
    if (operation == RowSelectOp.SELECT_ALL) {
        this.data.selectedItems.clear();

        for (const i of this.data.current)
            this.data.selectedItems.add(i.id[INDEX_DISPLAYABLE]);

        this.data.successItems.clear();
        this.data.failedItems.clear();
    } else if (operation == RowSelectOp.DESELECT_ALL) {
        this.data.selectedItems.clear();
        this.data.successItems.clear();
        this.data.failedItems.clear();
    } else if (operation == RowSelectOp.INVERT_SELECTION) {
        let newState = new Set();

        for (const i of this.data.current)
            if (!this.data.selectedItems.has(i.id[INDEX_DISPLAYABLE]))
                newState.add(i.id[INDEX_DISPLAYABLE]);

        this.data.selectedItems = newState;
        this.data.successItems.clear();
        this.data.failedItems.clear();
    } else if (operation == RowSelectOp.DESELECT_SUCCESSFULL) {
        for (const id of this.data.successItems)
            this.data.selectedItems.delete(id);

        this.data.successItems.clear();
    }

    // Rebuilding the table is too slow, so modify the checkbox cells directly
    for (let row of this.getTableRows()) {
        let cb = row.childNodes[0].childNodes[0];

        switch (operation) {
            case RowSelectOp.SELECT_ALL:
                cb.classList.add("checked");
                row.classList.remove("success", "fail");
                break;

            case RowSelectOp.DESELECT_ALL:
                cb.classList.remove("checked");
                row.classList.remove("success", "fail");
                break;

            case RowSelectOp.INVERT_SELECTION:
                if (cb.classList.contains("checked"))
                    cb.classList.remove("checked");
                else cb.classList.add("checked");

                row.classList.remove("success", "fail");
                break;

            case RowSelectOp.DESELECT_SUCCESSFULL:
                if (row.classList.contains("success")) {
                    row.classList.remove("success");
                    cb.classList.remove("checked");
                }

                break;

            default:
                break;
        }
    }

    this.doneAtLeastOneOperation = false;
    this.updateUI();
}

// Strip HTML from the pasted text (plain text only!). The thing is, the "text box" is a
// contentEdit-enabled DIV, so it accepts HTML. If you paste data from, say, LibreOffice
// Calc, the spreadsheet font gets embedded in it and it can actually screw up the page's
// layout completely (I saw that happening)! That's not acceptable, so this little function
// will hopefully remove all HTML from whatever's being pasted and leave only plain text.
// See https://developer.mozilla.org/en-US/docs/Web/API/ClipboardEvent/clipboardData
massSelectFilterPaste(e)
{
    e.preventDefault();
    e.target.innerText = e.clipboardData.getData("text/plain");
}

// Perform row mass selection
massSelectSpecificRows(state)
{
    if (this.updating || this.processing)
        return;

    let container = this.container.querySelector("div#massRowSelectSource");

    // Source data type
    const selector = this.container.querySelector("select#massRowSelectType");
    const type = selector.options[selector.selectedIndex].dataset.id;
    const numeric = this.settings.columns.definitions[type].type != ColumnType.STRING;

    // Extract plain text content
    let entries = new Set();

    for (const i of container.innerText.split("\n")) {
        let s = i.trim();

        if (s.length == 0 || s[0] == "#")
            continue;

        if (numeric) {
            s = parseInt(s, 10);

            if (isNaN(s))
                continue;
        }

        entries.add(s);
    }

    // Select/deselect the rows
    let tableRows = this.getTableRows();
    let found = new Set();

    for (let i = 0, j = this.data.current.length; i < j; i++) {
        const item = this.data.current[i];

        if (!item[type][INDEX_EXISTS])
            continue;

        const field = item[type][INDEX_FILTERABLE];

        if (!entries.has(field))
            continue;

        found.add(field);

        const id = item.id[INDEX_DISPLAYABLE];

        if (state)
            this.data.selectedItems.add(id);
        else {
            this.data.selectedItems.delete(id);
            this.data.successItems.delete(id);
            this.data.failedItems.delete(id);
        }

        // Directly update visible table rows
        if (i >= this.paging.firstRowIndex && i < this.paging.lastRowIndex) {
            let row = tableRows[i - this.paging.firstRowIndex],
                cb = row.childNodes[0].childNodes[0];

            if (state)
                cb.classList.add("checked");
            else cb.classList.remove("checked");

            row.classList.remove("success", "fail");
        }
    }

    // Highlight the items that weren't found
    let html = "";

    for (const e of entries) {
        if (found.has(e))
            html += "<div>";
        else html += `<div class="unmatchedRow">`;

        html += escapeHTML(e);
        html += "</div>";
    }

    container.innerHTML = html;

    this.container.querySelector("div#massRowSelectStatus").innerHTML =
        _tr('tabs.mass.mass_row_status',
            { total: entries.size, match: found.size, unmatched: entries.size - found.size });

    this.updateUI();
}

// Called when the selected mass operation changes
switchMassOperation(e)
{
    const index = e.target.selectedIndex - 1;
    const def = this.settings.massOperations[index];

    let fieldset = this.container.querySelector("div.stTab#tab-mass fieldset#settings"),
        container = fieldset.querySelector("div#ui");

    // Instantiate a new class
    this.massOperation.index = index;
    this.massOperation.handler = new def.cls(this, container);
    this.massOperation.singleShot = def.flags & MassOperationFlags.SINGLESHOT;

    // Hide/swap the UI
    container.innerHTML = "";

    if (def.flags & MassOperationFlags.HAVE_SETTINGS) {
        this.massOperation.handler.buildInterface();
        fieldset.classList.remove("hidden");
    } else fieldset.classList.add("hidden");

    this.ui.mass.progress.classList.add("hidden");
    this.ui.mass.counter.classList.add("hidden");

    this.doneAtLeastOneOperation = false;
    this.updateUI();
}

// Run the selected mass operation
doMassOperation()
{
    if (this.updating || this.processing)
        return;

    if (!this.massOperation.handler.canProceed())
        return;

    if (!window.confirm(_tr('are_you_sure')))
        return;

    function enableMassUI(ctx, isEnabled)
    {
        // Prevent tab switching during the operation. This way the user can't switch tabs
        // during the operation and we only have to disable controls in the mass tools tab.
        for (let t of ctx.container.querySelectorAll(".stTabBar > li")) {
            if (t.classList.contains("selected"))
                continue;

            if (isEnabled)
                t.classList.remove("disabled");
            else t.classList.add("disabled");
        }

        for (let b of ctx.container.querySelectorAll("div#massRowTools button"))
            b.disabled = !isEnabled;

        ctx.container.querySelector("div#controls select").disabled = !isEnabled;
        ctx.ui.mass.proceed.disabled = !isEnabled;

        ctx.enablePaginationControls(isEnabled);

        ctx.enableTable(isEnabled);
    }

    function beginOperation(ctx, numItems)
    {
        enableMassUI(ctx, false);

        ctx.ui.mass.progress.setAttribute("max", numItems);
        ctx.ui.mass.progress.setAttribute("value", 0);
        ctx.ui.mass.progress.classList.remove("hidden");
        ctx.ui.mass.counter.innerHTML = `0/${numItems}`;
        ctx.ui.mass.counter.classList.remove("hidden");

        ctx.processing = true;

        // This flag controls whether the success/fail counters will be visible after the
        // operation is done. They will be visible until the UI/selections change.
        ctx.doneAtLeastOneOperation = true;
    }

    function endOperation(ctx)
    {
        ctx.massOperation.handler.finish();

        enableMassUI(ctx, true);
        ctx.processing = false;

        // Leave the progress bar and the counter visible. They're only hidden until
        // the first time a mass operation is executed.
    }

    function updateProgress(ctx, numItems, currentItem)
    {
        ctx.ui.mass.progress.setAttribute("value", currentItem);
        ctx.ui.mass.counter.innerHTML = `${currentItem}/${numItems}`;
    }

    function updateRow(ctx, row, status)
    {
        if (!row[1]) {
            // This row is not on the current page
            return;
        }

        let cell = row[1];

        if (status.success === true) {
            cell.classList.remove("fail");
            cell.classList.add("success");
            cell.title = "";
        } else {
            cell.classList.remove("success");
            cell.classList.add("fail");

            // TODO: These messages need better visibility
            if (status.message === null)
                cell.title = "";
            else cell.title = status.message;
        }
    }

    let tableRows = this.getTableRows();

    // Reset previous row states of visible rows
    for (let row of tableRows)
        row.classList.remove("success", "fail");

    // Make a list of the selected items, in the order they appear in the table right now.
    // Store a reference to the table row so it can be easily updated in-place.
    let itemsToBeProcessed = [];

    for (let i = 0; i < this.data.current.length; i++) {
        const item = this.data.current[i];

        if (this.data.selectedItems.has(item.id[INDEX_DISPLAYABLE])) {
            if (i >= this.paging.firstRowIndex && i <= this.paging.lastRowIndex) {
                // Only rows that are visible on the current page can be live updated
                itemsToBeProcessed.push([item, tableRows[i - this.paging.firstRowIndex]]);
            } else itemsToBeProcessed.push([item, null]);
        }
    }

    this.data.successItems.clear();
    this.data.failedItems.clear();

    let us = this;      // JS scoping weirdness workaround

    us.massOperation.handler.start();
    beginOperation(us, itemsToBeProcessed.length);

    // Chain together Promise objects, one for every selected row. This
    // loop will exit before the first Promise object is resolved.
    var sequence = Promise.resolve();

    if (us.massOperation.singleShot) {
        // Do everything in one call
        sequence = sequence.then(function() {
            return us.massOperation.handler.processAllItems(itemsToBeProcessed);
        }).then(function(result) {
            // Update all table rows at once and finish the operation
            for (let i = 0; i < itemsToBeProcessed.length; i++) {
                const id = itemsToBeProcessed[i][0].id[INDEX_DISPLAYABLE];

                updateRow(us, itemsToBeProcessed[i], result);

                if (result.success === true)
                    us.data.successItems.add(id);
                else us.data.failedItems.add(id);
            }

            updateProgress(us, itemsToBeProcessed.length, itemsToBeProcessed.length);
            endOperation(us, itemsToBeProcessed.length);
            us.updateUI();
        });
    } else {
        for (let i = 0; i < itemsToBeProcessed.length; i++) {
            sequence = sequence.then(function() {
                // "Schedule" an operation that processes this item
                return us.massOperation.handler.processItem(itemsToBeProcessed[i][0]);
            }).then(function(result) {
                // After the item has been processed, update the status and the table
                // to reflect the state
                const id = itemsToBeProcessed[i][0].id[INDEX_DISPLAYABLE];

                updateRow(us, itemsToBeProcessed[i], result);

                if (result.success === true)
                    us.data.successItems.add(id);
                else us.data.failedItems.add(id);

                if (i >= itemsToBeProcessed.length - 1) {
                    // That was the last item, wrap everything up
                    // TODO: Should this be replaceable with Promise.all()?
                    updateProgress(us, itemsToBeProcessed.length, i + 1);
                    endOperation(us, itemsToBeProcessed.length);
                } else updateProgress(us, itemsToBeProcessed.length, i + 1);

                us.updateUI();
            });
        }
    }
}

// Check/uncheck a row. If Shift is being held, perform a range check/uncheck.
onRowCheckboxClick(e)
{
    e.preventDefault();

    if (this.updating || this.processing)
        return;

    let tr = e.target.parentNode,
        td = e.target,
        cb = tr.childNodes[0].childNodes[0];

    const index = parseInt(tr.dataset.index, 10),
          id = this.data.current[index].id[INDEX_DISPLAYABLE];

    if (e.shiftKey && this.ui.previousRow != null && this.ui.previousRow != td) {
        // Range select/deselect between the previously clicked row and this row
        let startIndex = this.ui.previousRow.parentNode.dataset.index,
            endIndex = tr.dataset.index;

        if (startIndex === undefined || endIndex === undefined) {
            console.error("Cannot determine the start/end indexes for range selection!");
            return;
        }

        startIndex = parseInt(startIndex, 10);
        endIndex = parseInt(endIndex, 10);

        // Select or deselect?
        const state = this.data.selectedItems.has(this.data.current[startIndex].id[INDEX_DISPLAYABLE]);

        if (startIndex > endIndex)
            [startIndex, endIndex] = [endIndex, startIndex];

        let tableRows = this.getTableRows();

        for (let i = startIndex; i <= endIndex; i++) {
            const id = this.data.current[i].id[INDEX_DISPLAYABLE];

            let row = tableRows[i - this.paging.firstRowIndex],
                cb = row.childNodes[0].childNodes[0];

            row.classList.remove("success", "fail");

            if (state) {
                cb.classList.add("checked");
                this.data.selectedItems.add(id);
            } else {
                cb.classList.remove("checked");
                this.data.selectedItems.delete(id);
            }
        }
    } else {
        // Check/uncheck one row
        e.target.parentNode.classList.remove("success", "fail");

        if (cb.classList.contains("checked")) {
            cb.classList.remove("checked");
            this.data.selectedItems.delete(id);
        } else {
            cb.classList.add("checked");
            this.data.selectedItems.add(id);
        }
    }

    // Remember the previously clicked row
    if (this.ui.previousRow)
        this.ui.previousRow.classList.remove("previousRow");

    td.classList.add("previousRow");
    this.ui.previousRow = td;

    this.doneAtLeastOneOperation = false;
    this.updateUI();
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// HEADER ROWS

// Start tracking a table header cell clicks/drags
onHeaderMouseDown(e)
{
    e.preventDefault();

    if (this.updating || this.processing)
        return;

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    this.headerDrag.active = false;         // we don't know yet if it's a click or drag
    this.headerDrag.element = e.target;
    this.headerDrag.canSort = e.target.dataset.sortable == "1";
    this.headerDrag.startingMousePos = { x: e.clientX, y: e.clientY };
    this.headerDrag.startIndex = null;
    this.headerDrag.endIndex = null;
    this.headerDrag.cellPositions = null;

    document.addEventListener("mouseup", this.onHeaderMouseUp);
    document.addEventListener("mousemove", this.onHeaderMouseMove);
}

// Either sort the table, or end cell reordering, depending on how far the mouse was moved
// since the button went down
onHeaderMouseUp(e)
{
    e.preventDefault();

    document.removeEventListener("mouseup", this.onHeaderMouseUp);
    document.removeEventListener("mousemove", this.onHeaderMouseMove);

    let table = this.container.querySelector("table.stTable");

    table.classList.remove("no-text-select", "no-pointer-events");
    document.body.classList.remove("cursor-grabbing");

    this.headerDrag.element = null;     // no memory leaks, please

    this.doneAtLeastOneOperation = false;

    if (!this.headerDrag.active) {
        // The mouse didn't move enough, sort the table by this column
        if (!this.headerDrag.canSort)
            return;

        const index = e.target.dataset.index,
              key = e.target.dataset.key;

        if (key == this.settings.sorting.column) {
            if (this.settings.sorting.dir == SortOrder.ASCENDING)
                this.settings.sorting.dir = SortOrder.DESCENDING;
            else this.settings.sorting.dir = SortOrder.ASCENDING;
        } else {
            this.settings.sorting.column = key;

            if (this.settings.columns.definitions[key].flags & ColumnFlag.DESCENDING_DEFAULT)
                this.settings.sorting.dir = SortOrder.DESCENDING;
            else this.settings.sorting.dir = SortOrder.ASCENDING;
        }

        this.saveSettings();
        this.clearRowSelections();
        this.updateTable();
        this.updateUI();

        return;
    }

    // Header cell dragging has ended, update the table
    destroy(document.querySelector("#stDragHeader"));
    destroy(document.querySelector("#stDropMarker"));

    this.headerDrag.active = false;

    if (this.headerDrag.cellPositions === null ||
        this.headerDrag.startIndex === null ||
        this.headerDrag.endIndex === null ||
        this.headerDrag.startIndex === this.headerDrag.endIndex) {
        // Why did we even get here?
        return;
    }

    // Reorder the columns array
    this.settings.columns.current.
        splice(this.headerDrag.endIndex, 0,
               this.settings.columns.current.splice(this.headerDrag.startIndex, 1)[0]);

    // Reorder the table row columns. Perform an in-place swap of the two table columns,
    // it's significantly faster than regenerating the whole table.
    const t0 = performance.now();

    const skip = (this.settings.flags & TableFlag.ENABLE_SELECTION) ? 1 : 0;

    const from = this.headerDrag.startIndex + skip,     // skip the checkbox column
          to = this.headerDrag.endIndex + skip;

    let rows = this.container.querySelector("table.stTable").rows,
        n = rows.length,
        row, cell;

    if (this.data.current.length == 0) {
        // The table is empty, so only reorder the header columns
        n = 1;
    }

    while (n--) {
        row = rows[n];
        cell = row.removeChild(row.cells[from]);
        row.insertBefore(cell, row.cells[to]);
    }

    const t1 = performance.now();
    console.log(`Table column swap: ${t1 - t0} ms`);

    this.saveSettings();
}

// Track mouse movement. If the mouse moves "enough", initiate a header cell drag.
onHeaderMouseMove(e)
{
    e.preventDefault();

    if (this.headerDrag.active) {
        this.updateHeaderDrag(e);
        return;
    }

    if (!this.headerDrag.active && e.target != this.headerDrag.element) {
        // The mouse veered away from the tracked element before enough
        // distance had been accumulated to properly trigger a drag
        let table = this.container.querySelector("table.stTable");

        document.removeEventListener("mouseup", this.onHeaderMouseUp);
        document.removeEventListener("mousemove", this.onHeaderMouseMove);

        table.classList.remove("no-text-select", "no-pointer-events");
        document.body.classList.remove("cursor-grabbing");

        this.headerDrag.element = null;
        return;
    }

    // Measure how far the mouse has been moved from the tracking start location.
    // Assume 10 pixels is "far enough".
    const dx = this.headerDrag.startingMousePos.x - e.clientX,
          dy = this.headerDrag.startingMousePos.y - e.clientY;

    if (Math.sqrt(dx * dx + dy * dy) < 10.0)
        return;

    // Make a list of header cell positions, so we'll know where to draw the drop markers
    const xOff = window.scrollX,
          yOff = window.scrollY;

    this.headerDrag.startIndex = null;
    this.headerDrag.endIndex = null;
    this.headerDrag.cellPositions = [];

    let headers = e.target.parentNode,
        start = 0,
        count = headers.childNodes.length;

    if (this.settings.flags & TableFlag.ENABLE_SELECTION)   // skip the checkbox column
        start++;

    if (this.settings.actionsCallback !== null)             // skip the "Actions" column
        count--;

    for (let i = start; i < count; i++) {
        let n = headers.childNodes[i];

        if (n == e.target) {
            // This is the cell we're dragging
            this.headerDrag.startIndex = i - start;
        }

        const r = n.getBoundingClientRect();

        this.headerDrag.cellPositions.push({
            x: r.x + xOff,
            y: r.y + yOff,
            w: r.width,
            h: r.height,
        });
    }

    if (this.headerDrag.cellPositions.length == 0) {
        console.error("No table header cells found!");
        this.headerDrag.cellPositions = null;
        return;
    }

    // Construct a floating "drag element" that follows the mouse
    const location = e.target.getBoundingClientRect(),
          dragX = Math.round(location.left),
          dragY = Math.round(location.top);

    this.headerDrag.offset = { x: e.clientX - dragX, y: e.clientY - dragY };

    let drag = create("div", { id: "stDragHeader", cls: "stDragHeader" });

    drag.style.left = `${dragX + window.scrollX}px`;
    drag.style.top = `${dragY + window.scrollY}px`;
    drag.style.width = `${location.width}px`;
    drag.style.height = `${location.height}px`;

    // Copy the title text, without the sorting arrow
    drag.innerHTML = `<span>${this.headerDrag.canSort ? e.target.firstChild.firstChild.innerText : e.target.innerText}</span>`;

    // Build the drop marker. It shows the position where the header will be placed when
    // the mouse button is released.
    let drop = create("div", { id: "stDropMarker", cls: "stDropMarker" });

    drop.style.height = `${location.height + 10}px`;

    document.body.appendChild(drag);
    document.body.appendChild(drop);

    // Start dragging the header cell
    let table = this.container.querySelector("table.stTable");

    table.classList.add("no-text-select", "no-pointer-events");
    document.body.classList.add("cursor-grabbing");

    this.headerDrag.active = true;
    this.updateHeaderDrag(e);
}

updateHeaderDrag(e)
{
    if (!this.headerDrag.active || this.headerDrag.cellPositions === null)
        return;

    const mx = e.clientX + window.scrollX,
          my = e.clientY + window.scrollY,
          mxOff = mx - this.headerDrag.offset.x;

    // Find the column under the current position
    this.headerDrag.endIndex = null;

    if (mx < this.headerDrag.cellPositions[0].x)
        this.headerDrag.endIndex = 0;
    else {
        for (let i = 0; i < this.headerDrag.cellPositions.length; i++)
            if (this.headerDrag.cellPositions[i].x <= mx)
                this.headerDrag.endIndex = i;
    }

    if (this.headerDrag.endIndex === null) {
        console.error(`Failed to find the column under the mouse (mouse X=${mx})`);
        return;
    }

    // Position the drop marker
    const slot = this.headerDrag.cellPositions[this.headerDrag.endIndex];

    let drop = document.querySelector("#stDropMarker");

    if (drop) {
        drop.style.left = `${slot.x - 2}px`;
        drop.style.top = `${slot.y - 5}px`;
    }

    // Position the dragged element. Clamp it against the window edges to prevent
    // unnecessary scrollbars from appearing.
    const windowW = document.body.scrollWidth,      // not the best, but nothing else...
          windowH = document.body.scrollHeight,     // ...works even remotely nicely here
          elementW = this.headerDrag.cellPositions[this.headerDrag.startIndex].w,
          elementH = this.headerDrag.cellPositions[this.headerDrag.startIndex].h;

    const dx = Math.max(0, Math.min(mx - this.headerDrag.offset.x, windowW - elementW)),
          dy = Math.max(0, Math.min(my - this.headerDrag.offset.y, windowH - elementH));

    let drag = document.querySelector("#stDragHeader");

    if (drag) {
        drag.style.left = `${dx}px`;
        drag.style.top = `${dy}px`;
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PROCESSING AND TABLE BUILDING

clearRowSelections()
{
    this.data.selectedItems.clear();
    this.data.successItems.clear();
    this.data.failedItems.clear();
}

beginTableUpdate()
{
    this.clearRowSelections();
    this.setStatus(`<div>${_tr('status.updating')}</div><img src="/images/spinner.gif" class="margin-left-5px">`);
    this.updating = true;
    this.enableUI(false);
    this.enableTable(false);
}

// Loads the statically provided table data
loadStaticData(data)
{
    this.beginTableUpdate();
}

// Retrieve data from the server and process it
fetchDataAndUpdate()
{
    this.beginTableUpdate();

    const startTime = performance.now();

    let networkError = null;

    fetch(this.settings.dynamicData)
        .then(response => {
            if (response.status != 200) {
                networkError = response.status;
                throw new Error(response);
            }

            if (!response.ok) {
                this.setError(_tr('network_error') + response.statusText);
                throw new Error(response);
            }

            return response;
        })
        .then(response => response.text())      // parse the JSON elsewhere, for better error handling
        .then(data => {
            this.enableTable(true);

            if (this.parseServerResponse(data, startTime))
                this.updateTable();
        })
        .catch(error => {
            if (networkError === null)
                this.setError(error);
            else this.setError(_tr('network_error') + networkError);

            this.updating = false;

            console.log(error);

            this.enableTable(true);
            this.enableUI(true);
            this.updateUI();
        });
}

// Takes the plain text returned by the server and, if possible, turns it into JSON
// and transforms it into usable data. Does not rebuild the table.
parseServerResponse(textData, startTime)
{
    const t0 = performance.now();

    console.log("parseServerResponse(): begin");
    console.log(`Network request: ${t0 - startTime} ms`);

    let raw = null;

    // try...catch block won't work as expected inside fetch(), so handle it here
    try {
        raw = JSON.parse(textData);
    } catch (e) {
        // The server responded with something that isn't JSON
        this.enableUI(true);
        this.setError(e);
        console.log(e);

        return false;
    }

    this.resetError();

    // Transform the received data. This is done here (and not in updateTable()) because it
    // only needs to be done once, but sorting and filtering can be done multiple times
    // on the transformed data.
    const t1 = performance.now();

    this.data.transformed = transformRawData(
        this.settings.columns.definitions,
        this.settings.userTransforms,
        raw
    );

    const t2 = performance.now();

    console.log(`JSON parsing: ${t1 - t0} ms`);
    console.log(`Data transformation: ${t2 - t1} ms`);
    console.log("parseServerResponse(): done");

    return true;
}

// Takes the currently cached transformed data, filters, sorts and displays it
updateTable()
{
    console.log("updateTable(): table update begins");

    this.enableUI(false);
    this.updating = true;
    this.doneAtLeastOneOperation = false;

    const t0 = performance.now();

    // Filter
    let filtered = [];

    if (this.settings.flags & TableFlag.ENABLE_FILTERING &&
        this.settings.filters.enabled &&
        this.settings.filters.program) {

        filtered = filterData(this.settings.columns.definitions,
                              this.data.transformed,
                              this.settings.filters.program,
                              this.settings.filters.reverse);
    } else filtered = [...this.data.transformed];

    const t1 = performance.now();

    // Sort
    const t2 = performance.now();
    this.data.current = sortData(this.settings.columns.definitions, this.settings.sorting,
                                 this.collator, filtered);
    const t3 = performance.now();

    console.log(`Data filtering: ${t1 - t0} ms`);
    console.log(`Data sorting: ${t3 - t2} ms`);

    this.calculatePagination();
    this.updatePaginationPageSelector();

    // Rebuild the table
    this.buildTable();

    this.updating = false;
    this.enableUI(true);
    this.updateUI();

    console.log("updateTable(): table update complete");
}

// Enables or disables the table itself, ie. makes everything in it not clickable. This is done
// when a mass operation starts, to prevent the user from modifying the table in any way, or
// clicking any buttons in it. You don't want to disturb the table during mass operations...
enableTable(isEnabled)
{
    let wrapper = this.container.querySelector("div.stTableWrapper");

    if (!wrapper || !wrapper.firstChild)
        return;

    if (isEnabled == true) {
        wrapper.classList.remove("no-text-selection", "cursor-wait");
        wrapper.firstChild.classList.remove("no-pointer-events");
    } else {
        wrapper.classList.add("no-text-selection", "cursor-wait");
        wrapper.firstChild.classList.add("no-pointer-events");
    }
}

onRowOpen(e)
{
    if (e.button != 1)    // middle button
        return;

    if (e.target.tagName != "TD")
        return;

    if (e.target.classList.contains("checkbox"))
        return;

    e.preventDefault();

    const index = e.target.parentNode.dataset.index;

    const url = this.settings.openCallback(this.data.current[index]);

    if (url === null || url === undefined)
        return;

    window.open(url, "_blank");
}

// Rebuild the table contents and place it in the output container
buildTable()
{
    const haveActions = !!this.settings.actionsCallback,
          canSelect = this.settings.flags & TableFlag.ENABLE_SELECTION,
          canOpen = !!this.settings.openCallback,
          currentColumn = this.settings.sorting.column;

    // Unicode arrow characters and empirically determined padding values (their widths
    // vary slightly). These won't work unless the custom puavo-icons font is applied.
    const arrows = {
        unsorted: { asc: "\uf0dc",                 padding: 10 },
        string:   { asc: "\uf15d", desc: "\uf15e", padding: 5 },
        numeric:  { asc: "\uf162", desc: "\uf163", padding: 6 },
    };

    let customCSSColumns = new Map();

    const t0 = performance.now();

    // ----------------------------------------------------------------------------------------------
    // Construct the table in HTML

    let html = "";

    // First the header row
    html += "<thead>";

    if (canSelect)
        html += `<th class="width-0"><span class="headerCheckbox"></span></th>`;

    for (const [index, key] of this.settings.columns.current.entries()) {
        const def = this.settings.columns.definitions[key];

        let classes = [],
            data = [["index", index], ["key", key]];

        if (def.flags & ColumnFlag.NOT_SORTABLE)
            classes.push("cursor-default");
        else {
            classes.push("cursor-pointer");
            classes.push("sortable");
        }

        if (key == currentColumn)
            classes.push("sorted");

        data.push(["sortable", (def.flags & ColumnFlag.NOT_SORTABLE) ? 0 : 1]);

        html += `<th `;
        html += `title="${key}" `;
        html += data.map(d => `data-${d[0]}="${d[1]}"`).join(" ");
        html += ` class="${classes.join(' ')}">`;

        // Figure out the cell contents (title + sort direction arrow)
        const isNumeric = (def.type != ColumnType.STRING);

        if (def.flags & ColumnFlag.NOT_SORTABLE)
            html += `${this.settings.columns.titles[key]}`;
        else {
            let symbol, padding;

            if (key == currentColumn) {
                // Currently sorted by this column
                const type = isNumeric ? "numeric" : "string",
                      dir = (this.settings.sorting.dir == SortOrder.ASCENDING) ? "asc" : "desc";

                symbol = arrows[type][dir];
                padding = arrows[type].padding;
            } else {
                symbol = arrows.unsorted.asc;
                padding = arrows.unsorted.padding;
            }

            // Do not put newlines in this HTML! Header drag cell construction will fail otherwise!
            html += `<div><span>${this.settings.columns.titles[key]}</span>` +
                    `<span class="arrow" style="padding-left: ${padding}px">${symbol}</span></div>`;
        }

        html += "</th>";

        if (def.flags & ColumnFlag.CUSTOM_CSS)
            customCSSColumns.set(key, def.cssClass);
    }

    // The actions column is always the last. It can't be sorted nor dragged.
    if (haveActions)
        html += `<th>${_tr('column_actions')}</th>`;

    html += "</tr></thead>";

    // Then the data rows
    html += "<tbody>";

    if (this.data.current.length == 0) {
        let numColumns = this.settings.columns.current.length;

        // Include the checkbox and actions columns, if present
        if (canSelect)
            numColumns++;

        if (haveActions)
            numColumns++;

        html += `<tr><td colspan="${numColumns}">(${_tr('empty_table')})</td></tr>`;
    } else {
        // Calculate start and end indexes
        let start, end;

        if (this.settings.flags & TableFlag.ENABLE_PAGINATION) {
            if (this.settings.paging.rowsPerPage == -1) {
                start = 0;
                end = this.data.current.length;
            } else {
                start = this.paging.currentPage * this.settings.paging.rowsPerPage;
                end = Math.min((this.paging.currentPage + 1) * this.settings.paging.rowsPerPage, this.data.current.length);
            }

            console.log(`currentPage=${this.paging.currentPage} start=${start} end=${end}`);
        } else {
            start = 0;
            end = this.data.current.length;
        }

        // These must always be updated, even when pagination is disabled
        this.paging.firstRowIndex = start;
        this.paging.lastRowIndex = end;

        for (let index = start; index < end; index++) {
            const row = this.data.current[index];
            const rowID = row.id[INDEX_DISPLAYABLE];
            let rowClasses = [];

            if (this.data.successItems.has(rowID))
                rowClasses.push("success");

            if (this.data.failedItems.has(rowID))
                rowClasses.push("fail");

            html += `<tr data-index="${index}" class=${rowClasses.join(" ")}>`;

            // The checkbox
            if (canSelect) {
                html += `<td class="minimize-width cursor-pointer checkbox">`;
                html += this.data.selectedItems.has(row.id[INDEX_DISPLAYABLE]) ? `<span class="checked">` : `<span>`;
                html += `</span></td>`;
            }

            // Data columns
            for (const column of this.settings.columns.current) {
                let classes = [];

                if (column == currentColumn)
                    classes.push("sorted");

                if (customCSSColumns.has(column))
                    classes.push(customCSSColumns.get(column));

                if (classes.length > 0)
                    html += `<td class=\"${classes.join(' ')}\">`;
                else html += "<td>";

                if (row[column][INDEX_DISPLAYABLE] !== null)
                    html += row[column][INDEX_DISPLAYABLE];

                html += "</td>";
            }

            // The actions column
            if (haveActions)
                html += "<td>" + this.settings.actionsCallback(row) + "</td>";

            html += "</tr>";
        }
    }

    html += "</tbody>";

    const t1 = performance.now();

    // ----------------------------------------------------------------------------------------------
    // Turn the HTML to an in-memory table

    let fragment = new DocumentFragment();

    fragment.appendChild(create("table", { id: this.id, cls: "stTable", html: html }));

    const t2 = performance.now();

    // ----------------------------------------------------------------------------------------------
    // Setup event handling

    let thead = fragment.querySelector("thead"),
        headings = thead.firstChild.childNodes;

    // Header cell click handlers
    const start = canSelect ? 1 : 0,                                    // skip the checkbox column
          count = haveActions ? headings.length - 1 : headings.length;  // skip the actions column

    for (let i = start; i < count; i++)
        headings[i].addEventListener("mousedown", event => this.onHeaderMouseDown(event));

    if (this.data.current.length > 0) {
        for (let row of fragment.querySelectorAll("tbody > tr")) {
            // Full row click open handlers
            if (canOpen)
                row.addEventListener("mouseup", event => this.onRowOpen(event));

            // Row checkbox handlers
            if (canSelect)
                row.childNodes[0].addEventListener("mousedown", event => this.onRowCheckboxClick(event));
        }
    }

    const t3 = performance.now();

    // ----------------------------------------------------------------------------------------------
    // Replace the existing table. This is actually the slowest part as it causes significant
    // content reflowing, especially if the table has thousands of rows.

    this.ui.previousRow = null;

    let table = this.container.querySelector("div.stTableWrapper");

    if (table.firstChild)
        table.replaceChild(fragment, table.firstChild);
    else table.appendChild(fragment);

    const t4 = performance.now();

    console.log(`[TABLE] HTML generation: ${t1 - t0} ms`);
    console.log(`[TABLE] In-memory table construction: ${t2 - t1} ms`);
    console.log(`[TABLE] Callback setup: ${t3 - t2} ms`);
    console.log(`[TABLE] DOM replace: ${t4 - t3} ms`);
    console.log(`[TABLE] Total: ${t4 - t0} ms`);
}

};
