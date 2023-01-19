// Unixtime filter editor. Handles absolute and relative times.

import { _tr } from "../../../common/utils.js";
import { FilterEditorNumeric } from "./edit_numeric.js";
import { parseAbsoluteOrRelativeDate } from "../interpreter/comparisons.js";

export class FilterEditorUnixtime extends FilterEditorNumeric {
    constructor(container, filter, definition)
    {
        super(container, filter, definition);

        // Use today's date as the default value
        const d = new Date();

        this.defaultValue = `${d.getFullYear()}-` +
                            `${String(d.getMonth() + 1).padStart(2, "0")}-` +
                            `${String(d.getDate()).padStart(2, "0")}`;

        this.fieldSize = 20;
        this.maxLength = "20";
    }

    buildUI()
    {
        super.buildUI();
        this.$(`a#${this.id}-help`).addEventListener("click", (e) => this.showHelp(e));
    }

    getData()
    {
        let values = [];

        // Unlike numbers, attempt no string->int conversions here. The filter compiler
        // engine will deal with interpreting absolute and relative time values.
        for (const i of this.$all(`table#values tr input[type="text"]`)) {
            const v = i.value.trim();

            if (v.length == 0)
                continue;

            values.push(v);
        }

        return values;
    }

    validate()
    {
        const interval = (this.filter.editOperator == "[]" || this.filter.editOperator == "![]");
        let valid = 0;

        for (const i of this.$all(`table#values tr input[type="text"]`)) {
            const v = i.value.trim();

            if (v.length == 0)
                continue;

            if (parseAbsoluteOrRelativeDate(v) === null)
                return [false, `"${v}"` + _tr("filtering.ed.time.invalid")];

            valid++;
        }

        if (interval && valid < 2)
            return [false, _tr("filtering.ed.invalid_interval")];

        if (!interval && valid == 0)
            return [false, _tr("filtering.ed.no_values")];

        return [true, null];
    }

    getExtraHelp()
    {
        return ` <a href="#" id="${this.id}-help"> ${_tr("filtering.ed.time.help_link")}</a>.`;
    }

    showHelp(e)
    {
        e.preventDefault();
        window.alert(_tr("filtering.ed.time.help"));
    }
}
