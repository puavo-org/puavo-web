import { _tr, escapeHTML } from "../../common/utils.js";

import { create, destroy, getTemplate, toggleClass } from "../../common/dom.js";

import {
    setupGlobalEvents,
    createPopup,
    closePopup,
    attachPopup,
    displayPopup,
    ensurePopupIsVisible,
    isPopupOpen,
    getPopupContents,
} from "../../common/modal_popup.js";

import {
    ColumnFlag,
    ColumnType,
    SortOrder,
    INDEX_EXISTS,
    INDEX_DISPLAYABLE,
    INDEX_FILTERABLE,
    INDEX_SORTABLE,
    ROWS_PER_PAGE_PRESETS,
    DEFAULT_ROWS_PER_PAGE,
} from "./constants.js";

import { JAVASCRIPT_TIME_GRANULARITY } from "./utils.js";

import * as Data from "./data";

import * as Export from "./export.js";

import * as ColumnEditor from "./column_editor.js";

import * as HeaderDrag from "./header_reordering.js";

import { FilterEditor } from "../filters/editor/fe_main.js";

import * as Mass from "./mass_operations.js";

import * as Settings from "./settings.js";

// Mass operation batch size (how many items are processed on one request)
const BATCH_SIZE = 5;

// SUPERTABLE_WORKER_FILE must be defined in the HTML file where the bundle is included in
const MASS_WORKER = new Worker(SUPERTABLE_WORKER_FILE);

MASS_WORKER.onmessage = e => {
    GLOBAL_SUPERTABLE_INSTANCE.onWorkerMessage(e);
};

