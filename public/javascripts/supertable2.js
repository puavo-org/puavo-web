"use strict;"

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// UTILITY

// A shorter to type alias
function _tr(id) { return I18n.translate(id); }

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

function splitArray(v)
{
    return v.map(i => escapeHTML(i)).join("<br>");
};

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
        // I'm not sure if this can throw errors
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

const dateTimeParserString =
    `^` +
    `(?<year>\\d{4})-?` +       // four-digit year followed by an optional "-",
    `(?<month>\\d{2})?-?` +     // month plus an optional "-",
    `(?<day>\\d{2})? ?` +       // day plus an optional whitespace,
    `(?<hour>\\d{2})?:?` +      // hours plus an optional colon,
    `(?<minute>\\d{2})?:?` +    // minutes plus an optional colon,
    `(?<second>\\d{2})?`;       // and finally seconds

const dateTimeParserRegexp = new RegExp(dateTimeParserString);

// Converts a "YYYY-MM-DD HH:MM:SS" into a Date object, but the catch is that you can omit
// the parts you don't need, ie. the more you specify, the more accurate it gets. Giving
// "2021" to this function returns 2021-01-01 00:00:00, "2021-05" returns 2021-05-01 00:00:00,
// "2021-05-27 19:37" returns 2021-05-27 19:37:00 and so on. The other format this function
// understands are relative times: if the input value is an integer, then it is added to the
// CURRENT time and returned. Negative values point to the past, positive point to the future.
function parseAbsoluteOrRelativeDate(s)
{
    if (typeof(s) == "string") {
        // Absolute
        const match = dateTimeParserRegexp.exec(s.trim());

        if (match === null)
            return null;

        // This should cut off after the first missing element (ie. if you omit the day,
        // then hours, minutes and seconds should not be set), but the regexp won't match
        // it then, so no harm done.
        const year = parseInt(match.groups.year, 10),
              month = parseInt(match.groups.month || "1", 10) - 1,
              day = parseInt(match.groups.day || "1", 10),
              hour = parseInt(match.groups.hour || "0", 10),
              minute = parseInt(match.groups.minute || "0", 10),
              second = parseInt(match.groups.second || "0", 10);

        //console.log(match.groups);
        //console.log(year, month, day, hour, minute, second);

        let d = new Date();

        d.setFullYear(year);
        d.setMonth(month);
        d.setDate(day);
        d.setHours(hour);
        d.setMinutes(minute);
        d.setSeconds(second);
        d.setMilliseconds(0);       // the database values have only 1-second granularity

        return d;
    } else if (typeof(s) == "number") {
        // Relative
        let d = new Date();

        d.setSeconds(d.getSeconds() + s);
        d.setMilliseconds(0);       // the database values have only 1-second granularity

        return d;
    }

    return null;
}

