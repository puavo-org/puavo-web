import { _tr } from "../../common/utils.js";

export const MassOperationFlags = {
    HAVE_SETTINGS: 0x01,        // this operation has adjustable settings
    SINGLESHOT: 0x02,           // this operation processes all items in one call, not one-by-one
};

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

    // Called after the mass operation is done. Do clean-ups, etc. here.
    finish()
    {
    }

    // Process a single item (a hash) and return success/failed status
    processItem(item)
    {
        return itemProcessedStatus(true);
    }

    // Process all items at once, and return success/failed status
    processAllItems(items)
    {
        return itemProcessedStatus(true);
    }
}

// Sends a single AJAX POST message
export function doPOST(url, itemData)
{
    // The (table) development environment does not have CSRF tokens, but
    // development and production Puavo environments have. Support both.
    const csrf = document.querySelector("meta[name='csrf-token']");

    return fetch(url, {
        method: "POST",
        mode: "cors",
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "X-CSRF-Token": csrf ? csrf.content : "",
        },
        body: JSON.stringify(itemData)
    }).then(function(response) {
        if (!response.ok)
            throw response;

        return response.json();
    }).catch((error) => {
        console.error(error);

        return {
            success: false,
            message: _tr('network_connection_error'),
        };
    });
}

// Mass operations are basically just a bunch of chained promises that are executed in sequence.
// Use this convenience function to construct and return response Promises.
export function itemProcessedStatus(success, message=null)
{
    // We don't actually reject the Promise itself, we just set the 'success' flag,
    // because it's the return value and the only thing we actually care about.
    return new Promise(function(resolve, reject) {
        resolve({ success: success, message: message });
    });
}
