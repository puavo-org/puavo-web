"use strict";

// String editor

import { create } from "../common/dom.js";
import { translate } from "./main.js";
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
        let input = create("input", { inputType: "text", inputValue: this.value });

        input.addEventListener("input", event => this.onChange(event));
        container.appendChild(input);

        if (this.choices) {
            const select = create("select", { id: `${this.id}-choices` });

            for (const choice of this.choices)
                select.appendChild(create("option", { id: choice, text: choice }));

            // Pre-select the current value if it is a valid choice
            if (this.choices.includes(this.value))
                select.value = this.value;
            else select.value = null;

            select.addEventListener("change", event => this.onChangeChoice(event));

            // Create a label too
            const label = create("label", { text: translate(this.language, "choices_title") });

            label.htmlFor = `${this.id}-choices`;
            container.appendChild(label);

            container.appendChild(select);
        }
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
