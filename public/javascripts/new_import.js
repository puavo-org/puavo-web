"use strict";

/*
Puavo Mass User Import III
Version 0.7
*/

// Localized column titles
let COLUMN_TITLES = {};

// Localized group types
let GROUP_TYPES = {};

// For new users, you need at least these columns
const REQUIRED_COLUMNS_NEW = new Set(["first", "last", "uid", "role"]);

// The same as above, but for existing users (when updating their attributes)
const REQUIRED_COLUMNS_UPDATE = new Set(["uid"]);

// Inferred column types. Maps various alternative colum name variants to one of the above
// colum names. If the inferred name does not exist in COLUMN_TITLES, bad things will happen.
// So don't do that.
// WARNING: If you edit this, remember to also update the inferring table in the page HTML.
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

const CELLS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

const MIN_PASSWORD_LENGTH = 5,
      MAX_PASSWORD_LENGTH = 50;

// Used to validate usernames
const USERNAME_REGEXP = /^[a-z][a-z0-9.-]{2,}$/;

// Used to extract filenames from the HTTP Content-Disposition header. Will not work if
// we're not getting an attachment download.
const CONTENT_DISPOSITION = /^attachment; filename="(?<filename>.+)"$/;

// Batching size for the import process. Reduces the number of network calls, but makes the UI
// seem slower (as it's not updated very often).
const BATCH_SIZE = 5;

// How many header columns each row has on the left edge
const NUM_ROW_HEADERS = 2;

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

// A shorter to type alias
function _tr(id, params={}) { return I18n.translate(id, params); }

// Returns a usable copy of a named HTML template. It's a DocumentFragment, not text,
// so it must be handled with DOM methods.
function getTemplate(id)
{
    return document.querySelector(`template#template_${id}`).content.cloneNode(true);
}

// Adds or removes 'cls' from target's classList, depending on 'state' (true=add, false=remove).
const toggleClass = (target, cls, state) => {
    state ? target.classList.add(cls) : target.classList.remove(cls);
};

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA

// Worker threads for CSV parsing and the actual data import/update process
const CSV_PARSER_WORKER = new Worker("/javascripts/csv_parser.js"),
      IMPORT_WORKER = new Worker("/javascripts/import_worker.js");

// Raw contents of the uploaded file (manual entry uses the textarea directly), grabbed
// whenever user selects a file (it cannot be done when the import actually begins, it
// has to be done in advance, when the file select event fires).
let fileContents = null;

// If not null, contains the error message the CSV parser returned
let parserError = null;

// Header column types (see the COLUMN_TYPES table, null if the column is skipped/unknown).
// This MUST have the same number of elements as there are data columns in the table!
let importHeaders = [];

// Tabular data parsed from the file/direct input. Each row is a 2-element table, the
// first element is a row number in the original data (zero-based) and the next element
// is an array containing the parsed row contents.
let importRows = [];

// Array of known problems in the import data that prevent the import process from starting.
// See detectProblems() for details.
let importProblems = [];

// Like above, but warnings. These won't prevent the import process.
let importWarnings = [];

// Everything in the import tool happens inside this container element
let container = null;

// The column we're editing when the column popup/dialog is open
let targetColumn = {
    column: null,
    index: -1
};

// Popup menu/dialog
let popup = {
    backdrop: null,
    contents: null,
    desiredPosition: {
        x: 0,
        y: 0
    },
};

// The (row, col) coordinates and the TD element we're directly editing (double-click)
let directCellEdit = {
    pos: null,
    target: null,
};

