"use strict";

/*
Puavo Mass User Import III
Version 0.8
*/

// Worker threads for CSV parsing and the actual data import/update process
const CSV_PARSER_WORKER = new Worker("/javascripts/csv_parser.js"),
      IMPORT_WORKER = new Worker("/javascripts/import_worker.js");

// For new users, you need at least these columns
const REQUIRED_COLUMNS_NEW = new Set(["first", "last", "uid", "role"]);

// The same as above, but for existing users (when updating their attributes)
const REQUIRED_COLUMNS_UPDATE = new Set(["uid"]);

// Inferred column types. Maps various alternative colum name variants to one of the above
// colum names. If the inferred name does not exist in localizedColumnTitles, bad things will happen.
// So don't do that.
// WARNING: If you edit these, remember to also update the inferring table in the page HTML.
const INFERRED_NAMES = {
    "first": "first",
    "first_name": "first",
    "firstname": "first",
    "first name": "first",
    "vorname": "first",
    "last": "last",
    "last_name": "last",
    "lastname": "last",
    "last name": "last",
    "name": "last",
    "uid": "uid",
    "user_name": "uid",
    "username": "uid",
    "role": "role",
    "type": "role",
    "phone": "phone",
    "telephone": "phone",
    "telefon": "phone",
    "email": "email",
    "mail": "email",
    "eid": "eid",
    "external_id": "eid",
    "externalid": "eid",
    "password": "password",
    "passwort": "password",
};

const VALID_ROLES = new Set(["student", "teacher", "staff", "parent", "visitor", "testuser"]);

// Batching size for the import process. Reduces the number of network calls, but makes the UI
// seem slower (as it's not updated very often).
const BATCH_SIZE = 2;

// How many header columns each row has on the left edge
const NUM_ROW_HEADERS = 2;

// Password length limitations
const MIN_PASSWORD_LENGTH = 8,
      MAX_PASSWORD_LENGTH = 100;

