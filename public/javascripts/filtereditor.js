"use strict;"

// Datetime filter year limits. The years are limited because values outside
// of these are unlikely to appear in the database.
const MIN_YEAR = 2000,
      MAX_YEAR = 2050;

// Base filter editor class
class FilterEditBase {
    constructor(container)
    {
        this.container = container;
    }

    validate()
    {
        // If you return false, the filter being edited cannot be saved
        return true;
    }

    setValue()
    {
    }

    getValue()
    {
        return null;
    }
};

class FilterEditBool extends FilterEditBase {
    constructor(container)
    {
        super(container);

        let html = "";

        html += `<input type="radio" name="type" id="filter-bool-true" checked><label for="filter-bool-true">${_tr('filter_editor.editor.bool_true')}</label><br>`;
        html += `<input type="radio" name="type" id="filter-bool-false"><label for="filter-bool-false">${_tr('filter_editor.editor.bool_false')}</label>`;

        this.container.innerHTML = html;
    }

    setValue(value)
    {
        const v = Array.isArray(value) ? value[0] : value;

        this.container.querySelector("input#filter-bool-true").checked = (v === true);
        this.container.querySelector("input#filter-bool-false").checked = (v !== true);
    }

    getValue()
    {
        return this.container.querySelector("input#filter-bool-true").checked;
    }
};

class FilterEditInteger extends FilterEditBase {
    constructor(container)
    {
        super(container);

        let html = "";

        html += `<input type="text" id="filter-number-value" style="width: 100%;" placeholder="Numeerinen arvo">`;
        html += "<p>" + _tr('filter_editor.editor.integer_help') + "</p>";

        this.container.innerHTML = html;
    }

    validate()
    {
        let input = this.container.querySelector("input#filter-number-value");

        if (input.value.trim().length == 0) {
            window.alert(_tr('filter_editor.editor.integer_missing_value'));
            return false;
        }

        return true;
    }

    setValue(value)
    {
        let input = this.container.querySelector("input#filter-number-value");

        // Allow multiple values
        if (Array.isArray(value))
            input.value = value.join("|");
        else input.value = value;
    }

    getValue()
    {
        // Since multiple values are allowed, we must split and clean the string
        const raw = this.container.querySelector("input#filter-number-value").value.trim().split("|");
        let clean = [];

        for (const n of raw) {
            if (n === null || n == "")
                continue;

            try {
                parseInt(n, 10);
            } catch (e) {
                continue;
            }

            clean.push(parseInt(n, 10));
        }

        return clean;
    }
};

class FilterEditFloat extends FilterEditInteger {
    constructor(container)
    {
        super(container);
    }

    getValue()
    {
        // Again, multiple values are allowed, so do some cleanup
        const raw = this.container.querySelector("input#filter-number-value").value.trim().split("|");
        let clean = [];

        for (const n of raw) {
            if (n === null || n == "")
                continue;

            // floats require more logic than integers (all numbers are floats in JS anyway...)
            if (isNaN(n))
                continue;

            const f = parseFloat(n);

            if (f === NaN || f === Infinity)
                continue;

            clean.push(parseFloat(n));
        }

        return clean;
    }
};