export class SuperTable {

constructor(container, settings)
{
    this.id = settings.id;
    this.container = container;

    if (!this.validateParameters(settings))
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

    // Direct handles to various user interface elements. Cleaner than using querySelector()
    // everywhere (but I have my suspicions about memory leaks).
    this.ui = {
        controls: null,         // the controls above the header cells
        headers: null,          // the table header cells
        body: null,             // the actual table body

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

        // The pagination controls
        paging: null,

        // The previously clicked table row. Can be null. Used when doing Shift+LMB
        // range selections.
        previousRow: null,
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

    // Table column header dragging state
    this.headerDrag = {
        element: null,              // the original TH where the drag originated from
        canSort: false,             // true if the dragged cell (column) is sortable
        active: false
    };

    // State
    this.updating = false;
    this.processing = false;
    this.stopRequested = false;
    this.doneAtLeastOneOperation = false;
    this.massRowSelectPopup = null;

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

// Validates the parameters passed to the class constructor
validateParameters(settings)
{
    // If these checks fail, explode loudly and completely prevent the table from even appearing.
    // That's intentional. These should be caught in development/testing.

    if (this.container === null || this.container === undefined) {
        console.error("The container DIV element is null or undefined");
        window.alert("The table container DIV is null or undefined. The table cannot be displayed. " +
                     "Please contact Opinsys support.");

        return false;
    }

    if (settings.columnDefinitions === undefined ||
        settings.columnDefinitions === null ||
        typeof(settings.columnDefinitions) != "object" ||
        Object.keys(settings.columnDefinitions).length == 0) {

        this.container.innerHTML =
            `<p class="error">The settings.columnDefinitions parameter missing/empty, or it isn't an associative array. ` +
            `Please contact Opinsys support.</p>`;

        return false;
    }

    if (settings.defaultColumns === undefined ||
        settings.defaultColumns === null ||
        !Array.isArray(settings.defaultColumns) ||
        settings.defaultColumns.length == 0) {

        this.container.innerHTML =
            `<p class="error">The settings.defaultColumn parameter missing/empty, or it isn't an array. ` +
            `Please contact Opinsys support.</p>`;

        return false;
    }

    if (settings.defaultSorting === undefined ||
        settings.defaultSorting === null ||
        typeof(settings.defaultSorting) != "object" ||
        settings.defaultSorting.length == 0) {

        this.container.innerHTML =
            `<p class="error">The settings.defaultSorting parameter missing/empty, or it isn't an associative array. ` +
            `Please contact Opinsys support.</p>`;

        return false;
    }

    // Ensure we have at least one data source
    if ((settings.staticData === undefined || settings.staticData === null) &&
        (settings.dynamicData === undefined || settings.dynamicData === null)) {

        this.container.innerHTML =
            `<p class="error">No data source has been defined (missing both <code>staticData</code> and <code>dynamicData</code>). ` +
            `Please contact Opinsys support.</p>`;

        return false;
    }

    // The default columns parameter MUST be correct at all times
    for (const c of settings.defaultColumns) {
        if (!(c in settings.columnDefinitions)) {
            this.container.innerHTML =
                `<p class="error">Invalid/unknown default column "${c}". The table cannot be displayed. ` +
                `Please contact Opinsys support.</p>`;

            return false;
        }
    }

    // The default sorting column and direction must be valid
    if (!(settings.defaultSorting.column in settings.columnDefinitions)) {
        const c = settings.defaultSorting.column;

        this.container.innerHTML =
            `<p class="error">Invalid/unknown default sorting column "${c}". The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;

        return false;
    }

    if (settings.defaultSorting.dir != SortOrder.ASCENDING && settings.defaultSorting.dir != SortOrder.DESCENDING) {
        this.container.innerHTML =
            `<p class="error">Invalid/unknown default sorting direction. The table cannot be displayed. ` +
            `Please contact Opinsys support.</p>`;

        return false;
    }

    return true;
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
        colButton.addEventListener("click", e => ColumnEditor.openEditor(e.target, this));
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
            toggleClass(this.container.querySelector("tr#controls div#massContainer"), "hidden", !e.target.checked);
            this.toggleArrow(e.target);
            Settings.save(this);
        });

        rowsButton.addEventListener("click", e => this.openRowsSelection(e.target));

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
    if (this.settings.enablePagination) {
        // Pagination controls
        this.ui.paging = frag.querySelector("section#paging");

        const selector = frag.querySelector("select#rowsPerPage");

        for (const preset of ROWS_PER_PAGE_PRESETS) {
            const o = create("option", { label: preset[1] });

            o.value = preset[0];
            o.selected = (preset[0] == this.paging.rowsPerPage);

            selector.appendChild(o);
        }

        this.ui.paging.querySelector("select#rowsPerPage").addEventListener("change", () => this.onRowsPerPageChanged());
        this.ui.paging.querySelector("button#first").addEventListener("click", () => this.onPageDelta(-999999));
        this.ui.paging.querySelector("button#prev").addEventListener("click", () => this.onPageDelta(-1));
        this.ui.paging.querySelector("button#next").addEventListener("click", () => this.onPageDelta(+1));
        this.ui.paging.querySelector("button#last").addEventListener("click", () => this.onPageDelta(+999999));
        this.ui.paging.querySelector("button#page").addEventListener("click", (e) => this.onJumpToPage(e.target));
    } else {
        // Remove pagination controls
        frag.querySelector("section#paging")?.remove();
    }

    // If the tools section is completely empty, remove it
    if (!this.settings.enableExport && !this.settings.enableColumnEditing && !this.settings.enableSelection)
        frag.querySelector("thead section#tools").remove();

    // Insert the empty table template on the page
    this.container.appendChild(frag);

    this.ui.controls = this.container.querySelector("thead tr#controls div#wrap div#top");
    this.ui.headers = this.container.querySelector("table.stTable thead tr#headers");
    this.ui.body = this.container.querySelector("table.stTable tbody#data");

    if (this.settings.dynamicData) {
        // Display the load animation. This gets overwritten with actual data once
        // the table is loaded. Assume the table has less than 1000 columns.
        this.ui.body.innerHTML = `<tr><td colspan="999"><img src="/images/spinner.svg" class="spinner"></td></tr>`;
    }
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
        this.enablePaginationControls(isEnabled);

    if (this.settings.enableFiltering) {
        this.ui.filters.show.disabled = !isEnabled;
        this.ui.controls.querySelector("section#filteringControls input#enabled").disabled = !isEnabled;
        this.ui.controls.querySelector("section#filteringControls input#reverse").disabled = !isEnabled;
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
    // TODO: This does not work entirely as it should. The "no-pointer-events" class applied to
    // the whole table is just a hacky workaround. But I don't know any other quick way to
    // disable all the clickable links.
    if (isEnabled) {
        this.ui.headers.classList.remove("no-text-selection", "no-pointer-events");
        this.ui.body.classList.remove("no-text-selection", "no-pointer-events");
    } else {
        this.ui.headers.classList.add("no-text-selection", "no-pointer-events");
        this.ui.body.classList.add("no-text-selection", "no-pointer-events");
    }
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
    return this.ui.body.querySelectorAll("tr");
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

        this.transformRawData(this.settings.staticData);
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

    console.log(`JSON parsing: ${performance.now() - t0} ms`);

    this.transformRawData(raw);

    console.log("parseServerResponse(): done");

    return true;
}

// Transform the received data. This is done here (and not in updateTable()) because it
// only needs to be done once, but sorting and filtering can be done multiple times
// on the transformed data.
transformRawData(incomingJSON)
{
    const t0 = performance.now();

    this.resetError();

    this.data.transformed = Data.transformRows(
        this.columns.definitions,
        incomingJSON,
        this.user.preFilterFunction
    );

    const t1 = performance.now();

    console.log(`Data transformation: ${t1 - t0} ms`);
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

    // Make sure the table knows what page to show
    this.calculatePagination();

    // Rebuild the table
    this.buildTable();

    this.updatePageCounter();
    this.enablePaginationControls();
    this.endTableUpdate();

    console.log("updateTable(): table update complete");
}

buildTable(updateMask=["headers", "rows"])
{
    const haveActions = !!this.user.actions,
          canOpen = !!this.user.open,
          currentColumn = this.sorting.column;

    // Unicode arrow characters and empirically determined padding values (their widths
    // vary slightly). These won't work unless the custom puavo-icons font is applied.
    const arrows = {
        unsorted: { asc: "\uf0dc",                 padding: 10 },
        string:   { asc: "\uf15d", desc: "\uf15e", padding: 5 },
        numeric:  { asc: "\uf162", desc: "\uf163", padding: 6 },
    };

    let customCSSColumns = new Map();

    // How many columns does the table have? Include the checkbox and actions
    // columns, if present.
    let numColumns = this.columns.current.length;

    if (this.settings.enableSelection)
        numColumns++;

    if (haveActions)
        numColumns++;

    // ----------------------------------------------------------------------------------------------
    // Construct the table parts in memory

    const t0 = performance.now();

    let headersFragment = null,
        bodyFragment = null;

    if (updateMask.includes("headers")) {
        let html = "";

        if (this.settings.enableSelection)
            html += `<th class="width-0"><span class="headerCheckbox"></span></th>`;

        for (const [index, key] of this.columns.current.entries()) {
            const def = this.columns.definitions[key];
            const sortable = (def.flags & ColumnFlag.NOT_SORTABLE) ? false : true;

            let classes = [],
                data = [["index", index], ["key", key]];

            if (!sortable)
                classes.push("cursor-default");
            else {
                classes.push("cursor-pointer");
                classes.push("sortable");
            }

            if (key == currentColumn)
                classes.push("sorted");

            data.push(["sortable", sortable ? 1 : 0]);

            html += `<th `;
            html += `title="${key}" `;
            html += data.map(d => `data-${d[0]}="${d[1]}"`).join(" ");
            html += ` class="${classes.join(' ')}">`;

            // Figure out the cell contents (title + sort direction arrow)
            const isNumeric = (def.type != ColumnType.STRING);

            if (!sortable)
                html += def.title;
            else {
                let symbol, padding;

                if (key == currentColumn) {
                    // Currently sorted by this column
                    const type = isNumeric ? "numeric" : "string",
                          dir = (this.sorting.dir == SortOrder.ASCENDING) ? "asc" : "desc";

                    symbol = arrows[type][dir];
                    padding = arrows[type].padding;
                } else {
                    symbol = arrows.unsorted.asc;
                    padding = arrows.unsorted.padding;
                }

                // Do not put newlines in this HTML! Header drag cell construction will fail otherwise!
                html += `<div><span>${def.title}</span>` +
                        `<span class="arrow" style="padding-left: ${padding}px">${symbol}</span></div>`;
            }

            html += "</th>";

            if (def.customCSS !== undefined) {
                if (Array.isArray(def.customCSS))
                    customCSSColumns.set(key, def.customCSS)
                else customCSSColumns.set(key, [def.customCSS]);
            }
        }

        // The actions column is always the last. It can't be sorted nor dragged.
        if (haveActions)
            html += `<th>${_tr('column_actions')}</th>`;

        headersFragment = new DocumentFragment();
        headersFragment.appendChild(create("tr", { id: "headers", html: html }));
    }

    const t1 = performance.now();

    if (updateMask.includes("rows")) {
        let html = "";

        if (this.data.current.length == 0) {
            // The table is empty
            html += `<tr><td colspan="${numColumns}">(${_tr('empty_table')})</td></tr>`;
        } else {
            // Calculate start and end indexes for the current page
            let start, end;

            if (this.settings.enablePagination) {
                if (this.paging.rowsPerPage == -1) {
                    start = 0;
                    end = this.data.current.length;
                } else {
                    start = this.paging.currentPage * this.paging.rowsPerPage;
                    end = Math.min((this.paging.currentPage + 1) * this.paging.rowsPerPage, this.data.current.length);
                }

                //console.log(`currentPage=${this.paging.currentPage} start=${start} end=${end}`);
            } else {
                // The table was created without pagination
                start = 0;
                end = this.data.current.length;
            }

            // These must always be updated, even when pagination is disabled
            this.paging.firstRowIndex = start;
            this.paging.lastRowIndex = end;

            for (let index = start; index < end; index++) {
                const row = this.data.transformed[this.data.current[index]];
                const rowID = row.id[INDEX_DISPLAYABLE];
                let rowClasses = [];

                if (this.data.successItems.has(rowID))
                    rowClasses.push("success");

                if (this.data.failedItems.has(rowID))
                    rowClasses.push("fail");

                html += `<tr data-index="${index}" class=${rowClasses.join(" ")}>`;

                // The checkbox
                if (this.settings.enableSelection) {
                    html += `<td class="minimize-width cursor-pointer checkbox">`;
                    html += this.data.selectedItems.has(row.id[INDEX_DISPLAYABLE]) ? `<span class="checked">` : `<span>`;
                    html += `</span></td>`;
                }

                // Data columns
                for (const column of this.columns.current) {
                    let classes = [];

                    if (column == currentColumn)
                        classes.push("sorted");

                    if (customCSSColumns.has(column))
                        classes = classes.concat(customCSSColumns.get(column));

                    if (classes.length > 0)
                        html += `<td class=\"${classes.join(' ')}\">`;
                    else html += "<td>";

                    if (row[column][INDEX_DISPLAYABLE] !== null)
                        html += row[column][INDEX_DISPLAYABLE];

                    html += "</td>";
                }

                // The actions column
                if (haveActions)
                    html += "<td>" + this.user.actions(row) + "</td>";

                html += "</tr>";
            }
        }

        bodyFragment = new DocumentFragment();
        bodyFragment.appendChild(create("tbody", { html: html, id: "data" }));
    }

