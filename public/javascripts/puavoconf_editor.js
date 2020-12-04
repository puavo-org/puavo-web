"use strict";

// Translations
const PC_STRINGS = {
    "en": {
        "new_placeholder": "Type in the name of the new key to be added...",
        "already_exists": "Key \"$(key)\" already exists",
        "accept_existing": "Create this key by pressing Enter or Tab",
        "accept_new": "Create a new key named \"$(key)\" by pressing Enter or Tab",
        "no_suggestions": "No key name suggestions available",
        "delete": "Delete this key",
    },

    "fi": {
        "new_placeholder": "Kirjoita uuden lisättävän avaimen nimi...",
        "already_exists": "Avain \"$(key)\" on jo käytössä",
        "accept_existing": "Lisää tämä avain painamalla Enter tai Tab",
        "accept_new": "Luo uusi avain \"$(key)\" painamalla Enter tai Tab",
        "no_suggestions": "Avaimen nimiehdotuksia ei ole tarjolla",
        "delete": "Poista tämä avain",
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
    constructor(prefix, container, storage, definitions, language="en")
    {
        this.prefix = prefix;
        this.container = container;
        this.storage = storage;
        this.definitions = definitions;
        this.language = language;

        this.tableEntries = [];                 // "nice" entries of the current table rows
        this.autocomplete = null;               // parent element for the autocomplete overlay
        this.matches = [];                      // autocomplete matches

        // Replace the textarea with us
        this.storage.style.display = "none";
        this.load(this.storage.value);

        this.buildTable();

        this.autocomplete = document.createElement("div");
        this.autocomplete.id = `${this.prefix}-autocomplete`;
        this.autocomplete.classList.add("pcAutocomplete");

        this.container.innerHTML = "";
        this.container.appendChild(this.table);
        document.body.appendChild(this.autocomplete);

        this.save();
    }

    findEntry(key)
    {
        for (let entry of this.tableEntries)
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
    load(puavoconf)
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

        keys.sort();

        this.tableEntries = [];

        for (const key of keys)
            this.tableEntries.push(this.createEntry(key, parsed[key]));
    }

    // Converts the entries to JSON and stores them in the textarea
    save()
    {
        let values = {};

        for (let e of this.tableEntries)
            values[e.key] = e.getValue();

        // pretty-printed output
        this.storage.value = JSON.stringify(values, null, "\t");
    }

    hideAutocomplete(whatever=null)     // this is sometimes called from an event handler
    {
        this.autocomplete.style.visibility = "hidden";
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

        for (let i in this.tableEntries) {
            if (this.tableEntries[i].key == key) {
                entry = this.tableEntries[i];
                index = i;
                break;
            }
        }

        if (entry === null)
            return;

        // Nuke it
        this.tableEntries.splice(index, 1);
        document.getElementById(entry.tableRowID).remove();

        // Rebuild the autocomplete list if it was open
        if (this.autocomplete.style.visibility == "visible")
            this.listMatchingEntries();

        document.getElementById(`${this.prefix}-newInput`).focus();

        this.save();
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

        // Add some wbr tags to aid the browser in wrapping long lines.
        // Can't use &shy; markers, because that would add fake "-" characters
        // to the strings and that's a big no-no.
        let s = entry.key.slice();

        keyCell.innerHTML = s.replace(".", ".<wbr>").replace("_", "_<wbr>");

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
        selector.addEventListener("input", event => this.handleAutocompleteInput(event));
        selector.addEventListener("keydown", event => this.handleAutocompleteKeys(event));
        selector.addEventListener("focusin", event => this.handleAutocompleteInput(event));

        // FIXME: If this is uncommented, then we cannot select entries from the list,
        // because clicking them immediately unfocuses the list and closes it BEFORE
        // the click event goes through.
        //selector.addEventListener("focusout", event => this.hideAutocomplete(event));

        cell.appendChild(selector);

        row.appendChild(cell);

        return row;
    }

    // Creates a new entry with the given name, and inserts it into the table.
    // A new "new entry" row is created below it.
    createNewEntry(key)
    {
        if (this.findEntry(key) !== null) {
            // no duplicates, please
            return;
        }

        this.hideAutocomplete();
        this.autocomplete.innerHTML = "";

        let entry = this.createEntry(key, null);
        this.tableEntries.push(entry);

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

    // Handles special keys in the entry name input box, like Tab, Enter and Esc
    handleAutocompleteKeys(event)
    {
        if (event.keyCode == 9 || event.keyCode == 13) {    // Tab, Enter
            event.preventDefault();

            // Accept the first matching item
            let key = null;

            if (this.matches.length > 0)
                key = this.matches[0];
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
            this.listMatchingEntries(true);
        } else if (event.keyCode == 27) {                   // Esc
            // Temporarily hide the autocomplete list
            this.hideAutocomplete();
        }
    }

    handleAutocompleteInput(event)
    {
        this.listMatchingEntries(false);
    }

    clickedMatchingEntry(event)
    {
        this.createNewEntry(event.target.dataset.key);
    }

    listMatchingEntries(showAll=false)
    {
        let newInput = document.getElementById(`${this.prefix}-newInput`);
        const needle = newInput.value.trim().toLowerCase();

        this.matches = [];

        let existing = new Set();

        // Find all matching definitions. Partial matches are enough.
        if (showAll || needle.length > 0) {
            for (const entry of this.tableEntries)
                existing.add(entry.key);

            for (const key in this.definitions)
                if (!existing.has(key))
                    if (showAll || key.includes(needle))
                        this.matches.push(key);
        }

        if (!showAll && needle.length == 0) {
            // Nothing to show
            this.autocomplete.style.visibility = "hidden";
            return;
        }

        this.matches.sort();

        let outer = null;

        if (this.matches.length == 0) {
            // This is a completely new entry, we have no definition for it
            outer = document.createElement("div");

            outer.classList.add("new");

            if (existing.has(needle)) {
                // ...aaaand it's a duplicate
                outer.innerHTML = translate(this.language, "already_exists", { "key": needle });
                outer.classList.add("error");
            } else {
                if (needle.length == 0)
                    outer.innerHTML = translate(this.language, "no_suggestions")
                else outer.innerHTML = translate(this.language, "accept_new", { "key": needle })
            }
        } else {
            // Construct a list of matching items
            outer = document.createElement("ul");

            let first = true;

            for (const key of this.matches) {
                let elem = document.createElement("a");

                elem.dataset.key = key;
                elem.addEventListener("click", event => this.clickedMatchingEntry(event));

                let html = "";

                if (showAll) {
                    html = key;
                } else {
                    // Highlight the matching part
                    const pos = key.indexOf(needle);

                    html =
                        key.substr(0, pos) +
                        `<span class="match">` + key.substr(pos, needle.length) + `</span>` +
                        key.substr(pos + needle.length);
                }

                if (first)
                    html += `<span class="hint">${translate(this.language, "accept_existing")}</span>`;

                elem.innerHTML = html;

                let li = document.createElement("li");

                li.appendChild(elem);
                outer.appendChild(li);

                first = false;
            }
        }

        if (this.autocomplete.firstChild)
            this.autocomplete.firstChild.remove();

        this.autocomplete.appendChild(outer);

        // Position and display the autocomplete match list
        const location = newInput.getBoundingClientRect();

        this.autocomplete.style.top = `${location.bottom + window.scrollY}px`;
        this.autocomplete.style.left = `${location.left + window.scrollX}px`;
        this.autocomplete.style.width = `${location.width}px`;
        this.autocomplete.style.visibility = "visible";
    }

    buildTable()
    {
        let thead = document.createElement("thead");

        let tbody = document.createElement("tbody");

        // Existing entry rows
        for (let entry of this.tableEntries)
            tbody.appendChild(this.createRowForExistingEntry(entry));

        // Initial new entry row
        tbody.appendChild(this.createRowForNewEntry());

        this.table = document.createElement("table");
        this.table.appendChild(thead);
        this.table.appendChild(tbody);
    }
};
