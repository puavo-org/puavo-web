/*
jarmo@toimisto-jarmo:~/palvelin$ node_modules/.bin/esbuild --bundle --outdir=app/static/js app/javascript/supertable3.js app/javascript/puavoconf_editor.js app/javascript/import_tool.js --target=es2020 --minify --watch --sourcemap --charset=utf8

((uid = /^test.user.[0-9a-fA-F]+$/ || uid = "jarmo") && !locked != 0) || rrt >= "2010-01-01 00:00:00"
*/

import { TableFlag, ColumnFlag, ColumnType, SortOrder, INDEX_EXISTS, INDEX_DISPLAYABLE, INDEX_FILTERABLE, INDEX_SORTABLE } from "./constants.js";
import { _tr, escapeHTML } from "../../common/utils.js";
import { create, destroy, getTemplate } from "../../common/dom.js";
import { transformRawData, filterData, sortData } from "./data.js";
import { MassOperationFlags, MassOperation } from "./mass_operations.js";
import { FilterEditor } from "../filters/editor/fe_main.js";

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

// Pagination counts. Each entry is formatted as [row count, title]. -1 displays all rows.
const ROWS_PER_PAGE_PRESETS = [
    [-1, "∞"],
    [5, "5"],
    [10, "10"],
    [20, "20"],
    [25, "25"],
    [50, "50"],
    [100, "100"],
    [200, "200"],
    [250, "250"],
    [500, "500"],
    [1000, "1000"],
    [2000, "2000"],
    [2500, "2500"],
    [5000, "5000"],
];

// How many rows are displayed by default
const DEFAULT_ROWS_PER_PAGE = 100;

