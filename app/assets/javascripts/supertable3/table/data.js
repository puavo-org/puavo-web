// Data transforms, high-level filtering, and sorting utility

import { ColumnFlag, ColumnType, SortOrder } from "./constants.js";
import { escapeHTML, pad } from "../../common/utils.js";
import { convertTimestamp, getColumnType } from "./utils.js";

import { compareRowValue } from "../filters/interpreter/comparisons.js";
import { evaluateFilter } from "../filters/interpreter/evaluator.js";

import { ST_TIMESTAMP_FORMATTER, ST_DATE_FORMATTER } from "./main.js";

// -------------------------------------------------------------------------------------------------
// GENERIC HELPERS

export const quotedVector = a => `"${a.join("\n")}"`;

export function outputAsStandardArray(v, quoteExport=false)
{
    return {
        display: v.map(i => escapeHTML(i)),
        sort: v.join(",").toLowerCase(),
        filter: v,
        export: v
    };
}

export function outputBoolean(v)
{
    if (v === undefined || v === null)
        return undefined;

    return {
        display: v ? "✔" : "",
        filter: v,
        sort: v,
        export: v
    };
}

// Converts an LDAP timestamp string into ISO8601 string that can be fed to the Date object constructor
export function convertLDAPTimestampToISO8601String(s)
{
    // Just add separators to the string
    return s.substring(0, 4) + "-" +        // year
           s.substring(4, 6) + "-" +        // month
           s.substring(6, 8) + "T" +        // day
           s.substring(8, 10) + ":" +       // hours
           s.substring(10, 12) + ":" +      // minutes
           s.substring(12);                 // seconds + timezone offset if present
}

// The "date" parameter can be an Unixtime, a string, or Date object. Other formats will return undefined.
export function outputISO8601Timestamp(date, flags = 0)
{
    if (date === undefined || date === null)
        return undefined;

    let d = null;

    if (typeof(date) == "object")
        d = date;                           // a plain Date object
    else if (typeof(date) == "number")
        d = new Date(date * 1000);          // raw unixtime stamp
    else if (typeof(date) == "string")
        d = new Date(date);                 // string, assume the Date object constructor understands it
    else return undefined;

    const dateOnly = flags & ST.ColumnFlag.F_DATEONLY;
    const unix = d.getTime() / 1000;
    let iso = d.toISOString();

    if (dateOnly)
        iso = iso.substr(0, 10);

    return {
        display: `<abbr title="${iso}">${dateOnly ? ST_DATE_FORMATTER.format(d) : ST_TIMESTAMP_FORMATTER.format(d)}</abbr>`,
        sort: unix,
        filter: unix,
        export: iso,
    };
}

// -------------------------------------------------------------------------------------------------
// CUSTOM

function transformCustomValue(raw, key, coldef)
{
    if (typeof(coldef.transform) == "function") {
        // Apply a user-defined transformation. We assume the user function can deal
        // with null and undefined values.
        return coldef.transform(raw);
    }

    // Apply a built-in transformation
    switch (coldef.type) {
        case ColumnType.BOOL:
            return outputBoolean(raw[key] === true);

        case ColumnType.NUMERIC:
            return { value: raw[key] };

        case ColumnType.UNIXTIME:
            return outputISO8601Timestamp(raw[key], coldef.flags);

        case ColumnType.STRING:
        default:
            return { value: escapeHTML(raw[key]) };
    }
}

// Apply some transformations to the raw data received from the server. For example,
// convert timestamps into user's local time, turn booleans into checkmarks, and so on.
// The data we generate here is purely presentational, intended for humans; it's never
// fed back into the database.
function transformCustom(columnDefinitions, rawData, preFilterFunction=null)
{
    const columnKeys = Object.keys(columnDefinitions);
    let out = [];

    for (const raw of (preFilterFunction ? preFilterFunction(rawData) : rawData)) {
        // Puavo ID and school ID are both *always* required. No exceptions.
        if (!("_puavo_id" in raw) || !("_school_id" in raw))
            continue;

        let cleaned = {
            _puavo_id: raw._puavo_id,
            _school_id: raw._school_id
        };

        for (const key of columnKeys) {
            const coldef = columnDefinitions[key];

            if (!(key in raw))
                continue;

            if (raw[key] === undefined || raw[key] === null)
                continue;

            const out = transformCustomValue(raw, key, coldef);

            if (out !== undefined)
                cleaned[key] = out;
        }

        out.push(cleaned);
    }

    return out;
}

