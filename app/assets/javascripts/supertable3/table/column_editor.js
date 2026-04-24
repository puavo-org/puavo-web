// The column editor popup

import { getTemplate } from "../../common/dom.js";
import { _tr } from "../../common/utils.js";
import { saveSettings } from "./settings.js";

// Remember the filter string. Restore it automatically when the editor is reopened.
let currentFilter = "";

const getColumnList = selected => modalPopup.getContents().querySelectorAll("div#columnList input" + (selected ? ":checked" : ""));

function update(table, changed)
{
    const numSelected = getColumnList(true).length,
          saveButton = modalPopup.getContents().querySelector("button#save")

    if (numSelected == 0)
        saveButton.disabled = true;             // the table must have at least one visible column
    else saveButton.disabled = !changed;

    modalPopup.getContents().querySelector("div#columnStats").innerText = _tr("status.column_stats", {
        selected: numSelected,
        total: Object.keys(table.columns.definitions).length
    });
}

function filter(e, table)
{
    if (e)
        currentFilter = e.target.value.trim().toLowerCase();

    for (const c of getColumnList(false)) {
        const p = c.parentNode;

        p.classList.toggle("hidden", currentFilter && table.columns.definitions[p.id].title.toLowerCase().indexOf(currentFilter) == -1);
    }
}

function save(table)
{
    // Make a list of "new" visible columns (ie. what columns are checked in the list)
    let newVisible = new Set();

    for (const c of getColumnList(true))
        newVisible.add(c.parentNode.id);

    // Then hide columns that aren currently visible in the table, but aren't visible
    // anymore, while retaining the column order
    let newColumns = [];

    for (const c of table.columns.current) {
        if (newVisible.has(c)) {
            newColumns.push(c);
            newVisible.delete(c);
        }
    }

    // Then tuck the new columns at the end of the array
    for (const c of newVisible)
        newColumns.push(c);

    update(table, false);
    applyColumns(table, newColumns);
}

function selectVisible(selected, table)
{
    let changed = false;

    for (const c of getColumnList(false)) {
        if (c.checked != selected && !c.parentNode.classList.contains("hidden")) {
            c.checked = selected;
            changed = true;
        }
    }

    if (changed)
        update(table, true);
}

function defaults(table)
{
    const initial = new Set(table.columns.defaults);

    for (const c of getColumnList(false))
        c.checked = initial.has(c.parentNode.id);

    update(table, true);
}

function resetOrder(table)
{
    const current = new Set(table.columns.current);
    let nc = [];

    for (const c of table.columns.order)
        if (current.has(c))
            nc.push(c);

    table.columns.current = nc;
    saveSettings(table);
    table.updateTable();
}

function applyColumns(table, newColumns)
{
    table.columns.current = newColumns;

    // Is the current sorting column still visible? If not, find another column to sort by.
    let sortVisible = false,
        defaultVisible = false;

    for (const col of newColumns) {
        if (table.sorting.column == col)
            sortVisible = true;

        if (table.columns.defaultSorting.column == col)
            defaultVisible = true;
    }

    if (!sortVisible) {
        if (defaultVisible) {
            // The default column is visible, so use it
            table.sorting.column = table.columns.defaultSorting.column;
        } else {
            // Pick the first column we have and use it
            // FIXME: What happens if the first column has ColumnFlag.NOT_SORTABLE flag?
            // FIXME: What happens if there are no sortable columns at all?
            table.sorting.column = newColumns[0];
        }
    }

    saveSettings(table);
    table.updateTable();
}

function open(table, e)
{
    const template = getTemplate("columnsPopup");

    // Sort the columns alphabetically by their localized names
    const columnNames =
        Object.keys(table.columns.definitions)
        .map((key) => [key, table.columns.definitions[key].title])
        .sort((a, b) => { return a[1].localeCompare(b[1]) });

    const current = new Set(table.columns.current);
    let html = "";

    for (const c of columnNames)
        html += `<label id="${c[0]}"><input type="checkbox"${current.has(c[0]) ? " checked": ""}>${c[1]}</label>`;

    template.querySelector("div#columnList").innerHTML = html;

    for (const i of template.querySelectorAll(`div#columnList input`))
        i.addEventListener("click", () => update(table, true));

    template.querySelector(`input[type="search"]`).value = currentFilter;
    template.querySelector(`input[type="search"]`).addEventListener("input", e => filter(e, table));
    template.querySelector("button#save").addEventListener("click", () => save(table));
    template.querySelector("button#selectAll").addEventListener("click", () => selectVisible(true, table));
    template.querySelector("button#deselectAll").addEventListener("click", () => selectVisible(false, table));
    template.querySelector("button#defaults").addEventListener("click", () => defaults(table));
    template.querySelector("button#resetOrder").addEventListener("click", () => resetOrder(table));

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e);
        modalPopup.display("bottom");

        update(table, false);
        filter(null, table);
        modalPopup.getContents().querySelector(`input[type="search"]`).focus();
    }
}

export function setupColumnEditor(table, frag)
{
    const button = frag.querySelector("thead div#top button#columns");

    if (table.settings.enableColumnEditing)
        button.addEventListener("click", e => open(table, e.target));
    else button.remove();
}
