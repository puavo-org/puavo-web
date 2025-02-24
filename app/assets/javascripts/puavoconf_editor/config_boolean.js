"use strict";

// Boolean editor

import { create } from "../common/dom.js";
import { ConfigEntry } from "./config_entry.js";

export class ConfigBoolean extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;

        // Convert initial "null" values to false, so when a new boolean entry is created,
        // it defaults to false
        if (value === true || value === "true")
            this.value = true;
        else this.value = false;
    }

    createEditor(container)
    {
        const tID = `true-${this.id}`,
              fID = `false-${this.id}`;

        container.innerHTML =
            `<input type="radio" id="${tID}" name="${this.id}"><label for="${tID}">True</label>` +
            `<input type="radio" id="${fID}" name="${this.id}"><label for="${fID}">False</label>`;

        container.querySelector(`#${tID}`).checked = (this.value == true);
        container.querySelector(`#${tID}`).addEventListener("click", () => {
            this.value = true;
            this.valueChanged();
        });

        container.querySelector(`#${fID}`).checked = (this.value == false);
        container.querySelector(`#${fID}`).addEventListener("click", () => {
            this.value = false;
            this.valueChanged();
        });
    }

    getValue()
    {
        if (this.value === null || this.value === undefined)
            return "false";

        return this.value ? "true" : "false";
    }
};
