// Mass operations

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

import { create } from "../../common/dom.js";
import { _tr } from "../../common/utils.js";
import { INDEX_DISPLAYABLE, BATCH_SIZE } from "./constants.js";
import * as Pagination from "./pagination.js";
import { saveSettings } from "./settings.js";
import { onOpenMassRowSelectionPopup } from "./row_selection.js";

export function setupMassTools(table, frag)
{
    const massSpan = frag.querySelector("thead section#massSpan");

    if (!table.settings.enableSelection) {
        massSpan.remove();
        return;
    }

    const showButton = massSpan.querySelector("input#mass");

    showButton.addEventListener("click", e => {
        table.container.querySelector("tr#controls div#massContainer").classList.toggle("hidden", !e.target.checked);
        table.toggleArrow(e.target);
        saveSettings(table);
    });

    const mass = frag.querySelector("thead div#massContainer");

    // List the available mass operations. The combo already contains a "select" placeholder
    // item which is selected by default.
    const selector = mass.querySelector("fieldset div.massControls select.operation");

    for (const m of table.user.massOperations)
        selector.appendChild(create("option", { label: m.title, inputValue: m.id }));

    mass.querySelector("div.massControls > select").addEventListener("change", e => changeOperation(table, e.target));

    const ui = frag.querySelector("thead div#massContainer div.massControls");

    ui.querySelector("button#start").addEventListener("click", () => start(table));
    ui.querySelector("button#stop").addEventListener("click", () => requestStop(table));

    // Expand the tool pane immediately
    if (table.settings.show.includes("mass")) {
        showButton.checked = true;
        frag.querySelector("tr#controls div#massContainer").classList.remove("hidden");
    }

    table.toggleArrow(showButton);
}

export function updateButtons(table)
{
    const ui = table.container.querySelector("thead div#massContainer div.massControls"),
          start = ui.querySelector("button#start"),
          stop = ui.querySelector("button#stop");

    if (start && stop) {
        start.disabled = table.processing || table.data.selectedItems.size == 0 || table.massOperation.definition === null;
        stop.disabled = !table.processing;
    }
}

// Called when the selected mass operation changes
export function changeOperation(table, e)
{
    const fieldset = table.container.querySelector("table.stTable thead div#massContainer fieldset#settings"),
          container = fieldset.querySelector("div#ui");

    const index = e.selectedIndex - 1;

    table.massOperation.definition = table.user.massOperations[index];
    table.massOperation.handler = new table.massOperation.definition.cls(this, container);

    // Hide/swap the UI
    container.innerText = "";

    if (table.massOperation.definition.haveSettings) {
        table.massOperation.handler.buildInterface();
        fieldset.classList.remove("hidden");
    } else fieldset.classList.add("hidden");

    const ui = table.container.querySelector("thead div#massContainer div.massControls");

    ui.querySelector("progress").classList.add("hidden");
    ui.querySelector("span.counter").classList.add("hidden");

    updateButtons(table);
    table.updateStats();
}

export function start(table)
{
    if (table.isBusy())
        return;

    if (!table.massOperation.handler.canProceed())
        return;

    if (!window.confirm(_tr('are_you_sure')))
        return;

    // Reset previous row states of visible rows
    for (const row of table.getTableRows()) {
        row.classList.remove("success", "fail", "processing");
        row.title = "";
    }

    table.data.successItems.clear();
    table.data.failedItems.clear();

    table.massOperation.rows = [];
    table.massOperation.pos = 0;
    table.massOperation.prevPos = 0;

    // Make a list of all selected rows
    for (let rowNum = 0; rowNum < table.data.current.length; rowNum++) {
        const id = table.data.transformed[table.data.current[rowNum]].id[INDEX_DISPLAYABLE];

        if (table.data.selectedItems.has(id)) {
            table.massOperation.rows.push({
                index: rowNum,
                id: id,
            });
        }
    }

    //console.log(table.data.selectedItems);

    table.massOperation.handler.start();
    table.massOperation.singleShot = table.massOperation.definition.singleShot || false;
    table.massOperation.parameters = table.massOperation.handler.getOperationParameters() || {};

    // Initiate the operation
    table.processing = true;
    table.stopRequested = false;

    table.enableUI(false);
    table.enableTable(false);
    updateButtons(table);

    const ui = table.container.querySelector("thead div#massContainer div.massControls"),
          progress = ui.querySelector("progress"),
          counter = ui.querySelector("span.counter");

    progress.setAttribute("max", table.massOperation.rows.length);
    progress.setAttribute("value", 0);
    progress.classList.remove("hidden");
    counter.innerHTML = _tr("status.mass_progress", { count: 0, total: table.massOperation.rows.length, success: 0, fail: 0 });
    counter.classList.remove("hidden");

    if (table.massOperation.definition.singleShot) {
        // Process all rows at once
        table.processBatch(table.prepareNextBatch(table.data.selectedItems.size));
    } else {
        // Process in smaller batches
        table.processBatch(table.prepareNextBatch(BATCH_SIZE));
    }
}