// Multiple selected cells
let cellSelection = {
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

// Current settings. Call loadDefaultSettings() to load the defaults.
let SETTINGS = {};

// The ID of the current school, set in the initializer
let SCHOOL_ID = -1;

// Current groups in the target school. Can be specified in the importer initializer, and
// optionally updated dynamically without reloading the page.
let SCHOOL_GROUPS = [];

// Tab-separated string of common passwords
let commonPasswords = "\tpassword\tsalasana\t";

// True if email addresses are automatic in this school/organisation, and thus email address
// columns will be ignored.
let automaticEmails = false;

// True if the user has already imported/updated something
let alreadyClickedImportOnce = false;

// True if an import job is currently active
let importActive = false;

// A copy of the table data used during the import process. Also contains table row numbers
// and other oddities. Don't touch.
let workerRows = [];

// List of failed rows (numbers). The user can retry them.
let failedRows = [];

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
const EXPECTED_SETTINGS_VERSION = 0;

function loadDefaultSettings()
{
    SETTINGS = {
        version: EXPECTED_SETTINGS_VERSION,
        parser: {
            tab: 0,
            infer: true,
            trim: true,
            separator: 0,   // 0=comma, 1=semicolon, 2=tab
        },
        import: {
            method: 1,      // 0=full sync, 1=import new users only, 2=update existing users only
            overwrite: true,
            username: {
                umlauts: 0,
            },
            password: {
                method: 1,
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

    SETTINGS.import.password.length = clamp(SETTINGS.import.password.length,
                                            MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH);
}

function getParserSettings()
{
    let settings = {
        separator: ";",
        wantHeader: container.querySelector("#inferTypes").checked,
        trimValues: container.querySelector("#trimValues").checked,
    };

    if (container.querySelector("#comma").checked)
        settings.separator =  ",";

    if (container.querySelector("#tab").checked)
        settings.separator =  "\t";

    return settings;
}

// Math.clamp() does not exist at the moment
function clamp(value, min, max)
{
    return Math.min(Math.max(min, value), max);
}

function sortGroups()
{
    SCHOOL_GROUPS.sort((a, b) => { return a["name"].localeCompare(b["name"]) });
}

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

// Called when a file has been selected
function onFileUploaded(e)
{
    let reader = new FileReader();

    reader.onload = () => { fileContents = reader.result; };
    reader.onerror = () => { window.alert(reader.error); };
    reader.readAsText(e.target.files[0], "utf-8");
}

// Updates the parser options summary
function updateParsingSummary()
{
    const settings = getParserSettings();

    const SEPARATORS = {
        ",": "commas",
        ";": "semicolons",
        "\t": "tabs",
    };

    if (!(settings.separator in SEPARATORS))
        settings.separator = ",";

    let parts = [];

    parts.push(`${_tr('parser.separated_by')} ${_tr("parser." + SEPARATORS[settings.separator])}`);

    if (settings.wantHeader)
        parts.push(_tr('parser.infer'));

    if (settings.trimValues)
        parts.push(_tr('parser.trim'));

    container.querySelector("details#settings summary").innerHTML =
        `${_tr('parser.title')} (${parts.join(", ")})`;
}

// Takes the data from the CSV parser and "cleans" it
function prepareRawImportedData(results)
{
    parserError = null;
    importHeaders = [];
    importRows = [];

    if (results.state == "error" || !Array.isArray(results.rows)) {
        parserError = results.message;
        return;
    }

    if (results.rows.length == 0)
        return;

    if (Array.isArray(results.headers)) {
        importHeaders = [...results.headers];

        for (let i = 0; i < importHeaders.length; i++) {
            // Some columns have multiple aliases
            if (importHeaders[i] in INFERRED_NAMES)
                importHeaders[i] = INFERRED_NAMES[importHeaders[i]];

            // Clear unknown column names so they don't mess up anything
            if (!(importHeaders[i] in COLUMN_TITLES))
                importHeaders[i] = "";
        }
    }

    importRows = [...results.rows];

    // Find the "widest" row, then pad all rows to have the same number of columns/cells.
    // It's far easier to handle empty values than empty OR missing values.
    let maxColumns = importHeaders.length;

    for (const row of importRows)
        maxColumns = Math.max(maxColumns, row.columns.length);

    console.log(`prepareRawImportedData(): the widest row has ${maxColumns} columns`);

    while (importHeaders.length < maxColumns)
        importHeaders.push("");     // "skip this column"

    for (let row of importRows)
        while (row.columns.length < maxColumns)
            row.columns.push("");

//    console.log(importHeaders);
//    console.log(importRows);
}

// Route messages from the worker thread to the function that updates the UI
CSV_PARSER_WORKER.onmessage = e => {
    prepareRawImportedData(e.data);
    buildImportTable();
    detectProblems();
}

// Launch a worker thread for CSS parsing
function beginCSVParse()
{
    if (alreadyClickedImportOnce) {
        if (!window.confirm("Sinulla on jo keskeneräistä dataa taulukossa. Oletko varma että haluat ylikirjoittaa sen?"))
            return;
    }

    alreadyClickedImportOnce = false;

    let source = null;

    // Get source data
    if (SETTINGS.parser.tab == 1) {
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

    // Launch a worker thread that parses the file
    CSV_PARSER_WORKER.postMessage({
        source: source,
        settings: getParserSettings(),
    });
}

// --------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------
// DATA PREVIEW AND MANIPULATION

function LOGITANYTVITTUSE(x)
{
    console.log(JSON.parse(JSON.stringify(x)));
}

// Re-enables column settings buttons
function clearMenuButtons()
{
    for (let button of container.querySelectorAll("table#preview thead button.controls")) {
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

/*
    targetColumn.column = null;
    targetColumn.index = -1;
*/

    popup.contents.innerHTML = "";
    popup.contents = null;
    popup.backdrop.remove();
    popup.backdrop = null;
}

function displayPopup()
{
    if (popup.backdrop)
        document.body.appendChild(popup.backdrop);
}

// You need to call this before displayPopup()
function placePopupAt(x, y, width=null)
{
    popup.desiredPosition.x = x;
    popup.desiredPosition.y = y;

    popup.contents.style.display = "block";
    popup.contents.style.position = "absolute";
    popup.contents.style.left = `${Math.round(x)}px`;
    popup.contents.style.top = `${Math.round(y)}px`;

    if (width !== null)
        popup.contents.style.width = `${Math.round(width)}px`;
}

// Positions the popup (menu or dialog) so that it's fully visible.
// The positioning breaks if the page is scrolled, though.
function ensurePopupIsVisible()
{
    if (!popup.backdrop)
        return;

    const popupRect = popup.contents.getBoundingClientRect(),
          pageWidth = document.documentElement.clientWidth,
          pageHeight = document.documentElement.clientHeight,
          popupW = popupRect.right - popupRect.left,
          popupH = popupRect.bottom - popupRect.top;

    if (popupRect.left < 0)
        popup.contents.style.left = `0px`;
    else if (popupRect.right > pageWidth)
        popup.contents.style.left = `${Math.round(pageWidth - popupW)}px`;

    if (popupRect.bottom > pageHeight)
        popup.contents.style.top = `${Math.round(pageHeight - popupH)}px`;
}

// Re-number column indexes in their header row datasets
function reindexColumns()
{
    let headings = container.querySelectorAll("table#preview thead th");

    if (headings.length == 1) {
        // Only the row number column is remaining, so effectively there's no data to display
        noData();
        return;
    }

    // firstChild cannot be used due to whitespace textNodes
    for (let i = NUM_ROW_HEADERS; i < headings.length; i++) {
        headings[i].dataset.column = i - NUM_ROW_HEADERS;
        headings[i].childNodes[1].childNodes[1].innerText = CELLS[(i - NUM_ROW_HEADERS) % 26];
    }
}

// Computes the start and end values for a fill-type operation. Takes the selection into account.
function getFillRange()
{
    let start, end;

    if (cellSelection.column == targetColumn.index &&
        cellSelection.start !== -1 &&
        cellSelection.end !== -1) {

        // We have a selection targeting this column (end is +1 because
        // the selection range is inclusive)
        start = Math.min(cellSelection.start, cellSelection.end);
        end = Math.max(cellSelection.start, cellSelection.end) + 1;
    } else {
        start = 0;
        end = importRows.length;
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

        if ((cell.cellIndex == cellSelection.column) && row >= start && row <= end)
            continue;

        cell.classList.remove("selectedCell");
    }

    // Then add it to all cells that are in the range
    const rows = container.querySelectorAll("table#preview tbody tr");

    for (let row = start; row <= end; row++)
        rows[row].children[cellSelection.column + NUM_ROW_HEADERS].classList.add("selectedCell");
}

function detectProblems()
{
    let output = container.querySelector("div#problems");

    if (importRows === null || importRows.length == 0) {
        output.innerHTML = "";
        output.classList.add("hidden");
        return;
    }

    // Certain problems will be ignored if we're only updating existing users
    const updateOnly = (SETTINGS.import.method == 2);

    const firstCol = findColumn("first"),
          lastCol = findColumn("last"),
          uidCol = findColumn("uid"),
          roleCol = findColumn("role"),
          eidCol = findColumn("eid"),
          emailCol = findColumn("email"),
          phoneCol = findColumn("phone"),
          passwordCol = findColumn("password");

    const tableRows = container.querySelectorAll("table#preview tbody tr");

    importProblems = [];
    importWarnings = [];

    // ----------------------------------------------------------------------------------------------
    // Make sure required columns are present and there are no duplicates

    let counts = {};

    for (const i of importHeaders) {
        if (i === null || i === undefined || i == "")
            continue;

        if (i in counts)
            counts[i]++;
        else counts[i] = 1;
    }

    for (const i of Object.keys(counts))
        if (counts[i] > 1)
            importProblems.push(`${_tr("problems.multiple_columns", { title: COLUMN_TITLES[i] })}`);

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
            importProblems.push(_tr("problems.no_role_mass_change"));
    } else {
        for (const r of REQUIRED_COLUMNS_NEW)
            if (!(r in counts))
                importProblems.push(`${_tr("problems.required_column_missing", { title: COLUMN_TITLES[r] })}`);

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
    if (!updateOnly && uidCol !== -1) {
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
                email = new Set();

            for (let row = 0; row < importRows.length; row++) {
                const value = importRows[row].columns[emailCol],
                      cell = tableRows[row].children[emailCol + NUM_ROW_HEADERS];

                if (value === null || value.trim().length == 0) {
                    cell.classList.remove("error");
                    continue;
                }

                if (email.has(value)) {
                    numDuplicate++;
                    cell.classList.add("error");
                } else email.add(value);
            }

            if (numDuplicate > 0)
                importProblems.push(_tr('problems.duplicate_email', { count: numDuplicate }));
        }
    }

    // Telephone numbers
    if (phoneCol !== -1) {
        let numDuplicate = 0,
            phone = new Set();

        for (let row = 0; row < importRows.length; row++) {
            const value = importRows[row].columns[phoneCol],
                  cell = tableRows[row].children[phoneCol + NUM_ROW_HEADERS];

            if (value === null || value.trim().length == 0) {
                cell.classList.remove("error");
                continue;
            }

            if (phone.has(value)) {
                numDuplicate++;
                cell.classList.add("error");
            } else phone.add(value);
        }

        if (numDuplicate > 0)
            importProblems.push(_tr('problems.duplicate_phone', { count: numDuplicate }));
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
    // Generate a list of problems

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

// Called when there's no data to import. Ensures everything is cleared.
function noData()
{
    if (container)
        container.querySelector("div#output").innerHTML = _tr('status.no_data_to_display');

    parserError = null;
    importHeaders = [];
    importRows = [];
}

function onDeleteAll(e)
{
    e.preventDefault();

    if (!window.confirm(_tr("alerts.delete_all")))
        return;

    resetSelection();
    noData();
    detectProblems();
}

function onDeleteRow(e)
{
    e.preventDefault();

    if (e.target.dataset.disabled === "1")
        return;

    if (!window.confirm(_tr("alerts.delete_row")))
        return;

    resetSelection();

    let tr = e.target.parentNode.parentNode.parentNode;
    const rowNum = parseInt(tr.dataset.row, 10);

    console.log(`Deleting row ${rowNum}`);

    // Remove the row from the parsed data
    importRows.splice(rowNum, 1);

    // Live delete the table row
    tr.parentNode.removeChild(tr);

    if (importRows.length == 0)
        noData();
    else {
        // Reindex the remaining rows
        const rows = container.querySelectorAll("table#preview tbody tr");

        for (let row = 0; row < rows.length; row++) {
            rows[row].dataset.row = row;
            rows[row].querySelector("span").innerText = row + 1;
        }
    }

    detectProblems();
}

// Called when the column type is changed from the combo box
function onColumnTypeChanged(e)
{
    const columnIndex = parseInt(e.target.parentNode.parentNode.dataset.column, 10);

//    const wasUnused = (importHeaders[columnIndex] == "");
    importHeaders[columnIndex] = e.target.value;
    const isUnused = (importHeaders[columnIndex] == "");

//    console.log(importHeaders[columnIndex]);

    resetSelection();

/*
    // TODO: Finish this?

    // Optimize classname changes, don't do anything unless the state actually changed
    if (wasUnused == isUnused) {
        detectProblems();
        return;
    }
*/

    for (const tableRow of container.querySelectorAll("table#preview tbody tr")) {
        const cell = tableRow.children[columnIndex + NUM_ROW_HEADERS];

        // detectProblems() removes the error class, but only
        // if the cell type is what it is looking for
        cell.classList.remove("error");

        toggleClass(cell, "skipped", isUnused);
        toggleClass(cell, "password", importHeaders[columnIndex] == "password");
    }

    detectProblems();
}

// Deletes a column
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
    for (let row of container.querySelector("table#preview").rows)
        row.deleteCell(column + NUM_ROW_HEADERS);

    reindexColumns();
    detectProblems();
}

// Clears column/selection contents
function onClearColumn(e)
{
    e.preventDefault();

    if (!window.confirm(_tr("alerts.are_you_sure")))
        return;

    closePopup();
    clearMenuButtons();

    const column = targetColumn.index;
    const [start, end] = getFillRange();

    console.log(`Clearing column ${column}`);

    for (let row = start; row < end; row++)
        importRows[row].columns[column] = "";

    const rows = container.querySelectorAll("table#preview tbody tr");

    for (let row = start; row < end; row++) {
        const cell = rows[row].children[column + NUM_ROW_HEADERS];

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
    const row = container.querySelector("table#preview thead tr");

    row.insertBefore(buildColumnHeader(0, ""), row.children[column + NUM_ROW_HEADERS + 1]);

    // Then empty table cells
    for (let row of container.querySelector("table#preview tbody").rows) {
        const cell = create("td");

        cell.innerText = "";
        cell.classList.add("empty", "skipped");
        row.insertBefore(cell, row.children[column + NUM_ROW_HEADERS + 1]);
    }

    reindexColumns();
    detectProblems();
}

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
    selector.disabled = (SCHOOL_GROUPS.length == 0);

    for (const g of SCHOOL_GROUPS) {
        let o = create("option");

        o.value = g.abbr;
        o.selected = (current === g.abbr);
        o.innerText = `${g.name} (${GROUP_TYPES[g.type] || "?"})`;

        selector.appendChild(o);
    }

    tmpl.querySelector("button#reload").addEventListener("click", onReloadGroups);

    return tmpl;
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

        SCHOOL_GROUPS = [...parsed];
        sortGroups();

        // Update the combo on-the-fly, if the popup still exists (it could have been closed
        // while fetch() was doing its job)
        // TODO: use makeGroupSelector() here?
        if (popup && popup.contents) {
            let html = "";

            for (const g of SCHOOL_GROUPS)
                html += `<option value="${g.abbr}" ${g.abbr === previous ? "selected" : ""}>${g.name} (${GROUP_TYPES[g.type] || "?"})</option>`;

            popup.contents.querySelector("select#abbr").innerHTML = html;
        }
    }).catch(error => {
        console.error(error);
        window.alert(_tr("alerts.cant_parse_server_response"));
    }).finally(() => {
        // Re-enable the reload button
        e.target.textContent = _tr("buttons.reload_groups");
        e.target.disabled = false;
        popup.contents.querySelector("select#abbr").disabled = (SCHOOL_GROUPS.length == 0);
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
            content.querySelector(`input#drop`).checked = (SETTINGS.import.username.umlauts == 0);
            content.querySelector(`input#replace`).checked = (SETTINGS.import.username.umlauts == 1);

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
            content.querySelector(`input#custom`).checked = (SETTINGS.import.password.method == 0);
            content.querySelector(`input#generate`).checked = (SETTINGS.import.password.method == 1);
            content.querySelector(`input#uppercase`).checked = (SETTINGS.import.password.uppercase == 1);
            content.querySelector(`input#lowercase`).checked = (SETTINGS.import.password.lowercase == 1);
            content.querySelector(`input#numbers`).checked = (SETTINGS.import.password.numbers == 1);
            content.querySelector(`input#punctuation`).checked = (SETTINGS.import.password.punctuation == 1);

            const len = clamp(parseInt(SETTINGS.import.password.length, 10),
                              MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH);

            let e = content.querySelector(`input#length`);

            e.min = MIN_PASSWORD_LENGTH;
            e.max = MAX_PASSWORD_LENGTH;
            e.value = len;

            content.querySelector("div#lengthValue").innerText = len;

            for (let i of content.querySelectorAll("input")) {
                i.addEventListener("click", e => {
                    if (e.target.id == "custom")
                        SETTINGS.import.password.method = 0;
                    else if (e.target.id == "generate")
                        SETTINGS.import.password.method = 1;
                    else if (e.target.id == "length")
                        SETTINGS.import.password.length =
                            clamp(parseInt(e.target.value, 10), MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH);
                    else SETTINGS.import.password[e.target.id] = e.target.checked;

                    saveSettings();
                });
            };

            content.querySelector("input#length").addEventListener("input", e => {
                // "content" (and thus querySelector()) does not exist in this context,
                // have to use nextSibling
                e.target.nextSibling.innerText = e.target.value

                SETTINGS.import.password.length =
                    clamp(parseInt(e.target.value, 10), MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH);
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

    ensurePopupIsVisible();

    // Restore settings and set event handling so that changed settings are saved
    let ow = popup.contents.querySelector(`input[type="checkbox"]#overwrite`);

    ow.checked = SETTINGS.import.overwrite;
    ow.addEventListener("click", e => {
        SETTINGS.import.overwrite = e.target.checked;
        saveSettings();
    });

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
            return;

        case "role":
            value = popup.contents.querySelector("select#role").value,
            console.log(`Filling roles in column ${targetColumn.index}, role=${value}`);
            break;

        case "group":
            if (SCHOOL_GROUPS.length === 0) {
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
    let tableRows = container.querySelectorAll("table#preview tbody tr");

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

    const headers = container.querySelectorAll("table#preview thead th");

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
    let tableRows = container.querySelectorAll("table#preview tbody tr");

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
    const tableRows = container.querySelectorAll("table#preview tbody tr");
    const [start, end] = getFillRange();

    // ----------------------------------------------------------------------------------------------
    // Set all to the same password (don't use this!)

    if (popup.contents.querySelector("input#custom").checked) {
        if (!window.confirm(_tr("alerts.same_password")))
            return;

        const password = popup.contents.querySelector("input#customPassword").value;

        if (password.length < 5) {
            window.alert(_tr("alerts.too_short_password"));
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
    if (length < 5) {
        window.alert(_tr("alerts.too_short_password"));
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

    placePopupAt(location.left - 1, location.bottom - 1);
    displayPopup();
    ensurePopupIsVisible();

    document.body.addEventListener("keydown", onKeyDown);
}

// Mouse tracking start
function onMouseDown(e)
{
    if (e.target.tagName != "TD")
        return;

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    if (importActive)
        return;

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

    // See if we should start a multi-cell selection
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
    if (e.target.tagName != "TD")
        return;

    if (e.button != 0) {
        // "Main" button only, no right clicks (or left clicks, if the buttons are swapped)
        return;
    }

    if (importActive)
        return;

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
    placePopupAt(location.left - 5, location.top - 1, location.right - location.left + 11);
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
        if (newValue.length > 0 && newValue.length < 5) {
            window.alert(_tr("alerts.too_short_password"));
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
function buildColumnHeader(index, type=null)
{
    const tmpl = getTemplate("columnHeader");

    tmpl.querySelector("th").dataset.column = index;    // a handy place for this
    tmpl.querySelector("div.colNumber").innerText = CELLS[index % 25];

    if (type != "")
        tmpl.querySelector("select#type").value = type;

    tmpl.querySelector("select#type").addEventListener("change", onColumnTypeChanged);
    tmpl.querySelector("button#controls").addEventListener("click", onOpenColumnMenu);

    return tmpl;
}

// Constructs the table containing the CSV parsing results
// TODO: Use more HTML templates here
function buildImportTable()
{
    const output = container.querySelector("div#output");

    resetSelection();

    // Handle special cases
    if (parserError) {
        output.innerHTML = `<p class="error">ERROR: ${parserError}</p>`;
        return;
    }

    if (importRows.length == 0) {
        noData();
        return;
    }

    const t0 = performance.now();

    // All rows have the same number of columns
    const numColumns = importRows[0].columns.length;

    const knownColumns = new Set([]);

    let table = getTemplate("importTable");

    // The header row
    let headerRow = table.querySelector("thead tr");

    for (let i = 0; i < numColumns; i++) {
        let type = "";

        // If importHeaders[n] isn't empty, then the column's type is known and valid
        // and its contents can be marked as such
        if (importHeaders[i] != "") {
            type = importHeaders[i];
            knownColumns.add(i);
        }

        headerRow.appendChild(buildColumnHeader(i, type));
    }

    // Data rows
    let tbody = table.querySelector("tbody");

    for (let row = 0; row < importRows.length; row++) {
        const columns = importRows[row].columns;

        let tableRow = getTemplate("tableRow");
        let tr = tableRow.querySelector("tr");

        tr.dataset.row = row;
        tableRow.querySelector("span").innerText = row + 1;
        tableRow.querySelector("a").addEventListener("click", onDeleteRow);

        tr.appendChild(create("th", { cls: ["state", "idle"] }));

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

    tbody.addEventListener("mousedown", onMouseDown);
    tbody.addEventListener("dblclick", onMouseDoubleClick);

    let fragment = new DocumentFragment();

    fragment.appendChild(table);

    // Place the table on the page, replacing previous contents, if any
    output.innerHTML = "";
    output.appendChild(fragment);

    const t1 = performance.now();
    console.log(`buildImportTable(): table construction took ${t1 - t0} ms`);
}

function enableUI(state)
{
    for (let i of container.querySelectorAll("button"))
        i.disabled = !state;

    for (let i of container.querySelectorAll("input"))
        i.disabled = !state;

    for (let i of container.querySelectorAll("select"))
        i.disabled = !state;

    for (let i of container.querySelectorAll("textarea"))
        i.disabled = !state;

    // The click handlers check the value of this dataset item
    for (let i of container.querySelectorAll("table#preview a"))
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

function progressBegin()
{
    let elem;

    statistics.totalRowsProcessed = 0;
    statistics.success = 0;
    statistics.partialSuccess = 0;
    statistics.failed = 0;

    elem = container.querySelector("div#status div#progress progress");
    elem.setAttribute("max", workerRows.length);
    elem.setAttribute("value", 0);

    updateStatistics();

    container.querySelector("div#status div#progress").classList.remove("hidden");
}

function progressUpdate()
{
    container.querySelector("div#status div#progress progress").setAttribute("value",
                            statistics.totalRowsProcessed);
    updateStatistics();
}

function progressEnd(success)
{
    //container.querySelector("div#status").classList.add("hidden");
    //container.querySelector("div#status div#progress").classList.add("hidden");

    importActive = false;
    container.querySelector("div#status div#message").innerText = _tr("status.complete");
    updateStatistics();
}

function markRowsAsBeingProcessed(from, to)
{
    const tableRows = container.querySelectorAll("table#preview tbody tr");

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
            const tableRows = container.querySelectorAll("table#preview tbody tr");

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

            // Proceed to the next batch
            progressUpdate();
            markRowsAsBeingProcessed(statistics.totalRowsProcessed, statistics.totalRowsProcessed + BATCH_SIZE);
            IMPORT_WORKER.postMessage({ message: "continue" });
            break;
        }

        case "server_error": {
            // Mark the failed rows
            const failed = container.querySelectorAll("table#preview tbody th.state.processing");

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

    if (!window.confirm(_tr("alerts.are_you_sure")))
        return;

    let status = container.querySelector("div#status"),
        message = container.querySelector("div#status div#message");

    message.innerText = _tr("status.fetching_current_users");
    status.classList.remove("hidden");

    resetSelection();
    enableUI(false);

    // Clear previous states
    for (const row of container.querySelectorAll("table#preview tbody tr th.state")) {
        row.classList.add("idle");
        row.classList.remove("processing", "failed", "partialSuccess", "success");
        row.innerText = "";
    }

    for (const cell of container.querySelectorAll("table#preview tbody td.error")) {
        cell.classList.remove("error");
        cell.title = "";
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
                if (SETTINGS.import.method == 0 || SETTINGS.import.method == 2) {
                    workerRows.push([row, existingUIDs.get(uid)].concat(importRows[row].columns));
                    numUpdate++;
                }
            } else {
                if (SETTINGS.import.method == 0 || SETTINGS.import.method == 1) {
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

        progressBegin();
        markRowsAsBeingProcessed(0, BATCH_SIZE);

        // Now we know what to do, so launch a worker thread that does the sync
        // stuff in the background
        message.innerText = _tr("status.synchronising");

        IMPORT_WORKER.postMessage({
            message: "start",
            school: SCHOOL_ID,
            csrf: document.querySelector("meta[name='csrf-token']").content,
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

function getDuplicates()
{
    const uidCol = findColumn("uid");

    if (uidCol === -1) {
        window.alert(_tr("problems.required_column_missing", { title: COLUMN_TITLES["uid"] }));
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

function getPasswords()
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

        if (password === null || password.length < 3) {
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

    if (missing > 0) {
        if (!window.confirm(_tr("alerts.empty_rows_skipped")))
            return;
    }

    let filename = null,
        failed = false,
        error = null;

    container.querySelector("button#getPasswords").disabled = true;

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

        //for (const [k, v] of response.headers.entries())
        //    console.log(`${k} = |${v}|`);

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
        const match = CONTENT_DISPOSITION.exec(response.headers.get("Content-Disposition"));

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
        container.querySelector("button#getPasswords").disabled = false;
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

function showCurrentTab()
{
    if (SETTINGS.parser.tab == 1) {
        container.querySelector("div#source button#upload").classList.add("selected");
        container.querySelector("div#source button#manual").classList.remove("selected");
        container.querySelector("div#source div.content div#manual").classList.add("hidden");
        container.querySelector("div#source div.content div#upload").classList.remove("hidden");
    } else {
        container.querySelector("div#source button#upload").classList.remove("selected");
        container.querySelector("div#source button#manual").classList.add("selected");
        container.querySelector("div#source div.content div#manual").classList.remove("hidden");
        container.querySelector("div#source div.content div#upload").classList.add("hidden");
    }
}

function onChangeTab(newTab)
{
    if (newTab == SETTINGS.parser.tab)
        return;

    SETTINGS.parser.tab = newTab;
    saveSettings();

    showCurrentTab();
}

function initializeImporter(params)
{
    try {
        container = params.container;

        COLUMN_TITLES = params.columnTitles;
        GROUP_TYPES = params.groupTypes;
        automaticEmails = params.automaticEmails || false;
        commonPasswords = params.commonPasswords || commonPasswords;

        loadSettings();

        // Restore parser settings (individual popup settings are restored when the popup is opened)
        container.querySelector("div#source button#manual").addEventListener("click", () => onChangeTab(0));
        container.querySelector("div#source button#upload").addEventListener("click", () => onChangeTab(1));
        showCurrentTab();

        container.querySelector("details#settings input#inferTypes").checked = SETTINGS.parser.infer;
        container.querySelector("details#settings input#trimValues").checked = SETTINGS.parser.trim;

        if (SETTINGS.parser.separator == 1)
            container.querySelector("details#settings input#semicolon").checked = true;
        else if (SETTINGS.parser.separator == 2)
            container.querySelector("details#settings input#tab").checked = true;
        else container.querySelector("details#settings input#comma").checked = true;

        container.querySelector(`select#method`).value = SETTINGS.import.method;

        // Setup event handling
        container.querySelector("details#settings input#inferTypes")
            .addEventListener("click", e => { SETTINGS.parser.infer = e.target.checked; saveSettings(); });

        container.querySelector("details#settings input#trimValues")
            .addEventListener("click", e => { SETTINGS.parser.trim = e.target.checked; saveSettings(); });

        container.querySelector("details#settings input#comma")
            .addEventListener("click", e => { SETTINGS.parser.separator = 0; saveSettings(); });

        container.querySelector("details#settings input#semicolon")
            .addEventListener("click", e => { SETTINGS.parser.separator = 1; saveSettings(); });

        container.querySelector("details#settings input#tab")
            .addEventListener("click", e => { SETTINGS.parser.separator = 2; saveSettings(); });

        for (let i of container.querySelectorAll("details#settings input"))
            i.addEventListener("click", updateParsingSummary);

        container.querySelector("input#fileUpload").addEventListener("change", onFileUploaded);

        container.querySelector("button#parseCSV").addEventListener("click", beginCSVParse);

        container.querySelector(`select#method`).addEventListener("change", e => {
            SETTINGS.import.method = parseInt(e.target.value, 10);
            saveSettings();
            detectProblems();
        });

        container.querySelector("button#beginImport").
            addEventListener("click", () => beginImport(false));

        container.querySelector("button#retryFailed").
            addEventListener("click", () => beginImport(true));

        container.querySelector("button#getDuplicates").addEventListener("click", getDuplicates);

        container.querySelector("button#getPasswords").addEventListener("click", getPasswords);

        container.querySelector("button#export").addEventListener("click", () => exportData());

        container.querySelector("button#deleteAll").addEventListener("click", onDeleteAll);

        document.body.addEventListener("click", e => {
            // Close any popups that might be active
            if (popup && e.target == popup.backdrop)
                closePopup();
        });

        // TODO: Fix popup repositioning during scroll
        //document.addEventListener("scroll", function(e) { ensurePopupIsVisible(); });

        // Prepare data
        SCHOOL_ID = params.schoolId;

        if ("groups" in params) {
            SCHOOL_GROUPS = [...params.groups];
            sortGroups();
        }

        updateParsingSummary();
    } catch (e) {
        console.error(e);
        window.alert("User importer initialization failed. Please see the browser console for technical " +
                     "details, then contact Opinsys Oy for assistance.");
    }
}
