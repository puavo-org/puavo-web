"use strict";

/*
SuperTable 3: The best thing since sliced bread
Version 3.1.2
*/

// Export unminified names for public use
import {
    ColumnType,
    ColumnFlag,
    SortOrder,
    INDEX_EXISTS, INDEX_DISPLAYABLE, INDEX_FILTERABLE, INDEX_SORTABLE
} from "./supertable3/table/constants.js";

import { MassOperation } from "./supertable3/table/mass_operations.js";

import { escapeHTML } from "./common/utils.js";

import { convertTimestamp } from "./supertable3/table/utils.js";

import { SuperTable, ST_DATE_FORMATTER, ST_TIMESTAMP_FORMATTER } from "./supertable3/table/main.js";

globalThis.ST = {
    ColumnType: ColumnType,
    ColumnFlag: ColumnFlag,
    SortOrder: SortOrder,
    INDEX_EXISTS: INDEX_EXISTS,
    INDEX_DISPLAYABLE: INDEX_DISPLAYABLE,
    INDEX_FILTERABLE: INDEX_FILTERABLE,
    INDEX_SORTABLE: INDEX_SORTABLE,

    escapeHTML: escapeHTML,
    convertTimestamp: convertTimestamp,

    MassOperation: MassOperation,

    SuperTable: SuperTable,

    dateFormatter: ST_DATE_FORMATTER,
    timestampFormatter: ST_TIMESTAMP_FORMATTER
};
