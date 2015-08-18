
import R from "ramda";
import u from "updeep";

import COLUMN_TYPES from "./column_types";

const initialImportData = {
    rows: [],
    columns: [
        COLUMN_TYPES.first_name,
        COLUMN_TYPES.last_name,
        COLUMN_TYPES.email,
    ],
};

export function importData(data=initialImportData, action) {
    switch (action.type) {
        case "SET_IMPORT_DATA":
            var cleanedRows = action.data.map(row => row.map(cell => ({originalValue: cell.trim()})));
            return u.update({rows: cleanedRows}, data);
        case "SET_CUSTOM_VALUE":
            return u.updateIn(["rows", action.rowIndex, action.columnIndex, "customValue"], action.value, data);
        case "ADD_COLUMN":
            return u.update({columns: R.append(COLUMN_TYPES[action.columnType])}, data);
        case "CHANGE_COLUMN_TYPE":
            return u.updateIn(["columns", action.columnIndex], COLUMN_TYPES[action.typeId], data);
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


// export function columnTypes(columnTypes, action) {
//     if (!columnTypes) {
//         columnTypes =  [
//             COLUMN_TYPES.first_name,
//             COLUMN_TYPES.last_name,
//             COLUMN_TYPES.username,
//         ];
//     }
// 
//     switch (action.type) {
//         case "ADD_COLUMN":
//             return R.append(action.columnType, columnTypes);
//         case "CHANGE_COLUMN_TYPE":
//             return R.update(action.columnIndex, COLUMN_TYPES[action.typeId], columnTypes);
//         default:
//             return columnTypes;
//     }
// 
// }
