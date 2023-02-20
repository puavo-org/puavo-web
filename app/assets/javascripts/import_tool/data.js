import { RowFlag, RowState, CellFlag } from "./constants.js";

export class ImportData {
    constructor()
    {
        // Header column types (see the COLUMN_TYPES table, null if the column is skipped/unknown).
        // This MUST have the same number of elements as there are data columns in the table!
        this.headers = [];

        // Tabular data parsed from the file/direct input. Each row is an object containing three
        // members: rowNumber, state, and columns. 'rowNumber' contains the original row number in
        // the CSV file; 'state' contains state flags for that row; 'columns' is the array of
        // the actual column values (there are as many columns as there are entries in the
        // "headers" array).
        this.rows = [];

        // As above, but for the small live preview table. Only the first 5 rows (can be changed
        // in csv_parser.js).
        this.previewHeaders = [];
        this.previewRows = [];

        // Known problems and warnings in the import data. See detectProblems() for details.
        this.errors = [];
        this.warnings = [];

        // Current organisation and school data
        this.currentOrganisationName = null;
        this.currentSchoolName = null;
        this.currentSchoolID = -1;

        // Name of the current user (currently used only when creating username lists)
        this.currentUserName = null;

        // True if the current user can create new users
        this.permitUserCreation = false;

        // Current groups in the target school. Can be specified in the importer initializer, and
        // optionally updated dynamically without reloading the page.
        this.currentGroups = [];

        // User data fetched from the server. Used to check for duplicate
        this.serverUsers = {
            uid: new Map(),
            eid: new Map(),
            email: new Map(),
            phone: new Map()
        };
    }

    // Returns the indx of the specified column in the table, or -1 if it can't be found
    findColumn(id)
    {
        for (let i = 0; i < this.headers.length; i++)
            if (this.headers[i] === id)
                return i;

        return -1;
    }

    // Counts how many times this type of column appears in the headers. Multiple columns
    // of the same type are errors.
    countColumnsByType(id)
    {
        let count = 0;

        for (let i = 0; i < this.headers.length; i++)
            if (this.headers[i] === id)
                count++;

        return count;
    }

    // Sets the new groups. The groups are sorted in alphabetical order automatically.
    setGroups(groups)
    {
        this.currentGroups = [...groups].sort((a, b) => {
            return a["name"].localeCompare(b["name"])
        });
    }

    countSelectedRows()
    {
        let count = 0;

        for (const row of this.rows)
            if (row.rowFlags & RowFlag.SELECTED)
                count++;

        return count;
    }
}
