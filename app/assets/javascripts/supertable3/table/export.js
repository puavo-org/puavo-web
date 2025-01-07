// Exports the table contents to CSV or JSON

import { _tr } from "../../common/utils.js";
import { getTemplate } from "../../common/dom.js";
import { getPopupContents } from "../../common/modal_popup.js";
import { ColumnType, INDEX_FILTERABLE } from "./constants.js";
import { JAVASCRIPT_TIME_GRANULARITY } from "./utils.js";

// Exports the data in columns, delimited by a single character
function storeAsColumns(data, source, columns, timeColumns, separator, onlySelected, output)
{
    for (const rowIndex of source) {
        const row = data.transformed[rowIndex];
        let out = [];

        if (onlySelected)
            if (!data.selectedItems.has(row.id[INDEX_FILTERABLE]))
                continue;

        for (const col of columns) {
            if (!(col in row) || row[col][INDEX_FILTERABLE] === null || row[col][INDEX_FILTERABLE] === undefined) {
                out.push("");
                continue;
            }

            if (timeColumns.has(col))
                out.push(new Date(row[col][INDEX_FILTERABLE] * JAVASCRIPT_TIME_GRANULARITY).toISOString());
            else out.push(row[col][INDEX_FILTERABLE]);
        }

        output.push(out.join(separator));
    }
}

function _doExport(format, data, allColumns, prefix)
{
    try {
        const onlySelected = modalPopup.getContents().querySelector("input#only-selected-rows").checked,
              visibleRows = modalPopup.getContents().querySelector("input#only-visible-rows").checked,
              visibleCols = modalPopup.getContents().querySelector("input#only-visible-cols").checked;

        let source = null;

        if (visibleRows)
            source = data.current;
        else {
            // 0, 1, 2, 3, ... N
            source = Array.from(Array(data.transformed.length).keys());
        }

        let output = [],
            mimetype, extension;

        const columns = visibleCols ?
            allColumns.current :
            Object.keys(allColumns.definitions);

        let headers = [...columns];

        const timeColumns = new Set();

        // Optional export alias names
        for (let i = 0; i < headers.length; i++) {
            const def = allColumns.definitions[headers[i]];

            if (def.export_name)
                headers[i] = def.export_name;

            if (def.type == ColumnType.UNIXTIME)
                timeColumns.add(headers[i]);
        }

        switch (format) {
            case "csv":
            default:
                output.push(headers.join(";"));
                storeAsColumns(data, source, columns, timeColumns, ";", onlySelected, output);

                output = output.join("\n");
                mimetype = "text/csv";
                extension = "csv";
                break;

            case "tsv":
                output.push(headers.join("\t"));
                storeAsColumns(data, source, columns, timeColumns, "\t", onlySelected, output);

                output = output.join("\n");
                mimetype = "text/tab-separated-values";
                extension = "tsv";
                break;

            case "json": {
                for (const rowIndex of source) {
                    const row = data.transformed[rowIndex];
                    let out = {};

                    if (onlySelected)
                        if (!data.selectedItems.has(row.id[INDEX_FILTERABLE]))
                            continue;

                    for (let i = 0; i < columns.length; i++) {
                        const col = columns[i];

                        if (!(col in row) || row[col][INDEX_FILTERABLE] === null || row[col][INDEX_FILTERABLE] === undefined)
                            continue;

                        if (timeColumns.has(col))
                            out[col] = new Date(row[col][INDEX_FILTERABLE] * JAVASCRIPT_TIME_GRANULARITY).toISOString();
                        else out[col] = row[col][INDEX_FILTERABLE];
                    }

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
        a.download = `${prefix}-${I18n.strftime(new Date(), "%Y-%m-%d-%H-%M-%S")}.${extension}`;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    } catch (e) {
        console.log(e);
        window.alert(_tr("export_failed", { error: e }));
    }
}

export function openPopup(event, data, columns, prefix, enableSelection)
{
    const template = getTemplate("exportPopup");

    template.querySelector(`button#btnCSV`).addEventListener("click", () => _doExport("csv", data, columns, prefix));
    template.querySelector(`button#btnTSV`).addEventListener("click", () => _doExport("tsv", data, columns, prefix));
    template.querySelector(`button#btnJSON`).addEventListener("click", () => _doExport("json", data, columns, prefix));

    template.querySelector(`input#only-selected-rows`).disabled = !enableSelection;

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(event);
        modalPopup.display("bottom");
    }
}
