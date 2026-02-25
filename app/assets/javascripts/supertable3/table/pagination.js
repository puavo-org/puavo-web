// Table pagination

// CAUTION: Most of these functions assume pagination is enabled and barge ahead without checking it.

import { _tr, escapeHTML } from "../../common/utils.js";
import { create, getTemplate } from "../../common/dom.js";
import { setPreviousRow } from "./row_selection.js";
import { buildTable } from "./table_builder.js";
import * as Settings from "./settings.js";

import {
    ColumnType,
    INDEX_EXISTS,
    INDEX_DISPLAYABLE,
    INDEX_FILTERABLE,
    INDEX_SORTABLE,
    ROWS_PER_PAGE_PRESETS,
} from "./constants.js";

export const isTableRowVisible = (paging, rowNum) => (rowNum >= paging.firstRowIndex) && (rowNum < paging.lastRowIndex);

// Calculates which page will be displayed on the next table update
export function calculatePagination(data, paging)
{
    if (data.current === null || data.current === undefined || data.current.length == 0) {
        // No data at all
        paging.numPages = 0;
        paging.currentPage = 0;

        return;
    }

    if (paging.rowsPerPage == -1 || data.current.length <= paging.rowsPerPage) {
        // Only one page
        paging.numPages = 1;
        paging.currentPage = 0;

        return;
    }

    paging.numPages = (paging.rowsPerPage == -1) ? 1 : Math.ceil(data.current.length / paging.rowsPerPage);

    paging.currentPage = Math.min(Math.max(paging.currentPage, 0), paging.numPages - 1);
}

export function updatePageCounter(table)
{
    table.container.querySelector("thead tr#controls section#paging button#page").innerText =
        _tr("status.pagination", {
            current: (table.paging.numPages == 0) ? 1 : table.paging.currentPage + 1,
            total: (table.paging.numPages == 0) ? 1 : table.paging.numPages
        });
}

function onPageDelta(table, delta)
{
    const old = table.paging.currentPage;

    table.paging.currentPage += delta;
    calculatePagination(table.data, table.paging);

    if (table.paging.currentPage == old)
        return;

    updatePageCounter(table);
    enableControls(table);

    setPreviousRow(table, -1);
    buildTable(table);
}

function onJumpToPage(table, e)
{
    // Too long strings can break the select layout
    const MAX_LENGTH = 30;
    const ellipsize = (str) => (str.length > MAX_LENGTH) ? str.substring(0, MAX_LENGTH) + "…" : str;

    const col = table.sorting.column,
          data = table.data,
          paging = table.paging;

    const template = getTemplate("jumpToPagePopup"),
          select = template.querySelector("select");

    // Assume string columns can contain HTML, but numeric columns won't. The values are
    // HTML-escaped when displayed, but that means HTML tags can slip through and it looks
    // really ugly.
    const index = (table.columns.definitions[col].type == ColumnType.STRING) ? INDEX_FILTERABLE : INDEX_DISPLAYABLE;

    // CAUTION: This loop will break if there's only one page. That's why this popup cannot be
    // opened if there's only one page.
    for (let page = 0; page < paging.numPages; page++) {
        const start = page * paging.rowsPerPage;
        const end = Math.min((page + 1) * paging.rowsPerPage, data.current.length);

        let first = data.transformed[data.current[start]],
            last = data.transformed[data.current[end - 1]];

        first = ellipsize(first[col][INDEX_EXISTS] ? first[col][index] : "-");
        last = ellipsize(last[col][INDEX_EXISTS] ? last[col][index] : "-");

        const o = create("option", { label: `${page + 1}: ${escapeHTML(first)} → ${escapeHTML(last)}` });

        o.value = page;
        o.selected = (page == paging.currentPage);

        select.appendChild(o);
    }

    template.querySelector("select").addEventListener("change", e => {
        // Jump to the selected page without closing the popup
        table.paging.currentPage = parseInt(e.target.value, 10);

        updatePageCounter(table);
        enableControls(table);
        setPreviousRow(table, -1);
        buildTable(table);
    });

    if (modalPopup.create()) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(e);
        modalPopup.display("bottom");
        modalPopup.getContents().querySelector("select").focus();
    }
}

export function enableControls(table, state = true)
{
    const ui = table.container.querySelector("thead tr#controls section#paging"),
          paging = table.paging;

    // [selector, condition]
    const items = [
        ["select#rowsPerPage", true],
        ["button#first", paging.currentPage > 0],
        ["button#prev", paging.currentPage > 0],
        ["button#page", paging.numPages > 1],
        ["button#next", paging.currentPage < paging.numPages - 1],
        ["button#last", paging.currentPage < paging.numPages - 1],
    ];

    for (const [selector, enabled] of items)
        ui.querySelector(selector).disabled = !(state && enabled);
}

export function initialize(table, template)
{
    const ui = template.querySelector("section#paging");

    // Fill in the rows per page selector
    const selector = ui.querySelector("select#rowsPerPage");

    for (const [value, label] of ROWS_PER_PAGE_PRESETS) {
        const o = create("option", { label: label });

        o.value = value;
        o.selected = (value == table.paging.rowsPerPage);
        selector.appendChild(o);
    }

    // Setup events
    ui.querySelector("select#rowsPerPage").addEventListener("change", e => {
        table.paging.rowsPerPage = parseInt(e.target.value, 10);
        console.log(`Rows per page changed to ${table.paging.rowsPerPage}`);

        calculatePagination(table.data, table.paging);
        updatePageCounter(table);
        enableControls(table);

        Settings.save(table);
        setPreviousRow(table, -1);
        buildTable(table);
    });

    ui.querySelector("button#first").addEventListener("click", () => onPageDelta(table, -999999));
    ui.querySelector("button#prev").addEventListener("click", () => onPageDelta(table, -1));
    ui.querySelector("button#next").addEventListener("click", () => onPageDelta(table, +1));
    ui.querySelector("button#last").addEventListener("click", () => onPageDelta(table, +999999));
    ui.querySelector("button#page").addEventListener("click", e => onJumpToPage(table, e.target));
}
