/*
====================================================================================================

SortableTable
-------------

Takes over a table and makes its columns sortable. You can specify which columns and what their
types are (string, integer, float). You can also optionally specify the initial sorted column and
the order.

You must use appropriate CSS to actually style the table. This code only changes style class
names, nothing more.

(c) Opinsys Oy 2019-2022

Version history
---------------

    0.1 alpha (2019-03-19)
        * Initial version, garbage but somehow it worked

    0.2 (2019-04-08):
        * Proper HTML support in table cells
        * Does not require every column to be sorted (0.1 supported this, but it was very
          poorly implemented)
        * Better column definitions handling
        * Support external sort keys in TD datasets
        * Use Element.classList to manipulate styles, not Element.className
        * Better sort direction indicators with FontAwesome

    0.2.1 (2019-08-12)
        * Added persistent settings through localStorage

TODO
----

- filtering and highlighting (only show rows that contain/don't contain text "foo")

- multi-level sorting (single-level sorting is good, but the real fun begins when you can have
  2-3 levels of sorting)

- checkboxes for mass processing, must work with filtering/sorting, all/none/invert buttons;
  somehow "save" the currently selected items, if the page is reloaded, they remain selected?

- actually make this also work on mobile devices somehow

====================================================================================================
*/

// Sort orders. Every column the table is not currently sorted by is SORT_ORDER_NONE,
// but the currently sorted column must be either _ASCENDING or _DESCENDING.
const SORT_ORDER_NONE = 0,
      SORT_ORDER_ASCENDING = 1,     // A -> Z, 1 -> 9, etc.
      SORT_ORDER_DESCENDING = 2;    // Z -> A, 9 -> 1, etc.

// Column content types. Affects how comparisons are done.
const COLUMN_TYPE_STRING = 0,
      COLUMN_TYPE_INTEGER = 1,
      COLUMN_TYPE_FLOAT = 2;

// Column flags
const COLUMN_FLAG_HTML = 0x01,          // the elements in this column can contain HTML
      COLUMN_FLAG_DONT_SORT = 0x02;     // only specify type/flags for this column, don't make it sortable

