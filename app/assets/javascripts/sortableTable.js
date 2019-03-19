// Extremely barebones table sorter. Takes over a table and makes its
// columns sortable. You can specify which columns and what their types
// are (string, integer, float). You can also optionally specify the
// initial sorted column and the order.

// Sort orders. Unsorted columns are "SORT_ORDER_NONE".
const SORT_ORDER_NONE = 0,
      SORT_ORDER_ASCENDING = 1,
      SORT_ORDER_DESCENDING = 2;

// Column content types
const COLUMN_TYPE_STRING = 0,
      COLUMN_TYPE_INTEGER = 1,
      COLUMN_TYPE_FLOAT = 2;

// If set, this column can contain HTML content that must be
// preserved when sorting. If not set, the column contents are
// assumed to be plain text.
const COLUMN_FLAG_PRESERVE_HTML = 0x01;

class SortableTable {
  constructor(tableId, columns, locale, initialColumn=null, initialOrder=null)
  {
    // The target table and its unique ID
    this.table = document.getElementById(tableId);
    this.tableId = tableId;

    // 2D array for the contents of *each* table cell
    this.tableContents = [];

    // Sortable columns, their types and flags
    this.headerColumns = [];

    // Actual TR elements for header and content row, for quick access.
    // We support multiple header rows.
    //this.tableHeaderRowElems = [];
    this.tableContentRowElems = [];

    // =========================================================================
    // Create the sortable columns

    const t0 = performance.now();

    for (var i = 0; i < columns.length; i++) {
      const number = columns[i]["index"],
            type = columns[i]["type"] || COLUMN_TYPE_STRING,
            flags = columns[i]["flags"] || 0;

      //console.log(`Table ${this.tableId}, column ${i}: number=${number} type=${type} flags=${flags}`);

      this.headerColumns[number] = {
        // Which column in the table gets sorted when this header column
        // is clicked?
        "number": number,

        // Content type: strings, numbers, etc., affects how sorting is done
        "type": type,

        // Flags
        "flags": flags,

        // Initial sorting order for this table column
        "order": SORT_ORDER_NONE,

        // The actual clickable TD elements on header rows for this column that
        // change the sorting. Stored here so we can quickly access them and
        // change the sort direction arrows.
        "elements": [],
      };
    }

    // =========================================================================
    // Gather up the table data

    for (var rowN = 0; rowN < this.table.rows.length; rowN++) {
      var row = this.table.rows[rowN];

      if (row.children.length == 0)
        continue;

      const nodeName = row.children[0].nodeName;

      if (nodeName == "TH") {
        // Collect the actual TH elements from each header row
        for (var colN = 0; colN < columns.length; colN++) {
          const index = columns[colN]["index"];

          if (index < 0 || index > row.children.length - 1) {
            throw "Invalid column index " + index + ", there are only " +
                  row.children.length + " columns!";
          }

          var element = row.children[index];

          // Store the column header element
          this.headerColumns[index]["elements"].push(element);

          // Make this header element clickable
          element.dataset.colNum = index;   // determining this later is *HARD*, so keep track of it
          element.className = "orderNone";  // initially all columns are in unsorted state
          element.addEventListener("click", event => this.clickedColumnHeader(event));
        }

        //this.tableHeaderRowElems.push(row);
      } else if (nodeName == "TD") {
        // Store the textual content for each cell so we can sort them
        var cols = [];

        for (var i = 0; i < row.children.length; i++) {
          if (i in this.headerColumns &&
              this.headerColumns[i]["flags"] & COLUMN_FLAG_PRESERVE_HTML) {
            // this cell can have HTML that must be preserved
            cols.push(
              [row.children[i].innerText,       // used for sorting
               row.children[i].innerHTML]);     // used for displaying
          } else {
            // no HTML in this cell (or this column is not sortable), this one
            // element is used for sorting and displaying
            cols.push([row.children[i].innerText]);
          }
        }

        this.tableContents.push([0, cols]);   // 0 == row flags

        // Store the row element for later quick(er) table access
        this.tableContentRowElems.push(row);
      }
    }

    this.setupSorting(locale, initialColumn, initialOrder);

    const t1 = performance.now();
    console.log(`SortableTable::ctor(): table "${this.tableId}" init took ${t1 - t0} ms`);
  }