// -------------------------------------------------------------------------------------------------
// DIRECT LDAP INGESTION

// Performs a type conversion on a single LDAP value. It must not be an array.
function transformLDAPValue(value, def, type)
{
    switch (type) {
        case ST.ColumnType.STRING:
            return { value: ST.escapeHTML(value) };

        case ST.ColumnType.BOOL:
            return outputBoolean(value === 'TRUE');

        case ST.ColumnType.NUMERIC:
            return { value: parseInt(value, 10) };

        case ST.ColumnType.UNIXTIME: {
            const dateOnly = def.flags & ColumnFlag.F_DATEONLY;
            const date = new Date(convertLDAPTimestampToISO8601String(value));
            const unix = date.getTime() / 1000;
            let iso = date.toISOString();

            if (dateOnly)
                iso = iso.substr(0, 10);

            return {
                display: `<abbr title="${iso}">${dateOnly ? ST_DATE_FORMATTER.format(date) : ST_TIMESTAMP_FORMATTER.format(date)}</abbr>`,
                sort: unix,
                filter: unix,
                export: iso,
            };
        }

        default:
            throw new Error(`transformSingle(): unknown column type ${type}`);
    }
}

// Performs a type conversion on an array LDAP value. At the moment, only string arrays are supported,
// as no other types of arrays are used in the database.
function transformLDAPArray(value, def, type)
{
    switch (type) {
        case ST.ColumnType.STRING:
            return outputAsStandardArray(value);

        default:
            throw new Error(`transformArray(): only string arrays are supported, not column type of ${type}`);
    }
}

// Transforms raw LDAP data
function transformLDAP(context, columns)
{
    const columnEntries = Object.entries(columns);
    let out = [];

    // Warn about missing attributes (you wouldn't belive how easy it is to forget these!)
    for (const [key, def] of columnEntries) {
        if (def.synthesizer)
            continue;

        if (!("attribute" in def))
            console.warn(`Column "${key}" has no "attribute" member!`);
    }

    // For every row in the source data...
    for (const [dn, entry] of context.entries) {
        let converted = {};

        // For every column in the row...
        for (const [key, def] of columnEntries) {
            const type = getColumnType(def);

            // Synthesize an artificial column. Artificial columns don't exist in the source data.
            if (def.synthesizer) {
                let synth = null;

                try {
                    synth = def.synthesizer(context, dn, entry);
                } catch (e) {
                    console.error(`Synthesizer function call failed for entry ${dn}, column "${key}":`);
                    console.error(e);
                }

                if (synth !== undefined)
                    converted[key] = synth;

                continue;
            }

            if (def.attribute in entry) {
                // Use a user-supplied function for type conversion
                if (def.transformer) {
                    converted[key] = def.transformer(context, dn, entry);
                    continue;
                }

                // Use a built-in function for type conversion
                if (def.flags & ST.ColumnFlag.ARRAY)
                    converted[key] = transformLDAPArray(entry[def.attribute], def, type);
                else converted[key] = transformLDAPValue(entry[def.attribute][0], def, type);

                continue;
            }

            // This column has no value in the database for this row. Leave it empty, or use
            // a default value if one has been specified. It must be converted too.
            if (def.defaultValue === undefined)
                continue;

            const value = def.defaultValue;

            switch (type) {
                case ColumnType.BOOL:
                    converted[key] = {
                        display: value ? "✔" : "",
                        filter: value,
                        sort: value,
                        export: value
                    };

                    break;

                case ColumnType.STRING:
                    converted[key] = { value: ST.escapeHTML(value) };
                    break;

                // Assume all other possible default value types are fully usable as-is
                // (if not, they've been defined incorrectly)
                default:
                    converted[key] = { value: value };
                    break;
            }
        }

        // Ensure each entry has its PuavoID in the data. Most entries already have an "id" column
        // in the data, but this ensures the ID is always present.
        converted._puavo_id = parseInt(entry.puavoId[0], 10);

        out.push(converted);
    }

    return out;
}

// -------------------------------------------------------------------------------------------------
// DATA TRANSFORMATION