    const t2 = performance.now();

    // ----------------------------------------------------------------------------------------------
    // Setup event handling

    if (updateMask.includes("headers")) {
        const headings = headersFragment.querySelectorAll("tr#headers th");

        // Header cell click handlers
        const start = this.settings.enableSelection ? 1 : 0,                // skip the checkbox column
              count = haveActions ? headings.length - 1 : headings.length;  // skip the actions column

        for (let i = start; i < count; i++)
            headings[i].addEventListener("mousedown", event => this.onHeaderMouseDown(event));
    }

    if (updateMask.includes("rows")) {
        if (this.data.current.length > 0) {
            for (const row of bodyFragment.querySelectorAll("tbody > tr")) {
                // Full row click open handlers
                if (canOpen)
                    row.addEventListener("mouseup", event => this.onRowOpen(event));

                // Row checkbox handlers
                if (this.settings.enableSelection)
                    row.childNodes[0].addEventListener("mousedown", event => this.onRowCheckboxClick(event));
            }
        }
    }

    const t3 = performance.now();

    // ----------------------------------------------------------------------------------------------
    // DOM update

    this.container.querySelector("table.stTable thead tr#controls th").colSpan = numColumns;

    if (updateMask.includes("headers")) {
        this.container.querySelector("table.stTable thead tr#headers").replaceWith(headersFragment);
        this.ui.headers = this.container.querySelector("table.stTable thead tr#headers");
    }

