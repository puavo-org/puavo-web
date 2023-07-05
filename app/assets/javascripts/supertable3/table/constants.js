// Column flags
export const ColumnFlag = {
    // This column can NOT be sorted. All columns are sortable by default, but you can use this
    // flag to invert that
    NOT_SORTABLE: 0x01,

    // The column values are actually arrays of zero or more values instead of just one
    // Only works with strings!
    ARRAY: 0x02,

    // Add a custom CSS class name to the column TD (specify it with "cssClass" value)
    CUSTOM_CSS: 0x08,

    // Normally, when a column header is clicked, it is sorted in ascending order. By setting
    // this flag, you make the descending order the default for that column. Some columns
    // contain values (like RAM size) that make more sense when sorted that way by default.
    DESCENDING_DEFAULT: 0x10,

    // ----------------------------------------------------------------------------------------------
    // Filter parser flags

    // Expand B/K/M/G/T size specifiers when parsing the filter. Useful with hard disk and
    // RAM sizes.
    F_STORAGE: 0x20,

    // This column can be NULL, ie. the !! operator is useful here. Used only in the Filter
    // Editor to display warnings about useless !! comparisons.
    F_NULLABLE: 0x40,
};

// Column data types. Affects filtering and sorting.
export const ColumnType = {
    BOOL: 1,
    NUMERIC: 2,     // int/float
    UNIXTIME: 3,    // internally an integer, but displayed as (24-hour) YYYY-MM-DD HH:MM:SS
    STRING: 4,
};

// Column sort ordering
export const SortOrder = {
    NONE: "none",
    ASCENDING: "asc",
    DESCENDING: "desc"
};

// After the data has been transformed, each row column is made up of multiple elements.
// These are the indexes to those elements. NEVER use plain numbers, always use these!
export const
    INDEX_EXISTS = 0,
    INDEX_DISPLAYABLE = 1,
    INDEX_FILTERABLE = 2,
    INDEX_SORTABLE = 3;

// Pagination counts. Each entry is formatted as [row count, title]. -1 displays all rows.
export const ROWS_PER_PAGE_PRESETS = [
    [-1, "∞"],
    [5, "5"],
    [10, "10"],
    [20, "20"],
    [25, "25"],
    [50, "50"],
    [100, "100"],
    [200, "200"],
    [250, "250"],
    [500, "500"],
    [1000, "1000"],
    [2000, "2000"],
    [2500, "2500"],
    [5000, "5000"],
];

// How many rows are displayed by default
export const DEFAULT_ROWS_PER_PAGE = 100;
