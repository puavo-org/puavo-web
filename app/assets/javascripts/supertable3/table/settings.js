import {
    SortOrder,
    ROWS_PER_PAGE_PRESETS,
    DEFAULT_ROWS_PER_PAGE
} from "./constants.js";


// Loads settings from an object that was (hopefully) constructed by deserializing JSON.
// Some items are processed multiple times for backwards compatibility.
function _loadSettingsObject(cls, stored)
{
    // Restore open panes
    if ("show" in stored && typeof(stored.show) == "string")
        cls.settings.show = stored.show.split(",");

    // Restore currently visible columns and their order
    let columns = null;

    if ("columns" in stored) {
        if (Array.isArray(stored.columns))
            columns = stored.columns;
        else if (typeof(stored.columns) == "string")
            columns = stored.columns.split(",").map(i => i.trim()).filter(e => e != "");
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

            if (c in cls.columns.definitions)
                valid.push(c);
        }

        // There must always be at least one visible column
        if (valid.length > 0)
            cls.columns.current = valid;
    }

    // Restore sorting and sorting direction
    if ("sorting" in stored) {
        // Restore these only if they're valid
        if (stored.sorting.column in cls.columns.definitions)
            cls.sorting.column = stored.sorting.column;
        else console.warn(`The stored sorting column "${stored.sorting.column}" isn't valid, using default`);

        if (stored.sorting.dir == SortOrder.ASCENDING || stored.sorting.dir == SortOrder.DESCENDING)
            cls.sorting.dir = stored.sorting.dir;
    } else if ("sort_by" in stored) {
        // TODO: Support multiple sorting columns. The format supports them,
        // but we currently use only the first.
        let sortBy = stored.sort_by.split(";")[0];

        if (sortBy != "") {
            const [by, dir] = sortBy.split(",");

            if (by in cls.columns.definitions)
                cls.sorting.column = by;
            else console.warn(`The stored sorting column "${by}" isn't valid, using default`);

            if (dir == SortOrder.ASCENDING || dir == SortOrder.DESCENDING)
                cls.sorting.dir = dir;
        }
    }

    // Restore filter settings
    if ("filtersEnabled" in stored && typeof(stored.filtersEnabled) == "boolean")
        cls.filters.enabled = stored.filtersEnabled;
    else if ("filter" in stored && typeof(stored.filter) == "boolean")
        cls.filters.enabled = stored.filter;

    if ("filtersReverse" in stored && typeof(stored.filtersReverse) == "boolean")
        cls.filters.reverse = stored.filtersReverse;
    else if ("reverse" in stored && typeof(stored.reverse) == "boolean")
        cls.filters.reverse = stored.reverse;

    if ("advanced" in stored && typeof(stored.advanced) == "boolean")
        cls.filters.advanced = stored.advanced;

    let tryToLoadOldFilters = false;

    if ("filters" in stored && typeof(stored.filters) == "string") {
        try {
            cls.filters.filters = JSON.parse(stored.filters);
        } catch (e) {
            // Okay
            cls.filters.filters = null;
            tryToLoadOldFilters = true;
        }
    } else tryToLoadOldFilters = true;

    if (tryToLoadOldFilters) {
        // If there were no new saved filters, but the old format filters are still present,
        // try to convert them. This is done only once and if it fails, too bad.
        // This code will be removed later.
        console.log("Attempting to load old filters, if present");

        let old = localStorage.getItem(`table-${cls.id}-filters`);

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
                    cls.filters.filters = [...converted];

                // Purge the old filters, they're no longer needed
                localStorage.removeItem(`table-${cls.id}-filters`);
            } catch (e) {
                console.error("Failed to convert the old filters:");
                console.error(e);
            }
        }
    }

    if ("filters_string" in stored && typeof(stored.filters_string) == "string")
        cls.filters.string = stored.filters_string;

    // Restore pagination settings
    if ("rows_per_page" in stored && typeof(stored.rows_per_page) == "number") {
        let found = false;

        // Validate the stored setting. Only allow predefined values.
        for (const r of ROWS_PER_PAGE_PRESETS) {
            if (r[0] == stored.rows_per_page) {
                cls.paging.rowsPerPage = stored.rows_per_page;
                found = true;
                break;
            }
        }

        if (!found)
            cls.paging.rowsPerPage = DEFAULT_ROWS_PER_PAGE;
    }

    return true;
}

// Constructs an object that contains all the current settings
function _getSettingsObject(cls)
{
    let filters = null;

    if (Array.isArray(cls.filters.filters))
        filters = JSON.stringify(cls.filters.filters, null, "");

    let show = [];

    if (cls.ui.filters.show && cls.ui.filters.show.checked)
        show.push("filters");

    if (cls.ui.mass.show && cls.ui.mass.show.checked)
        show.push("mass");

    let settings = {
        show: show.join(","),
        columns: cls.columns.current.join(","),
        sort_by: `${cls.sorting.column},${cls.sorting.dir}`,
        filter: cls.filters.enabled,
        reverse: cls.filters.reverse,
        advanced: cls.filters.advanced,
        filters: filters,
        filters_string: typeof(cls.filters.string) == "string" ? cls.filters.string : "",
        rows_per_page: cls.paging.rowsPerPage,
    };

    return settings;
}

// Loads stored settings from LocalStore, if they exist
export function load(cls)
{
    let stored = localStorage.getItem(`table-${cls.id}-settings`);

    if (stored === null)
        stored = "{}";

    try {
        stored = JSON.parse(stored);
    } catch (e) {
        console.error("Settings.load(): could not load stored settings:");
        console.error(e);

        return false;
    }

    return _loadSettingsObject(cls, stored);
}

// Saves the current settings to LocalStore
export function save(cls)
{
    try {
        localStorage.setItem(`table-${cls.id}-settings`, JSON.stringify(_getSettingsObject(cls)));
    } catch (e) {
        console.error("Cannot save table settings:");
        console.error(e);
    }
}