    if (updateMask.includes("rows")) {
        this.container.querySelector("table.stTable tbody#data").replaceWith(bodyFragment);
        this.ui.body = this.container.querySelector("table.stTable tbody#data");
    }

    const t4 = performance.now();

    // ----------------------------------------------------------------------------------------------

    console.log(`[TABLE] HTML generation: ${t1 - t0} ms`);
    console.log(`[TABLE] In-memory table construction: ${t2 - t1} ms`);
    console.log(`[TABLE] Callback setup: ${t3 - t2} ms`);
    console.log(`[TABLE] DOM replace: ${t4 - t3} ms`);
    console.log(`[TABLE] Total: ${t4 - t0} ms`);
}

// Called when a table row is middle-clicked. Uses the user-supplied callback function
// figure out the URL that is to be opened.
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

    const url = this.user.open(this.data.transformed[this.data.current[index]]);

    if (url === null || url === undefined)
        return;

    window.open(url, "_blank");
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// PAGINATION

// Calculates which page will be displayed on the next table update
calculatePagination()
{
    if (this.data.current === null || this.data.current === undefined || this.data.current.length == 0) {
        // No data at all
        this.paging.numPages = 0;
        this.paging.currentPage = 0;

        return;
    }

    if (this.paging.rowsPerPage == -1 || this.data.current.length <= this.paging.rowsPerPage) {
        // Only one page
        this.paging.numPages = 1;
        this.paging.currentPage = 0;

        return;
    }

    this.paging.numPages = (this.paging.rowsPerPage == -1) ? 1 :
        Math.ceil(this.data.current.length / this.paging.rowsPerPage);

    this.paging.currentPage =
        Math.min(Math.max(this.paging.currentPage, 0), this.paging.numPages - 1);
}

