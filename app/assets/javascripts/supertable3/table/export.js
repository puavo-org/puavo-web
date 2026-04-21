// Exports the table contents to CSV or JSON

import { _tr } from "../../common/utils.js";
import { getTemplate } from "../../common/dom.js";
import { getPopupContents } from "../../common/modal_popup.js";
import { ColumnType } from "./constants.js";
import { JAVASCRIPT_TIME_GRANULARITY, getColumnType, isNullOrUndefined } from "./utils.js";

const transformDate = v => new Date(v * JAVASCRIPT_TIME_GRANULARITY).toISOString();

function escape(str, extra=null)
{
    let out = [];

    for (const chr of str) {
        switch (chr) {
            case "\n":
                out.push("\\n");
                break;

            case "\r":
                out.push("\\r");
                break;

            case "\t":
                out.push("\\t");
                break;

            case "\\":
                out.push("\\\\");
                break;

            default:
                out.push(chr);
        }
    }

    return out.join("");
}

function exportColumnar(data, options, columnSeparator, subvalueSeparator)
{
    let output = [];

    for (const rowIndex of options.source) {
        const row = data.transformed[rowIndex];
        let rowOut = [];

        for (const col of options.columns) {
            try {
                let value = row[col];

                if (isNullOrUndefined(value)) {
                    rowOut.push(null);
                    continue;
                }

                value = value.export ?? value.value;

                if (options.timeColumns.has(col)) {
                    rowOut.push(value);
                    continue;
                }

                // Escape an array of strings. This works because currently there can be only arrays of strings.
                if (Array.isArray(value)) {
                    let out = [];

                    for (const v of value)
                        out.push(escape(v));

                    rowOut.push(out.join(subvalueSeparator));
                    continue;
                }

                if (typeof(value) == "string") {
                    rowOut.push(escape(value));
                    continue;
                }

                // Use as-is
                rowOut.push(value);
            } catch (e) {
                console.error(`Cannot transform row ${rowIndex} value "${col}":`);
                console.error(e);
                console.log(value);
                return null;
            }
        }

        output.push(rowOut.join(columnSeparator));
    }

    return output;
}

function exportJSON(data, options)
{
    let output = [];

    for (const rowIndex of options.source) {
        const row = data.transformed[rowIndex];
        let rowOut = {};

        for (const col of options.columns) {
            if (col in row) {
                try {
                    const value = row[col].export ?? row[col].value;

                    if (isNullOrUndefined(value))           // completely omit missing columns
                        continue;

                    rowOut[col] = value;
                } catch (e) {
                    console.error(`Cannot transform row ${rowIndex} value "${col}":`);
                    console.error(e);
                    console.log(value);
                    return null;
                }
            }
        }

        output.push(rowOut);
    }

    return output;
}

function doExport(table, format)
{
    try {
        const contents = modalPopup.getContents(),
              onlySelected = contents.querySelector("input#selected_rows").checked,
              visibleRows = contents.querySelector("input#visible_rows").checked,
              visibleCols = contents.querySelector("input#visible_cols").checked;

        let options = {};

        // Which rows to export?
        if (visibleRows) {
            // Only the currently visible
            options.source = table.data.current;
        } else {
            // All of them (0, 1, 2, 3, ... N)
            options.source = Array.from(Array(table.data.transformed.length).keys());
        }

        if (onlySelected) {
            // Only export rows that are selected
            let newSource = [];

            for (const rowIndex of options.source) {
                const row = table.data.transformed[rowIndex];

                if (onlySelected && table.data.selectedItems.has(row._puavo_id))
                    newSource.push(rowIndex);
            }

            options.source = newSource;
        }

        // Which columns to export?
        options.columns = visibleCols ? table.columns.current : Object.keys(table.columns.definitions);
        options.headers = [];
        options.timeColumns = new Set();

        for (const column of options.columns) {
            const definition = table.columns.definitions[column],
                  type = getColumnType(definition);

            options.headers.push(definition.export_name || column);

            if (type == ColumnType.UNIXTIME)
                options.timeColumns.add(column);
        }

        const FORMATS = {
            "csv":  { ext: "csv", sep: ",", subSep: ";", mime: "text/csv", },
            "tsv":  { ext: "tsv", sep: "\t", subSep: ",", mime: "text/tab-separated-values" },
            "json": { ext: "json", mime: "json" }
        }

        // Build the output
        let output = [];

        switch (format) {
            case "csv":
            case "tsv":
                output.push(options.headers.join(FORMATS[format].sep));
                output = output.concat(exportColumnar(table.data, options, FORMATS[format].sep, FORMATS[format].subSep));
                output = output.join("\n");
                break;

            case "json":
                output = JSON.stringify(exportJSON(table.data, options));
                break;
        }

        // Build a blob object (it must be an array for some reason), then trigger a download.
        // Download code stolen from StackOverflow.
        const b = new Blob([output], { type: FORMATS[format].mime });
        const a = window.document.createElement("a");

        a.href = window.URL.createObjectURL(b);
        a.download = `${table.settings.csvPrefix}-${I18n.strftime(new Date(), "%Y%m%d-%H%M%S")}.${FORMATS[format].ext}`;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    } catch (e) {
        console.log(e);
        window.alert(_tr("export_failed", { error: e }));
    }
}

function open(table, e)
{
    const template = getTemplate("exportPopup");

    for (const b of template.querySelectorAll("div#exportButtons button"))
        b.addEventListener("click", e => doExport(table, e.target.dataset.format));

    template.querySelector(`input#selected_rows`).disabled = !table.settings.enableSelection;

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e.target);
        modalPopup.display("bottom");
    }
}

export function setup(table, frag)
{
    const button = frag.querySelector("thead div#top button#export");

    if (table.settings.enableExport)
        button.addEventListener("click", e => open(table, e));
    else button.remove();
}
