// String filter editor

import { _tr } from "../../../common/utils.js";
import { FilterEditorBase } from "./editor_base.js";

export class FilterEditorString extends FilterEditorBase {
    buildUI()
    {
        this.container.innerHTML = `<p class="help">${this.getExplanation()}</p><table id="values"></table>`;
        let table = this.$("table#values");

        for (const v of this.filter.editValues)
            table.appendChild(this.createValueRow(v));
    }

    getData()
    {
        let values = [];

        for (const i of this.$all(`table#values tr input[type="text"]`))
            values.push(i.value.trim());

        return values;
    }

    operatorHasChanged(operator)
    {
        this.$("p").innerHTML = this.getExplanation();
    }

    getExplanation()
    {
        let out = "";

        out += _tr("filtering.ed.multiple");
        out += " ";
        out += _tr((this.filter.editOperator == "=") ? "filtering.ed.one_hit_is_enough" : "filtering.ed.no_hits_allowed");
        out += " ";
        out += _tr("filtering.ed.regexp");

        return out;
    }
}
