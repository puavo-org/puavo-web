"use strict";

// JSON editor

import { create } from "../common/dom.js";
import { ConfigEntry } from "./config_entry.js";

export class ConfigJSON extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
        this.input = null;

        // a JSON puavoconf value can be empty, even if the JSON spec
        // does not allow that
        if (this.value === null || this.value === undefined)
            this.value = "";
    }

    createEditor(container)
    {
        let input = create("textarea", { cls: "json", inputValue: this.value });

        input.rows = 2;

        this.input = input;
        this.validate();

        input.addEventListener("input", event => this.onChange(event));
        container.appendChild(input);
    }

    onChange(event)
    {
        this.value = event.target.value;
        this.validate();
        this.valueChanged();
    }

    validate()
    {
        // Highlight invalid JSON
        try {
            JSON.parse(this.value);
            this.input.classList.remove("invalid");
        } catch (e) {
            this.input.classList.add("invalid");
        }
    }
};
