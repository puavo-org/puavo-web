// A single editable filter. Takes the raw filter data and keeps it
// in a parsed format that can be easily fiddled with.

import { OPERATORS } from "./operators.js";

import { ColumnType, ColumnFlag } from "../../table/constants.js";
import { STORAGE_PARSER, parseAbsoluteOrRelativeDate } from "../interpreter/comparisons.js";

const ColumnTypeStrings = {
    [ColumnType.BOOL]: "boolean",
    [ColumnType.NUMERIC]: "numeric",
    [ColumnType.UNIXTIME]: "unixtime",
    [ColumnType.STRING]: "string",
};

export class EditableFilter {
    constructor()
    {
        this.active = false;
        this.column = null;
        this.operator = null;
        this.values = [];

        // Current data being edited (the original data is not overwritten until "Save" is pressed)
        this.editColumn = null;
        this.editOperator = null;
        this.editValues = null;

        // True if this is a brand new filter that hasn't been saved yet. Changes how some
        // operations work (or don't work).
        this.isNew = false;

        // Editor child class (see below)
        this.editor = null;
    }

    beginEditing()
    {
        this.editColumn = this.column;
        this.editOperator = this.operator;
        this.editValues = [...this.values];

        // The editor is created elsewhere
    }

    finishEditing()
    {
        // Overwrite old values
        this.column = this.editColumn;
        this.operator = this.editOperator;
        this.values = this.editor.getData();
    }

    cancelEditing()
    {
        this.editColumn = null;
        this.editOperator = null;
        this.editValues = null;

        // The editor is destroyed elsewhere
    }

    // Parses a "raw" filter stored as [active?, column, operator, value1, value2, ... valueN].
    // Returns true if OK.
    load(raw, columnDefinitions)
    {
        if (!Array.isArray(raw) || raw.length < 4) {
            console.error(`EditableFilter::fromRaw(): invalid/incomplete raw filter:`);
            console.error(raw);
            return false;
        }

        // The column must be valid. We can tolerate/fix almost everything else, but not this.
        if (!(raw[1] in columnDefinitions)) {
            console.warn(`EditableFilter::fromRaw(): column "${raw[1]}" is not valid`);
            return false;
        }

        this.active = (raw[0] === true || raw[0] === 1) ? 1 : 0;
        this.column = raw[1];
        this.operator = raw[2];
        this.values = raw.slice(3);

        // Reset invalid operators to "=" because it's the least destructive of them all,
        // and I'd wager that most filters are simple equality checks
        if (!(this.operator in OPERATORS)) {
            console.warn(`EditableFilter::fromRaw(): operator "${this.operator}" is not valid, resetting it to "="`);
            this.operator = "=";
        }

        // Is the operator usable with this column type?
        const opDef = OPERATORS[this.operator],
              colDef = columnDefinitions[this.column];

        if (!opDef.allowed.has(colDef.type)) {
            console.warn(`EditableFilter::fromRaw(): operator "${this.operator}" cannot be used with ` +
                         `column type "${ColumnTypeStrings[colDef.type]}" (column "${this.column}"), ` +
                         `resetting to "="`);
            this.operator = "=";
        }

        // Handle storage units. Remove invalid values.
        if (colDef.flags & ColumnFlag.F_STORAGE) {
            let proper = [];

            // Remove invalid entries
            for (const v of this.values) {
                try {
                    const m = STORAGE_PARSER.exec(v.toString().trim());

                    if (m !== null) {
                        const unit = (m.groups.unit === undefined || m.groups.unit === null) ? "B" : m.groups.unit;
                        proper.push(`${m.groups.value}${unit}`);
                    }
                } catch (e) {
                    console.error(e);
                    continue;
                }
            }

            this.values = proper;
        }

        // Check time strings
        if (colDef.type == ColumnType.UNIXTIME) {
            let proper = [];

            for (const v of this.values) {
                try {
                    if (parseAbsoluteOrRelativeDate(v) !== null)
                        proper.push(v);
                } catch (e) {
                    console.error(e);
                    continue;
                }
            }

            this.values = proper;
        }

        if (this.values.length == 0) {
            // Need to do this check again, because we might have altered the values
            console.error(`EditableFilter::fromRaw(): filter has no values at all`);
            return false;
        }

        // Ensure there's the required number of values for this operator
        if (this.operator == "[]" || this.operator == "![]") {
            if (this.values.length == 1) {
                console.warn(`EditableFilter::fromRaw(): need more than one value, duplicating the single value`);
                this.values.push(this.values[0]);
            } else if (this.values.length > 2) {
                console.warn(`EditableFilter::fromRaw(): intervals can use only two values, removing extras`);
                this.values = [this.values[0], this.values[1]];
            }
        }

        if (this.values.length > 1 && opDef.multiple !== true) {
            console.warn(`EditableFilter::fromRaw(): operator "${this.operator}" cannot handle multiple values, extra values removed`);
            this.values = [this.values[0]];
        }

        return true;
    }

    save()
    {
        return [this.active ? 1 : 0, this.column, this.operator].concat(this.values);
    }
}