export class SuperTable {

constructor(container, settings)
{
    this.id = settings.id;
    this.container = container;

    // ----------------------------------------------------------------------------------------------
    // Validate the parameters. These will explode loudly and completely prevent the table
    // from even appearing. That's intentional. These should be caught in development/testing.

    if (this.container === null || this.container === undefined) {
        console.error("The container DIV element is null or undefined");
        window.alert("The table container DIV is null or undefined. The table cannot be displayed. " +
                     "Please contact Opinsys support.");
        return;
    }

    if (settings.columnDefinitions === undefined ||
        settings.columnDefinitions === null ||
        typeof(settings.columnDefinitions) != "object" ||
        Object.keys(settings.columnDefinitions).length == 0) {

        this.container.innerHTML =
            `<p class="error">The settings.columnDefinitions parameter missing/empty, or it isn't an associative array. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    if (settings.columnTitles === undefined ||
        settings.columnTitles === null ||
        typeof(settings.columnTitles) != "object" ||
        Object.keys(settings.columnTitles).length == 0) {

        this.container.innerHTML =
            `<p class="error">The settings.columnTitles parameter missing/empty, or it isn't an associative array. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    if (settings.defaultColumns === undefined ||
        settings.defaultColumns === null ||
        !Array.isArray(settings.defaultColumns) ||
        settings.defaultColumns.length == 0) {

        this.container.innerHTML =
            `<p class="error">The settings.defaultColumn parameter missing/empty, or it isn't an array. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    if (settings.defaultSorting === undefined ||
        settings.defaultSorting === null ||
        typeof(settings.defaultSorting) != "object" ||
        settings.defaultSorting.length == 0) {

        this.container.innerHTML =
            `<p class="error">The settings.defaultSorting parameter missing/empty, or it isn't an associative array. ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    // Ensure we have at least one data source
    if ((settings.staticData === undefined || settings.staticData === null) &&
        (settings.dynamicData === undefined || settings.dynamicData === null)) {

        this.container.innerHTML =
            `<p class="error">No data source has been defined (missing both <code>staticData</code> and <code>dynamicData</code>). ` +
            `Please contact Opinsys support.</p>`;

        return;
    }

    // The default columns parameter MUST be correct at all times
    for (const c of settings.defaultColumns) {
        if (!(c in settings.columnDefinitions)) {
            this.container.innerHTML =
                `<p class="error">Invalid/unknown default column "${c}". The table cannot be displayed. ` +
                `Please contact Opinsys support.</p>`;

            return;
        }
    }

    // The default sorting column and direction must be valid
    if (!(settings.defaultSorting.column in settings.columnDefinitions)) {
        const c = settings.defaultSorting.column;

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

    // Direct handles to various user interface elements. Cleaner than using
    // querySelector() everywhere.
    this.ui = {
        controls: null,         // the controls above the header cells
        headers: null,          // the table header cells
        body: null,             // the actual table body

        filters: {
            show: null,         // show/hide checkbox
            enabled: null,      // enabled checkbox
            reverse: null,      // reverse checkbox
        },

        mass: {
            show: null,         // show/hide checkbox
            proceed: null,
            progress: null,
            counter: null,
        },

        // The pagination controls section
        paging: null,

        // The previously clicked table row. Can be null. Used when doing Shift+click
        // range selections.
        previousRow: null,
    };

    this.filterEditor = null;       // a child class that implements the filter editor

    // Current mass operation data
    this.massOperation = {
        index: -1,          // index to the settings.massOperations[] array
        handler: null,      // the user-supplied handler class that actually does the mass operation
        singleShot: false,  // true if the operation processes all rows at once
    };

    // Table column header dragging state
    this.headerDrag = {
        active: false,              // true if a cell is currently being dragged
        canSort: false,             // true if the dragged cell (column) is sortable
        element: null,              // the original TH where the drag originated from
        startingMousePos: null,     // initial drag mouse position
        startIndex: null,           // source column
        endIndex: null,             // destination column
        cellPositions: null,        // array of [x, y, w, h] table header cell rectangles
        offset: null,               // delta from 'element' to the mouse position ([dx, dy])
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

    // Header drag callback functions. "bind()" is needed to get around some weird
    // JS scoping garbage I don't understand.
    this.onHeaderMouseDown = this.onHeaderMouseDown.bind(this);
    this.onHeaderMouseUp = this.onHeaderMouseUp.bind(this);
    this.onHeaderMouseMove = this.onHeaderMouseMove.bind(this);

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
        preFilterFunction: typeof(settings.preFilterFunction) == "function" ? settings.preFilterFunction : null,
        massOperations: Array.isArray(settings.massOperations) ? settings.massOperations : [],
        massSelects: Array.isArray(settings.massSelects) ? settings.massSelects : [],
        show: [],                                       // which expanding tool panes are open (names)
    };

    this.columns = {
        definitions: settings.columnDefinitions,
        titles: settings.columnTitles,
        order: settings.columnOrder || [],
        defaults: [...settings.defaultColumns],
        current: [...settings.defaultColumns],      // overridden if saved settings exist
        defaultSorting: settings.defaultSorting,
    };

    this.sorting = {...settings.defaultSorting};    // overridden if saved settings exist

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
        rowsPerPage: DEFAULT_ROWS_PER_PAGE,         // -1 = "show all at once"
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

    if (this.settings.flags & TableFlag.ENABLE_FILTERING) {
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

    this.saveSettings();
    this.enableUI(false);

    if (settings.staticData) {
        // Static data, only one load
        this.beginTableUpdate();

        this.data.transformed = transformRawData(
            this.columns.definitions,
            this.settings.userTransforms,
            settings.staticData,
            this.settings.preFilterFunction
        );

        this.updating = false;
        this.updateTable();
        this.enableTable(true);
        this.enableUI(true);
    } else {
        // Dynamic data, potentially on-the-fly reloads
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

    this.loadSettingsObject(stored);
}

// Saves the current settings to LocalStore
saveSettings()
{
    localStorage.setItem(`table-${this.id}-settings`, JSON.stringify(this.getSettingsObject()));
}

// Loads settings from an object that was (hopefully) constructed by deserializing JSON.
// Some items are processed multiple times for backwards compatibility.
loadSettingsObject(stored)
{
    // Restore open panes
    if ("show" in stored && typeof(stored.show) == "string")
        this.settings.show = stored.show.split(",");

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

            if (c in this.columns.definitions)
                valid.push(c);
        }

        // There must always be at least one visible column
        if (valid.length > 0)
            this.columns.current = valid;
    }

    // Restore sorting and sorting direction
    if ("sorting" in stored) {
        // Restore these only if they're valid
        if (stored.sorting.column in this.columns.definitions)
            this.sorting.column = stored.sorting.column;
        else console.warn(`The stored sorting column "${stored.sorting.column}" isn't valid, using default`);

        if (stored.sorting.dir == SortOrder.ASCENDING || stored.sorting.dir == SortOrder.DESCENDING)
            this.sorting.dir = stored.sorting.dir;
    } else if ("sort_by" in stored) {
        // TODO: Support multiple sorting columns. The format supports them,
        // but we currently use only the first.
        let sortBy = stored.sort_by.split(";")[0];

        if (sortBy != "") {
            const [by, dir] = sortBy.split(",");

            if (by in this.columns.definitions)
                this.sorting.column = by;
            else console.warn(`The stored sorting column "${by}" isn't valid, using default`);

            if (dir == SortOrder.ASCENDING || dir == SortOrder.DESCENDING)
                this.sorting.dir = dir;
        }
    }

    // Restore filter settings
    if ("filtersEnabled" in stored && typeof(stored.filtersEnabled) == "boolean")
        this.filters.enabled = stored.filtersEnabled;
    else if ("filter" in stored && typeof(stored.filter) == "boolean")
        this.filters.enabled = stored.filter;

    if ("filtersReverse" in stored && typeof(stored.filtersReverse) == "boolean")
        this.filters.reverse = stored.filtersReverse;
    else if ("reverse" in stored && typeof(stored.reverse) == "boolean")
        this.filters.reverse = stored.reverse;

    if ("advanced" in stored && typeof(stored.advanced) == "boolean")
        this.filters.advanced = stored.advanced;

    let tryToLoadOldFilters = false;

    if ("filters" in stored && typeof(stored.filters) == "string") {
        try {
            this.filters.filters = JSON.parse(stored.filters);
        } catch (e) {
            // Okay
            this.filters.filters = null;
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
                    this.filters.filters = [...converted];

                // Purge the old filters, they're no longer needed
                localStorage.removeItem(`table-${this.id}-filters`);
            } catch (e) {
                console.error("Failed to convert the old filters:");
                console.error(e);
            }
        }
    }

    if ("filters_string" in stored && typeof(stored.filters_string) == "string")
        this.filters.string = stored.filters_string;

    // Restore pagination settings
    if ("rows_per_page" in stored && typeof(stored.rows_per_page) == "number") {
        let found = false;

        // Validate the stored setting. Only allow predefined values.
        for (const r of ROWS_PER_PAGE_PRESETS) {
            if (r[0] == stored.rows_per_page) {
                this.paging.rowsPerPage = stored.rows_per_page;
                found = true;
                break;
            }
        }

        if (!found)
            this.paging.rowsPerPage = DEFAULT_ROWS_PER_PAGE;
    }

    return true;
}

// Constructs an object that contains all the current settings. If 'full' is false, then
// some "non-essential" items are omitted from it (used in settings JSON import/export).
getSettingsObject(full=true)
{
    let filters = null;

    if (Array.isArray(this.filters.filters))
        filters = JSON.stringify(this.filters.filters, null, "");

    let show = [];

    if (this.ui.filters.show && this.ui.filters.show.checked)
        show.push("filters");

    if (this.ui.mass.show && this.ui.mass.show.checked)
        show.push("mass");

    let settings = {
        show: show.join(","),
        columns: this.columns.current.join(","),
        sort_by: `${this.sorting.column},${this.sorting.dir}`,
        filter: this.filters.enabled,
        reverse: this.filters.reverse,
        advanced: this.filters.advanced,
        filters: filters,
        filters_string: typeof(this.filters.string) == "string" ? this.filters.string : "",
        rows_per_page: this.paging.rowsPerPage,
    };

    return settings;
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

    // Setup event handling for the elements that are visible
    if (!(this.settings.flags & TableFlag.DISABLE_TOOLS))
        frag.querySelector("thead div#top button#export").addEventListener("click", (e) => this.clickedExport(e.target));

    if (this.settings.flags & TableFlag.ENABLE_COLUMN_EDITING)
        frag.querySelector("thead div#top button#columns").addEventListener("click", (e) => this.clickedColumns(e.target));

    if (this.settings.flags & TableFlag.ENABLE_FILTERING) {
        this.ui.filters.show = frag.querySelector("thead section input#editor");

        frag.querySelector("thead div#top input#editor").addEventListener("click", (e) => {
            this.filterEditor.setVisibility(e.target.checked);
            this.saveSettings();
        });

        this.ui.filters.enabled = frag.querySelector(`thead section#filteringControls input#enabled`);
        this.ui.filters.reverse = frag.querySelector(`thead section#filteringControls input#reverse`);

        this.ui.filters.enabled.checked = this.filters.enabled;
        this.ui.filters.reverse.checked = this.filters.reverse;

        this.ui.filters.enabled.addEventListener("click", () => this.toggleFiltersEnabled());
        this.ui.filters.reverse.addEventListener("click", () => this.toggleFiltersReverse());

        // Construct the filter editor
        this.filterEditor = new FilterEditor(this,
                                             frag.querySelector("thead div#filteringContainer"),
                                             frag.querySelector("thead div#filteringPreview"),
                                             this.columns.definitions,
                                             this.columns.titles,
                                             this.filters.presets,
                                             this.filters.defaults,
                                             this.filters.advanced);

        // Expand the tool pane immediately
        if (this.settings.show.includes("filters")) {
            this.ui.filters.show.checked = true;
            this.filterEditor.setVisibility(true);
        }
    }

    if (this.settings.flags & TableFlag.ENABLE_SELECTION) {
        frag.querySelector("thead div#top input#mass").addEventListener("click", (e) => {
            let c = this.container.querySelector("tr#controls div#massContainer");

            if (e.target.checked)
                c.classList.remove("hidden");
            else c.classList.add("hidden");

            this.saveSettings();
        });

        this.ui.mass.show = frag.querySelector("thead section input#mass");

        let mass = frag.querySelector("thead div#massContainer");

        mass.querySelector("#all").addEventListener("click", () => this.massSelectAllRows("select_all"));
        mass.querySelector("#none").addEventListener("click", () => this.massSelectAllRows("deselect_all"));
        mass.querySelector("#invert").addEventListener("click", () => this.massSelectAllRows("invert_selection"));
        mass.querySelector("#successfull").addEventListener("click", () => this.massSelectAllRows("deselect_successfull"));

        if (this.settings.massSelects.length > 0) {
            // Enable mass row selections. List available types in the selector.
            let selector = mass.querySelector("div#massSelects select#selectType");

            for (const m of this.settings.massSelects) {
                let o = create("option");

                o.dataset.id = m[0];
                o.label = m[1];
                selector.appendChild(o);
            }

            mass.querySelector("div#source").addEventListener("paste", (e) => this.massSelectFilterPaste(e));
            mass.querySelector("button#massRowSelect").addEventListener("click", () => this.massSelectSpecificRows(true));
            mass.querySelector("button#massRowDeselect").addEventListener("click", () => this.massSelectSpecificRows(false));
        } else {
            // No row mass selections available
            frag.querySelector("thead div#massContainer fieldset#massSelects")?.remove();
        }

        // List the available mass operations
        let selector = mass.querySelector("fieldset div.massControls select.operation");

        for (const m of this.settings.massOperations) {
            let o = create("option");

            o.dataset.id = m.id;
            o.label = m.title;

            selector.appendChild(o);
        }

        mass.querySelector("div.massControls > select").addEventListener("change", (e) => this.switchMassOperation(e));

        this.ui.mass.proceed = mass.querySelector("div.massControls > button");
        this.ui.mass.progress = mass.querySelector("div.massControls > progress");
        this.ui.mass.counter = mass.querySelector("div.massControls > span.counter");

        this.ui.mass.proceed.addEventListener("click", () => this.doMassOperation());

        // Expand the tool pane immediately
        if (this.settings.show.includes("mass")) {
            this.ui.mass.show.checked = true;
            frag.querySelector("tr#controls div#massContainer").classList.remove("hidden");
        }
    } else {
        // Remove the mass tools checkbox
        frag.querySelector("tr#controls section#massSpan").remove();
    }

    if (this.settings.flags & TableFlag.ENABLE_PAGINATION) {
        // Pagination controls
        this.ui.paging = frag.querySelector("section#paging");

        const selector = frag.querySelector("select#rowsPerPage");

        for (const preset of ROWS_PER_PAGE_PRESETS) {
            let o = create("option", { label: preset[1] });

            o.dataset.rows = preset[0];
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

    // Insert the empty table template on the page
    this.container.appendChild(frag);

    this.ui.controls = this.container.querySelector("thead tr#controls div#wrap div#top");
    this.ui.headers = this.container.querySelector("table.stTable thead tr#headers");
    this.ui.body = this.container.querySelector("table.stTable tbody#data");

    // Display the load animation. This gets overwritten with actual data once
    // the table is loaded. Assume the table has less than 1000 columns.
    this.ui.body.innerHTML = `<tr><td colspan="999"><img src="/images/spinner.svg" class="spinner"></td></tr>`;
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

    parts.push(_tr("status.visible_rows", { visible: visibleRows, total: totalRows }));
    parts.push(_tr("status.filtered_rows", { count: totalRows - visibleRows }));

    if (this.settings.flags & TableFlag.ENABLE_SELECTION) {
        parts.push(_tr("status.selected_rows", { count: this.data.selectedItems.size }));

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
    if (!(this.settings.flags & TableFlag.DISABLE_EXPORT))
        this.container.querySelector(`button#export`).disabled = !isEnabled;

    if (this.settings.flags & TableFlag.ENABLE_COLUMN_EDITING)
        this.container.querySelector(`button#columns`).disabled = !isEnabled;

    if (this.settings.flags & TableFlag.ENABLE_PAGINATION)
        this.enablePaginationControls(isEnabled);

    if (this.settings.flags & TableFlag.ENABLE_FILTERING) {
        this.ui.filters.show.disabled = !isEnabled;
        this.ui.filters.enabled.disabled = !isEnabled;
        this.ui.filters.reverse.disabled = !isEnabled;
        this.filterEditor.enableOrDisable(isEnabled);
    }

    if (this.settings.flags & TableFlag.ENABLE_SELECTION) {
        this.ui.mass.show.disabled = !isEnabled;

        this.container.querySelector("div.massControls select").disabled = !isEnabled;
        this.ui.mass.proceed.disabled = !isEnabled;

        for (let b of this.container.querySelectorAll("div#massSelects button"))
            b.disabled = !isEnabled;

        this.ui.mass.proceed.disabled = !isEnabled && this.data.selectedItems.size == 0;
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

    e.innerText = "";
    e.classList.add("hidden");
}

setStatus(text)
{
    this.container.querySelector("table.stTable thead tr#controls section#stats").innerText = text;
}

// Retrieves the actual table rows
getTableRows()
{
    return this.ui.body.querySelectorAll("tr");
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// EXPORT

clickedExport(e)
{
    const template = getTemplate("exportPopup");

    template.querySelector(`button#btnCSV`).addEventListener("click", (e) => this.exportTable("csv"));
    template.querySelector(`button#btnJSON`).addEventListener("click", (e) => this.exportTable("json"));

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e);
        modalPopup.display("bottom");
    }
}

// Download table contents. Format must be "csv" or "json".
exportTable(format)
{
    try {
        const visibleRows = modalPopup.getContents().querySelector("input#only-visible-rows").checked,
              visibleCols = modalPopup.getContents().querySelector("input#only-visible-cols").checked;

        const source = visibleRows ? this.data.current : this.data.transformed;

        let output = [],
            mimetype, extension;

        const columns = visibleCols ?
            this.columns.current :
            Object.keys(this.columns.definitions);

        let headers = [...columns];

        // Optional export alias names
        for (let i = 0; i < headers.length; i++) {
            const def = this.columns.definitions[headers[i]];

            if (def.export_name)
                headers[i] = def.export_name;
        }

        switch (format) {
            case "csv":
            default: {
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

                break;
            }

            case "json": {
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

                break;
            }
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
        window.alert(_tr("export_failed", { error: e }));
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// COLUMN EDITING

// Column reordering by header dragging is located later in this file

// Open the column editor popup
clickedColumns(e)
{
    // Sort the columns alphabetically by their localized names
    const columnNames =
        Object.keys(this.columns.definitions)
        .map((key) => [key, this.columns.titles[key]])
        .sort((a, b) => { return a[1].localeCompare(b[1]) });

    const current = new Set(this.columns.current);

    let html = "";

    for (const c of columnNames) {
        const def = this.columns.definitions[c[0]];
        let cls = ["item"];

        if (current.has(c[0]))
            cls.push("selected");

        html += `<div data-column="${c[0]}" class="${cls.join(' ')}">`;

        if (current.has(c[0]))
            html += `<input type="checkbox" checked></input>`;
        else html += `<input type="checkbox"></input>`;

        html += `${c[1]} (<span class="columnName">${c[0]}</span>)</div>`;
    }

    const template = getTemplate("columnsPopup");

    template.querySelector("div#columnList").innerHTML = html;

    for (let i of template.querySelectorAll(`div#columnList .item`))
        i.addEventListener("click", (e) => this.toggleColumn(e.target));

    template.querySelector(`input[type="search"]`).addEventListener("input", (e) => this.filterColumnList(e));
    template.querySelector("button#save").addEventListener("click", () => this.saveColumns());
    template.querySelector("button#reset").addEventListener("click", () => this.resetColumns());
    template.querySelector("button#selectAll").addEventListener("click", () => this.allColumns(true));
    template.querySelector("button#deselectAll").addEventListener("click", () => this.allColumns(false));
    template.querySelector("button#resetOrder").addEventListener("click", () => this.resetColumnOrder());

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e);
        modalPopup.display("bottom");

        this.updateColumnEditor();
        modalPopup.getContents().querySelector(`input[type="search"]`).focus();
    }
}

getColumnList(selected)
{
    const path = "div#columnList > div";

    return modalPopup.getContents().querySelectorAll(selected ? path + ".selected" : path);
}

// Check/uncheck the column on the list
toggleColumn(target)
{
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
    // Make a list of new visible columns
    let newVisible = new Set();

    for (let c of this.getColumnList(true))
        if (c.classList.contains("selected"))
            newVisible.add(c.dataset.column);

    // Keep the existing columns in whatever order they were, but remove
    // hidden columns
    let newColumns = [];

    for (const col of this.columns.current) {
        if (newVisible.has(col)) {
            newColumns.push(col);
            newVisible.delete(col);
        }
    }

    // Then tuck the new columns at the end of the array
    for (const col of newVisible)
        newColumns.push(col);

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

    this.unsavedColumns = false;
    this.updateColumnEditor();
    this.saveSettings();
    this.updateTable();
}

resetColumns()
{
    const initial = new Set(this.columns.defaults);

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
    const current = new Set(this.columns.current);
    let nc = [];

    for (const c of this.columns.order)
        if (current.has(c))
            nc.push(c);

    this.columns.current = nc;

    this.saveSettings();
    this.updateTable();
}

updateColumnEditor()
{
    const numSelected = this.getColumnList(true).length;
    let saveButton = modalPopup.getContents().querySelector("button#save")

    if (numSelected == 0)
        saveButton.disabled = true;
    else saveButton.disabled = !this.unsavedColumns;

    modalPopup.getContents().querySelector("div#columnStats").innerText = _tr("status.column_stats", {
        selected: numSelected,
        total: Object.keys(this.columns.definitions).length
    });
}

filterColumnList(e)
{
    const filter = e.target.value.trim().toLowerCase();

    // The list is not rebuilt when searching, we just change item visibilities.
    // This way, searching for something else does not undo previous changes
    // if they weren't saved yet.
    for (let c of this.getColumnList()) {
        const title = this.columns.titles[c.dataset.column];

        if (filter && title.toLowerCase().indexOf(filter) == -1)
            c.classList.add("hidden");
        else c.classList.remove("hidden");
    }
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

    const numRows = parseInt(selector.options[selector.selectedIndex].dataset.rows, 10);

    console.log(`Rows per page changed to ${numRows}`);

    this.paging.rowsPerPage = numRows;
    this.saveSettings();

    const old = this.paging.numPages;

    this.calculatePagination();
    this.updatePageCounter();
    this.enablePaginationControls(true);

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

    this.updatePageCounter();
    this.enablePaginationControls(true);

    if (this.data.current && this.data.current.length > 0)
        this.buildTable();
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
        let first = this.data.current[0],
            last = this.data.current[this.data.current.length - 1];

        first = ellipsize(first[col][INDEX_EXISTS] ? first[col][index] : "-");
        last = ellipsize(last[col][INDEX_EXISTS] ? last[col][index] : "-");

        html += `<option selected}>1: ${escapeHTML(first)} → ${escapeHTML(last)}</option>`;
    } else {
        for (let page = 0; page < this.paging.numPages; page++) {
            const start = page * this.paging.rowsPerPage;
            const end = Math.min((page + 1) * this.paging.rowsPerPage, this.data.current.length);

            let first = this.data.current[start],
                last = this.data.current[end - 1];

            first = ellipsize(first[col][INDEX_EXISTS] ? first[col][index] : "-");
            last = ellipsize(last[col][INDEX_EXISTS] ? last[col][index] : "-");

            html += `<option ${page == this.paging.currentPage ? "selected" : ""} ` +
                    `data-page="${page}">${page + 1}: ${escapeHTML(first)} → ${escapeHTML(last)}</option>`;
        }
    }

    template.querySelector("select").innerHTML = html;

    template.querySelector("select").addEventListener("change", (e) => {
        // Change the page. The popup stays open.
        const pageNum = parseInt(e.target.options[e.target.selectedIndex].dataset.page, 10);

        if (pageNum != this.paging.currentPage) {
            this.paging.currentPage = pageNum;

            this.updatePageCounter();
            this.enablePaginationControls(true);

            if (this.data.current && this.data.current.length > 0)
                this.buildTable();
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

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// FILTERS

// Called from the filter editor whenever a change to the filters have been made
saveFilters()
{
    this.filters.filters = this.filterEditor.getTraditionalFilters();
    this.filters.string = this.filterEditor.getAdvancedFilter();
    this.filters.advanced = this.filterEditor.isAdvancedMode();

    this.saveSettings();
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

toggleFiltersEnabled()
{
    this.filters.enabled = this.ui.filters.enabled.checked;
    this.doneAtLeastOneOperation = false;
    this.saveSettings();
    this.clearRowSelections();
    this.updateTable();
}

toggleFiltersReverse()
{
    this.filters.reverse = this.ui.filters.reverse.checked;
    this.saveSettings();

    if (this.filters.enabled) {
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
    if (operation == "select_all") {
        this.data.selectedItems.clear();

        for (const i of this.data.current)
            this.data.selectedItems.add(i.id[INDEX_DISPLAYABLE]);

        this.data.successItems.clear();
        this.data.failedItems.clear();
    } else if (operation == "deselect_all") {
        this.data.selectedItems.clear();
        this.data.successItems.clear();
        this.data.failedItems.clear();
    } else if (operation == "invert_selection") {
        let newState = new Set();

        for (const i of this.data.current)
            if (!this.data.selectedItems.has(i.id[INDEX_DISPLAYABLE]))
                newState.add(i.id[INDEX_DISPLAYABLE]);

        this.data.selectedItems = newState;
        this.data.successItems.clear();
        this.data.failedItems.clear();
    } else if (operation == "deselect_successfull") {
        for (const id of this.data.successItems)
            this.data.selectedItems.delete(id);

        this.data.successItems.clear();
    }

    // Rebuilding the table is too slow, so modify the checkbox cells directly
    for (let row of this.getTableRows()) {
        let cb = row.childNodes[0].childNodes[0];

        switch (operation) {
            case "select_all":
                cb.classList.add("checked");
                row.classList.remove("success", "fail");
                break;

            case "deselect_all":
                cb.classList.remove("checked");
                row.classList.remove("success", "fail");
                break;

            case "invert_selection":
                if (cb.classList.contains("checked"))
                    cb.classList.remove("checked");
                else cb.classList.add("checked");

                row.classList.remove("success", "fail");
                break;

            case "deselect_successfull":
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

    let container = this.container.querySelector("div#source");

    // Source data type
    const selector = this.container.querySelector("select#selectType");
    const type = selector.options[selector.selectedIndex].dataset.id;
    const numeric = this.columns.definitions[type].type != ColumnType.STRING;

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

    this.container.querySelector("div#massRowSelectStatus").innerText =
        _tr('status.mass_row_status', {
            total: entries.size,
            match: found.size,
            unmatched: entries.size - found.size
        });

    this.updateUI();
}

// Called when the selected mass operation changes
switchMassOperation(e)
{
    const index = e.target.selectedIndex - 1;
    const def = this.settings.massOperations[index];

    let fieldset = this.container.querySelector("table.stTable thead div#massContainer fieldset#settings"),
        container = fieldset.querySelector("div#ui");

    // Instantiate a new class
    this.massOperation.index = index;
    this.massOperation.handler = new def.cls(this, container);
    this.massOperation.singleShot = def.flags & MassOperationFlags.SINGLESHOT;

    // Hide/swap the UI
    container.innerText = "";

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
        ctx.enableUI(isEnabled);

        // Disable the mass row select controls
        // FIXME: The content-editable source DIV cannot be disabled this way
        for (let b of ctx.container.querySelector("div#massContainer div#massSelects").querySelectorAll("button, input, select"))
            b.disabled = !isEnabled;

        ctx.ui.mass.proceed.disabled = !isEnabled;

        ctx.enableTable(isEnabled);
    }

    function beginOperation(ctx, numItems)
    {
        enableMassUI(ctx, false);

        ctx.ui.mass.progress.setAttribute("max", numItems);
        ctx.ui.mass.progress.setAttribute("value", 0);
        ctx.ui.mass.progress.classList.remove("hidden");
        ctx.ui.mass.counter.innerHTML = _tr("status.mass_progress", { count: 0, total: numItems, success: 0, fail: 0 });
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
        ctx.ui.mass.counter.innerHTML = _tr("status.mass_progress", {
            count: currentItem,
            total: numItems,
            success: ctx.data.successItems.size,
            fail: ctx.data.failedItems.size
        });
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
    let sequence = Promise.resolve();

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
// SORTING AND COLUMN HEADER REORDERING

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

        if (key == this.sorting.column) {
            if (this.sorting.dir == SortOrder.ASCENDING)
                this.sorting.dir = SortOrder.DESCENDING;
            else this.sorting.dir = SortOrder.ASCENDING;
        } else {
            this.sorting.column = key;

            if (this.columns.definitions[key].flags & ColumnFlag.DESCENDING_DEFAULT)
                this.sorting.dir = SortOrder.DESCENDING;
            else this.sorting.dir = SortOrder.ASCENDING;
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
        // How and why did we even get here?
        return;
    }

    // Reorder the columns array
    this.columns.current.splice(this.headerDrag.endIndex, 0, this.columns.current.splice(this.headerDrag.startIndex, 1)[0]);

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
        // The table is empty, so only reorder the header columns. There are two
        // header rows, but only one of the will be processed.
        n = 2;
    }

    while (n--) {
        if (n == 0)     // don't reorder the topmost row which contains the controls
            break;

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
    this.updating = true;
    this.enableUI(false);
    this.enableTable(false);
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

    this.resetError();

    // Transform the received data. This is done here (and not in updateTable()) because it
    // only needs to be done once, but sorting and filtering can be done multiple times
    // on the transformed data.
    const t1 = performance.now();

    this.data.transformed = transformRawData(
        this.columns.definitions,
        this.settings.userTransforms,
        raw,
        this.settings.preFilterFunction
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
        this.filters.enabled &&
        this.filters.program) {

        filtered = filterData(this.columns.definitions,
                              this.data.transformed,
                              this.filters.program,
                              this.filters.reverse);
    } else {
        // Filtering is not enabled, pass the data through
        filtered = [...this.data.transformed];
    }

    const t1 = performance.now();

    // Sort
    const t2 = performance.now();
    this.data.current = sortData(this.columns.definitions, this.sorting,
                                 this.collator, filtered);
    const t3 = performance.now();

    console.log(`Data filtering: ${t1 - t0} ms`);
    console.log(`Data sorting: ${t3 - t2} ms`);

    // Make sure the table knows what page to show
    this.calculatePagination();

    // Rebuild the table
    this.buildTable();

    this.updatePageCounter();
    this.enablePaginationControls();

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
    // TODO: This does not work entirely as it should. The controls are disabled, but
    // the busy cursor / text selection prevention does not work properly. The "no-pointer-events"
    // class applied to the whole container is just a hacky workaround.
    if (isEnabled) {
        this.ui.headers.classList.remove("no-text-selection", "cursor-wait");
        this.ui.body.classList.remove("no-text-selection", "cursor-wait");
        this.container.classList.remove("no-pointer-events");
    } else {
        this.ui.headers.classList.add("no-text-selection", "cursor-wait");
        this.ui.body.classList.add("no-text-selection", "cursor-wait");
        this.container.classList.add("no-pointer-events");
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

buildTable(updateMask=["headers", "rows"])
{
    const haveActions = !!this.settings.actionsCallback,
          canSelect = this.settings.flags & TableFlag.ENABLE_SELECTION,
          canOpen = !!this.settings.openCallback,
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

    if (canSelect)
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

        if (canSelect)
            html += `<th class="width-0"><span class="headerCheckbox"></span></th>`;

        for (const [index, key] of this.columns.current.entries()) {
            const def = this.columns.definitions[key];

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
                html += `${this.columns.titles[key]}`;
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
                html += `<div><span>${this.columns.titles[key]}</span>` +
                        `<span class="arrow" style="padding-left: ${padding}px">${symbol}</span></div>`;
            }

            html += "</th>";

            if (def.flags & ColumnFlag.CUSTOM_CSS)
                customCSSColumns.set(key, def.cssClass);
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

            if (this.settings.flags & TableFlag.ENABLE_PAGINATION) {
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
                for (const column of this.columns.current) {
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

        bodyFragment = new DocumentFragment();
        bodyFragment.appendChild(create("tbody", { html: html, id: "data" }));
    }

    const t2 = performance.now();

    // ----------------------------------------------------------------------------------------------
    // Setup event handling

    if (updateMask.includes("headers")) {
        let headings = headersFragment.querySelectorAll("tr#headers th");

        // Header cell click handlers
        const start = canSelect ? 1 : 0,                                    // skip the checkbox column
              count = haveActions ? headings.length - 1 : headings.length;  // skip the actions column

        for (let i = start; i < count; i++)
            headings[i].addEventListener("mousedown", event => this.onHeaderMouseDown(event));
    }

    if (updateMask.includes("rows")) {
        if (this.data.current.length > 0) {
            for (let row of bodyFragment.querySelectorAll("tbody > tr")) {
                // Full row click open handlers
                if (canOpen)
                    row.addEventListener("mouseup", event => this.onRowOpen(event));

                // Row checkbox handlers
                if (canSelect)
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

}   // class SuperTable
