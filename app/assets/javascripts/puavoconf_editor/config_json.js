"use strict";

// JSON editor

import { create, getTemplate } from "../common/dom.js";
import { ConfigEntry } from "./config_entry.js";

export class ConfigJSON extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
        this.input = null;
        this.message = null;

        // a JSON puavoconf value can be empty, even if the JSON spec
        // does not allow that
        if (this.value === null || this.value === undefined)
            this.value = "";
    }

    createEditor(container)
    {
        const template = getTemplate("puavoconfJSON"),
              textarea = template.querySelector("textarea");

        textarea.id = this.id;
        textarea.value = this.value;
        textarea.addEventListener("input", event => this.onChange(event));

        this.input = textarea;
        this.message = template.querySelector("p");
        container.appendChild(template);

        this.validate();
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
            this.message.classList.add("hidden");
        } catch (e) {
            this.input.classList.add("invalid");
            this.message.classList.remove("hidden");
        }
    }
};
