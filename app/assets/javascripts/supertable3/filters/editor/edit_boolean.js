// Boolean filter editor

import { _tr } from "../../../common/utils.js";
import { FilterEditorBase } from "./editor_base.js";

export class FilterEditorBoolean extends FilterEditorBase {
    buildUI()
    {
        const add = (label, id, checked) => `<label><input type="radio" name="${this.id}-value" id="${this.id}-${id}" ${checked ? "checked" : ""}>${label}</label>`;

        this.container.innerHTML =
`<div class="flex-rows gap-5px padding-top-10px">` +
`${add(_tr("filtering.ed.bool.t"), "true", this.filter.editValues[0] === 1)}` +
`${add(_tr("filtering.ed.bool.f"), "false", this.filter.editValues[0] !== 1)}` +
`</div>`;

        this.$(`#${this.id}-true`).addEventListener("click", () => { this.filter.editValues = [1]; });
        this.$(`#${this.id}-false`).addEventListener("click", () => { this.filter.editValues = [0]; });
    }

    getData()
    {
        return [this.filter.editValues[0] === 1 ? 1 : 0];
    }
}