export function finish(table)
{
    table.massOperation.handler.finish();
    table.processing = false;
    table.enableUI(true);
    table.enableTable(true);
    updateButtons(table);

    // Leave the progress bar and the counter visible. They're only hidden until
    // the first time a mass operation is executed.
}

export function requestStop(table)
{
    // The operation will stop after the current batch has been processed
    // (no way to cancel the batch that's currently in-flight)
    table.stopRequested = true;
    console.log("Stopping the mass operation after the current batch finishes");
}

export function updateProgress(table)
{
    const ui = table.container.querySelector("thead div#massContainer div.massControls");

    ui.querySelector("progress").setAttribute("value", table.massOperation.pos);

    ui.querySelector("span.counter").innerHTML = _tr("status.mass_progress", {
        count: table.massOperation.pos,
        total: table.massOperation.rows.length,
        success: table.data.successItems.size,
        fail: table.data.failedItems.size
    });
}

export function prepareBatch(table, batchSize)
{
    const end = Math.min(table.massOperation.rows.length, table.massOperation.pos + batchSize);

    table.massOperation.prevPos = table.massOperation.pos;

    let batch = [];

    // Go through the next N rows and prepare them
    const tableRows = table.getTableRows();

    for (; table.massOperation.pos < end; table.massOperation.pos++) {
        const item = table.massOperation.rows[table.massOperation.pos];

        const tRow = Pagination.isTableRowVisible(table.paging, item.index) ?
            tableRows[item.index - table.paging.firstRowIndex] :
            null;

        console.log(`Processing item ${table.massOperation.pos + 1}/${table.massOperation.rows.length}: ${item.id} (row ${item.index})`);

        // Returns a { state, data } object
        const result = table.massOperation.handler.prepareItem(table.data.transformed[table.data.current[item.index]]);

        // Immediately update the table if the results are already known
        switch (result.state) {
            case "ready":
                // This item can be processed
                if (result.data !== undefined)
                    table.massOperation.rows[table.massOperation.pos].data = result.data;

                batch.push(table.massOperation.rows[table.massOperation.pos]);
                tRow?.classList.add("processing");
                break;

            case "skip":
                // This item is already in the desired state, it can be skipped
                tRow?.classList.add("success");
                table.data.successItems.add(item.id);
                break;

            case "error":
                // This item could not be prepared for processing, skip it
                tRow?.classList.add("fail");
                table.data.failedItems.add(item.id);

                if (tRow && result.message) {
                    // Instantly set the error message
                    tRow.title = result.message;
                }

                break;

            default:
                console.error(result);
                window.alert(`Unknown prepare status: "${result.state}". This is a fatal error, stopping here. See the console for details, then contact support.`);
                return null;
        }
    }

    return batch;
}

export function updateTableColors(table, e)
{
    const tableRows = table.getTableRows();

    for (const row of e.data.result) {
        if (row.status)
            table.data.successItems.add(row.id);
        else table.data.failedItems.add(row.id);

        // If this row is visible, update its status
        if (Pagination.isTableRowVisible(table.paging, row.index)) {
            const tRow = tableRows[row.index - table.paging.firstRowIndex];

            tRow.classList.remove("processing");

            if (row.status)
                tRow.classList.add("success");
            else {
                tRow.classList.add("fail");

                if (row.message)
                    tRow.title = row.message;
            }
        }
    }
}

export function flagNetworkError(table, e)
{
    const tableRows = table.getTableRows();

    for (let i = table.massOperation.prevPos; i < table.massOperation.pos; i++) {
        const item = table.massOperation.rows[i];
        const index = item.index;
        const tableRow = Pagination.isTableRowVisible(table.paging, index) ? tableRows[index - table.paging.firstRowIndex] : null;

        if (tableRow)
            tableRow.classList.remove("processing");

        if (table.data.successItems.has(item.id) || table.data.failedItems.has(item.id)) {
            // It's possible that some items were skipped in the preparation state,
            // and they're not affected by this network/server error. They were
            // not sent to the server, but because we mark all previous BATCH_SIZE
            // rows as "failed", they must be skipped again here.
            continue;
        }

        table.data.failedItems.add(item.id);

        if (tableRow) {
            tableRow.classList.add("fail");
            tableRow.title = e.data.error;
        }
    }
}
