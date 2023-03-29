// TODO: Decompose the massive FilterEditor class into smaller parts

import { ColumnType, ColumnFlag } from "../../table/constants.js";
import { _tr, escapeHTML, pad } from "../../../common/utils.js";
import { convertTimestamp } from "../../table/utils.js";
import { create, getTemplate } from "../../../common/dom.js";

import { ColumnDefinitions } from "../interpreter/columns.js";
import { MessageLogger } from "../interpreter/logger.js";
import { Tokenizer } from "../interpreter/tokenizer.js";
import { Parser } from "../interpreter/parser.js";
import { CodeGenerator } from "../interpreter/codegen.js";
import { ALLOWED_OPERATORS, ABSOLUTE_TIME, STORAGE_PARSER, floatize, parseAbsoluteOrRelativeDate, ComparisonCompiler, compareRowValue } from "../interpreter/comparisons.js";
import { evaluateFilter } from "../interpreter/evaluator.js";

import { OPERATORS } from "./operators.js";
import { EditableFilter } from "./editable_filter.js";
import { FilterEditorBase } from "./editor_base.js";

import { FilterEditorBoolean } from "./edit_boolean.js";
import { FilterEditorString } from "./edit_string.js";
import { FilterEditorNumeric } from "./edit_numeric.js";
import { FilterEditorUnixtime } from "./edit_unixtime.js";

function humanOperatorName(operator)
{
    switch (operator) {
        case "=": return "=";
        case "!=": return "≠";
        case "<": return "<";
        case "<=": return "≤";
        case ">": return ">";
        case ">=": return "≥";
        case "[]": return _tr("filtering.pretty.interval");
        case "![]": return _tr("filtering.pretty.not_interval");

        default:
            throw new Error(`humanOperatorName(): invalid operator "${operator}"`);
    }
}

function getDefaultValue(definition)
{
    switch (definition.type) {
        case ColumnType.BOOL:
            return true;

        case ColumnType.NUMERIC:
            if (definition.flags & ColumnFlag.F_STORAGE)
                return "0M";

            return 0;

        case ColumnType.STRING:
            return "";

        case ColumnType.UNIXTIME:
            return 0;

        default:
            throw new Error("getDefaultValue(): invalid column type");
    }
}

export class FilterEditor {
    constructor(parentClass, container, preview, columnDefinitions, columnTitles, filterPresets, filterDefaults, isAdvanced, isVisible)
    {
        // This container is our playground. Everything we put on the screen, it's
        // inside this HTML element, which in turn lives inside the SuperTable header
        // controls DIV.
        this.container = container;

        // This is the preview container which is shown when the editor isn't fully visible.
        // It contains a preview of the current filter, traditional or advanced.
        this.preview = preview;

        // Who do we notify about filter changes?
        this.parentClass = parentClass;

        // Column definitions
        this.plainColumnDefinitions = columnDefinitions;
        this.columnDefinitions = new ColumnDefinitions(columnDefinitions);
        this.columnTitles = columnTitles;

        this.isAdvanced = isAdvanced;
        this.isVisible = isVisible;

        this.filterPresets = filterPresets;

        this.filters = [];      // the traditional filters
        this.advancedPreview = null;
        this.showJSON = false;
        this.defaultFilter = filterDefaults[0];

        // The current filter programs. One for the old-style filters, one for the advanced filter.
        this.comparisons = [];
        this.program = [];
        this.comparisonsAdvanced = [];
        this.programAdvanced = [];

        // JS event handling shenanigans
        this.onActivateFilter = this.onActivateFilter.bind(this);
        this.onEditFilter = this.onEditFilter.bind(this);
//        this.onDuplicateFilter = this.onDuplicateFilter.bind(this);
        this.onDeleteFilter = this.onDeleteFilter.bind(this);

        this.buildUI();

        // Initially everything is disabled until the parent class changes that
        this.enableOrDisable(false);
    }

    $(selector) { return this.container.querySelector(selector); }
    $all(selector) { return this.container.querySelectorAll(selector); }

    buildUI()
    {
        this.$("button#deleteAll").addEventListener("click", () => this.onDeleteAllFilters());
        this.$("button#showJSON").addEventListener("click", () => this.onShowJSON());
        this.$("button#hideJSON").addEventListener("click", () => this.onHideJSON());
        this.$("button#saveJSON").addEventListener("click", () => this.onSaveJSON());
        this.$("textarea#json").addEventListener("input", (e) => this.onChangeJSON(e));
        this.$("input#advanced").addEventListener("click", (e) => this.toggleAdvancedMode(e.target.checked));

        this.$("button#save").addEventListener("click", () => this.onSave());
        this.$("button#clear").addEventListener("click", () => this.onClear());
        this.$("button#convert").addEventListener("click", () => this.onConvertTraditionalFilter());
        this.$("textarea#filter").addEventListener("input", () => this.onAdvancedInput());

        if (Object.keys(this.filterPresets[0]).length > 0)
            this.$("button#traditionalPresets").addEventListener("click", (e) => this.onOpenTraditionalPresets(e));
        else this.$("button#traditionalPresets").remove();

        if (Object.keys(this.filterPresets[1]).length > 0)
            this.$("button#advancedPresets").addEventListener("click", (e) => this.onOpenAdvancedPresets(e));
        else this.$("button#advancedPresets").remove();

        if (this.isAdvanced) {
            // The traditional editor is visbile by default. Do not call toggleAdvancedMode() here,
            // as it tries to signal the parent class that the filter has changed. But we're still
            // in the initialization phase, and we don't even have table data yet.
            this.$("input#advanced").checked = true;
            this.$("div#traditional").classList.add("hidden");
            this.$("div#advanced").classList.remove("hidden");
        }
    }