class SortableTable {
    constructor(tableId, columnDefs, sortLocale, storageKey=null, initialColumn=null, initialOrder=null)
    {
        // The target table and its unique ID
        this.table = document.getElementById(tableId);
        this.tableId = tableId;

        // 2D array for the contents of *each* table cell
        this.tableContents = [];

        // Columns, their types and flags and other data
        this.columnDefs = [];

        // Actual TR elements for header and content row, for quick access.
        // We support multiple header rows.
        this.tableContentRowElems = [];

        // localStorage key used to retain this table's sort column and order across
        // page reloads and browser restarts. If null, settings are not saved.
        this.storageKey = storageKey;

        // -----------------------------------------------------------------------------------------
        // Create the columns

        const t0 = performance.now();

        for (var i = 0; i < columnDefs.length; i++) {
            this.columnDefs[i] = {
                // Content type: strings, numbers, etc., affects how sorting is done
                "type": columnDefs[i][0] || COLUMN_TYPE_STRING,

                // Flags (preserve HTML, etc.)
                "flags": columnDefs[i][1] || 0,

                // Initial sorting order for this table column
                "order": SORT_ORDER_NONE,

                // The actual clickable TD elements on header rows for this column that
                // change the sorting. Stored here so we can quickly access them and
                // change the sort direction arrows.
                "headerElements": [],
            };
        }

        // -----------------------------------------------------------------------------------------
        // Gather up the table data

        for (var i = 0; i < this.table.rows.length; i++) {
            var row = this.table.rows[i];

            if (row.children.length == 0)
                continue;

            const nodeName = row.children[0].nodeName;

            if (nodeName == "TH") {
                // This is a header row. Collect the actual TH elements for each defined
                // column.
                for (var j = 0; j < row.children.length; j++) {
                    if (!(j in this.columnDefs))
                        throw "Table column " + colN + " not defined in column definitions!";

                    if (this.columnDefs[j]["flags"] & COLUMN_FLAG_DONT_SORT) {
                        // this column is not sortable
                        continue;
                    }

                    var element = row.children[j];

                    // Make this header element clickable
                    this.columnDefs[j]["headerElements"].push(element);

                    element.dataset.colNum = j;         // determining this later is *HARD*, so keep track of it
                    element.classList.add("sortHeader");
                    element.classList.add("orderNone"); // initially all columns are in unsorted state

                    if (this.columnDefs[j]["type"] == COLUMN_TYPE_STRING)
                        element.classList.add("typeString");
                    else element.classList.add("typeNumeric");

                    element.addEventListener("click", event => this.clickedColumnHeader(event));
                }
            } else if (nodeName == "TD") {
                // This is a content row. Store the textual content for each cell for sorting
                // and table rebuilding.
                var cols = [],
                    sortKey,
                    innerText;

                for (var j = 0; j < row.children.length; j++) {
                    const item = row.children[j];

                    const colType = this.columnDefs[j]["type"],
                          colFlags = this.columnDefs[j]["flags"];

                    if ("sortKey" in item.dataset) {
                        // use a separate sorting key
                        sortKey = item.dataset.sortKey;
                    } else {
                        // might not work properly if the element contains HTML!
                        sortKey = item.innerText;
                    }

                    // pre-parse numeric values
                    switch (colType) {
                        case COLUMN_TYPE_INTEGER:
                            sortKey = parseInt(sortKey, 10);
                            break;

                        case colType == COLUMN_TYPE_FLOAT:
                            sortKey = parseFloat(sortKey);
                            break;

                        default:
                            break;
                    }

                    if (colFlags & COLUMN_FLAG_HTML) {
                        // preserve HTML
                        cols.push([sortKey, item.innerHTML]);
                    } else {
                        // plaintext only
                        cols.push([sortKey, item.innerText]);
                    }
                }

                this.tableContents.push([0, cols]);   // 0 == row flags (currently unused)

                // Store the row element for later quick(er) table access
                this.tableContentRowElems.push(row);
            }
        }

        this.setupSorting(sortLocale, initialColumn, initialOrder);

        const t1 = performance.now();
        console.log(`Table "${this.tableId}" init took ${t1 - t0} ms`);
    }

    loadSortSettings()
    {
        if (this.storageKey == null) {
            console.warn("loadSortSettings(): localstore key not speficied");
            return null;
        }

        const keyName = "sort-" + this.storageKey;

        const settings = localStorage.getItem(keyName);

        if (settings)
            console.log(`loadSortSettings(): have initial settings for "${keyName}": ${settings}`);

        return JSON.parse(settings);
    }

    saveSortSettings(columnNumber, sortOrder)
    {
        if (this.storageKey == null) {
            console.warn("saveSortSettings(): localstore key not speficied");
            return;
        }

        const keyName = "sort-" + this.storageKey;

        console.log(`saveSortSettings(): key="${keyName}" column=${columnNumber} order=${sortOrder}`);

        localStorage.setItem(keyName, JSON.stringify({
            "column": columnNumber,
            "order": sortOrder,
        }));
    }

    // ---------------------------------------------------------------------------------------------
    // SORTING

    setupSorting(sortLocale, initialColumn, initialOrder, storageKey)
    {
        // Set up the collator object that we use to compare two strings
        this.collator = Intl.Collator(
            sortLocale,
            {
                usage: "sort",
                sensitivity: "base",
                ignorePunctuation: true,
                numeric: true,              // this one I like the most
            }
        );

        const savedSettings = this.loadSortSettings();

        if (savedSettings) {
            // Previously saved sort column and order overrides initial settings, if any
            initialColumn = savedSettings["column"];
            initialOrder = savedSettings["order"];
        }

        // Apply initial or saved sorting
        if (initialColumn != null && initialOrder != null &&
            initialColumn >= 0 && initialColumn < this.columnDefs.length) {

            var column = this.columnDefs[initialColumn];

            switch (initialOrder) {
                case SORT_ORDER_ASCENDING:
                default:
                    column["order"] = SORT_ORDER_ASCENDING;
                    this.setHeaderSortClass(column["headerElements"], "orderAscending");
                    this.sortTable(column, initialColumn);
                    break;

                case SORT_ORDER_DESCENDING:
                    column["order"] = SORT_ORDER_DESCENDING;
                    this.setHeaderSortClass(column["headerElements"], "orderDescending");
                    this.sortTable(column, initialColumn);
                    break;
            }
        }
    }

