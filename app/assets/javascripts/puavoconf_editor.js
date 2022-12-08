"use strict";

// Interactive PuavoConf editor v2.0

// Translations
const PC_STRINGS = {
    "en": {
        "new_placeholder": "Type in the name of the new key to be added...",
        "already_exists": "Key \"$(key)\" already exists",
        "accept_existing": "Create this key by pressing Enter or Tab",
        "accept_new": "Create a new key named \"$(key)\" by pressing Enter or Tab",
        "delete": "Delete this key",
        "show_raw": "Show editable JSON",
        "action_show": "Show",
        "action_hide": "Hide",
        "target_tag": "Tag",
        "target_category": "Category",
        "target_menu": "Menu",
        "target_program": "Program",
    },

    "fi": {
        "new_placeholder": "Kirjoita uuden lisättävän avaimen nimi...",
        "already_exists": "Avain \"$(key)\" on jo käytössä",
        "accept_existing": "Lisää tämä avain painamalla Enter tai Tab",
        "accept_new": "Luo uusi avain \"$(key)\" painamalla Enter tai Tab",
        "delete": "Poista tämä avain",
        "show_raw": "Näytä muokattava JSON",
        "action_show": "Näytä",
        "action_hide": "Piilota",
        "target_tag": "Tagi",
        "target_category": "Kategoria",
        "target_menu": "Valikko",
        "target_program": "Ohjelma",
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

    for (const p in params)
        s = s.replace(`$(${p})`, params[p]);

    return s;
}

// Generates random strings for radio button IDs
function randomID(length=10)
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

// Creates a new HTML element and sets is attributes
function create(tag, params={})
{
    let e = document.createElement(tag);

    if ("id" in params && params.id !== undefined)
        e.id = params.id;

    if ("name" in params && params.name !== undefined)
        e.name = params.name;

    if ("cls" in params && params.cls !== undefined) {
        if (Array.isArray(params.cls))
            e.className = params.cls.join(" ");
        else e.className = params.cls;
    }

    if ("html" in params && params.html !== undefined)
        e.innerHTML = params.html;

    if ("text" in params && params.text !== undefined)
        e.innerText = params.text;

    if ("textnode" in params && params.textnode !== undefined)
        e.appendChild(document.createTextNode(params.textnode));

    if ("inputType" in params && params.inputType !== undefined)
        e.type = params.inputType;

    if ("inputValue" in params && params.inputValue !== undefined)
        e.value = params.inputValue;

    return e;
}

// Base class for all entries
class ConfigEntry {
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
        throw new Error("Your derived class did not override ConfigEmtry::createEditor()!");
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

class ConfigString extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
    }

    createEditor(container)
    {
        let input = create("input", { inputType: "text", inputValue: this.value });

        input.addEventListener("input", event => this.onChange(event));
        container.appendChild(input);
    }

    onChange(event)
    {
        this.value = event.target.value;
        this.valueChanged();
    }
};

