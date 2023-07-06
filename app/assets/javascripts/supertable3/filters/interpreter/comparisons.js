/*
The RPN program contains only binary logic. These evaluators actually figure out if the logic
values being tested are true (1) or false (0). They're "compiled" only once, but they must be
re-evaluated again for every row that is being checked.
*/

import { ColumnType, ColumnFlag } from "../../table/constants.js";
import { TokenType, TokenFlags } from "./tokenizer.js";

// All known operators
const KNOWN_OPERATORS = new Set(["=", "!=", "<", "<=", ">", ">=", "!!"]);

// Which operators can be used with different column types? For example, strings cannot
// be compared with < or > (actually they can be, but it won't result in what you expect).
export const ALLOWED_OPERATORS = {
    [ColumnType.BOOL]: new Set(["=", "!=", "!!"]),
    [ColumnType.NUMERIC]: new Set(["=", "!=", "<", "<=", ">", ">=", "!!"]),
    [ColumnType.UNIXTIME]: new Set(["=", "!=", "<", "<=", ">", ">=", "!!"]),
    [ColumnType.STRING]: new Set(["=", "!=", "!!"]),
};

// Absolute ("YYYY-MM-DD HH:MM:SS") and relative ("-7d") time matchers
export const
    ABSOLUTE_TIME = /^(?<year>\d{4})-?(?<month>\d{2})?-?(?<day>\d{2})? ?(?<hour>\d{2})?:?(?<minute>\d{2})?:?(?<second>\d{2})?$/,
    RELATIVE_TIME = /^(?<sign>(\+|-))?(?<value>(\d*))(?<unit>(s|h|d|w|m|y))?$/;

// Storage size matcher ("10M", "1.3G", "50%10G" and so on).
// XY or Z%XY, where X=value, Y=optional unit, Z=percentage. Permit floats, written with
// either commas or dots.
export const STORAGE_PARSER = /^((?<percent>(([0-9]*[.,])?[0-9]+))%)?(?<value>(([0-9]*[.,])?[0-9]+))(?<unit>([a-zA-Z]))?$/;

// String->float, understands dots and commas (so locales that use dots or commas for
// thousands separating will work correctly)
export function floatize(str)
{
    return parseFloat(str.replace(",", "."));
}

// Converts a "YYYY-MM-DD HH:MM:SS" into a Date object, but the catch is that you can omit
// the parts you don't need, ie. the more you specify, the more accurate it gets. Giving
// "2021" to this function returns 2021-01-01 00:00:00, "2021-05" returns 2021-05-01 00:00:00,
// "2021-05-27 19:37" returns 2021-05-27 19:37:00 and so on. The other format this function
// understands are relative times: if the input value is an integer, then it is added to the
// CURRENT time and returned. Negative values point to the past, positive point to the future.
export function parseAbsoluteOrRelativeDate(str)
{
    let match = ABSOLUTE_TIME.exec(str);

    if (match !== null) {
        // Parse an absolute datetime

        // This should cut off after the first missing element (ie. if you omit the day,
        // then hours, minutes and seconds should not be set), but the regexp won't match
        // it then, so no harm done.
        const year = parseInt(match.groups.year, 10),
              month = parseInt(match.groups.month || "1", 10) - 1,
              day = parseInt(match.groups.day || "1", 10),
              hour = parseInt(match.groups.hour || "0", 10),
              minute = parseInt(match.groups.minute || "0", 10),
              second = parseInt(match.groups.second || "0", 10);

        let d = null;

        try {
            d = new Date();

            d.setFullYear(year);
            d.setMonth(month);
            d.setDate(day);
            d.setHours(hour);
            d.setMinutes(minute);
            d.setSeconds(second);
            d.setMilliseconds(0);       // the database values have only 1-second granularity
        } catch (e) {
            console.error(`parseAbsoluteOrRelativeDate(): can't construct an absolute Date object from "${str}":`);
            console.error(e);
            return null;
        }

        return d;
    }

    match = RELATIVE_TIME.exec(str);

    if (match === null) {
        // Don't know what this string means
        console.error(`parseAbsoluteOrRelativeDate(): "${str}" is neither absolute nor relative date`);
        return null;
    }

    // Parse a relative datetime
    let value = parseInt(match.groups.value, 10);

    // Scale
    switch (match.groups.unit) {
        default:
        case "s":
            // Seconds are the default, do nothing
            break;

        case "h":
            value *= 60 * 60;               // 1 hour in seconds
            break;

        case "d":
            value *= 60 * 60 * 24;          // 1 day in seconds
            break;

        case "w":
            value *= 60 * 60 * 24 * 7;      // 1 week in seconds
            break;

        case "m":
            value *= 60 * 60 * 24 * 30;     // 1 (30-day) month in seconds
            break;

        case "y":
            value *= 60 * 60 * 24 * 365;    // 1 year with 365 days (no leap year checks here)
            break;
    }

    // Sign
    if (match.groups.sign !== undefined) {
        if (match.groups.sign == "-")
            value *= -1;

        // Treat all other signs are +, even unknown ones (there shouldn't be any, since the
        // regexp rejects them)
    }

    let d = new Date();

    try {
        d.setSeconds(d.getSeconds() + value);
        d.setMilliseconds(0);       // the database values have only 1-second granularity
    } catch (e) {
        console.error(`parseAbsoluteOrRelativeDate(): can't construct a relative Date object from "${str}":`);
        console.error(e);
        return null;
    }

    return d;
}