updatePageCounter()
{
    if (!this.ui.paging)
        return;

    this.ui.paging.querySelector("button#page").innerText = _tr("status.pagination", {
        current: (this.paging.numPages == 0) ? 1 : this.paging.currentPage + 1,
        total: (this.paging.numPages == 0) ? 1 : this.paging.numPages
    });
}

onRowsPerPageChanged()
{
    const selector = this.ui.paging.querySelector("select#rowsPerPage");
    const numRows = parseInt(selector.value, 10);

    console.log(`Rows per page changed to ${numRows}`);

    this.paging.rowsPerPage = numRows;
    Settings.save(this);

    const old = this.paging.numPages;

    this.calculatePagination();
    this.updatePageCounter();
    this.enablePaginationControls(true);

    if (old != this.paging.numPages && this.data.current && this.data.current.length > 0) {
        this.clearPreviousRow();
        this.buildTable();
    }
}

onPageDelta(delta)
{
    const old = this.paging.currentPage;

    this.paging.currentPage += delta;
    this.calculatePagination();

    if (this.paging.currentPage == old)
        return;

    this.updatePageCounter();
    this.enablePaginationControls(true);

    if (this.data.current && this.data.current.length > 0) {
        this.clearPreviousRow();
        this.buildTable();
    }
}

