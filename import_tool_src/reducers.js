
import R from "ramda";
import u from "updeep";

import COLUMN_TYPES from "./column_types";
import {getCellValue} from "./utils";

const initialImportData = {
    rows: [],
    columns: [
        COLUMN_TYPES.first_name,
        COLUMN_TYPES.last_name,
        COLUMN_TYPES.email,
    ],
};

const arrayToObj = R.addIndex(R.reduce)((acc, val, i) => R.assoc(i, {originalValue: val}, acc), {});


function importData_(data=initialImportData, action) {
    switch (action.type) {
        case "SET_IMPORT_DATA":
            return R.assoc("rows", action.data.map(arrayToObj), data);
        case "SET_CUSTOM_VALUE":
            return u.updateIn(["rows", action.rowIndex, action.columnIndex, "customValue"], action.value, data);
        case "ADD_COLUMN":
            return R.evolve({columns: R.append(COLUMN_TYPES[action.columnType])}, data);
        case "CHANGE_COLUMN_TYPE":
            return u.updateIn(["columns", action.columnIndex], COLUMN_TYPES[action.typeId], data);
        default:
            return data;
    }
}

const isFirstName = R.equals(COLUMN_TYPES.first_name);
const isLastName = R.equals(COLUMN_TYPES.last_name);
const isUsername = R.equals(COLUMN_TYPES.username);

const canGenerateUsername = R.allPass(R.map(R.any, [isFirstName, isLastName, isUsername]));


const rowValue = R.curry((index, row) => {
    return getCellValue(row[index]);
});

const generateDefaultUsername = R.curry((usernameIndex, firstNameIndex, lastNameIndex, row) => {
    if (rowValue(usernameIndex, row)) return row;
    var username = rowValue(firstNameIndex, row) + "." + rowValue(lastNameIndex, row);
    return R.over(R.lensProp(usernameIndex), R.merge({customValue: username}), row);
});

const isMissing = R.curry((index, row) => !row[index]);

function injectUsernames(data) {
    if (!canGenerateUsername(data.columns)) return data;

    const usernameIndex = R.findIndex(isUsername, data.columns);
    const isMissingUsername = R.any(isMissing(usernameIndex));

    if (!isMissingUsername(data.rows)) return data;

    const addUsernames = R.map(generateDefaultUsername(
        usernameIndex,
        R.findIndex(isFirstName, data.columns),
        R.findIndex(isLastName, data.columns)
    ));

    return R.evolve({rows: addUsernames}, data);
}

export const importData = R.compose(injectUsernames, importData_);

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


