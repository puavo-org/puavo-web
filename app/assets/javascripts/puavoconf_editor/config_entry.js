"use strict";

// Base config entry

import { create } from "../common/dom.js";
import { randomID } from "./main.js";

// Base class for all entries
export class ConfigEntry {
    constructor(parent)
    {
        this.parent = parent;
        this.language = parent.language;
        this.key = null;
        this.value = null;
        this.details = null;        // optional "details" element below the editor
        this.id = randomID();
    }

    createEditor(container)
    {
        throw new Error("Your derived class did not override ConfigEntry::createEditor()!");
    }

    createDetails(params)
    {
        this.details = create("div", { cls: "details" });
    }

    valueChanged(fullRebuild=false)
    {
        // notify the editor
        if (this.parent && this.key !== null)
            this.parent.entryHasChanged(this.key, this.value, fullRebuild);
    }

    getValue()
    {
        // JSON allows NULLs, but puavo-conf does not like them
        if (this.value === null || this.value === undefined)
            return "";

        return this.value;
    }
};