onJumpToPage(e)
{
    const template = getTemplate("jumpToPagePopup");

    // Too long strings can break the layout
    const MAX_LENGTH = 30;
    const ellipsize = (str) => (str.length > MAX_LENGTH) ? str.substring(0, MAX_LENGTH) + "…" : str;

    const col = this.sorting.column;

    // Assume string columns can contain HTML, but numeric columns won't. The values are
    // HTML-escaped when displayed, but that means HTML tags can slip through and it looks
    // really ugly.
    const index = (this.columns.definitions[col].type == ColumnType.STRING) ?
        INDEX_FILTERABLE : INDEX_DISPLAYABLE;

    let html = "";

    if (this.paging.rowsPerPage == -1) {
        // Everything on one giant page
        let first = this.data.transformed[this.data.current[0]],
            last = this.data.transformed[this.data.current[this.data.current.length - 1]];

        first = ellipsize(first[col][INDEX_EXISTS] ? first[col][index] : "-");
        last = ellipsize(last[col][INDEX_EXISTS] ? last[col][index] : "-");

        html += `<option value="1" selected}>1: ${escapeHTML(first)} → ${escapeHTML(last)}</option>`;
    } else {
        for (let page = 0; page < this.paging.numPages; page++) {
            const start = page * this.paging.rowsPerPage;
            const end = Math.min((page + 1) * this.paging.rowsPerPage, this.data.current.length);

            let first = this.data.transformed[this.data.current[start]],
                last = this.data.transformed[this.data.current[end - 1]];

            first = ellipsize(first[col][INDEX_EXISTS] ? first[col][index] : "-");
            last = ellipsize(last[col][INDEX_EXISTS] ? last[col][index] : "-");

            html += `<option value="${page}" ${page == this.paging.currentPage ? "selected" : ""} >` +
                    `${page + 1}: ${escapeHTML(first)} → ${escapeHTML(last)}</option>`;
        }
    }

    template.querySelector("select").innerHTML = html;

    template.querySelector("select").addEventListener("change", (e) => {
        // Change the row count. The popup stays open.
        const pageNum = parseInt(e.target.value, 10);

        if (pageNum != this.paging.currentPage) {
            this.paging.currentPage = pageNum;

            this.updatePageCounter();
            this.enablePaginationControls(true);

            if (this.data.current && this.data.current.length > 0) {
                this.clearPreviousRow();
                this.buildTable();
            }
        }
    });

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e);
        modalPopup.display("bottom");
        modalPopup.getContents().querySelector("select").focus();
    }
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
    this.ui.paging.querySelector("button#page").disabled = !(state && this.paging.numPages > 1);
}

isTableRowVisible(rowNum)
{
    return rowNum >= this.paging.firstRowIndex && rowNum < this.paging.lastRowIndex;
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
    this.doneAtLeastOneOperation = false;

    if (this.filters.enabled) {
        this.clearRowSelections();
        this.updateTable();
    }
}

toggleFiltersEnabled(e)
{
    this.filters.enabled = e.target.checked;
    Settings.save(this);

    this.doneAtLeastOneOperation = false;
    this.clearRowSelections();
    this.updateTable();
}