    // Called from the parent class
    enableOrDisable(isEnabled)
    {
        this.disabled = !isEnabled;

        this.$("button#deleteAll").disabled = this.disabled;
        this.$("button#showJSON").disabled = this.disabled;
        this.$("button#hideJSON").disabled = this.disabled;
        this.$("button#saveJSON").disabled = this.disabled;

        if (Object.keys(this.filterPresets[0]).length > 0)
            this.$("button#traditionalPresets").disabled = this.disabled;

        this.$("textarea#json").disabled = this.disabled;
        this.$("input#advanced").disabled = this.disabled;

        this.$("button#save").disabled = this.disabled;
        this.$("button#clear").disabled = this.disabled;
        this.$("button#convert").disabled = this.disabled;

        if (Object.keys(this.filterPresets[1]).length > 0)
            this.$("button#advancedPresets").disabled = this.disabled;

        this.$("textarea#filter").disabled = this.disabled;

        this.$("button#deleteAll").disabled = this.disabled;
        this.$("button#saveJSON").disabled = this.disabled;

        for (const e of this.$all(".filterList input, .filterList button"))
            e.disabled = this.disabled;
    }

    // Switch between traditional and advanced filtering modes
    toggleAdvancedMode(mode)
    {
        if (this.isAdvanced == mode)
            return;

        this.isAdvanced = mode;

        if (this.isAdvanced) {
            this.$("div#traditional").classList.add("hidden");
            this.$("div#advanced").classList.remove("hidden");
        } else {
            this.$("div#traditional").classList.remove("hidden");
            this.$("div#advanced").classList.add("hidden");
        }

        this.updateFilterView();

        this.parentClass.saveFilters();
        this.parentClass.updateFiltering();
    }

    isAdvancedMode()
    {
        return this.isAdvanced;
    }

    // Alternate between editor and preview container visibilities
    setVisibility(isVisible)
    {
        if (isVisible) {
            this.container.classList.remove("hidden");
            this.preview.classList.add("hidden");
            this.updateFilterView();
        } else {
            this.container.classList.add("hidden");
            this.preview.classList.remove("hidden");
            this.updatePreview();
        }

        this.isVisible = isVisible;
    }

    // Updates the filter "preview" that sits below the supertable control row.
    // The container element is completely hidden if there is no filter.
    updatePreview()
    {
        if (!this.preview) {
            console.warning("FilterEditor::updatePreview(): the preview container element is NULL");
            return;
        }

        if (this.isAdvanced) {
            if (this.advancedPreview === null || this.advancedPreview.length == 0)
                this.preview.classList.add("hidden");
            else {
                this.preview.innerHTML = `${_tr("filtering.preview_prefix")}: <code>${this.advancedPreview}</code>`;

                if (!this.isVisible)
                    this.preview.classList.remove("hidden");
            }

            return;
        }

        // Count how many usable filters there are. If there are none, don't show the preview.
        let numUsable = 0;

        for (const f of this.filters)
            if (f.active)
                numUsable++;

        if (numUsable == 0) {
            this.preview.innerText = "";
            this.preview.classList.add("hidden");
        } else {
            this.preview.innerText = _tr("filtering.preview_prefix") + ":";

            for (const f of this.filters)
                if (f.active)
                    this.preview.appendChild(this.buildFilterEntry(f, false));

            if (!this.isVisible)
                this.preview.classList.remove("hidden");
        }
    }

    // Returns the current filter program. It doesn't matter which mode the system is (traditional
    // or advanced), this will always retun the current program. The program can be empty, that's
    // not an error.
    getFilterProgram()
    {
        return {
            comparisons: [...(this.isAdvanced ? this.comparisonsAdvanced : this.comparisons)],
            program: [...(this.isAdvanced ? this.programAdvanced : this.program)]
        };
    }

    // ----------------------------------------------------------------------------------------------
    // ----------------------------------------------------------------------------------------------
    // "TRADITIONAL" FILTERS

    // Loads filters from an array and compiles them. Does not update the user interface.
    setTraditionalFilters(array)
    {
        this.filters = [];

        for (const raw of (Array.isArray(array) ? array : [])) {
            let e = new EditableFilter();

            if (e.load(raw, this.plainColumnDefinitions))
                this.filters.push(e);
        }

        this.updateJSON();
        this.compileTraditionalFilters();
        this.updateFilterView();
    }

    getTraditionalFilters()
    {
        let out = [];

        for (const f of this.filters)
            if (!f.isNew)
                out.push(f.save());

        return out;
    }

