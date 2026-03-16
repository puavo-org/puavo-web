// Table settings saving and loading

import { SortOrder, ROWS_PER_PAGE_PRESETS, DEFAULT_ROWS_PER_PAGE } from "./constants.js";

const keyName = table => `table-${table.id}-settings`;
const haveString = (stored, key) => (key in stored) && (typeof(stored[key]) == "string");
const haveBoolean = (stored, key) => (key in stored) && (typeof(stored[key]) == "boolean");

function _loadSettings(table, stored)
{
    // Restore open tool sections
    if (haveString(stored, "show"))
        table.settings.show = stored.show.split(",");

    // Restore the currently visible columns and their order
    let columns = null;

    if (haveString(stored, "columns"))
        columns = stored.columns.split(",").map(i => i.trim()).filter(e => e != "");

    if (columns !== null) {
        // Deduplicate the column names array and remove invalid/missing columns from it
        columns = [...new Set(columns)].filter(column => column in table.columns.definitions);

        if (columns.length > 0)
            table.columns.current = columns;
    }

    // Restore the sorting column and direction
    if (haveString(stored, "sort_by")) {
        const [column, dir] = stored.sort_by.split(",");

        if (column in table.columns.definitions)
            table.sorting.column = column;

        if (dir == SortOrder.ASCENDING || dir == SortOrder.DESCENDING)
            table.sorting.dir = dir;
    }

    // Restore filter settings
    if (haveBoolean(stored, "filter"))
        table.filters.enabled = stored.filter;

    if (haveBoolean(stored, "reverse"))
        table.filters.reverse = stored.reverse;

    if (haveBoolean(stored, "advanced"))
        table.filters.advanced = stored.advanced;

    // Restore the traditional filters
    if (haveString(stored, "filters")) {
        try {
            table.filters.filters = JSON.parse(stored.filters);
        } catch (e) {
            console.error(`Could not restore the traditional filters: ${e}`);
            console.error(stored.filters);
        }
    }

    // Restore the advanced filtering string
    if (haveString(stored, "filters_string"))
        table.filters.string = stored.filters_string;

    // Restore the pagination settings. Ensure the value is valid.
    if ("rows_per_page" in stored && typeof(stored.rows_per_page) == "number") {
        if (ROWS_PER_PAGE_PRESETS.find(r => r[0] == stored.rows_per_page))
            table.paging.rowsPerPage = stored.rows_per_page;
        else table.paging.rowsPerPage = DEFAULT_ROWS_PER_PAGE;
    }
}

// Loads stored settings from local storage
export function loadSettings(table)
{
    try {
        const stored = localStorage.getItem(keyName(table)) || "{}";

        _loadSettings(table, JSON.parse(stored));
    } catch (e) {
        console.error(`Cannot load the table settings: ${e}`);
    }
}

// Saves the current settings to local storage
export function saveSettings(table)
{
    try {
        // Which tool sections are open?
        let showSections = [];

        if (table.container.querySelector("thead section input#editor")?.checked)
            showSections.push("filters");

        if (table.container.querySelector("thead section#massSpan input")?.checked)
            showSections.push("mass");

        localStorage.setItem(keyName(table), JSON.stringify({
            show: showSections.join(","),
            columns: table.columns.current.join(","),
            sort_by: `${table.sorting.column},${table.sorting.dir}`,
            filter: table.filters.enabled,
            reverse: table.filters.reverse,
            advanced: table.filters.advanced,
            filters: Array.isArray(table.filters.filters) ? JSON.stringify(table.filters.filters, null, "") : [],
            filters_string: typeof(table.filters.string) == "string" ? table.filters.string : "",
            rows_per_page: table.paging.rowsPerPage,
        }));
    } catch (e) {
        console.error(`Cannot save the table settings: ${e}`);
    }
}
