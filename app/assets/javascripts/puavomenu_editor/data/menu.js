"use strict";

import { isNonemptyString } from "../utils.js";
import { TranslatableString } from "./translatable.js";

export class Menu {
    constructor(m = null)
    {
        this.name = new TranslatableString();
        this.description = new TranslatableString();
        this.condition = "";
        this.icon = "";
        this.programs = [];
        this.hiddenByDefault = false;

        this.warnings = new Set();
        this.errors = new Set();

        // Marks this menu as external and makes it available, but uneditable
        this.isExternal = false;

        if (m)
            this.load(m);
    }

    load(object)
    {
        if (!object.name) {
            console.error(`Menu::load(): ignoring a menu without a name`);
            return false;
        }

        this.name.load(object.name);
        this.description.load(object.description);

        this.condition = isNonemptyString(object.condition) ? object.condition.trim() : "";

        this.icon = isNonemptyString(object.icon) ? object.icon.trim() : "";

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
            name: this.name.save()
        };

        if (this.hiddenByDefault)
            out.hidden_by_default = true;

        if (this.condition.length > 0)
            out.condition = this.condition;

        if (this.description.isNonEmpty())
            out.description = this.description.save();

        if (this.icon.length > 0)
            out.icon = this.icon;

        if (this.programs.length > 0)
            out.programs = [...this.programs];

        return out;
    }

    validate()
    {
        if (!this.isExternal && !this.name.isNonEmpty())
            this.errors.add("missing_name");
        else this.errors.delete("missing_name");

        if (!this.isExternal && this.name.hasMultiple())
            this.warnings.add("multiple_names");
        else this.warnings.delete("multiple_names");

        if (!this.isExternal && this.description.hasMultiple())
            this.warnings.add("multiple_descriptions");
        else this.warnings.delete("multiple_descriptions");

        if (!this.isExternal && this.icon.length == 0)
            this.errors.add("missing_icon");
        else this.errors.delete("missing_icon");
    }
}
