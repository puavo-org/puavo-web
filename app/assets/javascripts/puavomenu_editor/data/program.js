"use strict";

import { isNonemptyString } from "../utils.js";
import { TranslatableString } from "./translatable.js";

function loadArray(a)
{
    if (isNonemptyString(a))
        return a.split(", ");
    else if (Array.isArray(a))
        return [...a];
    else return [];
}

export const ProgramType = {
    DESKTOP: 1,
    CUSTOM: 2,
    WEB_LINK: 3,
};

export class Program {
    constructor(p = null)
    {
        this.programType = ProgramType.DESKTOP;

        // Common properties
        this.condition = "";
        this.name = new TranslatableString();
        this.description = new TranslatableString();
        this.icon = "";
        this.tags = [];
        this.keywords = [];
        this.hiddenByDefault = false;

        // The executed command for custom programs
        this.command = "";

        // The URL for web links
        this.url = "";

        // Package ID for puavo-pkg -installed optional programs
        this.puavoPkgID = "";

        this.warnings = new Set();
        this.errors = new Set();

        // Marks this program as external and makes it available, but uneditable
        this.isExternal = false;

        if (p)
            this.load(p);
    }

    load(object)
    {
        if (object.type) {
            switch (object.type) {
                case "web":
                    this.programType = ProgramType.WEB_LINK;
                    break;

                case "custom":
                    this.programType = ProgramType.CUSTOM;
                    break;

                default:
                    this.programType = ProgramType.DESKTOP;
                    break;
            }
        }

        // For programs, the name is optional
        if (object.name)
            this.name.load(object.name);

        if (object.description)
            this.description.load(object.description);

        this.condition = isNonemptyString(object.condition) ? object.condition.trim() : "";

        if ("hidden_by_default" in object && object.hidden_by_default === true)
            this.hiddenByDefault = true;
        else this.hiddenByDefault = false;

        this.icon = isNonemptyString(object.icon) ? object.icon.trim() : "";

        this.tags = loadArray(object.tags);

        this.keywords = loadArray(object.keywords);

        this.command = isNonemptyString(object.command) ? object.command.trim() : "";

        this.url = isNonemptyString(object.url) ? object.url.trim() : "";

        if (object.puavopkg && object.puavopkg.id)
            this.puavoPkgID = object.puavopkg.id;
        else this.puavoPkgID = "";

        this.warnings = new Set();
        this.errors = new Set();
        this.validate();

        return true;
    }

    save()
    {
        let out = {};

        switch (this.programType) {
            case ProgramType.CUSTOM:
                out.type = "custom";
                break;

            case ProgramType.WEB_LINK:
                out.type = "web";
                break;

            default:
                break;
        }

        if (this.name.isNonEmpty())
            out.name = this.name.save();

        if (this.description.isNonEmpty())
            out.description = this.description.save();

        if (this.programType == ProgramType.CUSTOM && this.command.length > 0)
            out.command = this.command;

        if (this.programType == ProgramType.WEB_LINK && this.url.length > 0)
            out.url = this.url;

        if (this.hiddenByDefault)
            out.hidden_by_default = true;

        if (this.condition.length > 0)
            out.condition = this.condition;

        if (this.icon.length > 0)
            out.icon = this.icon;

        if (this.tags.length > 0)
            out.tags = this.tags.join(", ");

        if (this.keywords.length > 0)
            out.keywords = this.keywords.join(", ");

        if (this.puavoPkgID.length > 0)
            out.puavopkg = { id: this.puavoPkgID };

        return out;
    }

    validate()
    {
        this.warnings.delete("missing_icon");
        this.warnings.delete("no_tags");
        this.errors.delete("missing_name");
        this.errors.delete("missing_description");
        this.errors.delete("missing_command");
        this.errors.delete("missing_url");

        if (this.programType == ProgramType.CUSTOM || this.programType == ProgramType.WEB_LINK) {
            if (!this.name.isNonEmpty())
                this.errors.add("missing_name");

            if (this.icon.length == 0) {
                // technically this isn't required, it just looks ugly
                this.warnings.add("missing_icon");
            }
        }

        if (this.name.hasMultiple())
            this.warnings.add("multiple_names");
        else this.warnings.delete("multiple_names");

        if (this.description.hasMultiple())
            this.warnings.add("multiple_descriptions");
        else this.warnings.delete("multiple_descriptions");

        if (this.programType == ProgramType.CUSTOM && this.command.length == 0)
            this.errors.add("missing_command");

        if (this.programType == ProgramType.WEB_LINK && this.url.length == 0)
            this.errors.add("missing_url");

        if (this.tags.length == 0)
            this.warnings.add("no_tags");
    }
}
