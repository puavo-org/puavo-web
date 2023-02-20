"use strict";

/*
Puavo Mass User Import III
Version 1.0.1
*/

import { create, getTemplate, toggleClass } from "../common/dom.js";
import { _tr, clamp } from "../common/utils.js";
import { loadSettings, saveSettings } from "./settings.js";

import {
    REQUIRED_COLUMNS_NEW,
    REQUIRED_COLUMNS_UPDATE,
    INFERRED_NAMES,
    NUM_ROW_HEADERS,
    BATCH_SIZE,
    MIN_PASSWORD_LENGTH,
    MAX_PASSWORD_LENGTH,
    USERNAME_REGEXP,
    EMAIL_REGEXP,
    PHONE_REGEXP,
    VALID_ROLES,
    RowFlag,
    RowState,
    CellFlag,
    Duplicates,
    ImportRows,
    PopupType,
} from "./constants.js";

import {
    ImportData,
} from "./data.js";

import {
    clampPasswordLength,
    beginGET,
    beginPOST,
    parseServerJSON,
} from "./utils.js";

import { exportData } from "./export_data.js";

import { doDetectProblems } from "./problems.js";

import {
    dropDiacritics,
    shuffleString,
} from "./fill.js";

// Worker threads for CSV parsing and the actual data import/update process.
// CSV_PARSER_PATH and IMPORT_WORKER_PATH are defined in the page header;
// they contain the asset paths to the JS files. We can't set them here, since
// this file is not a template; it has no access to the Rails' asset pipeline.
const CSV_PARSER_WORKER = new Worker(CSV_PARSER_PATH),
      IMPORT_WORKER = new Worker(IMPORT_WORKER_PATH);

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA

// Popup menu/dialog. When the popup is opened, it is attached to the 'attachTo' HTML element.
// How the popup is positioned relative to the element depends on the element type. When the
// page is scrolled, the popup is repositioned so that it follows the attached element.
const popup = {
    backdrop: null,
    contents: null,
    attachedTo: null,
    attachmentType: null,       // see 'PopupType' below
};

// Global state
const state = {
    // Everything in the import tool happens inside this container element
    container: null,

    // Localized strings. Supplied by the user in the initializer.
    localizedColumnTitles: {},
    localizedGroupTypes: {},

    // Current settings. Call loadDefaultSettings() to load the defaults.
    SETTINGS: {},

    // Tab-separated string of common passwords. Make sure this starts and ends in a tab,
    // so substring searching works.
    commonPasswords: "\tpassword\tsalasana\tpasswort\t",

    // True if email addresses are automatic in this school/organisation, and thus email address
    // columns will be ignored.
    automaticEmails: false,

    parser: {
        // Raw contents of the uploaded file (manual entry uses the textarea directly), grabbed
        // whenever user selects a file (it cannot be done when the import actually begins, it has to
        // be done in advance, when the file select event fires).
        fileContents: null,

        // If not null, contains the error message the CSV parser returned
        error: null,
    },

    // The column we're editing when the column popup/dialog is open
    targetColumn: {
        column: null,
        index: -1
    },

    // The (row, col) coordinates and the TD element we're directly editing (double-click)
    directCellEdit: {
        pos: null,
        target: null,
    },

    // Cell selection
    selection: {
        active: false,

        // X and Y coordinates of the mouse cursor at the time the left mouse button went down
        mouseTrackPos: null,

        // The HTML element under the mouse when the selection began
        initialClick: null,

        // Last updated cell during a range selection
        previousCell: null,

        // Indexes, -1 if nothing is selected
        column: -1,
        start: -1,
        end: -1,
    },

    // Row statistics
    statistics: {
        // Generic stats
        totalRows: 0,
        selectedRows: 0,
        rowsWithErrors: 0,

        // Import stats
        rowsToBeImported: 0,
        totalRowsProcessed: 0,
        success: 0,
        partialSuccess: 0,
        failed: 0,
    },

    // The imported data
    importData: new ImportData(),

    // The mass import process state
    process: {
        // True if an import job is currently active
        importActive: false,

        // True if the user has already imported/updated something
        alreadyClickedImportOnce: false,

        // If the password column exists and its contents are edited, the generated PDF will be
        // out-of-sync unless they're synced first. This flag warns the user about that.
        passwordsAlteredSinceImport: false,

        // If true, the import process will be stopped after the current batch is finished
        // (it cannot be stopped mid-way; even if you terminate the worker thread, the server
        // is busy processing the batch and there's no way to stop it)
        stopRequested: false,

        // Allow continuing from the previously-stopped row
        previousImportStopped: false,

/*
        // If true, only the selected rows are checked in detectProblems(). This is a dangerous
        // setting, but it can be useful if you have erroneous rows and you just want to import
        // the non-erroneous rows and you've selected them.
        // TODO: this works, but it has some problems, will be fixed later.
        checkOnlySelectedRows: false,
*/

        // A copy of importData.rows made at the start of the import process. This ensures the
        // original data is not modified in any way under any circumstances.
        workerRows: [],

        // List of failed rows (numbers). The user can retry them.
        failedRows: [],

        // Records the last processed row. This is used to resume the import process if it was stopped.
        lastRowProcessed: 0,
    },
};

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// POPUP UTILITY

// Re-enables column settings buttons
function clearMenuButtons()
{
    for (let button of state.container.querySelectorAll("div#output table thead button.controls")) {
        button.classList.remove("activeMenu");
        button.disabled = false;
    }
}

// Creates an empty popup menu/dialog. You have to fill, position and display it.
function createPopup()
{
    if (popup.backdrop) {
        window.alert("createPopup(): the popup is already open!");
        return;
    }

    popup.backdrop = create("div", { id: "popupBackdrop" });
    popup.contents = create("div", { cls: "popup" });
    popup.backdrop.appendChild(popup.contents);
}

// Closes the active popup menu/dialog
function closePopup()
{
    if (!popup.backdrop)
        return;

    document.body.removeEventListener("keydown", onKeyDown);

    clearMenuButtons();

    popup.contents.innerHTML = "";
    popup.contents = null;
    popup.backdrop.remove();
    popup.backdrop = null;
}

function displayPopup()
{
    if (popup.backdrop) {
        document.body.appendChild(popup.backdrop);
        ensurePopupIsVisible();
    }
}

// Attaches the popup to the specified HTML element and, optionally, sets the popup width.
// These are done in one function because the popup width cannot be (reliably) changed after
// it has been attached. You need to call this before displayPopup()!
function attachPopup(element, type, width=null)
{
    popup.attachedTo = element;
    popup.attachmentType = type;

    const rect = element.getBoundingClientRect();

    let x = rect.left,
        y = rect.top;

    popup.contents.style.display = "block";
    popup.contents.style.position = "absolute";
    popup.contents.style.left = `${Math.round(x)}px`;
    popup.contents.style.top = `${Math.round(y)}px`;

    if (width !== null)
        popup.contents.style.width = `${Math.round(width)}px`;
}

