// Numeric filter editor. Handles storage units, etc.

import { _tr } from "../../../common/utils.js";
import { FilterEditorBase } from "./editor_base.js";
import { floatize } from "../interpreter/comparisons.js";

export class FilterEditorNumeric extends FilterEditorBase {
    constructor(container, filter, definition)
    {
        super(container, filter, definition);

        this.defaultValue = this.isStorage ? "0M" : "0";
        this.fieldSize = 10;
        this.maxLength = "32";
    }

    buildUI()
    {
        const id = this.id;
        const opr = this.filter.editOperator;

        if (opr == "[]" || opr == "![]") {
            let help = "";

            if (opr == "[]")
                help += _tr("filtering.ed.closed");
            else help += _tr("filtering.ed.open");

            this.container.innerHTML = `<p>${help}${this.getExtraHelp()}</p><table id="values" class="font-80p"></table>`;

            let table = this.$("table#values");

            table.appendChild(this.createValueRow(this.filter.editValues[0], false, "Min:"));
            table.appendChild(this.createValueRow(this.filter.editValues[1], false, "Max:"));
        } else if (opr == "=" || opr == "!=") {
            let html = `<p class="help">${_tr("filtering.ed.multiple")}`;

            html += " ";
            html += _tr((opr == "=") ? "filtering.ed.one_hit_is_enough" : "filtering.ed.no_hits_allowed");
            html += " ";

            html += `${this.getExtraHelp()}</p><table id="values"></table>`;

            this.container.innerHTML = html;

            let table = this.$("table#values");

            for (const v of this.filter.editValues)
                table.appendChild(this.createValueRow(v));
        } else {
            this.container.innerHTML = `<p class="help">${_tr("filtering.ed.single")}${this.getExtraHelp()}</p><table id="values"></table>`;
            this.$("table#values").appendChild(this.createValueRow(this.filter.editValues[0], false));
        }
    }

    getData()
    {
        const interval = (this.filter.editOperator == "[]" || this.filter.editOperator == "![]");
        let values = [];

        // This assumes validate() has been called first and the data is actually valid
        for (const i of this.$all(`table#values tr input[type="text"]`)) {
            let n = i.value.trim();

            if (n.length == 0)
                continue;

            try {
                n = floatize(n);
            } catch (e) {
                continue;
            }

            if (isNaN(n))
                continue;

            if (this.isStorage) {
                const s = i.parentNode.children[1];
                values.push(`${n}${s.options[s.selectedIndex].dataset.unit}`);  // put the unit back
            } else values.push(n);
        }

        // min > max, swap
        // TODO: Make this work with storage
        if (!this.isStorage && interval && values[0] > values[1])
            values = [values[1], values[0]];

        return values;
    }

    validate()
    {
        const interval = (this.filter.editOperator == "[]" || this.filter.editOperator == "![]");
        let valid = 0;

        for (const i of this.$all(`table#values tr input[type="text"]`)) {
            let n = i.value.trim();

            if (n.length == 0)
                continue;

            try {
                n = floatize(n);
            } catch (e) {
                return [false, `"${i.value.trim()}" ` + _tr("filtering.ed.numeric.nan")];
            }

            if (isNaN(n))
                return [false, `"${i.value.trim()}" `+ _tr("filtering.ed.numeric.nan")];

            if (this.isStorage && n < 0)
                return [false, _tr("filtering.ed.numeric.negative_storage")];

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
        return "";
    }
}