toggleFiltersReverse(e)
{
    this.filters.reverse = e.target.checked;
    Settings.save(this);

    if (this.filters.enabled) {
        this.doneAtLeastOneOperation = false;
        this.clearRowSelections();
        this.updateTable();
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MASS ROW SELECTIONS

openRowsSelection(e)
{
    let template = null;

    if (this.massRowSelectPopup) {
        // Restore previous copy
        template = this.massRowSelectPopup;
    } else {
        template = getTemplate("rowSelection");

        template.querySelector("#all").addEventListener("click", () => this.massSelectAllRows("select_all"));
        template.querySelector("#none").addEventListener("click", () => this.massSelectAllRows("deselect_all"));
        template.querySelector("#invert").addEventListener("click", () => this.massSelectAllRows("invert_selection"));
        template.querySelector("#successfull").addEventListener("click", () => this.massSelectAllRows("deselect_successfull"));

        if (this.user.massSelects.length > 0) {
            // Enable mass row selections. List available types in the selector.
            const selector = template.querySelector("select#sourceType");

            for (const m of this.user.massSelects) {
                const o = create("option");

                o.value = m[0];
                o.label = m[1];

                selector.appendChild(o);
            }

            template.querySelector("div#source").addEventListener("paste", e => {
                // Strip HTML from the pasted text (plain text only!). The thing is, the "text box" is a
                // contentEdit-enabled DIV, so it accepts HTML. If you paste data from, say, LibreOffice
                // Calc, the spreadsheet font gets embedded in it and it can actually screw up the page's
                // layout completely (I saw that happening)! That's not acceptable, so this little function
                // will hopefully remove all HTML from whatever's being pasted and leave only plain text.
                // See https://developer.mozilla.org/en-US/docs/Web/API/ClipboardEvent/clipboardData
                e.preventDefault();
                e.target.innerText = e.clipboardData.getData("text/plain");
            });

            template.querySelector("button#massRowSelect").addEventListener("click", () => this.massSelectSpecificRows(true));
            template.querySelector("button#massRowDeselect").addEventListener("click", () => this.massSelectSpecificRows(false));
        } else {
            // No row mass selections available
            template.querySelector("fieldset#massSelects").remove();
        }
    }

    if (modalPopup.create((_) => {
        // Detach the template from the popup, so we can retain its contents
        let n = modalPopup.getContents().querySelector("div.popupRows");

        this.massRowSelectPopup = n.parentElement.removeChild(n);
    })) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e, 800);
        modalPopup.display("bottom");
    }
}

// Mass select or deselect table rows
massSelectAllRows(operation)
{
    this.clearPreviousRow();
    Mass.selectAllRows(operation, this.data, this.getTableRows());
    this.doneAtLeastOneOperation = false;
    this.updateStats();
    this.updateMassButtons();
}

