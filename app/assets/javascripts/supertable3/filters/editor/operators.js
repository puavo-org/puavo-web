// All known operators and which column types they can be used with

import { ColumnType } from "../../table/constants.js";

export const OPERATORS = {
    "=": {
        allowed: new Set([ColumnType.BOOL, ColumnType.NUMERIC, ColumnType.UNIXTIME, ColumnType.STRING]),
        multiple: true,
    },

    "!=": {
        allowed: new Set([ColumnType.BOOL, ColumnType.NUMERIC, ColumnType.UNIXTIME, ColumnType.STRING]),
        multiple: true,
    },

    "<": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    "<=": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    ">": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    ">=": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: false,
    },

    // interval (closed)
    "[]": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: true,
    },

    // reverse interval (closed)
    "![]": {
        allowed: new Set([ColumnType.NUMERIC, ColumnType.UNIXTIME]),
        multiple: true,
    },
};