// Transform the received data. This needs to be done only once after new data has been received.
export function transformRawData(table, incomingJSON)
{
    table.resetError();

    const t0 = performance.now();

    if (table.user.datamode == "custom") {
        // Old custom data transformation
        table.data.transformed = transformCustom(
            table.columns.definitions,
            incomingJSON,
            table.user.preFilterFunction
        );

        const t1 = performance.now();
        console.log(`transformRawData(): rows transform took ${t1 - t0} ms`);
    } else {
        // Ingest LDAP data directly
        const context = table.user.preparseFunction(incomingJSON);

        const t1 = performance.now();
        table.data.transformed = transformLDAP(context, table.columns.definitions);

        if (table.user.postparseFunction)
            table.user.postparseFunction(context, table.data.transformed);

        const t2 = performance.now();
        console.log(`transformRawData(): context building took ${t1 - t0} ms`);
        console.log(`transformRawData(): rows transform took ${t2 - t1} ms`);
    }
}

// -------------------------------------------------------------------------------------------------
// FILTERING AND SORTING

// Applies zero or more filters to the data. Returns the indexes of rows that are visible.
export function filterRows(columnDefinitions, data, filters, reverse)
{
    const numComparisons = filters.comparisons.length;
    let filtered = [];

    for (let index = 0; index < data.length; index++) {
        const row = data[index];

        // Evaluate comparisons for this row
        let results = [];

        for (const cmp of filters.comparisons) {
            let value = row[cmp.column];

            if (value !== undefined) {
                if ("filter" in value)
                    value = value.filter;
                else value = value.value;
            }

            results.push(compareRowValue(value, cmp));
        }

        const final = evaluateFilter(filters.program, results);

        // Then run the RPN filter program. If the row is visible, store its index in the array.
        if (final != reverse)
            filtered.push(index);
    }

    return filtered;
}

// Sorts the data by the specified column and order
export function sortRows(columnDefinitions, sortBy, collator, data, indexes)
{
    const direction = (sortBy.dir == SortOrder.ASCENDING) ? 1 : -1,
          key = sortBy.column;

    try {
        switch (getColumnType(columnDefinitions[sortBy.column])) {
            case ColumnType.BOOL:
                indexes.sort((indexA, indexB) => {
                    const data1 = data[indexA],
                          data2 = data[indexB];

                    let valueA = data1[key],
                        valueB = data2[key];

                    if (valueA === undefined)
                        return direction;
                    else if (valueB === undefined)
                        return -direction;

                    valueA = (valueA.sort === undefined) ? valueA.value : valueA.sort;
                    valueB = (valueB.sort === undefined) ? valueB.value : valueB.sort;

                    if (valueA === true && valueB === false)
                        return -direction;
                    else if (valueA === false && valueB === true)
                        return direction;

                    return data1._puavo_id - data2._puavo_id;       // stabilize the sort
                });

                break;

            case ColumnType.NUMERIC:
            case ColumnType.UNIXTIME:
                indexes.sort((indexA, indexB) => {
                    const data1 = data[indexA],
                          data2 = data[indexB];

                    let valueA = data1[key],
                        valueB = data2[key];

                    if (valueA === undefined)
                        return -direction;
                    else if (valueB === undefined)
                        return direction;

                    valueA = valueA.sort || valueA.value;
                    valueB = valueB.sort || valueB.value;

                    if (valueA < valueB)
                        return -direction;
                    else if (valueA > valueB)
                        return direction;

                    return data1._puavo_id - data2._puavo_id;       // stabilize the sort
                });

                break;

            case ColumnType.STRING:
                indexes.sort((indexA, indexB) => {
                    const data1 = data[indexA],
                          data2 = data[indexB];

                    let valueA = data1[key],
                        valueB = data2[key];

                    // Sort existing values first (or last, depending on the order)
                    if (valueA === undefined)
                        return direction;
                    else if (valueB === undefined)
                        return -direction;

                    valueA = valueA.sort ?? valueA.value;
                    valueB = valueB.sort ?? valueB.value;

                    const r = collator.compare(valueA, valueB) * direction;

                    if (r === 0)
                        return data1._puavo_id - data2._puavo_id; // stabilize the sort

                    return r;
                });

                break;

            default:
                throw new Error(`sortRows(): invalid column type "${type}"`);
        }
    } catch (e) {
        console.error("Unable to sort the table:");
        console.log(e);
    }

    return indexes;
}