    updateFilterView()
    {
        const box = this.container.querySelector("div.filterList");

        if (this.isAdvanced)
            box.innerText = "";
        else {
            box.innerText = "";

            // Existing filters
            for (let i = 0; i < this.filters.length; i++) {
                const filter = this.filters[i];
                const entry = this.buildFilterEntry(filter, true);

                // Setup events
                entry.querySelector("div.active").addEventListener("click", e => this.onActivateFilter(e));
                entry.querySelector("div.parts").addEventListener("click", e => this.onEditFilter(e));
                entry.querySelector("div.danger").addEventListener("click", e => this.onDeleteFilter(e));

                box.appendChild(entry);
            }

            // The "new filter" button
            let newFilter = create("button", { cls: ["filterBox", "newFilter"], text: _tr("filtering.new_traditional_filter") });

            newFilter.addEventListener("click", e => this.onNewFilter(e));

            box.appendChild(newFilter);

            this.reindexTraditionalFilters();
        }
    }

    reindexTraditionalFilters()
    {
        const filters = this.container.querySelectorAll("div.filterList > div.filter");

        for (let i = 0; i < filters.length; i++)
            filters[i].dataset.index = i;
    }

    onDeleteAllFilters()
    {
        if (!window.confirm(_tr("are_you_sure")))
            return;

        this.filters = [];

        this.updateJSON();
        this.updateFilterView();
        this.compileTraditionalFilters();
        this.parentClass.saveFilters();
        this.parentClass.updateFiltering();
    }

    onShowJSON()
    {
        this.$("button#showJSON").classList.add("hidden");
        this.$("button#hideJSON").classList.remove("hidden");
        this.$("button#saveJSON").classList.remove("hidden");
        this.$("textarea#json").classList.remove("hidden");
    }

    onHideJSON()
    {
        this.$("button#showJSON").classList.remove("hidden");
        this.$("button#hideJSON").classList.add("hidden");
        this.$("button#saveJSON").classList.add("hidden");
        this.$("textarea#json").classList.add("hidden");
    }

    onChangeJSON(e)
    {
        // Validate the JSON
        try {
            JSON.parse(e.target.value);
            e.target.classList.remove("error");
            this.$("button#saveJSON").disabled = false;
        } catch (error) {
            e.target.classList.add("error");
            this.$("button#saveJSON").disabled = true;
        }
    }

    onSaveJSON()
    {
        if (!window.confirm(_tr("filtering.save_json_confirm")))
            return;

        try {
            this.setTraditionalFilters(JSON.parse(this.$("textarea#json").value));
            this.compileTraditionalFilters();
            this.parentClass.saveFilters();
            this.parentClass.updateFiltering();
        } catch (e) {
            console.error(e);
            window.alert(e);
        }
    }

    updateJSON()
    {
        this.$("textarea#json").value = JSON.stringify(this.getTraditionalFilters());

        // It can't be invalid anymore
        this.$("textarea#json").classList.remove("error");
        this.$("button#saveJSON").disabled = false;
    }

