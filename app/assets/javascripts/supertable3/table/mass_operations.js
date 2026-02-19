// Some mass operations stuff

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