export class ComparisonCompiler {
    constructor(logger, columnDefinitions, columnNames)
    {
        this.logger = logger;
        this.columnDefinitions = columnDefinitions;
        this.columnNames = columnNames;
    }

    // Parses and expands a value with unit, like "10M" or "10G" to a full number. Optionally
    // calculates a percentage value, like "50%10M" is equivalent to writing "5M".
    __parseStorage(valueToken)
    {
        const storage = STORAGE_PARSER.exec(valueToken.str.trim());

        if (storage === null) {
            // Just a number, no units or percentages
            try {
                const v = floatize(valueToken.str);

                if (isNaN(v)) {
                    console.error(`__parseStorage(): "${valueToken.str}" is not a valid number`);
                    this.logger.errorToken("not_a_number", valueToken);
                    return null;
                }

                return v;
            } catch (e) {
                console.error(`__parseStorage(): "${valueToken.str}" cannot be parsed as a float`);
                this.logger.errorToken("not_a_number", valueToken);
                return null;
            }
        }

        // The base value. It's easier if we treat everything here as a float.
        let value = 0;

        try {
            value = floatize(storage.groups.value);
        } catch (e) {
            console.error(`__parseStorage(): "${storage.groups.value}" cannot be parsed as a float`);
            this.logger.errorToken("not_a_number", valueToken);
            return null;
        }

        // Scale unit
        let unit = storage.groups.unit;

        if (unit === undefined || unit === null)
            unit = "B";

        switch (unit) {
            case "B":
                // bytes are the default, do nothing
                break;

            case "K":
                value *= 1024;
                break;

            case "M":
                value *= 1024 * 1024;
                break;

            case "G":
                value *= 1024 * 1024 * 1024;
                break;

            case "T":
                value *= 1024 * 1024 * 1024 * 1024;
                break;

            default:
                console.error(`__parseStorage(): invalid storage unit "${unit}"`);
                this.logger.errorToken("invalid_storage_unit", valueToken, unit);
                return null;
        }

        // Percentage
        let percent = storage.groups.percent;

        if (percent) {
            percent = Math.min(Math.max(floatize(percent), 0.0), 100.0);
            value *= percent / 100.0;
        }

        return value;
    }

