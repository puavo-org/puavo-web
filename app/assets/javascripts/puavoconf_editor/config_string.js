"use strict";

// String editor

import { create, getTemplate } from "../common/dom.js";
import { ConfigEntry } from "./config_entry.js";

export class ConfigString extends ConfigEntry {
    constructor(parent, key, value, choices)
    {
        super(parent);

        this.key = key;
        this.value = value;
        this.choices = choices;
    }

    createEditor(container)
    {
        const template = getTemplate("puavoconfString");
        const input = template.querySelector("input");

        input.id = this.id;
        input.addEventListener("input", e => this.onChange(e));
        input.value = this.value;

        if (!this.choices) {
            template.querySelector("label").remove();
            template.querySelector("select").remove();
        } else {
            // Setup the predefined choices
            const select = template.querySelector("select");

            select.id = `${this.id}-choices`;
            template.querySelector("label").htmlFor = `${this.id}-choices`;

            for (const choice of this.choices)
                select.appendChild(create("option", { id: choice, text: choice }));

            // Pre-select the current value if it is a valid choice
            if (this.choices.includes(this.value))
                select.value = this.value;
            else select.value = null;

            select.addEventListener("change", e => this.onChangeChoice(e));
        }

        container.appendChild(template);
    }

    onChange(event)
    {
        this.value = event.target.value;

        if (this.choices) {
            // Change the select to reflect the typed-in value, if it's a valid choice
            const select = event.target.parentNode.querySelector("select");

            if (this.choices.includes(this.value))
                select.value = this.value;
            else select.value = null;
        }

        this.valueChanged();
    }

    onChangeChoice(event)
    {
        // Reflect the change in the input box
        event.target.parentNode.querySelector("input").value = event.target.value;
        this.value = event.target.value;
        this.valueChanged();
    }
};