function doesItLookLikeADate(s)
{
    return parseAbsoluteOrRelativeDate(s) !== null;
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// SUPERTABLE UTILITY

// NOTE: Do not use zeroes when defining new values! They confuse JavaScript's "types"
// in comparisons.

const ColumnType = {
    BOOL: 1,
    INTEGER: 2,
    FLOAT: 3,
    UNIXTIME: 4,
    STRING: 5,
};

// Default value for each of the above column types. If new types are added, or their
// order is changed, this array must be updated. Keep the first entry as null, it is
// never used for anything.
const DEFAULT_VALUE = [
    null,       // (not used)
    false,      // BOOL
    0,          // INTEGER
    0.0,        // FLOAT
    0,          // UNIXTIME
    ""          // STRING
];

const ColumnFlag = {
    SORTABLE: 0x01,         // this column can be sorted
    ARRAY: 0x02,            // the column values are actually arrays of zero or more values
    USER_TRANSFORM: 0x04,   // call a user-defined callback function to get the actual value
};

const SortOrder = {
    NONE: "none",
    ASCENDING: "asc",
    DESCENDING: "desc"
};

const FilterOperator = {
    EQU: "equ",     // ==
    NEQ: "neq",     // !=
    LT: "lt",       // <
    LTE: "lte",     // <=
    GT: "gt",       // >
    GTE: "gte",     // >=
};

// "availableFor" defines which column types can be compared with this operator
const OPERATOR_DEFINITIONS = [
    {
        title: "=",
        operator: FilterOperator.EQU,
        availableFor: new Set([ColumnType.BOOL, ColumnType.INTEGER, ColumnType.FLOAT,
                               ColumnType.UNIXTIME, ColumnType.STRING]),
    },

    {
        title: "≠",
        operator: FilterOperator.NEQ,
        availableFor: new Set([ColumnType.BOOL, ColumnType.INTEGER, ColumnType.FLOAT,
                               ColumnType.UNIXTIME, ColumnType.STRING]),
    },

    {
        title: "<",
        operator: FilterOperator.LT,
        availableFor: new Set([ColumnType.INTEGER, ColumnType.FLOAT, ColumnType.UNIXTIME]),
    },

    {
        title: "≤",
        operator: FilterOperator.LTE,
        availableFor: new Set([ColumnType.INTEGER, ColumnType.FLOAT, ColumnType.UNIXTIME]),
    },

    {
        title: ">",
        operator: FilterOperator.GT,
        availableFor: new Set([ColumnType.INTEGER, ColumnType.FLOAT, ColumnType.UNIXTIME]),
    },

    {
        title: "≥",
        operator: FilterOperator.GTE,
        availableFor: new Set([ColumnType.INTEGER, ColumnType.FLOAT, ColumnType.UNIXTIME]),
    },
];

const RowSelectOp = {
    SELECT_ALL: 1,
    DESELECT_ALL: 2,
    DESELECT_SUCCESSFULL: 3,
};

const TableFlag = {
    ALLOW_SELECTION: 0x01,          // rows can be selected and mass processed
    ALLOW_FILTERING: 0x02,          // enable customizable filtering
    ALLOW_COLUMN_CHANGES: 0x04,     // allow the visible columns to be selected and reordered
};

// JavaScript has a built-in Set type and it has... no common set operators defined for it.
// Nope. Nothing. Nada. Zilch. Zero. Do it yourself. Sigh.
function setUnion(a, b)
{
    let c = new Set(a);

    for (const i of b)
        c.add(i);

    return c;
}

// Apply some transformations to the raw data received from the server. For example,
// convert timestamps into user's local time, turn booleans into checkmarks, and so on.
// Filtering and sorting work better when there are no NULLs in the data and all columns
// are present. The data we generate is purely presentational, intended for humans.
// These transformed values are never fed back into the database.
function transformRawData(columnDefinitions, visibleColumns, userTransforms, rawData)
{
    function transformItem(raw, key)
    {
        const coldef = columnDefinitions[key];
        const defVal = DEFAULT_VALUE[coldef.type];

        // Figure out these two variables for this column. The first is what we'll
        // put in the HTML table cell; it is assumed to be valid HTML. The next
        // is a value that is used for sorting and filtering this row.
        let displayable = null,
            sortable = null;

        if (!(key in raw)) {
            // Null values are removed from the server's response to minimize the amount
            // of transferred data. Assume this column name is valid, but this row just
            // has no value for it in the database
            displayable = "";
            sortable = defVal;
        } else if (coldef.flags & ColumnFlag.USER_TRANSFORM) {
            // Use the user-defined transformation function to convert this column's
            // content into displayable and sortable form.
            if (key in userTransforms)
                [displayable, sortable] = userTransforms[key](raw);
            else {
                displayable = `<span class="missingData">Missing user transform function!</span>`;
                sortable = defVal;
            }
        } else if (raw[key] === null) {
            // This entry exists and the server returned it, but it is NULL. Store
            // the default value, so sorting works.
            displayable = defVal;
            sortable = defVal;
        } else {
            // Apply a built-in transformation to the displayed data
            let value = raw[key];

            switch (coldef.type) {
                case ColumnType.BOOL:
                    if (value === true)
                        value = "✔";
                    else value = "";

                    break;

                case ColumnType.UNIXTIME: {
                    // Intl.DateTimeFormat could be used here, but it would not be very
                    // useful, because we want the output format to be always the same
                    // (24-hour YYYY-MM-DD HH:MM:SS)
                    const [valid, s] = convertTimestamp(value);

                    value = s;
                    break;
                }

                case ColumnType.FLOAT:
                    if (value === null || value == undefined)
                        value = 0.0;

                    break;

                default:
                    break;
            }

            if (coldef.flags & ColumnFlag.ARRAY) {
                displayable = value.map(i => escapeHTML(i)).join("<br>");
                sortable = value.join();
            } else {
                displayable = escapeHTML(value);
                sortable = raw[key];
            }
        }

        return [sortable, displayable];
    };

    let out = [];

    // These are the IDs of the currently visible columns. They *MUST* be included
    // in the transformed data, even if their values are empty/defaults.
    const required = new Set(visibleColumns);

    for (const raw of rawData) {
        let cleaned = {};

        // The link is a special field. It's not a separate column, but many user
        // transform functions require it, so specifically include it.
        // There are some other "required" fields, but they're always included in
        // the server's response so they don't need special handling. (I hope.)
        cleaned.link = [raw.link];

        // Process everything the server sends
        const actualKeys = setUnion(required, new Set(Object.keys(raw)))

        for (const key of actualKeys) {
            if (!(key in columnDefinitions))
                continue;

            const [sortable, displayable] = transformItem(raw, key);

            if (sortable === displayable)
                cleaned[key] = [sortable];
            else cleaned[key] = [sortable, displayable];
        }

        out.push(cleaned);
    }

    return out;
}

// Applies zero or more filters to the data
function filterData(columnDefinitions, data, filters, reverse)
{
    let missingColumns = false;

    let filtered = data.filter(function(item) {
        // Each row is visible by default
        let rowMatched = true;

        // Process each filter
        for (const filter of filters) {
            if (!(filter.column in item)) {
                // This column does not exist in the data
                missingColumns = true;
                continue;
            }

            // Timestamps require some extra wrangling
            const type = columnDefinitions[filter.column].type;

            let value = item[filter.column][0];
            let filterMatch = false;

            switch (filter.operator) {
                case FilterOperator.EQU:
                    if (filter.regexp) {
                        filterMatch = filter.value[0].test(value);
                        //console.log(`EQU: '${value}' < '${filter.value[0]}': ${filterMatch}`);
                    } else if (type == ColumnType.INTEGER || type == ColumnType.FLOAT) {
                        for (const v of filter.value) {
                            if (value == v) {
                                filterMatch = true;
                                break;
                            }
                        }
                    } else {
                        // Just one value
                        filterMatch = (value == filter.value[0]);
                    }

                    break;

                case FilterOperator.NEQ:
                    if (filter.regexp)
                        filterMatch = !filter.value[0].test(value);
                    else if (type == ColumnType.INTEGER || type == ColumnType.FLOAT) {
                        filterMatch = true;     // assume it matches

                        for (const v of filter.value) {
                            if (value == v) {
                                filterMatch = false;
                                break;
                            }
                        }
                    } else {
                        // Just one value
                        filterMatch = (value != filter.value[0]);
                    }

                    break;

                case FilterOperator.LT:
                    if (type == ColumnType.UNIXTIME && value === 0)
                        value = 999999999999;           // never matches

                    filterMatch = value < filter.value[0];
                    //console.log(`LT: '${value}' < '${filter.value}': ${filterMatch}`);
                    break;

                case FilterOperator.LTE:
                    if (type == ColumnType.UNIXTIME && value === 0)
                        value = 999999999999;           // never matches

                    filterMatch = value <= filter.value[0];
                    //console.log(`LT: '${value}' <= '${filter.value}': ${filterMatch}`);
                    break;

                case FilterOperator.GT:
                    if (type == ColumnType.UNIXTIME && value === 0)
                        value = -999999999999;          // never matches

                    filterMatch = value > filter.value[0];
                    //console.log(`LT: '${value}' > '${filter.value}': ${filterMatch}`);
                    break;

                case FilterOperator.GTE:
                    if (type == ColumnType.UNIXTIME && value === 0)
                        value = -999999999999;          // never matches

                    filterMatch = value >= filter.value[0];
                    //console.log(`GTE: '${value}' >= '${filter.value}': ${filterMatch}`);
                    break;

                default:
                    break;
            }

            if (filterMatch == reverse) {
                // The first miss makes the row invisible, no need to keep going
                rowMatched = false;
                break;
            }
        }

        return rowMatched;
    });

    if (missingColumns)
        console.error("The filter targets one or more columns that aren't in the data set");

    return filtered;
}

// Sorts the data by the specified column and order
function sortData(columnDefinitions, sortBy, collator, data)
{
    // Don't touch the original data
    let out = [...data];

    const direction = (sortBy.dir == SortOrder.ASCENDING) ? 1 : -1;
    const key = columnDefinitions[sortBy.column].key;

    //console.log(`Sorting data by key "${sortBy.column}"`);

    switch (columnDefinitions[sortBy.column].type) {
        case ColumnType.BOOL:
        case ColumnType.INTEGER:
        case ColumnType.FLOAT:
        case ColumnType.UNIXTIME:
        case ColumnType.BOOL:                   // not the best choice
            out.sort((a, b) => {
                const n1 = a[key][0],
                      n2 = b[key][0];

                if (n1 < n2)
                    return -1 * direction;
                else if (n1 > n2)
                    return 1 * direction;

                // try to stabilize the sort
                return a.id - b.id;
            });

            break;

        case ColumnType.STRING:
        default:
            out.sort((a, b) => {
                const r = collator.compare(a[key][0], b[key][0]) * direction;

                if (r === 0) {
                    // try to stabilize the sort
                    return a.id - b.id;
                }

                return r;
            });

            break;
    }

    return out;
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// MASS OPERATIONS

// Sends a single AJAX POST message
function doPOST(url, itemData)
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
    // because it's the return value and we only care about it
    return new Promise(function(resolve, reject) {
        resolve({ success: success, message: message });
    });
}

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

const MassOperationFlags = {
    HAVE_SETTINGS: 0x01,        // this operation has adjustable settings
    SINGLESHOT: 0x02,           // this operation processes all items in one call, not one-by-one
};

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// THE SUPERTABLE

// Creates a new HTML element and sets is attributes
function elem(tag, params)
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

class SuperTable {

constructor(container, settings)
{
    // Unique prefix appended to all relevant items, so you can have multiple
    // SuperTables on a single page and they won't interfere with each other.
    this.id = settings.id;

    // Everything happens inside this container DIV
    this.container = container;

    if (this.container === null || this.container === undefined) {
        console.error("The container DIV element is null or undefined");

        window.alert("The table container DIV is null or undefined. The table cannot be displayed.\n\nPlease contact Opinsys support.");
        return;
    }

    if (settings.columnDefinitions === undefined ||
        settings.columnDefinitions === null ||
        typeof(settings.columnDefinitions) != "object" ||
        Object.keys(settings.columnDefinitions).length == 0) {

        console.error("The settings.columnDefinitions parameter missing/empty, or it isn't an associative array");

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

        // We don't know yet if the default sorting column is actually *visible*.
        // That cannot be validated until later.

        return;
    }

    if (settings.defaultSorting.dir != SortOrder.ASCENDING && settings.defaultSorting.dir != SortOrder.DESCENDING) {
        this.container.innerHTML =
            `<p class="error">Invalid/unknown default sorting direction. The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;
    }

//    localStorage.removeItem(`table-${this.id}-settings`);

    // Initial settings
    this.settings = {
        flags: settings.flags || 0,
        locale: settings.locale || "en-US",
        csvPrefix: settings.csvPrefix || "unknown",

        columnDefinitions: settings.columnDefinitions,
        columnTitles: settings.columnTitles,
        columnOrder: settings.columnOrder || [],
        userTransforms: settings.userTransforms || null,
        massOperations: settings.massOperations || [],

        defaultColumns: [...settings.defaultColumns],
        defaultSorting: {...settings.defaultSorting},

        columns: [...settings.defaultColumns],  // will be overridden if stored settings exist
        sorting: {...settings.defaultSorting},  // ditto
        filters: [],                            // will be dealt with later
        effectiveFilters: [],                   // ditto
        defaultFilterColumn: settings.defaultFilterColumn,
        filterPresets: settings.filterPresets || null,
        filtersEnabled: false,
        filtersReverse: false,

        actionsCallback: null,

        source: settings.source,

        currentTab: "tools",
    };

    if (settings.actions && typeof(settings.actions) == "function")
        this.settings.actionsCallback = settings.actions;

    // Load and merge stored settings from localStore, if they exist. If there are no
    // settings, save the current settings.
    if (!this.loadSettings())
        this.saveSettings();

    // The only remaining thing left to be validated is the current sorting column: is it
    // in the currently visible columns? If not, use the first available column. We could
    // try restoring it to the default column, but it might not be visible (if we loaded
    // only partial settings).
    let found = false;

    for (const c of this.settings.columns) {
        if (c == this.settings.sorting.column) {
            found = true;
            break;
        }
    }

    if (!found) {
        console.warn(`The initial sorting column "${this.settings.sorting.column}" isn't visible, ` +
                     `using the first available ("${this.settings.columns[0]}")`);
        this.settings.sorting.column = this.settings.columns[0];
    }

    // Used when sorting the table contents. The locale defines language-specific
    // sorting rules.
    this.collator = new Intl.Collator(
        settings.locale, {
            usage: "sort",
            sensitivity: "accent",
            ignorePunctuation: true,
            numeric: true,                  // I really like this one
        }
    );

    // Table/network data
    this.data = {
        errorCode: null,
        transformed: null,
        current: null,
        selectedItems: new Set(),
        successItems: new Set(),
        failedItems: new Set(),
    };

    // State
    this.updating = false;
    this.processing = false;
    this.doneAtLeastOneOperation = false;
    this.unsavedColumns = false;
    this.headerDragTargetElement = null;
    this.headerIsBeingDragged = false;
    this.headerTrackStartPos = null;
    this.headerTrackCanSort = false;
    this.headerDragStartIndex = null;
    this.headerDragEndIndex = null;
    this.headerCellPositions = [];
    this.onHeaderMouseDown = this.onHeaderMouseDown.bind(this);     // some weird JS scoping garbage
    this.onHeaderMouseUp = this.onHeaderMouseUp.bind(this);
    this.onHeaderMouseMove = this.onHeaderMouseMove.bind(this);

    // Direct handles to various user interface elements. You could use querySelector()
    // everywhere, but it's cleaner this way. There shouldn't be any memory leaks,
    // because the elements aren't repeatedly deleted and recreated.
    this.ui = {
        reload: null,
        csv: null,

        columns: {
            status: null,
            unsaved: null,
            list: null,
            save: null,
            reset: null,
            all: null,
            sort: null,
        },

        filter: {
            enabled: null,
            reverse: null,
            presets: null,
        },

        mass: {
            selector: null,
            proceed: null,
            progress: null,
            counter: null,
        },

        status: null,

        // Container for the table itself. Again, for easy updating. The DIV is never changed,
        // but its contents are.
        table: null,

        // The previously clicked table row. Can be null.
        previousRow: null,
    };

    // Handle to the class that implements the filter editor
    this.filterEditor = null;

    // Current mass operation data
    this.massOperation = {
        index: -1,          // index to the settings.massOperations[] array, -1 if nothing
        handler: null,      // the user-supplied handler class that actually does the mass operation
        singleShot: false,  // true if the operation processes all items at once
    };

    this.buildUI();

    // Setup filtering if enabled
    if (this.settings.flags & TableFlag.ALLOW_FILTERING) {
        this.filterEditor.setColumns(this.settings.columns);

        // Load stored filters from the localstore. If there's nothing there, use the
        // initially supplied filters.
        const initial = this.loadInitialFilters();

        this.filterEditor.loadFilters(initial ? initial : settings.initialFilters);
        this.filterEditor.buildFilterTable();

        if (initial)
            this.setFilters(initial, false);
        else this.setFilters(settings.initialFilters, true);
    }

    this.saveSettings();

    // Do the initial update
    this.enableUI(false);
    this.fetchDataAndUpdate();
}

loadSettings()
{
    const key = `table-${this.id}-settings`;

    let stored = localStorage.getItem(key);

    if (stored === null)
        return false;

    try {
        stored = JSON.parse(stored);
    } catch (e) {
        console.error("loadSettings(): could not load stored settings:");
        console.error(e);
        return false;
    }

    // Validate the initial tab
    const VALID_TAB = new Set(["tools", "columns", "filters", "mass"]);

    if (!VALID_TAB.has(stored.currentTab))
        stored.currentTab = "tools";

    if (stored.currentTab == "filters" && !(this.settings.flags & TableFlag.ALLOW_FILTERING))
        stored.currentTab = "tools";

    if (stored.currentTab == "mass" && !this.haveMassTools())
        stored.currentTab = "tools";

    this.settings.currentTab = stored.currentTab;

    if ("columns" in stored && Array.isArray(stored.columns)) {
        // Remove invalid and duplicate columns from the array. They could be columns that
        // once existed but have been deleted since. Or someone edited the saved settings
        // and put garbage in there. Or something else happened. Weed them out.
        let valid = [],
            seen = new Set();

        for (const c of stored.columns) {
            if (seen.has(c))
                continue;

            seen.add(c);

            if (c in this.settings.columnDefinitions)
                valid.push(c);
        }

        // There must always be at least one visible column
        if (valid.length > 0)
            this.settings.columns = valid;
    }

    if ("sorting" in stored) {
        // Restore these only if they're valid
        if (stored.sorting.column in this.settings.columnDefinitions)
            this.settings.sorting.column = stored.sorting.column;
        else console.warn(`The stored sorting column "${stored.sorting.column}" isn't valid, using default`);

        if (stored.sorting.dir == SortOrder.ASCENDING || stored.sorting.dir == SortOrder.DESCENDING)
            this.settings.sorting.dir = stored.sorting.dir;
    }

    // Restore the other settings
    if ("filtersEnabled" in stored && typeof(stored.filtersEnabled) == 'boolean')
        this.settings.filtersEnabled = stored.filtersEnabled;

    if ("filtersReverse" in stored && typeof(stored.filtersReverse) == 'boolean')
        this.settings.filtersReverse = stored.filtersReverse;

    return true;
}

saveSettings()
{
    const key = `table-${this.id}-settings`;

    const settings = {
        columns: this.settings.columns,
        sorting: this.settings.sorting,
        currentTab: this.settings.currentTab,
        filtersEnabled: this.settings.filtersEnabled,
        filtersReverse: this.settings.filtersReverse,
    }

    localStorage.setItem(key, JSON.stringify(settings));
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// USER INTERFACE

haveMassTools()
{
    return this.settings.flags & TableFlag.ALLOW_SELECTION &&
           Array.isArray(this.settings.massOperations) &&
           this.settings.massOperations.length > 0;
}

buildUI()
{
    // Builds the tab bar button and the tab container
    function buildTab(tableID, tabID, title, selected)
    {
        let tab = document.createElement("li"),
            cont = document.createElement("div");

        tab.id = `${tableID}-tabbar-${tabID}`;
        tab.dataset.id = tabID;

        if (selected)
            tab.classList.add("selected");
        else {
            tab.classList.add("unselected");
            tab.classList.add("disabled");
        }

        tab.innerText = title;

        cont.id = `${tableID}-tab-${tabID}`;
        cont.dataset.id = tabID;

        cont.classList.add("tab");

        if (!selected)
            cont.classList.add("hidden");

        return [tab, cont];
    }

    // The outer container for everything
    let frag = document.createDocumentFragment();

    // ---------------------------------------------------------------------------------------------
    // Create the tab bar

    let tabBar = elem("ul", {cls: "tabs"});
    frag.appendChild(tabBar);

    // ---------------------------------------------------------------------------------------------
    // Build the "tools" tab

    let [toolsTab, toolsCont] = buildTab(this.id, "tools", _tr('tabs.tools.title'),
                                         this.settings.currentTab == "tools");

    toolsCont.innerHTML =
        `<div class="flex flex-vcenter"><button id="btnReload">${_tr("tabs.tools.reload")}</button>` +
        `<button id="btnCSV">${_tr("tabs.tools.csv")}</button>` +
        `<input type="checkbox" id="${this.id}-csv-only-visible"><label for="${this.id}-csv-only-visible">${_tr("tabs.tools.csv_only_visible")}</label></div>`;

    this.ui.reload = toolsCont.querySelector(`button#btnReload`);
    this.ui.reload.disabled = true;
    this.ui.reload.addEventListener("click", () => this.fetchDataAndUpdate());

    this.ui.csv = toolsCont.querySelector(`button#btnCSV`);
    this.ui.csv.disabled = true;
    this.ui.csv.addEventListener("click", () => this.getCSV());

    tabBar.appendChild(toolsTab);
    frag.appendChild(toolsCont);

    // ---------------------------------------------------------------------------------------------
    // Build the columns tab

    if (this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES) {
        let [columnsTab, columnsCont] = buildTab(this.id, "columns", _tr('tabs.columns.title'),
                                                 this.settings.currentTab == "columns");

        let html = "";

        html += "<p>" + _tr('tabs.columns.help') + "</p>";

        const keys = Object.keys(this.settings.columnDefinitions);

        html +=
            `<br><p class="flex"><span class="columnStats"></span>` +
            `<span class="unsavedWarning hidden">&nbsp;${_tr('tabs.columns.unsaved_changes')}</span></p>` +
            `<table class="columnTable"><tr><td width="300px">` +
            `<div class="columnList">`;

        let currentColumns = new Set();

        for (const c of this.settings.columns)
            currentColumns.add(c);

        let columnNames = [];

        for (const name of keys)
            columnNames.push([name, this.settings.columnTitles[name]]);

        columnNames.sort((a, b) => { return a[1].localeCompare(b[1]) });

        for (const c of columnNames) {
            const def = this.settings.columnDefinitions[c[0]];

            let cls = ["column"];

            if (currentColumns.has(c[0]))
                cls.push("selected");

            cls.push("disabled");

            html += `<div data-column="${c[0]}" class="${cls.join(' ')}">`;

            if (currentColumns.has(c[0]))
                html += `<input type="checkbox" checked></input>`;
            else html += `<input type="checkbox"></input>`;

            html += `${c[1]}</div>`;
        }

        html += `</div>`;
        html += `</td><td style="vertical-align: top;">`;
        html += `<button id="save">${_tr('tabs.columns.save')}</button><br>`;
        html += `<button id="reset">${_tr('tabs.columns.defaults')}</button><br>`;
        html += `<button id="selectAll">${_tr('tabs.columns.all')}</button><br><br>`;
        html += `<button id="sort">${_tr('tabs.columns.sort')}</button>`;
        html += `</td></tr></table>`;

        columnsCont.innerHTML = html;

        for (let i of columnsCont.querySelectorAll(`.columnList .column`))
            i.addEventListener("click", (e) => this.toggleColumn(e.target));

        this.ui.columns.status = columnsCont.querySelector("p span.columnStats");
        this.ui.columns.unsaved = columnsCont.querySelector("p span.unsavedWarning");
        this.ui.columns.list = columnsCont.querySelector("div.columnList");
        this.ui.columns.save = columnsCont.querySelector(".columnTable button#save");
        this.ui.columns.reset = columnsCont.querySelector(".columnTable button#reset");
        this.ui.columns.all = columnsCont.querySelector(".columnTable button#selectAll");
        this.ui.columns.sort = columnsCont.querySelector(".columnTable button#sort");

        this.ui.columns.save.disabled = true;
        this.ui.columns.reset.disabled = true;
        this.ui.columns.all.disabled = true;
        this.ui.columns.sort.disabled = true;

        this.ui.columns.save.addEventListener("click", () => this.saveColumns());
        this.ui.columns.reset.addEventListener("click", () => this.resetColumns());
        this.ui.columns.all.addEventListener("click", () => this.allColumns());
        this.ui.columns.sort.addEventListener("click", () => this.resetColumnOrder());

        tabBar.appendChild(columnsTab);
        frag.appendChild(columnsCont);
    }

    // ---------------------------------------------------------------------------------------------
    // Build the filter editor tab

    if (this.settings.flags & TableFlag.ALLOW_FILTERING) {
        let [tab, container] =
            buildTab(this.id, "filters", _tr('tabs.filtering.title') + (this.settings.filtersEnabled ? " [ON]" : " [OFF]"),
            this.settings.currentTab == "filters");

        tabBar.appendChild(tab);

        container.classList.add("filters");

        let html = "";
        html += `<div class="flex flex-vcenter">`

        html += `<input type="checkbox" id="st-filters-enabled-${this.id}">` +
                `<label for="st-filters-enabled-${this.id}" class="margin-right-10">` +
                `${_tr('tabs.filtering.enabled')}</label>`;

        html += `<input type="checkbox" id="st-filters-reverse-${this.id}">` +
                `<label for="st-filters-reverse-${this.id}" class="margin-right-10">` +
                `${_tr('tabs.filtering.reverse')}</label>`;

        if (this.settings.filterPresets) {
            let t = [];

            for (let k of Object.keys(this.settings.filterPresets))
                t.push([this.settings.filterPresets[k].title.toLowerCase(), k]);

            t.sort((a, b) => { return a[0].localeCompare(b[0]) });

            html += `<label for="st-filters-presets-${this.id}" class="margin-right-10">` +
                    `${_tr('tabs.filtering.presets')}:</label>`;

            html += `<select id="st-filters-presets-${this.id}">`;

            html += `<option data-id="" hidden disabled selected value>${_tr('selected')}</option>`;

            for (const i of t)
                html += `<option data-id="${i[1]}">${this.settings.filterPresets[i[1]].title}</option>`;

            html += `</select>`;
        }

        html += `</div><div class="ui"></div>`;

        container.innerHTML = html;
        frag.appendChild(container);

        this.ui.filter.enabled = container.querySelector(`input#st-filters-enabled-${this.id}`);
        this.ui.filter.reverse = container.querySelector(`input#st-filters-reverse-${this.id}`);

        if (this.settings.filterPresets) {
            this.ui.filter.presets = container.querySelector(`select#st-filters-presets-${this.id}`);
            this.ui.filter.presets.addEventListener("change", (e) => this.loadFilterPreset(e));
        }

        this.ui.filter.enabled.addEventListener("click", () => this.toggleFiltersEnabled());
        this.ui.filter.reverse.addEventListener("click", () => this.toggleFiltersReverse());

        this.ui.filter.enabled.disabled = true;
        this.ui.filter.reverse.disabled = true;

        if (this.ui.filter.presets)
            this.ui.filter.presets.disabled = true;

        // Restore settings
        this.ui.filter.enabled.checked = this.settings.filtersEnabled;
        this.ui.filter.reverse.checked = this.settings.filtersReverse;

        this.filterEditor = new FilterEditor(this,
                                             container.querySelector("div.ui"),
                                             this.settings.columnDefinitions,
                                             this.settings.columnTitles,
                                             this.settings.defaultFilterColumn);
    }

    // Build the mass operations tab
    if (this.haveMassTools()) {
        let html = "";

        html += `<fieldset><legend>${_tr('tabs.mass.rows_title')}</legend><div class="mainButtons">`;
        html += `<button id="selectAll">${_tr('tabs.mass.select_all')}</button>`;
        html += `<button id="deselectAll">${_tr('tabs.mass.deselect_all')}</button>`;
        html += `<button id="deselectSuccessfull">${_tr('tabs.mass.deselect_successfull')}</button>`;
        html += `<button id="invertSelection">${_tr('tabs.mass.invert_selection')}</button>`;
        html += `</div></fieldset>`;

        html += `<fieldset><legend>${_tr('tabs.mass.operation_title')}</legend><div class="controls">`;
        html += `<select class="operation">`;

        html += `<option data-id="" hidden disabled selected value>${_tr('selected')}</option>`;

        for (const m of this.settings.massOperations)
            html += `<option data-id="${m.id}">${m.title}</option>`;

        html += "</select>";

        html += `<button>${_tr('tabs.mass.proceed')}</button>` +
                `<progress></progress>` +
                `<span class="counter""></span>`;

        html += `</div></fieldset>`;

        // This is where the child UI is placed in
        html += `<fieldset id="ui" class="hidden"><legend>${_tr('tabs.mass.settings_title')}</legend><div class="ui"></div></fieldset>`;

        let [tab, container] =
            buildTab(this.id, "mass", _tr('tabs.mass.title'), this.settings.currentTab == "mass");

        tabBar.appendChild(tab);

        container.classList.add("mass");

        container.innerHTML = html;

        container.querySelector("#selectAll")
            .addEventListener("click", () => this.selectRows(RowSelectOp.SELECT_ALL));
        container.querySelector("#deselectAll")
            .addEventListener("click", () => this.selectRows(RowSelectOp.DESELECT_ALL));
        container.querySelector("#deselectSuccessfull")
            .addEventListener("click", () => this.selectRows(RowSelectOp.DESELECT_SUCCESSFULL));
        container.querySelector("#invertSelection")
            .addEventListener("click", () => this.selectRows(RowSelectOp.INVERT));

        frag.appendChild(container);

        this.ui.mass.selector = container.querySelector("div.controls > select");
        this.ui.mass.proceed = container.querySelector("div.controls > button");
        this.ui.mass.progress = container.querySelector("div.controls > progress");
        this.ui.mass.counter = container.querySelector("div.controls > span.counter");

        this.ui.mass.selector.disabled = true;
        this.ui.mass.progress.classList.add("hidden");
        this.ui.mass.progress.setAttribute("max", "0");
        this.ui.mass.progress.setAttribute("value", "0");
        this.ui.mass.counter.classList.add("hidden");

        this.ui.mass.selector.addEventListener("change", () =>
            this.switchMassOperation(this.ui.mass.selector.selectedIndex - 1));

        this.ui.mass.proceed.addEventListener("click", () => this.doMassOperation());
    }

    this.ui.status = elem("div", {cls: "status"});
    this.ui.status.innerHTML = _tr('status.updating');

    // Assemble the final pieces of the layout
    this.ui.error = elem("div", {cls: ["error", "hidden"]}),
    this.ui.table = elem("div", {});

    this.container.appendChild(frag);

    // Setup tab switching
    for (let tab of this.container.querySelectorAll("ul.tabs li"))
        tab.addEventListener("click", (e) => this.switchTab(e.target.dataset.id));

    this.container.appendChild(this.ui.status);
    this.container.appendChild(this.ui.error);
    this.container.appendChild(this.ui.table);
}

switchTab(tab)
{
    if (this.updating || this.processing)
        return;

    if (this.settings.currentTab == tab)
        return;

    let containers = [
        this.container.querySelector(`div.tab#${this.id}-tab-tools`),
        this.container.querySelector(`div.tab#${this.id}-tab-columns`),
        this.container.querySelector(`div.tab#${this.id}-tab-filters`),
        this.container.querySelector(`div.tab#${this.id}-tab-mass`),
    ];

    for (let t of this.container.querySelectorAll("ul.tabs > li")) {
        if (t.classList.contains("disabled"))
            return;

        if (t.dataset.id == tab) {
            t.classList.remove("unselected");
            t.classList.add("selected");
        } else {
            t.classList.remove("selected");
            t.classList.add("unselected");
        }
    }

    for (let c of containers) {
        if (!c)
            continue;

        if (c.dataset.id == tab)
            c.classList.remove("hidden");
        else c.classList.add("hidden");
    }

    this.settings.currentTab = tab;

    this.saveSettings();
}

updateUI()
{
    let totalRows = 0,
        visibleRows = 0;

    try { totalRows = this.data.transformed.length; } catch (e) {}
    try { visibleRows = this.data.current.length; } catch (e) {}

    let html =
        `${totalRows} ${_tr('status.total_rows')}, ` +
        `${visibleRows} ${_tr('status.visible_rows')}, ` +
        `${totalRows - visibleRows} ${_tr('status.filtered_rows')}`;

    if (this.settings.flags & TableFlag.ALLOW_SELECTION) {
        html += `, ${this.data.selectedItems.size} ${_tr('status.selected_rows')}`;

        if (this.processing || this.doneAtLeastOneOperation) {
            html += ` (<span class=\"success\">${this.data.successItems.size} ${_tr('status.successfull_rows')}</span>, `;
            html += `<span class=\"fail\">${this.data.failedItems.size} ${_tr('status.failed_rows')}</span>)`;
        }
    }

    this.ui.status.innerHTML = html;

    if (this.haveMassTools()) {
        if (this.processing || this.updating || this.massOperation.index == -1)
            this.ui.mass.proceed.disabled = true;
        else this.ui.mass.proceed.disabled = (this.data.selectedItems.size == 0);
    }
}

enableUI(state)
{
    if (!state) {
        // Disable
        for (let t of this.container.querySelectorAll("ul.tabs > li"))
            if (!t.classList.contains("selected"))
                t.classList.add("disabled");

        this.disableColumnEditor();

        this.ui.table.classList.add("updating");

        this.ui.reload.disabled = true;
        this.ui.csv.disabled = true;

        if (this.settings.flags & TableFlag.ALLOW_FILTERING) {
            this.ui.filter.enabled.disabled = true;
            this.ui.filter.reverse.disabled = true;

            if (this.ui.filter.presets)
                this.ui.filter.presets.disabled = true;

            this.filterEditor.disable();
        }

        if (this.haveMassTools()) {
            this.ui.mass.selector.disabled = true;
            this.ui.mass.proceed.disabled = true;
        }
    } else {
        // Enable
        for (let t of this.container.querySelectorAll("ul.tabs > li"))
            t.classList.remove("disabled");

        this.enableColumnEditor();

        this.ui.table.classList.remove("updating");

        this.ui.reload.disabled = false;
        this.ui.csv.disabled = false;

        if (this.settings.flags & TableFlag.ALLOW_FILTERING) {
            this.ui.filter.enabled.disabled = false;
            this.ui.filter.reverse.disabled = false;

            if (this.ui.filter.presets)
                this.ui.filter.presets.disabled = false;

            this.filterEditor.enable();
        }

        if (this.haveMassTools()) {
            for (let b of this.container.querySelectorAll("div.mass > div.mainButtons button"))
                b.disabled = true;

            this.ui.mass.selector.disabled = false;
            this.ui.mass.proceed.disabled = this.data.selectedItems.size == 0;
        }
    }
}

setError(message)
{
    this.ui.error.innerHTML = message + ". " + _tr('see_console_for_details');
    this.ui.error.classList.remove("hidden");
}

resetError()
{
    this.ui.error.innerHTML = "";
    this.ui.error.classList.add("hidden");
}

// Retrieve data from the server and process it
fetchDataAndUpdate()
{
    this.data.selectedItems.clear();
    this.data.successItems.clear();
    this.data.failedItems.clear();
    this.ui.status.innerHTML = _tr('status.updating');
    this.updating = true;
    this.enableUI(false);

    let networkError = null;

    let url = this.settings.source + "?fields=" + this.settings.columns.join(",");

    fetch(url)
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
            if (this.parseServerResponse(data))
                this.updateTable();
        })
        .catch(error => {
            if (networkError === null)
                this.setError(error);
            else this.setError(_tr('network_error') + networkError);

            this.enableUI(true);
            this.updateUI();

            console.log(error);
        });
}