class FilterEditUnixtime extends FilterEditBase {
    constructor(container)
    {
        super(container);

        let html = "";

        html += `<input type="radio" name="type" id="filter-time-absolute" checked><label for="filter-time-absolute">${_tr('filter_editor.editor.time_absolute')}</label><br>`;
        html += `<div class="margin-left-25 margin-top-5">`;
        html += `<input type="text" id="filter-time-absolute-value" maxlength="19" size="20" placeholder="${_tr('filter_editor.editor.time_placeholder')}">`;
        html += ` <button id="absoluteTimeHelp">${_tr('help')}</button>`;
        html += `</div><br>`;
        html += `<input type="radio" name="type" id="filter-time-relative"><label for="filter-time-relative">${_tr('filter_editor.editor.time_relative')}</label><br>`;
        html += `<div class="margin-left-25 margin-top-5">`;
        html += `<table>`;
        html += `<tr><td><label for="filter-time-rel-amount">${_tr('filter_editor.editor.time_relative_title')}</label></td>`;
        html += `<td><input type="number" size="15" id="filter-time-relative-value" placeholder="0"> <button id="relativeTimeHelp">${_tr('help')}</button></td></tr>`;
        html += `<tr><td><label for="filter-time-presets">${_tr('filter_editor.editor.time_presets')}</label></td><td><select id="filter-time-presets">`;
        html += `<option disabled hidden selected>${_tr('selected')}</option>`;
        html += `<option data-value="-3600">${_tr('filter_editor.editor.time_preset.hours1')}</option>`;
        html += `<option data-value="-43200">${_tr('filter_editor.editor.time_preset.hours12')}</option>`;
        html += `<option data-value="-86400">${_tr('filter_editor.editor.time_preset.day1')}</option>`;
        html += `<option data-value="-604800">${_tr('filter_editor.editor.time_preset.week1')}</option>`;
        html += `<option data-value="-2592000">${_tr('filter_editor.editor.time_preset.days30')}</option>`;
        html += `<option data-value="-5184000">${_tr('filter_editor.editor.time_preset.days60')}</option>`;
        html += `<option data-value="-7776000">${_tr('filter_editor.editor.time_preset.days90')}</option>`;
        html += `<option data-value="-15552000">${_tr('filter_editor.editor.time_preset.days180')}</option>`;
        html += `<option data-value="-23328000">${_tr('filter_editor.editor.time_preset.days270')}</option>`;
        html += `<option data-value="-31536000">${_tr('filter_editor.editor.time_preset.days365')}</option>`;
        html += `</select></td></tr></table>`;
        html += `</div>`;

        this.container.innerHTML = html;

        this.container.querySelector("select#filter-time-presets").addEventListener("change",
            (e) => this.setRelativeTime(e));

        this.container.querySelector("button#absoluteTimeHelp").addEventListener("click",
            (e) => this.showHelp('filter_editor.editor.time_absolute_help'));

        this.container.querySelector("button#relativeTimeHelp").addEventListener("click",
            (e) => this.showHelp('filter_editor.editor.time_direction'));
    }

    showHelp(id)
    {
        window.alert(_tr(id));
    }

    setRelativeTime(selector)
    {
        this.container.querySelector("input#filter-time-relative-value").value =
            event.target[event.target.selectedIndex].dataset.value;
    }

    validate()
    {
        if (this.container.querySelector("input#filter-time-absolute").checked) {
            const v = this.container.querySelector("input#filter-time-absolute-value").value;

            if (v.trim().length == 0) {
                window.alert(_tr('filter_editor.editor.time_missing_absolute'));
                return false;
            }

            const d = parseAbsoluteOrRelativeDate(v);

            if (d === null) {
                window.alert(_tr('filter_editor.editor.time_invalid_absolute'));
                return false;
            }

            if (d.getFullYear() < MIN_YEAR || d.getFullYear() > MAX_YEAR) {
                window.alert(I18n.translate('filter_editor.editor.time_invalid_absolute_year', {min: MIN_YEAR, max: MAX_YEAR}));
                return false;
            }
        } else {
            let v = this.container.querySelector("input#filter-time-relative-value").value;

            if (v.trim().length == 0) {
                window.alert(_tr('filter_editor.editor.time_missing_relative'));
                return false;
            }

            v = parseInt(v, 10)

            const d = parseAbsoluteOrRelativeDate(v);

            if (d === null) {
                window.alert(_tr('filter_editor.editor.time_invalid_relative'));
                return false;
            }

            if (d.getFullYear() < MIN_YEAR || d.getFullYear() > MAX_YEAR) {
                window.alert(I18n.translate('filter_editor.editor.time_invalid_relative_year', {min: MIN_YEAR, max: MAX_YEAR, full: d.getFullYear()}));
                return false;
            }
        }

        return true;
    }

    setValue(value)
    {
        const v = Array.isArray(value) ? value[0] : value;

        if (typeof(v) == "string") {
            this.container.querySelector("input#filter-time-absolute").checked = true;
            this.container.querySelector("input#filter-time-absolute-value").value = value;
        } else if (typeof(v) == "number") {
            this.container.querySelector("input#filter-time-relative").checked = true;
            this.container.querySelector("input#filter-time-relative-value").value = parseInt(v, 10);
        } else {
            // Don't know what this is, reset to some sane default
            this.container.querySelector("input#filter-time-absolute").checked = true;
        }
    }

    getValue()
    {
        if (this.container.querySelector("input#filter-time-absolute").checked) {
            return this.container.querySelector("input#filter-time-absolute-value").value.trim();
        } else {
            return parseInt(
                this.container.querySelector("input#filter-time-relative-value").value, 10);
        }
    }
};

