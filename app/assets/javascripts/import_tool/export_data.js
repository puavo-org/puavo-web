// PDF and CSV export

import { _tr } from "../common/utils.js";
import { MIN_PASSWORD_LENGTH, RowFlag, } from "./constants.js";
import { enableUI } from "./main.js";

// Generate and download a PDF that contains the users and optionally their passwords.
// 'selectionState' can be used to control which rows are exported (null exports all,
// true exports only selected rows, and false exports unselected rows).
function exportPDF(data, selectionState, includePasswords)
{
    const uidCol = data.findColumn("uid"),
          passwordCol = data.findColumn("password");

    if (uidCol === -1 || (includePasswords && passwordCol === -1)) {
        window.alert(_tr("alerts.no_data_for_the_pdf"));
        return;
    }

    let users = {},
        missing = 0,
        total = 0;

    for (let row = 0; row < data.rows.length; row++) {
        // Include only the wanted rows
        const selected = (data.rows[row].rowFlags & RowFlag.SELECTED) ? true : false;

        if (selectionState !== null && selected !== selectionState)
            continue;

        const uid = data.rows[row].cellValues[uidCol],
              password = data.rows[row].cellValues[passwordCol];

        if (uid === null || uid.trim().length < 3) {
            missing++;
            continue;
        }

        if (includePasswords) {
            if (password === null || password.length < MIN_PASSWORD_LENGTH) {
                missing++;
                continue;
            }

            users[uid] = password;
        } else {
            // Just pass the username
            users[uid] = null;
        }

        total++;
    }

    if (total == 0) {
        window.alert(_tr("alerts.still_no_data_for_the_pdf"));
        return;
    }

    if (missing > 0) {
        if (!window.confirm(_tr("alerts.empty_rows_skipped")))
            return;
    }

    let filename = null,
        failed = false,
        error = null;

    enableUI(false);

    fetch("new_import/generate_pdf", {
        method: "POST",
        mode: "cors",
        headers: {
            // Again use text/plain to avoid RoR from logging user passwords in plaintext
            "Content-Type": "text/plain; charset=utf-8",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        },
        body: JSON.stringify(users),
    }).then(response => {
        if (!response.ok)
            throw response;

        // If the server responded with JSON, then it means the PDF generation failed,
        // as nothing else can generate a JSON response
        const type = response.headers.get("Content-Type");

        if (type == "application/json") {
            failed = true;

            // We HAVE to return something from this function. It's the JavaScript's rain dance,
            // you have to do it exactly by the book or it won't work. And after you get it to
            // work, then you have to invent the rain because it does not come with JavaScript.
            return response.json();
        }

        // Extract the filename from the headers
        const match = /^attachment; filename="(?<filename>.+)"/.exec(response.headers.get("Content-Disposition"));

        if (!match) {
            window.alert(_tr("alerts.server_sent_invalid_filename"));
            filename = "generated_passwords.pdf";
        } else filename = match.groups.filename;

        return response.blob();
    }).then(data => {
        if (failed) {
            console.log(data);
            throw new Error(_tr("alerts.pdf_generation_failed", { message: data.message }));
        }

        // Trigger a download
        const b = new Blob([data], { type: "application/octet-stream" });
        let a = window.document.createElement("a");

        a.setAttribute("download", filename);
        a.setAttribute("target", "_blank");
        a.href = window.URL.createObjectURL(b);

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }).catch(error => {
        window.alert(error);
    }).finally(() => {
        enableUI(true);
    });
}

// Exports the table rows to a CSV file. 'selectionState' can be used to control
// which rows are exported (null exports all, true exports only selected rows,
// and false exports unselected rows).
function exportCSV(data, selectionState, separatorIndex)
{
    // Use the same separator that was used during parsing
    const separator = { 0: ",", 1: ";", 2: "\t" }[separatorIndex];

    try {
        const outputRow = (row) => {
            let out = [];

            for (let col = 0; col < data.headers.length; col++) {
                if (row.cellValues[col] == "")
                    out.push("");
                else out.push(row.cellValues[col]);
            }

            return out;
        };

        let output = [];

        // Header first
        output.push(data.headers.join(separator));

        if (selectionState === null) {
            // All rows
            for (const row of data.rows)
                output.push(outputRow(row).join(separator));
        } else {
            // Only rows whose selection state equals to selectionState (ie. true/false)
            if (selectionState === true) {
                // Selected rows
                for (const row of data.rows)
                    if (row.rowFlags & RowFlag.SELECTED)
                        output.push(outputRow(row).join(separator));
            } else {
                // Unselected rows
                for (const row of data.rows)
                    if (!(row.rowFlags & RowFlag.SELECTED))
                        output.push(outputRow(row).join(separator));
            }
        }

        output = output.join("\n");

        // Build a blob object (it must be an array for some reason), then trigger a download.
        // Download code stolen from StackOverflow.
        const b = new Blob([output], { type: "text/csv" });
        let a = window.document.createElement("a");

        a.href = window.URL.createObjectURL(b);
        a.download = `${data.currentOrganisationName}_${data.currentSchoolName}_` +
                     `${I18n.strftime(new Date(), "%Y%m%d_%H%M%S")}.csv`;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    } catch (e) {
        console.log(e);
        window.alert(`CSV generation failed, see the console for details.`);
    }
}

export function exportData(data, format, selectionType, settings, includePDFPasswords=false)
{
    let numRows = 0;

    // Count matching rows first
    switch (selectionType) {
        case "all":
        default:
            numRows = data.rows.length;
            break;

        case "selected":
            for (const row of data.rows)
                if (row.rowFlags & RowFlag.SELECTED)
                    numRows++;
            break;

        case "unselected":
            for (const row of data.rows)
                if (!(row.rowFlags & RowFlag.SELECTED))
                    numRows++;
            break;
    }

    if (numRows == 0) {
        window.alert(_tr("alerts.no_matching_rows"));
        return;
    }

    switch (format) {
        case "csv":
            if (selectionType == "all")
                exportCSV(data, null, settings.parser.separator);
            else if (selectionType == "selected")
                exportCSV(data, true, settings.parser.separator);
            else exportCSV(data, false, settings.parser.separator);

            break;

        case "pdf":
            if (selectionType == "all")
                exportPDF(data, null, includePDFPasswords);
            else if (selectionType == "selected")
                exportPDF(data, true, includePDFPasswords);
            else exportPDF(data, false, includePDFPasswords);

            break;

        default:
            window.alert(`exportData(): unknown format "${format}"`);
            break;
    }
}