// Takes the plain text returned by the server and, if possible, turns it into JSON
// and transforms it into usable data. Does not rebuild the table.
parseServerResponse(textData)
{
    let json = null;

    const t0 = performance.now();

    // try...catch block won't work as expected inside fetch(), so handle it here
    try {
        json = JSON.parse(textData);
    } catch (e) {
        // The server responded with something that isn't JSON
        this.enableUI(true);
        this.ui.table.classList.remove("updating");
        this.setError(e);
        console.log(e);

        return false;
    }

    // Clean up the server data
    const t1 = performance.now();

    this.data.transformed = transformRawData(
        this.settings.columnDefinitions,
        this.settings.columns,
        this.settings.userTransforms,
        json
    );

    if (this.settings.flags & TableFlag.ALLOW_SELECTION) {
        // If the currently selected items (if any) have items that no longer exist in
        // the data returned by the server, remove them.
        let newSelected = new Set();

        for (const item of this.data.transformed) {
            const id = item.id[0];

            if (this.data.selectedItems.has(id))
                newSelected.add(id);
        }

        // Of course this assumes the table will be rebuilt immediately after this...
        this.data.selectedItems = newSelected;
    }

    const t2 = performance.now();

    this.resetError();

    console.log(`JSON parsing: ${t1 - t0} ms; data transformation: ${t2 - t1} ms.`);
    return true;
}

