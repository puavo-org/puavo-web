
import R from "ramda";

import COLUMN_TYPES from "./column_types";

export function importData(data=[], action) {
    switch (action.type) {
        case "SET_IMPORT_DATA":
            return action.data.map(row => row.map(cell => ({originalValue: cell.trim()})));
        case "SET_CUSTOM_VALUE":
            return R.assocPath( // XXX
        default:
            return data;
    }
}

export function rowStatus(states={}, action) {
    const setStatus = R.assoc(action.rowId, R.__, states);

    switch (action.type) {
        case "SET_SENDING_ROW":
            return setStatus({status: "sending"});
        case "SET_OK_ROW":
            return setStatus({status: "ok"});
        case "SET_ERROR_ROW":
            return setStatus({status: "error", error: action.error});
        default:
            return states;
    }
}


export function columnTypes(columnTypes, action) {
    if (!columnTypes) {
        return [
            COLUMN_TYPES.first_name,
            COLUMN_TYPES.last_name,
            COLUMN_TYPES.username,
        ];
    }

    switch (action.type) {
        case "ADD_COLUMN":
            return R.append(action.columnType, columnTypes);
        case "CHANGE_COLUMN_TYPE":
            return R.update(action.columnIndex, COLUMN_TYPES[action.typeId], columnTypes);
        default:
            return columnTypes;
    }

}
