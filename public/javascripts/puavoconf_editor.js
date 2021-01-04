"use strict";

// PuavoConf editor v1.1

// Translations
const PC_STRINGS = {
    "en": {
        "new_placeholder": "Type in the name of the new key to be added...",
        "already_exists": "Key \"$(key)\" already exists",
        "accept_existing": "Create this key by pressing Enter or Tab",
        "accept_new": "Create a new key named \"$(key)\" by pressing Enter or Tab",
        "delete": "Delete this key",
        "show_raw": "Show editable JSON",
    },

    "fi": {
        "new_placeholder": "Kirjoita uuden lisättävän avaimen nimi...",
        "already_exists": "Avain \"$(key)\" on jo käytössä",
        "accept_existing": "Lisää tämä avain painamalla Enter tai Tab",
        "accept_new": "Luo uusi avain \"$(key)\" painamalla Enter tai Tab",
        "delete": "Poista tämä avain",
        "show_raw": "Näytä muokattava JSON",
    }
};

function translate(language, id, params={})
{
    if (!(language in PC_STRINGS))
        return `(Unknown string "${language}.${id}")`;

    const strings = PC_STRINGS[language];

    if (!(id in strings))
        return `(Unknown string "${language}.${id}")`;

    let s = strings[id].slice();

    // Any parameters?
    for (const p in params) {
        const name = `$(${p})`;

        s = s.replace(name, params[p]);
    }

    return s;
}

const CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789";

function randomString(length=10)
{
    const CHARS_LEN = CHARACTERS.length;
    let output = "";

    for (let i = 0; i < length; i++ )
        output += CHARACTERS.charAt(Math.floor(Math.random() * CHARS_LEN));

    return output;
}

// Creates a new HTML element and sets is attributes
function newElem(tag, params={})
{
    let e = document.createElement(tag);

    if (params.id)
        e.id = params.id;

    if (params.classes)
        e.className = params.classes.join(" ");

    if (params.contentHTML)
        e.innerHTML = params.contentHTML;

    if (params.contentText)
        e.innerText = params.contentText;

    if (params.innerText)
        e.appendChild(document.createTextNode(params.innerText));

    return e;
}

// Base class
class ConfigEntry {
    constructor(parent)
    {
        this.parent = parent;

        this.key = null;
        this.value = null;

        this.tableRowID = null;     // not known yet, will be set once the table is built
    }

    createEditor(container)
    {
    }

    valueChanged()
    {
        if (this.parent && this.key !== null)
            this.parent.entryHasChanged(this.key, this.value);
    }

    getValue()
    {
        // JSON allows NULLs, but puavo-conf wasn't built to like them much
        if (this.value === null || this.value === undefined)
            return "";

        return this.value;
    }
};

class ConfigString extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
    }

    createEditor(container)
    {
        let input = document.createElement("input");

        input.type = "text";
        input.value = this.value;
        input.addEventListener("input", event => this.onChange(event));

        container.appendChild(input);
    }

    onChange(event)
    {
        this.value = event.target.value;
        this.valueChanged();
    }
};

class ConfigJSON extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
        this.input = null;

        if (this.value === null || this.value === undefined) {
            // see above
            this.value = "";
        }
    }

    createEditor(container)
    {
        let input = document.createElement("textarea");

        input.classList.add("json");
        input.rows = 2;
        input.value = this.value;
        input.addEventListener("input", event => this.onChange(event));

        this.input = input;
        this.validate();

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
        let ok = true;

        try {
            JSON.parse(this.value);
        } catch (e) {
            ok = false;
        }

        // highlight invalid JSON
        if (ok)
            this.input.classList.remove("invalid");
        else this.input.classList.add("invalid");
    }
};

class ConfigBoolean extends ConfigEntry {
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

    clickedTrue(event)
    {
        this.value = true;
        this.valueChanged();
    }

    clickedFalse(event)
    {
        this.value = false;
        this.valueChanged();
    }

