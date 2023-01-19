// Main table flags
export const TableFlag = {
    // Allow user to change and reorder the visible columns
    ENABLE_COLUMN_EDITING: 0x01,

    // Allow user to filter the table contents
    ENABLE_FILTERING: 0x02,

    // Allow user to select one or more table rows and apply mass operations to them
    ENABLE_SELECTION: 0x04,

    // Enable pagination (if disabled, all rows are always displayed)
    ENABLE_PAGINATION: 0x08,

    // Disables CSV export (enabled by default)
    DISABLE_EXPORT: 0x10,

    // Disables JSON/URL view saving (enabled by default)
    DISABLE_VIEW_SAVING: 0x20,

    // Completely hide the "Tools" tab
    DISABLE_TOOLS: 0x40,
};

// Column flags
export const ColumnFlag = {
    // This column can NOT be sorted. All columns are sortable by default, but you can use this
    // flag to invert that
    NOT_SORTABLE: 0x01,

    // The column values are actually arrays of zero or more values instead of just one
    // Only works with strings!
    ARRAY: 0x02,

    // Call a user-defined callback function to get the actual displayable value
    USER_TRANSFORM: 0x04,

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
