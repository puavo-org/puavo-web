// Mass table rows selection (all, none, invert, specific, etc.)

import { create, getTemplate } from "../../common/dom.js";
import { _tr, escapeHTML } from "../../common/utils.js";

import {
    ColumnType,
    INDEX_EXISTS,
    INDEX_DISPLAYABLE,
    INDEX_FILTERABLE,
    INDEX_SORTABLE
} from "./constants.js";

// Updates the internal item PuavoID sets to match the desired selection mode
function updateItemIDSets(data, operation)
{
    switch (operation) {
        case "all":
            data.selectedItems.clear();

            for (const index of data.current)
                data.selectedItems.add(data.transformed[index].id[INDEX_DISPLAYABLE]);

            data.successItems.clear();
            data.failedItems.clear();
            break;

        case "none":
            data.selectedItems.clear();
            data.successItems.clear();
            data.failedItems.clear();
            break;

        case "invert":
            let newState = new Set();

            for (const index of data.current) {
                const id = data.transformed[index].id[INDEX_DISPLAYABLE];

                if (!data.selectedItems.has(id))
                    newState.add(id);
            }

            data.selectedItems = newState;
            data.successItems.clear();
            data.failedItems.clear();
            break;

        // Deselect rows that were successfully processed in the last mass operation.
        // This way you can re-run the operation on the rows that failed.
        case "successfull":
            for (const id of data.successItems)
                data.selectedItems.delete(id);

            data.successItems.clear();
            break;

        default:
            window.alert(`updateItemIDSets(): invalid operation \"${operation}\"`);
            return;
    }
}

// Actually sets and removes the checkmarks in the table to match the current selection set.
// This only updates the rows that are currently visible.
function updateTableCheckboxes(table)
{
    const data = table.data;

    for (const row of table.getTableRows())
        row.childNodes[0].childNodes[0].checked =
            data.selectedItems.has(parseInt(row.dataset.puavoid, 10));
}

// Mass select or deselect all table rows
function selectAllRows(table, operation)
{
    if (table.updating || table.processing)
        return;

    updateItemIDSets(table.data, operation);
    updateTableCheckboxes(table);

    table.clearPreviousRow();
    table.doneAtLeastOneOperation = false;
    table.updateStats();
    table.updateMassButtons();
}

// Selects (or deselects) specific rows that match one or more search terms
function selectSpecificRows(table, state)
{
    if (table.updating || table.processing)
        return;

    const container = modalPopup.getContents().querySelector("fieldset#massSelects"),
          source = container.querySelector("div#source"),
          type = container.querySelector("select#sourceType").value,
          isNumeric = table.columns.definitions[type].type != ColumnType.STRING;

    // Parse the input values
    const entries = new Set();

    for (const i of source.innerText.split("\n")) {
        let s = i.trim();

        if (s.length == 0 || s[0] == "#")
            continue;

        if (isNumeric) {
            s = parseInt(s, 10);

            if (isNaN(s))
                continue;
        }

        entries.add(s);
    }

    // Select/deselect the rows
    const data = table.data;
    const found = new Set();

    for (let i = 0, j = data.current.length; i < j; i++) {
        const item = data.transformed[data.current[i]];

        if (!item[type][INDEX_EXISTS])
            continue;

        const field = item[type][INDEX_FILTERABLE];

        if (!entries.has(field))
            continue;

        found.add(field);

        const id = item.id[INDEX_DISPLAYABLE];

        if (state) {
            // Select this row
            data.selectedItems.add(id);
        } else {
            // Deselect this row
            data.selectedItems.delete(id);
            data.successItems.delete(id);
            data.failedItems.delete(id);
        }
    }

    updateTableCheckboxes(table);

    // Highlight the items that weren't found
    source.innerHTML = [...entries].map(e => (found.has(e) ? "<div>" : `<div class="unmatchedRow">`) + escapeHTML(e) + "</div>").join("");

    // Update statistics
    container.querySelector("div#massRowSelectStatus").innerText =
        _tr('status.mass_row_status', {
            total: entries.size,
            match: found.size,
            unmatched: entries.size - found.size
        });

    // doneAtLeastOneOperation is not set to false on purpose
    table.clearPreviousRow();
    table.updateStats();
    table.updateMassButtons();
}

// Remember the previous contents
let previousEntries = null,
    previousType = null,
    previousStats = null;

export function onOpenMassRowSelectionPopup(table, button)
{
    const template = getTemplate("rowSelection");

    for (const b of ["all", "none", "invert", "successfull"])
        template.querySelector(`button#${b}`).addEventListener("click", () => selectAllRows(table, b));

    if (table.user.massSelects.length > 0) {
        // Enable mass row selections. List available types in the selector, and restore previous contents;
        const source = template.querySelector("div#source"),
              selector = template.querySelector("select#sourceType"),
              stats = template.querySelector("div#massRowSelectStatus");

        source.innerHTML = previousEntries;
        stats.innerText = previousStats;

        for (const [id, label] of table.user.massSelects) {
            const o = create("option", { label: label });

            o.value = id;
            o.selected = (id === previousType);
            selector.appendChild(o);
        }

        source.addEventListener("paste", e => {
            // Strip HTML from the pasted text (plain text only!). The thing is, the "text box" is a
            // contentEdit-enabled DIV, so it accepts HTML. If you paste data from, say, LibreOffice
            // Calc, the spreadsheet font gets embedded in it and it can actually screw up the page's
            // layout completely (I saw that happening)! That's not acceptable, so this little function
            // will hopefully remove all HTML from whatever's being pasted and leave only plain text.
            // See https://developer.mozilla.org/en-US/docs/Web/API/ClipboardEvent/clipboardData
            e.preventDefault();
            e.target.innerText = e.clipboardData.getData("text/plain");
        });

        template.querySelector("button#massRowSelect").addEventListener("click", () => selectSpecificRows(table, true));
        template.querySelector("button#massRowDeselect").addEventListener("click", () => selectSpecificRows(table, false));
    } else {
        // No row mass selections available. Manually fix the layout.
        template.querySelector("fieldset#massSelects").remove();
        template.querySelector("fieldset").classList.remove("width-50p");
    }

    if (modalPopup.create(() => {
        // Remember the previous contents of the mass row selection controls, if present
        const popup = modalPopup.getContents().querySelector("div.popupRows"),
              source = popup.querySelector("div#source"),
              selector = popup.querySelector("select#sourceType");

        if (source && selector) {
            previousEntries = source.innerHTML;
            previousType = selector.value;
            previousStats = popup.querySelector("div#massRowSelectStatus").innerText;
        }
    })) {
        modalPopup.getContents().appendChild(template);
        modalPopup.attach(button, table.user.massSelects.length > 0 ? 800 : 200);   // completely arbitrary widths
        modalPopup.display("bottom");
    }
}