class ConfigPuavomenuTags extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
        this.container = null;

        // Created by calling load()
        this.tags = [];
    }

    createEditor(container)
    {
        let input = create("input", { inputType: "text", inputValue: this.value });

        input.addEventListener("input", event => this.onChange(event));
        container.appendChild(input);

        this.container = container;

        this.load();
        this.createDetails();
        this.explain();
        container.appendChild(this.details);
    }

    onChange(event)
    {
        this.value = event.target.value;
        this.load();
        this.explain();
        this.valueChanged();
    }

    load()
    {
        const TAG_SPLITTER = /,|;|\ /,
              TAG_MATCHER = /^(?<action>(\+|\-))?((?<namespace>c|cat|category|m|menu|p|prog|program|t|tag)\:)?(?<target>[a-zA-Z0-9\-_\.]+)$/;

        this.tags = [];

        for (const tag of (this.value === null ? "" : this.value.trim()).split(TAG_SPLITTER)) {
            if (tag.trim().length == 0)
                continue;

            const match = tag.match(TAG_MATCHER);

            if (!match) {
                // Invalid tag
                this.tags.push({
                    valid: false,
                    action: null,
                    namespace: null,
                    target: null
                });

                continue;
            }

            const action = (match.groups.action && match.groups.action == "-") ? "hide" : "show";
            let namespace = undefined;

            switch (match.groups.namespace) {
                case "c":
                case "cat":
                case "category":
                    namespace = "category";
                    break;

                case "m":
                case "menu":
                    namespace = "menu";
                    break;

                case "p":
                case "prog":
                case "program":
                    namespace = "program";
                    break;

                case undefined:     // unmatched regexp group ends up here too
                default:
                    namespace = "tag";
                    break;
            }

            // Valid tag
            this.tags.push({
                valid: true,
                action: action,
                namespace: namespace,
                target: match.groups.target
            });
        }
    }

    save(fullRebuild=false)
    {
        let tags = [];

        for (const t of this.tags) {
            if (!t.valid || !t.target)
                continue;

            let tag = [];

            if (t.action == "hide")
                tag.push("-");

            if (t.namespace == "tag") {
                // Pretty-print plain tag filters ("tag" is the default type)
                tag.push(t.target);
            } else {
                switch (t.namespace) {
                    case "tag":
                    default:
                        tag.push("t:");
                        break;

                    case "category":
                        tag.push("c:");
                        break;

                    case "menu":
                        tag.push("m:");
                        break;

                    case "program":
                        tag.push("p:");
                        break;
                }

                tag.push(t.target);
            }

            tags.push(tag.join(""));
        }

        this.value = tags.join(" ");
        this.container.querySelector("input").value = this.value;
        this.valueChanged(fullRebuild);
    }

    explain()
    {
        if (this.value === null || this.value.trim().length == 0 || this.tags.length == 0) {
            // Provide a new tag button
            this.details.innerHTML = `<button class="margin-top-10px margin-left-10px">+</button>`;
            this.details.querySelector("button").addEventListener("click", () => {
                this.tags.splice(0, 0, {
                    valid: true,
                    action: "show",
                    namespace: "tag",
                    target: "default"
                });

                this.save();
                this.explain();
            });

            return;
        }

        let html = `<table class="width-50p margin-top-10px margin-left-10px"><tbody>`;

        for (let i = 0; i < this.tags.length; i++)
            html += this._createRow(i);

        html += "</tbody></table>";
        this.details.innerHTML = html;

        const rows = this.details.querySelectorAll("table tbody tr");

        for (let i = 0; i < this.tags.length; i++) {
            const tag = this.tags[i],
                  row = rows[i];

            const action = row.querySelector("#action"),
                  namespace = row.querySelector("#namespace"),
                  target = row.querySelector("#target");

            action.value = tag.action;
            namespace.value = tag.namespace;

            if (tag.target)
                target.value = tag.target;

            if (!tag.valid)
                row.classList.add("invalid");

            action.addEventListener("change", (e) => this.onChangeAction(e));
            namespace.addEventListener("change", (e) => this.onChangeNamespace(e));
            target.addEventListener("input", (e) => this.onChangeTarget(e));

            row.querySelector("button#add").addEventListener("click", (e) => this.onAddTag(e));
            row.querySelector("button#delete").addEventListener("click", (e) => this.onDeleteTag(e));

            row.querySelector("button#up").disabled = (this.tags.length > 0 && i == 0);
            row.querySelector("button#up").addEventListener("click", (e) => this.onMoveTagUp(e));
            row.querySelector("button#down").disabled = (this.tags.length > 0 && i == this.tags.length - 1);
            row.querySelector("button#down").addEventListener("click", (e) => this.onMoveTagDown(e));
        }
    }

    revalidateTag(index)
    {
        const rows = this.details.querySelectorAll("table tbody tr");

        this.tags[index].valid = this._isValidTag(this.tags[index]);

        if (this.tags[index].valid)
            rows[index].classList.remove("invalid");
        else rows[index].classList.add("invalid");
    }

    onChangeAction(e)
    {
        const index = this._getIndex(e.target);

        this.tags[index].action = e.target.value;
        this.revalidateTag(index);
        this.save();
    }

    onChangeNamespace(e)
    {
        const index = this._getIndex(e.target);

        this.tags[index].namespace = e.target.value;
        this.revalidateTag(index);
        this.save();
    }

    onChangeTarget(e)
    {
        const index = this._getIndex(e.target);

        this.tags[index].target = e.target.value;
        this.revalidateTag(index);
        this.save();
    }

    onAddTag(e)
    {
        this.tags.splice(this._getIndex(e.target) + 1, 0, {
            valid: true,
            action: "show",
            namespace: "tag",
            target: "default"
        });

        this.save(true);
        this.explain();
    }

    onDeleteTag(e)
    {
        this.tags.splice(this._getIndex(e.target), 1);
        this.save(true);
        this.explain();
    }

    onMoveTagUp(e)
    {
        const index = this._getIndex(e.target);

        if (index == 0 || this.tags.length == 1)
            return;

        const t = this.tags[index - 1];

        this.tags[index - 1] = this.tags[index];
        this.tags[index] = t;

        this.save();
        this.explain();
    }

    onMoveTagDown(e)
    {
        const index = this._getIndex(e.target);

        if (index == this.tags.length - 1 || this.tags.length == 1)
            return;

        const t = this.tags[index + 1];

        this.tags[index + 1] = this.tags[index];
        this.tags[index] = t;

        this.save();
        this.explain();
    }

    _createRow(index)
    {
        let html =
`<tr data-index="${index}">
    <td>
        <select id="action">
            <option value="show">${translate(this.language, "action_show")}</option>
            <option value="hide">${translate(this.language, "action_hide")}</option>
        </select>
    </td>

    <td>
        <select id="namespace">
            <option value="tag">${translate(this.language, "target_tag")}</option>
            <option value="category">${translate(this.language, "target_category")}</option>
            <option value="menu">${translate(this.language, "target_menu")}</option>
            <option value="program">${translate(this.language, "target_program")}</option>
        </select>
    </td>

    <td>
        <input id="target" type="text" size="20" maxlength="100" pattern="[a-zA-Z0-9\-_\.]+">
    </td>

    <td class="width-0 nowrap">
        <button id="add">+</button>
        <button id="delete">-</button>
        <button id="up">↑</button>
        <button id="down">↓</button>
    </td>
</tr>`;

        return html;
    }

    _getIndex(node)
    {
        return parseInt(node.parentNode.parentNode.dataset.index, 10);
    }

    _isValidTag(tag)
    {
        if (tag.action === null)
            return false;

        if (tag.namespace === null)
            return false;

        if (tag.target === null || tag.target.trim().length == 0)
            return false;

        // Highlight tags whose target contains unacceptable characters
        if (tag.target.match(/[^a-zA-Z0-9\-_\.]/))
            return false;

        return true;
    }
};