// Validation regexps. I'm not sure about the email and phone number regexps, but they're the same
// regexps we've used elsewhere (I think the telephone validator lets through too much junk).
const USERNAME_REGEXP = /^[a-z][a-z0-9.-]{2,}$/,
      EMAIL_REGEXP = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
      PHONE_REGEXP = /^\+?[A-Za-z0-9 '(),-.\/:?"]+$/;

const CELLS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA

// Everything in the import tool happens inside this container element
let container = null;

// Localized strings. Supplied by the user in the initializer.
let localizedColumnTitles = {},
    localizedGroupTypes = {};

// Current settings. Call loadDefaultSettings() to load the defaults.
let SETTINGS = {};

// The ID of the current school, set in the initializer
let currentSchool = -1;

// Current groups in the target school. Can be specified in the importer initializer, and
// optionally updated dynamically without reloading the page.
let currentGroups = [];

// Tab-separated string of common passwords
let commonPasswords = "\tpassword\tsalasana\t";

// True if email addresses are automatic in this school/organisation, and thus email address
// columns will be ignored.
let automaticEmails = false;

// Raw contents of the uploaded file (manual entry uses the textarea directly), grabbed whenever
// user selects a file (it cannot be done when the import actually begins, it has to be done in
// advance, when the file select event fires; such is life with JavaScript).
let fileContents = null;

// If not null, contains the error message the CSV parser returned
let parserError = null;

// Raw data from the CSV parser
let parserOutput = null;

// Header column types (see the COLUMN_TYPES table, null if the column is skipped/unknown).
// This MUST have the same number of elements as there are data columns in the table!
let importHeaders = [];

// Tabular data parsed from the file/direct input. Each row is a 2-element table, the
// first element is a row number in the original data (zero-based) and the next element
// is an array containing the parsed row contents.
let importRows = [];

// Same as importHeaders and importRows, but for the live preview table. The preview table
// only contains the first ten rows of data.
let previewHeaders = [],
    previewRows = [];

// Array of known problems in the import data that prevent the import process from starting.
// See detectProblems() for details.
let importProblems = [];

// Like above, but warnings. These won't prevent the import process.
let importWarnings = [];

// If true, the import process will be stopped after the current batch is finished
// (it cannot be stopped mid-way; even if you terminate the worker thread, the server
// is busy processing the batch and there's no way to stop it)
let importStopRequested = false,
    previousImportStopped = false;

// Records the last processed row. This is used to resume the import process if it was stopped.
let lastRowProcessed = 0;

// If the password column exists and its contents are edited, the generated PDF will be out-of-sync
// unless they're synced first. This flag warns the user about that.
let passwordsAlteredSinceImport = false;

// The column we're editing when the column popup/dialog is open
const targetColumn = {
    column: null,
    index: -1
};

// Popup menu/dialog. When the popup is opened, it is attached to the 'attachTo' HTML element.
// How the popup is positioned relative to the element depends on the element type. When the
// page is scrolled, the popup is repositioned so that it follows the attached element.
const popup = {
    backdrop: null,
    contents: null,
    attachedTo: null,
    attachmentType: null,       // see 'PopupType' below
};

// Possible values for 'attachmentType' above
const PopupType = {
    COLUMN_TOOL: 1,
    CELL_EDIT: 2,
};

// The (row, col) coordinates and the TD element we're directly editing (double-click)
const directCellEdit = {
    pos: null,
    target: null,
};

// Multiple selected cells
const cellSelection = {
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
};

// A copy of the table data used during the import process. Also contains table row numbers
// and other oddities. Don't touch.
let workerRows = [];

// List of failed rows (numbers). The user can retry them.
let failedRows = [];

// True if the user has already imported/updated something
let alreadyClickedImportOnce = false;

// True if an import job is currently active
let importActive = false;

// Statistics collected during the operation
const statistics = {
    totalRowsProcessed: 0,
    success: 0,
    partialSuccess: 0,
    failed: 0,
};

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// UTILITY

// A crude mechanism for updating the saved settings
const EXPECTED_SETTINGS_VERSION = 1;

function loadDefaultSettings()
{
    SETTINGS = {
        version: EXPECTED_SETTINGS_VERSION,
        mainTab: 0,
        parser: {
            sourceTab: 0,
            infer: true,
            trim: true,
            separator: 0,   // 0=comma, 1=semicolon, 2=tab
        },
        import: {
            mode: 1,        // 0=full sync, 1=import new users only, 2=update existing users only
            overwrite: true,
            username: {
                umlauts: 0,
            },
            password: {
                randomize: true,
                uppercase: true,
                lowercase: true,
                numbers: true,
                punct: false,
                length: 12,
            },
        }
    };
}

// Try to save all settings to localhost
function saveSettings()
{
    localStorage.setItem("importSettings", JSON.stringify(SETTINGS));
}

// Try to restore all settings from localhost. If they cannot be loaded,
// resets them to defaults and saves them.
function loadSettings()
{
    loadDefaultSettings();

    const raw = localStorage.getItem("importSettings");

    if (!raw) {
        // Initialize new settings
        saveSettings();
        return;
    }

    let data = null;

    try {
        data = JSON.parse(raw);
    } catch (e) {
        console.error("loadSettings(): can't parse the stored JSON:");
        console.error(e);
        saveSettings();
        return;
    }

    if (data.version === EXPECTED_SETTINGS_VERSION)
        SETTINGS = {...SETTINGS, ...data};
    else {
        console.warn("Settings version number changed, reset everything");
        saveSettings();
    }

    SETTINGS.import.password.length = clampPasswordLength(SETTINGS.import.password.length);
}

// A shorter to type alias
function _tr(id, params={})
{
    return I18n.translate(id, params);
}

// Returns a usable copy of a named HTML template. It's a DocumentFragment, not text,
// so it must be handled with DOM methods.
function getTemplate(id)
{
    return document.querySelector(`template#template_${id}`).content.cloneNode(true);
}

// Adds or removes 'cls' from target's classList, depending on 'state' (true=add, false=remove)
function toggleClass(target, cls, state)
{
    if (!target) {
        console.error(`toggleClass(): target element is NULL! (cls="${cls}", state=${state})`);
        return;
    }

    if (state)
        target.classList.add(cls);
    else target.classList.remove(cls);
}

// Math.clamp() does not exist at the moment
function clamp(value, min, max)
{
    return Math.min(Math.max(min, value), max);
}

function clampPasswordLength(value)
{
    return clamp(value, MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH);
}

// Creates a new HTML element and sets is attributes
function create(tag, params={})
{
    let e = document.createElement(tag);

    if ("id" in params && params.id !== undefined)
        e.id = params.id;

    if ("cls" in params && params.cls !== undefined) {
        if (Array.isArray(params.cls))
            e.className = params.cls.join(" ");
        else e.className = params.cls;
    }

    if ("html" in params && params.html !== undefined)
        e.innerHTML = params.html;

    if ("text" in params && params.text !== undefined)
        e.innerText = params.text;

    if ("textnode" in params && params.textnode !== undefined)
        e.appendChild(document.createTextNode(params.textnode));

    if ("title" in params && params.title !== undefined)
        e.title = params.title;

    return e;
}

// Updates the current group list
function setGroups(groups)
{
    currentGroups = [...groups].sort((a, b) => { return a["name"].localeCompare(b["name"]) });
}

// Returns the indx of the specified column in the table, or -1 if it can't be found
function findColumn(id)
{
    for (let i = 0; i < importHeaders.length; i++)
        if (importHeaders[i] === id)
            return i;

    return -1;
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PARSING

// Updates the parser options summary
function updateParsingSummary()
{
    let parts = [];

    if (container.querySelector("#comma").checked)
        parts.push(_tr("parser.commas"));
    else if (container.querySelector("#tab").checked)
        parts.push(_tr("parser.tabs"));
    else parts.push(_tr("parser.semicolons"));

    if (container.querySelector("#inferTypes").checked)
        parts.push(_tr('parser.infer'));

    if (container.querySelector("#trimValues").checked)
        parts.push(_tr('parser.trim'));

    container.querySelector("details#settings summary").innerHTML =
        `${_tr('parser.title')} (${parts.join(", ")})`;
}

// Takes the data from the CSV parser and figures out column types, row widths, etc.
function prepareCSVParserResults(data)
{
    const prepareHeadersAndRows = (data) => {
        let headers = [],
            rows = [];

        if (Array.isArray(data.headers)) {
            headers = [...data.headers];

            for (let i = 0; i < headers.length; i++) {
                // Some column types can have multiple choices
                const colName = headers[i].toLowerCase();

                if (colName in INFERRED_NAMES)
                    headers[i] = INFERRED_NAMES[colName];

                // Clear unknown column types, so the column will be skipped
                if (!(headers[i] in localizedColumnTitles))
                    headers[i] = "";
            }
        }

        rows = [...data.rows];

        // Find the "widest" row, then pad all rows to have the same number of columns/cells.
        // It's far easier to handle empty values than empty OR missing values.
        let maxColumns = headers.length;

        for (const row of rows)
            maxColumns = Math.max(maxColumns, row.columns.length);

        console.log(`prepareCSVParserResults(): the widest row has ${maxColumns} columns`);

        while (headers.length < maxColumns)
            headers.push("");       // "skip this column"

        for (let row of rows)
            while (row.columns.length < maxColumns)
                row.columns.push("");

        return [headers, rows];
    };

    parserError = null;

    if (data.state == "error") {
        parserError = data.message;
        return;
    }

    // Preview update must not clobber potentially already existing table data (and vice versa)
    if (data.isPreview)
        [previewHeaders, previewRows] = prepareHeadersAndRows(data);
    else [importHeaders, importRows] = prepareHeadersAndRows(data);
}

// Builds a "mini" import table for previewing the first N rows of data
function updatePreview()
{
    const source = (SETTINGS.parser.sourceTab == 1) ? fileContents : container.querySelector("textarea").value;

    // Launch a worker thread that parses the file
    let settings = {
        separator: ";",
        wantHeader: container.querySelector("#inferTypes").checked,
        trimValues: container.querySelector("#trimValues").checked,
    };

    if (container.querySelector("#comma").checked)
        settings.separator =  ",";

    if (container.querySelector("#tab").checked)
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
    if (alreadyClickedImportOnce) {
        if (!window.confirm(_tr("alerts.already_imported")))
            return false;
    }

    alreadyClickedImportOnce = false;

    // The next import must start from the beginning
    previousImportStopped = false;

    // This is technically true...
    passwordsAlteredSinceImport = true;

    let source = null;

    // Get source data
    if (SETTINGS.parser.sourceTab == 1) {
        // file upload
        if (fileContents === null) {
            window.alert(_tr("alerts.no_file"));
            return;
        }

        source = fileContents;
    } else {
        // manual entry
        source = container.querySelector("textarea").value;
    }

    // UI reset in case the previous import was stopped half-way
    container.querySelector("div#status").classList.add("hidden");
    resetSelection();

    // Launch a worker thread that parses the file
    let settings = {
        separator: ";",
        wantHeader: container.querySelector("#inferTypes").checked,
        trimValues: container.querySelector("#trimValues").checked
    };

    if (container.querySelector("#comma").checked)
        settings.separator =  ",";

    if (container.querySelector("#tab").checked)
        settings.separator =  "\t";

    CSV_PARSER_WORKER.postMessage({
        source: source,
        settings: settings,
        isPreview: false,
    });

    // Signal Tab change
    return true;
}

// Route messages from the worker thread to the function that updates the UI
CSV_PARSER_WORKER.onmessage = e => {
    prepareCSVParserResults(e.data);

    if (e.data.isPreview) {
        buildImportTable(container.querySelector("div#preview"), previewHeaders, previewRows, true);
        return;
    }

    buildImportTable(container.querySelector("div#output"), importHeaders, importRows, false);

    // TODO: We should at least check for missing required columns in the preview mode
    if (!e.data.isPreview)
        detectProblems();
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PREVIEW AND MANIPULATION

// Called when there's no data to import. Ensures everything is cleared.
function noData()
{
    if (container)
        container.querySelector("div#output").innerHTML = _tr('status.no_data_to_display');

    parserError = null;
    importHeaders = [];
    importRows = [];
}

// Re-number column indexes in their header row datasets
function reindexColumns()
{
    const headings = container.querySelectorAll("div#output table thead th");

    if (headings.length == 1) {
        // Only the row number column is remaining, so effectively there's no data to display
        noData();
        return;
    }

    for (let i = NUM_ROW_HEADERS; i < headings.length; i++) {
        headings[i].dataset.column = i - NUM_ROW_HEADERS;

        // firstChild cannot be used due to varying whitespace textNodes
        headings[i].childNodes[1].childNodes[1].innerText = CELLS[(i - NUM_ROW_HEADERS) % 26];
    }
}

// Computes the start and end values for a fill-type operation. Takes the selection into account.
function getFillRange()
{
    let start = 0,
        end = importRows.length;

    if (cellSelection.column == targetColumn.index &&
        cellSelection.start !== -1 &&
        cellSelection.end !== -1) {

        // We have a selection targeting this column (end is +1 because
        // the selection range is inclusive)
        start = Math.min(cellSelection.start, cellSelection.end);
        end = Math.max(cellSelection.start, cellSelection.end) + 1;
    }

    console.log(`getFillRange(): start=${start}, end=${end}`);

    return [start, end];
}

// Ends multi-cell selection
function resetSelection()
{
    cellSelection.active = false;
    cellSelection.mouseTrackPos = null;
    cellSelection.initialClick = null;
    cellSelection.previousCell = null;
    cellSelection.column = -1;
    cellSelection.start = -1;
    cellSelection.end = -1;

    for (let cell of container.querySelectorAll("table tbody td.selectedCell"))
        cell.classList.remove("selectedCell");
}

// Updates multi-cell selection highlighting
function highlightSelection()
{
    if (!cellSelection.active || cellSelection.start == -1 || cellSelection.end == -1)
        return;

    const start = Math.min(cellSelection.start, cellSelection.end),
          end = Math.max(cellSelection.start, cellSelection.end);

    // Remove highlights from all cells that aren't in the selection range anymore
    for (let cell of container.querySelectorAll("table tbody td.selectedCell")) {
        const row = cell.parentNode.rowIndex - 1;

        if (cell.cellIndex == cellSelection.column && row >= start && row <= end)
            continue;

        cell.classList.remove("selectedCell");
    }

    // Then add it to all cells that are in the range
    const rows = container.querySelectorAll("div#output table tbody tr");

    for (let row = start; row <= end; row++)
        rows[row].children[cellSelection.column + NUM_ROW_HEADERS].classList.add("selectedCell");
}

// Try to detect problems and potential problems (warnings) in the table data
function detectProblems()
{
    let output = container.querySelector("div#problems");

    if (importRows === null || importRows.length == 0) {
        // The table is empty
        output.innerHTML = "";
        output.classList.add("hidden");
        return;
    }

    // Certain problems will be ignored if we're only updating existing users
    const updateOnly = (SETTINGS.import.mode == 2);

    const firstCol = findColumn("first"),
          lastCol = findColumn("last"),
          uidCol = findColumn("uid"),
          roleCol = findColumn("role"),
          eidCol = findColumn("eid"),
          emailCol = findColumn("email"),
          phoneCol = findColumn("phone"),
          passwordCol = findColumn("password");

    const tableRows = container.querySelectorAll("div#output table tbody tr");

    importProblems = [];
    importWarnings = [];

    // ----------------------------------------------------------------------------------------------
    // Make sure required columns are present and there are no duplicates

    let counts = {};

    // Check for duplicate columns
    for (const i of importHeaders) {
        if (i === null || i === undefined || i == "")
            continue;

        if (i in counts)
            counts[i]++;
        else counts[i] = 1;
    }

    for (const i of Object.keys(counts))
        if (counts[i] > 1)
            importProblems.push(`${_tr("problems.multiple_columns", { title: localizedColumnTitles[i] })}`);

    if (updateOnly) {
        // In update-only mode, you need the username column, but everything else is optional
        if (uidCol === -1)
            importProblems.push(_tr("problems.need_uid_column_in_update_mode"));

        let numNonUIDCols = 0;

        for (const i of importHeaders)
            if (i !== "uid" && i !== "")
                numNonUIDCols++;

        if (numNonUIDCols < 1)
            importProblems.push(_tr("problems.need_something_to_update_in_update_mode"));

        if (roleCol !== -1)
            importWarnings.push(_tr("problems.no_role_mass_change"));
    } else {
        // Check for missing required columns
        for (const r of REQUIRED_COLUMNS_NEW)
            if (!(r in counts))
                importProblems.push(`${_tr("problems.required_column_missing", { title: localizedColumnTitles[r] })}`);

        // These columns are not required, but they can cause problems, especially if you're
        // importing new users
        if (findColumn("group") === -1)
            importWarnings.push(_tr("problems.no_group_column"));

        if (findColumn("password") === -1)
            importWarnings.push(_tr("problems.no_password_column"));
    }

    // ----------------------------------------------------------------------------------------------
    // Ensure the required columns have proper values and that there are no duplicates.
    // This will produce invalid results if there are duplicate columns.

    // Validate first names
    if (firstCol !== -1) {
        let numEmpty = 0;

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[firstCol],
                  cell = tableRows[row].children[firstCol + NUM_ROW_HEADERS];

            if (value === null || value.trim().length == 0) {
                numEmpty++;
                cell.classList.add("error");
            } else cell.classList.remove("error");
        }

        if (numEmpty > 0)
            importProblems.push(_tr('problems.empty_first', { count: numEmpty }));
    }

    // Validate last names
    if (lastCol !== -1) {
        let numEmpty = 0;

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[lastCol],
                  cell = tableRows[row].children[lastCol + NUM_ROW_HEADERS];

            if (value === null || value.trim().length == 0) {
                numEmpty++;
                cell.classList.add("error");
            } else cell.classList.remove("error");
        }

        if (numEmpty > 0)
            importProblems.push(_tr('problems.empty_last', { count: numEmpty }));
    }

    // Validate usernames
    if (uidCol !== -1) {
        let numEmpty = 0,
            numDuplicate = 0,
            numShort = 0,
            numInvalid = 0;

        let usernames = new Set();

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[uidCol],
                  cell = tableRows[row].children[uidCol + NUM_ROW_HEADERS];

            let flag = false;

            if (value === null || value.trim().length == 0) {
                numEmpty++;
                flag = true;
            } else {
                const u = value.trim();

                if (usernames.has(u)) {
                    numDuplicate++;
                    flag = true;
                } else usernames.add(u);

                if (u.length < 3) {
                    numShort++;
                    flag = true;
                }

                if (!USERNAME_REGEXP.test(u)) {
                    numInvalid++;
                    flag = true;
                }
            }

            if (flag)
                cell.classList.add("error");
            else cell.classList.remove("error");
        }

        if (numEmpty > 0)
            importProblems.push(_tr('problems.empty_uid', { count: numEmpty }));

        if (numDuplicate > 0)
            importProblems.push(_tr('problems.duplicate_uid', { count: numDuplicate }));

        if (numShort > 0)
            importProblems.push(_tr('problems.short_uid', { count: numShort }));

        if (numInvalid > 0)
            importProblems.push(_tr('problems.invalid_uid', { count: numInvalid }));
    }

    // Roles
    if (roleCol !== -1) {
        let numInvalid = 0;

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[roleCol],
                  cell = tableRows[row].children[roleCol + NUM_ROW_HEADERS];

            if (value === null || !VALID_ROLES.has(value.trim())) {
                numInvalid++;
                cell.classList.add("error");
            } else cell.classList.remove("error");
        }

        if (numInvalid > 0)
            importProblems.push(_tr('problems.missing_role', { count: numInvalid }));
    }

    // External IDs
    if (eidCol !== -1) {
        let numDuplicate = 0;
        let eid = new Set();

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[eidCol],
                  cell = tableRows[row].children[eidCol + NUM_ROW_HEADERS];

            if (value === null || value.trim().length == 0) {
                cell.classList.remove("error");
                continue;
            }

            if (eid.has(value)) {
                numDuplicate++;
                cell.classList.add("error");
            } else eid.add(value);
        }

        if (numDuplicate > 0)
            importProblems.push(_tr('problems.duplicate_eid', { count: numDuplicate }));
    }

    // Email addresses
    if (emailCol !== -1) {
        if (automaticEmails) {
            // We could simply ignore the column, but since the error reporting mechanism
            // exists and works, use it to enfore 99% valid data
            importProblems.push(_tr("problems.automatic_emails"));
        } else {
            let numDuplicate = 0,
                numInvalid = 0,
                seen = new Set();

            for (let row = 0; row < importRows.length; row++) {
                const value = importRows[row].columns[emailCol],
                      cell = tableRows[row].children[emailCol + NUM_ROW_HEADERS];

                if (value === null || value.trim().length == 0) {
                    cell.classList.remove("error");
                    continue;
                }

                let flag = false;

                if (seen.has(value)) {
                    numDuplicate++;
                    flag = true;
                } else seen.add(value);

                if (!EMAIL_REGEXP.test(value)) {
                    numInvalid++;
                    flag = true;
                }

                if (flag)
                    cell.classList.add("error");
                else cell.classList.remove("error");
            }

            if (numDuplicate > 0)
                importProblems.push(_tr('problems.duplicate_email', { count: numDuplicate }));

            if (numInvalid > 0)
                importProblems.push(_tr('problems.invalid_email', { count: numInvalid }));
        }
    }

    // Telephone numbers
    if (phoneCol !== -1) {
        let numDuplicate = 0,
            numInvalid = 0,
            seen = new Set();

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[phoneCol],
                  cell = tableRows[row].children[phoneCol + NUM_ROW_HEADERS];

            if (value === null || value.trim().length == 0) {
                cell.classList.remove("error");
                continue;
            }

            let flag = false;

            if (seen.has(value)) {
                numDuplicate++;
                flag = true;
            } else seen.add(value);

            // For some reason, LDAP really does not like if the telephone attribute is
            // just a "-". And when I say "does not like", I mean "it completely crashes".
            // We found out that in the hard way.
            if (value.trim() == "-" || !PHONE_REGEXP.test(value)) {
                numInvalid++;
                flag = true;
            }

            if (flag)
                cell.classList.add("error");
            else cell.classList.remove("error");
        }

        if (numDuplicate > 0)
            importProblems.push(_tr('problems.duplicate_phone', { count: numDuplicate }));

        if (numInvalid > 0)
            importProblems.push(_tr('problems.invalid_phone', { count: numInvalid }));
    }

    // Passwords
    if (passwordCol !== -1) {
        let numCommon = 0;

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[passwordCol],
                  cell = tableRows[row].children[passwordCol + NUM_ROW_HEADERS];

            if (value === null || value.trim().length == 0 || commonPasswords.indexOf(`\t${value}\t`) === -1) {
                cell.classList.remove("error");
                continue;
            }

            cell.classList.add("error");
            numCommon++;
        }

        if (numCommon > 0)
            importProblems.push(_tr('problems.common_password', { count: numCommon }));
    }

    // ----------------------------------------------------------------------------------------------
    // Generate a list of problems and warnings

    output.innerHTML = "";

    if (importProblems.length > 0) {
        const tmpl = getTemplate("errors");
        const list = tmpl.querySelector("ul");

        for (const p of importProblems)
            list.appendChild(create("li", { text: p }));

        output.appendChild(tmpl);
    }

    if (importWarnings.length > 0) {
        const tmpl = getTemplate("warnings");
        const list = tmpl.querySelector("ul");

        for (const p of importWarnings)
            list.appendChild(create("li", { text: p }));

        output.appendChild(tmpl);
    }

    output.classList.remove("hidden");
}