    __compileBoolean(columnToken, operatorToken, valueToken)
    {
        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: ["1", "t", "y", "true", "yes", "on"].includes(valueToken.str.toLowerCase()),
            regexp: false
        };
    }

    __compileNumeric(columnToken, operatorToken, valueToken)
    {
        const colDef = this.columnDefinitions[this.columnNames.get(columnToken.str)];
        let value = undefined;

        if (colDef.flags & ColumnFlag.F_STORAGE) {
            // Parse a storage specifier, like "5M" or "10G"
            value = this.__parseStorage(valueToken);

            if (value === null)
                return null;
        } else {
            try {
                if (valueToken.str.indexOf(".") == -1 && valueToken.str.indexOf(",") == -1) {
                    // Integer
                    value = parseInt(valueToken.str, 10);
                } else {
                    // Float
                    value = floatize(valueToken.str);
                }

                if (isNaN(value))
                    throw new Error("not an integer");
            } catch (e) {
                console.error(`ComparisonCompiler::compile(): can't parse a number: ${e.message}`);
                console.error(e);
                this.logger.errorToken("not_a_number", valueToken);
                return null;
            }
        }

        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: value,
            regexp: false
        };
    }

    __compileUnixtime(columnToken, operatorToken, valueToken)
    {
        const out = parseAbsoluteOrRelativeDate(valueToken.str);

        if (out === null) {
            this.logger.errorToken("unparseable_time", valueToken);
            return false;
        }

        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: out.getTime() / 1000,        // convert to seconds
            regexp: false
        }
    }

    __compileString(columnToken, operatorToken, valueToken)
    {
        let regexp = false,
            value = undefined;

        if (valueToken.flags & TokenFlags.REGEXP) {
            // Compile a regexp
            try {
                value = new RegExp(valueToken.str.trim(),
                                   valueToken.flags & TokenFlags.MULTILINE ? "miu" : "iu"),
                regexp = true;
            } catch (e) {
                console.error(`ComparisonCompiler::compile(): regexp compilation failed: ${e.message}`);
                this.logger.errorToken("invalid_regexp", valueToken, e.message);
                return null;
            }
        } else {
            // A plain string, use as-is
            value = valueToken.str;
        }

        return {
            column: columnToken.str,
            operator: operatorToken.str,
            value: value,
            regexp: regexp
        };
    }

    // Takes a raw comparison (made of three tokens) and "compiles" it (ie. verifies the data
    // types, the comparison operator and the value, and converts the stringly-typed value into
    // "native" JavaScript type). Returns null if it failed.
    compile(columnToken, operatorToken, valueToken)
    {
        // Validate the column and the operator
        if (!this.columnNames.has(columnToken.str)) {
            console.error(`ComparisonCompiler::compile(): unknown column "${columnToken.str}"`);
            this.logger.errorToken("unknown_column", columnToken);
            return null;
        }

        if (!KNOWN_OPERATORS.has(operatorToken.str)) {
            console.error(`ComparisonCompiler::compile(): invalid operator "${operatorToken.str}"`);
            this.logger.errorToken("invalid_operator", operatorToken);
            return null;
        }

        const colDef = this.columnDefinitions[this.columnNames.get(columnToken.str)];

        if (!ALLOWED_OPERATORS[colDef.type].has(operatorToken.str)) {
            console.error(`ComparisonCompiler::compile(): operator "${operatorToken.str}" cannot be used with column type "${colDef.type}"`);
            this.logger.errorToken("incompatible_operator", operatorToken);
            return null;
        }

        if (typeof(valueToken.str) != "string") {
            console.error(`ComparisonCompiler::compile(): value "${valueToken.str}" is not a string`);
            this.logger.errorToken("invalid_value", valueToken);
            return null;
        }

        // Interpret the comparison value and convert it into a "native" type
        if (operatorToken.str == "!!") {
            // Special case: always treat the value as boolean, regardless of what the column is
            return this.__compileBoolean(columnToken, operatorToken, valueToken);
        }

        switch (colDef.type) {
            case ColumnType.BOOL:
                return this.__compileBoolean(columnToken, operatorToken, valueToken);

            case ColumnType.NUMERIC:
                return this.__compileNumeric(columnToken, operatorToken, valueToken);

            case ColumnType.UNIXTIME:
                return this.__compileUnixtime(columnToken, operatorToken, valueToken);

            case ColumnType.STRING:
                return this.__compileString(columnToken, operatorToken, valueToken);

            default:
                console.error(`ComparisonCompiler::compile(): unhandled column type "${colDef.type}"`);
                this.logger.errorToken("unknown_error", columnToken);
                return null;
        }
    }
}

// Executes a comparison. Returns true if the comparison matches the tested value.
// Can (sorta) deal with NULL and undefined values.
function __compareSingleValue(cmp, value)
{
    if (cmp.operator != "!!") {
        if (value === undefined || value === null) {
            // Treat missing values as false. Actually comparing them with something
            // is nonsensical. Use the "!!" operator to test if those values actually
            // are present in the data.
            return false;
        }
    }

    switch (cmp.operator) {
        case "=":
            return cmp.regexp ? cmp.value.test(value) : cmp.value === value;

        case "!=":
            return !(cmp.regexp ? cmp.value.test(value) : cmp.value === value);

        case "<":
            return value < cmp.value;

        case "<=":
            return value <= cmp.value;

        case ">":
            return value > cmp.value;

        case ">=":
            return value >= cmp.value;

        case "!!":
            return cmp.value != (value === null || value === undefined);

        default:
            throw new Error(`compare(): unknown operator "${cmp.operator}"`);
    }
}

// Executes a single comparison against a row value. Deals with arrays and NULL/undefined
// data. Returns true if the comparison matched.
export function compareRowValue(value, cmp)
{
    if (value !== undefined && value !== null && Array.isArray(value)) {
        // Loop over multiple values. Currently only string arrays are supported,
        // because no other types of arrays exists in the database.
        if (cmp.operator == "=") {
            for (const v of value)
                if (__compareSingleValue(cmp, v))
                    return true;

            return false;
        }

        // Assume "!=" because there are only two usable operators with strings
        for (const v of value)
            if (!__compareSingleValue(cmp, v))
                return false;

        return true;
    }

    // Just one value
    return __compareSingleValue(cmp, value);
}
