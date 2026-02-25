import { _tr } from "../../common/utils.js";

import { create, getTemplate } from "../../common/dom.js";

import {
    ColumnFlag,
    SortOrder,
    INDEX_DISPLAYABLE,
    DEFAULT_ROWS_PER_PAGE,
} from "./constants.js";

import * as Data from "./data";

import * as Export from "./export.js";

import * as ColumnEditor from "./column_editor.js";

import * as Headers from "./headers.js";

import { FilterEditor } from "../filters/editor/fe_main.js";

import { onRowCheckboxClick, onOpenMassRowSelectionPopup } from "./row_selection.js";

import * as Settings from "./settings.js";

import * as Pagination from "./pagination.js";

import { buildTable } from "./table_builder.js";

import { isNullOrUndefined, isObject } from "./utils.js";

// Mass operation batch size (how many items are processed on one request)
const BATCH_SIZE = 5;

// SUPERTABLE_WORKER_FILE must be defined in the HTML file where the bundle is included in
const MASS_WORKER = new Worker(SUPERTABLE_WORKER_FILE);

MASS_WORKER.onmessage = e => {
    GLOBAL_SUPERTABLE_INSTANCE.onWorkerMessage(e);
};

// These formatters are exported into the public namespace
export const ST_DATE_FORMATTER = Intl.DateTimeFormat(document.documentElement.dataset.intlLocale, {
    weekday: "short",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    timeZone: document.documentElement.dataset.intlTimezone
});

export const ST_TIMESTAMP_FORMATTER = Intl.DateTimeFormat(document.documentElement.dataset.intlLocale, {
    weekday: "short",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
    hour12: false,
    timeZone: document.documentElement.dataset.intlTimezone
});

// Validates the parameters passed to the table class
function validateParameters(container, settings)
{
    if (isNullOrUndefined(container)) {
        console.error("this.container is null or undefined");
        return false;
    }

    const fatalError = msg => container.innerHTML = `<p class="stError">${msg}</p>`;

    if (!isObject(settings.columnDefinitions) || Object.keys(settings.columnDefinitions).length == 0) {
        fatalError("settings.columnDefinitions is missing or invalid (not an object)");
        return false;
    }

    if (!Array.isArray(settings.defaultColumns) || settings.defaultColumns.length == 0) {
        fatalError("settings.defaultColumns is missing, not an array, or empty");
        return false;
    }

    if (!isObject(settings.defaultSorting)) {
        fatalError("settings.defaultSorting is missing or invalid (not an object)");
        return false;
    }

    // Ensure we have at least one data source
    if (isNullOrUndefined(settings.staticData) && isNullOrUndefined(settings.dynamicData)) {
        fatalError("No data source defined (staticData and dynamicData are both missing)");
        return false;
    }

    // The default columns parameter MUST be correct at all times
    for (const c of settings.defaultColumns) {
        if (!(c in settings.columnDefinitions)) {
            fatalError(`Default column "${c}" is not in the column definitions`);
            return false;
        }
    }

    // The default sorting column and direction must be valid
    if (!(settings.defaultSorting.column in settings.columnDefinitions)) {
        fatalError(`Invalid default sorting column "${settings.defaultSorting.column}"`);
        return false;
    }

    if (![SortOrder.ASCENDING, SortOrder.DESCENDING].includes(settings.defaultSorting.dir)) {
        fatalError(`Invalid or unknown default sorting direction "${settings.defaultSorting.dir}".`);
        return false;
    }

    return true;
}