// Takes the currently cached table data, filters and sorts it, then displays the results
updateTable()
{
    this.enableUI(false);
    this.updating = true;
    this.doneAtLeastOneOperation = false;
    this.data.selectedItems.clear();
    this.data.successItems.clear();
    this.data.failedItems.clear();

    // Filter (if enabled)
    const t0 = performance.now();
    let filtered = [];

    if (this.settings.flags & TableFlag.ALLOW_FILTERING &&
        this.settings.filtersEnabled &&
        this.settings.effectiveFilters.length > 0) {

        filtered = filterData(this.settings.columnDefinitions,
                              this.data.transformed,
                              this.settings.effectiveFilters,
                              this.settings.filtersReverse);
    } else filtered = this.data.transformed;

    const t1 = performance.now();

    // Sort
    const t2 = performance.now();
    this.data.current = sortData(this.settings.columnDefinitions, this.settings.sorting,
                                 this.collator, filtered);
    const t3 = performance.now();

    // Display results
    this.buildTable();
    const t4 = performance.now();

    console.log(`Filtering: ${t1 - t0} ms; sorting ${t3 - t2} ms; table rebuild ${t4 - t3} ms.`);

    this.updating = false;
    this.enableUI(true);
    this.updateUI();
}

neuterTableClickables(state)
{
    // Enable/disable sort headers
    let headings = document.querySelector(`#${this.id} thead`).childNodes[0].childNodes;

    for (let i = 1; i < headings.length; i++) {
        if (state)
            headings[i].classList.remove("cursor-not-allowed");
        else headings[i].classList.add("cursor-not-allowed");
    }

    // Enable/disable row checkboxes
    let tbody = document.querySelector(`#${this.id} tbody`);

    for (let i = 0; i < tbody.childNodes.length; i++) {
        let td = tbody.childNodes[i].childNodes[0];

        if (state)
            td.classList.remove("cursor-not-allowed");
        else td.classList.add("cursor-not-allowed");
    }
}

