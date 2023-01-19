"use strict";

// Modal popup "dialogs" that block access to the page behind them, but they can be closed
// if you click outside of them.

import {
    setupGlobalEvents,
    createPopup,
    closePopup,
    attachPopup,
    displayPopup,
    ensurePopupIsVisible,
    isPopupOpen,
    getPopupContents,
} from "./common/modal_popup.js";

globalThis.modalPopup = {
    setupGlobalEvents: setupGlobalEvents,
    create: createPopup,
    close: closePopup,
    attach: attachPopup,
    display: displayPopup,
    ensureVisible: ensurePopupIsVisible,
    isOpen: isPopupOpen,
    getContents: getPopupContents,
};
