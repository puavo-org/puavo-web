"use strict";

/*
SuperTable 3: The best thing since sliced bread
Version 3.0 alpha

This is functionally identical to SuperTable v2.6.7; the only
difference is that it has been modularized and the UI has been
reworked thoroughly. But other major changes will follow.
*/

// Export unminified names for public use
import {
    TableFlag,
    ColumnType,
    ColumnFlag,
    SortOrder,
    INDEX_EXISTS, INDEX_DISPLAYABLE, INDEX_FILTERABLE, INDEX_SORTABLE
} from "./supertable3/table/constants.js";

import {
    MassOperationFlags,
    MassOperation,
    doPOST,
    itemProcessedStatus,
} from "./supertable3/table/mass_operations.js";

import {
    escapeHTML,
} from "./common/utils.js";

import {
    convertTimestamp,
} from "./supertable3/table/utils.js";

import { SuperTable } from "./supertable3/table/main.js";

globalThis.ST = {
    TableFlag: TableFlag,
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
    MassOperationFlags: MassOperationFlags,
    doPOST: doPOST,
    itemProcessedStatus: itemProcessedStatus,

    SuperTable: SuperTable,
};
