// Some mass operations stuff

import {
    _tr,
    escapeHTML
} from "../../common/utils.js";

import {
    ColumnType,
    INDEX_EXISTS,
    INDEX_DISPLAYABLE,
    INDEX_FILTERABLE,
} from "./constants.js";

// Base class for all user-derived mass operations
export class MassOperation {
    constructor(parent, container)
    {
        this.parent = parent;
        this.container = container;
    }

    // Construct the interface, if anything
    buildInterface()
    {
    }

    // Validate the current parameters, if any. Return true to signal that the operation
    // can proceed, false if not.
    canProceed()
    {
        return true;
    }

    // Called just before the mass operation begins. Disable the UI, etc.
    start()
    {
    }

    // Called after the mass operation is done. Re-enable the UI, clean up, etc. here.
    finish()
    {
    }

    // Return the parameters for the operation, if any. Usually flags and things
    // that are in the user interface for this operation. Return null if this
    // operation has no parameters.
    getOperationParameters()
    {
        return null;
    }

    /*
    Takes the incoming item, and "prepares" it for mass the mass operation.
    Must return the following data:

    {
        state: "string here",
        data: ...
    }

    Valid state strings are:
        - "ready": This item is ready to be processed
        - "skip": This item is already in the desired state, and it can be skipped
        - "error": Something went wrong during the preparation, this item will be skipped

    "data" contains the data to be sent over the network for this item. It can be null,
    if the network endpoint doesn't need anything extra. PuavoID is already part of the
    data, you don't have to append it to the data.
    */
    prepareItem(item)
    {
    }
}

// Mass select or deselect all table rows
export function selectAllRows(operation, data, tableRows)
{
    switch (operation) {
        case "select_all":
            data.selectedItems.clear();

            for (const index of data.current)
                data.selectedItems.add(data.transformed[index].id[INDEX_DISPLAYABLE]);

            data.successItems.clear();
            data.failedItems.clear();
            break;

        case "deselect_all":
            data.selectedItems.clear();
            data.successItems.clear();
            data.failedItems.clear();
            break;

        case "invert_selection":
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

        case "deselect_successfull":
            for (const id of data.successItems)
                data.selectedItems.delete(id);

            data.successItems.clear();
            break;

        default:
            console.error(`massSelectAllRows(): invalid operation \"${operation}\"`);
            return;
    }

    // Rebuilding the table is too slow, so modify the checkbox cells directly
    for (const row of tableRows) {
        let cb = row.childNodes[0].childNodes[0];

        switch (operation) {
            case "select_all":
                cb.classList.add("checked");
                row.classList.remove("success", "fail");
                break;

            case "deselect_all":
                cb.classList.remove("checked");
                row.classList.remove("success", "fail");
                break;

            case "invert_selection":
                if (cb.classList.contains("checked"))
                    cb.classList.remove("checked");
                else cb.classList.add("checked");

                row.classList.remove("success", "fail");
                break;

            case "deselect_successfull":
                if (row.classList.contains("success")) {
                    row.classList.remove("success");
                    cb.classList.remove("checked");
                }

                break;

            default:
                break;
        }
    }
}

// Perform row mass selection based on some specific criteria
export function selectSpecificRows(container, selectionState, columns, data, paging, tableRows)
{
    // Source and its type
    const source = container.querySelector("div#source").innerText.trim(),
          type = container.querySelector("select#sourceType").value,
          isNumeric = columns.definitions[type].type != ColumnType.STRING;

    // Parse the input values
    let entries = new Set();

    for (const i of source.split("\n")) {
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
    let found = new Set();

    for (let i = 0, j = data.current.length; i < j; i++) {
        const item = data.transformed[data.current[i]];

        if (!item[type][INDEX_EXISTS])
            continue;

        const field = item[type][INDEX_FILTERABLE];

        if (!entries.has(field))
            continue;

        found.add(field);

        const id = item.id[INDEX_DISPLAYABLE];

        if (selectionState)
            data.selectedItems.add(id);
        else {
            data.selectedItems.delete(id);
            data.successItems.delete(id);
            data.failedItems.delete(id);
        }

        // Directly update (visible) table rows
        if (i >= paging.firstRowIndex && i < paging.lastRowIndex) {
            let row = tableRows[i - paging.firstRowIndex],
                cb = row.childNodes[0].childNodes[0];

            if (selectionState)
                cb.classList.add("checked");
            else cb.classList.remove("checked");

            row.classList.remove("success", "fail");
        }
    }

    // Highlight the items that weren't found
    let html = "";

    for (const e of entries) {
        html += found.has(e) ? "<div>" : `<div class="unmatchedRow">`;
        html += escapeHTML(e);
        html += "</div>";
    }

    container.querySelector("div#source").innerHTML = html;

    container.querySelector("div#massRowSelectStatus").innerText =
        _tr('status.mass_row_status', {
            total: entries.size,
            match: found.size,
            unmatched: entries.size - found.size
        });
}