    createEditor(container)
    {
        const name = randomString();

        let tr = document.createElement("input");

        tr.type = "radio";
        tr.name = `boolean-${name}`;
        tr.id = `boolean-true-${name}`;
        tr.checked = this.value == true;
        tr.addEventListener("click", event => this.clickedTrue(event));

        let tl = document.createElement("label");

        tl.htmlFor = tr.id;
        tl.appendChild(document.createTextNode("True"));

        let fr = document.createElement("input");

        fr.type = "radio";
        fr.name = `boolean-${name}`;
        fr.id = `boolean-false-${name}`;
        fr.checked = this.value == false;
        fr.addEventListener("click", event => this.clickedFalse(event));

        let fl = document.createElement("label");

        fl.htmlFor = fr.id;
        fl.appendChild(document.createTextNode("False"));

        container.appendChild(tr);
        container.appendChild(tl);
        container.appendChild(fr);
        container.appendChild(fl);
    }

    getValue()
    {
        if (this.value === null || this.value === undefined)
            return "false";

        return this.value ? "true" : "false";
    }
};

class PuavoConfEditor
{
    constructor(params)
    {
        if (!params.prefix) {
            console.warn("PuavoConfEditor::ctor(): params.prefix does not exist, editor not created");
            return;
        }

        this.prefix = params.prefix;

        if (!params.container) {
            console.warn("PuavoConfEditor::ctor(): params.container is missing/invalid, editor not created");
            return;
        }

        this.editor = params.container.getElementsByClassName("pcEdit")[0];
        this.storage = params.container.getElementsByTagName("textarea")[0];

        if (!this.editor || !this.storage) {
            console.warn("PuavoConfEditor::ctor(): missing editor DIV or storage textarea, editor not created");
            return;
        }

        if (params.definitions)
            this.definitions = params.definitions;
        else {
            this.definitions = {};
            console.warn("PuavoConfEditor::ctor(): no puavoconf definitions given, autocomplete suggestions not available");
        }

        this.language = params.language || "en";

        this.suggestions = newElem(
            "div",
            {
                id: `${this.prefix}-autocomplete`,
                classes: ["pcSuggestions"]
            }
        );

        this.suggestionsList = [];      // a list of suggested puavo-conf entries

        this.entries = [];              // the actual things we're editing

        this.table = null;              // the table containing the entries

        this.showRaw = document.createElement("input");
        this.showRaw.type = "checkbox";
        this.showRaw.id = `${this.prefix}-showRaw`;
        this.showRaw.addEventListener("click", event => this.toggleRaw(event));

        this.rawLabel = document.createElement("label");
        this.rawLabel.innerText = translate(this.language, "show_raw");
        this.rawLabel.htmlFor = this.showRaw.id;

        this.storage.style.display = "none";
        this.load(this.storage.value, true);

        this.buildTable();

        this.editor.appendChild(this.table);
        this.editor.appendChild(this.showRaw);
        this.editor.appendChild(this.rawLabel);
        document.body.appendChild(this.suggestions);

        this.save();

        this.storage.addEventListener("input", event => this.rawEdited(event));
    }

    toggleRaw(event)
    {
        if (event.target.checked)
            this.storage.style.display = "initial";
        else this.storage.style.display = "none";
    }

    rawEdited(event)
    {
        const text = event.target.value;
        let parsed = null;

        try {
            parsed = JSON.parse(text);
        } catch (e) {
            event.target.classList.add("pcRawError");
            return;
        }

        event.target.classList.remove("pcRawError");

        // Rebuild the table (inefficient, but... eh)
        this.load(this.storage.value, false);
        this.buildTable();

        this.editor.innerHTML = "";
        this.editor.appendChild(this.table);
        this.editor.appendChild(this.showRaw);
        this.editor.appendChild(this.rawLabel);
    }

    findEntry(key)
    {
        for (let entry of this.entries)
            if (entry.key == key)
                return entry;

        return null;
    }

    createEntry(key, value)
    {
        let entry = null,
            type = null;

        if (key in this.definitions) {
            type = this.definitions[key].typehint;

            if (value === null || value === undefined) {
                if ("default" in this.definitions[key])
                    value = this.definitions[key]['default']
            }
        }

        switch (type) {
            case "string":
            default:        // assume unknown puavo-conf items are just plain strings
                entry = new ConfigString(this, key, value);
                break;

            case "json":
                entry = new ConfigJSON(this, key, value);
                break;

            case "bool":
                entry = new ConfigBoolean(this, key, value);
                break;
        }

        // Unique table row ID. When an entry is deleted, this is used to locate the table row
        // so it can be deleted without having to rebuild the whole table.
        entry.tableRowID = this.prefix + "-" + key;

        return entry;
    }