// CSV download
getCSV()
{
    const visibleRows = this.container.querySelector(`#${this.id}-csv-only-visible`).checked;

    try {
        const source = visibleRows ? this.data.current : this.data.transformed;

        let csvData = [];

        // The header row
        csvData.push(this.settings.columns.join(";"));

        // Data rows
        for (const row of source) {
            let csvRow = [];

            for (const col of this.settings.columns) {
                // Store the raw values, not the "cleaned up" display values
                if (col in row)
                    csvRow.push(row[col][0]);
                else csvRow.push("");
            }

            csvData.push(csvRow.join(";"));
        }

        csvData = csvData.join("\n");

        const timestamp = I18n.strftime(new Date(), "%Y-%m-%d-%H-%M-%S");

        // Build a blob object (it must be an array for some reason), then trigger a download.
        // Download code stolen from StackOverflow.
        // @@@FIXME: For some reason, this clears the browser console?
        const b = new Blob([csvData], { type: "text/csv" });

        let a = window.document.createElement("a");
        a.href = window.URL.createObjectURL(b);

        a.download = `${this.settings.csvPrefix}-${timestamp}.csv`;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    } catch (e) {
        console.log(e);
        window.alert(_tr('csv_generation_error') + "\n\n" + e + "\n\n" + _tr('see_console_for_details'));
    }
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// COLUMN EDITING

toggleColumn(target)
{
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    if (this.processing || this.updating)
        return;

    if (target.classList.contains("disabled"))
        return;

    const columnID = target.dataset.column;

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
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    if (this.processing || this.updating)
        return;

    // Make a list of new visible columns
    let newVisible = new Set();

    for (let i = 0; i < this.ui.columns.list.childNodes.length; i++) {
        let c = this.ui.columns.list.childNodes[i];

        if (!c.classList.contains("selected"))
            continue;

        newVisible.add(c.dataset.column);
    }

    // Keep the existing columns in whatever order they were, but remove
    // hidden columns
    let newColumns = [];

    for (const col of this.settings.columns) {
        if (newVisible.has(col)) {
            newColumns.push(col);
            newVisible.delete(col);
        }
    }

    // Then tuck the newly-added columns at the end of the array
    for (const col of newVisible)
        newColumns.push(col);

    this.settings.columns = [...newColumns];

    // Is the current sorting column still visible? If not, find another column to sort by.
    let sortVisible = false,
        defaultVisible = false;

    for (const col of newColumns) {
        if (this.settings.sorting.column == col)
            sortVisible = true;

        if (this.settings.defaultSorting.column == col)
            defaultVisible = true;
    }

    if (!sortVisible) {
        if (defaultVisible) {
            // The default column is visible, so use it
            this.settings.sorting.column = this.settings.defaultSorting.column;
        } else {
            // Okay, pick the first column we have and use it
            this.settings.sorting.column = newColumns[0];
        }
    }

    if (this.settings.flags & TableFlag.ALLOW_FILTERING) {
        // Filters may target columns that aren't visible anymore, so update them
        this.filterEditor.setColumns(this.settings.columns);
        this.filterEditor.buildFilterTable();
    }

    this.unsavedColumns = false;
    this.updateColumnEditor();
    this.saveSettings();
    this.fetchDataAndUpdate();
}

resetColumns()
{
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    if (this.processing || this.updating)
        return;

    let initial = new Set();

    for (const c of this.settings.defaultColumns)
        initial.add(c);

    for (let i = 0; i < this.ui.columns.list.childNodes.length; i++) {
        let c = this.ui.columns.list.childNodes[i];

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

allColumns()
{
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    if (this.processing || this.updating)
        return;

    for (let i = 0; i < this.ui.columns.list.childNodes.length; i++) {
        let c = this.ui.columns.list.childNodes[i];

        c.classList.add("selected");
        c.firstChild.checked = true;
    }

    this.unsavedColumns = true;
    this.updateColumnEditor();
}

resetColumnOrder()
{
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    const current = new Set(this.settings.columns);

    let nc = [];

    for (const c of this.settings.columnOrder)
        if (current.has(c))
            nc.push(c);

    this.settings.columns = [...nc];
    this.saveSettings();
    this.updateTable();     // only the column order changes, not what is visible
}

updateColumnEditor()
{
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    // Count how many columns have been selected
    let numSelected = 0;

    for (let c = 0; c < this.ui.columns.list.childNodes.length; c++)
        if (this.ui.columns.list.childNodes[c].classList.contains("selected"))
            numSelected++;

    if (numSelected == 0)
        this.ui.columns.save.disabled = true;
    else if (this.unsavedColumns)
        this.ui.columns.save.disabled = false;
    else this.ui.columns.save.disabled = true;

    if (this.unsavedColumns)
        this.ui.columns.unsaved.classList.remove("hidden");
    else this.ui.columns.unsaved.classList.add("hidden");

    this.ui.columns.status.innerHTML =
        _tr('tabs.columns.selected') + " " + numSelected +
        "/" + Object.keys(this.settings.columnDefinitions).length + " " +
        _tr('tabs.columns.total') + ":";
}

enableColumnEditor()
{
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    for (let i = 0; i < this.ui.columns.list.childNodes.length; i++) {
        let c = this.ui.columns.list.childNodes[i];

        c.classList.remove("disabled");
        c.firstChild.disabled = false;
    }

    this.ui.columns.reset.disabled = false;
    this.ui.columns.all.disabled = false;
    this.ui.columns.sort.disabled = false;
    this.updateColumnEditor();
}

disableColumnEditor()
{
    if (!(this.settings.flags & TableFlag.ALLOW_COLUMN_CHANGES))
        return;

    for (let i = 0; i < this.ui.columns.list.childNodes.length; i++) {
        let c = this.ui.columns.list.childNodes[i];

        c.classList.add("disabled");
        c.firstChild.disabled = true;
    }

    this.ui.columns.reset.disabled = true;
    this.ui.columns.all.disabled = true;
    this.ui.columns.sort.disabled = true;
    this.updateColumnEditor();
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// FILTERS

setFilters(filters, saveThem)
{
    if (!(this.settings.flags & TableFlag.ALLOW_FILTERING))
        return;

    if (this.updating || this.processing)
        return;

    // Preprocess the filters into "effective" filters. These are never converted back
    // into "editable" filters.
    let effective = [];

    try {
        if (Array.isArray(filters)) {
            for (const f of filters) {
                if (!f.active)
                    continue;

                if (!(f.column in this.settings.columnDefinitions))
                    continue;

                if (f.value === null)
                    continue;

                let e = {
                    column: f.column,
                    operator: f.operator,
                    value: null,
                    regexp: false
                };

                const def = this.settings.columnDefinitions[f.column];

                if (def.type == ColumnType.STRING) {
                    const value = Array.isArray(f.value) ? f.value[0] : f.value;

                    // Strings are always regexps. Substitute empty strings with "^$" because
                    // that's probably what the user wanted (to match empty strings).
                    e.value = new RegExp(value.trim().length == 0 ? "^$" : f.value, "iu");
                    e.regexp = true;
                } else if (def.type == ColumnType.UNIXTIME) {
                    const value = Array.isArray(f.value) ? f.value[0] : f.value;
                    const d = parseAbsoluteOrRelativeDate(value);

                    e.value = (d === null ? 0 : d.valueOf() / 1000);
                } else if (def.type == ColumnType.BOOLEAN) {
                    e.value = Array.isArray(f.value) ? f.value[0] : f.value;
                } else {
                    // Use as-is (integers and floats)
                    e.value = f.value;
                }

                // Only integer columns actually support array comparisons, but convert everything
                // into arrays. This makes the filtering code easier to write, because the value
                // is always accessed with [0].
                if (!Array.isArray(e.value))
                    e.value = [e.value];

                effective.push(e);
            }
        }
    } catch (e) {
        window.alert(_tr('filter_conversion_failed') + "\n\n" + e + "\n\n" + _tr('new_filters_not_applied'));
        return;
    }

    this.settings.effectiveFilters = effective;

    this.doneAtLeastOneOperation = false;

    if (saveThem == true)
        this.saveInitialFilters(filters);
}

// Called from the filter editor
filtersHaveChanged()
{
    if (!(this.settings.flags & TableFlag.ALLOW_FILTERING))
        return;

    if (this.updating || this.processing)
        return;

    this.doneAtLeastOneOperation = false;
    this.updateTable();
}

// Saves the filters to localstore
saveInitialFilters(filters)
{
    if (!(this.settings.flags & TableFlag.ALLOW_FILTERING))
        return;

    localStorage.setItem(`table-${this.id}-filters`, JSON.stringify(filters));
}

// Loads the filters from localstore. Returns true if something was loaded, false if not.
loadInitialFilters()
{
    if (!(this.settings.flags & TableFlag.ALLOW_FILTERING))
        return;

    const key = `table-${this.id}-filters`;

    const filters = localStorage.getItem(key);

    if (!filters) {
        console.log(`loadInitialFilters(): nothing stored for "${key}", using defaults`);
        return null;
    }

    let parsed = null;

    try {
        parsed = JSON.parse(filters);
    } catch (e) {
        console.error(`Unable to parse stored JSON filter data from "${key}":`);
        console.error(e);
        console.error("Using the initial filters");
        return null;
    }

    let cleaned = [];

    // Validate the filters. Columns, operators, values, etc.
    const validOperators = new Set([
        FilterOperator.EQU,
        FilterOperator.NEQ,
        FilterOperator.LT,
        FilterOperator.LTE,
        FilterOperator.GT,
        FilterOperator.GTE,
    ]);

    if (Array.isArray(parsed)) {
        for (const f of parsed) {
            if (!("column" in f && "operator" in f && "value" in f))
                continue;

            if (!(f.column in this.settings.columnDefinitions))
                continue;

            if (!validOperators.has(f.operator))
                continue;

            let c = {
                active: false,
                column: f.column,
                operator: f.operator,
                value: f.value
            };

            // This is optional. Restore it if possible.
            if ("active" in f && f.active === true)
                c.active = true;

            cleaned.push(c);
        }
    }

    return cleaned;
}

toggleFiltersEnabled()
{
    if (!(this.settings.flags & TableFlag.ALLOW_FILTERING))
        return;

    if (this.updating || this.processing)
        return;

    let tab = this.container.querySelector(`li#${this.id}-tabbar-filters`);

    tab.innerText = _tr('tabs.filtering.title') + (this.ui.filter.enabled.checked ? " [ON]" : " [OFF]");

    this.settings.filtersEnabled = this.ui.filter.enabled.checked;
    this.doneAtLeastOneOperation = false;
    this.saveSettings();
    this.updateTable();
}

toggleFiltersReverse()
{
    if (!(this.settings.flags & TableFlag.ALLOW_FILTERING))
        return;

    if (this.updating || this.processing)
        return;

    this.settings.filtersReverse = this.ui.filter.reverse.checked;
    this.saveSettings();

    if (this.settings.filtersEnabled) {
        this.doneAtLeastOneOperation = false;
        this.updateTable();
    }
}

loadFilterPreset(e)
{
    if (!(this.settings.flags & TableFlag.ALLOW_FILTERING))
        return;

    if (this.updating || this.processing)
        return;

    const key = e.target.options[e.target.selectedIndex].dataset.id,
          preset = this.settings.filterPresets[key].filters;

    this.filterEditor.loadFilters(preset);
    this.setFilters(preset, true);
    this.updateTable();
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// MASS OPERATIONS

// Called when the selected mass operation changes
switchMassOperation(index)
{
    if (!(this.settings.flags & TableFlag.ALLOW_SELECTION))
        return;

    const def = this.settings.massOperations[index];

    let fieldset = this.container.querySelector(`div#${this.id}-tab-mass fieldset#ui`),
        container = fieldset.querySelector("div.ui");

    // Instantiate a new class
    this.massOperation.index = index;
    this.massOperation.handler = new def.cls(this, container);
    this.massOperation.singleShot = def.flags & MassOperationFlags.SINGLESHOT;

    // Hide/replace the existing UI
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
    if (!(this.settings.flags & TableFlag.ALLOW_SELECTION))
        return;

    if (this.updating || this.processing)
        return;

    if (!this.massOperation.handler.canProceed())
        return;

    if (!window.confirm(_tr('are_you_sure')))
        return;

    function beginOperation(ctx, numItems)
    {
        for (let t of ctx.container.querySelectorAll("ul.tabs > li"))
            if (!t.classList.contains("selected"))
                t.classList.add("disabled");

        for (let b of ctx.container.querySelectorAll("div.mass div.mainButtons button"))
            b.disabled = true;

        ctx.ui.mass.selector.disabled = true;
        ctx.ui.mass.proceed.disabled = true;

        ctx.ui.mass.progress.classList.remove("hidden");
        ctx.ui.mass.progress.setAttribute("max", numItems);
        ctx.ui.mass.progress.setAttribute("value", 1);

        ctx.ui.mass.counter.classList.remove("hidden");
        ctx.ui.mass.counter.innerHTML = `1/${numItems}`;

        ctx.neuterTableClickables(false);
        ctx.processing = true;

        // don't hide the success/fail counters after the operation is complete
        ctx.doneAtLeastOneOperation = true;
    }

    function endOperation(ctx)
    {
        for (let t of ctx.container.querySelectorAll("ul.tabs > li"))
            if (!t.classList.contains("selected"))
                t.classList.remove("disabled");

        for (let b of ctx.container.querySelectorAll("div.mass div.mainButtons button"))
            b.disabled = false;

        ctx.ui.mass.selector.disabled = false;
        ctx.ui.mass.proceed.disabled = false;

        // Leave the progress bar and the counter visible. They're only hidden until
        // the first time a mass operation is executed.

        ctx.massOperation.handler.finish();

        ctx.neuterTableClickables(true);
        ctx.processing = false;
    }

    function updateProgress(ctx, numItems, currentItem)
    {
        ctx.ui.mass.progress.setAttribute("value", currentItem);
        ctx.ui.mass.counter.innerHTML = `${currentItem}/${numItems}`;
    }

    function updateRow(ctx, row, status)
    {
        let cell = row[1];

        if (status.success === true) {
            cell.classList.remove("fail");
            cell.classList.add("success");
            cell.title = "";
        } else {
            cell.classList.remove("success");
            cell.classList.add("fail");

            if (status.message === null)
                cell.title = "";
            else cell.title = status.message;
        }
    }

    // Make a list of the selected items, in the order they appear in the table right now
    let tbody = document.querySelector(`#${this.id} tbody`);
    let itemsToBeProcessed = [];

    for (let i = 0; i < this.data.current.length; i++) {
        const row = this.data.current[i];

        if (this.data.selectedItems.has(row.id[0]))
            itemsToBeProcessed.push([row, tbody.childNodes[i]]);
    }

    this.data.successItems.clear();
    this.data.failedItems.clear();

    // Remove previous row states
    for (let i = 0; i < tbody.childNodes.length; i++) {
        let row = tbody.childNodes[i];

        row.classList.remove("success");
        row.classList.remove("fail");
    }

    // Javascript scoping garbage workaround
    let us = this;

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
                const id = itemsToBeProcessed[i][0].id[0];

                updateRow(us, itemsToBeProcessed[i], result);

                if (result.success === true)
                    us.data.successItems.add(id);
                else us.data.failedItems.add(i);
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
                const id = itemsToBeProcessed[i][0].id[0];

                updateRow(us, itemsToBeProcessed[i], result);

                if (result.success === true)
                    us.data.successItems.add(id);
                else us.data.failedItems.add(i);

                if (i >= itemsToBeProcessed.length - 1) {
                    // That was the last item, wrap everything up
                    // TODO: Should this be replaceable with Promise.all()?
                    updateProgress(us, itemsToBeProcessed.length, i + 1);
                    endOperation(us, itemsToBeProcessed.length);
                } else {
                    // Still ongoing
                    updateProgress(us, itemsToBeProcessed.length, i + 1);
                }

                us.updateUI();
            });
        }
    }
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// THE TABLE ITSELF

// Check/uncheck a single row
clickedRowCheckbox(e)
{
    if (!(this.settings.flags & TableFlag.ALLOW_SELECTION))
        return;

    if (this.updating || this.processing)
        return;

    e.preventDefault();

    let tr = e.target.parentNode,
        td = e.target,
        cb = tr.childNodes[0].childNodes[0];

    const index = parseInt(tr.dataset.index, 10),
          id = this.data.current[index].id[0];

    if (e.shiftKey && this.ui.previousRow != null && this.ui.previousRow != td) {
        // Range selection between the previously clicked row and this row
        let startIndex = this.ui.previousRow.parentNode.dataset.index,
            endIndex = tr.dataset.index;

        if (startIndex === undefined || endIndex === undefined) {
            console.error("Cannot determine the start/end indexes for range selection!");
            return;
        }

        startIndex = parseInt(startIndex, 10);
        endIndex = parseInt(endIndex, 10);

        // Select or deselect? Do this before the indexes are reordered.
        const state = this.data.selectedItems.has(this.data.current[startIndex].id[0]);

        if (startIndex > endIndex)
            [startIndex, endIndex] = [endIndex, startIndex];

        // Toggle selections
        let tbody = document.querySelector(`#${this.id} tbody`);

        for (let i = startIndex; i <= endIndex; i++) {
            let row = tbody.childNodes[i];
            let cb = row.childNodes[0].childNodes[0];

            row.classList.remove("success");
            row.classList.remove("fail");

            if (state) {
                cb.classList.add("checked");
                this.data.selectedItems.add(this.data.current[i].id[0]);
            } else {
                cb.classList.remove("checked");
                this.data.selectedItems.delete(this.data.current[i].id[0]);
            }
        }
    } else {
        // Select/deselect one row
        e.target.parentNode.classList.remove("success");
        e.target.parentNode.classList.remove("fail");

        // Rebuilding the table is too slow, so modify the checkbox cells directly
        if (cb.classList.contains("checked")) {
            cb.classList.remove("checked");
            this.data.selectedItems.delete(id);
        } else {
            cb.classList.add("checked");
            this.data.selectedItems.add(id);
        }
    }

    if (this.ui.previousRow)
        this.ui.previousRow.classList.remove("previousRow");

    td.classList.add("previousRow");
    this.ui.previousRow = td;

    this.doneAtLeastOneOperation = false;
    this.updateUI();
}

// Mass select or deselect rows. Called from the popup dropdown menu.
selectRows(operation)
{
    if (!(this.settings.flags & TableFlag.ALLOW_SELECTION))
        return;

    if (this.updating || this.processing || !this.data.current || this.data.current.length == 0)
        return;

    if (this.ui.previousRow) {
        this.ui.previousRow.classList.remove("previousRow");
        this.ui.previousRow = null;
    }

    // Rebuilding the table is too slow, so modify the checkbox cells directly
    let tbody = document.querySelector(`#${this.id} tbody`);

    for (let i = 0; i < tbody.childNodes.length; i++) {
        let row = tbody.childNodes[i];
        let cb = row.childNodes[0].childNodes[0];

        switch (operation) {
            case RowSelectOp.SELECT_ALL:
                cb.classList.add("checked");
                row.classList.remove("success");
                row.classList.remove("fail");
                this.data.selectedItems.add(this.data.current[row.dataset.index].id[0]);
                break;

            case RowSelectOp.DESELECT_ALL:
                cb.classList.remove("checked");
                row.classList.remove("success");
                row.classList.remove("fail");
                this.data.selectedItems.delete(this.data.current[row.dataset.index].id[0]);
                break;

            case RowSelectOp.INVERT_SELECTION:
                if (cb.classList.contains("checked")) {
                    cb.classList.remove("checked");
                    this.data.selectedItems.delete(this.data.current[row.dataset.index].id[0]);
                } else {
                    cb.classList.add("checked");
                    this.data.selectedItems.add(this.data.current[row.dataset.index].id[0]);
                }

                row.classList.remove("success");
                row.classList.remove("fail");
                break;

            case RowSelectOp.DESELECT_SUCCESSFULL:
                if (row.classList.contains("success")) {
                    row.classList.remove("success");
                    cb.classList.remove("checked");
                    this.data.selectedItems.delete(this.data.current[row.dataset.index].id[0]);
                }

                break;

            default:
                return;
        }
    }

    this.doneAtLeastOneOperation = false;

    this.data.successItems.clear();
    this.data.failedItems.clear();
    this.updateUI();
}

// Start tracking a table header cell clicks/drags
onHeaderMouseDown(e)
{
    e.preventDefault();

    if (this.updating || this.processing)
        return;

    if (e.button != 0) {
        // Only accept "main" mouse button clicks
        return;
    }

    let header = e.target;

    this.headerDragTargetElement = e.target;
    this.headerTrackCanSort = header.dataset.sortable == "1"
    this.headerIsBeingDragged = false;
    this.headerTrackStartPos = [e.clientX, e.clientY];
    this.headerCellPositions = null;

    document.addEventListener("mouseup", this.onHeaderMouseUp);
    document.addEventListener("mousemove", this.onHeaderMouseMove);
}

// Either sort the table, or end cell reordering, depending on how much the mouse was moved
onHeaderMouseUp(e)
{
    e.preventDefault();

    document.removeEventListener("mouseup", this.onHeaderMouseUp);
    document.removeEventListener("mousemove", this.onHeaderMouseMove);

    this.ui.table.classList.remove("no-text-select");
    this.ui.table.classList.remove("no-pointer-events");
    document.body.classList.remove("cursor-grabbing");

    this.headerDragTargetElement = null;

    if (this.headerIsBeingDragged) {
        // Remove the drag overlays
        let s = null;

        s = document.querySelector("#DRAGHEADER");

        if (s)
            s.remove();

        s = document.querySelector("#DROPMARKER");

        if (s)
            s.remove();

        s = null;

        if (this.headerCellPositions === null)
            return;

        if (this.headerDragStartIndex === null)
            return;

        if (this.headerDragEndIndex === null)
            return;

        if (this.headerDragStartIndex === this.headerDragEndIndex)
            return;

        // Reorder the columns array
        this.settings.columns.splice(this.headerDragEndIndex, 0,
                                     this.settings.columns.splice(this.headerDragStartIndex, 1)[0]);

        // Reorder the table row columns. Perform an in-place swap of the two table columns,
        // it's much faster than regenerating the whole table.
        const t0 = performance.now();

        const offset = (this.settings.flags & TableFlag.ALLOW_SELECTION) ? 1 : 0;

        const from = this.headerDragStartIndex + offset,
              to = this.headerDragEndIndex + offset;

        let rows = this.ui.table.firstChild.rows,
            n = rows.length,
            row, cell;

        if (this.data.current.length == 0) {
            // Only reorder the header row columns, there's no data
            n = 1;
        }

        while (n--) {
            row = rows[n];
            cell = row.removeChild(row.cells[from]);
            row.insertBefore(cell, row.cells[to]);
        }

        this.headerCellPositions = null;

        const t1 = performance.now();

        console.log(`Table column swap: ${t1 - t0} ms`);

        this.doneAtLeastOneOperation = false;
        this.saveSettings();
    } else {
        // The mouse didn't move, so sort the table instead (if the column was sortable)
        if (!this.headerTrackCanSort)
            return;

        const index = e.target.dataset.index,
              key = e.target.dataset.key;

        if (key == this.settings.sorting.column) {
            // Change sorting direction
            if (this.settings.sorting.dir == SortOrder.ASCENDING)
                this.settings.sorting.dir = SortOrder.DESCENDING;
            else this.settings.sorting.dir = SortOrder.ASCENDING;
        } else {
            // Sort by another column
            this.settings.sorting.column = key;
            this.settings.sorting.dir = SortOrder.ASCENDING;
        }

        this.doneAtLeastOneOperation = false;
        this.saveSettings();
        this.updateTable();
        this.updateUI();
    }
}

// Track a table header cell. If the mouse moves "enough", initiate a drag.
onHeaderMouseMove(e)
{
    e.preventDefault();

    if (!this.headerIsBeingDragged && e.target != this.headerDragTargetElement) {
        // The mouse veered away from the tracked element *before* enough
        // distance had been accumulated to properly trigger the drag
        document.removeEventListener("mouseup", this.onHeaderMouseUp);
        document.removeEventListener("mousemove", this.onHeaderMouseMove);

        this.ui.table.classList.remove("no-text-select");
        this.ui.table.classList.remove("no-pointer-events");
        document.body.classList.remove("cursor-grabbing");

        this.headerDragTargetElement = null;
        return;
    }

    if (this.headerIsBeingDragged) {
        this.positionHeaderDragElements(e);
        return;
    }

    // Measure how far the mouse has been moved from the tracking start location
    const dx = this.headerTrackStartPos[0] - e.clientX,
          dy = this.headerTrackStartPos[1] - e.clientY;

    if (Math.sqrt(dx * dx + dy * dy) < 10.0)
        return;

    // Make a list of header cell positions, so we'll know where to draw the drop markers
    this.headerDragStartIndex = null;
    this.headerDragEndIndex = null;
    this.headerCellPositions = [];

    const xOff = window.scrollX,
          yOff = window.scrollY;

    let headers = e.target.parentNode;

    let start = 0,
        count = headers.childNodes.length;

    if (this.settings.flags & TableFlag.ALLOW_SELECTION)
        start++;

    if (this.settings.actionsCallback !== null)
        count--;

    //console.log(`start=${start} count=${count}`);

    for (let i = start; i < count; i++) {
        let n = headers.childNodes[i];

        if (n == e.target) {
            // This is the cell we're dragging
            this.headerDragStartIndex = i - start;
        }

        const r = n.getBoundingClientRect();

        this.headerCellPositions.push({
            x: r.x + xOff,
            y: r.y + yOff,
            w: r.width,
            h: r.height,
        });
    }

    if (this.headerCellPositions.length == 0) {
        console.error("No table header cells found!");
        this.headerCellPositions = null;
        return;
    }

    let drag = document.createElement("div");

    drag.id = "DRAGHEADER";
    drag.classList.add("dragHeader");

    const location = e.target.getBoundingClientRect();

    const dragX = Math.round(location.left),
          dragY = Math.round(location.top);

    this.dragOffX = e.clientX - dragX;
    this.dragOffY = e.clientY - dragY;

    drag.style.left = `${dragX + window.scrollX}px`;
    drag.style.top = `${dragY + window.scrollY}px`;
    drag.style.width = `${location.width}px`;
    drag.style.height = `${location.height}px`;

    // Copy the title. Have to do some juggling to get the text properly centered vertically.
    if (this.headerTrackCanSort)
        drag.innerHTML = `<span>${e.target.firstChild.firstChild.innerText}</span>`;
    else drag.innerHTML = `<span>${e.target.innerText}</span>`;

    let drop = document.createElement("div");

    drop.id = "DROPMARKER";
    drop.classList.add("dropMarker");
    drop.style.width = `3px`;
    drop.style.height = `${location.height + 10}px`;

    document.body.appendChild(drag);
    document.body.appendChild(drop);

    this.ui.table.classList.add("no-text-select");
    this.ui.table.classList.add("no-pointer-events");
    document.body.classList.add("cursor-grabbing");

    // Start dragging the header cell
    this.headerIsBeingDragged = true;

    // Initial positioning
    this.positionHeaderDragElements(e);
}

positionHeaderDragElements(e)
{
    if (this.headerCellPositions === null)
        return;

    const mx = e.clientX + window.scrollX,
          my = e.clientY + window.scrollY,
          mxOff = mx - this.dragOffX;

    // Find the column under the current position
    this.headerDragEndIndex = null;

    if (mx < this.headerCellPositions[0].x)
        this.headerDragEndIndex = 0;
    else {
        for (let i = 0; i < this.headerCellPositions.length; i++)
            if (this.headerCellPositions[i].x <= mx)
                this.headerDragEndIndex = i;
    }

    if (this.headerDragEndIndex === null) {
        console.error(`FAILED: x=${mx}`);
        return;
    }

    const slot = this.headerCellPositions[this.headerDragEndIndex];

    // Position the drag drop marker
    let drop = document.querySelector("#DROPMARKER");

    if (!drop)
        return;

    drop.style.left = `${slot.x - 2}px`;
    drop.style.top = `${slot.y - 5}px`;

    // Position the drag element. Clamp it against the window edges to prevent
    // unnecessary scrollbars from appearing.
    let drag = document.querySelector("#DRAGHEADER");

    if (!drag)
        return;

    const windowW = document.body.scrollWidth,      // not the best, but nothing else...
          windowH = document.body.scrollHeight,     // ...works even remotely nicely here
          elementW = this.headerCellPositions[this.headerDragStartIndex].w,
          elementH = this.headerCellPositions[this.headerDragStartIndex].h;

    const dx = Math.max(0, Math.min(mx - this.dragOffX, windowW - elementW)),
          dy = Math.max(0, Math.min(my - this.dragOffY, windowH - elementH));

    drag.style.left = `${dx}px`;
    drag.style.top = `${dy}px`;
}

// Rebuild the table contents and place it in the output container
buildTable()
{
    this.ui.previousRow = null;

    const t0 = performance.now();

    const haveActions = !!this.settings.actionsCallback;

    // Assemble the table as a string of HTML
    let html = "";

    html += "<thead>";

    if (this.settings.flags & TableFlag.ALLOW_SELECTION) {
        // This empty checkbox column in the header would be a nice place for some
        // button. But all the relevant buttons are already located in the control
        // box above. So for now, it's empty. Reserved for the future.
        html += `<th class="width-0 stStickyHeader"></th>`;
    }

    const currentColumn = this.settings.sorting.column;

    // Arrow unicode characters and padding values (their widths vary slightly,
    // so try to unify them). The padding values were determined empirically.
    const arrows = {
        unsorted: { asc: "\uf0dc",                 padding: 10 },
        string:   { asc: "\uf15d", desc: "\uf15e", padding: 5 },
        numeric:  { asc: "\uf162", desc: "\uf163", padding: 6 },
    };

    // The header row and sort columns
    for (let i = 0; i < this.settings.columns.length; i++) {
        const key = this.settings.columns[i];
        const def = this.settings.columnDefinitions[key];
        let classes = [],
            data = [];

        classes.push("stStickyHeader");

        // What CSS classes to add?
        if (def.flags & ColumnFlag.SORTABLE) {
            classes.push("cursor-pointer");
            classes.push("sortable");
        } else {
            // Not sortable, but don't show an ordinary "text" cursor
            classes.push("cursor-default");
        }

        if (key == currentColumn)
            classes.push("sorted");

        data.push(["index",  i]);
        data.push(["key", key]);
        data.push(["sortable", def.flags & ColumnFlag.SORTABLE]);

        html += `<th`;
        html += " " + data.map(d => `data-${d[0]}="${d[1]}"`).join(" ");
        html += ` class="${classes.join(' ')}">`;

        // Build the header cell contents. Put the column title and
        // a sort direction indicator in it.
        const isNumeric = (def.type != ColumnType.STRING);

        if (def.flags & ColumnFlag.SORTABLE) {
            let symbol, padding;

            if (key == currentColumn) {
                // Sorted by this column
                const type = isNumeric ? "numeric" : "string",
                      dir = (this.settings.sorting.dir == SortOrder.ASCENDING) ? "asc" : "desc";

                symbol = arrows[type][dir];
                padding = arrows[type]["padding"];
            } else {
                // Not sorted by this column
                symbol = arrows.unsorted.asc;
                padding = arrows.unsorted.padding;
            }

            html += `<div><span>${this.settings.columnTitles[key]}</span>`;
            html += `<span class="arrow" style="padding-left: ${padding}px">${symbol}`;
            html += "</span></div>";
        } else {
            // Unsortable column
            html += `${this.settings.columnTitles[key]}`;
        }

        html += "</th>";
    }

    if (haveActions) {
        // The actions column is always the last. It cannot be sorted or dragged around.
        html += `<th class="stStickyHeader">${_tr('column_actions')}</th>`;
    }

    html += "</tr></thead>";

    // Actual content
    html += "<tbody>";

    if (this.data.current.length == 0) {
        let numColumns = this.settings.columns.length;

        // Include the checkbox and actions columns, if present
        if (this.settings.flags & TableFlag.ALLOW_SELECTION)
            numColumns++;

        if (haveActions)
            numColumns++;

        html += `<tr><td colspan="${numColumns}">(${_tr('empty_table')})</td></tr>`;
    } else {
        for (let i = 0; i < this.data.current.length; i++) {
            const row = this.data.current[i];

            html += `<tr data-index="${i}">`;

            if (this.settings.flags & TableFlag.ALLOW_SELECTION)
                html += `<td class="minimize-width cursor-pointer checkbox"><span></span></td>`;

            for (const column of this.settings.columns) {
                const value = row[column];

                if (column == currentColumn)
                    html += "<td class=\"sorted\">";
                else html += "<td>";

                if (value.length == 1)
                    html += `${row[column][0]}`;
                else html += `${row[column][1]}`;

                html += "</td>";
            }

            if (haveActions)
                html += "<td>" + this.settings.actionsCallback(row) + "</td>";

            html += "</tr>";
        }
    }

    html += "</tbody>";

    const t1 = performance.now();

    // Turn the HTML into an in-memory table
    let fragment = new DocumentFragment();

    let table = document.createElement("table");

    table.id = this.id;
    table.classList.add("table");
    table.innerHTML = html;

    fragment.appendChild(table);

    const t2 = performance.now();

    // Setup event handlers
    let thead = fragment.querySelector("thead");
    let headings = thead.firstChild.childNodes;

    // Header row click handlers, for sorting the table.
    const start = (this.settings.flags & TableFlag.ALLOW_SELECTION) ? 1 : 0,    // skip the checkbox column
          count = haveActions ? headings.length - 1 : headings.length;          // skip the actions column

    for (let i = start; i < count; i++)
        headings[i].addEventListener("mousedown", event => this.onHeaderMouseDown(event));

    // Row checkbox callbacks
    if (this.settings.flags & TableFlag.ALLOW_SELECTION && this.data.current.length > 0)
        for (let row of fragment.querySelectorAll("tbody > tr"))
            row.childNodes[0].addEventListener("click", event => this.clickedRowCheckbox(event));

    const t3 = performance.now();

    // Replace the existing table
    if (this.ui.table.firstChild)
        this.ui.table.replaceChild(fragment, this.ui.table.firstChild);
    else this.ui.table.appendChild(fragment);

    const t4 = performance.now();

    console.log(`[TABLE] HTML generation: ${t1 - t0} ms; in-memory table: ${t2 - t1} ms; ` +
                `callback setup: ${t3 - t2} ms; DOM replace: ${t4 - t3} ms; total: ${t4 - t0} ms.`);
}

};
