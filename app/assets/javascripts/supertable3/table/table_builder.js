// Table builder

import { _tr } from "../../common/utils.js";
import { create } from "../../common/dom.js";

import {
    ColumnFlag,
    ColumnType,
    SortOrder,
    INDEX_DISPLAYABLE,
} from "./constants.js";

function buildHeaders(table, currentColumn, haveActions)
{
    // Unicode arrow characters and empirically determined padding values (their widths
    // vary slightly). These won't work unless the custom puavo-icons font is applied.
    const arrows = {
        unsorted: { asc: "\uf0dc",                 padding: 10 },
        string:   { asc: "\uf15d", desc: "\uf15e", padding: 5 },
        numeric:  { asc: "\uf162", desc: "\uf163", padding: 6 },
    };

    let html = "";

    // The header checkbox column (always empty)
    if (table.settings.enableSelection)
        html += `<th class="width-0"></th>`;

    for (const key of table.columns.current) {
        const def = table.columns.definitions[key];
        const sortable = (def.flags & ColumnFlag.NOT_SORTABLE) ? false : true;
        let classes = [];

        if (!sortable)
            classes.push("cursor-default");
        else {
            classes.push("cursor-pointer");
            classes.push("sortable");
        }

        if (key == currentColumn)
            classes.push("sorted");

        html += `<th title="${key}" ` +
                `data-key="${key}" data-sortable="${sortable ? 1 : 0}" ` +
                `class="${classes.join(' ')}">`;

        // Figure out the cell contents (title + sort direction arrow)
        const isNumeric = (def.type != ColumnType.STRING);

        if (!sortable)
            html += def.title;
        else {
            let symbol, padding;

            if (key == currentColumn) {
                // Currently sorted by this column
                const type = isNumeric ? "numeric" : "string",
                      dir = (table.sorting.dir == SortOrder.ASCENDING) ? "asc" : "desc";

                symbol = arrows[type][dir];
                padding = arrows[type].padding;
            } else {
                symbol = arrows.unsorted.asc;
                padding = arrows.unsorted.padding;
            }

            // Do not put newlines in this HTML! Header drag cell construction will fail otherwise!
            html += `<div><span>${def.title}</span>` +
                    `<span class="arrow" style="padding-left: ${padding}px">` +
                    `${symbol}</span></div>`;
        }

        html += "</th>";
    }

    // The actions column is always the last. It can't be sorted nor dragged.
    if (haveActions)
        html += `<th>${_tr('column_actions')}</th>`;

    const headersFragment = new DocumentFragment();

    headersFragment.appendChild(create("tr", { id: "headers", html: html }));

    // Setup header cell click handlers
    const headings = headersFragment.querySelectorAll("tr#headers th");

    const start = table.settings.enableSelection ? 1 : 0,                // skip the checkbox column
          count = haveActions ? headings.length - 1 : headings.length;  // skip the actions column

    for (let i = start; i < count; i++)
        headings[i].addEventListener("mousedown", event => table.onHeaderMouseDown(event));

    return headersFragment;
}

function buildBody(table, numColumns, currentColumn, haveActions)
{
    const bodyFragment = new DocumentFragment();
    let html = "";

    if (table.data.current.length == 0) {
        // The table is empty
        bodyFragment.appendChild(create("tbody", {
            html: `<tr><td colspan="${numColumns}">(${_tr('empty_table')})</td></tr>`,
            id: "data"
        }));

        return bodyFragment;
    }

    // Make a list of custom CSS classes in the column definitions
    const customCSSColumns = new Map();

    for (const c of table.columns.current) {
        const d = table.columns.definitions[c];

        if (Boolean(d.customCSS))
            customCSSColumns.set(c, Array.isArray(d.customCSS) ? Array.from(d.customCSS) : [d.customCSS]);
    }

    // Calculate start and end indexes for the current page
    let start = 0,
        end = table.data.current.length;

    if (table.settings.enablePagination && table.paging.rowsPerPage != -1) {
        start = table.paging.currentPage * table.paging.rowsPerPage;
        end = Math.min((table.paging.currentPage + 1) * table.paging.rowsPerPage, table.data.current.length);
    }

    // These must always be updated, even when pagination is disabled
    table.paging.firstRowIndex = start;
    table.paging.lastRowIndex = end;

    // Append the data rows
    for (let index = start; index < end; index++) {
        const row = table.data.transformed[table.data.current[index]];
        const rowID = row.id[INDEX_DISPLAYABLE];
        let rowClasses = [];

        if (table.data.successItems.has(rowID))
            rowClasses.push("success");

        if (table.data.failedItems.has(rowID))
            rowClasses.push("fail");

        html += `<tr data-index="${index}" data-puavoid="${rowID}" class=${rowClasses.join(" ")}>`;

        // The checkbox
        if (table.settings.enableSelection) {
            html += `<td class="minimize-width cursor-pointer checkbox">`;
            html += `<input type="checkbox" ${table.data.selectedItems.has(row.id[INDEX_DISPLAYABLE]) ? "checked": ""}></td>`;
        }

        // Data columns
        for (const column of table.columns.current) {
            let classes = [];

            if (column == currentColumn)
                classes.push("sorted");

            if (customCSSColumns.has(column))
                classes = classes.concat(customCSSColumns.get(column));

            if (classes.length > 0)
                html += `<td class=\"${classes.join(' ')}\">`;
            else html += "<td>";

            if (row[column][INDEX_DISPLAYABLE] !== null)
                html += row[column][INDEX_DISPLAYABLE];

            html += "</td>";
        }

        // The actions column
        if (haveActions)
            html += "<td>" + table.user.actions(row) + "</td>";

        html += "</tr>";
    }

    bodyFragment.appendChild(create("tbody", { html: html, id: "data" }));

    // Setup table rows event handling
    const tbody = bodyFragment.querySelector("tbody");

    tbody.addEventListener("mousedown", e => table.onTableBodyMouseDown(e));

    if (table.user.open)
        tbody.addEventListener("mouseup", e => table.onTableBodyMouseUp(e));

    return bodyFragment;
}

export function buildTable(table, updateMask=["headers", "rows"])
{
    const haveActions = !!table.user.actions;

    // How many columns does the table have? Include the checkbox and actions
    // columns, if present.
    let numColumns = table.columns.current.length;

    if (table.settings.enableSelection)
        numColumns++;

    if (haveActions)
        numColumns++;

    // Construct the table parts in memory
    const t0 = performance.now();

    let headersFragment = null,
        bodyFragment = null;

    if (updateMask.includes("headers"))
        headersFragment = buildHeaders(table, table.sorting.column, haveActions);

    if (updateMask.includes("rows"))
        bodyFragment = buildBody(table, numColumns, table.sorting.column, haveActions);

    const t1 = performance.now();

    // DOM update
    table.container.querySelector("table.stTable thead tr#controls th").colSpan = numColumns;

    if (updateMask.includes("headers"))
        table.container.querySelector("table.stTable thead tr#headers").replaceWith(headersFragment);

    if (updateMask.includes("rows"))
        table.getTableBody().replaceWith(bodyFragment);

    const t2 = performance.now();

    // Debug statistics
    console.log(`buildTable(): In-memory table construction: ${t1 - t0} ms`);
    console.log(`buildTable(): DOM replace: ${t2 - t1} ms`);
    console.log(`buildTable(): Total: ${t2 - t0} ms`);
}