// --------------------------------------------------------------------------------------------------
// POPUP UTILITY

// Re-enables column settings buttons
function clearMenuButtons()
{
    for (let button of container.querySelectorAll("div#output table thead button.controls")) {
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

        case PopupType.CELL_EDIT:
            x = attachedToRect.left - 5;
            y = attachedToRect.top - 1;
            break;

        default:
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
// EVENT HANDLERS

function makeRoleSelector(current=null)
{
    const tmpl = getTemplate("selectRole");

    if (current && VALID_ROLES.has(current))
        tmpl.querySelector("select#role").value = current;
    else tmpl.querySelector("select#role").value = "student";

    return tmpl;
}

function makeGroupSelector(current=null)
{
    const tmpl = getTemplate("selectGroup");
    const selector = tmpl.querySelector("select#abbr");

    // Fill in the groups list
    selector.disabled = (currentGroups.length == 0);

    for (const g of currentGroups) {
        let o = create("option");

        o.value = g.abbr;
        o.selected = (current === g.abbr);
        o.innerText = `${g.name} (${localizedGroupTypes[g.type] || "?"})`;

        selector.appendChild(o);
    }

    tmpl.querySelector("button#reload").addEventListener("click", onReloadGroups);

    return tmpl;
}

// Mark/unmark all rows (the master checkbox in the upper left corner of the table)
function onMarkAllRows(e)
{
    const state = e.target.checked;

    for (let cb of container.querySelectorAll(`div#output table tbody tr th.rowNumber input[type="checkbox"]`))
        cb.checked = state;
}

function onDeleteMarkedRows()
{
    if (previousImportStopped) {
        window.alert(_tr("alerts.cant_remove_rows_after_stopping"));
        return;
    }

    // Make a list of selected table rows
    let markedRows = [];

    for (let cb of container.querySelectorAll(`div#output table tbody tr th.rowNumber input[type="checkbox"]:checked`))
        markedRows.push(parseInt(cb.closest("tr").dataset.row, 10));

    if (markedRows.length == 0) {
        window.alert(_tr("alerts.no_marked_rows"));
        return;
    }

    if (markedRows.length == importRows.length) {
        // Confirm whole table removal
        if (!window.confirm(_tr("alerts.delete_everything")))
            return;
    } else {
        if (!window.confirm(_tr("alerts.delete_marked_rows", { count: markedRows.length })))
            return;
    }

    resetSelection();

    if (markedRows.length == importRows.length) {
        // Faster path for whole table deletion
        noData();
    } else {
        // Delete the selected rows. Live-update the table (don't rebuild it wholly).
        let tableRows = container.querySelectorAll("div#output table tbody tr");

        for (let i = markedRows.length - 1; i >= 0; i--) {
            const rowNum = markedRows[i];

            console.log(`Removing row ${rowNum}`);
            importRows.splice(rowNum, 1);
            tableRows[rowNum].parentNode.removeChild(tableRows[rowNum]);
        }

        // Reindex the remaining rows
        if (importRows.length == 0)
            noData();
        else {
            const rows = container.querySelectorAll("div#output table tbody tr");

            for (let row = 0; row < rows.length; row++) {
                rows[row].dataset.row = row;
                rows[row].querySelector("span").innerText = row + 1;
            }
        }
    }

    detectProblems();
}

// Called when the column type is changed from the combo box
function onColumnTypeChanged(e)
{
    const columnIndex = parseInt(e.target.parentNode.parentNode.dataset.column, 10);

    importHeaders[columnIndex] = e.target.value;
    const isUnused = (importHeaders[columnIndex] == "");

    resetSelection();

    for (const row of container.querySelectorAll("div#output table tbody tr")) {
        const cell = row.children[columnIndex + NUM_ROW_HEADERS];

        // detectProblems() removes the error class, but only
        // if the cell type is what it is looking for
        cell.classList.remove("error");

        toggleClass(cell, "skipped", isUnused);
        toggleClass(cell, "password", importHeaders[columnIndex] == "password");
    }

    detectProblems();
}

function onDeleteColumn(e)
{
    e.preventDefault();

    if (!window.confirm(_tr("alerts.delete_column")))
        return;

    closePopup();
    clearMenuButtons();
    resetSelection();

    const column = targetColumn.index;

    console.log(`Deleting column ${column}`);

    // Remove the column from the parsed data
    for (let row of importRows)
        row.columns.splice(column, 1);

    importHeaders.splice(column, 1);

    // Remove the table column
    for (let row of container.querySelector("div#output table").rows)
        row.deleteCell(column + NUM_ROW_HEADERS);

    reindexColumns();
    detectProblems();
}

function onClearColumn(e)
{
    e.preventDefault();

    if (!window.confirm(_tr("alerts.are_you_sure")))
        return;

    closePopup();
    clearMenuButtons();

    const column = targetColumn.index,
          [start, end] = getFillRange();

    console.log(`Clearing column ${column}`);

    for (let row = start; row < end; row++)
        importRows[row].columns[column] = "";

    const tableRows = container.querySelectorAll("div#output table tbody tr");

    for (let row = start; row < end; row++) {
        const cell = tableRows[row].children[column + NUM_ROW_HEADERS];

        cell.innerText = "";
        cell.classList.add("empty");
    }

    detectProblems();
}

// Inserts a new empty column on the right side
function onInsertColumn(e)
{
    e.preventDefault();

    closePopup();
    clearMenuButtons();
    resetSelection();

    const column = targetColumn.index;

    console.log(`Inserting a new column after column ${column}`);

    for (let row of importRows)
        row.columns.splice(column + 1, 0, "");

    importHeaders.splice(column + 1, 0, "");

    // Insert a header cell. The index number isn't important, as the columns are reindexed after.
    const row = container.querySelector("div#output table thead tr");

    row.insertBefore(buildColumnHeader(0, ""), row.children[column + NUM_ROW_HEADERS + 1]);

    // Then empty table cells
    for (let row of container.querySelector("div#output table tbody").rows) {
        const cell = create("td");

        cell.innerText = "";
        cell.classList.add("empty", "skipped");
        row.insertBefore(cell, row.children[column + NUM_ROW_HEADERS + 1]);
    }

    reindexColumns();
    detectProblems();
}

// Dynamically reload the schools' group list. This is called from the "proper" group add dialog,
// but also from the direct cell edit popup. Both dialogs have the same essential controls.
function onReloadGroups(e)
{
    e.target.textContent = _tr("buttons.reloading");
    e.target.disabled = true;
    popup.contents.querySelector("select#abbr").disabled = true;

    const previous = popup.contents.querySelector("select#abbr").value;

    fetch("reload_groups", {
        method: "GET",
        mode: "cors",
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
    }).then(response => {
        if (!response.ok)
            throw response;

        // Parse JSON separately, for better error handling
        return response.text();
    }).then(data => {
        let parsed = null;

        try {
            parsed = JSON.parse(data);
        } catch (e) {
            console.error("Can't parse the server response:");
            console.error(data);
            console.error(e);
            window.alert(_tr("alerts.cant_parse_server_response"));
            return;
        }

        setGroups(parsed);

        // Update the combo on-the-fly, if the popup still exists (it could have been closed
        // while fetch() was doing its job)
        // TODO: use makeGroupSelector() here?
        if (popup && popup.contents) {
            let html = "";

            for (const g of currentGroups)
                html += `<option value="${g.abbr}" ${g.abbr === previous ? "selected" : ""}>${g.name} (${localizedGroupTypes[g.type] || "?"})</option>`;

            popup.contents.querySelector("select#abbr").innerHTML = html;
        }
    }).catch(error => {
        console.error(error);
        window.alert(_tr("alerts.cant_parse_server_response"));
    }).finally(() => {
        // Re-enable the reload button
        e.target.textContent = _tr("buttons.reload_groups");
        e.target.disabled = false;
        popup.contents.querySelector("select#abbr").disabled = (currentGroups.length == 0);
    });
}

// Fill/generate column/selection contents
function onFillColumn(e)
{
    e.preventDefault();

    const column = targetColumn.index,
          type = importHeaders[column];

    const selection = (cellSelection.column == targetColumn.index &&
                       cellSelection.start !== -1 && cellSelection.end !== -1);

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

    switch (type) {
        case "role":
            setTitle("set_role");
            showButton("set");
            content = makeRoleSelector();
            break;

        case "group":
            setTitle("set_group");
            showButton("add");
            width = 300;
            content = makeGroupSelector();
            break;

        case "uid":
            setTitle("generate_usernames");
            showButton("generate");
            width = 350;

            content = getTemplate("generateUsernames");

            // Restore settings and setup events for saving them when changed
            check("drop", SETTINGS.import.username.umlauts == 0);
            check("replace", SETTINGS.import.username.umlauts == 1);

            content.querySelector("#drop").addEventListener("click", () => {
                SETTINGS.import.username.umlauts = 0;
                saveSettings();
            });

            content.querySelector("#replace").addEventListener("click", () => {
                SETTINGS.import.username.umlauts = 1;
                saveSettings();
            });

            break;

        case "password":
            setTitle("generate_passwords");
            showButton("generate");
            width = 350;

            content = getTemplate("generatePasswords");

            // Restore settings and setup events for saving them when changed
            check("fixed", !SETTINGS.import.password.randomize);
            check("random", SETTINGS.import.password.randomize);
            check("uppercase", SETTINGS.import.password.uppercase);
            check("lowercase", SETTINGS.import.password.lowercase);
            check("numbers", SETTINGS.import.password.numbers);
            check("punctuation", SETTINGS.import.password.punctuation);

            const len = clampPasswordLength(parseInt(SETTINGS.import.password.length, 10));
            let e = content.querySelector(`input#length`);

            e.min = MIN_PASSWORD_LENGTH;
            e.max = MAX_PASSWORD_LENGTH;
            e.value = len;

            content.querySelector("div#lengthValue").innerText = len;

            for (let i of content.querySelectorAll("input")) {
                i.addEventListener("click", e => {
                    if (e.target.id == "fixed")
                        SETTINGS.import.password.randomize = false;
                    else if (e.target.id == "random")
                        SETTINGS.import.password.randomize = true;
                    else if (e.target.id == "length")
                        SETTINGS.import.password.length = clampPasswordLength(parseInt(e.target.value, 10));
                    else SETTINGS.import.password[e.target.id] = e.target.checked;

                    saveSettings();
                });
            };

            content.querySelector("input#length").addEventListener("input", e => {
                // "content" (and thus querySelector()) does not exist in this context,
                // have to use nextSibling
                e.target.nextSibling.innerText = e.target.value
                SETTINGS.import.password.length = clampPasswordLength(parseInt(e.target.value, 10));
                saveSettings();
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

    ow.checked = SETTINGS.import.overwrite;
    ow.addEventListener("click", e => {
        SETTINGS.import.overwrite = e.target.checked;
        saveSettings();
    });

    // If this popup has an input field, focus it
    if (type == "first" || type == "last" || type == "phone" || type == "email" ||
        type == "eid" || type == "pnumber" || type == "")
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
    const type = importHeaders[targetColumn.index];
    const overwrite = popup.contents.querySelector("input#overwrite").checked;
    let value;

    // Generate the values
    switch (type) {
        case "uid":
            // value reused for the umlaut conversion type selection
            value = popup.contents.querySelector("input#drop").checked;
            console.log(`Generating usernames for column ${targetColumn.index}, mode=${value}, (overwrite=${overwrite})`);
            generateUsernames(!value, overwrite);
            return;

        case "password":
            console.log(`Generating/filling passwords for column ${targetColumn.index}, (overwrite=${overwrite})`);
            generatePasswords(overwrite);
            passwordsAlteredSinceImport = true;
            return;

        case "role":
            value = popup.contents.querySelector("select#role").value,
            console.log(`Filling roles in column ${targetColumn.index}, role=${value}`);
            break;

        case "group":
            if (currentGroups.length === 0) {
                window.alert(_tr("alerts.no_groups"));
                return;
            }

            value = popup.contents.querySelector("select#abbr").value;
            console.log(`Filling group in column ${targetColumn.index}, group abbreviation=${value} (overwrite=${overwrite})`);
            break;

        default:
            value = popup.contents.querySelector("input#value").value;
            console.log(`Filling column ${targetColumn.index} with "${value}" (overwrite=${overwrite})`);
            break;
    }

    // Update the table in-place
    let tableRows = container.querySelectorAll("div#output table tbody tr");

    const [start, end] = getFillRange();

    for (let i = start; i < end; i++) {
        let columns = importRows[i].columns;

        if (columns[targetColumn.index] != "" && !overwrite)
            continue;

        let tableCell = tableRows[i].children[targetColumn.index + NUM_ROW_HEADERS];

        columns[targetColumn.index] = value;
        tableCell.innerText = value;

        if (value == "")
            tableCell.classList.add("empty");
        else tableCell.classList.remove("empty");
    }

    // The popup dialog remains open, on purpose
    detectProblems();
}

// Generates usernames
function generateUsernames(alternateUmlauts, overwrite)
{
    const dropDiacritics = (string, alternateUmlauts) => {
        let out = string;

        if (alternateUmlauts) {
            // Convert some umlauts differently. These conversions won't work in Finnish,
            // but they work in some other languages.
            out = out.replace(/ä/g, "ae");
            out = out.replace(/ö/g, "oe");
            out = out.replace(/ü/g, "ue");
        }

        // Leaving this out will cause trouble (and the old version did this too)
        out = out.replace(/ß/g, "ss");

        // Decompose and remove the combining characters (ie. remove everything in the "Combining
        // Diacritical Marks" Unicode block (U+0300 -> U+036F)). This leaves the base characters
        // intact.
        out = out.normalize("NFD").replace(/[\u0300-\u036f]/g, "");

        // Finally remove everything that isn't permitted
        out = out.replace(/[^a-z0-9.-]/g, "");

        return out;
    };

    // ----------------------------------------------------------------------------------------------
    // First verify that we have first and last name columns

    let numFirst = 0,
        firstCol = 0,
        numLast = 0,
        lastCol = 0;

    const headers = container.querySelectorAll("div#output table thead th");

    for (let i = 0; i < importHeaders.length; i++) {
        // The possibility of having multiple first name/last name columns is small, but
        // it can happen to an absent-minded user. Let's handle that case too.
        if (importHeaders[i] === "first") {
            numFirst++;
            firstCol = i;
        }

        if (importHeaders[i] === "last") {
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
    let tableRows = container.querySelectorAll("div#output table tbody tr");

    for (let i = start; i < end; i++) {
        let columns = importRows[i].columns;

        // Missing values?
        if (columns[firstCol].trim().length == 0) {
            missing = true;
            continue;
        }

        if (columns[lastCol].trim().length == 0) {
            missing = true;
            continue;
        }

        // Generate a username
        const first = dropDiacritics(columns[firstCol].toLowerCase(), alternateUmlauts),
              last = dropDiacritics(columns[lastCol].toLowerCase(), alternateUmlauts);

        const username = `${first}.${last}`;

        if (first.length == 0 || last.length == 0) {
            console.error(`Can't generate username for "${columns[firstCol]} ${columns[lastCol]}"`);
            unconvertable.push([i + NUM_ROW_HEADERS, columns[firstCol], columns[lastCol]]);
            continue;
        }

        if (columns[targetColumn.index] != "" && !overwrite)
            continue;

        let tableCell = tableRows[i].children[targetColumn.index + NUM_ROW_HEADERS];

        columns[targetColumn.index] = username;
        tableCell.innerText = username;
        tableCell.classList.remove("empty");
    }

    // ----------------------------------------------------------------------------------------------
    // End reports

    // Update the table before displaying the message boxes
    detectProblems();

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

// Generates random passwords
function generatePasswords(overwrite)
{
    const tableRows = container.querySelectorAll("div#output table tbody tr");
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

        for (let row = start; row < end; row++) {
            const columns = importRows[row].columns;

            if (columns[targetColumn.index] != "" && !overwrite)
                continue;

            const tableCell = tableRows[row].children[targetColumn.index + NUM_ROW_HEADERS];

            columns[targetColumn.index] = password;
            tableCell.innerText = password;
            tableCell.classList.remove("empty");
        }

        detectProblems();
        return;
    }

    // ----------------------------------------------------------------------------------------------
    // Generate random passwords

    const shuffleString = (s) => {
        let a = s.split("");

        // Fisher-Yates shuffle, Durstenfeld version
        for (let first = a.length - 1; first > 0; first--) {
            const second = Math.floor(Math.random() * (first + 1));
            [a[first], a[second]] = [a[second], a[first]];
        }

        return a.join("");
    }

    let available = "";

    if (popup.contents.querySelector("input#uppercase").checked)
        available += shuffleString("ABCDEFGHIJKLMNOPQRSTUVWXYZ");

    if (popup.contents.querySelector("input#lowercase").checked)
        available += shuffleString("abcdefghijklmnopqrstuvwxyz");

    if (popup.contents.querySelector("input#numbers").checked)
        available += shuffleString("0123456789");

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

    for (let row = start; row < end; row++) {
        const columns = importRows[row].columns;

        if (columns[targetColumn.index] != "" && !overwrite)
            continue;

        const tableCell = tableRows[row].children[targetColumn.index + NUM_ROW_HEADERS];

        // Generate a random password
        const max = available.length;
        let password = "";

        // TODO: use crypto.getRandomValues() for proper random numbers? It returns values that
        // are OOB of the 'available' array and % can cause ugly repetitions, so the values cannot
        // be used directly.
        for (let j = 0; j < length; j++)
            password += available[Math.floor(Math.random() * max)];

        password = shuffleString(password);

        columns[targetColumn.index] = password;
        tableCell.innerText = password;
        tableCell.classList.remove("empty");
    }

    detectProblems();
}

// Open the column popup menu
function onOpenColumnMenu(e)
{
    targetColumn.column = e.target.parentNode.parentNode;
    targetColumn.index = parseInt(targetColumn.column.dataset.column, 10);

    e.target.classList.add("activeMenu");
    e.target.disabled = true;       // pressing Enter/Space would open another popup menu

    const selection = (cellSelection.column == targetColumn.index &&
                       cellSelection.start !== -1 && cellSelection.end !== -1);

    let fillTitle = null;

    let tmpl = getTemplate("columnMenu");

    // By default the menu contains all entries. Remove those that don't apply to this situation.
    let keep = null,
        title = null,
        enableFill = true,
        enableClear = false;

    switch (importHeaders[targetColumn.index]) {
        case "role":
            keep = "set_role";
            break;

        case "uid":
            keep = "generate_usernames";
            break;

        case "password":
            keep = "generate_passwords";
            enableClear = true;
            break;

        case "group":
            keep = "add_to_group";
            enableClear = true;
            break;

        case "email":
        case "phone":
        case "eid":
            enableFill = false;
            enableClear = true;
            break;

        case "pnumber":
            enableFill = false;
            enableClear = true;
            break;

        default:
            keep = selection ? "fill_selection" : "fill_column";
            break;
    }

    if (keep != "set_role")
        tmpl.querySelector("a#set_role").parentNode.remove();

    if (keep != "generate_usernames")
        tmpl.querySelector("a#generate_usernames").parentNode.remove();

    if (keep != "generate_passwords")
        tmpl.querySelector("a#generate_passwords").parentNode.remove();

    if (keep != "add_to_group")
        tmpl.querySelector("a#add_to_group").parentNode.remove();

    if (keep != "fill_selection")
        tmpl.querySelector("a#fill_selection").parentNode.remove();

    if (keep != "fill_column")
        tmpl.querySelector("a#fill_column").parentNode.remove();

    // Only some (rare) column types have a "clear" menu entry
    if (enableClear) {
        if (selection)
            tmpl.querySelector("a#clear_column").parentNode.remove();
        else tmpl.querySelector("a#clear_selection").parentNode.remove();
    } else {
        tmpl.querySelector("a#clear_column").parentNode.remove();
        tmpl.querySelector("a#clear_selection").parentNode.remove();
    }

    // Set events
    if (enableFill)
        tmpl.querySelector(`a#${keep}`).addEventListener("click", onFillColumn);

    tmpl.querySelector("a#insert_column").addEventListener("click", onInsertColumn);

    if (enableClear) {
        if (selection)
            tmpl.querySelector("a#clear_selection").addEventListener("click", onClearColumn);
        else tmpl.querySelector("a#clear_column").addEventListener("click", onClearColumn);
    }

    tmpl.querySelector("a#delete_column").addEventListener("click", onDeleteColumn);

    // Open the popup menu
    createPopup();
    popup.contents.style.width = "200px";
    popup.contents.appendChild(tmpl);

    const location = e.target.getBoundingClientRect();

    attachPopup(e.target, PopupType.COLUMN_MENU);
    displayPopup();

    document.body.addEventListener("keydown", onKeyDown);
}

// Potentially start a multi-cell selection
function onMouseDown(e)
{
    if (importActive)
        return;

    if (e.target.tagName != "TD")
        return;

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    e.preventDefault();

    cellSelection.mouseTrackPos = {
        x: e.clientX,
        y: e.clientY
    };

    cellSelection.initialClick = e.target;
    cellSelection.column = -1;
    cellSelection.start = -1;
    cellSelection.end = -1;

    for (let cell of container.querySelectorAll("table tbody td.selectedCell"))
        cell.classList.remove("selectedCell");

    // Start tracking the mouse and see if this is a single-cell click, or a multi-cell drag
    document.addEventListener("mouseup", onMouseUp);
    document.addEventListener("mousemove", onMouseMove);
}

// Stop multi-cell selection
function onMouseUp(e)
{
    if (importActive)
        return;

    e.preventDefault();

    cellSelection.active = false;
    cellSelection.mouseTrackPos = null;
    cellSelection.initialClick = null;
    cellSelection.previousCell = null;

    document.removeEventListener("mouseup", onMouseUp);
    document.removeEventListener("mousemove", onMouseMove);
}

// Initiate/update multi-cell selection
function onMouseMove(e)
{
    if (importActive)
        return;

    e.preventDefault();

    if (cellSelection.active) {
        // Update multi-cell drag selection
        if (e.target == cellSelection.previousCell)
            return;

        let current = document.elementFromPoint(e.clientX, e.clientY);

        if (!current || current.tagName != "TD") {
            // This can happen if the mouse goes outside of the browser window.
            // Don't cancel the selection.
            return;
        }

        const newEnd = clamp(current.parentNode.rowIndex - 1, 0, importRows.length);

        if (newEnd != cellSelection.end) {
            cellSelection.end = newEnd;
            highlightSelection();
        }

        cellSelection.previousCell = e.target;
        return;
    }

    // See if we should start a multi-cell selection. We need some tolerance here, because
    // the mouse can move a pixel or two during double-clicks, and we don't want those tiny
    // movements to trigger a selection.
    const dx = e.clientX - cellSelection.mouseTrackPos.x,
          dy = e.clientY - cellSelection.mouseTrackPos.y;

    const dist = Math.sqrt(dx * dx + dy * dy);

    if (dist < 5.0)
        return;

    // Yes, start multi-cell selection
    for (let cell of container.querySelectorAll("table tbody td.selectedCell"))
        cell.classList.remove("selectedCell");

    cellSelection.initialClick.classList.add("selectedCell");

    cellSelection.active = true;
    cellSelection.column = cellSelection.initialClick.cellIndex - NUM_ROW_HEADERS;
    cellSelection.start = cellSelection.initialClick.parentNode.rowIndex - 1;

    console.log(`Multi-cell selection initiated, col=${cellSelection.column}, row=${cellSelection.start}`);

    // The mouse can be move across multiple cells during the dragging period
    if (e.target == cellSelection.initialClick)
        cellSelection.end = e.target.parentNode.rowIndex - 1;
    else cellSelection.end = document.elementFromPoint(e.clientX, e.clientY).parentNode.rowIndex - 1;

    highlightSelection();
}

// Directly edit a cell's value
function onMouseDoubleClick(e)
{
    if (importActive)
        return;

    if (e.target.tagName != "TD")
        return;

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    e.preventDefault();

    directCellEdit.pos = {
        row: e.target.parentNode.rowIndex - 1,
        col: e.target.cellIndex - NUM_ROW_HEADERS
    };

    directCellEdit.target = e.target;

    const type = importHeaders[directCellEdit.pos.col];
    let value = e.target.innerText;

    console.log(`Editing cell (${directCellEdit.pos.row}, ${directCellEdit.pos.col}) directly, type=${type}`);

    const tmpl = getTemplate("directCellEdit");
    const contents = tmpl.querySelector("div#contents");

    switch (type) {
        case "role":
            contents.appendChild(makeRoleSelector(value));
            break;

        case "group":
            contents.appendChild(makeGroupSelector(value));
            break;

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
    if (!popup || !directCellEdit.target)
        return;

    const type = importHeaders[directCellEdit.pos.col];
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
    importRows[directCellEdit.pos.row].columns[directCellEdit.pos.col] = newValue;
    directCellEdit.target.innerText = newValue;

    if (type == "password") {
        // Prevent password PDF generation unless the table is imported first
        passwordsAlteredSinceImport = true;
    }

    if (newValue == "")
        directCellEdit.target.classList.add("empty");
    else directCellEdit.target.classList.remove("empty");

    directCellEdit.target.classList.remove("error");    // will be re-checked soon

    directCellEdit.pos = null;
    directCellEdit.target = null;

    closePopup();
    detectProblems();
}

// Close/accept a popup
function onKeyDown(e)
{
    if (!popup)
        return;

    if (e.keyCode == 27)
        closePopup();

    if (e.keyCode == 13 && directCellEdit.target)
        onSaveCellValue(null);
}

// Expand the colum header template. Called from multiple places.
function buildColumnHeader(index, type, isPreview=false)
{
    const tmpl = getTemplate(isPreview ? "previewColumnHeader" : "columnHeader");

    tmpl.querySelector("div.colNumber").innerText = CELLS[index % 26];

    if (isPreview) {
        if (type != "")
            tmpl.querySelector("div.colType").innerText = localizedColumnTitles[type];
    } else {
        if (type != "")
            tmpl.querySelector("select#type").value = type;

        tmpl.querySelector("select#type").addEventListener("change", onColumnTypeChanged);
        tmpl.querySelector("button#controls").addEventListener("click", onOpenColumnMenu);

        tmpl.querySelector("th").dataset.column = index;        // a handy place for this
    }

    return tmpl;
}

// Constructs the table containing the CSV parsing results
function buildImportTable(output, headers, rows, isPreview)
{
    // Handle special cases
    if (parserError) {
        output.innerHTML = `<p class="error">ERROR: ${parserError}</p>`;
        return;
    }

    if (rows.length == 0) {
        output.innerHTML = _tr('status.no_data_to_display');
        return;
    }

    const t0 = performance.now();

    // All rows have the same number of columns
    const numColumns = rows[0].columns.length;

    const knownColumns = new Set([]);

    let table = getTemplate("importTable");

    // The header row
    let headerRow = table.querySelector("thead tr");

    if (isPreview) {
        // Remove the status column. Beware of textNodes; if the table layout is changed,
        // the array index must be changed!
        headerRow.childNodes[3].remove();
        headerRow.classList.remove("stickyTop");
    }

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

    // Data rows
    let tbody = table.querySelector("tbody");

    for (let row = 0; row < rows.length; row++) {
        const columns = rows[row].columns;

        let tableRow = getTemplate("tableRow");
        let tr = tableRow.querySelector("tr");

        if (!isPreview)
            tr.dataset.row = row;

        tableRow.querySelector("span").innerText = row + 1;

        if (isPreview) {
            // Remove the "delete row" checkboxes
            tableRow.querySelector(`input[type="checkbox"]`).remove();
        } else {
            tr.appendChild(create("th", { cls: ["state", "idle"] }));
        }

        for (let col = 0; col < numColumns; col++) {
            let td = document.createElement("td");

            if (columns[col] == "")
                td.classList.add("empty");
            else td.innerText = columns[col];

            if (!knownColumns.has(col))
                td.classList.add("skipped");

            if (importHeaders[col] == "password")
                td.classList.add("password");

            tr.appendChild(td);
        }

        tbody.appendChild(tableRow);
    }

    if (isPreview) {
        // Remove the "delete row" checkboxes
        table.querySelector(`input#markAllRows`).remove();
    } else {
        tbody.addEventListener("mousedown", onMouseDown);
        tbody.addEventListener("dblclick", onMouseDoubleClick);
        table.querySelector("table").classList.add("notPreview");
        table.querySelector(`input#markAllRows`).addEventListener("click", e => onMarkAllRows(e));
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

function enableUI(state)
{
    container.querySelector("button#beginImport").disabled = !state;
    container.querySelector("button#retryFailed").disabled = !state;
    container.querySelector("button#getDuplicates").disabled = !state;
    container.querySelector("button#getPasswordPDF").disabled = !state;
    container.querySelector("button#deleteMarkedRows").disabled = !state;

    for (let i of container.querySelectorAll("input"))
        i.disabled = !state;

    for (let i of container.querySelectorAll("select"))
        i.disabled = !state;

    for (let i of container.querySelectorAll("textarea"))
        i.disabled = !state;

    // The click handlers check the value of this dataset item
    for (let i of container.querySelectorAll("div#output table a"))
        i.dataset.disabled = (state ? "0" : "1");
}

function updateStatistics()
{
    container.querySelector("div#status div#progress div#counter").innerHTML =
        `${statistics.totalRowsProcessed}/${workerRows.length} (` +
        `<span class="success">${statistics.success} ${_tr("status.success")}</span>, ` +
        `<span class="partial_success">${statistics.partialSuccess} ${_tr("status.partial_success")}</span>, ` +
        `<span class="failed">${statistics.failed} ${_tr("status.failed")}</span>)`;
}

function progressBegin(isResume)
{
    if (!isResume) {
        statistics.totalRowsProcessed = 0;
        statistics.success = 0;
        statistics.partialSuccess = 0;
        statistics.failed = 0;
        lastRowProcessed = 0;

        let elem = container.querySelector("div#status div#progress progress");
        elem.setAttribute("max", workerRows.length);
        elem.setAttribute("value", 0);
    }

    updateStatistics();

    container.querySelector("div#status div#progress").classList.remove("hidden");

    container.querySelector("button#beginImport").classList.add("hidden");
    container.querySelector("button#stopImport").classList.remove("hidden");
}

function progressUpdate()
{
    container.querySelector("div#status div#progress progress").setAttribute("value",
                            statistics.totalRowsProcessed);
    updateStatistics();
}

function progressEnd(success)
{
    if (importStopRequested)
        container.querySelector("div#status div#message").innerText = _tr("status.stopped");
    else container.querySelector("div#status div#message").innerText = _tr("status.complete");

    importActive = false;

    updateStatistics();

    container.querySelector("button#beginImport").classList.remove("hidden");
    container.querySelector("button#stopImport").classList.add("hidden");
}

function markRowsAsBeingProcessed(from, to)
{
    const tableRows = container.querySelectorAll("div#output table tbody tr");

    for (let row = from; row < to; row++) {
        if (row > workerRows.length - 1)
            break;

        // Each workerRow knows the actual table row number. They aren't
        // necessarily sequential.
        const cell = tableRows[workerRows[row][0]].querySelector("th.state");

        cell.classList.remove("idle", "failed", "partialSuccess", "success");
        cell.classList.add("processing");
    }
}

IMPORT_WORKER.onmessage = e => {
    switch (e.data.message) {
        case "progress": {
            console.log(`[main] Worker sent "${e.data.message}", total=${e.data.total}`);

            // UI update, based on the row states the server sent back
            const tableRows = container.querySelectorAll("div#output table tbody tr");

            for (const r of e.data.states) {
                let cls = "";

                switch (r.state) {
                    case "failed":
                    default:
                        cls = "failed";
                        statistics.failed++;
                        failedRows.push(r.row);
                        break;

                    case "partial_ok":
                        cls = "partialSuccess";
                        statistics.partialSuccess++;
                        break;

                    case "ok":
                        cls = "success";
                        statistics.success++;
                        break;
                }

                lastRowProcessed = Math.max(lastRowProcessed, r.row);

                const cell = tableRows[r.row].querySelector("th.state");

                cell.classList.remove("idle", "processing", "failed", "partialSuccess", "success");
                cell.classList.add(cls);

                if (r.state == "failed")
                    cell.appendChild(create("i", { cls: ["icon", "icon-attention"], title: r.error }));

                if (r.failed) {
                    for (const [col, n, msg] of r.failed) {
                        console.log(`Marking column "${col}" (${n}) on row ${r.row} as failed: ${msg}`);
                        tableRows[r.row].cells[n + NUM_ROW_HEADERS].classList.add("error");
                        tableRows[r.row].cells[n + NUM_ROW_HEADERS].title = msg;
                    }
                }

                statistics.totalRowsProcessed++;
            }

            console.log(`lastRowProcessed: ${lastRowProcessed} (length=${importRows.length})`);

            if (importStopRequested && lastRowProcessed < importRows.length - 1) {
                // Stop
                progressUpdate();
                progressEnd();
                enableUI(true);
                importStopRequested = false;
                previousImportStopped = true;
                break;
            }

            // Proceed to the next batch
            progressUpdate();
            markRowsAsBeingProcessed(statistics.totalRowsProcessed, statistics.totalRowsProcessed + BATCH_SIZE);
            IMPORT_WORKER.postMessage({ message: "continue" });
            break;
        }

        case "server_error": {
            // Mark the failed rows
            const failed = container.querySelectorAll("div#output table tbody th.state.processing");

            for (const cell of failed) {
                failedRows.push(parseInt(cell.closest("tr").dataset.row, 10));
                statistics.failed++;
                cell.classList.remove("processing");
                cell.classList.add("failed");
                cell.appendChild(create("i", { cls: ["icon", "icon-attention"] }));
                cell.title = e.data.error;
            }

            progressEnd();
            enableUI(true);

            container.querySelector("div#status div#message").innerText = _tr("status.aborted");

            window.alert("Server failure. Try again in a minute.");
            break;
        }

        // Finish up
        case "complete":
            console.log(`[main] Worker sent "${e.data.message}"`);
            progressEnd();
            enableUI(true);
            previousImportStopped = false;
            break;

        default:
            console.error(`[main] Unhandled import worker message "${e.data.message}"`);
            break;
    }
};

// Start the user import/update process
function beginImport(onlyFailed)
{
    if (importRows.length == 0 || importHeaders.length == 0) {
        window.alert(_tr("alerts.no_data_to_import"));
        return;
    }

    if (importProblems.length > 0) {
        window.alert(_tr("alerts.fix_problems_first"));
        return;
    }

    if (onlyFailed && failedRows.length == 0) {
        window.alert(_tr("alerts.no_failed_rows"));
        return;
    }

    let startRow = 0;
    let resume = false;

    // A simple resuming mechanism, in case the previous import was stopped
    if (previousImportStopped) {
        if (window.confirm(_tr("alerts.resume_previous"))) {
            startRow = lastRowProcessed + 1;
            resume = true;
        }
    }

    if (!window.confirm(_tr("alerts.are_you_sure")))
        return;

    let status = container.querySelector("div#status"),
        message = container.querySelector("div#status div#message");

    message.innerText = _tr("status.fetching_current_users");
    status.classList.remove("hidden");

    resetSelection();
    enableUI(false);

    // Clear previous states (unless we're resuming)
    if (!resume) {
        for (const row of container.querySelectorAll("div#output table tbody tr th.state")) {
            row.classList.add("idle");
            row.classList.remove("processing", "failed", "partialSuccess", "success");
            row.innerText = "";
        }

        for (const cell of container.querySelectorAll("div#output table tbody td.error")) {
            cell.classList.remove("error");
            cell.title = "";
        }
    }

    // Get a list of current users and their puavoIDs in the target organisation
    fetch("get_current_users", {
        method: "GET",
        mode: "cors",
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
    }).then(response => {
        if (!response.ok)
            throw response;

        return response.text();
    }).then(data => {
        // Parse the received JSON
        let existingUsers = null;

        try {
            existingUsers = JSON.parse(data);
        } catch (e) {
            message.innerText = "";
            status.classList.add("hidden");

            console.error("Can't parse the server response:");
            console.error(data);
            console.error(e);

            window.alert(_tr("alerts.cant_parse_server_response"));
            enableUI(true);

            return;
        }

        message.innerText = _tr("status.comparing_data");

        // Find the username column
        const uidCol = findColumn("uid");

        if (uidCol === -1) {
            // This shouldn't happen, we've validated the data!
            status.classList.add("hidden");
            enableUI(true);
            console.error("uidCol is NULL, how did we get this far without usenames?");
            window.alert("Can't find the UID column index. Please contact support.");
            return;
        }

        // Split the table data into two arrays: one for new users, one for users to be updated
        const existingUIDs = new Map();

        for (const e of existingUsers)
            existingUIDs.set(e.uid, e.id);

        let numNew = 0,
            numUpdate = 0;

        workerRows = [];

        // Process either all rows matching the update mode, or only the rows that
        // failed during the previous loop
        const numRows = onlyFailed ? failedRows.length : importRows.length;

        for (let i = 0; i < numRows; i++) {
            const row = onlyFailed ? failedRows[i] : i;
            const uid = importRows[row].columns[uidCol];

            if (existingUIDs.has(uid)) {
                if (SETTINGS.import.mode == 0 || SETTINGS.import.mode == 2) {
                    workerRows.push([row, existingUIDs.get(uid)].concat(importRows[row].columns));
                    numUpdate++;
                }
            } else {
                if (SETTINGS.import.mode == 0 || SETTINGS.import.mode == 1) {
                    workerRows.push([row, -1].concat(importRows[row].columns));
                    numNew++;
                }
            }
        }

        failedRows = [];

        console.log(`${numNew} new users, ${numUpdate} updated users`);

        if (workerRows.length == 0) {
            status.classList.add("hidden");
            enableUI(true);
            window.alert(_tr("alerts.no_data_to_import"));
            return;
        }

        alreadyClickedImportOnce = true;
        importActive = true;

        // *Technically* this should be set after the import is complete, not before...
        passwordsAlteredSinceImport = false;

        progressBegin(resume);
        markRowsAsBeingProcessed(startRow, startRow + BATCH_SIZE);

        // Now we know what to do, so launch a worker thread that does the sync
        // stuff in the background
        message.innerText = _tr("status.synchronising");

        IMPORT_WORKER.postMessage({
            message: "start",
            school: currentSchool,
            csrf: document.querySelector("meta[name='csrf-token']").content,
            startIndex: startRow,
            batchSize: BATCH_SIZE,
            headers: importHeaders,
            rows: workerRows,
        });
    }).catch(error => {
        message.innerText = "";
        status.classList.add("hidden");
        console.error(error);
        enableUI(true);
        window.alert(_tr("alerts.cant_parse_server_response"));
    });
}

function stopImport()
{
    if (importStopRequested)
        container.querySelector("div#status div#message").innerText = _tr("status.stopping_impatient");
    else {
        container.querySelector("div#status div#message").innerText = _tr("status.stopping");
        importStopRequested = true;
    }
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// MAIN

// Download a CSV of table rows that contain duplicate usernames
function getListOfDuplicateUIDs()
{
    const uidCol = findColumn("uid");

    if (uidCol === -1) {
        window.alert(_tr("problems.required_column_missing", { title: localizedColumnTitles["uid"] }));
        return;
    }

    // Find the rows that have duplicate usernames
    let usernames = new Set(),
        duplicateRows = [];

    for (let row = 0; row < importRows.length; row++) {
        const value = importRows[row].columns[uidCol];

        if (value === null || value.trim().length == 0)
            continue;

        const u = value.trim();

        if (usernames.has(u))
            duplicateRows.push(row);
        else usernames.add(u);
    }

    if (duplicateRows.length == 0) {
        window.alert(_tr("alerts.no_duplicate_uids"));
        return;
    }

    exportData(duplicateRows);
}

// Generate and download a PDF that contains the passwords in a neat format
function downloadPasswordPDF()
{
    const uidCol = findColumn("uid"),
          passwordCol = findColumn("password");

    if (uidCol === -1 || passwordCol === -1) {
        window.alert(_tr("alerts.no_data_for_the_pdf"));
        return;
    }

    let users = {};
    let missing = 0,
        total = 0;

    for (let row = 0; row < importRows.length; row++) {
        const uid = importRows[row].columns[uidCol],
              password = importRows[row].columns[passwordCol];

        if (uid === null || uid.trim().length < 3) {
            missing++;
            continue;
        }

        if (password === null || password.length < MIN_PASSWORD_LENGTH) {
            missing++;
            continue;
        }

        users[uid] = password;
        total++;
    }

    if (total == 0) {
        window.alert(_tr("alerts.still_no_data_for_the_pdf"));
        return;
    }

    // The PDF is useless if it contains passwords that haven't been imported
    if (passwordsAlteredSinceImport)
        if (!window.confirm(_tr("alerts.passwords_out_of_sync")))
            return;

    if (missing > 0) {
        if (!window.confirm(_tr("alerts.empty_rows_skipped")))
            return;
    }

    let filename = null,
        failed = false,
        error = null;

    container.querySelector("button#getPasswordPDF").disabled = true;

    fetch("password_pdf", {
        method: "POST",
        mode: "cors",
        headers: {
            // Again use text/plain to avoid RoR from logging user passwords in plaintext
            "Content-Type": "text/plain; charset=utf-8",
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
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
        const match = /^attachment; filename="(?<filename>.+)"$/.exec(response.headers.get("Content-Disposition"));

        if (!match) {
            window.alert("The server sent an invalid filename for the generated PDF. You will have to rename it yourself.");
            filename = "generated_passwords.pdf";
        } else filename = match.groups.filename;

        return response.blob();
    }).then(data => {
        if (failed) {
            console.log(data);
            throw new Error(`PDF generation failed:\n\n${data.message}\n\nThe server log might contain more information.`);
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
        container.querySelector("button#getPasswordPDF").disabled = false;
    });
}

// Either exports the current table as a CSV, or, if 'duplicateRows' is not NULL, exports
// the rows in it as a CSV.
function exportData(duplicateRows=null)
{
    // Use the same separator that was used during parsing
    const separator = { 0: ",", 1: ";", 2: "\t" }[SETTINGS.parser.separator];

    try {
        const outputRow = (row) => {
            let out = [];

            for (let col = 0; col < importHeaders.length; col++) {
                if (row.columns[col] == "")
                    out.push("");
                else out.push(row.columns[col]);
            }

            return out;
        };

        let output = [];

        // Header first
        output.push(importHeaders.join(separator));

        if (duplicateRows === null) {
            for (const row of importRows)
                output.push(outputRow(row).join(separator));
        } else {
            for (const rowNum of duplicateRows)
                output.push(outputRow(importRows[rowNum]).join(separator));
        }

        output = output.join("\n");

        // Build a blob object (it must be an array for some reason), then trigger a download.
        // Download code stolen from StackOverflow.
        const b = new Blob([output], { type: "text/csv" });
        let a = window.document.createElement("a");

        a.href = window.URL.createObjectURL(b);
        a.download = duplicateRows ? `duplicates.csv` :  `cleaned.csv`;

        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    } catch (e) {
        console.log(e);
        window.alert(`CSV generation failed, see the console for details.`);
    }
}

function switchImportTab()
{
    toggleClass(container.querySelector("nav button#page1"), "selected", SETTINGS.mainTab == 0);
    toggleClass(container.querySelector("nav button#page2"), "selected", SETTINGS.mainTab == 1);
    toggleClass(container.querySelector("section#page1"), "hidden", SETTINGS.mainTab == 1);
    toggleClass(container.querySelector("section#page2"), "hidden", SETTINGS.mainTab == 0);
}

function onChangeImportTab(newTab)
{
    if (newTab != SETTINGS.mainTab) {
        SETTINGS.mainTab = newTab;
        saveSettings();
        switchImportTab();
    }
}

function onChangeSource()
{
    if (container.querySelector("select#source").value == "manual")
        SETTINGS.parser.sourceTab = 0;
    else SETTINGS.parser.sourceTab = 1;

    toggleClass(container.querySelector("div#manual"), "hidden", SETTINGS.parser.sourceTab == 1);
    toggleClass(container.querySelector("div#upload"), "hidden", SETTINGS.parser.sourceTab == 0);

    updatePreview();
}

function initializeImporter(params)
{
    try {
        container = params.container;

        // Prepare data
        localizedColumnTitles = params.columnTitles;
        localizedGroupTypes = params.groupTypes;
        automaticEmails = params.automaticEmails || false;
        commonPasswords = params.commonPasswords || commonPasswords;

        currentSchool = params.schoolId;

        if ("groups" in params)
            setGroups(params.groups);

        // Initial UI update
        loadSettings();
        switchImportTab();
        onChangeSource();
        updateParsingSummary();

        // Setup event handling and restore parser settings
        container.querySelector("nav button#page1").addEventListener("click", () => { onChangeImportTab(0); });
        container.querySelector("nav button#page2").addEventListener("click", () => { onChangeImportTab(1); });
        container.querySelector("select#source").addEventListener("change", () => onChangeSource());

        const settings = container.querySelector("details#settings");

        settings.querySelector("input#inferTypes").addEventListener("click", e => { SETTINGS.parser.infer = e.target.checked; });
        settings.querySelector("input#trimValues").addEventListener("click", e => { SETTINGS.parser.trim = e.target.checked; });
        settings.querySelector("input#comma").addEventListener("click", e => { SETTINGS.parser.separator = 0; });
        settings.querySelector("input#semicolon").addEventListener("click", e => { SETTINGS.parser.separator = 1; });
        settings.querySelector("input#tab").addEventListener("click", e => { SETTINGS.parser.separator = 2; });

        for (let i of settings.querySelectorAll("input")) {
            i.addEventListener("click", e => {
                saveSettings();
                updateParsingSummary();
                updatePreview();
            });
        }

        container.querySelector("input#fileUpload").addEventListener("change", e => {
            // Parse the "uploaded" file
            let reader = new FileReader();

            reader.onload = () => {
                fileContents = reader.result;
                updatePreview();
            };

            reader.onerror = () => {
                window.alert(reader.error);
            };

            reader.readAsText(e.target.files[0], "utf-8");
        });

        container.querySelector("div#manual textarea").addEventListener("input", updatePreview);

        settings.querySelector("input#inferTypes").checked = SETTINGS.parser.infer;
        settings.querySelector("input#trimValues").checked = SETTINGS.parser.trim;
        settings.querySelector("input#comma").checked = (SETTINGS.parser.separator == 0);
        settings.querySelector("input#semicolon").checked = (SETTINGS.parser.separator == 1);
        settings.querySelector("input#tab").checked = (SETTINGS.parser.separator == 2);

        container.querySelector(`select#mode`).addEventListener("change", e => {
            SETTINGS.import.mode = parseInt(e.target.value, 10);
            previousImportStopped = false;      // otherwise this would get too complicated
            saveSettings();
            detectProblems();
        });

        container.querySelector("button#readData").addEventListener("click", () => {
            if (readAllData())
                onChangeImportTab(1);
        });

        container.querySelector("button#beginImport").
            addEventListener("click", () => beginImport(false));

        container.querySelector("button#retryFailed").
            addEventListener("click", () => beginImport(true));

        container.querySelector("button#stopImport").addEventListener("click", stopImport);
        container.querySelector("button#getDuplicates").addEventListener("click", getListOfDuplicateUIDs);
        container.querySelector("button#getPasswordPDF").addEventListener("click", downloadPasswordPDF);
        container.querySelector("button#deleteMarkedRows").addEventListener("click", onDeleteMarkedRows);

        container.querySelector(`select#mode`).value = SETTINGS.import.mode;

        // Close any popups that might be active
        document.body.addEventListener("click", e => {
            if (popup && e.target == popup.backdrop)
                closePopup();
        });

        // Reposition the popup when the page is scrolled
        document.addEventListener("scroll", ensurePopupIsVisible);

        updatePreview();
    } catch (e) {
        console.error(e);

        params.container.innerHTML =
            `<p class="error">Importer initialization failed. Please see the browser console for technical ` +
            `details, then contact Opinsys Oy for assistance.</p>`;

        return;
    }
}