    // Loads the puavoconf data from the "storage" textarea
    load(puavoconf, initial)
    {
        let parsed = [];

        if (puavoconf && puavoconf.trim() != "") {
            try {
                parsed = JSON.parse(puavoconf);
            } catch (e) {
                console.error("parseConfig(): unable to parse puavo-conf string");
                console.error(e);
                console.log("The original puavo-conf string was:");
                console.log(puavoconf);
            }
        }

        // Sort the entries alphabetically. They're shown alhabetically, so
        // edit them alphabetically. New entries are added at the end, though.
        let keys = [];

        for (const key in parsed)
            keys.push(key);

        if (initial)
            keys.sort();

        this.entries = [];

        for (const key of keys)
            this.entries.push(this.createEntry(key, parsed[key]));
    }

    // Converts the entries to JSON and stores them in the textarea
    save()
    {
        let values = {};

        for (let e of this.entries)
            values[e.key] = e.getValue();

        // pretty-printed output
        this.storage.value = JSON.stringify(values, null, "\t");

        // It will be valid now, if someone hand-edited it
        this.storage.classList.remove("pcRawError");
    }

    buildTable()
    {
        let thead = document.createElement("thead");

        let tbody = document.createElement("tbody");

        // Existing entry rows
        for (let entry of this.entries)
            tbody.appendChild(this.createRowForExistingEntry(entry));

        // New entry row
        tbody.appendChild(this.createRowForNewEntry());

        this.table = document.createElement("table");
        this.table.appendChild(thead);
        this.table.appendChild(tbody);
    }

    createRowForExistingEntry(entry)
    {
        let buttonsCell = newElem("td", { classes: ["buttons"] }),
            keyCell = newElem("td", { classes: ["key"] }),
            valueCell = newElem("td", { classes: ["value"] });

        let deleteButton = document.createElement("a");

        deleteButton.classList.add("delete");
        deleteButton.innerHTML = "✖";
        deleteButton.title = translate(this.language, "delete");
        deleteButton.addEventListener("click", event => this.deleteRow(event));

        buttonsCell.appendChild(deleteButton);

        keyCell.innerText = entry.key;

        let form = document.createElement("div");

        form.classList.add("editor");

        entry.createEditor(form);
        valueCell.appendChild(form);

        let row = document.createElement("tr");

        row.id = entry.tableRowID;
        row.dataset.key = entry.key;

        row.appendChild(buttonsCell);
        row.appendChild(keyCell);
        row.appendChild(valueCell);

        return row;
    }

    createRowForNewEntry()
    {
        let row = document.createElement("tr");

        row.id = `${this.prefix}-newRow`;       // a special ID

        let cell = document.createElement("td");

        cell.colSpan = 3;

        let selector = document.createElement("input");

        selector.type = "text";
        selector.id = `${this.prefix}-newInput`;
        selector.classList.add("new");
        selector.placeholder = translate(this.language, "new_placeholder");
        selector.addEventListener("input", event => this.handleNewEntryInput(event));
        selector.addEventListener("keydown", event => this.handleNewEntryKeys(event));
        selector.addEventListener("focusin", event => this.handleNewEntryInput(event));

        // FIXME: If this is uncommented, then we cannot select entries from the list,
        // because clicking them immediately unfocuses the list and closes it BEFORE
        // the click event goes through.
        //selector.addEventListener("focusout", event => this.hideAutocomplete(event));

        cell.appendChild(selector);

        row.appendChild(cell);

        return row;
    }

    // Handles special keys in the entry name input box, like Tab, Enter and Esc
    handleNewEntryKeys(event)
    {
        if (event.keyCode == 9 || event.keyCode == 13) {    // Tab, Enter
            event.preventDefault();

            // Accept the first matching item
            let key = null;

            if (this.suggestionsList.length > 0)
                key = this.suggestionsList[0];
            else {
                // This key does not exist in the definitions, so it could be a completely
                // new puavoconf item
                key = event.target.value.trim();
            }

            if (key === null || key.length == 0)
                return;

            this.createNewEntry(key);
        } else if (event.keyCode == 40) {                   // Down arrow
            // List ALL available (no duplicates) keys
            this.listSuggestions(true);
        } else if (event.keyCode == 27) {                   // Esc
            // Temporarily hide the suggestions list
            this.hideSuggestions();
        }
    }