export class SuperTable {

constructor(container, settings)
{
    this.id = settings.id;
    this.container = container;

    if (!validateParameters(this.container, settings))
        return;

    // ----------------------------------------------------------------------------------------------
    // Data

    // Main settings
    this.settings = {
        // Sorting locale
        locale: settings.locale ?? "en-US",

        // Prefix for CSV exporting
        csvPrefix: settings.csvPrefix ?? "unknown",

        // Load settings, apply defaults if omitted
        enableExport: settings.enableExport ?? true,
        enableColumnEditing: settings.enableColumnEditing ?? true,
        enableSelection: settings.enableSelection ?? true,
        enableFiltering: settings.enableFiltering ?? true,
        enablePagination: settings.enablePagination ?? true,

        // Static source for data
        staticData: settings.staticData ?? null,

        // URL where to get data dynamically
        dynamicData: settings.dynamicData,

        // Which expanding tool panes are open (names)
        show: [],
    };

    // User-supplied functions and callbacks
    this.user = {
        // An optional generator function that generates/filters the data when it is being
        // transformed.
        preFilterFunction: typeof(settings.preFilterFunction) == "function" ? settings.preFilterFunction : null,

        // Optional callback functions for populating the rightmost "actions" column and
        // handling middle mouse clicks.
        actions: typeof(settings.actions) == "function" ? settings.actions : null,
        open: typeof(settings.openCallback) == "function" ? settings.openCallback : null,

        // Mass row selections
        massSelects: Array.isArray(settings.massSelects) ? settings.massSelects : [],

        // Mass operations
        massOperations: Array.isArray(settings.massOperations) ? settings.massOperations : [],

        // The URL where mass operations are sent to
        massOperationsEndpoint: typeof(settings.massOperationsEndpoint) == "string" ? settings.massOperationsEndpoint : null,
    };

    // Current table data
    this.data = {
        // Data that has been transformed from the almost-raw database dump. The transformation
        // is done only once, when the data is loaded from the server (either static or dynamic).
        // The transformed data contains multiple copies of every value, each with different
        // meanings and uses (some data is displayed to the user and it gets "pretty-printed"
        // and formatted nicely, while other data is used only for sorting and filtering, and so
        // on). This is an array of objects. Each array element is one row in the table, and
        // the object members can be in whatever order they happen to be; it does not have to
        // match the table column order. Always access this array through "current" array below!
        transformed: [],

        // A lookup table to "transformed". Stores the indexes of the currently visible table
        // rows (pagination is ignored), in the order they are (based on the current sorting
        // column and order). So always write "this.data.transformed[this.data.current[N]]"
        // when you need to access row data.
        current: [],

        // Item IDs (puavoIds) for mass tools. The ID ordering does not matter.
        selectedItems: new Set(),
        successItems: new Set(),
        failedItems: new Set(),
    };

    // Current table columns
    this.columns = {
        definitions: settings.columnDefinitions,
        order: settings.columnOrder || [],
        defaults: [...settings.defaultColumns],
        current: [...settings.defaultColumns],      // overridden if saved settings exist
        defaultSorting: settings.defaultSorting,
    };

    // Current sorting
    this.sorting = {...settings.defaultSorting};    // overridden if saved settings exist

    // Current filters
    this.filters = {
        enabled: false,
        reverse: false,
        advanced: false,
        presets: settings.filterPresets || [{}, {}],
        defaults: settings.defaultFilter || [[], []],
        filters: null,                              // overridden if saved settings exist
        string: null,                               // ditto
        program: null,                              // the current (compiled) filter program
    };

    // Pagination state
    this.paging = {
        rowsPerPage: settings.defaultRowsPerPage ?? DEFAULT_ROWS_PER_PAGE,
        numPages: 0,
        currentPage: 0,
        firstRowIndex: 0,     // used to compute table row numbers during selections and mass operations
        lastRowIndex: 0,
    };

    // Index of the previously clicked table row (in the current page), -1 if nothing.
    // Used when doing Shift+LMB range selections.
    this.previousRow = -1;

    // Direct handles to various user interface elements. Cleaner than using querySelector()
    // everywhere (but I have my suspicions about memory leaks).
    this.ui = {
        filters: {
            show: null,         // show/hide filter editor checkbox
        },

        mass: {
            show: null,         // show/hide checkbox
            start: null,
            stop: null,
            progress: null,
            counter: null,
        },
    };

    // A child class that implements the filter editor. Everything it does happens inside its
    // own container DIV element that is shown or hidden independently of the editor.
    this.filterEditor = null;

    // Current mass operation data
    this.massOperation = {
        // The user-supplied definition for this mass operation
        definition: null,

        // The user-supplied handler class that actually does the mass operation (the SuperTable
        // code only sets up everything, its the user code that actually does the operation)
        handler: null,

        // Used during an on-going mass operation to track the state of each selected table row
        singleShot: false,
        parameters: null,
        rows: [],
        pos: 0,
        prevPos: 0,
    };

    // State
    this.updating = false;
    this.processing = false;
    this.stopRequested = false;

    // Header drag callback functions. "bind()" is needed to get around some weird
    // JS scoping garbage I don't understand.
    this.onHeaderMouseDown = this.onHeaderMouseDown.bind(this);
    this.onHeaderMouseUp = this.onHeaderMouseUp.bind(this);
    this.onHeaderMouseMove = this.onHeaderMouseMove.bind(this);

    // ----------------------------------------------------------------------------------------------

    // There's no point in permitting row selection if there are no mass tools
    if (this.settings.enableSelection && (this.user.massOperations.length == 0 || this.user.massOperationsEndpoint == null))
        this.settings.enableSelection = false;

    // Load stored settings
    Settings.load(this);

    // Validate the current sorting column and ensure it is in the currently visible columns
    let found = false;

    for (const c of this.columns.current) {
        if (c == this.sorting.column) {
            found = true;
            break;
        }
    }

    if (!found) {
        // FIXME: What happens if the first column has ColumnFlag.NOT_SORTABLE flag?
        // FIXME: What happens if there are no sortable columns at all?
        console.warn(`The initial sorting column "${this.sorting.column}" isn't visible, ` +
                     `using the first available ("${this.columns.current[0]}")`);
        this.sorting.column = this.columns.current[0];
    }

    // ----------------------------------------------------------------------------------------------
    // Build the user interface

    this.buildUI();

    // ----------------------------------------------------------------------------------------------
    // Setup filtering. Can't do this earlier, because the filter editor object won't
    // exist before buildUI() is finished.

    if (this.settings.enableFiltering) {
        let advanced = this.filters.string;

        if (typeof(advanced) != "string" || advanced == "")
            advanced = settings.initialFilter;

        this.filterEditor.setTraditionalFilters(this.filters.filters);
        this.filterEditor.setAdvancedFilter(advanced);

        // Can't call setFilter() here, because it attempts to update the table...
        // and we don't have any table data yet!
        this.filters.program = this.filterEditor.getFilterProgram();

        this.filterEditor.updatePreview();
    }

    // ----------------------------------------------------------------------------------------------
    // Do the initial data fetch and table update

    Settings.save(this);
    this.fetchDataAndUpdate();
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// USER INTERFACE

buildUI()
{
    // Can't assume the container DIV already has the required styles
    this.container.classList.add("superTable", "flex-rows", "gap-10px");

    this.container.appendChild(create("div", { cls: ["stError", "hidden"]}));

    const frag = getTemplate("tableControls");
    let elem;

    // Setup event handling for the elements that are visible
    elem = frag.querySelector("thead div#top button#export");

    if (this.settings.enableExport)
        elem.addEventListener("click", e => Export.openPopup(e.target, this.data, this.columns, this.settings.csvPrefix, this.settings.enableSelection));
    else elem.remove();

    const colButton = frag.querySelector("thead div#top button#columns");

    if (this.settings.enableColumnEditing)
        colButton.addEventListener("click", e => ColumnEditor.open(e.target, this));
    else colButton.remove();

    // Setup filtering
    if (this.settings.enableFiltering) {
        const enabled  = frag.querySelector(`thead section#filteringControls input#enabled`);

        enabled.checked = this.filters.enabled;
        enabled.addEventListener("click", (e) => this.toggleFiltersEnabled(e));

        const reverse  = frag.querySelector(`thead section#filteringControls input#reverse`);

        reverse.checked = this.filters.reverse;
        reverse.addEventListener("click", (e) => this.toggleFiltersReverse(e));

        this.ui.filters.show = frag.querySelector("thead section input#editor");

        frag.querySelector("thead div#top input#editor").addEventListener("click", e => {
            this.filterEditor.setVisibility(e.target.checked);
            this.toggleArrow(e.target);
            Settings.save(this);
        });

        // Construct the filter editor
        this.filterEditor = new FilterEditor(this,
                                             frag.querySelector("thead div#filteringContainer"),
                                             frag.querySelector("thead div#filteringPreview"),
                                             this.columns.definitions,
                                             this.filters.presets,
                                             this.filters.defaults,
                                             this.filters.advanced);

        // Expand the tool pane immediately
        if (this.settings.show.includes("filters")) {
            this.ui.filters.show.checked = true;
            this.filterEditor.setVisibility(true);
        }

        this.toggleArrow(this.ui.filters.show);
    } else {
        // Remove all filtering stuff from the view
        frag.querySelector("thead section#filteringControls").remove();
        frag.querySelector("div#filteringPreview").remove();
    }

    // Setup mass tools and row selection
    const rowsButton = frag.querySelector("thead div#top button#rows");

    if (this.settings.enableSelection) {
        this.ui.mass.show = frag.querySelector("thead section input#mass");

        frag.querySelector("thead div#top input#mass").addEventListener("click", e => {
            this.container.querySelector("tr#controls div#massContainer").classList.toggle("hidden", !e.target.checked);
            this.toggleArrow(e.target);
            Settings.save(this);
        });

        rowsButton.addEventListener("click", e => onOpenMassRowSelectionPopup(this, e.target));

        const mass = frag.querySelector("thead div#massContainer");

        // List the available mass operations. The combo already contains a "select" placeholder
        // item which is selected by default.
        const selector = mass.querySelector("fieldset div.massControls select.operation");

        for (const m of this.user.massOperations) {
            const o = create("option");

            o.value = m.id;
            o.label = m.title;

            selector.appendChild(o);
        }

        mass.querySelector("div.massControls > select").addEventListener("change", (e) => this.switchMassOperation(e));

        this.ui.mass.start = mass.querySelector("div.massControls button#start");
        this.ui.mass.stop = mass.querySelector("div.massControls button#stop");
        this.ui.mass.progress = mass.querySelector("div.massControls progress");
        this.ui.mass.counter = mass.querySelector("div.massControls span.counter");

        this.ui.mass.start.addEventListener("click", () => this.startMassOperation());
        this.ui.mass.stop.addEventListener("click", () => this.stopMassOperation());

        // Expand the tool pane immediately
        if (this.settings.show.includes("mass")) {
            this.ui.mass.show.checked = true;
            frag.querySelector("tr#controls div#massContainer").classList.remove("hidden");
        }

        this.toggleArrow(this.ui.mass.show);
    } else {
        rowsButton.remove();
        frag.querySelector("tr#controls section#massSpan").remove();
    }

    // Setup pagination
    if (this.settings.enablePagination)
        Pagination.initialize(this, frag);
    else frag.querySelector("section#paging")?.remove();

    // If the tools section is completely empty, remove it
    if (!this.settings.enableExport && !this.settings.enableColumnEditing && !this.settings.enableSelection)
        frag.querySelector("thead section#tools").remove();

    // Insert the empty table template on the page
    this.container.appendChild(frag);

    if (this.settings.dynamicData) {
        // Display the load animation. This gets overwritten with actual data once
        // the table is loaded. Assume the table has less than 1000 columns.
        this.getTableBody().innerHTML = `<tr><td colspan="999"><img src="/images/spinner.svg" class="spinner"></td></tr>`;
    }
}

// Returns true if the table is "busy", ie. it's updating itself, or a mass operation is underway.
// The table data or rows must not be modified while it's busy.
isBusy()
{
    return this.updating || this.processing;
}

getTableBody()
{
    return this.container.querySelector("table.stTable tbody#data");
}

// Sets and shows the error message
setError(html)
{
    const e = this.container.querySelector("div.stError");

    e.innerHTML = `${html}. ${_tr('see_console_for_details')}`;
    e.classList.remove("hidden");
}

resetError()
{
    const e = this.container.querySelector("div.stError");

    e.innerText = "";
    e.classList.add("hidden");
}

// Updates the "status bar" numbers (total rows, selected rows, etc.) and
// some selection-dependent button states
updateStats()
{
    const totalRows = this.data.transformed.length,
          visibleRows = this.data.current.length;

    let parts = [];

    parts.push(_tr("status.visible_rows", { visible: visibleRows, total: totalRows }));

    if (this.settings.enableFiltering)
        parts.push(_tr("status.filtered_rows", { count: totalRows - visibleRows }));

    if (this.settings.enableSelection)
        parts.push(_tr("status.selected_rows", { count: this.data.selectedItems.size }));

    this.container.querySelector("table.stTable thead tr#controls section#stats").innerText = parts.join(", ");
}

// Rotates the pane open/close toggle arrow
toggleArrow(element)
{
    if (!element) {
        console.warning("toggleArrow(): element is NULL");
        return;
    }

    const label = element.parentNode;

    if (!label || label.tagName != "LABEL") {
        console.warning("toggleArrow(): the element's parent is not a label node");
        return;
    }

    // ewww
    label.nextSibling.nextSibling.innerText = element.checked ? "▼" : "▶";
}

// Enable/disable UI elements. Called during updates, mass operations, etc. to
// prevent the user from initiating multiple overlapping/interfering actions.
enableUI(isEnabled)
{
    if (this.settings.enableExport)
        this.container.querySelector(`button#export`).disabled = !isEnabled;

    if (this.settings.enableColumnEditing)
        this.container.querySelector(`button#columns`).disabled = !isEnabled;

    if (this.settings.enablePagination)
        Pagination.enableControls(this, isEnabled);

    if (this.settings.enableFiltering) {
        const uiControls = this.container.querySelector("thead tr#controls section#filteringControls");

        this.ui.filters.show.disabled = !isEnabled;
        uiControls.querySelector("input#enabled").disabled = !isEnabled;
        uiControls.querySelector("input#reverse").disabled = !isEnabled;
        this.filterEditor.enableOrDisable(isEnabled);
    }

    if (this.settings.enableSelection) {
        this.container.querySelector(`button#rows`).disabled = !isEnabled;
        this.ui.mass.show.disabled = !isEnabled;
        this.container.querySelector("div.massControls select").disabled = !isEnabled;

        if (isEnabled)
            this.updateMassButtons();
        else {
            // Explicitly all disabled
            this.ui.mass.start.disabled = true;
            this.ui.mass.stop.disabled = true;
        }

        for (const b of this.container.querySelectorAll("div#massSelects button"))
            b.disabled = !isEnabled;
    }
}

// Enables or disables the table itself, ie. makes everything in it not clickable. This is done
// when a mass operation starts, to prevent the user from modifying the table in any way, or
// clicking any buttons in it. You don't want to disturb the table during mass operations...
enableTable(isEnabled)
{
    const headers = this.container.querySelector("table.stTable thead tr#headers"),
          body = this.getTableBody();

    // TODO: This is a hack. All links need to be disabled and this is the only quick way I know that works.
    headers.classList.toggle("user-select-none", !isEnabled);
    body.classList.toggle("user-select-none", !isEnabled);
    headers.classList.toggle("pointer-events-none", !isEnabled);
    body.classList.toggle("pointer-events-none", !isEnabled);
}

updateMassButtons()
{
    if (!this.ui.mass.start || !this.ui.mass.stop)
        return;

    if (this.processing || this.data.selectedItems.size == 0 || this.massOperation.definition === null)
        this.ui.mass.start.disabled = true
    else this.ui.mass.start.disabled = false;

    this.ui.mass.stop.disabled = !this.processing;
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PROCESSING AND TABLE BUILDING

// Called from the column editor
setVisibleColumns(newColumns)
{
    this.columns.current = newColumns;

    // Is the current sorting column still visible? If not, find another column to sort by.
    let sortVisible = false,
        defaultVisible = false;

    for (const col of newColumns) {
        if (this.sorting.column == col)
            sortVisible = true;

        if (this.columns.defaultSorting.column == col)
            defaultVisible = true;
    }

    if (!sortVisible) {
        if (defaultVisible) {
            // The default column is visible, so use it
            this.sorting.column = this.columns.defaultSorting.column;
        } else {
            // Pick the first column we have and use it
            // FIXME: What happens if the first column has ColumnFlag.NOT_SORTABLE flag?
            // FIXME: What happens if there are no sortable columns at all?
            this.sorting.column = newColumns[0];
        }
    }

    Settings.save(this);
    this.updateTable();
}

// Retrieves the actual table rows
getTableRows()
{
    return this.getTableBody().querySelectorAll("tr");
}

clearRowSelections()
{
    this.data.selectedItems.clear();
    this.data.successItems.clear();
    this.data.failedItems.clear();
}

beginTableUpdate()
{
    this.clearRowSelections();
    this.updating = true;
    this.enableUI(false);
    this.enableTable(false);
}

endTableUpdate()
{
    this.updating = false;
    this.enableUI(true);
    this.enableTable(true);
    this.updateStats();
}

// Retrieve data from the server and process it
fetchDataAndUpdate()
{
    this.beginTableUpdate();

    const startTime = performance.now();

    // Static or dynamic data?
    if (this.settings.staticData) {
        console.log("fetchDataAndUpdate(): static data only");

        Data.transformRawData(this, this.settings.staticData);
        this.updateTable();
        this.endTableUpdate();
        return;
    }

    // Do a network request for the data
    let networkError = null;

    console.log("fetchDataAndUpdate(): sending a network request");

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
        .then(textData => {
            console.log(`fetchDataAndUpdate(): network request: ${performance.now() - startTime} ms`);

            if (this.parseServerResponse(textData))
                this.updateTable();
        }).catch(error => {
            if (networkError === null)
                this.setError(error);
            else this.setError(_tr('network_error') + networkError);

            console.log(error);

            this.endTableUpdate();
        });
}

// Takes the plain text returned by the server and, if possible, turns it into JSON
// and transforms it into usable data. Does not rebuild the table.
parseServerResponse(textData, startTime)
{
    console.log("parseServerResponse(): begin");

    const t0 = performance.now();

    let raw = null;

    // try...catch won't work as expected inside fetch(), so do all JSON parsing and
    // error handling here (we're not inside fetch() promises anymore)
    try {
        raw = JSON.parse(textData);
    } catch (e) {
        // The server responded with something that isn't JSON
        this.enableUI(true);
        this.setError(e);
        console.log(e);

        return false;
    }

    console.log(`parseServerResponse(): JSON parsing took ${performance.now() - t0} ms`);

    Data.transformRawData(this, raw);

    console.log("parseServerResponse(): done");

    return true;
}

// Takes the currently cached transformed data, filters, sorts and displays it
updateTable()
{
    console.log("updateTable(): table update begins");

    this.enableUI(false);
    this.updating = true;

    const t0 = performance.now();

    // Filter
    let filtered = [];

    if (this.settings.enableFiltering && this.filters.enabled && this.filters.program) {
        filtered = Data.filterRows(this.columns.definitions,
                                   this.data.transformed,
                                   this.filters.program,
                                   this.filters.reverse);
    } else {
        // Filtering is not enabled, build an array that contains all rows
        filtered = Array.from(Array(this.data.transformed.length).keys());
    }

    const t1 = performance.now();

    // Sort
    const t2 = performance.now();

    const collator = new Intl.Collator(
        this.settings.locale,
        {
            usage: "sort",
            sensitivity: "accent",
            ignorePunctuation: true,
            numeric: true,                  // I really like this one
        }
    );

    this.data.current = Data.sortRows(this.columns.definitions, this.sorting, collator, this.data.transformed, filtered);

    const t3 = performance.now();

    console.log(`Data filtering: ${t1 - t0} ms`);
    console.log(`Data sorting: ${t3 - t2} ms`);

    if (this.settings.enablePagination) {
        Pagination.calculatePagination(this.data, this.paging);
        Pagination.updatePageCounter(this);
        Pagination.enableControls(this);
    }

    // Rebuild the table
    buildTable(this);
    this.endTableUpdate();

    console.log("updateTable(): table update complete");
}

onTableBodyMouseDown(e)
{
    if (this.isBusy())
        return;

    if (this.data.current.length == 0)
        return;

    if (e.button != 0 ||
            !this.settings.enableSelection ||
            e.target.tagName != "TD" ||
            !e.target.firstChild ||
            e.target.firstChild.tagName != "INPUT")
        return;

    // Clicked a row checkbox, forward the event
    onRowCheckboxClick(this, e);
}

onTableBodyMouseUp(e)
{
    if (this.isBusy())
        return;

    if (this.data.current.length == 0)
        return;

    if (e.button != 1 ||
            !this.user.open ||
            e.target.tagName == "A" ||
            e.target.classList.contains("checkbox"))
        return;

    // Full row open. Call the user-supplied callback function to format the URL and open it.
    e.preventDefault();

    const url = this.user.open(this.data.transformed[this.data.current[e.target.closest("tr").dataset.index]]);

    if (isNullOrUndefined(url))
        return;

    return window.open(url, "_blank");
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// FILTERS

// Called from the filter editor whenever a change to the filters have been made
saveFilters()
{
    this.filters.filters = this.filterEditor.getTraditionalFilters();
    this.filters.string = this.filterEditor.getAdvancedFilter();
    this.filters.advanced = this.filterEditor.isAdvancedMode();

    Settings.save(this);
    this.filterEditor.updatePreview();
}

// Called when a filtering settings have changed enough to force the table to be updated
updateFiltering()
{
    this.filters.program = this.filterEditor.getFilterProgram();

    if (this.filters.enabled) {
        this.clearRowSelections();
        this.updateTable();
    }
}

toggleFiltersEnabled(e)
{
    this.filters.enabled = e.target.checked;
    Settings.save(this);

    this.clearRowSelections();
    this.updateTable();
}

toggleFiltersReverse(e)
{
    this.filters.reverse = e.target.checked;
    Settings.save(this);

    if (this.filters.enabled) {
        this.clearRowSelections();
        this.updateTable();
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MASS OPERATIONS

// Called when the selected mass operation changes
switchMassOperation(e)
{
    const fieldset = this.container.querySelector("table.stTable thead div#massContainer fieldset#settings"),
          container = fieldset.querySelector("div#ui");

    const index = e.target.selectedIndex - 1;

    this.massOperation.definition = this.user.massOperations[index];
    this.massOperation.handler = new this.massOperation.definition.cls(this, container);

    // Hide/swap the UI
    container.innerText = "";

    if (this.massOperation.definition.haveSettings) {
        this.massOperation.handler.buildInterface();
        fieldset.classList.remove("hidden");
    } else fieldset.classList.add("hidden");

    this.ui.mass.progress.classList.add("hidden");
    this.ui.mass.counter.classList.add("hidden");

    this.updateStats();
    this.updateMassButtons();
}

startMassOperation()
{
    if (this.isBusy())
        return;

    if (!this.massOperation.handler.canProceed())
        return;

    if (!window.confirm(_tr('are_you_sure')))
        return;

    // Reset previous row states of visible rows
    for (const row of this.getTableRows()) {
        row.classList.remove("success", "fail", "processing");
        row.title = "";
    }

    this.data.successItems.clear();
    this.data.failedItems.clear();

    this.massOperation.rows = [];
    this.massOperation.pos = 0;
    this.massOperation.prevPos = 0;

    // Make a list of all selected rows
    for (let rowNum = 0; rowNum < this.data.current.length; rowNum++) {
        const id = this.data.transformed[this.data.current[rowNum]].id[INDEX_DISPLAYABLE];

        if (this.data.selectedItems.has(id)) {
            this.massOperation.rows.push({
                index: rowNum,
                id: id,
            });
        }
    }

    //console.log(this.data.selectedItems);

    this.massOperation.handler.start();
    this.massOperation.singleShot = this.massOperation.definition.singleShot || false;
    this.massOperation.parameters = this.massOperation.handler.getOperationParameters() || {};

    // Initiate the operation
    this.processing = true;
    this.stopRequested = false;

    this.enableUI(false);
    this.enableTable(false);
    this.updateMassButtons();

    this.ui.mass.progress.setAttribute("max", this.massOperation.rows.length);
    this.ui.mass.progress.setAttribute("value", 0);
    this.ui.mass.progress.classList.remove("hidden");
    this.ui.mass.counter.innerHTML = _tr("status.mass_progress", { count: 0, total: this.massOperation.rows.length, success: 0, fail: 0 });
    this.ui.mass.counter.classList.remove("hidden");

    if (this.massOperation.definition.singleShot) {
        // Process all rows at once
        this.processBatch(this.prepareNextBatch(this.data.selectedItems.size));
    } else {
        // Process in smaller batches
        this.processBatch(this.prepareNextBatch(BATCH_SIZE));
    }
}

stopMassOperation()
{
    // The operation will stop after the current batch has been processed
    // (no way to cancel the batch that's currently in-flight)
    this.stopRequested = true;
    console.log("Stopping the mass operation after the current batch finishes");
}

updateMassOperation()
{
    this.ui.mass.progress.setAttribute("value", this.massOperation.pos);

    this.ui.mass.counter.innerHTML = _tr("status.mass_progress", {
        count: this.massOperation.pos,
        total: this.massOperation.rows.length,
        success: this.data.successItems.size,
        fail: this.data.failedItems.size
    });
}

endMassOperation()
{
    this.massOperation.handler.finish();
    this.processing = false;
    this.enableUI(true);
    this.enableTable(true);
    this.updateMassButtons();

    // Leave the progress bar and the counter visible. They're only hidden until
    // the first time a mass operation is executed.
}

// Prepares the next N rows of the mass operation
prepareNextBatch(batchSize)
{
    if (this.massOperation.pos >= this.massOperation.rows.length) {
        console.log(`----- All items have been processed -----`);
        this.endMassOperation();
        return null;
    }

    const tableRows = this.getTableRows();

    const end = Math.min(this.massOperation.rows.length, this.massOperation.pos + batchSize);

    this.massOperation.prevPos = this.massOperation.pos;

    let batch = [];

    // Go through the next N rows and prepare them
    for (; this.massOperation.pos < end; this.massOperation.pos++) {
        const item = this.massOperation.rows[this.massOperation.pos];

        const tRow = Pagination.isTableRowVisible(this.paging, item.index) ?
            tableRows[item.index - this.paging.firstRowIndex] :
            null;

        //console.log(`Processing item ${this.massOperation.pos + 1}/${this.massOperation.rows.length}: ${item.id} (row ${item.index})`);

        // Returns a { state, data } object
        const result = this.massOperation.handler.prepareItem(this.data.transformed[this.data.current[item.index]]);

        // Immediately update the table if the results are already known
        switch (result.state) {
            case "ready":
                // This item can be processed
                if (result.data !== undefined)
                    this.massOperation.rows[this.massOperation.pos].data = result.data;

                batch.push(this.massOperation.rows[this.massOperation.pos]);
                tRow?.classList.add("processing");
                break;

            case "skip":
                // This item is already in the desired state, it can be skipped
                tRow?.classList.add("success");
                this.data.successItems.add(item.id);
                break;

            case "error":
                // This item could not be prepared for processing, skip it
                tRow?.classList.add("fail");
                this.data.failedItems.add(item.id);

                if (tRow && result.message) {
                    // Instantly set the error message
                    tRow.title = result.message;
                }

                break;

            default:
                console.error(result);
                window.alert(`Unknown prepare status: "${result.state}". This is a fatal error, stopping here. See the console for details, then contact support.`);
                this.endMassOperation();
                return null;
        }
    }

    return batch;
}

processBatch(batch)
{
    if (!Array.isArray(batch))
        return;

    if (batch.length == 0) {
        // Nothing to do for this batch. But these functions are not recursive, we have to
        // "route" the work through the worker thread.
        MASS_WORKER.postMessage({ message: "skip_batch" });
        return;
    }

    // We have at least 1 row to be processed
    console.log(`Have ${batch.length} rows in this batch`);

    MASS_WORKER.postMessage({
        message: "process_batch",
        url: this.user.massOperationsEndpoint,
        singleShot: this.massOperation.singleShot,
        operation: this.massOperation.definition.operation,
        parameters: this.massOperation.parameters,
        csrf: document.querySelector("meta[name='csrf-token']")?.content,
        rows: batch,
    });
}

onWorkerMessage(e)
{
    console.log(`[main] worker sent message:`, e.data.message);

    const tableRows = this.getTableRows();

    switch (e.data.message) {
        case "batch_processed":
            // Update table row colors
            for (const row of e.data.result) {
                if (row.status)
                    this.data.successItems.add(row.id);
                else this.data.failedItems.add(row.id);

                // If this row is visible, update its status
                if (Pagination.isTableRowVisible(this.paging, row.index)) {
                    const tRow = tableRows[row.index - this.paging.firstRowIndex];

                    tRow.classList.remove("processing");

                    if (row.status)
                        tRow.classList.add("success");
                    else {
                        tRow.classList.add("fail");

                        if (row.message)
                            tRow.title = row.message;
                    }
                }
            }

            break;

        case "batch_skipped":
            // There was nothing in this batch to process, the table has been updated, move on
            break;

        case "server_error":
        case "network_error":
            // This batch could not be processed. Flag all rows as failed and move on.
            for (let i = this.massOperation.prevPos; i < this.massOperation.pos; i++) {
                const item = this.massOperation.rows[i];
                const index = item.index;
                const tableRow = Pagination.isTableRowVisible(this.paging, index) ? tableRows[index - this.paging.firstRowIndex] : null;

                if (tableRow)
                    tableRow.classList.remove("processing");

                if (this.data.successItems.has(item.id) || this.data.failedItems.has(item.id)) {
                    // It's possible that some items were skipped in the preparation state,
                    // and they're not affected by this network/server error. They were
                    // not sent to the server, but because we mark all previous BATCH_SIZE
                    // rows as "failed", they must be skipped again here.
                    continue;
                }

                this.data.failedItems.add(item.id);

                if (tableRow) {
                    tableRow.classList.add("fail");
                    tableRow.title = e.data.error;
                }
            }

            break;

        default:
            // This is a fatal error
            console.error(`The worker thread sent an unknown message: "${e.data.message}"!`);
            window.alert("Unhandled worker thread message. Operation halted. See the console for details, then contact support.");
            this.endMassOperation();
            return;
    }

    this.updateMassOperation();

    if (this.stopRequested) {
        console.log(`----- Stopping per user request -----`);
        this.endMassOperation();
        return;
    }

    this.processBatch(this.prepareNextBatch(BATCH_SIZE));
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// TABLE HEADER REORDERING

// Start tracking a table header cell clicks/drags
onHeaderMouseDown(e)
{
    e.preventDefault();

    if (this.isBusy())
        return;

    if (e.button != 0)      // LMB only (or RMB if the buttons are swapped)
        return;

    Headers.beginMouseTracking(this, e);
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

    Headers.endMouseTracking(this, e);
    Settings.save(this);
}

// Drag a header cell around, or track mouse movement to see if header drag should be started
onHeaderMouseMove(e)
{
    e.preventDefault();

    if (Headers.updateDrag(e))
        return;

    if (Headers.shouldCancelMouseTracking(e)) {
        // The mouse veered away from the tracked element before enough "distance" had been accumulated
        // to trigger a header drag. Cancel the whole thing.
        Headers.cancelMouseTracking(this);

        document.removeEventListener("mouseup", this.onHeaderMouseUp);
        document.removeEventListener("mousemove", this.onHeaderMouseMove);
        return;
    }

    Headers.tryBeginDrag(this, e);
}

}   // class SuperTable
