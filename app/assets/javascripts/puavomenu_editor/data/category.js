"use strict";

import { isNonemptyString } from "../utils.js";
import { TranslatableString } from "./translatable.js";

export class Category {
    constructor(c = null)
    {
        this.position = 0;
        this.condition = "";
        this.name = new TranslatableString();
        this.menus = [];
        this.programs = [];
        this.hiddenByDefault = false;

        this.warnings = new Set();
        this.errors = new Set();

        if (c)
            this.load(c);
    }

    load(object)
    {
        try {
            this.position = parseInt(object.position, 10);
        } catch (e) {
            console.warn(`Category::load(): cannot parse "${object.position}" as a number, resetting to 0`);
            this.position = 0;
        }

        if (isNaN(this.position)) {
            console.warn(`Category::load(): cannot parse "${object.position}" as a number, resetting to 0`);
            this.position = 0;
        }

        if (!object.name) {
            console.error(`Category::load(): ignoring a category without a name`);
            return false;
        }

        this.name.load(object.name);

        this.condition = isNonemptyString(object.condition) ? object.condition.trim() : "";

        // Empty arrays are valid here
        this.menus = Array.isArray(object.menus) ? [...object.menus] : [];
        this.programs = Array.isArray(object.programs) ? [...object.programs] : [];

        if ("hidden_by_default" in object && object.hidden_by_default === true)
            this.hiddenByDefault = true;
        else this.hiddenByDefault = false;

        this.warnings = new Set();
        this.errors = new Set();
        this.validate();

        return true;
    }

    save()
    {
        let out = {
            position: this.position,
            name: this.name.save(),
        };

        // Save this only if it's set to true, since "false" is the default
        if (this.hiddenByDefault)
            out.hidden_by_default = true;

        if (this.condition.length > 0)
            out.condition = this.condition;

        if (this.menus.length > 0)
            out.menus = [...this.menus];

        if (this.programs.length > 0)
            out.programs = [...this.programs];

        return out;
    }

    validate()
    {
        if (!this.name.isNonEmpty())
            this.errors.add("missing_name");
        else this.errors.delete("missing_name");

        if (this.name.hasMultiple())
            this.warnings.add("multiple_names");
        else this.warnings.delete("multiple_names");
    }
}