    // List and show matching suggestions
    handleNewEntryInput(event)
    {
        this.listSuggestions(false);
    }

    hideSuggestions(whatever=null)      // this is sometimes called from an event handler
    {
        this.suggestions.style.visibility = "hidden";
    }

    // Called from the value editors
    entryHasChanged(key, value)
    {
        this.save();
    }

    deleteRow(event)
    {
        const key = event.target.parentNode.parentNode.dataset.key

        // Locate the entry
        let entry = null,
            index = null;

        for (let i in this.entries) {
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
        document.getElementById(entry.tableRowID).remove();

        // Rebuild the autocomplete list if it was open
        if (this.suggestions.style.visibility == "visible")
            this.listSuggestions(true);

        document.getElementById(`${this.prefix}-newInput`).focus();

        this.save();
    }

    // Creates a new entry with the given name, and inserts it into the table.
    // A new "new entry" row is created below it.
    createNewEntry(key)
    {
        if (this.findEntry(key) !== null) {
            // no duplicates, please
            return;
        }

        this.hideSuggestions();
        this.suggestions.innerHTML = "";

        let entry = this.createEntry(key, null);
        this.entries.push(entry);

        // Remove the old input row, create a new entry row in its place,
        // then recreate the input row
        const newRowID = `${this.prefix}-newRow`;

        let entryRow = this.createRowForExistingEntry(entry),
            newRow = this.createRowForNewEntry();

        let tbody = this.table.getElementsByTagName('tbody')[0];

        document.getElementById(newRowID).remove();
        tbody.appendChild(entryRow);
        tbody.appendChild(newRow);

        document.getElementById(`${this.prefix}-newInput`).focus();

        this.save();
    }

    clickedSuggestion(event)
    {
        this.createNewEntry(event.target.dataset.key);
    }

    listSuggestions(showAll=false)
    {
        let newInput = document.getElementById(`${this.prefix}-newInput`);
        const needle = newInput.value.trim().toLowerCase();

        this.suggestionsList = [];

        let existing = new Set();

        // Find all matching definitions. Partial matches are enough.
        if (showAll || needle.length > 0) {
            for (const entry of this.entries)
                existing.add(entry.key);

            for (const key in this.definitions)
                if (!existing.has(key))
                    if (showAll || key.includes(needle))
                        this.suggestionsList.push(key);
        }

        if (!showAll && needle.length == 0) {
            // Nothing to show
            this.suggestions.style.visibility = "hidden";
            return;
        }

        this.suggestionsList.sort();

        this.suggestions.innerHTML = "";

        if (this.suggestionsList.length == 0) {
            // This is a completely new entry, we have no definition for it
            let e = document.createElement("div");

            if (existing.has(needle)) {
                // It's a duplicate
                e.innerHTML = translate(this.language, "already_exists", { "key": needle });
                e.classList.add("error");
            } else {
                e.innerHTML = translate(this.language, "accept_new", { "key": needle })
                e.classList.add("new");
            }

            this.suggestions.appendChild(e);
        } else {
            // Construct a list of matching items
            let first = true;

            for (const key of this.suggestionsList) {
                let e = document.createElement("div");

                e.classList.add("entry");

                e.dataset.key = key;
                e.addEventListener("click", event => this.clickedSuggestion(event));

                let html = "";

                if (showAll)
                    html = key;
                else {
                    // Highlight the matching part
                    const pos = key.indexOf(needle);

                    html =
                        key.substr(0, pos) +
                        `<span class="match">` + key.substr(pos, needle.length) + `</span>` +
                        key.substr(pos + needle.length);
                }

                if (first)
                    html += `<span class="hint">${translate(this.language, "accept_existing")}</span>`;

                e.innerHTML = html;

                this.suggestions.appendChild(e);
                first = false;
            }
        }

        // Position the suggestions list
        const location = newInput.getBoundingClientRect();

        this.suggestions.style.top = `${location.bottom + window.scrollY}px`;
        this.suggestions.style.left = `${location.left + window.scrollX}px`;
        this.suggestions.style.width = `${location.width}px`;
        this.suggestions.style.visibility = "visible";
    }
};
