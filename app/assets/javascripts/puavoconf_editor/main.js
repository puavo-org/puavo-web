"use strict";

// Interactive PuavoConf editor v2.1

import { create, getTemplate } from "../common/dom.js";

import { ConfigEntry } from "./config_entry.js";
import { ConfigBoolean } from "./config_boolean.js";
import { ConfigString } from "./config_string.js";
import { ConfigJSON } from "./config_json.js";
import { ConfigPuavomenuTags } from "./config_puavomenu.js";

// Generates random strings for radio button IDs
export function randomID(length=10)
{
    const CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789";
    const CHARS_LEN = CHARACTERS.length;
    let output = "";

    // Always start with a letter (CSS IDs can start with a number, but they
    // can cause problems elsewhere)
    output += CHARACTERS.charAt(Math.floor(Math.random() * 26));

    for (let i = 0; i < length - 1; i++ )
        output += CHARACTERS.charAt(Math.floor(Math.random() * CHARS_LEN));

    return output;
}

function initError(outer, message)
{
    outer.prepend(create("p", { cls: "genericError", text: msg }));
}

export class PuavoConfEditor {
    constructor(params)
    {
        // Verify the required parameters
        if (!params.outer) {
            console.warn("PuavoConfEditor::ctor(): params.outer is NULL or invalid, editor not created");
            return;
        }

        if (!params.prefix) {
            initError(params.outer, "PuavoConfEditor::ctor(): no editor prefix specified, editor not created");
            return;
        }

        if (!params.storage) {
            initError(params.outer, "PuavoConfEditor::ctor(): missing storage textarea element, editor not created");
            return;
        }

        this.prefix = params.prefix;
        this.storage = params.storage;
        this.language = params.language || "en";

        if (params.definitions)
            this.definitions = params.definitions;
        else this.definitions = {};

        // Create the user interface
        const template = getTemplate("puavoconfEditor");

        this.container = template.querySelector("div.puavoConfEditor");
        params.outer.prepend(template);

        this.storage.style.display = "none";

        this.container.querySelector(`div.raw input`).addEventListener("click", e => {
            this.storage.style.display = e.target.checked ? "initial" : "none";
        });

        // UI handles
        this.table = this.container.querySelector("table.pcTable");
        this.newInput = this.container.querySelector("input.new");

        this.newInput.addEventListener("input", () => this.handleNewEntryInput());
        this.newInput.addEventListener("keydown", e => this.handleNewEntryKeys(e));

        this.newInput.addEventListener("focusout", (e) => {
            // focusout fires immediately and closes the suggestions list when you
            // try to click it, so we need some hacky timer junk here. It'd be nice
            // if I could see *which* element was clicked, so I could simply not
            // close the popup if it was the target element, but AFAIK that cannot
            // be done reliably in JavaScript... 250 milliseconds is long enough
            // for a mouse click, but it's dangerously short.
            setTimeout(() => { this.hideSuggestions() }, 250);
        });

        // Suggestions list
        this.suggestions = create("div", { id: `${this.prefix}-autocomplete`, cls: "pcSuggestions" });
        this.suggestionsList = [];
        this.currentSuggestion = -1;

        document.body.appendChild(this.suggestions);

        // Initial update
        this.entries = [];

        this.load(this.storage.value, true);
        this.buildTable();

        this.save();
    }

    // Loads the puavoconf data
    load(string, isInitial)
    {
        let parsed = [];

        if (string && string.trim() != "") {
            try {
                parsed = JSON.parse(string);
            } catch (e) {
                console.error("PuavoConfEditor::load(): unable to parse puavo-conf string");
                console.error(e);
                console.log("The original puavo-conf string was:");
                console.log(string);
            }
        }

        // Sort the entries alphabetically. They're shown alhabetically, so
        // edit them alphabetically. New entries are added at the end.
        let keys = Object.keys(parsed);

        if (isInitial)
            keys.sort();

        this.entries = [];

        for (const key of keys)
            this.entries.push(this.createEntry(key, parsed[key]));
    }

    // Converts the entries to JSON and stores them in the storage textarea
    save()
    {
        let values = {};

        for (const e of this.entries)
            values[e.key] = e.getValue();

        // CAUTION: The database does not like hard tabs in pretty-printed JSON.
        // We found out this the hard way.
        this.storage.value = JSON.stringify(values, null, "  ");

        this.storage.classList.remove("pcRawError");
    }

    // Called if the raw JSON is hand-edited
    rawEdited()
    {
        const text = this.storage.value;
        let parsed = null;

        // Don't clobber the table if the JSON isn't valid
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            event.target.classList.add("pcRawError");
            return;
        }