    // Event handler, called when a table header column is clicked
    clickedColumnHeader(event)
    {
        var target = event.target;
        const targetColumn = target.dataset.colNum;

        if (!(targetColumn in this.columnDefs)) {
            console.error("Invalid column index " + targetColumn + ", not sorting anything");
            return;
        }

        for (var i = 0; i < this.columnDefs.length; i++) {
            var column = this.columnDefs[i];

            if (i == targetColumn) {
                // Sort by this column
                switch (column["order"]) {
                    case SORT_ORDER_DESCENDING:
                    default:
                        column["order"] = SORT_ORDER_ASCENDING;
                        this.setHeaderSortClass(column["headerElements"], "orderAscending");
                        this.sortTable(column, i);
                        this.saveSortSettings(i, SORT_ORDER_ASCENDING);
                        break;

                    case SORT_ORDER_ASCENDING:
                        column["order"] = SORT_ORDER_DESCENDING;
                        this.setHeaderSortClass(column["headerElements"], "orderDescending");
                        this.sortTable(column, i);
                        this.saveSortSettings(i, SORT_ORDER_DESCENDING);
                        break;
                }
            } else {
                // Change this column to unsorted
                column["order"] = SORT_ORDER_NONE;
                this.setHeaderSortClass(column["headerElements"], "orderNone");
            }
        }
    }

    // Helper for clickedColumnHeader(), changes the CSS classname of
    // the item, making the sort order arrows work
    setHeaderSortClass(elements, newClass)
    {
        for (var i = 0; i < elements.length; i++) {
            elements[i].classList.remove("orderNone", "orderAscending", "orderDescending");
            elements[i].classList.add(newClass);
        }
    }

    // Actually sorts the table by the specified column
    sortTable(column, colIndex)
    {
        if (column["order"] == SORT_ORDER_NONE) {
            console.error("sortTable(): sort order is SORT_ORDER_NONE, doing nothing");
            return;
        }

        const t0 = performance.now();

        // Sort in ascending order by default
        // Each object is [row flags, [columns]], and each column is [sort key, plaintext/HTML]
        switch (column["type"]) {
            case COLUMN_TYPE_STRING:
            default:
                this.tableContents.sort((a, b) => {
                    return this.collator.compare(a[1][colIndex][0], b[1][colIndex][0]);
                });

            break;

            case COLUMN_TYPE_INTEGER:
                this.tableContents.sort((a, b) => {
                    const i1 = a[1][colIndex][0],
                          i2 = b[1][colIndex][0];

                    if (i1 < i2)
                        return -1;
                    else if (i1 > i2)
                        return 1;

                    return 0;
                });

                break;

            case COLUMN_TYPE_FLOAT:
                this.tableContents.sort((a, b) => {
                    const i1 = a[1][colIndex][0],
                          i2 = b[1][colIndex][0];

                    if (i1 < i2)
                        return -1;
                    else if (i1 > i2)
                        return 1;

                    return 0;
                });

                break;
        }

        // Descending order if desired
        if (column["order"] == SORT_ORDER_DESCENDING)
            this.tableContents.reverse();

        const t1 = performance.now();

        // Replace the old contents
        for (var i = 0; i < this.tableContentRowElems.length; i++) {
            var row = this.tableContentRowElems[i];

            const newRow = this.tableContents[i][1];

            for (var j = 0; j < newRow.length; j++) {
                if (this.columnDefs[j]["flags"] & COLUMN_FLAG_HTML)
                    row.children[j].innerHTML = newRow[j][1];
                else row.children[j].innerText = newRow[j][1];

                // highlight the sorted column
                if (j == colIndex)
                    row.children[j].classList.add("selectedColumn");
                else row.children[j].classList.remove("selectedColumn");
            }
        }

        const t2 = performance.now();
        console.log(`sortTable(): table "${this.tableId}" sorting took ${t1 - t0} ms and rebuilding took ${t2 - t1} ms`);
    }
};
