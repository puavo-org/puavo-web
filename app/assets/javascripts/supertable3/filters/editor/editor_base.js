// A base filter editor user interface class for all column types

import { ColumnFlag } from "../../table/constants.js";

export class FilterEditorBase {
    constructor(container, filter, definition)
    {
        // Target filter
        this.filter = filter;

        // Does this filter target RAM/HD sizes?
        this.isStorage = (definition.flags & ColumnFlag.F_STORAGE) ? true : false;

        // Where to put the editor interface
        this.container = container;

        // Unique UI element prefix
        this.id = this._makeRandomID();

        // UI properties
        this.defaultValue = "";
        this.fieldSize = 30;
        this.maxLength = "";
    }

    buildUI()
    {
    }

    operatorHasChanged(operator)
    {
        this.buildUI();
    }

    getData()
    {
        throw new Error("you did not override getData()");
    }

    // Return [state, message], if state is true then the data is valid, otherwise the
    // message is displayed and the filter is NOT saved (and the editor does not close).
    validate()
    {
        return [true, null];
    }

    // Accessing this.container.query... is so frequent that here's two helpers for it
    $(query) { return this.container.querySelector(query); }
    $all(query) { return this.container.querySelectorAll(query); }

    createValueRow(value, showButtons=true, title=null)
    {
        let row = document.createElement("tr"),
            html = "";

        if (title !== null)
            html += `<td>${title}</td>`;

        html += `<td><div class="flex-cols gap-5px">`;

        value = value.toString();

        if (this.isStorage) {
            // Make a unit selector combo box and strip the unit from the value
            const unit = value.length > 1 ? value.toString().slice(value.length - 1) : null;

            html += `<input type="text" size="${this.fieldSize}" maxlen="" value="${value.length > 1 ? value.slice(0, value.length - 1) : value}">`;

            html += "<select>";

            for (const u of [["B", "B"], ["KiB", "K"], ["MiB", "M"], ["GiB", "G"], ["TiB", "T"]])
                html += `<option data-unit="${u[1]}" ${u[1] == unit ? "selected" : ""}>${u[0]}</option>`;

            html += "</select>";
        } else html += `<input type="text" size="${this.fieldSize}" maxlength="${this.maxLength}">`;

        if (showButtons)
            html += `<button>+</button><button>-</button>`;

        html += "</div></td>";

        row.innerHTML = html;

        if (!this.isStorage)
            row.querySelector(`input[type="text"]`).value = value;

        if (showButtons)
            this.addEventHandlers(row);

        return row;
    }

    addEventHandlers(row)
    {
        // +/- button click handlers. Their positions change if the unit combo box is on the row.
        const add = this.isStorage ? 2 : 1,
              del = this.isStorage ? 3 : 2;

        row.children[0].children[0].children[add].addEventListener("click", (e) => this.duplicateRow(e));
        row.children[0].children[0].children[del].addEventListener("click", (e) => this.removeRow(e));
    }

    duplicateRow(e)
    {
        let thisRow = e.target.parentNode.parentNode.parentNode,
            newRow = thisRow.cloneNode(true);

        if (this.isStorage) {
            // Turns out that selectedIndex is not part of the DOM. Thank you, JavaScript.
            // This is so ugly.
            newRow.children[0].children[0].children[1].selectedIndex =
                thisRow.children[0].children[0].children[1].selectedIndex;
        }

        this.addEventHandlers(newRow);
        thisRow.parentNode.insertBefore(newRow, thisRow.nextSibling);
    }

    removeRow(e)
    {
        let thisRow = e.target.parentNode.parentNode.parentNode;

        thisRow.parentNode.removeChild(thisRow);

        // There must be at least one value at all times, even if it's empty
        if (this.$all(`table#values tr`).length == 0) {
            console.log("Creating a new empty value row");
            this.$("table#values").appendChild(this.createValueRow(this.defaultValue));
        }
    }

    _makeRandomID()
    {
        const CHARS = "abcdefghijklmnopqrstuvwxyz";
        let out = "";

        for (let i = 0; i < 20; i++)
            out += CHARS.charAt(Math.floor(Math.random() * CHARS.length));

        return out;
    }
}
