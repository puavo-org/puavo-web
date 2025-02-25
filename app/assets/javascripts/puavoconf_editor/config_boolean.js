"use strict";

// Boolean editor

import { create, getTemplate } from "../common/dom.js";
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
        const template = getTemplate("puavoconfBoolean"),
              items = template.querySelectorAll("label"),
              rbTrue = items[0].querySelector("input"),
              rbFalse = items[1].querySelector("input");

        // Setup unique IDs and events
        items[0].id = `${this.id}-true`;
        items[1].id = `${this.id}-false`;
        rbTrue.name = this.id;
        rbTrue.checked = (this.value == true);
        rbTrue.addEventListener("click", e => { this.value = true; this.valueChanged(); });
        rbFalse.name = this.id;
        rbFalse.checked = (this.value == false);
        rbFalse.addEventListener("click", e => { this.value = false; this.valueChanged(); });

        container.appendChild(template);
    }

    getValue()
    {
        if (this.value === null || this.value === undefined)
            return "false";

        return this.value ? "true" : "false";
    }
};