// Perform row mass selection
massSelectSpecificRows(state)
{
    if (this.updating || this.processing)
        return;

    const container = modalPopup.getContents().querySelector("fieldset#massSelects");

    this.clearPreviousRow();
    Mass.selectSpecificRows(container, state, this.columns, this.data, this.paging, this.getTableRows());
    this.updateStats();
    this.updateMassButtons();
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MASS OPERATIONS

clearPreviousRow()
{
    if (this.ui.previousRow) {
        this.ui.previousRow.classList.remove("previousRow");
        this.ui.previousRow = null;
    }
}

// Check/uncheck a row. If Shift is being held, perform a range checking/unchecking.
onRowCheckboxClick(e)
{
    e.preventDefault();

    if (this.updating || this.processing)
        return;

    const tr = e.target.parentNode,
          td = e.target,
          cb = tr.childNodes[0].childNodes[0];

    const index = parseInt(tr.dataset.index, 10),
          id = this.data.transformed[this.data.current[index]].id[INDEX_DISPLAYABLE];

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
        const state = this.data.selectedItems.has(this.data.transformed[this.data.current[startIndex]].id[INDEX_DISPLAYABLE]);

        if (startIndex > endIndex)
            [startIndex, endIndex] = [endIndex, startIndex];

        const tableRows = this.getTableRows();

        for (let i = startIndex; i <= endIndex; i++) {
            const id = this.data.transformed[this.data.current[i]].id[INDEX_DISPLAYABLE];
            const row = tableRows[i - this.paging.firstRowIndex],
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
        // Check/uncheck just one row
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
    this.updateStats();
    this.updateMassButtons();
}

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

    this.doneAtLeastOneOperation = false;
    this.updateStats();
    this.updateMassButtons();
}

startMassOperation()
{
    if (this.updating || this.processing)
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

    // This flag controls whether the success/fail counters will be visible after the
    // operation is done. They will be visible until the UI/selections change.
    this.doneAtLeastOneOperation = true;

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

        const tRow = this.isTableRowVisible(item.index) ?
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
                if (this.isTableRowVisible(row.index)) {
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
                const tableRow = this.isTableRowVisible(index) ? tableRows[index - this.paging.firstRowIndex] : null;

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

    if (this.updating || this.processing) {
        return;
    }

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    this.headerDrag.element = e.target;
    this.headerDrag.canSort = (e.target.dataset.sortable == "1");

    HeaderDrag.initialize(e);

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

    const table = this.container.querySelector("table.stTable");

    table.classList.remove("no-text-select", "no-pointer-events");
    document.body.classList.remove("cursor-grabbing");

    this.headerDrag.element = null;

    this.doneAtLeastOneOperation = false;

    if (this.headerDrag.active) {
        // Reorder the columns
        this.headerDrag.active = false;
        HeaderDrag.end();

        const [startIndex, endIndex] = HeaderDrag.getIndexes();

        HeaderDrag.reset();

        if (startIndex == endIndex)
            return;

        // Reorder the columns array
        this.columns.current.splice(endIndex, 0, this.columns.current.splice(startIndex, 1)[0]);

        // Reorder the table row columns. Perform an in-place swap of the two table columns,
        // it's significantly faster than regenerating the whole table.
        const t0 = performance.now();

        // Skip the checkbox column
        const skip = this.settings.enableSelection ? 1 : 0;

        const from = startIndex + skip,
              to = endIndex + skip;

        let rows = this.container.querySelector("table.stTable").rows,
            n = rows.length,
            row, cell;

        if (this.data.current.length == 0) {
            // The table is empty, so only reorder the header columns. There are two
            // header rows, but only one of the will be processed.
            n = 2;
        }

        while (n--) {
            if (n == 0)         // don't reorder the table controls row
                break;

            row = rows[n];
            cell = row.removeChild(row.cells[from]);
            row.insertBefore(cell, row.cells[to]);
        }

        const t1 = performance.now();
        console.log(`Table column swap: ${t1 - t0} ms`);

        Settings.save(this);
    } else {
        // No drag, sort the table by this column
        HeaderDrag.reset();

        if (!this.headerDrag.canSort)
            return;

        const index = e.target.dataset.index,
              key = e.target.dataset.key;

        if (key == this.sorting.column) {
            // Same column, but invert sort direction
            if (this.sorting.dir == SortOrder.ASCENDING)
                this.sorting.dir = SortOrder.DESCENDING;
            else this.sorting.dir = SortOrder.ASCENDING;
        } else {
            // Change the sort column
            this.sorting.column = key;

            if (this.columns.definitions[key].flags & ColumnFlag.DESCENDING_DEFAULT)
                this.sorting.dir = SortOrder.DESCENDING;
            else this.sorting.dir = SortOrder.ASCENDING;
        }

        Settings.save(this);

        this.clearRowSelections();
        this.updateTable();
        this.updateStats();
    }
}

// Track mouse movement. If the mouse moves "enough", initiate a header cell drag.
onHeaderMouseMove(e)
{
    e.preventDefault();

    if (this.headerDrag.active) {
        HeaderDrag.update(e);
        return;
    }

    if (!this.headerDrag.active && e.target != this.headerDrag.element) {
        // The mouse has veered away from the tracked element before enough
        // distance had been accumulated to properly trigger a drag
        const table = this.container.querySelector("table.stTable");

        document.removeEventListener("mouseup", this.onHeaderMouseUp);
        document.removeEventListener("mousemove", this.onHeaderMouseMove);

        table.classList.remove("no-text-select", "no-pointer-events");
        document.body.classList.remove("cursor-grabbing");

        this.headerDrag.element = null;
        return;
    }

    if (!HeaderDrag.begin(e, this.headerDrag.canSort, this.settings.enableSelection, this.user.actions !== null))
        return;

    // Start dragging the header cell
    const table = this.container.querySelector("table.stTable");

    table.classList.add("no-text-select", "no-pointer-events");
    document.body.classList.add("cursor-grabbing");

    this.headerDrag.active = true;
    HeaderDrag.update(e);
}

}   // class SuperTable
