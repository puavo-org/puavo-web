// Reorder headers by dragging them with the mouse

import { create, destroy } from "../../common/dom.js";

let
    // Initial drag mouse position (X and Y)
    dragStartMousePos = null,

    // Source column index
    dragStartIndex = null,

    // Destination column index
    dragEndIndex = null,

    // Array of [x, y, w, h] table header cell rectangles. Used to position the drop marker
    // and calculate 'endIndex' above.
    dragCellPositions = null,

    // Delta (distance) from the original event element to the mouse position ([dx, dy])
    dragOffset = null;

export function reset()
{
    dragStartMousePos = null;
    dragStartIndex = null;
    dragEndIndex = null;
    dragCellPositions = null;
    dragOffset = null;
}

export function initialize(event)
{
    reset();

    dragStartMousePos = {
        x: event.clientX,
        y: event.clientY
    };
}

export function getIndexes()
{
    return [dragStartIndex, dragEndIndex];
}

export function begin(event, canSort, hasSelection, hasActions)
{
    // Measure how far the mouse has been moved from the tracking start location.
    // Assume 10 pixels is "far enough".
    const dx = dragStartMousePos.x - event.clientX,
          dy = dragStartMousePos.y - event.clientY;

    if (Math.sqrt(dx * dx + dy * dy) < 10.0) {
        // not yet
        return false;
    }

    // Make a list of header cell positions, so we'll know where to draw the drop markers
    const xOff = window.scrollX,
          yOff = window.scrollY;

    dragStartIndex = null;
    dragEndIndex = null;
    dragCellPositions = [];

    let headers = event.target.parentNode,
        start = 0,
        count = headers.childNodes.length;

    if (hasSelection)   // skip the checkbox column
        start++;

    if (hasActions)     // skip the "Actions" column
        count--;

    for (let i = start; i < count; i++) {
        let n = headers.childNodes[i];

        if (n == event.target) {
            // This is the cell we're dragging
            dragStartIndex = i - start;
        }

        const r = n.getBoundingClientRect();

        dragCellPositions.push({
            x: r.x + xOff,
            y: r.y + yOff,
            w: r.width,
            h: r.height,
        });
    }

    if (dragCellPositions.length == 0) {
        console.error("No table header cells found!");
        dragCellPositions = null;

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

    let dragHeader = create("div", { id: "stDragHeader", cls: "stDragHeader" });

    dragHeader.style.left = `${dragX + window.scrollX}px`;
    dragHeader.style.top = `${dragY + window.scrollY}px`;
    dragHeader.style.width = `${location.width}px`;
    dragHeader.style.height = `${location.height}px`;

    // Copy the title text, without the sorting arrow
    // TODO: Restructure the header cells so that we don't need to look up 'canSort'
    dragHeader.innerText = canSort ? event.target.firstChild.firstChild.innerText : event.target.innerText;

    // Build the drop marker. It shows the position where the header will be placed when
    // the mouse button is released.
    let dropMarker = create("div", { id: "stDropMarker", cls: "stDropMarker" });

    dropMarker.style.height = `${location.height + 10}px`;

    document.body.appendChild(dragHeader);
    document.body.appendChild(dropMarker);

    return true;
}

export function update(event)
{
    if (dragCellPositions === null)
        return;

    const mx = event.clientX + window.scrollX,
          my = event.clientY + window.scrollY,
          mxOff = mx - dragOffset.x;

    // Find the column under the current position
    dragEndIndex = null;

    if (mx < dragCellPositions[0].x)
        dragEndIndex = 0;
    else {
        for (let i = 0; i < dragCellPositions.length; i++)
            if (dragCellPositions[i].x <= mx)
                dragEndIndex = i;
    }

    if (dragEndIndex === null) {
        console.error(`Failed to find the column under the mouse (mouse X=${mx})`);
        return;
    }

    // Position the drop marker
    const slot = dragCellPositions[dragEndIndex];

    let drop = document.querySelector("#stDropMarker");

    if (drop) {
        drop.style.left = `${slot.x - 2}px`;
        drop.style.top = `${slot.y - 5}px`;
    }

    // Position the dragged element. Clamp it against the window edges to prevent
    // unnecessary scrollbars from appearing.
    const windowW = document.body.scrollWidth,      // not the best, but nothing else...
          windowH = document.body.scrollHeight,     // ...works even remotely nicely here
          elementW = dragCellPositions[dragStartIndex].w,
          elementH = dragCellPositions[dragStartIndex].h;

    const dx = Math.max(0, Math.min(mx - dragOffset.x, windowW - elementW)),
          dy = Math.max(0, Math.min(my - dragOffset.y, windowH - elementH));

    const dragHeader = document.querySelector("#stDragHeader");

    if (dragHeader) {
        dragHeader.style.left = `${dx}px`;
        dragHeader.style.top = `${dy}px`;
    }
}

export function end()
{
    destroy(document.querySelector("#stDragHeader"));
    destroy(document.querySelector("#stDropMarker"));
}
