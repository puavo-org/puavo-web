// Header cell reordering and table sort order changing

import { create, destroy } from "../../common/dom.js";
import { ColumnFlag, SortOrder } from "./constants.js";

// Internal data. This can be global, because you can't have multiple SuperTables with active header cell tracking
let startMousePos = null,       // Initial drag mouse position (X and Y)
    dragStartIndex = -1,        // Source column index
    dragEndIndex = -1,          // Destination column index
    headerPositions = [],       // Array of [x, y, w, h] table header cell rectangles
    trackingElement = null,     // The header TH element which we're tracking before dragging starts
    dragOffset = null,          // Delta (distance) from the original event element to the mouse position ([dx, dy])
    canSort = false,
    isDragActive = false;       // true if a header cell drag is active

function resetDrag()
{
    startMousePos = null;
    headerPositions = [];
    trackingElement = null;
    isDragActive = false;
}

function removeMarkers()
{
    for (const s of ["#stDragHeader", "#stDropMarker"])
        destroy(document.querySelector(s));
}

function setTableClasses(table, state)
{
    const cl = table.container.querySelector("table.stTable").classList;

    cl.toggle("user-select-none", state);
    cl.toggle("pointer-events-none", state);
    document.body.classList.toggle("cursor-grabbing", state);
}

function positionElement(e, x, y)
{
    if (e) {
        e.style.left = `${x}px`;
        e.style.top = `${y}px`;
    }
}

// Reorders two table columns
function reorderColumns(table)
{
    resetDrag();
    removeMarkers();

    if (dragStartIndex == dragEndIndex)
        return;

    // Reorder the columns array
    table.columns.current.splice(dragEndIndex, 0, table.columns.current.splice(dragStartIndex, 1)[0]);

    // Reorder the table row columns. Perform an in-place swap of the two table columns,
    // it's significantly faster than regenerating the whole table.
    const t0 = performance.now();

    // Skip the checkbox column
    const skip = table.settings.enableSelection ? 1 : 0;

    const from = dragStartIndex + skip,
          to = dragEndIndex + skip;

    let rows = table.container.querySelector("table.stTable").rows,
        n = rows.length,
        row, cell;

    if (table.data.current.length == 0) {
        // The table is empty, so only reorder the header columns. There are two
        // header rows, but only one of the will be processed.
        n = 2;
    }

    while (n--) {
        if (n == 0)         // don't reorder the table controls row
            break;

        row = rows[n];
        cell = row.removeChild(row.cells[from]);
        row.insertBefore(cell, row.cells[to]);
    }

    const t1 = performance.now();
    console.log(`Table column swap: ${t1 - t0} ms`);
}

// Toggles the current sort column and sorting direction
function toggleSorting(table, e)
{
    const key = e.dataset.key,
          sorting = table.sorting;

    if (key == sorting.column) {
        // Same column: invert sort direction
        if (sorting.dir == SortOrder.ASCENDING)
            sorting.dir = SortOrder.DESCENDING;
        else sorting.dir = SortOrder.ASCENDING;
    } else {
        // Different column: change the sorting column
        sorting.column = key;

        // Which way to sort initially?
        sorting.dir = (table.columns.definitions[key].flags & ColumnFlag.DESCENDING_DEFAULT) ?
            SortOrder.DESCENDING : SortOrder.ASCENDING;
    }
}

export function beginMouseTracking(table, e)
{
    resetDrag();

    trackingElement = e.target;
    canSort = (e.target.dataset.sortable == "1");

    startMousePos = {
        x: e.clientX,
        y: e.clientY
    };
}