  // ===========================================================================
  // SORTING

  setupSorting(locale, initialColumn, initialOrder)
  {
    // Set up the collator object that we use to compare two strings
    this.collator = Intl.Collator(
      locale,
      {
        usage: "sort",
        sensitivity: "base",
        ignorePunctuation: true,
        numeric: true,              // this one I like the most
      }
    );

    // Initial sort, if specified
    if (initialColumn != null && initialOrder != null) {
      if (initialColumn in this.headerColumns) {
        var column = this.headerColumns[initialColumn];

        switch (initialOrder) {
          case SORT_ORDER_ASCENDING:
          default:
            column["order"] = SORT_ORDER_ASCENDING;
            this.setHeaderSortClass(column["elements"], "orderAscending");
            this.sortTable(column);
            break;

          case SORT_ORDER_DESCENDING:
            column["order"] = SORT_ORDER_DESCENDING;
            this.setHeaderSortClass(column["elements"], "orderDescending");
            this.sortTable(column);
            break;
        }
      }
    }
  }

  // Event handler, called when a table header column is clicked
  clickedColumnHeader(event)
  {
    var target = event.target;
    const colNum = target.dataset.colNum;

    if (!(colNum in this.headerColumns)) {
      console.error("Invalid column index " + colNum + ", not sorting anything");
      return;
    }

    // ...okay then, JavaScript, whatever you say
    const columnNumbers = Object.keys(this.headerColumns);

    for (var i = 0; i < columnNumbers.length; i++) {
      var column = this.headerColumns[columnNumbers[i]];

      if (columnNumbers[i] == colNum) {
        // Sort by this column
        switch (column["order"]) {
          case SORT_ORDER_DESCENDING:
          default:
            column["order"] = SORT_ORDER_ASCENDING;
            this.setHeaderSortClass(column["elements"], "orderAscending");
            this.sortTable(column);
            break;

          case SORT_ORDER_ASCENDING:
            column["order"] = SORT_ORDER_DESCENDING;
            this.setHeaderSortClass(column["elements"], "orderDescending");
            this.sortTable(column);
        }
      } else {
        // Change this column to unsorted
        column["order"] = SORT_ORDER_NONE;
        this.setHeaderSortClass(column["elements"], "orderNone");
      }
    }
  }

  // Helper for clickedColumnHeader(), changes the CSS classname of
  // the item, making the sort order arrows work
  setHeaderSortClass(elements, newClass)
  {
    for (var i = 0; i < elements.length; i++)
      elements[i].className = newClass;
  }

  // Actually sorts the table by the specified column
  sortTable(column)
  {
    if (column["order"] == SORT_ORDER_NONE) {
      console.error("sortTable(): sort order is SORT_ORDER_NONE, doing nothing");
      return;
    }

    const columnNum = column["number"];

    const t0 = performance.now();

    // Sort in ascending order
    switch (column["type"]) {
      case COLUMN_TYPE_STRING:
      default:
        this.tableContents.sort((a, b) => {
          return this.collator.compare(a[1][columnNum][0], b[1][columnNum][0]);
        });

        break;

      case COLUMN_TYPE_INTEGER:
        this.tableContents.sort((a, b) => {
          const i1 = parseInt(a[1][columnNum][0], 10),
                i2 = parseInt(b[1][columnNum][0], 10);

          if (i1 < i2)
            return -1;
          else if (i1 > i2)
            return 1;
          return 0;
        });

        break;

      case COLUMN_TYPE_FLOAT:
        this.tableContents.sort((a, b) => {
          const i1 = parseFloat(a[1][columnNum][0]),
                i2 = parseFloat(b[1][columnNum][0]);

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
        if (j in this.headerColumns &&
            this.headerColumns[j]["flags"] & COLUMN_FLAG_PRESERVE_HTML) {
          // copy HTML
          row.children[j].innerHTML = newRow[j][1];
        } else {
          // copy plain text
          row.children[j].innerText = newRow[j][0];
        }
      }
    }

    const t2 = performance.now();
    console.log(`SortableTable::sortTable(): table "${this.tableId}" sorting took ${t1 - t0} ms and rebuilding took ${t2 - t1} ms`);
  }
};
