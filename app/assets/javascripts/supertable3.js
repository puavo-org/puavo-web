"use strict";

/*
SuperTable 3: The best thing since sliced bread
Version 3.2
*/

// Export unminified names for public use
import { ColumnType, ColumnFlag, SortOrder } from "./supertable3/table/constants.js";

import { MassOperation } from "./supertable3/table/mass_operations.js";

import { escapeHTML } from "./common/utils.js";

import { convertTimestamp } from "./supertable3/table/utils.js";

import { outputAsStandardArray, quotedVector, outputBoolean, outputISO8601Timestamp, convertLDAPTimestampToISO8601String } from "./supertable3/table/data.js";

import { SuperTable, ST_DATE_FORMATTER, ST_TIMESTAMP_FORMATTER } from "./supertable3/table/main.js";

globalThis.ST = {
    ColumnType: ColumnType,
    ColumnFlag: ColumnFlag,
    SortOrder: SortOrder,

    escapeHTML: escapeHTML,
    convertTimestamp: convertTimestamp,

    MassOperation: MassOperation,

    SuperTable: SuperTable,

    dateFormatter: ST_DATE_FORMATTER,
    timestampFormatter: ST_TIMESTAMP_FORMATTER,
    outputAsStandardArray: outputAsStandardArray,
    outputBoolean: outputBoolean,
    quotedVector: quotedVector,
    outputISO8601Timestamp: outputISO8601Timestamp,
    convertLDAPTimestampToISO8601String: convertLDAPTimestampToISO8601String,
};
