import {
    REQUIRED_COLUMNS_NEW,
    USERNAME_REGEXP,
    EMAIL_REGEXP,
    PHONE_REGEXP,
    NUM_ROW_HEADERS,
    VALID_ROLES,
    CellFlag,
    RowFlag,
 } from "./constants.js";

import { _tr } from "../common/utils.js";
import { create, getTemplate } from "../common/dom.js";

// How many entries to list when listing invalid entries (usernames, external IDs, etc.).
// Don't set this too high, or the resulting list can break the layout.
const FIRST_N = 10;

// Try to detect problems and potential errors/warnings in the table data
export function doDetectProblems(data, container, commonPasswords, automaticEmails, selectRows, updateOnly)
{
    const firstCol = data.findColumn("first"),
          lastCol = data.findColumn("last"),
          uidCol = data.findColumn("uid"),
          roleCol = data.findColumn("role"),
          eidCol = data.findColumn("eid"),
          emailCol = data.findColumn("email"),
          phoneCol = data.findColumn("phone"),
          passwordCol = data.findColumn("password");

    const tableRows = container.querySelectorAll("div#output table tbody tr");

    data.errors = [];
    data.warnings = [];

    // ----------------------------------------------------------------------------------------------
    // Make sure required columns are present and there are no duplicates

    let counts = {};

    // Check for duplicate columns
    for (const header of data.headers) {
        if (header === null || header === undefined || header == "")
            continue;

        if (header in counts)
            counts[header]++;
        else counts[header] = 1;
    }

    for (const columnID of Object.keys(counts))
        if (counts[columnID] > 1)
            data.errors.push(`${_tr("errors.multiple_columns", { title: _tr("columns." + columnID) })}`);

    if (updateOnly) {
        // In update-only mode, you need the username column, but everything else is optional
        if (uidCol === -1)
            data.errors.push(_tr("errors.need_uid_column_in_update_mode"));

        let numNonUIDCols = 0;

        for (const i of data.headers)
            if (i !== "uid" && i !== "")
                numNonUIDCols++;

        if (numNonUIDCols < 1)
            data.errors.push(_tr("errors.need_something_to_update_in_update_mode"));

        if (roleCol !== -1)
            data.warnings.push(_tr("errors.no_role_mass_change"));
    } else {
        // Check for missing required columns
        for (const columnID of REQUIRED_COLUMNS_NEW)
            if (!(columnID in counts))
                data.errors.push(`${_tr("errors.required_column_missing", { title: _tr("columns." + columnID) })}`);

        // These columns are not required, but they can cause unwanted behavior, especially if you're
        // importing new users
        if (data.findColumn("group") === -1)
            data.warnings.push(_tr("errors.no_group_column"));

        if (data.findColumn("password") === -1)
            data.warnings.push(_tr("errors.no_password_column"));
    }

    // ----------------------------------------------------------------------------------------------
    // Ensure the required columns have proper values and that there are no duplicates.
    // This will produce invalid results if there are duplicate columns.

    const checkboxes = container.querySelectorAll(`div#output table tbody tr input[type="checkbox"]`);

    if (selectRows) {
        for (const cb of checkboxes)
            cb.checked = false;
    }

    // A common wrapper for all validation code. Iterates over every 'index' cell on every row,
    // and calls the callback function on it. If the callback returns false, the cell is assumed
    // to contain an invalid value and it is flagged as such.
    const validateCells = (index, callback) => {
        for (let rowNum = 0; rowNum < data.rows.length; rowNum++) {
            const row = data.rows[rowNum],
                  cell = tableRows[rowNum].children[NUM_ROW_HEADERS + index];

/*
            if (process.checkOnlySelectedRows && !selectRows) {
                // Only check selected already-selected rows
                if (!checkboxes[rowNum].checked)
                    continue;
            }
*/

            let markRow = false;

            if (callback(row.cellValues[index], cell, rowNum, index)) {
                row.cellFlags[index] &= ~CellFlag.INVALID;
                cell.classList.remove("error");
            } else {
                row.cellFlags[index] |= CellFlag.INVALID;
                cell.classList.add("error");
                markRow = true;
            }

            if (selectRows) {
                if (markRow) {
                    checkboxes[rowNum].checked = true;
                    row.rowFlags |= RowFlag.SELECTED;
                } else row.rowFlags &= ~RowFlag.SELECTED;
            }
        }
    };

    const isEmpty = (v) => v === null || v.trim().length == 0;

    // Checks if *someone else* has this specific entry on the duplicate data
    // we get from the server.
    const existsInServer = (key, dataset, row, column) => {
        if (column === -1)
            return false;

        if (!data.serverUsers[dataset].has(key))
            return false;

        return data.serverUsers[dataset].get(key) !==
               data.rows[row].cellValues[column].trim();
    };

    // Validate first names
    if (firstCol !== -1) {
        let numEmpty = 0;

        validateCells(firstCol, (value, cell) => {
            if (isEmpty(value)) {
                numEmpty++;
                return false;
            }

            return true;
        });

        if (numEmpty > 0)
            data.errors.push(_tr('errors.empty_first', { count: numEmpty }));
    }

    // Validate last names
    if (lastCol !== -1) {
        let numEmpty = 0;

        validateCells(lastCol, (value, cell) => {
            if (isEmpty(value)) {
                numEmpty++;
                return false;
            }

            return true;
        });

        if (numEmpty > 0)
            data.errors.push(_tr('errors.empty_last', { count: numEmpty }));
    }

    // Validate usernames
    if (uidCol !== -1) {
        let numEmpty = 0,
            numDuplicate = 0,
            numShort = 0,
            numInvalid = 0;

        const usernames = new Set();
        let invalid = [],
            short = [],
            duplicate = [];

        validateCells(uidCol, (value, cell) => {
            if (isEmpty(value)) {
                numEmpty++;
                return false;
            }

            const u = value.trim();

            if (usernames.has(u)) {
                numDuplicate++;
                duplicate.push(u);
                return false;
            }

            if (u.length < 3) {
                numShort++;
                short.push(u);
                return false;
            }

            if (!USERNAME_REGEXP.test(u)) {
                numInvalid++;
                invalid.push(u);
                return false;
            }

            usernames.add(u);

            return true;
        });

        invalid = invalid.slice(0, FIRST_N);
        short = short.slice(0, FIRST_N);
        duplicate = duplicate.slice(0, FIRST_N);

        if (numEmpty > 0)
            data.errors.push(_tr('errors.empty_uid', { count: numEmpty }));

        if (numDuplicate > 0) {
            data.errors.push(_tr('errors.duplicate_uid', {
                count: numDuplicate,
                first_n: FIRST_N,
                values: duplicate.join(", ")
            }));
        }

        if (numShort > 0) {
            data.errors.push(_tr('errors.short_uid', {
                count: numShort,
                first_n: FIRST_N,
                values: short.join(", ")
            }));
        }

        if (numInvalid > 0) {
            data.errors.push(_tr('errors.invalid_uid', {
                count: numInvalid,
                first_n: FIRST_N,
                values: invalid.join(", ")
            }));
        }
    }

    // Roles
    if (roleCol !== -1) {
        let numInvalid = 0;

        validateCells(roleCol, (value, cell) => {
            if (value === null || !VALID_ROLES.has(value.trim())) {
                numInvalid++;
                return false;
            }

            return true;
        });

        if (numInvalid > 0)
            data.errors.push(_tr('errors.missing_role', { count: numInvalid }));
    }

    // External IDs
    if (eidCol !== -1) {
        let numDuplicate = 0,
            numUsed = 0;

        const eid = new Set();
        let duplicate = [],
            used = [];

        validateCells(eidCol, (value, cell, rowNum) => {
            if (isEmpty(value))
                return true;

            const e = value.trim();

            if (eid.has(e)) {
                numDuplicate++;
                duplicate.push(e);
                return false;
            }

            if (existsInServer(e, "eid", rowNum, uidCol)) {
                numUsed++;
                used.push(e);
                return false;
            }

            eid.add(value.trim());

            return true;
        });

        duplicate = duplicate.slice(0, FIRST_N);
        used = used.slice(0, FIRST_N);

        if (numDuplicate > 0) {
            data.errors.push(_tr('errors.duplicate_eid', {
                count: numDuplicate,
                first_n: FIRST_N,
                values: duplicate.join(", ")
            }));
        }

        if (numUsed > 0) {
            data.errors.push(_tr('errors.eid_already_in_use', {
                count: numUsed,
                first_n: FIRST_N,
                values: used.join(", ")
            }));
        }
    }

    // Email addresses
    if (emailCol !== -1) {
        if (automaticEmails) {
            // We could simply ignore the column, but since the error reporting mechanism
            // exists and works, use it to enfore this.
            data.errors.push(_tr("errors.automatic_emails"));
        } else {
            let numDuplicate = 0,
                numUsed = 0,
                numInvalid = 0;

            const seen = new Set();
            let duplicate = [],
                invalid = [],
                used = [];

            validateCells(emailCol, (value, cell, rowNum) => {
                if (isEmpty(value))
                    return true;

                const e = value.trim();

                if (seen.has(e)) {
                    numDuplicate++;
                    duplicate.push(e);
                    return false;
                }

                if (!EMAIL_REGEXP.test(e)) {
                    numInvalid++;
                    invalid.push(e);
                    return false;
                }

                if (existsInServer(e, "email", rowNum, uidCol)) {
                    numUsed++;
                    used.push(e);
                    return false;
                }

                seen.add(value);
                return true;
            });

            duplicate = duplicate.slice(0, FIRST_N);
            used = used.slice(0, FIRST_N);
            invalid = invalid.slice(0, FIRST_N);

            if (numDuplicate > 0) {
                data.errors.push(_tr('errors.duplicate_email', {
                    count: numDuplicate,
                    first_n: FIRST_N,
                    values: duplicate.join(", ")
                }));
            }

            if (numUsed > 0) {
                data.errors.push(_tr('errors.email_already_in_use', {
                    count: numUsed,
                    first_n: FIRST_N,
                    values: used.join(", ")
                }));
            }

            if (numInvalid > 0) {
                data.errors.push(_tr('errors.invalid_email', {
                    count: numInvalid,
                    first_n: FIRST_N,
                    values: invalid.join(", ")
                }));
            }
        }
    }

    // Telephone numbers
    if (phoneCol !== -1) {
        let numDuplicate = 0,
            numUsed = 0,
            numInvalid = 0;

        const seen = new Set();
        let duplicate = [],
            invalid = [],
            used = [];

        validateCells(phoneCol, (value, cell, rowNum) => {
            if (isEmpty(value))
                return true;

            const p = value.trim();

            if (seen.has(p)) {
                numDuplicate++;
                duplicate.push(p);
                return false;
            }

            if (existsInServer(p, "phone", rowNum, uidCol)) {
                numUsed++;
                used.push(p);
                return false;
            }

            // For some reason, LDAP really does not like if the telephone attribute is
            // just a "-". And when I say "does not like", I mean "it completely crashes".
            // We found out that in the hard way.
            if (p == "-" || !PHONE_REGEXP.test(p)) {
                numInvalid++;
                invalid.push(p);
                return false;
            }

            seen.add(value);
            return true;
        });

        duplicate = duplicate.slice(0, FIRST_N);
        used = used.slice(0, FIRST_N);
        invalid = invalid.slice(0, FIRST_N);

        if (numDuplicate > 0) {
            data.errors.push(_tr('errors.duplicate_phone', {
                count: numDuplicate,
                first_n: FIRST_N,
                values: duplicate.join(", ")
            }));
        }

        if (numUsed > 0) {
            data.errors.push(_tr('errors.phone_already_in_use', {
                count: numUsed,
                first_n: FIRST_N,
                values: used.join(", ")
            }));
        }

        if (numInvalid > 0) {
            data.errors.push(_tr('errors.invalid_phone', {
                count: numInvalid,
                first_n: FIRST_N,
                values: invalid.join(", ")
            }));
        }
    }

    // Passwords
    if (passwordCol !== -1) {
        let numCommon = 0;

        validateCells(passwordCol, (value, cell) => {
            if (isEmpty(value) || commonPasswords.indexOf(`\t${value}\t`) == -1)
                return true;

            numCommon++;
            return false;
        });

        if (numCommon > 0)
            data.errors.push(_tr('errors.common_password', { count: numCommon }));
    }

    // ----------------------------------------------------------------------------------------------
    // Generate a list of errors and warnings

    let output = container.querySelector("div#problems");

    output.innerHTML = "";

    if (data.errors.length > 0) {
        const tmpl = getTemplate("errors");
        const list = tmpl.querySelector("ul");

        for (const i of data.errors)
            list.appendChild(create("li", { text: i }));

        output.appendChild(tmpl);
    }

    if (data.warnings.length > 0) {
        const tmpl = getTemplate("warnings");
        const list = tmpl.querySelector("ul");

        for (const i of data.warnings)
            list.appendChild(create("li", { text: i }));

        output.appendChild(tmpl);
    }
}
