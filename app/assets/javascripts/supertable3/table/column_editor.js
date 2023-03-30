// The column editor popup

import { getTemplate, toggleClass } from "../../common/dom.js";
import { _tr } from "../../common/utils.js";
import * as Settings from "./settings.js";

// A global variable to the parent class, that we call directly... violates probably
// all OOP design principles there are
let ceParentClass = null;

let ceUnsaved = false;

function getColumnList(selected)
{
    let selector = "div#columnList > div";

    if (selected)
        selector += ".selected";

    return modalPopup.getContents().querySelectorAll(selector);
}

function updateEditor()
{
    const numSelected = getColumnList(true).length;
    const saveButton = modalPopup.getContents().querySelector("button#save")

    if (numSelected == 0)
        saveButton.disabled = true;
    else saveButton.disabled = !ceUnsaved;

    modalPopup.getContents().querySelector("div#columnStats").innerText = _tr("status.column_stats", {
        selected: numSelected,
        total: Object.keys(ceParentClass.columns.definitions).length
    });
}

function filterList(e)
{
    const str = e.target.value.trim().toLowerCase();

    // Only change item visibilities based on the search string, so we don't lose
    // unsaved changes
    for (const c of getColumnList())
        toggleClass(c, "hidden", str && ceParentClass.columns.titles[c.dataset.column].toLowerCase().indexOf(str) == -1);
}

function toggleColumn(elem)
{
    toggleClass(elem, "selected", !elem.classList.contains("selected"));
    elem.childNodes[0].checked = elem.classList.contains("selected");

    ceUnsaved = true;
    updateEditor();
}

function save()
{
    // Make a list of new visible columns
    let newVisible = new Set();

    for (const c of getColumnList(true))
        if (c.classList.contains("selected"))
            newVisible.add(c.dataset.column);

    // Keep the existing columns in whatever order they were, but remove
    // hidden columns
    let newColumns = [];

    for (const col of ceParentClass.columns.current) {
        if (newVisible.has(col)) {
            newColumns.push(col);
            newVisible.delete(col);
        }
    }

    // Then tuck the new columns at the end of the array
    for (const col of newVisible)
        newColumns.push(col);

    ceUnsaved = false;
    updateEditor();

    ceParentClass.setVisibleColumns(newColumns);
}

// Selects or deselect all columns that are *currently* visible on the list
function selectAllVisible(select)
{
    let changed = false;

    for (const c of getColumnList(false)) {
        if (c.classList.contains("hidden")) {
            // Hidden by the filter
            continue;
        }

        toggleClass(c, "selected", select);

        if (c.firstChild.checked != select) {
            c.firstChild.checked = select;
            changed = true;
        }
    }

    if (changed) {
        ceUnsaved = true;
        updateEditor();
    }
}

function loadDefaults()
{
    const initial = new Set(ceParentClass.columns.defaults);

    for (const c of getColumnList(false)) {
        if (initial.has(c.dataset.column)) {
            c.classList.add("selected");
            c.firstChild.checked = true;
        } else {
            c.classList.remove("selected");
            c.firstChild.checked = false;
        }
    }

    ceUnsaved = true;
    updateEditor();
}

function resetOrder()
{
    const current = new Set(ceParentClass.columns.current);
    let nc = [];

    for (const c of ceParentClass.columns.order)
        if (current.has(c))
            nc.push(c);

    ceParentClass.columns.current = nc;
    Settings.save(ceParentClass);
    ceParentClass.updateTable();
}

// Open the column editor popup
export function openEditor(e, parentClass)
{
    ceParentClass = parentClass;

    // Sort the columns alphabetically by their localized names
    const columnNames =
        Object.keys(ceParentClass.columns.definitions)
        .map((key) => [key, ceParentClass.columns.titles[key]])
        .sort((a, b) => { return a[1].localeCompare(b[1]) });

    const current = new Set(ceParentClass.columns.current);

    let html = "";

    for (const c of columnNames) {
        const def = ceParentClass.columns.definitions[c[0]];
        let cls = ["item"];

        if (current.has(c[0]))
            cls.push("selected");

        html += `<div data-column="${c[0]}" class="${cls.join(' ')}">`;

        if (current.has(c[0]))
            html += `<input type="checkbox" checked></input>`;
        else html += `<input type="checkbox"></input>`;

        html += `${c[1]}</div>`;
    }

    const template = getTemplate("columnsPopup");

    template.querySelector("div#columnList").innerHTML = html;

    for (const i of template.querySelectorAll(`div#columnList .item`))
        i.addEventListener("click", e => toggleColumn(e.target));

    template.querySelector(`input[type="search"]`).addEventListener("input", e => filterList(e));

    template.querySelector("button#save").addEventListener("click", () => save());
    template.querySelector("button#selectAll").addEventListener("click", () => selectAllVisible(true));
    template.querySelector("button#deselectAll").addEventListener("click", () => selectAllVisible(false));
    template.querySelector("button#defaults").addEventListener("click", () => loadDefaults());
    template.querySelector("button#resetOrder").addEventListener("click", () => resetOrder());

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e);
        modalPopup.display("bottom");

        updateEditor();
        modalPopup.getContents().querySelector(`input[type="search"]`).focus();
    }
}