class FilterEditString extends FilterEditBase {
    constructor(container)
    {
        super(container);

        let html = "";

        html += `<input type="text" id="filter-string-value" style="width: 100%;" placeholder="Regexp-arvo">`;
        html += "<p>" + _tr('filter_editor.editor.string_help') + "</p>";

        this.container.innerHTML = html;
    }

    setValue(value)
    {
        this.container.querySelector("input#filter-string-value").value =
            Array.isArray(value) ? value[0] : value;
    }

    getValue()
    {
        return this.container.querySelector("input#filter-string-value").value;
    }
};

class FilterEditor {

constructor(parentClass, container, columnDefinitions, columnTitles, defaultColumn)
{
    // Who do we tell about filter changes?
    this.parentClass = parentClass;

    // This container is our playground. Everything we put on the screen, it's
    // inside this HTML element.
    this.container = container;

    // Definitions
    this.columnDefinitions = columnDefinitions;
    this.columnTitles = columnTitles;
    this.defaultColumn = defaultColumn;

    this.ui = {
        deleteAll: null,
        jsonToggle: null,
        jsonSave: null,
        jsonEditor: null,
        filterTable: null,
    };

    this.showJSON = false;

    // Data
    this.columns = [];
    this.columnNames = [];
    this.filters = [];

    this.editFilterIndex = null;
    this.editFilter = null;
    this.editedFilterRow = null;

    this.disabled = true;

    // The editor popup
    this.editor = {
        backdrop: null,     // modal backdrop (prevents interaction with the page)
        popup: null,        // the popup container
        column: null,       // the column selector
        operator: null,     // the operator selector
        child: null,        // the per-type child editor wrapper DIV
        childEditor: null,  // the per-type child editor/validator object
    };

    this.buildUI();
    this.disabled = false;
}

buildUI()
{
    let html = "";

    html += `<div class="mainButtons">`;
    html += `<button id="filter-delete-all" title="${_tr('filter_editor.delete_all_title')}">${_tr('filter_editor.delete_all')}</button>`;
    html += `<button id="filter-json-toggle" title="${_tr('filter_editor.toggle_json_title')}">${_tr('filter_editor.show_json')}</button>`;
    html += `<button id="filter-json-save" title="${_tr('filter_editor.save_json_title')}">${_tr('filter_editor.save_json')}</button>`;
    html += `</div>`;
    html += `<div class="jsonEditor">`;
    html += `<textarea rows="10"></textarea>`;
    html += `</div>`;
    html += `<div class="tableWrapper"></div>`;    // this DIV is where the filter table is placed in

    this.container.innerHTML = html;

    this.ui.deleteAll = this.container.querySelector("button#filter-delete-all");
    this.ui.jsonToggle = this.container.querySelector("button#filter-json-toggle");
    this.ui.jsonSave = this.container.querySelector("button#filter-json-save");
    this.ui.jsonEditor = this.container.querySelector("textarea");
    this.ui.filterTable = this.container.querySelector("div.tableWrapper");

    this.ui.deleteAll.disabled = true;
    this.ui.jsonToggle.disabled = true;

    this.ui.jsonSave.disabled = true;
    this.ui.jsonEditor.style.display = "none";
    this.ui.jsonSave.style.display = "none";

    this.ui.deleteAll.addEventListener("click", () => this.deleteAllFilters());
    this.ui.jsonToggle.addEventListener("click", () => this.toggleJSONEditor());
    this.ui.jsonSave.addEventListener("click", () => this.saveJSONFilters());
    this.ui.jsonEditor.addEventListener("input", () => this.validateJSONFilters());
}

enable()
{
    this.ui.deleteAll.disabled = false;
    this.ui.jsonToggle.disabled = false;
    this.disabled = false;
}

disable()
{
    this.ui.deleteAll.disabled = true;
    this.ui.jsonToggle.disabled = true;
    this.disabled = true;
}

// Notify the supertable that we have new filters for it
notifyParentClass()
{
    this.parentClass.setFilters(this.getFilters(), true);
    this.parentClass.filtersHaveChanged();
}

setColumns(columns)
{
    this.columns = columns;

    // Sort the columns by their localized names (they look nicer in the column selector
    // when they're sorted alphabetically)
    this.columnNames = [];

    for (const name of Object.keys(this.columnDefinitions))
        this.columnNames.push([name, this.columnTitles[name]]);

    this.columnNames.sort((a, b) => { return a[1].localeCompare(b[1]) });

    this.validateFilters();
    this.buildFilterTable();
    this.updateJSON();
}

loadFilters(filters, append)
{
    if (!append)
        this.filters = [];

    if (Array.isArray(filters)) {
        // Convert the filters into "cooked" format. They contain the same data, but
        // there are extra fields used for use in the editor.
        for (const filter of filters) {
            this.filters.push({
                ...filter,
                valid: false,
                columnValid: false,
                displayValue: null,
            });
        }
    }

    this.validateFilters();
    this.buildFilterTable();
    this.updateJSON();
}

getFilters()
{
    let plainFilters = [];

    // "Uncook" the filters, ie. the opposite of loadFilters()
    for (const filter of this.filters) {
        plainFilters.push({
            active: filter.valid && filter.active,
            column: filter.column,
            operator: filter.operator,
            value: filter.value,
        });
    }

    return plainFilters;
}

validateFilters()
{
    let validColumns = new Set();

    for (const c of this.columns)
        validColumns.add(c);

    for (let i = 0; i < this.filters.length; i++) {
        let filter = this.filters[i];

        // Assume all filters are valid until proven otherwise
        filter.valid = true;
        filter.columnValid = true;
        filter.displayValue = filter.value;

        if (!(filter.column in this.columnDefinitions)) {
            //console.warn(`validateFilters(): filter target column "${filter.column}" is not valid`);
            filter.valid = false;
            continue;
        }

        // Do some pretty printing
        const def = this.columnDefinitions[filter.column];

        if (filter.value === null) {
            filter.displayValue = "?";
            filter.valid = false;
        } else {
            switch (def.type) {
                case ColumnType.BOOL:
                    filter.displayValue = filter.value ? _tr('filter_editor.editor.bool_true') : _tr('filter_editor.editor.bool_false');
                    break;

                case ColumnType.UNIXTIME:
                {
                    const date = parseAbsoluteOrRelativeDate(filter.value);

                    if (date === null || date.getFullYear() < MIN_YEAR || date.getFullYear() > MAX_YEAR) {
                        // It wasn't valid, show the raw value
                        filter.valid = false;
                        filter.displayValue = filter.value;
                    } else {
                        filter.valid = true;
                        filter.displayValue = padDateTime(date);
                    }

                    break;
                }

                case ColumnType.INTEGER:
                case ColumnType.FLOAT:
                    // Currently this is the only place where multiple values are actually allowed.
                    // Regexps allow multiple values separated with |'s, so imitate that style here.
                    if (Array.isArray(filter.displayValue))
                        filter.displayValue = filter.displayValue.join("|");

                    break;

                case ColumnType.STRING: {
                    let v = filter.value.toString().trim();

                    if (v.length == 0 || v == "^$")
                        v = _tr('empty');

                    filter.displayValue = v;

                    break;
                }

                default:
                    break;
            }
        }

        if (!validColumns.has(filter.column)) {
            //console.warn(`validateFilters(): column "${filter.column}" is not visible`);
            filter.columnValid = false;
        }
    }
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// THE JSON EDITOR

updateJSON()
{
    let parts = [];

    // "Slightly" pretty-printed format, construct the JSON manually, line by line, so
    // every row contains one filter.
    for (const filter of this.filters) {
        parts.push(JSON.stringify({
            active: filter.active && filter.valid,
            column: filter.column,
            operator: filter.operator,
            value: filter.value,
        }));
    }

    this.ui.jsonEditor.value = "[" + parts.join(",\n") + "]";
}

// Open/close the JSON filter editor
toggleJSONEditor()
{
    if (!this.showJSON) {
        this.ui.jsonToggle.innerText = _tr('filter_editor.hide_json');
        this.ui.jsonEditor.style.display = "block";
        this.ui.jsonSave.style.display = "inline-block";
        this.ui.jsonSave.disabled = false;
        this.showJSON = true;
    } else {
        this.ui.jsonToggle.innerText = _tr('filter_editor.show_json');
        this.ui.jsonEditor.style.display = "none";
        this.ui.jsonSave.style.display = "none";
        this.ui.jsonSave.disabled = true;
        this.showJSON = false;
    }
}

// Called whenever the contents of the JSON textarea changes
validateJSONFilters()
{
    let valid = true;

    try {
        JSON.parse(this.ui.jsonEditor.value);
    } catch (e) {
        valid = false;
    }

    if (valid) {
        this.ui.jsonEditor.classList.remove("invalidJSON");
        this.ui.jsonSave.disabled = false;
    } else {
        this.ui.jsonEditor.classList.add("invalidJSON");
        this.ui.jsonSave.disabled = true;
    }
}

// Loads the JSON filters from the textarea and saves them
saveJSONFilters()
{
    let parsed = null;
    let newFilters = [];

    try {
        parsed = JSON.parse(this.ui.jsonEditor.value);
    } catch (e) {
        window.alert(_tr('filter_editor.invalid_json') + "\n\n" + e);
        return;
    }

    if (!Array.isArray(parsed)) {
        window.alert(_tr('filter_editor.not_an_array'));
        return;
    }

    const validOperators = new Set([
        FilterOperator.EQU,
        FilterOperator.NEQ,
        FilterOperator.LT,
        FilterOperator.LTE,
        FilterOperator.GT,
        FilterOperator.GTE,
    ]);

    for (const row of parsed) {
        if (typeof(row) != "object" || !("column" in row) || !("operator" in row) || !("value" in row)) {
            window.alert(_tr('filter_editor.data_requirements'));
            return;
        }

        if (!(row.column in this.columnDefinitions)) {
            window.alert(I18n.translate('filter_editor.invalid_column', {column: row.column}));
            return;
        }

        if (!validOperators.has(row.operator)) {
            window.alert(I18n.translate('filter_editor.invalid_operator', {operator: row.operator}));
            return;
        }

        // Is this operator available for this column type?
        const def = this.columnDefinitions[row.column];

        let available = false,
            operatorTitle = "?";

        for (const op of OPERATOR_DEFINITIONS) {
            if (op.operator == row.operator) {
                operatorTitle = op.title;

                if (op.availableFor.has(def.type)) {
                    available = true;
                    break;
                }
            }
        }

        if (!available) {
            window.alert(I18n.translate('filter_editor.column_type_mismatch',
                         {operator: row.operator, title: operatorTitle, column: row.column}));
            return;
        }

        // Only integers and floats support arrays of values
        if (Array.isArray(row.value)) {
            let type = "";
            let valid = false;

            switch (def.type) {
                case ColumnType.STRING:
                default:
                    break;

                case ColumnType.UNIXTIME:
                    type = "Time";
                    break;

                case ColumnType.BOOL:
                    type = "Boolean";
                    break;

                case ColumnType.INTEGER:
                case ColumnType.FLOAT:
                    valid = true;
                    break;
            }

            if (!valid) {
                if (def.type == ColumnType.STRING)
                    window.alert(_tr('filter_editor.use_regexps'));
                else window.alert(I18n.translate('filter_editor.only_one_value', {type: type}));

                return false;
            }
        }

        // It's good, store
        let f = {
            active: false,
            column: row.column,
            operator: row.operator,
            value: row.value,
        };

        if ("active" in row)
            f.active = row.active;

        newFilters.push(f);
    }

    // Save the filters. Do NOT call updateJSON() here because that will overwrite the
    // textarea contents with the loaded filters and there could be differences!
    this.filters = newFilters;
    this.validateFilters();
    this.buildFilterTable();
    this.notifyParentClass();
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// THE FILTER TABLE

makeFilterRow(filter, index)
{
    let row = document.createElement("tr");

    row.dataset.index = index;

    if (!filter.valid) {
        row.classList.add("invalidFilter");
        row.title = _tr('filter_editor.list.explanation_broken_hover');
    } else if (!filter.columnValid) {
        row.classList.add("invalidColumn");
        row.title = _tr('filter_editor.list.explanation_column_not_visible_hover');
    }

    // ----- Activation checkbox -----

    let activeTD = document.createElement("td"),
        checkbox = document.createElement("input");

    checkbox.type = "checkbox";
    checkbox.checked = filter.active;
    checkbox.title = _tr('filter_editor.list.explanation_is_active');

    if (!filter.valid)
        checkbox.disabled = true;

    checkbox.addEventListener("click",
        (event) => this.onFilterActiveCheckboxClick(event));

    activeTD.classList.add("minimize-width");

    activeTD.appendChild(checkbox);
    row.appendChild(activeTD);

    // ----- Plain text filter explanation -----

    let explanationTD = document.createElement("td");

    let html = "";

    html += `<div class="explanation" title="${_tr('filter_editor.list.explanation_click_to_edit')}">`;
    html += `<span class="column">`;

    let found = false;

    for (const col of this.columnNames) {
        if (col[0] == filter.column) {
            html += col[1];
            found = true;
            break;
        }
    }

    if (!found)
        html += `<span class="error">(${_tr('filter_editor.list.explanation_unknown_column')})</span>`;

    html += `</span><span class="op">`;

    found = false;

    for (const op of OPERATOR_DEFINITIONS) {
        if (op.operator == filter.operator) {
            html += op.title;
            found = true;
            break;
        }
    }

    if (!found)
        html += `(?)`;

    html += `</span><span class="value">${escapeHTML(filter.displayValue)}</span>`;

    if (!filter.valid)
        html += `<span class="notification">${_tr('filter_editor.list.explanation_broken')}</span>`;
    else if (!filter.columnValid)
        html += `<span class="notification">${_tr('filter_editor.list.explanation_column_not_visible')}</span>`;

    html += "</div>";

    explanationTD.innerHTML = html;

    explanationTD.classList.add("width-100p");

    explanationTD.querySelector("div.explanation").
        addEventListener("click", (event) => this.openFilterEditor(event));

    row.appendChild(explanationTD);

    // ----- Action buttons -----

    let buttonsTD = document.createElement("td");

    buttonsTD.classList.add("buttons");
    buttonsTD.classList.add("minimize-width");

    buttonsTD.innerHTML =
        `<button class="dup" data-index=${index}>${_tr('filter_editor.list.duplicate_row')}</button>` +
        `<button class="del" data-index=${index}>${_tr('filter_editor.list.remove_row')}</button>`;

    buttonsTD.querySelector("button.dup").addEventListener("click",
        (event) => this.duplicateFilter(event));

    buttonsTD.querySelector("button.del").addEventListener("click",
        (event) => this.deleteFilter(event));

    row.appendChild(buttonsTD);

    return row;
}

// The "new filter" row at the end of the filter table
makeNewFilterRow()
{
    let html = "";

    html += `<td colspan="3">`;
    html += `<button class="new">${_tr('filter_editor.list.new_row')}</button></td>`;

    let row = document.createElement("tr");

    row.dataset.index = "new";
    row.innerHTML = html;
    row.querySelector("button").addEventListener("click", (event) => this.openFilterEditor(event));

    return row;
}

buildFilterTable()
{
    let table = document.createElement("table");

    table.classList.add("table");

    for (let i = 0; i < this.filters.length; i++)
        table.appendChild(this.makeFilterRow(this.filters[i], i));

    table.appendChild(this.makeNewFilterRow());

    this.ui.filterTable.innerHTML = "";
    this.ui.filterTable.appendChild(table);
}

deleteAllFilters()
{
    if (!window.confirm(_tr('are_you_sure')))
        return;

    this.filters = [];
    this.closeFilterEditor();
    this.validateFilters();
    this.buildFilterTable();
    this.updateJSON();
    this.notifyParentClass();
}

// The "active" checkbox of a filter was clicked
onFilterActiveCheckboxClick(e)
{
    if (this.disabled)
        return;

    const index = parseInt(e.target.parentNode.parentNode.dataset.index, 10),
          active = e.target.checked;

    if (index < 0 || index > this.filters.length - 1) {
        window.alert(`Invalid filter index ${event.target.dataset.index}. The filter cannot be activated/deactivated.`);
        return;
    }

    this.filters[index].active = active;
    this.updateJSON();
    this.notifyParentClass();
}

duplicateFilter(event)
{
    if (this.disabled)
        return;

    const index = parseInt(event.target.dataset.index, 10);

    if (index < 0 || index > this.filters.length - 1) {
        window.alert(`Invalid filter index ${event.target.dataset.index}. The filter cannot be duplicated.`);
        return;
    }

    this.filters.splice(index + 1, 0, {
        active: false,
        column: this.filters[index].column,
        operator: this.filters[index].operator,
        value: this.filters[index].value,
        valid: false,
        columnValid: false,
        displayValue: null,
    });

    this.validateFilters();
    this.buildFilterTable();
    this.updateJSON();
    this.notifyParentClass();
}

deleteFilter(event)
{
    if (this.disabled)
        return;

    const index = parseInt(event.target.dataset.index, 10);

    if (index < 0 || index > this.filters.length - 1) {
        window.alert(`Invalid filter index ${event.target.dataset.index}. The filter cannot be removed.`);
        return;
    }

    this.closeFilterEditor();
    this.filters.splice(index, 1);
    this.validateFilters();
    this.buildFilterTable();
    this.updateJSON();
    this.notifyParentClass();
}

// -------------------------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------------
// FILTER EDITOR POPUP

openFilterEditor(e)
{
    if (this.disabled)
        return;

    const node = e.target.parentNode.parentNode;

    if (node.dataset.index == "new") {
        // Create a new empty filter. Find the initially selected column.
        let columnName = null;

        if (this.defaultColumn in this.columnDefinitions)
            columnName = this.defaultColumn;
        else {
            // Sigh. The default column does not exist in the column definitions.
            // Pick the first available column, whatever it is.
            columnName = Object.keys(this.columnDefinitions)[0];
            console.warn(`FilterEditor::openFilterEditor(): the default column "${this.defaultColumn}" is not valid!`);
        }

        const def = this.columnDefinitions[columnName];

        this.editFilterIndex = -1;

        this.editFilter = {
            column: columnName,
            operator: def.defaultOperator,
            value: ""
        };
    } else {
        // Edit an existing filter
        const index = parseInt(node.dataset.index, 10);

        if (index < 0 || index > this.filters.length - 1) {
            window.alert(`Invalid filter index ${node.dataset.index}. The filter cannot be edited.`);
            return;
        }

        this.editFilterIndex = index;

        this.editFilter = {
            column: this.filters[index].column,
            operator: this.filters[index].operator,
            value: this.filters[index].value
        };
    }

    // Construct the editor user interface
    this.editor.backdrop = document.createElement("div");
    this.editor.backdrop.id = "modalDialogBackdrop";

    this.editor.popup = document.createElement("div");
    this.editor.popup.classList.add("filterPopup");

    let html = "";

    const title = _tr((this.editFilterIndex == -1) ? 'filter_editor.popup.title_new' : 'filter_editor.popup.title_edit');

    html += `<div class="upper">`;
    html += `<div class="title">${title}</div><div class="buttons">`;
    html += `<button id="ok" class="btn-save">${_tr('filter_editor.popup.save')}</button>`;
    html += `<button id="cancel" class="btn-cancel">${_tr('filter_editor.popup.cancel')}</button>`;
    html += `</div></div>`;

    html += `<div class="lower">`;
    html += `<table>`;
    html += `<tr><th style="width: 25%;">${_tr('filter_editor.popup.target_title')}</th><td><select id="filterColumn" class="control"></select></td></tr>`;
    html += `<tr><td colspan="2">`;
    html += "<p>" + _tr('filter_editor.popup.target_warning') + "</p>";
    html += `</td></tr>`;
    html += `<tr><th>${_tr('filter_editor.popup.operator_title')}</th><td><select id="filterOperator" class="control"></select></td></tr>`;
    html += `<tr><th colspan="2">${_tr('filter_editor.popup.comparison_title')}</th></r>`;
    html += `<tr><td colspan="2">`;
    html += `<div id="filterValue"></div>`;
    html += `</tr></table></div>`;

    this.editor.popup.innerHTML = html;
    this.editor.column = this.editor.popup.querySelector("select#filterColumn");
    this.editor.operator = this.editor.popup.querySelector("select#filterOperator");
    this.editor.child = this.editor.popup.querySelector("div#filterValue");

    // Fill the column selector. Its contents won't change when the editor popup is open.
    let validColumns = new Set();

    for (const c of this.columns)
        validColumns.add(c);

    let found = false;

    for (const c of this.columnNames) {
        let option = document.createElement("option");

        if (validColumns.has(c[0]))
            option.innerHTML = `${c[1]}`;
        else {
            option.innerHTML = `${c[1]} *`;
            option.classList.add("missing");
        }

        option.dataset.column = c[0];

        if (c[0] == this.editFilter.column) {
            option.selected = true;
            found = true;
        }

        this.editor.column.appendChild(option);
    }

    if (!found) {
        // TODO: What now?
        console.error(`openFilterEditor(): column "${this.editFilter.column}" is not valid`);
        window.alert(`Column "${this.editFilter.column}" is invalid. Using the first available column instead.`);
    }

    this.fillOperatorSelector(this.editor.operator, this.editFilter.column, this.editFilter.operator);
    this.buildEditorChild();

    // Setup event handling
    this.editor.column.addEventListener("change",
        () => this.onFilterEditorColumnChanged());

    this.editor.operator.addEventListener("change",
        () => this.onFilterEditorOperatorChanged());

    this.editor.popup.querySelector("button#ok").addEventListener("click",
        () => this.onFilterEditorSave());

    this.editor.popup.querySelector("button#cancel").addEventListener("click",
        () => this.onFilterEditorCancel());

    if (node.dataset.index != "new") {
        // Highlight the edited filter row
        this.editedFilterRow = e.target.parentNode.parentNode;
        this.editedFilterRow.classList.add("filterBeingEdited");
    }

    // Make the popup visible
    this.editor.popup.style.display = "flex";
    this.editor.backdrop.appendChild(this.editor.popup);
    document.body.appendChild(this.editor.backdrop);
}

// Construct the child editor inside the editor popup, that actually edits the filter value
buildEditorChild()
{
    if (this.editor.childEditor) {
        // Remove the old editor first, if the target column has changed
        this.editor.child.innerHTML = "";
        this.editor.childEditor = null;
    }

    // Figure out the editor we need
    let type = null;

    if (this.editFilter.column in this.columnDefinitions)
        type = this.columnDefinitions[this.editFilter.column].type;

    let valid = true;

    switch (type) {
        case ColumnType.BOOL:
            type = FilterEditBool;
            break;

        case ColumnType.INTEGER:
            type = FilterEditInteger;
            break;

        case ColumnType.FLOAT:
            type = FilterEditFloat;
            break;

        case ColumnType.UNIXTIME:
            type = FilterEditUnixtime;
            valid = doesItLookLikeADate(this.editFilter.value);
            break;

        case ColumnType.STRING:
        default:    // coerce unknown types into strings
            type = FilterEditString;
            break;
    }

    // Then build it
    this.editor.childEditor = new type(this.editor.child);

    if (this.editFilterIndex != -1 && valid)
        this.editor.childEditor.setValue(this.editFilter.value);
}

fillOperatorSelector(element, column, initial)
{
    const def = this.columnDefinitions[column];

    if (def === null || def === undefined) {
        // If the column is unknown, put "=" in the box and move on. It's the only "reliable"
        // operator we can use.
        console.error(`FilterEditor::refillOperatorSelector(): unknown column "${column}"`);

        element.innerHTML = "";

        let option = document.createElement("option");

        option.text = "=";
        option.dataset.operator = "equ";
        option.selected = true;

        element.appendChild(option);

        return;
    }

    element.innerHTML = "";     // purge any existing content

    let found = false;

    for (const op of OPERATOR_DEFINITIONS) {
        // Is this operator available for this column type?
        if (!op.availableFor.has(def.type))
            continue;

        let option = document.createElement("option");

        option.text = op.title;
        option.dataset.operator = op.operator;

        if (op.operator == (initial ? initial : def.defaultOperator)) {
            option.selected = true;
            found = true;
        }

        element.appendChild(option);
    }

    if (!found) {
        console.warn(`Could not select the initial/current operator for column "${column}"`);
        // TODO: What now?
    }
}

onFilterEditorColumnChanged()
{
    this.editFilter.column = this.editor.column[this.editor.column.selectedIndex].dataset.column;
    this.fillOperatorSelector(this.editor.operator, this.editFilter.column, null);
    this.onFilterEditorOperatorChanged();
    this.buildEditorChild();
}

onFilterEditorOperatorChanged()
{
    this.editFilter.operator = this.editor.operator[this.editor.operator.selectedIndex].dataset.operator;
}

closeFilterEditor()
{
    // Make sure everything goes away, no DOM references left behind
    if (this.editor.backdrop) {
        this.editor.column = null;
        this.editor.operator = null;
        this.editor.childEditor = null;
        this.editor.child = null;
        this.editor.popup = null;
        this.editor.backdrop.remove();
        this.editor.backdrop = null;
    }

    if (this.editedFilterRow) {
        this.editedFilterRow.classList.remove("filterBeingEdited");
        this.editedFilterRow = null;
    }

    this.editFilterIndex = null;
    this.editFilter = null;
}

onFilterEditorSave()
{
    if (!this.editor.childEditor.validate()) {
        // The filter is invalid and it cannot be saved
        return;
    }

    const value = this.editor.childEditor.getValue();

    if (this.editFilterIndex == -1) {
        // Create a new
        this.filters.push({
            active: false,
            column: this.editFilter.column,
            operator: this.editFilter.operator,
            value: value,
            valid: false,
            columnValid: false,
            displayValue: null,
        });
    } else {
        // Save changes to an existing filter
        let filter = this.filters[this.editFilterIndex];

        filter.column = this.editFilter.column;
        filter.operator = this.editFilter.operator;
        filter.value = value;
    }

    this.closeFilterEditor();

    this.validateFilters();
    this.buildFilterTable();
    this.updateJSON();
    this.notifyParentClass();
}

onFilterEditorCancel()
{
    this.closeFilterEditor();
}

};  // class FilterEditor