        this.load(this.storage.value, false);
        this.buildTable();
        event.target.classList.remove("pcRawError");
    }

    // Called from the value editors
    entryHasChanged(key, value, fullRebuild=false)
    {
        this.save();
    }

    // Adds a new editable puavo-conf entry. All entries have an internal "editor"
    // class attached to them; the class handles the editing interface in the table.
    createEntry(key, value)
    {
        let entry = null,
            type = null,
            definition = null;

        // Find the type and a possible default value for this entry
        if (key in this.definitions) {
            definition = this.definitions[key];
            type = definition.typehint;

            if (value === null || value === undefined) {
                if ("default" in definition)
                    value = definition["default"]
            }
        }

        // Handle special editors (exact key matches)
        if (key == "puavo.puavomenu.tags")
            return new ConfigPuavomenuTags(this, key, value);

        // Build a type-specific editor. Assume unknown puavo-conf items
        // are just plain strings.
        switch (type) {
            case "string":
            default: {
                const choices = (definition && "choices" in definition) ? definition.choices : null;

                return new ConfigString(this, key, value, choices);
            }

            case "json":
                return new ConfigJSON(this, key, value);

            case "bool":
                return new ConfigBoolean(this, key, value);
        }
    }

    buildTable()
    {
        const tbody = document.createElement("tbody");

        for (const entry of this.entries)
            tbody.appendChild(this._createEntryRow(entry));

        this.table.innerText = "";
        this.table.appendChild(tbody);
    }

    // Removes an entry. Performs an in-place update of the table.
    deleteRow(event)
    {
        const key = event.target.parentNode.parentNode.dataset.key

        // Locate the entry
        let entry = null,
            index = null;

        for (let i = 0; i < this.entries.length; i++) {
            if (this.entries[i].key == key) {
                entry = this.entries[i];
                index = i;
                break;
            }
        }

        if (entry === null)
            return;

        // Nuke it
        this.entries.splice(index, 1);
        this.container.querySelector(`tr#${entry.id}`).remove();

        this.save();

        if (this.suggestions.style.visibility == "visible")
            this.buildSuggestions();
    }

    // Creates a new entry with the given name, and inserts it into the table.
    // A new "new entry" row is created below it.
    createNewEntry(key)
    {
        if (key === undefined || key === null || key.trim().length == 0)
            return;

        // Refuse to create duplicate entries
        for (const entry of this.entries)
            if (entry.key == key)
                return;

        this.hideSuggestions();

        let entry = this.createEntry(key, null);
        this.entries.push(entry);

        this.table.getElementsByTagName('tbody')[0].appendChild(this._createEntryRow(entry));

        if (this.suggestions.style.visibility == "visible") {
            this.hideSuggestions();
            this.suggestions = [];
        }

        this.newInput.value = "";

        this.save();
    }

    _createEntryRow(entry)
    {
        const template = getTemplate("puavoconfEntry");

        const tr = template.querySelector("tr");

        tr.id = entry.id;
        tr.dataset.key = entry.key;

        template.querySelector("td.key").innerText = entry.key;
        template.querySelector("button").addEventListener("click", e => this.deleteRow(e));

        // Create the editor inside the row container DIV
        entry.createEditor(template.querySelector("td.value div"));

        return template;
    }

    // Handles special keys in the entry name input box
    handleNewEntryKeys(event)
    {
        const previous = this.currentSuggestion;

        switch (event.code) {
            // Accept the selected item
            case "Tab":
                if (this.newInput.value.length == 0)
                    return;

                // fallthrough

            case "Enter":
            {
                event.preventDefault();

                let key = null;

                if (this.suggestionsList.length > 0 && this.currentSuggestion != -1)
                    key = this.suggestionsList[this.currentSuggestion];
                else {
                    // This key does not exist in the definitions, so it could be
                    // a completely new puavoconf item
                    key = event.target.value.trim();
                }

                if (key === null || key === undefined || key.trim().length == 0)
                    return;

                // Reset suggestions for the next entry
                this.suggestionsList = [];
                this.currentSuggestion = -1;

                this.createNewEntry(key);
                return;
            }

            // Temporarily hide the suggestions list
            case "Escape":
                event.preventDefault();
                this.hideSuggestions();
                return;

            // Scroll up
            case "ArrowUp":
                event.preventDefault();

                if (this.suggestionsList.length == 0)
                    return;

                if (this.currentSuggestion > 0)
                    this.currentSuggestion--;

                break;

            // Scroll down (or show the list if it's hidden)
            case "ArrowDown":
                event.preventDefault();

                if (this.suggestionsList.length == 0) {
                    this.buildSuggestions();
                    break;
                }

                if (this.suggestions.style.visibility != "visible") {
                    if (this.suggestionsList.length > 0)
                        this.currentSuggestion = 0;

                    this.suggestions.style.visibility = "visible";
                    break;
                }

                if (this.currentSuggestion < this.suggestionsList.length - 1)
                    this.currentSuggestion++;

                break;

            // First entry
            case "Home":
                event.preventDefault();

                if (this.suggestionsList.length == 0)
                    return;

                this.currentSuggestion = 0;
                break;

            // Last entry
            case "End":
                event.preventDefault();

                if (this.suggestionsList.length == 0)
                    return;

                this.currentSuggestion = this.suggestionsList.length - 1;
                break;

            // Page up and down
            case "PageUp":
            case "PageDown": {
                event.preventDefault();

                if (this.suggestionsList.length == 0)
                    return;

                if (this.currentSuggestion < 0 || this.currentSuggestion > this.suggestionsList.length - 1)
                    this.currentSuggestion = 0;
                else {
                    // Compute the average number of items visible at once,
                    // then jump up/down by it. Works surprisingly nicely.
                    const height = this.suggestions.getBoundingClientRect().height,
                          elems = this.suggestions.querySelectorAll("div.entry");

                    let totalHeight = 0;

                    for (const e of elems)
                        totalHeight += e.getBoundingClientRect().height;

                    let delta = Math.floor(height / (totalHeight / elems.length));

                    if (event.code == "PageUp")
                        delta = -delta;

                    this.currentSuggestion = Math.max(0, Math.min(this.currentSuggestion + delta, this.suggestionsList.length - 1));
                }

                break;
            }

            default:
                return;
        }

    //    console.log(`previous=${previous} current=${this.currentSuggestion}`);

        // Update selection states and list scrolling
        if (this.currentSuggestion == previous)
            return;

        let nodes = this.suggestions.childNodes;

        if (previous >= 0 && previous <= this.suggestionsList.length)
            nodes[previous].classList.remove("selected");

        nodes[this.currentSuggestion].classList.add("selected");
        this.ensureItemIsVisible(this.currentSuggestion);
    }

    handleNewEntryInput()
    {
        this.buildSuggestions();
    }

    hideSuggestions()
    {
        this.suggestions.style.visibility = "hidden";
    }

    buildSuggestions()
    {
        const translations = getTemplate("puavoconfTranslations");

        const needle = this.newInput.value.trim();
        const showAll = needle.length == 0;
        let existing = new Set();

        this.suggestionsList = [];
        this.currentSuggestion = -1;

        // Find all matching definitions. Partial matches are enough.
        if (showAll || needle.length > 0) {
            for (const entry of this.entries)
                existing.add(entry.key);

            for (const key in this.definitions)
                if (!existing.has(key) && (showAll || key.includes(needle)))
                    this.suggestionsList.push(key);
        }

        this.suggestionsList.sort();
        this.suggestions.innerText = "";

        if (this.suggestionsList.length == 0) {
            // This is a completely new entry, we have no definition for it
            const duplicate = existing.has(needle);

            let newEntry = create("div", {
                text: translations.querySelector("div#" + (duplicate ? "already_exists" : "accept_new")).innerText.replace("$(name)", `"${needle}"`),
                cls: duplicate ? "error" : "new"
            });

            newEntry.addEventListener("click", e => this.createNewEntry(needle));
            this.suggestions.appendChild(newEntry);

            this.positionSuggestions();
            return;
        }

        // Construct a list of matching items
        for (const key of this.suggestionsList) {
            let e = create("div", { cls: "entry" });

            e.dataset.key = key;
            e.addEventListener("click", e => this.createNewEntry(e.target.dataset.key));

            let html = "";

            if (showAll)
                html = key;
            else {
                // Highlight the matching part
                const pos = key.indexOf(needle);

                html = `${key.substr(0, pos)}` +
                       `<span class="match">${key.substr(pos, needle.length)}</span>` +
                       `${key.substr(pos + needle.length)}`;

                if (key in this.definitions) {
                    const def = this.definitions[key];

                    if (def["default"])
                        html += `<dfn>(${def["default"]})</dfn>`;

                    if (def.description)
                        html += `<dfn>${def.description}</dfn>`;
                }
            }

            e.innerHTML = html;
            this.suggestions.appendChild(e);
        }

        this.currentSuggestion = 0;
        this.suggestions.childNodes[this.currentSuggestion].classList.add("selected");
        this.ensureItemIsVisible(this.currentSuggestion);
        this.positionSuggestions();
    }

    // "element.scrollIntoView()" works but it's lackluster
    ensureItemIsVisible(index)
    {
        const list = this.suggestions,
              item = list.childNodes[index];

        if (!list || !item)
            return;

        // This padding has to be taken into account
        const padding = parseInt(window.getComputedStyle(list).paddingTop, 10);

        const lrect = list.getBoundingClientRect(),
              irect = item.getBoundingClientRect();

        // Scroll up
        if (irect.top - padding < lrect.top)
            list.scrollTop += irect.top - lrect.top - padding;

        // Scroll down
        if (irect.bottom + padding > lrect.bottom )
            list.scrollTop += irect.bottom - lrect.bottom + padding;
    }

    // Position the suggestions list
    positionSuggestions()
    {
        const location = this.container.querySelector("input.new").getBoundingClientRect();

        this.suggestions.style.top = `${location.bottom + window.scrollY}px`;
        this.suggestions.style.left = `${location.left + window.scrollX + 25}px`;
        this.suggestions.style.width = `${location.width - 25}px`;
        this.suggestions.style.visibility = "visible";
    }
}
