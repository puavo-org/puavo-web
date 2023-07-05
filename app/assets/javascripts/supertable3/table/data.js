// Data transforms, high-level filtering, and sorting utility

import { ColumnFlag, ColumnType, SortOrder, INDEX_EXISTS, INDEX_DISPLAYABLE, INDEX_FILTERABLE, INDEX_SORTABLE } from "./constants.js";
import { escapeHTML } from "../../common/utils.js";
import { convertTimestamp } from "./utils.js";

import { compareRowValue } from "../filters/interpreter/comparisons.js";
import { evaluateFilter } from "../filters/interpreter/evaluator.js";

// Default values for different column types. Used to substitute missing values for sorting.
const DEFAULT_VALUES = {
    [ColumnType.BOOL]: false,
    [ColumnType.NUMERIC]: 0,
    [ColumnType.UNIXTIME]: 0,
    [ColumnType.STRING]: ""
};

function _transformValue(raw, key, coldef, defVal)
{
    if (typeof(coldef.transform) == "function") {
        // Apply a user-defined transformation. We assume the user function can deal
        // with null and undefined values.
        return coldef.transform(raw);
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
            [, value] = convertTimestamp(value);
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
}

// Apply some transformations to the raw data received from the server. For example,
// convert timestamps into user's local time, turn booleans into checkmarks, and so on.
// The data we generate here is purely presentational, intended for humans; it's never
// fed back into the database.
export function transformRows(columnDefinitions, rawData, preFilterFunction=null)
{
    const columnKeys = Object.keys(columnDefinitions);

    let out = [];

    for (const raw of (preFilterFunction ? preFilterFunction(rawData) : rawData)) {
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
                const [d, s, f] = _transformValue(raw, key, coldef, defVal);

                clean[INDEX_EXISTS] = true;
                clean[INDEX_DISPLAYABLE] = d;
                clean[INDEX_SORTABLE] = s;
                clean[INDEX_FILTERABLE] = (f === undefined) ? raw[key] : f;
            } else {
                clean[INDEX_EXISTS] = false;
                clean[INDEX_DISPLAYABLE] = null;
                clean[INDEX_SORTABLE] = defVal;
                clean[INDEX_FILTERABLE] = undefined;    // the filter system knows how to deal with this

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
export function filterRows(columnDefinitions, data, filters, reverse)
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
export function sortRows(columnDefinitions, sortBy, collator, data)
{
    const direction = (sortBy.dir == SortOrder.ASCENDING) ? 1 : -1,
          key = columnDefinitions[sortBy.column].key;

    let out = [...data];

    switch (columnDefinitions[sortBy.column].type) {
        case ColumnType.BOOL:               // not the best choice
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