// Positions the popup (menu or dialog) so that it's fully visible. Since the attachment
// type and element are known, the popup position can be updated if the page is scrolled.
function ensurePopupIsVisible()
{
    if (!popup.backdrop)
        return;

    const attachedToRect = popup.attachedTo.getBoundingClientRect(),
          popupRect = popup.contents.getBoundingClientRect(),
          pageWidth = document.documentElement.clientWidth,
          pageHeight = document.documentElement.clientHeight,
          popupW = popupRect.right - popupRect.left,
          popupH = popupRect.bottom - popupRect.top;

    let x = popupRect.left,
        y = popupRect.top;

    switch (popup.attachmentType) {
        case PopupType.COLUMN_MENU:
            x = attachedToRect.left - 1;
            y = attachedToRect.bottom - 1;
            break;

        case PopupType.POPUP_MENU:
            x = attachedToRect.left;
            y = attachedToRect.bottom;
            break;

        case PopupType.CELL_EDIT:
            x = attachedToRect.left - 5;
            y = attachedToRect.top - 1;
            break;

        default:
            console.warn(`Unknown popup attachment type ${popup.attachmentType}`);
            break;
    }

    if (x < 0)
        x = 0;

    if (x + popupW > pageWidth)
        x = pageWidth - popupW;

    if (y < 0)
        y = 0;

    if (y + popupH > pageHeight)
        y = pageHeight - popupH;

    popup.contents.style.left = `${Math.round(x)}px`;
    popup.contents.style.top = `${Math.round(y)}px`;
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PARSING

// Updates the parser options summary
function updateParsingSummary()
{
    let parts = [];

    if (state.container.querySelector("#comma").checked)
        parts.push(_tr("parser.commas"));
    else if (state.container.querySelector("#tab").checked)
        parts.push(_tr("parser.tabs"));
    else parts.push(_tr("parser.semicolons"));

    if (state.container.querySelector("#inferTypes").checked)
        parts.push(_tr('parser.infer'));

    if (state.container.querySelector("#trimValues").checked)
        parts.push(_tr('parser.trim'));

    state.container.querySelector("details#settings summary").innerHTML =
        `${_tr('parser.title')} (${parts.join(", ")})`;
}

// Called when the CSV parser is finished. Update either the preview table, or the
// main import table.
CSV_PARSER_WORKER.onmessage = e => {
    state.parser.error = null;

    if (e.data.state == "error") {
        state.parser.error = e.data.message;

        // Don't overwrite existing data, if any
        return;
    }

    let headers = [],
        rows = [];

    // Infer column types
    if (Array.isArray(e.data.headers)) {
        headers = [...e.data.headers];

        for (let i = 0; i < headers.length; i++) {
            const colName = headers[i].toLowerCase();

            if (colName in INFERRED_NAMES)
                headers[i] = INFERRED_NAMES[colName];

            // Clear unknown column types, so the column will be skipped
            if (!(headers[i] in state.localizedColumnTitles))
                headers[i] = "";
        }
    }

    rows = [...e.data.rows];

    const maxColumns = e.data.widestRow;

    console.log(`preprocessParserOutput(): the widest row has ${maxColumns} columns`);

    // Padd all rows (including the header) to have the same number of columns as the widest row
    while (headers.length < maxColumns)
        headers.push("");       // empty means "skip this column"

    for (let row of rows) {
        while (row.cellValues.length < maxColumns)
            row.cellValues.push("");

        row.rowFlags = 0;
        row.rowState = RowState.IDLE;
        row.cellFlags = Array(maxColumns).fill(0);
    }

    // Preview update must not clobber potentially already existing table data, and vice versa
    if (e.data.isPreview) {
        state.importData.previewHeaders = headers;
        state.importData.previewRows = rows;
    } else {
        state.importData.headers = headers;
        state.importData.rows = rows;
        state.statistics.totalRows = rows.length;
    }

    buildImportTable(state.container.querySelector(e.data.isPreview ? "div#preview" : "div#output"),
                     headers, rows, e.data.isPreview);

    if (!e.data.isPreview) {
        // TODO: We should at least check for missing required columns in the preview mode
        detectProblems();
        updateStatistics();
    }
}

// Builds a "mini" import table for previewing the first N rows of data
function updatePreview()
{
    let source = "";

    // Data source
    switch (state.SETTINGS.parser.sourceTab) {
        case 0:
        default:
            // Manual entry
            source = state.container.querySelector("div#manual textarea").value;
            break;

        case 1:
            // File upload
            source = state.parser.fileContents;
            break;

        case 2:
            // Username list (a different textarea)
            source = state.container.querySelector("div#unl textarea")?.value;
            break;
    }

    if (source === undefined || source === null)
        source = "";

    // Launch a worker thread that parses the file
    let settings = {
        separator: ";",
        wantHeader: state.container.querySelector("#inferTypes").checked,
        trimValues: state.container.querySelector("#trimValues").checked,
    };

    if (state.container.querySelector("#comma").checked)
        settings.separator =  ",";

    if (state.container.querySelector("#tab").checked)
        settings.separator =  "\t";

    CSV_PARSER_WORKER.postMessage({
        source: source,
        settings: settings,
        isPreview: true,
    });
}

// Launch a worker thread for parsing the input file / manual entry
function readAllData()
{
    if (state.process.alreadyClickedImportOnce && state.importData.rows.length > 0) {
        if (!window.confirm(_tr("alerts.already_imported")))
            return false;
    }

    state.process.alreadyClickedImportOnce = false;

    // The next import must start from the beginning
    state.process.previousImportStopped = false;

    // This is technically true...
    state.process.passwordsAlteredSinceImport = true;

    state.container.querySelector("div#status div#message").classList.add("hidden");
    state.container.querySelector("div#status progress").classList.add("hidden");

    let source = null;

    // Get source data
    if (state.SETTINGS.parser.sourceTab == 0) {
        // Manual entry
        source = state.container.querySelector("div#manual textarea").value;
    } else if (state.SETTINGS.parser.sourceTab == 1) {
        // File upload
        if (state.parser.fileContents === null) {
            window.alert(_tr("alerts.no_file"));
            return;
        }

        source = state.parser.fileContents;
    } else {
        // Username list (not always available)
        source = state.container.querySelector("div#unl textarea")?.value;
    }

    if (source === undefined || source === null)
        source = "";

    // UI reset in case the previous import was stopped half-way
    resetSelection();

    // Launch a worker thread that parses the file
    let settings = {
        separator: ";",
        wantHeader: state.container.querySelector("#inferTypes").checked,
        trimValues: state.container.querySelector("#trimValues").checked
    };

    if (state.container.querySelector("#comma").checked)
        settings.separator =  ",";

    if (state.container.querySelector("#tab").checked)
        settings.separator =  "\t";

    CSV_PARSER_WORKER.postMessage({
        source: source,
        settings: settings,
        isPreview: false,
    });

    // Signal a Tab change
    return true;
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PREVIEW AND MANIPULATION

// Called when there's no data to import. Ensures everything is cleared.
function noDataToDisplay()
{
    if (state.container) {
        state.container.querySelector("div#output").innerHTML = _tr('status.no_data_to_display');
        state.container.querySelector("div#status div#message").classList.add("hidden");
        state.container.querySelector("div#status progress").classList.add("hidden");
    }

    state.parser.error = null;
    state.importData.headers = [];
    state.importData.rows = [];
    state.process.workerRows = [];
    state.process.failedRows = [];

    updateStatistics();
}

// Re-number column indexes in their header row datasets
function renumberTableColumns()
{
    const headings = state.container.querySelectorAll("div#output table thead th");

    // +1 for the messages column
    if (headings.length <= NUM_ROW_HEADERS + 1) {
        // Only the row number column is remaining, so effectively there's no data to display
        noDataToDisplay();
        return;
    }

     for (let i = NUM_ROW_HEADERS; i < headings.length - 1; i++)
        headings[i].dataset.column = i - NUM_ROW_HEADERS;
}

// Computes the start and end values for a fill-type operation. Takes the selection into account.
function getFillRange()
{
    let start = 0,
        end = state.importData.rows.length;

    if (state.selection.column == state.targetColumn.index &&
        state.selection.start !== -1 &&
        state.selection.end !== -1) {

        // We have a selection targeting this column (end is +1 because
        // the selection range is inclusive)
        start = Math.min(state.selection.start, state.selection.end);
        end = Math.max(state.selection.start, state.selection.end) + 1;
    }

    console.log(`getFillRange(): start=${start}, end=${end}`);

    return [start, end];
}

// Ends multi-cell selection
function resetSelection()
{
    state.selection.active = false;
    state.selection.mouseTrackPos = null;
    state.selection.initialClick = null;
    state.selection.previousCell = null;
    state.selection.column = -1;
    state.selection.start = -1;
    state.selection.end = -1;

    for (let cell of state.container.querySelectorAll("table tbody td.selectedCell"))
        cell.classList.remove("selectedCell");
}

// Updates multi-cell selection highlighting
function highlightSelection()
{
    if (!state.selection.active || state.selection.start == -1 || state.selection.end == -1)
        return;

    const start = Math.min(state.selection.start, state.selection.end),
          end = Math.max(state.selection.start, state.selection.end);

    // Remove highlights from all cells that aren't in the selection range anymore
    for (let cell of state.container.querySelectorAll("table tbody td.selectedCell")) {
        const row = cell.parentNode.rowIndex - 1;

        if (cell.cellIndex == state.selection.column && row >= start && row <= end)
            continue;

        cell.classList.remove("selectedCell");
    }

    // Then add it back to all cells that are in the range
    const tableRows = state.container.querySelectorAll("div#output table tbody tr");

    for (let rowNum = start; rowNum <= end; rowNum++)
        tableRows[rowNum].children[state.selection.column + NUM_ROW_HEADERS].classList.add("selectedCell");
}

function updateStatistics()
{
    let html = "";

    html += `<div>${state.statistics.totalRows} ${_tr("status.total_rows")}; ${state.statistics.selectedRows} ${_tr("status.selected_rows")}</div>`;

    // These numbers are not shown until something gets imported, but afterwards they're
    // always visible, showing the results of the previous import
    if ((state.process.importActive || state.process.alreadyClickedImportOnce) && (state.importData.rows.length > 0)) {
        html +=
            `<div>${_tr("status.importing_rows")} ${state.statistics.totalRowsProcessed}/${state.process.workerRows.length} (` +
            `<span class="success">${state.statistics.success} ${_tr("status.success")}</span>, ` +
            `<span class="partial_success">${state.statistics.partialSuccess} ${_tr("status.partial_success")}</span>, ` +
            `<span class="failed">${state.statistics.failed} ${_tr("status.failed")}</span>)</div>`;
    }

    state.container.querySelector("div#status div#rowCounts").innerHTML = html;
}

// Try to detect problems and potential errors/warnings in the table data
function detectProblems(selectRows=false)
{
    let output = state.container.querySelector("div#problems");

    if (state.importData.rows === null || state.importData.rows.length == 0) {
        // The table is empty
        noDataToDisplay();
        output.innerHTML = "";
        output.classList.add("hidden");
        return;
    }

    doDetectProblems(state.importData, state.container, state.commonPasswords, state.localizedColumnTitles, state.automaticEmails, selectRows, state.SETTINGS.import.mode == 2);

    toggleClass(output, "hidden", state.importData.errors.length == 0 && state.importData.warnings.length == 0);

    if (selectRows) {
        state.statistics.selectedRows = state.importData.countSelectedRows();
        updateStatistics();
    }
}

// --------------------------------------------------------------------------------------------------
// EVENT HANDLERS

function makeRoleSelector(current=null)
{
    const tmpl = getTemplate("selectRole");

    if (current && VALID_ROLES.has(current))
        tmpl.querySelector("select#role").value = current;
    else tmpl.querySelector("select#role").value = "student";

    return tmpl;
}

function fillGroupSelector(selector, current=null)
{
    selector.innerHTML = "";

    for (const g of state.importData.currentGroups) {
        let o = create("option");

        o.value = g.abbr;
        o.selected = (current === g.abbr);
        o.innerText = `${g.name} (${state.localizedGroupTypes[g.type] || "?"})`;

        selector.appendChild(o);
    }

    selector.disabled = (state.importData.currentGroups.length == 0);
}

function onSelectDuplicates(mode)
{
    const uidCol = state.importData.findColumn("uid");

    if (uidCol === -1) {
        window.alert(_tr("errors.required_column_missing", { title: state.localizedColumnTitles["uid"] }));
        return;
    }

    // Make a list of usernames on the table, then send them to the server for analysis.
    // Once the server returns the results, update the table and selection states to match.
    // This way we don't send thousands of usernames back to the client, when we only
    // need to know if 10 users already exists.
    let outgoingUsernames = [];

    for (let rowNum = 0; rowNum < state.importData.rows.length; rowNum++)
        outgoingUsernames.push(state.importData.rows[rowNum].cellValues[uidCol].trim());

    const request = {
        school_id: state.importData.currentSchoolID,
        usernames: outgoingUsernames,
    };

    enableUI(false);

    beginPOST("new_import/find_existing_users", request).then(data => {
        // Make a list of current users
        const states = parseServerJSON(data);

        if (states === null) {
            window.alert(_tr("alerts.cant_parse_server_response"));
            return;
        }

        if (states.status != "ok") {
            if (states.error)
                window.alert(_tr("alerts.data_retrieval_failed_known") + "\n\n" + states.error);
            else window.alert(_tr("alerts.data_retrieval_failed_unknown"));

            return;
        }

        // Update selections
        const tableRows = state.container.querySelectorAll(`div#output table tbody tr`);

        state.statistics.selectedRows = 0;

        let haveErrors = false;

        for (let rowNum = 0; rowNum < state.importData.rows.length; rowNum++) {
            const uid = outgoingUsernames[rowNum];
            const s = states.states[rowNum];

            let select = false,
                message = null;

            switch (s[0]) {
                case -1:
                    // Something failed on the server when this user was being looked up
                    haveErrors = true;
                    break;

                case 0:
                default:
                    // This user does not exist on the server
                    break;

                case 1:
                    // This user exists and is in this school
                    if (mode == Duplicates.ALL || mode == Duplicates.THIS_SCHOOL)
                        select = true;

                    break;

                case 2:
                    // This user exists, but they're in some other school
                    if (mode == Duplicates.ALL)
                        select = true;
                    else if (mode == Duplicates.OTHER_SCHOOLS) {
                        select = true;
                        message = _tr("messages.already_in_school", { schools: s[1].join(", ") });
                    }

                    break;
            }

            // Update the table
            const row = state.importData.rows[rowNum];
            const checkbox = tableRows[rowNum].querySelector("input");

            row.message = message;

            if (select) {
                row.rowFlags |= RowFlag.SELECTED;
                checkbox.checked = true;
                state.statistics.selectedRows++;
            } else {
                row.rowFlags &= ~RowFlag.SELECTED;
                checkbox.checked = false;
            }

            tableRows[rowNum].querySelector("td.message").innerText = message;
        }

        updateStatistics();
    }).catch(error => {
        console.error(error);
        window.alert(_tr("alerts.cant_parse_server_response"));
    }).finally(() => {
        enableUI(true);
    });
}

function onAnalyzeDuplicates()
{
    enableUI(false);

    beginGET("new_import/duplicate_detection").then(data => {
        const existing = parseServerJSON(data);

        if (existing === null) {
            window.alert(_tr("alerts.cant_parse_server_response"));
            return;
        }

        if (existing.status != "ok") {
            if (existing.error)
                window.alert(_tr("alerts.data_retrieval_failed_known") + "\n\n" + existing.error);
            else window.alert(_tr("alerts.data_retrieval_failed_unknown"));

            return;
        }

        let eid = new Map(),
            email = new Map(),
            phone = new Map();

        for (const u of existing["users"]) {
            const uid = u["username"];

            if (u["external_id"])
                eid.set(u["external_id"], uid);

            if (u["email"] !== null)
                for (const e of u["email"])
                    email.set(e, uid);

            if (u["phone"] !== null)
                for (const p of u["phone"])
                    phone.set(p, uid);
        }

        state.importData.serverUsers.eid = eid;
        state.importData.serverUsers.email = email;
        state.importData.serverUsers.phone = phone;

        // The "true" argument actually selects the rows
        detectProblems(true);
    }).catch(error => {
        console.error(error);
        window.alert(_tr("alerts.cant_parse_server_response"));
    }).finally(() => {
        enableUI(true);
    });
}

// Select, deselect or invert row selections
function onSelectRows(operation)
{
    const rows = state.container.querySelectorAll(`div#output table tbody tr input[type="checkbox"]`);

    state.statistics.selectedRows = 0;

    switch (operation) {
        case 0:
            for (let cb of rows)
                cb.checked = false;

            for (let row of state.importData.rows)
                row.rowFlags &= ~RowFlag.SELECTED;

            break;

        case 1:
            for (let cb of rows)
                cb.checked = true;

            for (let row of state.importData.rows)
                row.rowFlags |= RowFlag.SELECTED;

            state.statistics.selectedRows = rows.length;
            break;

        case -1:
            for (let cb of rows) {
                cb.checked = !cb.checked;

                if (cb.checked)
                    state.statistics.selectedRows++;
            }

            for (let row of state.importData.rows) {
                if (row.rowFlags & RowFlag.SELECTED)
                    row.rowFlags &= ~RowFlag.SELECTED;
                else row.rowFlags |= RowFlag.SELECTED;
            }

            break;
    }

    updateStatistics();
}

function onRowCheckboxClick(e)
{
    const rowNum = parseInt(e.target.parentNode.parentNode.dataset.row, 10);
    const row = state.importData.rows[rowNum];

    if (e.target.checked) {
        row.rowFlags |= RowFlag.SELECTED;
        state.statistics.selectedRows++;
    } else {
        row.rowFlags &= ~RowFlag.SELECTED;
        state.statistics.selectedRows--;
    }

    /*if (state.process.checkOnlySelectedRows)
        detectProblems();
    else*/ updateStatistics();
}

function onSelectProcessedRows(mode)
{
    const checkboxes = state.container.querySelectorAll(`div#output table tbody tr input[type="checkbox"]`);

    state.statistics.selectedRows = 0;

    for (let rowNum = 0; rowNum < state.importData.rows.length; rowNum++) {
        const row = state.importData.rows[rowNum],
              checkbox = checkboxes[rowNum];

        if (row.rowState == mode) {
            row.rowFlags |= RowFlag.SELECTED;
            checkbox.checked = true;
            state.statistics.selectedRows++;
        } else {
            row.rowFlags &= ~RowFlag.SELECTED;
            checkbox.checked = false;
        }
    }

    updateStatistics();
}

function onDeleteSelectedRows()
{
    if (state.process.previousImportStopped) {
        window.alert(_tr("alerts.cant_remove_rows_after_stopping"));
        return;
    }

    // Make a list of selected table rows
    let selectedRows = [];

    for (let cb of state.container.querySelectorAll(`div#output table tbody tr input[type="checkbox"]:checked`))
        selectedRows.push(parseInt(cb.closest("tr").dataset.row, 10));

    if (selectedRows.length == 0) {
        window.alert(_tr("alerts.no_selected_rows"));
        return;
    }

    if (selectedRows.length == state.importData.rows.length) {
        // Confirm whole table removal
        if (!window.confirm(_tr("alerts.delete_everything")))
            return;
    } else {
        if (!window.confirm(_tr("alerts.delete_selected_rows", { count: selectedRows.length })))
            return;
    }

    resetSelection();

    if (selectedRows.length == state.importData.rows.length) {
        // Faster path for whole table deletion
        noDataToDisplay();
    } else {
        // Delete the selected rows. Live-update the table (don't rebuild it wholly).
        let tableRows = state.container.querySelectorAll("div#output table tbody tr");

        for (let i = selectedRows.length - 1; i >= 0; i--) {
            const rowNum = selectedRows[i];

            console.log(`Removing row ${rowNum}`);
            state.importData.rows.splice(rowNum, 1);
            tableRows[rowNum].parentNode.removeChild(tableRows[rowNum]);
        }

        // Reindex the remaining rows
        if (state.importData.rows.length == 0)
            noDataToDisplay();
        else {
            const rows = state.container.querySelectorAll("div#output table tbody tr");

            for (let rowNum = 0; rowNum < rows.length; rowNum++)
                rows[rowNum].dataset.row = rowNum;
        }
    }

    state.statistics.totalRows = state.importData.rows.length;
    state.statistics.selectedRows = 0;

    detectProblems();
    updateStatistics();
}

// Called when the column type is changed from the combo box
function onColumnTypeChanged(e)
{
    const columnIndex = parseInt(e.target.parentNode.parentNode.dataset.column, 10);

    state.importData.headers[columnIndex] = e.target.value;
    const isUnused = (state.importData.headers[columnIndex] == "");

    resetSelection();

    for (const tableRow of state.container.querySelectorAll("div#output table tbody tr")) {
        const tableCell = tableRow.children[columnIndex + NUM_ROW_HEADERS];

        // detectProblems() removes the error class, but only
        // if the cell type is what it is looking for
        tableCell.classList.remove("error");

        toggleClass(tableCell, "skipped", isUnused);
        toggleClass(tableCell, "password", state.importData.headers[columnIndex] == "password");
    }

    detectProblems();
    updateStatistics();
}

function onDeleteColumn(e)
{
    e.preventDefault();

    if (!window.confirm(_tr("alerts.delete_column")))
        return;

    closePopup();
    clearMenuButtons();
    resetSelection();

    const column = state.targetColumn.index;

    console.log(`Deleting column ${column}`);

    // Remove the column from the parsed data
    for (let row of state.importData.rows) {
        row.cellValues.splice(column, 1);
        row.cellFlags.splice(column, 1);
    }

    state.importData.headers.splice(column, 1);

    // Remove the table column
    for (let tableRow of state.container.querySelector("div#output table").rows)
        tableRow.deleteCell(column + NUM_ROW_HEADERS);

    // If there are no columns left, remove all rows
    if (state.importData.headers.length == 0) {
        state.importData.rows = [];
        state.statistics.totalRows = 0;
        state.statistics.selectedRows = 0;
    }

    renumberTableColumns();
    detectProblems();
    updateStatistics();
}

function onClearColumn(e)
{
    e.preventDefault();

    if (!window.confirm(_tr("alerts.are_you_sure")))
        return;

    closePopup();
    clearMenuButtons();

    const column = state.targetColumn.index,
          [start, end] = getFillRange();

    console.log(`Clearing column ${column}`);

    for (let row = start; row < end; row++) {
        state.importData.rows[row].cellValues[column] = "";
        state.importData.rows[row].cellFlags[column] = 0;
    }

    const tableRows = state.container.querySelectorAll("div#output table tbody tr");

    for (let row = start; row < end; row++) {
        const tableCell = tableRows[row].children[column + NUM_ROW_HEADERS];

        tableCell.innerText = "";
        tableCell.classList.add("empty");
    }

    detectProblems();
    updateStatistics();
}

// Inserts a new empty column on the right side
function onInsertColumn(e)
{
    e.preventDefault();

    closePopup();
    clearMenuButtons();
    resetSelection();

    const column = state.targetColumn.index;

    console.log(`Inserting a new column after column ${column}`);

    for (let row of state.importData.rows) {
        row.cellValues.splice(column + 1, 0, "");
        row.cellFlags.splice(column + 1, 0, 0);
    }

    state.importData.headers.splice(column + 1, 0, "");

    // Insert a header cell. The index number isn't important, as the columns are reindexed after.
    const row = state.container.querySelector("div#output table thead tr");

    row.insertBefore(buildColumnHeader(0, ""), row.children[column + NUM_ROW_HEADERS + 1]);

    // Then empty table cells
    for (let tableRow of state.container.querySelector("div#output table tbody").rows) {
        const tableCell = create("td");

        tableCell.innerText = "";
        tableCell.classList.add("empty", "skipped", "value");
        tableRow.insertBefore(tableCell, tableRow.children[column + NUM_ROW_HEADERS + 1]);
    }

    renumberTableColumns();
    detectProblems();
    updateStatistics();
}

// Dynamically reload the schools' group list. This is called from the "proper" group add dialog,
// but also from the direct cell edit popup. Both dialogs have the same essential controls.
function onReloadGroups(e)
{
    e.target.textContent = _tr("buttons.reloading");
    e.target.disabled = true;
    popup.contents.querySelector("select#abbr").disabled = true;

    const previous = popup.contents.querySelector("select#abbr").value;

    beginGET("new_import/reload_groups").then(data => {
        const newGroups = parseServerJSON(data);

        if (newGroups === null) {
            window.alert(_tr("alerts.cant_parse_server_response"));
            return;
        }

        state.importData.setGroups(newGroups);

        // Update the combo on-the-fly, if the popup still exists (it could have been closed
        // while fetch() was doing its job)
        if (popup && popup.contents)
            fillGroupSelector(popup.contents.querySelector("select#abbr"), previous);
    }).catch(error => {
        console.error(error);
        window.alert(_tr("alerts.cant_parse_server_response"));
    }).finally(() => {
        // Re-enable the reload button
        e.target.textContent = _tr("buttons.reload_groups");
        e.target.disabled = false;
    });
}

// Fill/generate column/selection contents
function onFillColumn(e)
{
    const targetID = e.target.id;
    e.preventDefault();

    const column = state.targetColumn.index,
          type = state.importData.headers[column];

    const selection = (state.selection.column == state.targetColumn.index &&
                       state.selection.start !== -1 && state.selection.end !== -1);

    const dialog = getTemplate("fillDialogCommon");

    const setTitle = (title) => {
        // The dialog template has a <header> element for all possible tools (so that we can use
        // Rails' t() for translating them). Remove them all except the one we actually want.
        const headers = dialog.querySelectorAll("header");

        for (let i = headers.length - 1; i >= 0; i--)
            if (headers[i].dataset.for != title)
                headers[i].remove();
    };

    const showButton = (title) => {
        // Do the same for the accept button
        const buttons = dialog.querySelectorAll("div.buttons button");

        for (let i = buttons.length - 1; i >= 0; i--)
            if (buttons[i].id != "close" && buttons[i].dataset.for != title)
                buttons[i].remove();
    };

    const check = (id, checked) => { content.querySelector(`input#${id}`).checked = checked; };

    let width = 250,
        content = null;

    // By default, the "overwrite existing values" checkbox is displayed. Set to false to
    // hide it.
    let supportsOverwrite = true;

    switch (type) {
        case "role":
            setTitle("set_role");
            showButton("set");
            content = makeRoleSelector();
            break;

        case "group":
            if (targetID == "parse_groups") {
                setTitle("parse_groups");
                showButton("generate");
                width = 400;
                content = getTemplate("parseGroups");

                const rawCol = state.importData.findColumn("rawgroup");

                if (rawCol === -1) {
                    window.alert(_tr("alerts.need_one_raw_group"));
                    return;
                }

                // Make a base selector and duplicate it for every row
                let selector = create("select");

                fillGroupSelector(selector, null);

                let tab = content.querySelector("div#parseGroupsTable table tbody")

                for (let i = 0; i < state.importData.rows.length; i++) {
                    let values = state.importData.rows[i].cellValues,
                        unique = true;

                    for (let i = 0; i < tab.rows.length; i++)
                        if (tab.rows[i].cells[0].innerText == values[rawCol])
                            unique = false;

                    if (unique) {
                        let tr = document.createElement("tr");
                        let nametd = document.createElement("td");

                        nametd.textContent = values[rawCol];
                        tr.appendChild(nametd);

                        let grouptd = document.createElement("td");
                        let thisselect=selector.cloneNode(true)
                        grouptd.appendChild(thisselect);
                        for(let j = 0; j < thisselect.options.length;j++) // try to automatically guess the right one, this often is enough
                        {
                            let len=(thisselect.options[j].text.length > nametd.textContent.length ? nametd.textContent.length : thisselect.options[j].text.length)
                            if(thisselect.options[j].text.substring(0,len).toLowerCase() == nametd.textContent.substring(0,len).toLowerCase())
                            {
                                thisselect.options[j].selected = true
                                continue
                            }
                        }
                        tr.appendChild(grouptd);

                        tab.appendChild(tr);
                    }
                }
            } else {
                setTitle("set_group");
                showButton("add");
                width = 300;

                const tmpl = getTemplate("selectGroup");

                fillGroupSelector(tmpl.querySelector("select#abbr"));
                tmpl.querySelector("button#reload").addEventListener("click", onReloadGroups);

                content = tmpl;
            }

            break;

        case "uid":
            setTitle("generate_usernames");
            showButton("generate");
            width = 350;

            content = getTemplate("generateUsernames");

            // Restore settings and setup events for saving them when changed
            check("drop", state.SETTINGS.import.username.umlauts == 0);
            check("replace", state.SETTINGS.import.username.umlauts == 1);
            check("first_first_only", state.SETTINGS.import.username.first_first_only == true);

            content.querySelector("#drop").addEventListener("click", () => {
                state.SETTINGS.import.username.umlauts = 0;
                saveSettings(state.SETTINGS);
            });

            content.querySelector("#replace").addEventListener("click", () => {
                state.SETTINGS.import.username.umlauts = 1;
                saveSettings(state.SETTINGS);
            });

            content.querySelector("#first_first_only").addEventListener("click", (e) => {
                state.SETTINGS.import.username.first_first_only = e.target.checked;
                saveSettings(state.SETTINGS);
            });

            break;

        case "password":
            setTitle("generate_passwords");
            showButton("generate");
            width = 350;

            content = getTemplate("generatePasswords");

            // Restore settings and setup events for saving them when changed
            check("fixed", !state.SETTINGS.import.password.randomize);
            check("random", state.SETTINGS.import.password.randomize);
            check("uppercase", state.SETTINGS.import.password.uppercase);
            check("lowercase", state.SETTINGS.import.password.lowercase);
            check("numbers", state.SETTINGS.import.password.numbers);
            check("punctuation", state.SETTINGS.import.password.punctuation);

            const len = clampPasswordLength(parseInt(state.SETTINGS.import.password.length, 10));
            let e = content.querySelector(`input#length`);

            e.min = MIN_PASSWORD_LENGTH;
            e.max = MAX_PASSWORD_LENGTH;
            e.value = len;

            content.querySelector("div#lengthValue").innerText = len;

            for (let i of content.querySelectorAll("input")) {
                i.addEventListener("click", e => {
                    if (e.target.id == "fixed")
                        state.SETTINGS.import.password.randomize = false;
                    else if (e.target.id == "random")
                        state.SETTINGS.import.password.randomize = true;
                    else if (e.target.id == "length")
                        state.SETTINGS.import.password.length = clampPasswordLength(parseInt(e.target.value, 10));
                    else state.SETTINGS.import.password[e.target.id] = e.target.checked;

                    saveSettings(state.SETTINGS);
                });
            };

            content.querySelector("input#length").addEventListener("input", e => {
                // "content" (and thus querySelector()) does not exist in this context,
                // have to use nextSibling
                e.target.nextSibling.innerText = e.target.value
                state.SETTINGS.import.password.length = clampPasswordLength(parseInt(e.target.value, 10));
                saveSettings(state.SETTINGS);
            });

            break;

        default:
            setTitle(selection ? "fill_selection" : "fill_column");
            showButton("fill");

            content = getTemplate("genericFill");

            if (selection)
                content.querySelector("label#column").remove();
            else content.querySelector("label#selection").remove();

            break;
    }

    // The popup is already open (menu), so just replace its contents
    if (content)
        dialog.querySelector("div#contents").appendChild(content);
    else {
        dialog.querySelector("div#contents").innerHTML =
            `<p class="error">ERROR: "content" is NULL. Please contact support.</p>`;
    }

    popup.contents.style.width = `${width}px`;
    popup.contents.innerHTML = "";
    popup.contents.appendChild(dialog);

    // The column tool popup is attached to the same element the menu was (the tools button),
    // no need to re-attach it
    ensurePopupIsVisible();

    // Restore settings and set event handling so that changed settings are saved
    let ow = popup.contents.querySelector(`input[type="checkbox"]#overwrite`);

    ow.checked = state.SETTINGS.import.overwrite;

    if (supportsOverwrite) {
        ow.addEventListener("click", e => {
            state.SETTINGS.import.overwrite = e.target.checked;
            saveSettings(state.SETTINGS);
        });
    } else popup.contents.querySelector(`input[type="checkbox"]#overwrite`).parentNode.classList.add("hidden");

    // If this popup has an input field, focus it
    if (type == "first" || type == "last" || type == "phone" || type == "email" ||
        type == "eid" || type == "pnumber" || type == "rawgroup" || type == "")
        popup.contents.querySelector("input#value").focus();

    // All types have these two buttons
    popup.contents.querySelector("button#fill").addEventListener("click", onClickFillColumn);

    popup.contents.querySelector("button#close").addEventListener("click", e => {
        closePopup();
        clearMenuButtons();
    });
}

// Actually do the column filling/generation
function onClickFillColumn(e)
{
    const type = state.importData.headers[state.targetColumn.index];
    const overwrite = popup.contents.querySelector("input#overwrite").checked;
    let value, value2;

    // Generate the values
    switch (type) {
        case "uid":
            // value reused for the umlaut conversion type selection
            value = popup.contents.querySelector("input#drop").checked;
            value2 = popup.contents.querySelector("input#first_first_only").checked;
            console.log(`Generating usernames for column ${state.targetColumn.index}, mode=${value}, first_first_only=${value2} (overwrite=${overwrite})`);
            generateUsernames(!value, value2, overwrite);
            return;

        case "password":
            console.log(`Generating/filling passwords for column ${state.targetColumn.index}, (overwrite=${overwrite})`);
            generatePasswords(overwrite);
            state.process.passwordsAlteredSinceImport = true;
            return;

        case "role":
            value = popup.contents.querySelector("select#role").value,
            console.log(`Filling roles in column ${state.targetColumn.index}, role=${value}`);
            break;

        case "group":
            if (state.importData.currentGroups.length === 0) {
                window.alert(_tr("alerts.no_groups"));
                return;
            }

            if (popup.contents.querySelector("header").dataset.for == "parse_groups") {
                let groupTable = popup.contents.querySelector("div#parseGroupsTable table tbody"),
                    groupMappings = {};

                for (let i = 0; i < groupTable.rows.length; i++)
                    groupMappings[groupTable.rows[i].cells[0].innerText] = groupTable.rows[i].cells[1].children[0].value;

                console.log(`Filling group in column ${state.targetColumn.index} by parsing rawgroup column, mappings:`);

                for (const [k, v] of Object.entries(groupMappings))
                    console.log(`"${k}" -> "${v}"`);

                parseGroups(groupMappings, overwrite);
                return;
            } else {
                value = popup.contents.querySelector("select#abbr").value;
                console.log(`Filling group in column ${state.targetColumn.index}, group abbreviation=${value} (overwrite=${overwrite})`);
            }

            break;

        default:
            value = popup.contents.querySelector("input#value").value;
            console.log(`Filling column ${state.targetColumn.index} with "${value}" (overwrite=${overwrite})`);
            break;
    }

    // Update the table in-place
    let tableRows = state.container.querySelectorAll("div#output table tbody tr");

    const [start, end] = getFillRange();

    for (let i = start; i < end; i++) {
        let values = state.importData.rows[i].cellValues;

        if (values[state.targetColumn.index] != "" && !overwrite)
            continue;

        let tableCell = tableRows[i].children[state.targetColumn.index + NUM_ROW_HEADERS];

        values[state.targetColumn.index] = value;
        tableCell.innerText = value;

        if (value == "")
            tableCell.classList.add("empty");
        else tableCell.classList.remove("empty");
    }

    // The popup dialog remains open, on purpose
    detectProblems();
    updateStatistics();
}

// Generates usernames
function generateUsernames(alternateUmlauts, firstFirstNameOnly, overwrite)
{
    // ----------------------------------------------------------------------------------------------
    // First verify that we have first and last name columns

    let numFirst = 0,
        firstCol = 0,
        numLast = 0,
        lastCol = 0;

    const headers = state.container.querySelectorAll("div#output table thead th");

    for (let i = 0; i < state.importData.headers.length; i++) {
        // The possibility of having multiple first name/last name columns is small, but
        // it can happen to an absent-minded user. Let's handle that case too.
        if (state.importData.headers[i] === "first") {
            numFirst++;
            firstCol = i;
        }

        if (state.importData.headers[i] === "last") {
            numLast++;
            lastCol = i;
        }
    }

    if (numFirst != 1) {
        window.alert(_tr("alerts.need_one_first_name"));
        return;
    }

    if (numLast != 1) {
        window.alert(_tr("alerts.need_one_last_name"));
        return;
    }

    // ----------------------------------------------------------------------------------------------
    // Then generate the names

    const [start, end] = getFillRange();

    let missing = false;
    let unconvertable = [];

    // Change data and update the table, in one loop
    let tableRows = state.container.querySelectorAll("div#output table tbody tr");

    for (let rowNum = start; rowNum < end; rowNum++) {
        let values = state.importData.rows[rowNum].cellValues;

        // Missing values?
        if (values[firstCol].trim().length == 0) {
            missing = true;
            continue;
        }

        if (values[lastCol].trim().length == 0) {
            missing = true;
            continue;
        }

        // Generate a username
        let first = values[firstCol].toLowerCase(),
            last = values[lastCol].toLowerCase();

        if (firstFirstNameOnly) {
            const space = first.indexOf(" ");

            if (space != -1)
                first = first.substring(0, space);
        }

        first = dropDiacritics(first, alternateUmlauts);
        last = dropDiacritics(last, alternateUmlauts);

        const username = `${first}.${last}`;

        if (first.length == 0 || last.length == 0) {
            console.error(`Can't generate username for "${columns[firstCol]} ${columns[lastCol]}"`);
            unconvertable.push([i + NUM_ROW_HEADERS, columns[firstCol], columns[lastCol]]);
            continue;
        }

        if (values[state.targetColumn.index] != "" && !overwrite)
            continue;

        let tableCell = tableRows[rowNum].children[state.targetColumn.index + NUM_ROW_HEADERS];

        values[state.targetColumn.index] = username;
        tableCell.innerText = username;
        tableCell.classList.remove("empty");
    }

    // ----------------------------------------------------------------------------------------------
    // End reports

    // Update the table before displaying the message boxes
    detectProblems();
    updateStatistics();

    if (missing)
        window.alert(_tr("alerts.could_not_generate_all_usernames"));

    if (unconvertable.length > 0) {
        let msg = _tr("alerts.unconvertible_characters", { count: unconvertable.length }) + "\n\n";

        if (unconvertable.length > 5)
            msg += _tr("alerts.first_five") + "\n\n";

        for (let i = 0; i < Math.min(unconvertable.length, 5); i++) {
            const u = unconvertable[i];

            msg += _tr("alerts.unconvertible_name", { row: u[0], first: u[1], last: u[2] }) + "\n";
        }

        window.alert(msg);
    }
}

// Parse groups based on the rawgroup column
function parseGroups(magicTable, overwrite)
{
    // Verify that there's one source column for us
    let numRawgroup = 0,
        rawCol = 0;

    for (let i = 0; i < state.importData.headers.length; i++) {
        if (state.importData.headers[i] === "rawgroup") {
            numRawgroup++;
            rawCol = i;
        }
    }

    if (numRawgroup != 1) {
        window.alert(_tr("alerts.need_one_raw_group"));
        return;
    }

    const [start, end] = getFillRange();
    let missing = false;

    // Change data and update the table, in one loop
    let tableRows = state.container.querySelectorAll("div#output table tbody tr");

    for (let rowNum = start; rowNum < end; rowNum++) {
        let values = state.importData.rows[rowNum].cellValues;

        if (values[state.targetColumn.index] != "" && !overwrite)
            continue;

        // Parse the group names
        let processedGroup = values[rawCol];

        if (magicTable[processedGroup])
            processedGroup = magicTable[processedGroup];
        else missing = true;

        let tableCell = tableRows[rowNum].children[state.targetColumn.index + NUM_ROW_HEADERS];

        values[state.targetColumn.index] = processedGroup;
        tableCell.innerText = processedGroup;
        tableCell.classList.remove("empty");
    }

    // ----------------------------------------------------------------------------------------------
    // End reports

    // Update the table before displaying the message boxes
    detectProblems();
    updateStatistics();

    if (missing)
        window.alert(_tr("alerts.could_not_parse_all_groups"));
}

// Generates random passwords
function generatePasswords(overwrite)
{
    const tableRows = state.container.querySelectorAll("div#output table tbody tr");
    const [start, end] = getFillRange();

    // ----------------------------------------------------------------------------------------------
    // Set all to the same password (don't use this!)

    if (popup.contents.querySelector("input#fixed").checked) {
        if (!window.confirm(_tr("alerts.same_password")))
            return;

        const password = popup.contents.querySelector("input#fixedPassword").value;

        if (password.length < MIN_PASSWORD_LENGTH) {
            window.alert(_tr("alerts.too_short_password", { length: MIN_PASSWORD_LENGTH }));
            return;
        }

        for (let rowNum = start; rowNum < end; rowNum++) {
            const values = state.importData.rows[rowNum].cellValues;

            if (values[state.targetColumn.index] != "" && !overwrite)
                continue;

            const tableCell = tableRows[rowNum].children[state.targetColumn.index + NUM_ROW_HEADERS];

            values[state.targetColumn.index] = password;
            tableCell.innerText = password;
            tableCell.classList.remove("empty");
        }

        detectProblems();
        updateStatistics();
        return;
    }

    // ----------------------------------------------------------------------------------------------
    // Generate random passwords

    let available = "";

    if (popup.contents.querySelector("input#uppercase").checked)
        available += shuffleString("ABCDEFGHJKLMNPQRSTUVWXYZ");

    if (popup.contents.querySelector("input#lowercase").checked)
        available += shuffleString("abcdefghijkmnopqrstuvwxyz");

    if (popup.contents.querySelector("input#numbers").checked)
        available += shuffleString("123456789");

    if (popup.contents.querySelector("input#punctuation").checked)
        available += shuffleString(".,;:@£$+?#%&=\"/\\{}[]()");

    if (available.length == 0) {
        window.alert(_tr("alerts.check_something"));
        return;
    }

    available = shuffleString(available);

    const length = parseInt(popup.contents.querySelector("input#length").value, 10);

    // This should not happen, as the input control won't let you to type in the length manually
    if (length < MIN_PASSWORD_LENGTH) {
        window.alert(_tr("alerts.too_short_password", { length: MIN_PASSWORD_LENGTH }));
        return;
    }

    for (let rowNum = start; rowNum < end; rowNum++) {
        const values = state.importData.rows[rowNum].cellValues;

        if (values[state.targetColumn.index] != "" && !overwrite)
            continue;

        const tableCell = tableRows[rowNum].children[state.targetColumn.index + NUM_ROW_HEADERS];

        // Generate a random password
        const max = available.length;
        let password = "";

        // TODO: use crypto.getRandomValues() for proper random numbers? It returns values that
        // are OOB of the 'available' array and % can cause ugly repetitions, so the values cannot
        // be used directly.
        for (let j = 0; j < length; j++)
            password += available[Math.floor(Math.random() * max)];

        password = shuffleString(password);

        values[state.targetColumn.index] = password;
        tableCell.innerText = password;
        tableCell.classList.remove("empty");
    }

    detectProblems();
    updateStatistics();
}

// Open the column popup menu
function onOpenColumnMenu(e)
{
    state.targetColumn.column = e.target.parentNode.parentNode;
    state.targetColumn.index = parseInt(state.targetColumn.column.dataset.column, 10);

    e.target.classList.add("activeMenu");
    e.target.disabled = true;       // pressing Enter/Space would open another popup menu

    const selection = (state.selection.column == state.targetColumn.index &&
                       state.selection.start !== -1 && state.selection.end !== -1);

    let fillTitle = null;

    let tmpl = getTemplate("columnMenu");

    // By default the menu contains all entries. Remove those that don't apply to this situation.
    let keep = [],
        actions = [],
        enableFill = true,
        enableClear = false;

    // Menu width, in pixels. Override if needed.
    let width = 200;

    switch (state.importData.headers[state.targetColumn.index]) {
        case "":
            // Allow ignored columns to be cleared
            enableClear = true;
            break;

        case "role":
            keep.push("set_role");
            actions.push("set_role");
            enableFill = false;
            break;

        case "uid":
            keep.push("generate_usernames");
            actions.push("generate_usernames");
            enableFill = false;
            break;

        case "password":
            keep.push("generate_passwords");
            actions.push("generate_passwords");
            enableFill = false;
            enableClear = true;
            break;

        case "rawgroup":
            // Nothing to do
            break;

        case "group":
            keep.push("parse_groups", "add_to_group");
            actions.push("parse_groups", "add_to_group");
            enableFill = false;
            enableClear = true;
            break;

        case "email":
        case "phone":
        case "eid":
        case "pnumber":
            // These values must be unique, so filling them with the same value would be pointless
            enableFill = false;

            // But since they're optional, they can be empty
            enableClear = true;
            break;

        default:
            break;
    }

    keep.push("insert_column", "delete_column");

    if (enableFill)
        keep.push(selection ? "fill_selection" : "fill_column");

    if (enableClear)
        keep.push(selection ? "clear_selection" : "clear_column");

    console.log(keep);

    for (const e of tmpl.querySelectorAll("a"))
        if (!keep.includes(e.id))
            e.parentNode.remove();

    // These two entries always exist
    tmpl.querySelector("a#insert_column").addEventListener("click", onInsertColumn);
    tmpl.querySelector("a#delete_column").addEventListener("click", onDeleteColumn);

    // But these are optional
    tmpl.querySelector(`a#${selection ? "fill_selection" : "fill_column"}`)?.addEventListener("click", onFillColumn);
    tmpl.querySelector(`a#${selection ? "clear_selection" : "clear_column"}`)?.addEventListener("click", onClearColumn);

    for (const a of actions)
        tmpl.querySelector(`a#${a}`).addEventListener("click", onFillColumn);

    // Open the popup menu
    createPopup();
    popup.contents.style.width = `${width}px`;
    popup.contents.appendChild(tmpl);

    const location = e.target.getBoundingClientRect();

    attachPopup(e.target, PopupType.COLUMN_MENU);
    displayPopup();

    document.body.addEventListener("keydown", onKeyDown);
}

// Potentially start a multi-cell selection
function onMouseDown(e)
{
    if (state.process.importActive)
        return;

    if (e.target.tagName != "TD")
        return;

    if (!e.target.classList.contains("value"))
        return;

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    e.preventDefault();

    state.selection.mouseTrackPos = {
        x: e.clientX,
        y: e.clientY
    };

    state.selection.initialClick = e.target;
    state.selection.column = -1;
    state.selection.start = -1;
    state.selection.end = -1;

    for (let cell of state.container.querySelectorAll("table tbody td.selectedCell"))
        cell.classList.remove("selectedCell");

    // Start tracking the mouse and see if this is a single-cell click, or a multi-cell drag
    document.addEventListener("mouseup", onMouseUp);
    document.addEventListener("mousemove", onMouseMove);
}

// Stop multi-cell selection
function onMouseUp(e)
{
    if (state.process.importActive)
        return;

    e.preventDefault();

    state.selection.active = false;
    state.selection.mouseTrackPos = null;
    state.selection.initialClick = null;
    state.selection.previousCell = null;

    document.removeEventListener("mouseup", onMouseUp);
    document.removeEventListener("mousemove", onMouseMove);
}

// Initiate/update multi-cell selection
function onMouseMove(e)
{
    if (state.process.importActive)
        return;

    e.preventDefault();

    if (state.selection.active) {
        // Update multi-cell drag selection
        if (e.target == state.selection.previousCell)
            return;

        let current = document.elementFromPoint(e.clientX, e.clientY);

        if (!current || current.tagName != "TD") {
            // This can happen if the mouse goes outside of the browser window.
            // Don't cancel the selection.
            return;
        }

        const newEnd = clamp(current.parentNode.rowIndex - 1, 0, state.importData.rows.length);

        if (newEnd != state.selection.end) {
            state.selection.end = newEnd;
            highlightSelection();
        }

        state.selection.previousCell = e.target;
        return;
    }

    // See if we should start a multi-cell selection. We need some tolerance here, because
    // the mouse can move a pixel or two during double-clicks, and we don't want those tiny
    // movements to trigger a selection.
    const dx = e.clientX - state.selection.mouseTrackPos.x,
          dy = e.clientY - state.selection.mouseTrackPos.y;

    const dist = Math.sqrt(dx * dx + dy * dy);

    if (dist < 5.0)
        return;

    // Yes, start multi-cell selection
    for (let cell of state.container.querySelectorAll("table tbody td.selectedCell"))
        cell.classList.remove("selectedCell");

    state.selection.initialClick.classList.add("selectedCell");

    state.selection.active = true;
    state.selection.column = state.selection.initialClick.cellIndex - NUM_ROW_HEADERS;
    state.selection.start = state.selection.initialClick.parentNode.rowIndex - 1;

    console.log(`Multi-cell selection initiated, col=${state.selection.column}, row=${state.selection.start}`);

    // The mouse can be move across multiple cells during the dragging period
    if (e.target == state.selection.initialClick)
        state.selection.end = e.target.parentNode.rowIndex - 1;
    else state.selection.end = document.elementFromPoint(e.clientX, e.clientY).parentNode.rowIndex - 1;

    highlightSelection();
}

// Directly edit a cell's value
function onMouseDoubleClick(e)
{
    if (state.process.importActive)
        return;

    if (e.target.tagName != "TD")
        return;

    if (!e.target.classList.contains("value"))
        return;

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    e.preventDefault();

    state.directCellEdit.pos = {
        row: e.target.parentNode.rowIndex - 1,
        col: e.target.cellIndex - NUM_ROW_HEADERS
    };

    state.directCellEdit.target = e.target;

    const type = state.importData.headers[state.directCellEdit.pos.col];
    let value = e.target.innerText;

    console.log(`Editing cell (${state.directCellEdit.pos.row}, ${state.directCellEdit.pos.col}) directly, type=${type}`);

    const tmpl = getTemplate("directCellEdit");
    const contents = tmpl.querySelector("div#contents");

    switch (type) {
        case "role":
            contents.appendChild(makeRoleSelector(value));
            break;

        case "group": {
            const tmpl = getTemplate("selectGroup");

            fillGroupSelector(tmpl.querySelector("select#abbr"), value);
            tmpl.querySelector("button#reload").addEventListener("click", onReloadGroups);
            contents.appendChild(tmpl);
            break;
        }

        default: {
            const tmpl = getTemplate("directCellEditText");
            const edit = tmpl.childNodes[1];

            if (type == "password") {
                edit.classList.remove("cellEdit");
                edit.classList.add("cellEditPassword");
            }

            edit.value = value;
            contents.appendChild(tmpl);
            break;
        }
    }

    tmpl.querySelector("button#save").addEventListener("click", onSaveCellValue);
    tmpl.querySelector("button#close").addEventListener("click", () => { closePopup(); });

    createPopup();
    popup.contents.appendChild(tmpl);

    // Display the popup
    const location = e.target.getBoundingClientRect();

    // TODO: Figure out where these numbers come from. I just wiggled them until they looked good.
    attachPopup(e.target, PopupType.CELL_EDIT, location.right - location.left + 11);
    displayPopup();

    document.body.addEventListener("keydown", onKeyDown);

    // Try to focus the input box
    let input = popup.contents.querySelector(`input[type="text"]`);

    if (input) {
        input.focus();
        input.selectionStart = input.selectionEnd = input.value.length;
    }
}

// Save the new value of a cell that's being edited directly
function onSaveCellValue(e)
{
    if (!popup || !state.directCellEdit.target)
        return;

    const type = state.importData.headers[state.directCellEdit.pos.col];
    let newValue = "";

    // Some column types have their own special editors, figure out what the new value is
    if (type == "role")
        newValue = popup.contents.querySelector("select#role").value;
    else if (type == "group")
        newValue = popup.contents.querySelector("select#abbr").value;
    else newValue = popup.contents.querySelector("input").value.trim();

    // Perform type-specific validations
    if (type == "password") {
        if (newValue.length > 0 && newValue.length < MIN_PASSWORD_LENGTH) {
            window.alert(_tr("alerts.too_short_password", { length: MIN_PASSWORD_LENGTH }));
            return;
        }
    } else if (type == "uid") {
        if (newValue.length < 3) {
            window.alert(_tr("alerts.too_short_uid"));
            return;
        }

        if (!USERNAME_REGEXP.test(newValue)) {
            window.alert(_tr("alerts.invalid_uid"));
            return;
        }
    }

    // Save the value and update the table
    state.importData.rows[state.directCellEdit.pos.row].cellValues[state.directCellEdit.pos.col] = newValue;
    state.directCellEdit.target.innerText = newValue;

    if (type == "password") {
        // Prevent password PDF generation unless the table is imported first
        state.process.passwordsAlteredSinceImport = true;
    }

    if (newValue == "")
        state.directCellEdit.target.classList.add("empty");
    else state.directCellEdit.target.classList.remove("empty");

    state.directCellEdit.pos = null;
    state.directCellEdit.target = null;

    closePopup();
    detectProblems();
    updateStatistics();
}

// Close/accept a popup
function onKeyDown(e)
{
    if (!popup)
        return;

    if (e.keyCode == 27)
        closePopup();

    if (e.keyCode == 13 && state.directCellEdit.target)
        onSaveCellValue(null);
}

// Expand the colum header template. Called from multiple places.
function buildColumnHeader(index, type, isPreview=false)
{
    const tmpl = getTemplate(isPreview ? "previewColumnHeader" : "columnHeader");

    if (isPreview) {
        if (type != "")
            tmpl.querySelector("div.colType").innerText = state.localizedColumnTitles[type];
    } else {
        if (type != "")
            tmpl.querySelector("select#type").value = type;

        tmpl.querySelector("select#type").addEventListener("change", onColumnTypeChanged);
        tmpl.querySelector("button#controls").addEventListener("click", onOpenColumnMenu);

        tmpl.querySelector("th").dataset.column = index;        // needed in many places
    }

    return tmpl;
}

// Constructs the table containing the CSV parsing results
function buildImportTable(output, headers, rows, isPreview, selectedOnly = false)
{
    // Handle special cases
    if (state.parser.error) {
        output.innerHTML = `<p class="error">ERROR: ${state.parser.error}</p>`;
        return;
    }

    if (rows.length == 0) {
        output.innerHTML = _tr('status.no_data_to_display');
        return;
    }

    const t0 = performance.now();

    // All rows have the same number of columns
    const numColumns = rows[0].cellValues.length;

    let table = getTemplate("importTable");

    // The header row
    let headerRow = table.querySelector("thead tr");

    if (isPreview) {
        // Remove the status column. Beware of textNodes; if the table layout is changed,
        // the array index must be changed!
        headerRow.childNodes[3].remove();
        headerRow.classList.remove("stickyTop");
    }

    const knownColumns = new Set([]);

    for (let i = 0; i < numColumns; i++) {
        let type = "";

        // If headers[n] isn't empty, then the column's type is known and valid
        // and its contents can be marked as such
        if (headers[i] != "") {
            type = headers[i];
            knownColumns.add(i);
        }

        headerRow.appendChild(buildColumnHeader(i, type, isPreview));
    }

    if (!isPreview)
        headerRow.appendChild(create("th", { cls: ["message"], text: _tr("status.table_messages") }));

    // Data rows
    let tbody = table.querySelector("tbody");

    for (let rowNum = 0; rowNum < rows.length; rowNum++) {
        const row = rows[rowNum];
        const cellValues = row.cellValues;

        let tableRow = getTemplate("tableRow");
        let tr = tableRow.querySelector("tr");

        if (!isPreview)
            tr.dataset.row = rowNum;

        let checkbox = tableRow.querySelector(`input[type="checkbox"]`),
            stateTH = tr.querySelector("th.state");

        if (isPreview) {
            checkbox.remove();
            stateTH.remove();
        } else {
            checkbox.checked = row.rowFlags & RowFlag.SELECTED;

            if (selectedOnly)
                checkbox.disabled = true;
            else checkbox.addEventListener("click", (e) => onRowCheckboxClick(e));

            let stateCls = "";

            // Replicate row states, in case the table is rebuilt from existing data
            switch (row.rowState) {
                case RowState.IDLE: stateCls = "idle"; break;
                case RowState.PROCESSING: stateCls = "processing"; break;
                case RowState.FAILED: stateCls = "failed"; break;
                case RowState.PARTIAL_SUCCESS: stateCls = "partialSuccess"; break;
                case RowState.SUCCESS: stateCls = "success"; break;
                default: break;
            }

            stateTH.classList.add(stateCls);
        }

        for (let colNum = 0; colNum < numColumns; colNum++) {
            let td = document.createElement("td");

            if (cellValues[colNum] == "")
                td.classList.add("empty");
            else td.innerText = cellValues[colNum];

            if (!knownColumns.has(colNum))
                td.classList.add("skipped");

            if (state.importData.headers[colNum] == "password")
                td.classList.add("password");

            if (colNum == 0)
                td.classList.add("divider");

            td.classList.add("value");      // enable selection and direct cell editing

            tr.appendChild(td);
        }

        if (!isPreview)
            tr.appendChild(create("td", { cls: ["message", "divider"], text: row.message }));

        tbody.appendChild(tableRow);
    }

    // Add event handlers
    if (!isPreview) {
        tbody.addEventListener("mousedown", onMouseDown);
        tbody.addEventListener("dblclick", onMouseDoubleClick);
        table.querySelector("table").classList.add("notPreview");
    }

    let fragment = new DocumentFragment();

    fragment.appendChild(table);

    // Place the table on the page, replacing previous contents, if any
    output.innerHTML = "";
    output.appendChild(fragment);

    const t1 = performance.now();
    console.log(`buildImportTable(): table construction took ${t1 - t0} ms`);
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// THE IMPORT PROCESS

// This subsystem has two parts: one that updates the table and responds to button clicks,
// and one that runs in a worker thread. The main thread sends a message to the worker thread,
// telling it to process table rows N to M. The worker thread sends an async network request for
// those rows, and after the server responds, sends status information back to the main thread.
// This ping-pong process repeats until all rows have been processed, or the user cancels it.

// The reason it's done this way is because network requests are always async in JavaScript.
// Worker threads are also always async, so doing network stuff in them is easy, but it's not
// (always) easy to do them in the non-async main thread.

export function enableUI(newState)
{
    for (let i of state.container.querySelectorAll(`div#controls button`))
        if (i.id != "stopImport")
            i.disabled = !newState;

    for (let i of state.container.querySelectorAll("input, select, textarea"))
        i.disabled = !newState;

    for (let i of state.container.querySelectorAll("section#page1 button"))
        i.disabled = !newState;

    // Disable the table
    for (let i of state.container.querySelectorAll("div#output table select, div#output table button"))
        i.disabled = !newState;

    if (popup && popup.contents) {
        // Popup menus can have buttons and input elements
        for (let i of popup.contents.querySelectorAll("button, input"))
            i.disabled = !newState;
    }
}

function progressBegin(isResume)
{
    if (!isResume) {
        state.statistics.totalRowsProcessed = 0;
        state.statistics.success = 0;
        state.statistics.partialSuccess = 0;
        state.statistics.failed = 0;

        state.process.lastRowProcessed = 0;

        const elem = state.container.querySelector("div#status progress");

        elem.setAttribute("max", state.process.workerRows.length);
        elem.setAttribute("value", 0);
    }

    updateStatistics();

    state.container.querySelector("div#status div#message").classList.remove("hidden");
    state.container.querySelector("div#status progress").classList.remove("hidden");
    state.container.querySelector("button#beginImport").disabled = true;
    state.container.querySelector("button#stopImport").disabled = false;
}

function progressUpdate()
{
    state.container.querySelector("div#status progress").setAttribute("value",
                                  state.statistics.totalRowsProcessed);
    updateStatistics();
}

function progressEnd(success)
{
    if (state.process.stopRequested)
        state.container.querySelector("div#status div#message").innerText = _tr("status.stopped");
    else state.container.querySelector("div#status div#message").innerText = _tr("status.complete");

    state.process.importActive = false;

    updateStatistics();

    state.container.querySelector("button#beginImport").disabled = false;
    state.container.querySelector("button#stopImport").disabled = true;
}

function markRowsAsBeingProcessed(from, to)
{
    const tableRows = state.container.querySelectorAll("div#output table tbody tr");

    for (let row = from; row < to; row++) {
        if (row > state.process.workerRows.length - 1)
            break;

        // Each workerRow knows the actual table row number. They aren't
        // necessarily sequential, since the user can choose which rows
        // are processed.
        const rowNum = state.process.workerRows[row][0];

        state.importData.rows[rowNum].rowState = RowState.PROCESSING;

        const cell = tableRows[rowNum].querySelector("th.state");

        cell.classList.remove("idle", "failed", "partialSuccess", "success");
        cell.classList.add("processing");
    }
}

IMPORT_WORKER.onmessage = e => {
    switch (e.data.message) {
        case "progress": {
            console.log(`[main] Worker sent "${e.data.message}", total=${e.data.total}`);

            // UI update, based on the row states the server sent back
            const tableRows = state.container.querySelectorAll("div#output table tbody tr");

            for (const r of e.data.states) {
                let cls = "";

                switch (r.state) {
                    case "failed":
                    default:
                        cls = "failed";
                        state.statistics.failed++;
                        state.process.failedRows.push(r.row);
                        state.importData.rows[r.row].rowState = RowState.FAILED;
                        break;

                    case "partial_ok":
                        cls = "partialSuccess";
                        state.statistics.partialSuccess++;
                        state.importData.rows[r.row].rowState = RowState.PARTIAL_SUCCESS;
                        break;

                    case "ok":
                        cls = "success";
                        state.statistics.success++;
                        state.importData.rows[r.row].rowState = RowState.SUCCESS;
                        break;
                }

                state.process.lastRowProcessed = Math.max(state.process.lastRowProcessed, r.row);

                const cell = tableRows[r.row].querySelector("th.state");
                const message = tableRows[r.row].querySelector("td.message");

                cell.classList.remove("idle", "processing", "failed", "partialSuccess", "success");
                cell.classList.add(cls);

                if (r.state == "failed")
                    message.innerText = r.error;
                else message.innerText = null;

                if (r.failed) {
                    for (const [col, n, msg] of r.failed) {
                        console.log(`Marking column "${col}" (${n}) on row ${r.row} as failed: ${msg}`);
                        tableRows[r.row].cells[n + NUM_ROW_HEADERS].classList.add("error");
                        tableRows[r.row].cells[n + NUM_ROW_HEADERS].title = msg;
                        state.importData.rows[r.row].cellFlags[n] |= CellFlag.INVALID;
                    }
                }

                state.statistics.totalRowsProcessed++;
            }

            console.log(`[main] lastRowProcessed: ${state.process.lastRowProcessed} (length=${state.importData.rows.length})`);

            if (state.process.stopRequested && state.process.lastRowProcessed < state.importData.rows.length - 1) {
                // Stop
                progressUpdate();
                progressEnd();
                enableUI(true);
                state.process.stopRequested = false;
                state.process.previousImportStopped = true;
                break;
            }

            // Proceed to the next batch
            progressUpdate();
            markRowsAsBeingProcessed(state.statistics.totalRowsProcessed, state.statistics.totalRowsProcessed + BATCH_SIZE);
            IMPORT_WORKER.postMessage({ message: "continue" });
            break;
        }

        case "server_error": {
            // Mark the failed rows
            const tableRows = state.container.querySelectorAll("div#output table tbody tr");
            const failed = state.container.querySelectorAll("div#output table tbody th.state.processing");

            for (const cell of failed) {
                const rowNum = parseInt(cell.closest("tr").dataset.row, 10);

                state.process.failedRows.push(rowNum);

                cell.classList.remove("processing");
                cell.classList.add("failed");

                tableRows[rowNum].querySelector("td.message").innerText = e.data.error;
                state.importData.rows[rowNum].rowState = RowState.FAILED;

                state.statistics.failed++;
            }

            progressEnd();
            enableUI(true);

            state.container.querySelector("div#status div#message").innerText = _tr("status.aborted");

            window.alert("Server failure. Try again in a minute.");
            break;
        }

        // Finish up
        case "complete":
            console.log(`[main] Worker sent "${e.data.message}"`);
            progressEnd();
            enableUI(true);
            state.process.previousImportStopped = false;
            break;

        default:
            console.error(`[main] Unhandled import worker message "${e.data.message}"`);
            break;
    }
};

// Start the user import/update process
function beginImport(mode)
{
    // See if we have data to import
    if (state.importData.rows.length == 0 || state.importData.headers.length == 0) {
        window.alert(_tr("alerts.no_data_to_import"));
        return;
    }

    if (state.importData.errors.length > 0) {
        window.alert(_tr("alerts.fix_errors_first"));
        return;
    }

    if (mode == ImportRows.FAILED && state.process.failedRows.length == 0) {
        window.alert(_tr("alerts.no_failed_rows"));
        return;
    }

    const checkboxes = (mode == ImportRows.SELECTED) ?
        state.container.querySelectorAll(`div#output table tbody tr input[type="checkbox"]:checked`) : [];

    if (mode == ImportRows.SELECTED && checkboxes.length == 0) {
        window.alert(_tr("alerts.no_selected_rows"));
        return;
    }

    const uidCol = state.importData.findColumn("uid");

    // Verify it anyway, even if detectProblems() should handle it
    if (uidCol === -1) {
        window.alert(_tr("errors.required_column_missing", { title: state.localizedColumnTitles["uid"] }));
        return;
    }

    // A simple resuming mechanism, in case the previous import was stopped
    let startRow = 0,
        resume = false;

    if (state.process.previousImportStopped) {
        if (window.confirm(_tr("alerts.resume_previous"))) {
            startRow = state.process.lastRowProcessed + 1;
            resume = true;
        }
    }

    if (!window.confirm(_tr("alerts.are_you_sure")))
        return;

    // Clear previous states (unless we're resuming)
    if (!resume) {
        for (const row of state.importData.rows)
            row.rowState = RowState.IDLE;

        for (const row of state.container.querySelectorAll("div#output table tbody tr th.state")) {
            row.classList.add("idle");
            row.classList.remove("processing", "failed", "partialSuccess", "success");
            row.innerText = "";
        }

        for (const cell of state.container.querySelectorAll("div#output table tbody td.error")) {
            cell.classList.remove("error");
            cell.title = "";
        }
    }

    resetSelection();

    let status = state.container.querySelector("div#status"),
        message = state.container.querySelector("div#status div#message");

    message.classList.remove("hidden");
    message.innerText = _tr("status.fetching_current_users");

    /*
        Given the state (start from the beginning, or resume), and the current mode
        (all, selected, failed rows only), make a list of *incoming* usernames and
        their associated table rows. Each entry on the list is a three-element tuple:

        - username
        - puavoID (initially NULL for all users (undefined would make sense here, but
          it isn't a valid "unknown" value in JSON))
        - original table row number
    */
    let usernames = [];

    switch (mode) {
        case ImportRows.ALL:
        default:
            for (let rowNum = 0; rowNum < state.importData.rows.length; rowNum++) {
                const row = state.importData.rows[rowNum];

                if (row.cellFlags[uidCol] & CellFlag.INVALID)
                    continue;

                usernames.push([row.cellValues[uidCol], null, rowNum]);
            }

            break;

        case ImportRows.SELECTED:
            for (let rowNum = 0; rowNum < state.importData.rows.length; rowNum++) {
                const row = state.importData.rows[rowNum];

                if (row.cellFlags[uidCol] & CellFlag.INVALID)
                    continue;

                if (row.rowFlags & RowFlag.SELECTED)
                    usernames.push([row.cellValues[uidCol], null, rowNum]);
            }

            break;

        case ImportRows.FAILED:
            for (let rowNum = 0; rowNum < state.process.failedRows.length; rowNum++) {
                const fr = state.process.failedRows[rowNum];      // row numbers

                usernames.push([state.importData.rows[fr].cellValues[uidCol], null, fr]);
            }

            break;
    }

    // Then send the list to the server. It will compare the usernames against
    // the list of existing users, and fill in the puavoIDs of existing users.
    // The server always returns puavoIDs or -1 for the users, it will not leave
    // them to "null". If it cannot determine the ID of some user, the import
    // process is halted to prevent failures.
    enableUI(false);

    beginPOST("new_import/get_current_users", usernames).then(data => {
        const existingUsers = parseServerJSON(data);

        if (existingUsers === null) {
            window.alert(_tr("alerts.cant_parse_server_response"));
            enableUI(true);

            return;
        }

        if (existingUsers.status != "ok") {
            if (existingUsers.error)
                window.alert(_tr("alerts.data_retrieval_failed_known") + "\n\n" + existingUsers.error);
            else window.alert(_tr("alerts.data_retrieval_failed_unknown"));

            enableUI(true);

            return;
        }

        // Now use the puavoIDs to split the usernames into two arrays: one for existing
        // users (that will be updated) and one for new users (that will be created).
        // Both arrays are processed or ignored, depending on the current update mode.
        let numNew = 0,
            numUpdate = 0;

        state.process.workerRows = [];

        for (let i = 0; i < existingUsers.usernames.length; i++) {
            const pid = existingUsers.usernames[i][1];
            const rowNum = usernames[i][2];

            if (pid == -1) {
                // New user
                if (state.SETTINGS.import.mode == 2)
                    continue;

                numNew++;
            } else {
                // Existing
                if (state.SETTINGS.import.mode == 1)
                    continue;

                numUpdate++;
            }

            state.process.workerRows.push([rowNum, pid].concat(state.importData.rows[rowNum].cellValues));
        }

        console.log(`${numNew} new users, ${numUpdate} updated users`);

        if (state.process.workerRows.length == 0) {
            enableUI(true);
            window.alert(_tr("alerts.no_data_to_import"));

            return;
        }

        // This must not be cleared earlier, otherwise mode switch could incorrectly clear
        // the state
        state.process.failedRows = [];

        // Then, finally, begin the update process
        state.process.alreadyClickedImportOnce = true;
        state.process.importActive = true;

        // *Technically* this should be set after the import is complete, not before...
        state.process.passwordsAlteredSinceImport = false;

        progressBegin(resume);
        markRowsAsBeingProcessed(startRow, startRow + BATCH_SIZE);

        // Now we know what to do, so launch a worker thread that does the sync
        // stuff in the background
        message.innerText = _tr("status.synchronising");

        IMPORT_WORKER.postMessage({
            message: "start",
            school: state.importData.currentSchoolID,
            csrf: document.querySelector("meta[name='csrf-token']").content,
            startIndex: startRow,
            batchSize: BATCH_SIZE,
            headers: state.importData.headers,
            rows: state.process.workerRows,
        });
    }).catch(error => {
        console.error(error);
        enableUI(true);
        window.alert(_tr("alerts.cant_parse_server_response"));
    });
}

function stopImport()
{
    if (state.process.stopRequested)
        state.container.querySelector("div#status div#message").innerText = _tr("status.stopping_impatient");
    else {
        state.container.querySelector("div#status div#message").innerText = _tr("status.stopping");
        state.process.stopRequested = true;
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MAIN

function onDownloadTemplate()
{
    let columns = [];

    for (const cb of popup.contents.querySelectorAll(`input[type="checkbox"]:checked`))
        columns.push(cb.id);

    if (columns.length == 0) {
        window.alert(_tr("alerts.download_template_nothing_selected"));
        return;
    }

    let separator = ",";

    if (popup.contents.querySelector("input#template_semicolon").checked)
        separator = ";";
    else if (popup.contents.querySelector("input#template_tab").checked)
        separator = "\t";

    const contents = columns.join(separator) + "\n";

    try {
        const b = new Blob([contents], { type: "text/csv" });
        let a = window.document.createElement("a");

        a.href = window.URL.createObjectURL(b);
        a.download = "template." + (separator == "\t" ? "tsv" : "csv");

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    } catch (e) {
        console.log(e);
        window.alert(`CSV generation failed, see the console for details.`);
    }
}

function onCreateUsernameList(onlySelected, description)
{
    const uidCol = state.importData.findColumn("uid");

    if (uidCol === -1) {
        window.alert(_tr("errors.required_column_missing", { title: state.localizedColumnTitles["uid"] }));
        return;
    }

    let usernames = [];

    if (onlySelected) {
        for (const row of state.importData.rows)
            if (row.rowFlags & RowFlag.SELECTED)
                usernames.push(row.cellValues[uidCol]);
    } else {
        for (const row of state.importData.rows)
            usernames.push(row.cellValues[uidCol]);
    }

    if (usernames.length == 0) {
        window.alert(_tr("alerts.no_matching_rows"));
        return;
    }

    const postData = {
        creator: state.importData.currentUserName,
        school: state.importData.currentSchoolID,
        description: description,
        usernames: usernames,
    };

    enableUI(false);

    beginPOST("new_import/make_username_list", postData).then(data => {
        const response = parseServerJSON(data);

        if (response === null) {
            window.alert(_tr("alerts.cant_parse_server_response"));
            return;
        }

        switch (response.status) {
            case "ok":
                window.alert(_tr("alerts.list_created"));
                break;

            case "missing_users":
                window.alert(_tr("alerts.list_missing_users", { count: response.error.length }) + "\n\n" + response.error.join("\n"));
                break;

            default:
                window.alert(_tr("alerts.list_failed") + "\n\n" + response.error);
                break;
        }
    }).catch(error => {
        window.alert(error);
    }).finally(() => {
        enableUI(true);
    });
}

function onLoadUsernameList()
{
    const uuid = state.container.querySelector("div#unl select").value,
          url = `new_import/load_username_list?uuid=${encodeURIComponent(uuid)}`

    enableUI(false);

    beginGET(url).then(data => {
        const response = parseServerJSON(data);

        if (response === null) {
            window.alert(_tr("alerts.cant_parse_server_response"));
            return;
        }

        switch (response.status) {
            case "ok":
                break;

            case "list_not_found":
                window.alert(_tr("alerts.list_not_found"));
                return;

            case "missing_users":
                window.alert(_tr("alerts.list_missing_users", { count: response.error.length }));
                break;

            default:
                window.alert(_tr("alerts.list_loading_failed") + "\n\n" + response.error);
                return;
        }

        let usernames = "";

        // Specify the column type if type inferring is enabled
        if (state.SETTINGS.parser.infer)
            usernames += "uid\n";

        usernames += response.usernames.join("\n");
        state.container.querySelector("div#unl textarea").value = usernames;

        updatePreview();
    }).catch(error => {
        console.log(error);
        window.alert("Failed. See the console for details.");
    }).finally(() => {
        enableUI(true);
    });
}

function switchImportTab()
{
    toggleClass(state.container.querySelector("nav button#page1"), "selected", state.SETTINGS.mainTab == 0);
    toggleClass(state.container.querySelector("nav button#page2"), "selected", state.SETTINGS.mainTab == 1);
    toggleClass(state.container.querySelector("section#page1"), "hidden", state.SETTINGS.mainTab == 1);
    toggleClass(state.container.querySelector("section#page2"), "hidden", state.SETTINGS.mainTab == 0);
}

function onChangeImportTab(newTab)
{
    if (newTab != state.SETTINGS.mainTab) {
        state.SETTINGS.mainTab = newTab;
        saveSettings(state.SETTINGS);
        switchImportTab();
    }
}

function onChangeSource()
{
    const oldSource = state.SETTINGS.parser.sourceTab,
          newSource = state.container.querySelector("select#source").value;

    if (newSource == "manual")
        state.SETTINGS.parser.sourceTab = 0;
    else if (newSource == "upload")
        state.SETTINGS.parser.sourceTab = 1;
    else state.SETTINGS.parser.sourceTab = 2;

    toggleClass(state.container.querySelector("div#manual"), "hidden", state.SETTINGS.parser.sourceTab != 0);
    toggleClass(state.container.querySelector("div#upload"), "hidden", state.SETTINGS.parser.sourceTab != 1);
    toggleClass(state.container.querySelector("div#unl"), "hidden", state.SETTINGS.parser.sourceTab != 2);

    if (state.SETTINGS.parser.sourceTab != oldSource)
        updatePreview();
}

function togglePopupButton(e)
{
    e.preventDefault();

    const selectionType = () => {
        if (popup.contents.querySelector("#selected").checked)
            return "selected";
        if (popup.contents.querySelector("#unselected").checked)
            return "unselected";
        else return "all";
    };

    const contents = getTemplate(e.target.dataset.template);
    let width = null;

    // Attach event handlers
    switch (e.target.id) {
        case "selectExistingUIDs":
            contents.querySelector("button#selectDupesAll").
                addEventListener("click", () => onSelectDuplicates(Duplicates.ALL));
            contents.querySelector("button#selectDupesThisSchool").
                addEventListener("click", () => onSelectDuplicates(Duplicates.THIS_SCHOOL));
            contents.querySelector("button#selectDupesOtherSchools").
                addEventListener("click", () => onSelectDuplicates(Duplicates.OTHER_SCHOOLS));

            break;

        case "selectRows":
            contents.querySelector("button#selectAll").
                addEventListener("click", () => onSelectRows(1));
            contents.querySelector("button#deselectAll").
                addEventListener("click", () => onSelectRows(0));
            contents.querySelector("button#invertSelection").
                addEventListener("click", () => onSelectRows(-1));
            contents.querySelector("button#selectIdle").
                addEventListener("click", () => onSelectProcessedRows(RowState.IDLE));
            contents.querySelector("button#selectSuccessfull").
                addEventListener("click", () => onSelectProcessedRows(RowState.SUCCESS));
            contents.querySelector("button#selectPartiallySuccessfull").
                addEventListener("click", () => onSelectProcessedRows(RowState.PARTIAL_SUCCESS));
            contents.querySelector("button#selectFailed").
                addEventListener("click", () => onSelectProcessedRows(RowState.FAILED));
            break;

        case "analyze":
            contents.querySelector("button#analyzeDuplicates").
                addEventListener("click", () => onAnalyzeDuplicates());
            break;

        case "unl":
            contents.querySelector("button#doIt").addEventListener("click", () => {
                onCreateUsernameList(
                    popup.contents.querySelector("input#onlySelection").checked,
                    popup.contents.querySelector("input#unlDescription").value.trim()
                );
            });
            break;

        case "export":
            contents.querySelector("button#exportCSV").addEventListener("click", () => {
                exportData(state.importData, "csv", selectionType(), state.SETTINGS, false);
            });

            contents.querySelector("button#exportPDF").addEventListener("click", () => {
                exportData(state.importData, "pdf", selectionType(), state.SETTINGS, false);
            });

            contents.querySelector("button#exportPDFWithPasswords").addEventListener("click", () => {
                // Do this check here, because the export function has no access to state.process.*.
                if (state.process.passwordsAlteredSinceImport) {
                    // The PDF is useless if it contains passwords that haven't been imported
                    if (!window.confirm(_tr("alerts.passwords_out_of_sync")))
                        return;
                }

                exportData(state.importData, "pdf", selectionType(), state.SETTINGS, true);
            });

            break;

        case "downloadTemplate":
            contents.querySelector("button").addEventListener("click", onDownloadTemplate);
            width = 300;
            break;

        default:
            break;
    }

    // Show the popup
    createPopup();
    popup.contents.appendChild(contents);
    attachPopup(e.target, PopupType.POPUP_MENU, width);
    displayPopup();

    // Autoclose with Esc
    document.body.addEventListener("keydown", onKeyDown);
}

function dumpDebug()
{
    const states = {
        [RowState.IDLE]: "idle",
        [RowState.PROCESSING]: "proc",
        [RowState.SUCCESS]: "succ",
        [RowState.PARTIAL_SUCCESS]: "psuc",
        [RowState.FAILED]: "fail",
    };

    console.log("========== DEBUG DUMP START ==========");

    console.log(`rows: ${state.importData.rows.length} columns: ${state.importData.headers.length}`);
    console.log(`statistics: total=${state.statistics.totalRows}  selected=${state.statistics.selectedRows}  ` +
                `errors=${state.statistics.rowsWithErrors}  tobei=${state.statistics.rowsToBeImported}  ` +
                `totalproc=${state.statistics.totalRowsProcessed}  success=${state.statistics.success}  ` +
                `partial=${state.statistics.partialSuccess}  failed=${state.statistics.failed}`);

    let header = "#####            col=[";

    for (let colNum = 0; colNum < state.importData.headers.length; colNum++) {
        header += colNum.toString().padStart(2, " ");

        if (colNum < state.importData.headers.length - 1)
            header += " ";
    }

    header += "]";

    console.log(header);

    for (let rowNum = 0; rowNum < state.importData.rows.length; rowNum++) {
        const row = state.importData.rows[rowNum];

        let text = `${rowNum.toString().padStart(5, "0")}: ` +
                   `sel=${row.rowFlags & RowFlag.SELECTED ? 1 : 0} ` +
                   `st=${states[row.rowState]}`;

        let columns = [];

        for (let colNum = 0; colNum < state.importData.headers.length; colNum++) {
            if (row.cellValues[colNum] == "")
                columns.push(" e");
            else {
                if (row.cellFlags[colNum] & CellFlag.INVALID)
                    columns.push(" i");
                else columns.push(" -");
            }
        }

        text += ` [${columns.join(" ")}]`
        console.log(text);
    }

    console.log("=========== DEBUG DUMP END ===========");
}

function buildInferTable()
{
    /*
        Build an "inverse" lookup table for the inferred names. For example, if names
        "a", "b" and "c" all are aliases for column "foo", and names "d" and "e" are
        aliases for column "bar", the reverse lookup table will look like this:

        {
            "foo": ["foo", "a", "b", "c"],
            "bar": ["bar", "d", "e"]
        }
    */

    const keys = new Map();

    // Seed the lookup table with non-inferred names. JavaScript's Set maintains insertion
    // order, which is perfect for us, because now we can use INFERRED_NAMES to control the
    // order in which the names appear on the table. Set is needed, because the infer table
    // contains also the non-inferred names, and some column types have no inferred names.
    for (const [k, v] of Object.entries(state.localizedColumnTitles))
        keys.set(k, new Set([k]));

    // Then add infers
    for (const [k, v] of Object.entries(INFERRED_NAMES))
        keys.get(v).add(k);

    // Finally build the table
    let html = "";

    for (const [k, v] of Object.entries(state.localizedColumnTitles)) {
        html += `<tr>`;
        html += `<td><code>${Array.from(keys.get(k)).join(", ")}</code></td>`;
        html += `<td>${v}</td>`;
        html += `</tr>`;
    }

    state.container.querySelector("details#settings table.inferTable tbody").innerHTML = html;
}

export function initializeImporter(params)
{
    try {
        state.container = params.container;

        // Prepare data
        state.localizedColumnTitles = params.columnTitles;
        state.localizedGroupTypes = params.groupTypes;
        state.automaticEmails = params.automaticEmails || false;
        state.commonPasswords = params.commonPasswords || state.commonPasswords;

        state.importData.currentOrganisationName = params.organisationName;
        state.importData.currentSchoolID = params.schoolId;
        state.importData.currentSchoolName = params.schoolName;
        state.importData.currentUserName = params.currentUserName;
        state.importData.permitUserCreation = params.permitUserCreation;

        if ("groups" in params)
            state.importData.setGroups(params.groups);

        buildInferTable();

        // Initial UI update
        state.SETTINGS = loadSettings();
        switchImportTab();
        onChangeSource();

        // Setup event handling and restore parser settings
        state.container.querySelector("nav button#page1").addEventListener("click", () => { onChangeImportTab(0); });
        state.container.querySelector("nav button#page2").addEventListener("click", () => { onChangeImportTab(1); });
        state.container.querySelector("select#source").addEventListener("change", () => onChangeSource());

        state.container.querySelector("div#unl button#loadUNL")?.addEventListener("click", onLoadUsernameList);

        const settings = state.container.querySelector("details#settings");

        settings.querySelector("input#inferTypes").addEventListener("click", e => { state.SETTINGS.parser.infer = e.target.checked; });
        settings.querySelector("input#trimValues").addEventListener("click", e => { state.SETTINGS.parser.trim = e.target.checked; });
        settings.querySelector("input#comma").addEventListener("click", e => { state.SETTINGS.parser.separator = 0; });
        settings.querySelector("input#semicolon").addEventListener("click", e => { state.SETTINGS.parser.separator = 1; });
        settings.querySelector("input#tab").addEventListener("click", e => { state.SETTINGS.parser.separator = 2; });

        for (let i of settings.querySelectorAll("input")) {
            i.addEventListener("click", e => {
                saveSettings(state.SETTINGS);
                updateParsingSummary();
                updatePreview();
            });
        }

        state.container.querySelector("input#fileUpload").addEventListener("change", e => {
            // Parse the "uploaded" file
            let reader = new FileReader();

            reader.onload = () => {
                state.parser.fileContents = reader.result;
                updatePreview();
            };

            reader.onerror = () => {
                window.alert(reader.error);
            };

            reader.readAsText(e.target.files[0], "utf-8");
        });

        state.container.querySelector("div#manual textarea").addEventListener("input", updatePreview);
        state.container.querySelector("div#unl textarea")?.addEventListener("input", updatePreview);

        settings.querySelector("input#inferTypes").checked = state.SETTINGS.parser.infer;
        settings.querySelector("input#trimValues").checked = state.SETTINGS.parser.trim;
        settings.querySelector("input#comma").checked = (state.SETTINGS.parser.separator == 0);
        settings.querySelector("input#semicolon").checked = (state.SETTINGS.parser.separator == 1);
        settings.querySelector("input#tab").checked = (state.SETTINGS.parser.separator == 2);

        if (!state.importData.permitUserCreation) {
            console.log("The current user cannot create new users, resetting the mode to update existing only");
            state.SETTINGS.import.mode = 2;
        }

        state.container.querySelector("select#mode").value = state.SETTINGS.import.mode;

        state.container.querySelector(`select#mode`).addEventListener("change", e => {
            state.SETTINGS.import.mode = parseInt(e.target.value, 10);
            state.process.previousImportStopped = false;   // otherwise this would get too complicated
            saveSettings(state.SETTINGS);
            detectProblems();
        });

        state.container.querySelector("button#readData").addEventListener("click", () => {
            if (readAllData()) {
                // FIXME: The tab is changed while the worker is still doing its thing,
                // which means the table can briefly display old contents before it gets
                // updated. The joys of asynchronous operations... I will fix this once
                // the old importer is removed and I can update the bundler to a more
                // modern version, and I can then properly modularize this monolith.
                onChangeImportTab(1);
            }
        });

        state.container.querySelector("button#deleteSelectedRows").addEventListener("click", onDeleteSelectedRows);

        state.container.querySelector("button#beginImport").
            addEventListener("click", () => beginImport(ImportRows.ALL));

        state.container.querySelector("button#beginImportSelected")?.
            addEventListener("click", () => beginImport(ImportRows.SELECTED));

        state.container.querySelector("button#retryFailed").
            addEventListener("click", () => beginImport(ImportRows.FAILED));

        state.container.querySelector("button#stopImport").addEventListener("click", stopImport);

/*
        state.container.querySelector("input#checkOnlySelectedRows").addEventListener("click", (e) => {
            state.process.checkOnlySelectedRows = e.target.checked;
            detectProblems();
        });

        state.container.querySelector("button#detectProblemsNow").addEventListener("click", () => detectProblems(false));
*/

        const debug = state.container.querySelector("button#debug");

        if (debug)
            debug.addEventListener("click", dumpDebug);

        // Popup buttons/dialogs
        for (const p of state.container.querySelectorAll("button.popupToggle"))
            p.addEventListener("click", (e) => togglePopupButton(e));

        // Close any popups that might be active
        document.body.addEventListener("click", e => {
            if (popup && e.target == popup.backdrop)
                closePopup();
        });

        // Reposition the popup when the page is scrolled
        document.addEventListener("scroll", ensurePopupIsVisible);

        updateParsingSummary();
        updatePreview();
    } catch (e) {
        console.error(e);

        params.state.container.innerHTML =
            `<p class="error">Importer initialization failed. Please see the browser console for technical ` +
            `details, then contact Opinsys Oy for assistance.</p>`;

        return;
    }
}
