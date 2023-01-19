// Modal popup system

import { create } from "./dom.js";

let
    // invisible overlay covering the page behind the popup, for catching clicks outside of it
    backdrop = null,
    // the popup itself (container)
    contents = null,
    // the element the popup is attached to; positioning is calculated relative to this
    attachedTo = null,
    // positioning type (string), or a user-supplied callback that computes the popup's position
    positioning = null,
    // user-supplied callback that is called when the popup is closed
    closeCallback = null;

export function setupGlobalEvents()
{
    document.body.addEventListener("click", e => {
        // If the user clicked outside of the popup (ie. the backdrop element),
        // close the popup
        if (backdrop && e.target == backdrop)
            closePopup(false);
    });

    // Keep the popup visible if the page is scrolled
    document.addEventListener("scroll", ensurePopupIsVisible);
}

// Creates an empty popup menu/dialog. You have to fill, position and display it.
export function createPopup(closeCallbackFunction = null)
{
    if (backdrop) {
        console.warn("createPopup(): the popup is already open");
        return false;
    }

    backdrop = create("div", { id: "popupBackdrop" });
    contents = create("div", { cls: "popup" });
    backdrop.appendChild(contents);

    // Register a close callback
    if (typeof(closeCallbackFunction) == "function")
        closeCallback = closeCallbackFunction;

    return true;
}

// Closes the active popup menu/dialog
export function closePopup(manual = true)
{
    if (!backdrop)
        return false;

    if (closeCallback)
        closeCallback(manual);

    // This only works once
    closeCallback = null;

    contents.innerHTML = "";
    contents = null;

    // Detach the backdrop from the page, so normal click events work again
    backdrop.remove();
    backdrop = null;

    return true;
}

// Attaches the popup to the specified HTML element and, optionally, sets the popup width.
// These are done in one function because the popup width cannot be (reliably) changed after
// it has been attached. You need to call this before displayPopup()!
export function attachPopup(element, width=null)
{
    if (!backdrop)
        return;

    attachedTo = element;

    // Set the initial position
    const rect = element.getBoundingClientRect();

    let x = rect.left,
        y = rect.top;

    contents.style.display = "block";
    contents.style.position = "absolute";
    contents.style.left = `${Math.round(x)}px`;
    contents.style.top = `${Math.round(y)}px`;

    if (width !== null)
        contents.style.width = `${Math.round(width)}px`;
}

// Actually displays the popup on the screen
export function displayPopup(p = null)
{
    if (!backdrop) {
        console.warn("Can't display the popup if it hasn't been created yet");
        return;
    }

    positioning = p;

    document.body.appendChild(backdrop);
    ensurePopupIsVisible();
}

// Change the positioning callback while the popup is visible; set 'f' to NULL
// to reset to default positioning. Remember to call ensurePopupIsVisible()
// afterwards.
export function setPositioning(p)
{
    positioning = p;
}

// Positions the popup (menu or dialog) so that it's fully visible. Since the attachment
// type and element are known, the popup position can be updated if the page is scrolled.
export function ensurePopupIsVisible()
{
    if (!backdrop)
        return;

    const attachedToRect = attachedTo.getBoundingClientRect();

    let x, y, clamp;

    if (typeof(positioning) == "string") {
        // Built-in
        switch (positioning) {
            case "right":
                x = attachedToRect.right;
                y = attachedToRect.top;
                break;

            case "bottom":
            default:
                x = attachedToRect.left;
                y = attachedToRect.bottom;
                break;
        }

        clamp = true;
    } else if (typeof(positioning) == "function") {
        // Custom positioning
        [x, y, clamp] = positioning(attachedTo, attachedToRect);
    } else {
        // Default positioning
        x = attachedToRect.left;
        y = attachedToRect.top;
        clamp = true;
    }

    if (clamp) {
        // Clamp to view edges
        const popupRect = contents.getBoundingClientRect(),
              pageWidth = document.documentElement.clientWidth,
              pageHeight = document.documentElement.clientHeight,
              popupW = popupRect.right - popupRect.left,
              popupH = popupRect.bottom - popupRect.top;

        if (x < 0)
            x = 0;

        if (x + popupW > pageWidth)
            x = pageWidth - popupW;

        if (y < 0)
            y = 0;

        if (y + popupH > pageHeight)
            y = pageHeight - popupH;
    }

    contents.style.left = `${Math.round(x)}px`;
    contents.style.top = `${Math.round(y)}px`;
}

export function isPopupOpen()
{
    return !!backdrop;
}

// Returns handle to the popup contents, you can then put content in it
export function getPopupContents()
{
    return contents;
}