export function tryBeginDrag(table, event)
{
    if (startMousePos === null)
        return;

    // Measure how far the mouse has been moved from the tracking start location. If it has,
    // start dragging the header column. Assume 10 pixels is "far enough"
    const dx = startMousePos.x - event.clientX,
          dy = startMousePos.y - event.clientY;

    if (Math.sqrt(dx * dx + dy * dy) < 10.0)
        return;

    dragStartIndex = -1;
    dragEndIndex = -1;
    headerPositions = [];

    // Make a list of header cell positions, so we'll know where to draw the drop markers
    const xOff = window.scrollX,
          yOff = window.scrollY;

    const headers = event.target.parentNode;

    let start = 0,
        count = headers.childNodes.length;

    if (table.settings.enableSelection)     // skip the checkbox column
        start++;

    if (table.user.actions !== null)        // skip the "Actions" column
        count--;

    for (let i = start; i < count; i++) {
        const n = headers.childNodes[i];

        if (n == event.target) {
            // This is the cell we're dragging
            dragStartIndex = i - start;
        }

        const r = n.getBoundingClientRect();

        headerPositions.push({
            x: r.x + xOff,
            y: r.y + yOff,
            w: r.width,
            h: r.height,
        });
    }

    if (headerPositions.length == 0) {
        console.error("No table header cells found!");
        startMousePos = null;
        return false;
    }

    // Construct a floating "drag element" that follows the mouse
    const location = event.target.getBoundingClientRect(),
          dragX = Math.round(location.left),
          dragY = Math.round(location.top);

    dragOffset = {
        x: event.clientX - dragX,
        y: event.clientY - dragY
    };

    const dragHeader = create("div", { id: "stDragHeader", cls: "stDragHeader" });

    dragHeader.style.left = `${dragX + window.scrollX}px`;
    dragHeader.style.top = `${dragY + window.scrollY}px`;
    dragHeader.style.width = `${location.width}px`;
    dragHeader.style.height = `${location.height}px`;

    // Copy the title text, without the sorting arrow
    // TODO: Restructure the header cells so that we don't need to look up 'canSort'
    dragHeader.innerText = canSort ? event.target.firstChild.firstChild.innerText : event.target.innerText;

    // Build the drop marker. It shows the position where the header will be placed when
    // the mouse button is released.
    const dropMarker = create("div", { id: "stDropMarker", cls: "stDropMarker" });

    dropMarker.style.height = `${location.height + 10}px`;

    document.body.appendChild(dragHeader);
    document.body.appendChild(dropMarker);

    isDragActive = true;
    setTableClasses(table, true);
    updateDrag(event);
}

export function updateDrag(event)
{
    if (!isDragActive || headerPositions.length == 0)
        return false;

    const mx = event.clientX + window.scrollX,
          my = event.clientY + window.scrollY,
          mxOff = mx - dragOffset.x;

    // Find the *leftmost* column under the current position
    if (mx < headerPositions[0].x)
        dragEndIndex = 0;
    else {
        dragEndIndex = -1;

        for (let i = 0; i < headerPositions.length; i++)
            if (headerPositions[i].x <= mx)
                dragEndIndex = i;
    }

    if (dragEndIndex === -1) {
        console.error(`Failed to find the column under the mouse (mouse X=${mx})`);
        return false;
    }

    // Reposition the dragged element. Clamp it against the window edges to prevent
    // unnecessary scrollbars from appearing.
    const windowW = document.body.scrollWidth,      // not the best, but nothing else...
          windowH = document.body.scrollHeight,     // ...works even remotely nicely here
          elementW = headerPositions[dragStartIndex].w,
          elementH = headerPositions[dragStartIndex].h;

    const x = Math.max(0, Math.min(mx - dragOffset.x, windowW - elementW)),
          y = Math.max(0, Math.min(my - dragOffset.y, windowH - elementH));

    positionElement(document.querySelector("#stDragHeader"), x, y);

    // Reposition the drop marker
    const slot = headerPositions[dragEndIndex];
    positionElement(document.querySelector("#stDropMarker"), slot.x - 2, slot.y - 5);

    return true;
}

export function shouldCancelMouseTracking(e)
{
    return !isDragActive && trackingElement != e.target;
}

export function cancelMouseTracking(table)
{
    setTableClasses(table, false);
    resetDrag();
}

export function endMouseTracking(table, e)
{
    setTableClasses(table, false);

    if (isDragActive) {
        // Reorder the columns
        reorderColumns(table);
    } else {
        // Change table sorting
        resetDrag();

        if (!canSort)
            return;

        toggleSorting(table, e.target);

        table.clearRowSelections();
        table.updateTable();
        table.updateStats();
    }
}