class ConfigJSON extends ConfigEntry {
    constructor(parent, key, value)
    {
        super(parent);

        this.key = key;
        this.value = value;
        this.input = null;

        // a JSON puavoconf value can be empty, even if the JSON spec
        // does not allow that
        if (this.value === null || this.value === undefined)
            this.value = "";
    }

    createEditor(container)
    {
        let input = create("textarea", { cls: "json", inputValue: this.value });

        input.rows = 2;

        this.input = input;
        this.validate();

        input.addEventListener("input", event => this.onChange(event));
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
        // Highlight invalid JSON
        try {
            JSON.parse(this.value);
            this.input.classList.remove("invalid");
        } catch (e) {
            this.input.classList.add("invalid");
        }
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

    createEditor(container)
    {
        const tID = `true-${this.id}`,
              fID = `false-${this.id}`;

        container.innerHTML =
            `<input type="radio" id="${tID}" name="${this.id}"><label for="${tID}">True</label>` +
            `<input type="radio" id="${fID}" name="${this.id}"><label for="${fID}">False</label>`;

        container.querySelector(`#${tID}`).checked = (this.value == true);
        container.querySelector(`#${tID}`).addEventListener("click", () => {
            this.value = true;
            this.valueChanged();
        });

        container.querySelector(`#${fID}`).checked = (this.value == false);
        container.querySelector(`#${fID}`).addEventListener("click", () => {
            this.value = false;
            this.valueChanged();
        });
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

    if (params.definitions)
        this.definitions = params.definitions;
    else this.definitions = {};

    this.language = params.language || "en";

    this.container = params.container;

    this.storage = this.container.getElementsByTagName("textarea")[0];

    if (!this.storage) {
        this.container.innerHTML = "PuavoConfEditor::ctor(): missing storage textarea element, editor not created";
        return;
    }

    // Create the user interface
    this.container.innerHTML =
`<div class="pcEditorWrapper">
<table class="pcTable"></table>
<input class="new" type="text" maxlength="100" placeholder="${translate(this.language, "new_placeholder")}">
<div class="raw">
    <input type="checkbox" id="${this.prefix}-showRaw">
    <label for="${this.prefix}-showRaw">${translate(this.language, "show_raw")}</label>
</div>
</div>`;

    // Move the storage textarea inside the DIV
    this.storage.style.display = "none";
    this.storage.addEventListener("input", () => this.rawEdited());
    this.container.querySelector("div.pcEditorWrapper").appendChild(this.storage);

    // UI handles
    this.table = this.container.querySelector("table.pcTable");
    this.newInput = this.container.querySelector("input.new");

    this.newInput.addEventListener("input", () => this.handleNewEntryInput());
    this.newInput.addEventListener("keydown", e => this.handleNewEntryKeys(e));

    this.container.querySelector(`div.raw input`).addEventListener("click", e => {
        this.storage.style.display = e.target.checked ? "initial" : "none";
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

    // Something changed so drastically in the editor that we need to
    // reposition the suggestions list if it's open
    if (fullRebuild && this.suggestionsList.length > 0 && this.currentSuggestion != -1)
        this.positionSuggestions();
}

// Adds a new editable puavo-conf entry. All entries have an internal "editor"
// class attached to them; the class handles the editing interface in the table.
createEntry(key, value)
{
    let entry = null,
        type = null;

    // Find the type and a possible default value for this entry
    if (key in this.definitions) {
        type = this.definitions[key].typehint;

        if (value === null || value === undefined) {
            if ("default" in this.definitions[key])
                value = this.definitions[key]["default"]
        }
    }

    // Handle special editors (exact key matches)
    if (key == "puavo.puavomenu.tags")
        return new ConfigPuavomenuTags(this, key, value);

    // Build a type-specific editor. Assume unknown puavo-conf items
    // are just plain strings.
    switch (type) {
        case "string":
        default:
            return new ConfigString(this, key, value);

        case "json":
            return new ConfigJSON(this, key, value);

        case "bool":
            return new ConfigBoolean(this, key, value);
    }
}

buildTable()
{
    let tbody = document.createElement("tbody");

    for (let entry of this.entries)
        tbody.appendChild(this._createEntryRow(entry));

    this.table.innerHTML = "";
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

    this.newInput.focus();
}

// Creates a new entry with the given name, and inserts it into the table.
// A new "new entry" row is created below it.
createNewEntry(key)
{
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
    this.newInput.focus();

    this.save();
}

_createEntryRow(entry)
{
    let buttons = create("td", { cls: "buttons" }),
        key = create("td", { cls: "key", text: entry.key }),
        value = create("td", { cls: "value" });

    let deleteButton = create("button", { cls: "delete", text: "✖" });

    deleteButton.title = translate(this.language, "delete");
    deleteButton.addEventListener("click", e => this.deleteRow(e));
    buttons.appendChild(deleteButton);

    // Editor container DIV
    let form = create("div", { cls: "editor" });

    entry.createEditor(form);
    value.appendChild(form);

    let row = create("tr", { id: entry.id });

    row.dataset.key = entry.key;

    row.appendChild(buttons);
    row.appendChild(key);
    row.appendChild(value);

    return row;
}

// Handles special keys in the entry name input box
handleNewEntryKeys(event)
{
    const previous = this.currentSuggestion;

    switch (event.code) {
        // Accept the selected item
        case "Tab":
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

            if (key === null || key.length == 0)
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

        // Scroll down
        case "ArrowDown":
            event.preventDefault();

            if (this.suggestionsList.length == 0) {
                const needle = this.newInput.value.trim().toLowerCase();

                if (needle.length == 0) {
                    this.buildSuggestions();
                    break;
                }
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

                console.log(delta);

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
    const needle = this.newInput.value.trim().toLowerCase();
    const showAll = needle.length == 0;

    this.suggestionsList = [];
    this.currentSuggestion = -1;

    let existing = new Set();

    // Find all matching definitions. Partial matches are enough.
    if (showAll || needle.length > 0) {
        for (const entry of this.entries)
            existing.add(entry.key);

        for (const key in this.definitions)
            if (!existing.has(key) && (showAll || key.includes(needle)))
                this.suggestionsList.push(key);
    }

    this.suggestionsList.sort();

    this.suggestions.innerHTML = "";

    if (this.suggestionsList.length == 0) {
        // This is a completely new entry, we have no definition for it
        const duplicate = existing.has(needle);

        let newEntry = create("div", {
            text: translate(this.language, duplicate ? "already_exists" : "accept_new", { "key": needle }),
            cls: duplicate ? "error" : "new"
        });

        newEntry.addEventListener("click", e => this.createNewEntry(needle));

        this.suggestions.appendChild(newEntry);
    } else {
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
    }

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
    this.suggestions.style.width = `${location.width-25}px`;
    this.suggestions.style.visibility = "visible";
}

};  // class PuavoConfEditor