    // Pretty-prints a traditional filter (generates the <span> elements
    // that wrap the filter elements in color-coded blocks)
    prettyPrintTraditionalFilter(filter)
    {
        const colDef = this.plainColumnDefinitions[filter.column],
              operator = OPERATORS[filter.operator];

        function formatValue(v)
        {
            // Format a timestamp
            if (colDef.type == ColumnType.UNIXTIME) {
                const d = parseAbsoluteOrRelativeDate(v);

                if (d === null)
                    return "?";

                return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
                       `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
            }

            // Format a storage amount
            if (colDef.flags & ColumnFlag.F_STORAGE) {
                if (v.length == 0)
                    return "";

                let unit = v.slice(v.length - 1);

                if (!"BKMGT".includes(unit))
                    return `${v} B`;

                switch (unit) {
                    case "B": unit = "B"; break;
                    case "K": unit = "KiB"; break;
                    case "M": unit = "MiB"; break;
                    case "G": unit = "GiB"; break;
                    case "T": unit = "TiB"; break;
                }

                return `${v.slice(0, v.length - 1)} ${unit}`
            }

            return v;
        }

        const prettyTrue = _tr("filtering.ed.bool.t"),
              prettyFalse = _tr("filtering.ed.bool.f"),
              prettyEmpty = _tr("filtering.pretty.empty"),
              prettyOr = _tr("filtering.pretty.or"),
              prettyNor = _tr("filtering.pretty.nor");

        let html = "";

        html += `<span class="column">${this.columnTitles[filter.column]}</span>`;
        html += `<span class="operator">${humanOperatorName(filter.operator)}</span>`;
        html += `<span class="values">`

        if (filter.operator == "[]" || filter.operator == "![]") {
            html += `<span class="value">`;
            html += formatValue(filter.values[0]);
            html += `</span><span class="sep"> − </span><span class="value">`;
            html += formatValue(filter.values[1]);
            html += `</span>`;
        } else {
            if (colDef.type == ColumnType.BOOL)
                html += `<span class="value">${filter.values[0] === 1 ? prettyTrue : prettyFalse}</span>`;
            else {
                for (let i = 0, j = filter.values.length; i < j; i++) {
                    if (filter.values[i].length == 0 && colDef.type == ColumnType.STRING)
                        html += `<span class="value empty">${prettyEmpty}</span>`;
                    else {
                        html += `<span class="value">`;
                        html += formatValue(filter.values[i]);
                        html += "</span>";
                    }

                    if (i + 1 < j - 1)
                        html += `<span class="sep">, </span>`;
                    else if (i + 1 < j) {
                        if (filter.operator == "!=")
                            html += `<span class="sep"> ${prettyNor} </span>`;
                        else html += `<span class="sep"> ${prettyOr} </span>`;
                    }
                }
            }
        }

        html += "</span>";

        return html;
    }

    buildFilterEntry(filter, isEditable)
    {
        let n = create("div", { cls: ["filterBox", "filter"] });

        n.appendChild(getTemplate("traditionalFilter"));

        if (isEditable) {
            n.classList.add("editableFilter");
            n.querySelector("input").checked = filter.active;
            n.querySelectorAll("div")[1].classList.add("font-110p");
        } else {
            n.classList.add("padding-5px");
            n.querySelectorAll("div")[2].remove();
            n.querySelectorAll("div")[0].remove();
        }

        n.querySelector("div.parts").innerHTML = this.prettyPrintTraditionalFilter(filter);

        return n;
    }

    onNewFilter(e)
    {
        if (this.disabled) {
            e.preventDefault();
            return;
        }

        let f = new EditableFilter();

        let initial = null;

        if (this.defaultFilter === undefined || this.defaultFilter === null || this.defaultFilter.length < 4) {
            // Use the first available column. Probably not the best, but at least the filter will be valid.
            initial = [0, Object.keys(this.plainColumnDefinitions)[0], "=", ""];
        } else initial = [...this.defaultFilter];

        initial[3] = getDefaultValue(this.plainColumnDefinitions[initial[1]]);

        if (!f.load(initial, this.plainColumnDefinitions)) {
            window.alert("Filter creation failed. See the console for details.");
            return;
        }

        this.filters.push(f);
        this.updateJSON();
        this.updateFilterView();

        // Ugh...
        this.container.querySelectorAll("div.filterList > div.filter")[this.filters.length - 1].querySelector("div.parts").click();
    }

    // Activate or deactivate an individual filter
    onActivateFilter(e)
    {
        if (this.disabled) {
            e.preventDefault();
            return;
        }

        const index = parseInt(e.target.parentNode.dataset.index, 10);

        this.filters[index].active ^= 1;
        e.target.firstChild.checked = this.filters[index].active;

        this.updateJSON();
        this.compileTraditionalFilters();
        this.parentClass.saveFilters();
        this.parentClass.updateFiltering();
    }

    onEditFilter(e)
    {
        if (this.disabled) {
            e.preventDefault();
            return;
        }

        const index = parseInt(e.target.parentNode.dataset.index, 10);

        let filter = this.filters[index];

        filter.beginEditing();

        const editor = getTemplate("editTraditionalFilter");

        // We need this index in the event handlers, so stash it somewhere
        editor.querySelector("div#upper").dataset.index = index;

        // Sort the columns in alphabetical order
        let select = editor.querySelector("div#upper select#column"),
            columns = [];

        for (const column of Object.keys(this.plainColumnDefinitions))
            columns.push([column, this.columnTitles[column]]);

        columns.sort((a, b) => { return a[1].localeCompare(b[1]) });

        for (const [column, title] of columns) {
            let o = document.createElement("option");

            o.innerText = title;
            o.value = column;
            o.selected = (filter.editColumn == column);

            select.appendChild(o);
        }

        const colDef = this.plainColumnDefinitions[filter.editColumn];

        this.fillOperatorSelector(editor.querySelector("div#upper select#operator"),
                                  colDef.type, filter.editOperator);

        // Initial type-specific editor child UI
        this.buildValueEditor(filter, editor.querySelector("div#editor"), colDef);

        // Setup events for changing the column and the operator
        editor.querySelector("div#upper select#column").addEventListener("change", (e) => this.onColumnChanged(e));
        editor.querySelector("div#upper select#operator").addEventListener("change", (e) => this.onOperatorChanged(e));

        editor.querySelector("div#upper button#save").addEventListener("click", (e) => {
            let upper = e.target.closest("div#upper");
            const index = parseInt(upper.dataset.index, 10);

            // Don't save the filter if the value (or values) is incorrect
            const valid = this.filters[index].editor.validate();

            if (!valid[0]) {
                window.alert(valid[1]);
                return;
            }

            this.filters[index].finishEditing();
            this.filters[index].active = true;      // automatical activation
            this.filters[index].isNew = false;      // enable normal functionality
            modalPopup.close();

            // Immediately update the filter contents
            let box = this.container.querySelectorAll("div.filterList > div.filter")[index];

            box.querySelector("input").checked = this.filters[index].active;
            box.querySelector("div.parts").innerHTML = this.prettyPrintTraditionalFilter(this.filters[index]);

            this.updateJSON();
            this.parentClass.saveFilters();

            if (this.filters[index].active) {
                this.compileTraditionalFilters();
                this.parentClass.updateFiltering();
            }
        });

        if (modalPopup.create(() => filter.editor = null)) {        // don't leak the editor object when the popup is closed
            modalPopup.getContents().appendChild(editor);
            modalPopup.attach(e.target.parentNode, 400);
            modalPopup.display("bottom");
        }
    }

    onDeleteFilter(e)
    {
        if (this.disabled) {
            e.preventDefault();
            return;
        }

        const index = parseInt(e.target.parentNode.dataset.index, 10);

        const wasActive = this.filters[index].active;

        this.filters.splice(index, 1);
        e.target.parentNode.remove();

        this.reindexTraditionalFilters();

        this.updateJSON();
        this.parentClass.saveFilters();

        // Don't waste time updating the table if the filter wasn't active
        if (wasActive) {
            this.compileTraditionalFilters();
            this.parentClass.updateFiltering();
        }
    }

    fillOperatorSelector(target, type, initial)
    {
        target.innerHTML = "";

        for (const opId of ["=", "!=", "<", "<=", ">", ">=", "[]", "![]"]) {
            if (OPERATORS[opId].allowed.has(type)) {
                let o = document.createElement("option");

                o.innerText = humanOperatorName(opId);
                o.value = opId;
                o.selected = (opId == initial);

                target.appendChild(o);
            }
        }
    }

    buildValueEditor(filter, container, colDef)
    {
        const editors = {
            [ColumnType.BOOL]: FilterEditorBoolean,
            [ColumnType.NUMERIC]: FilterEditorNumeric,
            [ColumnType.STRING]: FilterEditorString,
            [ColumnType.UNIXTIME]: FilterEditorUnixtime,
        };

        if (colDef.type in editors) {
            filter.editor = new editors[colDef.type](container, filter, colDef);
            filter.editor.buildUI();
        } else throw new Error(`Unknown column type ${colDef.type}`);
    }

    // Attempts to preserve the current filter values between operator/column changes and applies
    // fixes to the data to ensure the current operator has enough data to work with
    preserveFilterData(filter)
    {
        if (!filter.editor) {
            console.warn("preserveFilterData(): no editor?");
            return;
        }

        // Grab the values from the form first
        filter.editValues = filter.editor.getData();

        // Then ensure there are enough values
        if (filter.editValues.length == 0)
            filter.editValues.push(getDefaultValue(this.plainColumnDefinitions[filter.editColumn]));

        if ((filter.editOperator == "[]" || filter.editOperator == "![]") && filter.editValues.length < 2)
            filter.editValues.push(filter.editValues[0]);
    }

    onColumnChanged(e)
    {
        let upper = e.target.closest("div#upper");
        const index = parseInt(upper.dataset.index, 10);
        let filter = this.filters[index];

        filter.editColumn = e.target[e.target.selectedIndex].value;

        // Is the previous operator still valid for this type? If not, reset it to "=",
        // it's the default (and the safest) operator.
        const newDef = this.plainColumnDefinitions[filter.editColumn];

        if (!OPERATORS[filter.editOperator].allowed.has(newDef.type))
            filter.editOperator = "=";

        // Refill the operator selector
        // TODO: Don't do this if the new column has the same operators available
        // as the previous column did.
        this.fillOperatorSelector(upper.querySelector("select#operator"),
                                  newDef.type, filter.editOperator);

        this.preserveFilterData(filter);

        // Recreate the editor UI
        let editor = upper.parentNode.querySelector("div#editor");

        editor.innerHTML = "";
        filter.editor = null;
        this.buildValueEditor(filter, editor, newDef);
    }

    onOperatorChanged(e)
    {
        let upper = e.target.closest("div#upper");
        const index = parseInt(upper.dataset.index, 10);
        let filter = this.filters[index];

        const operator = e.target[e.target.selectedIndex].value;

        filter.editOperator = operator;
        this.preserveFilterData(filter);

        filter.editor.operatorHasChanged(operator);
    }

    // Converts the traditional filters into an advanced filter string
    convertTraditionalFilter(filter)
    {
        // Convert the editable filter parts into a string
        let parts = [];

        for (const f of filter) {
            if (!f[0])          // inactive filter
                continue;

            if (f.length < 4)   // incomplete filter (TODO: can this even happen now?)
                continue;

            let col = f[1],
                op = f[2],
                val = [];

            const colDef = this.plainColumnDefinitions[col];

            // Convert the value
            for (let v of f.slice(3)) {
                switch (colDef.type) {
                    case ColumnType.BOOL:
                        if (v.length == 0)
                            continue;

                        val.push(v === 1 ? '1' : '0');
                        break;

                    case ColumnType.NUMERIC:
                        // All possible values should work fine, even storage units, without quotes
                        if (v.length == 0)
                            continue;

                        val.push(v);
                        break;

                    case ColumnType.UNIXTIME:
                        if (v.length == 0)
                            continue;

                        // Absolute times must be quoted, relative times should work as-is
                        val.push(ABSOLUTE_TIME.exec(v) !== null ? `"${v}"` : v);
                        break;

                    case ColumnType.STRING:
                    default:
                        // Convert strings to regexps
                        if (v == "")
                            val.push(`/^$/`);
                        else val.push(`/${v}/`);
                        break;
                }
            }

            // Output a comparison with the converted value
            if (op == "[]") {
                // include (closed)
                if (val.length < 2)
                    continue;

                parts.push(`(${col} >= ${val[0]} && ${col} <= ${val[1]})`);
            } else if (op == "![]") {
                // exclude (open)
                if (val.length < 2)
                    continue;

                parts.push(`(${col} < ${val[0]} || ${col} > ${val[1]})`);
            } else {
                if (val.length < 1)
                    continue;

                if (val.length == 1) {
                    // a single value
                    parts.push(`${col} ${op} ${val[0]}`);
                } else {
                    // multiple values, either OR'd or AND'd together depending on the operator
                    let sub = [];

                    for (const v of val)
                        sub.push(`${col} ${op} ${v}`);

                    if (op == "=")
                        sub = sub.join(" || ");
                    else sub = sub.join(" && ");

                    parts.push("(" + sub + ")");
                }
            }
        }

        // A traditional filter is basically nothing but a chain of AND comparisons
        return parts.join(" && ");
    }

    // Converts the "traditional" filters into an advanced filter string and compiles it
    compileTraditionalFilters()
    {
        const result = this.compileFilterString(this.convertTraditionalFilter(this.getTraditionalFilters()));

        if (result === false || result === null) {
            window.alert("Could not compile the filter. See the console for details, then contact Opinsys support.");
            return;
        }

        this.comparisons = result[0];
        this.program = result[1];
    }

    onOpenTraditionalPresets(e)
    {
        const presets = this.filterPresets[0];
        let html = "";

        for (const key of Object.keys(presets)) {
            html += `<tr><td><a href="#" data-id="${key}">${presets[key].title}</a></td><td>`;
            html += `<div class="filterList">`;

            const filters = presets[key].filters;

            for (let i = 0; i < filters.length; i++) {
                let e = new EditableFilter();

                if (!e.load(presets[key].filters[i], this.plainColumnDefinitions))
                    continue;

                html += `<div class="filterBox filter padding-2px"><div class="parts">`;
                html += this.prettyPrintTraditionalFilter(e, false);
                html += `</div></div>`;
            }

            html += `</div>`;
            html += `</td></tr>`;
        }

        const tmpl = getTemplate("filterPresets");

        tmpl.querySelector("p#help-advanced").remove();
        tmpl.querySelector("input#parenthesis").parentNode.remove();
        tmpl.querySelector("table tbody").innerHTML = html;

        // Click handlers
        for (let a of tmpl.querySelectorAll("table tbody a"))
            a.addEventListener("click", (e) => this.onInsertFilterPreset(e, true));

        if (modalPopup.create()) {
            modalPopup.getContents().appendChild(tmpl);
            modalPopup.attach(e.target);
            modalPopup.display("bottom");
        }
    }

    onInsertFilterPreset(e, isTraditional)
    {
        e.preventDefault();
        const id = e.target.dataset.id;
        const preset = this.filterPresets[isTraditional ? 0 : 1][id];

        if (!preset) {
            window.alert(`Invalid preset ID "${id}". Please contact Opinsys support.`);
            return;
        }

        if (isTraditional) {
            // Append or replace?
            if (modalPopup.getContents().querySelector("input#append").checked)
                this.setTraditionalFilters(this.getTraditionalFilters().concat(preset.filters));
            else this.setTraditionalFilters(preset.filters);

            this.updatePreview();
            this.parentClass.saveFilters();
            this.parentClass.updateFiltering();
        } else {
            let box = this.$("textarea#filter"),
                f = preset.filter;

            if (modalPopup.getContents().querySelector("input#parenthesis").checked)
                f = `(${f})`;

            // Append or replace?
            if (modalPopup.getContents().querySelector("input#append").checked) {
                if (box.value.trim().length == 0)
                    box.value = f;
                else {
                    box.value += "\n";
                    box.value += f;
                }
            } else box.value = f;

            this.clearMessages();
            this.changed = true;
            this.updateUnsavedWarning();

            this.updatePreview();
            this.parentClass.saveFilters();
            this.parentClass.updateFiltering();
        }
    }

    // --------------------------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------------------------
    // ADVANCED FILTERS

    setAdvancedFilter(filter)
    {
        let box = this.$("textarea#filter");

        if (typeof(filter) != "string")
            box.value = "";
        else box.value = filter;

        this.comparisonsAdvanced = [];
        this.programAdvanced = [];

        const result = this.compileFilterString(box.value);

        if (result === false || result === null)
            return;

        this.comparisonsAdvanced = result[0];
        this.programAdvanced = result[1];
        this.advancedPreview = result[2];

        this.updatePreview();
    }

    getAdvancedFilter()
    {
        return this.$("textarea#filter").value;
    }

    // Save the advanced filter string
    onSave()
    {
        const str = this.$("textarea#filter").value;
        const result = this.compileFilterString(str);

        if (result === false || result === null)
            return;

        this.comparisonsAdvanced = result[0];
        this.programAdvanced = result[1];
        this.advancedPreview = result[2];
        this.changed = false;

        this.updatePreview();
        this.updateUnsavedWarning();
        this.parentClass.saveFilters();
        this.parentClass.updateFiltering();
    }

    // Clear the advanced filter
    onClear()
    {
        if (window.confirm(_tr('are_you_sure'))) {
            this.$("textarea#filter").value = "";
            this.clearMessages();
            this.changed = true;
            this.updateUnsavedWarning();
        }
    }

    // Convert the traditional (mouse-driven) filter into a filter expression string
    onConvertTraditionalFilter()
    {
        if (!window.confirm(_tr('are_you_sure')))
            return;

        const filters = this.getTraditionalFilters();

        if (filters === null || filters === undefined || filters.length == 0) {
            window.alert(_tr('traditional_filter_is_empty'));
            return;
        }

        const result = this.convertTraditionalFilter(filters);

        if (result === false || result === null) {
            window.alert("Could not compile the filter. See the console for details, then contact Opinsys support.");
            return;
        }

        this.$("textarea#filter").value = result;
        this.clearMessages();
        this.changed = true;
        this.updateUnsavedWarning();
    }

    // Advanced filter string has changed
    onAdvancedInput()
    {
        this.changed = true;
        this.updateUnsavedWarning();
    }

    updateUnsavedWarning()
    {
        let legend = this.$("fieldset legend");

        if (!legend)
            return;

        let html = _tr('filtering.expression_title');

        if (this.changed)
            html += ` <span class="unsaved">[${_tr('filtering.unsaved')}]</span>`;

        legend.innerHTML = html;
    }

    clearMessages()
    {
        this.$("#messages").innerHTML = `<p class="margin-0 padding-0">${_tr('filtering.no_messages')}</p>`;
    }

    // Update the advanced filter compilation messages box
    listMessages(logger)
    {
        if (logger.empty())
            return;

        let html =
`<table class="commonTable messages width-100p"><thead><tr>
<th>${_tr('filtering.row')}</th>
<th>${_tr('filtering.column')}</th>
<th>${_tr('filtering.message')}</th>
</tr></thead><tbody>`;

        // The messages aren't necessarily in any particular order; sort them first by row number,
        // then by column number
        const sorted = [...logger.messages].sort((a, b) => (a.row - b.row) || (a.col - b.col));

        for (const e of sorted) {
            let cls = [];

            if (e.type == 'error')
                cls.push("error");

            html +=
`<tr class="${cls.join(' ')}" data-pos="${e.pos}" data-len="${e.len}">
<td class="minimize-width align-center">${e.row == -1 ? "" : e.row}</td>
<td class="minimize-width align-center">${e.col == -1 ? "" : e.col}</td>`;

            html += "<td>";
            html += _tr('filtering.' + e.type) + ": ";
            html += _tr('filtering.messages.' + e.message);

            if (e.extra !== null)
                html += `<br>(${e.extra})`;

            html += "</td></tr>";
        }

        html += "</tbody></table>";

        this.$("#messages").innerHTML = html;

        // Add event listeners. I'm 99% certain this leaks memory, but I'm not sure how to fix it.
        for (let row of this.$all(`table.messages tbody tr`))
            row.addEventListener("click", (e) => this.highlightMessage(e));
    }

    highlightMessage(e)
    {
        // Find the target table row. Using "pointer-events" to pass through clicks works, but
        // it makes browsers not display the "text" cursor when hovering the table and that is
        // just wrong.
        let elem = e.target;

        while (elem && elem.nodeName != "TR")
            elem = elem.parentNode;

        if (!elem) {
            console.error("highlightMessage(): can't find the clicked table row");
            return;
        }

        // Highlight the target
        const pos = parseInt(elem.dataset.pos, 10),
              len = parseInt(elem.dataset.len, 10);

        let t = this.$("textarea#filter");

        if (!t) {
            console.error("highlightMessage(): can't find the textarea element");
            return;
        }

        t.focus();

        if (len == -1) {
            // Move the cursor to the end
            t.setSelectionRange(t.value.length, t.value.length);
        } else {
            t.selectionStart = pos;
            t.selectionEnd = pos + len;
        }
    }

    onOpenAdvancedPresets(e)
    {
        const presets = this.filterPresets[1];
        let html = "";

        for (const key of Object.keys(presets)) {
            html += `<tr><td><a href="#" data-id="${key}">${presets[key].title}</a></td><td><code>`;
            html += escapeHTML(presets[key].filter);
            html += `</code></td></tr>`;
        }

        const tmpl = getTemplate("filterPresets");

        tmpl.querySelector("p#help-traditional").remove();
        tmpl.querySelector("table tbody").innerHTML = html;

        // Click handlers
        for (let a of tmpl.querySelectorAll("table tbody a"))
            a.addEventListener("click", (e) => this.onInsertFilterPreset(e, false));

        if (modalPopup.create()) {
            modalPopup.getContents().appendChild(tmpl);
            modalPopup.attach(e.target);
            modalPopup.display("bottom");
        }
    }

    // Compiles a filter expression and returns the compiled comparisons and RPN code in an array.
    // This does not actually USE the filter for anything, it only compiles the given string.
    compileFilterString(input, verboseDebug = true)
    {
        console.log(`----- Compiling filter string (verboseDebug=${verboseDebug}) -----`);
        console.log("Input:", input);

        const t0 = performance.now();

        this.clearMessages();

        if (input.trim() == "") {
            // Do nothing if there's nothing to compile
            console.log("----- Compilation finished -----");
            return [[], [], []];
        }

        let logger = new MessageLogger();

        // ----------------------------------------------------------------------------------------------
        // Tokenization

        let t = new Tokenizer();

        if (verboseDebug)
            console.log("----- Tokenization -----");

        t.tokenize(logger, this.columnDefinitions, input);

        if (!logger.empty()) {
            for (const m of logger.messages) {
                if (m.message == "unexpected_end") {
                    // Don't report the same error multiple times
                    this.listMessages(logger);
                    return null;
                }
            }
        }

        if (verboseDebug) {
            console.log("Raw tokens:");

            if (t.tokens.length == 0)
                console.log("  (NONE)");
            else console.log(t.tokens);
        } else console.log(`Tokenization generated ${t.tokens.length} tokens`);

        // ----------------------------------------------------------------------------------------------
        // Syntax analysis and comparison extraction

        let p = new Parser();

        if (verboseDebug)
            console.log("----- Syntax analysis/parsing -----");

        // TODO: Should we abort the compilation if this fails? Now we just cram ahead at full speed
        // and hope for the best.
        p.parse(logger, this.columnDefinitions, t.tokens, t.lastRow, t.lastCol);

        if (verboseDebug) {
            console.log("Raw comparisons:");

            if (p.comparisons.length == 0)
                console.log("  (NONE)");
            else console.log(p.comparisons);

            console.log("Raw parser output:");

            if (p.output.length == 0)
                console.log("  (NONE)");
            else console.log(p.output);
        } else console.log(`Parsing generated ${p.comparisons.length} comparisons and ${p.output.length} instructions`);

        // ----------------------------------------------------------------------------------------------
        // Compile the actual comparisons

        let comparisons = [];

        if (verboseDebug)
            console.log("----- Compiling the comparisons -----");

        let cc = new ComparisonCompiler();

        for (const raw of p.comparisons) {
            const c = cc.compile(logger, this.columnDefinitions, raw.column, raw.operator, raw.value);

            if (c === null) {
                // null == the comparison was so invalid it could not even be parsed
                // log it for debugging
                console.error(raw);
                continue;
            }

            if (c === false) {
                // false == the comparison was syntactically okay, but it wasn't actually correct
                console.warn("Could not compile comparison");
                console.warn(raw);
                continue;
            }

            comparisons.push(c);
        }

        if (!logger.empty()) {
            this.listMessages(logger);

            if (logger.haveErrors()) {
                // Warnings won't stop the filter string from saved or used
                console.error("Comparison compilation failed, no filter program produced");
                return null;
            }
        }

        if (verboseDebug) {
            console.log("Compiled comparisons:");
            console.log(comparisons);
        }

        let program = [];

        if (verboseDebug)
            console.log("----- Shunting Yard -----");

        // Generate code
        let cg = new CodeGenerator();

        program = cg.compile(p.output);

        if (verboseDebug) {
            console.log("Final filter program:");

            if (program.length == 0)
                console.log("  (Empty)");

            for (let i = 0; i < program.length; i++) {
                const o = program[i];

                switch (o[0]) {
                    case "!":
                        console.log(`(${i}) NEG`);
                        break;

                    case "&":
                        console.log(`(${i}) AND`);
                        break;

                    case "|":
                        console.log(`(${i}) OR`);
                        break;

                    default: {
                        const cmp = comparisons[o[0]];
                        console.log(`(${i}) CMP [${cmp.column} ${cmp.operator} ${cmp.value.toString()}]`);
                        break;
                    }
                }
            }
        }

        const t1 = performance.now();

        console.log(`Filter expression compiled to ${program.length} opcode(s), ${comparisons.length} comparison evaluator(s)`);
        console.log(`Filter expression compilation: ${t1 - t0} ms`);

        console.log("----- Compilation finished -----");

        // Generate a syntax-highlighted preview of the current filter string. This was originally
        // part of the custom syntax-highlighting editor I was designing for the advanced filtering
        // system, to be used in a content-editable DIV. But I never finished that, but a part of
        // it now lives here. Sigh... maybe I will one day create that simple contentEditable-based
        // syntax-highlighted editor for this.
        let html = [];

        const tag = (cls, value) => html.push(`<span class="${cls}">${value}</span>`);

        for (const i of p.output) {
            if (i[0] == "(" || i[0] == ")")
                tag("par", i[0]);
            else if (i[0] == "&" || i[0] == "|")
                tag("bool", i[0] + i[0]);
            else if (i[0] == "!")
                tag("neg", i[0]);
            else {
                const c = comparisons[i[0]];

                html.push(`<span class="cmp">`);
                tag("col", c.column);
                tag("opr", escapeHTML(c.operator));

                if (c.operator == "!!")
                    tag("val-b", c.value);
                else {
                    switch (this.columnDefinitions.get(this.columnDefinitions.expandAlias(c.column)).type) {
                        case ColumnType.BOOL:
                            tag("val-b", c.value);
                            break;

                        case ColumnType.NUMERIC:
                            tag("val-n", c.value);
                            break;

                        case ColumnType.STRING:
                            if (c.regexp)
                                tag("val-r", escapeHTML(c.value.toString()));
                            else tag("val-s", escapeHTML(c.value));

                            break;

                        case ColumnType.UNIXTIME:
                            tag("val-t", convertTimestamp(c.value)[1]);
                            break;

                        default:
                            tag("val-o", escapeHTML(c.value));
                            break;
                    }
                }

                html.push(`</span>`);
            }
        }

        html = html.join("");

        return [comparisons, program, html];
    }
}
